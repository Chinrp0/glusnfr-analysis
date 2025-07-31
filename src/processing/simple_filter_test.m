function simple_filter_test()
    % SIMPLE_FILTER_TEST - Compare original vs enhanced filtering
    %
    % This script compares your current filtering method against the enhanced
    % filter and shows which ROIs the enhanced filter removes (potential false positives).
    
    fprintf('\n=== Simple Filter Comparison Test ===\n');
    fprintf('Comparing original threshold vs enhanced filtering\n\n');
    
    try
        % Load modules
        addpath(genpath(pwd));
        modules = module_loader();
        filter_system = enhanced_filtering_system();
        fprintf('✓ Modules loaded\n');
        
    catch ME
        fprintf('✗ Error loading modules: %s\n', ME.message);
        return;
    end
    
    % Select test file
    fprintf('\nStep 1: Select Excel file\n');
    [filename, pathname] = uigetfile('*.xlsx', 'Select Excel file for comparison');
    
    if isequal(filename, 0)
        fprintf('No file selected, exiting...\n');
        return;
    end
    
    filepath = fullfile(pathname, filename);
    fprintf('Selected: %s\n', filename);
    
    % Read and process data
    fprintf('\nStep 2: Processing data...\n');
    try
        [rawData, headers, success] = modules.io.readExcelFile(filepath, true);
        if ~success || isempty(rawData)
            error('Failed to read file');
        end
        
        % Extract data
        traces = single(rawData(:, 2:end));
        validHeaders = headers(2:end);
        [n_frames, n_rois] = size(traces);
        
        fprintf('✓ Read %d frames × %d ROIs\n', n_frames, n_rois);
        
        % Calculate dF/F
        [dF_values, thresholds, gpuUsed] = modules.calc.calculate(traces, true, struct('memory', 4));
        fprintf('✓ Calculated dF/F (GPU: %s)\n', string(gpuUsed));
        
    catch ME
        fprintf('✗ Error processing file: %s\n', ME.message);
        return;
    end
    
    % Determine experiment type
    experimentType = '1AP';
    if contains(filename, 'PPF')
        experimentType = 'PPF';
        ppfMatch = regexp(filename, 'PPF-(\d+)ms', 'tokens');
        if ~isempty(ppfMatch)
            ppfTimepoint = str2double(ppfMatch{1}{1});
        else
            ppfTimepoint = 30;
        end
    else
        ppfTimepoint = [];
    end
    
    fprintf('✓ Detected: %s experiment\n', experimentType);
    
    % Run both filtering methods
    fprintf('\nStep 3: Running filter comparison...\n');
    
    % Original filtering
    fprintf('  Running original filtering...\n');
    filter_module = roi_filter();
    [originalFiltered, originalHeaders, ~, originalStats] = ...
        filter_module.filterROIs(dF_values, validHeaders, thresholds, experimentType, ppfTimepoint);
    
    % Enhanced filtering  
    fprintf('  Running enhanced filtering...\n');
    [enhancedFiltered, enhancedHeaders, ~, enhancedStats] = ...
        filter_system.filterROIs(dF_values, validHeaders, thresholds, experimentType, ...
        'PPFTimepoint', ppfTimepoint, 'Verbose', false);
    
    % Extract ROI numbers for comparison
    originalROIs = extractROINumbers(originalHeaders);
    enhancedROIs = extractROINumbers(enhancedHeaders);
    
    % Find differences
    bothPassed = intersect(originalROIs, enhancedROIs);
    originalOnly = setdiff(originalROIs, enhancedROIs);  % These are the ones enhanced filter removes
    enhancedOnly = setdiff(enhancedROIs, originalROIs);  % These are added by enhanced (unlikely)
    
    % Display results
    fprintf('\n=== COMPARISON RESULTS ===\n');
    fprintf('Original filtering:  %d ROIs passed\n', length(originalROIs));
    fprintf('Enhanced filtering:  %d ROIs passed\n', length(enhancedROIs));
    fprintf('Both methods:        %d ROIs\n', length(bothPassed));
    fprintf('Net change:          %+d ROIs\n', length(enhancedROIs) - length(originalROIs));
    
    % This is what you're most interested in:
    if ~isempty(originalOnly)
        fprintf('\n=== ROIs REMOVED by Enhanced Filter ===\n');
        fprintf('These %d ROIs passed your original threshold but failed enhanced filtering:\n', length(originalOnly));
        fprintf('(These are potential FALSE POSITIVES caught by enhanced filtering)\n\n');
        
        for i = 1:length(originalOnly)
            fprintf('  ROI %d\n', originalOnly(i));
        end
        
        % Show a few example traces
        fprintf('\nShowing example traces of removed ROIs...\n');
        plotRemovedROIs(dF_values, validHeaders, originalOnly(1:min(4, length(originalOnly))), thresholds);
        
    else
        fprintf('\n✓ Enhanced filter did not remove any additional ROIs\n');
        fprintf('  (Both methods gave identical results)\n');
    end
    
    % Unlikely, but check if enhanced added any
    if ~isempty(enhancedOnly)
        fprintf('\n=== ROIs ADDED by Enhanced Filter ===\n');
        fprintf('These %d ROIs failed original but passed enhanced filtering:\n', length(enhancedOnly));
        for i = 1:length(enhancedOnly)
            fprintf('  ROI %d\n', enhancedOnly(i));
        end
    end
    
    % Summary recommendation
    fprintf('\n=== RECOMMENDATION ===\n');
    if length(originalOnly) > length(originalROIs) * 0.1  % More than 10% removed
        fprintf('🟢 Enhanced filtering removes %.1f%% of your original ROIs\n', length(originalOnly)/length(originalROIs)*100);
        fprintf('   This suggests it could help reduce false positives\n');
        fprintf('   Review the removed ROIs above to see if they look like artifacts\n');
    elseif length(originalOnly) > 0
        fprintf('🟡 Enhanced filtering removes %.1f%% of your original ROIs\n', length(originalOnly)/length(originalROIs)*100);
        fprintf('   Modest improvement in selectivity\n');
    else
        fprintf('🔵 Both methods give identical results\n');
        fprintf('   Your current filtering is already quite good\n');
    end
    
    fprintf('\nTest complete!\n');
end

function roiNumbers = extractROINumbers(headers)
    % Extract ROI numbers from headers
    
    roiNumbers = [];
    for i = 1:length(headers)
        matches = regexp(headers{i}, 'ROI\s*(\d+)', 'tokens', 'ignorecase');
        if ~isempty(matches)
            roiNumbers(end+1) = str2double(matches{1}{1});
        end
    end
end

function plotRemovedROIs(dF_values, headers, removedROIs, thresholds)
    % Plot traces of ROIs that were removed by enhanced filtering
    
    cfg = GluSnFRConfig();
    time_ms = (0:size(dF_values, 1)-1) * cfg.timing.MS_PER_FRAME;
    stimTime = cfg.timing.STIMULUS_TIME_MS;
    
    figure('Position', [100, 100, 1200, 800], 'Name', 'ROIs Removed by Enhanced Filter');
    
    numToPlot = min(4, length(removedROIs));
    
    for i = 1:numToPlot
        roiNum = removedROIs(i);
        
        % Find ROI index
        roiIdx = [];
        for j = 1:length(headers)
            if contains(headers{j}, sprintf('ROI %d', roiNum)) || contains(headers{j}, sprintf('ROI%d', roiNum))
                roiIdx = j;
                break;
            end
        end
        
        if isempty(roiIdx)
            continue;
        end
        
        subplot(2, 2, i);
        
        % Plot trace
        plot(time_ms, dF_values(:, roiIdx), 'b-', 'LineWidth', 1.5);
        hold on;
        
        % Add threshold line
        if roiIdx <= length(thresholds)
            plot([0, max(time_ms)], [thresholds(roiIdx), thresholds(roiIdx)], 'r--', 'LineWidth', 1, 'DisplayName', 'Threshold');
        end
        
        % Add stimulus line
        plot([stimTime, stimTime], ylim, 'g--', 'LineWidth', 1, 'DisplayName', 'Stimulus');
        
        title(sprintf('ROI %d (Removed by Enhanced)', roiNum), 'FontWeight', 'bold');
        xlabel('Time (ms)');
        ylabel('ΔF/F');
        grid on;
        
        % Calculate and show peak response
        stimFrame = cfg.timing.STIMULUS_FRAME;
        postStimWindow = stimFrame + (1:30);  % 150ms window
        postStimWindow = postStimWindow(postStimWindow <= size(dF_values, 1));
        
        if ~isempty(postStimWindow)
            [peakVal, ~] = max(dF_values(postStimWindow, roiIdx));
            text(0.05, 0.95, sprintf('Peak: %.4f', peakVal), 'Units', 'normalized', ...
                 'VerticalAlignment', 'top', 'BackgroundColor', 'white');
        end
        
        legend('Location', 'best');
    end
    
    sgtitle('ROIs Removed by Enhanced Filter (Potential False Positives)', 'FontSize', 14, 'FontWeight', 'bold');
end