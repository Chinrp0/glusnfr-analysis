function test_simple_filter()
    % TEST_SIMPLE_FILTER - Test simplified enhanced filtering
    %
    % This tests the new 3-criteria enhanced filter:
    % 1. SNR >= 3.0 (signal vs noise)
    % 2. Peak timing 5-100ms after stimulus
    % 3. Peak prominence >= 2% above baseline
    % ROI passes if it meets 2 out of 3 criteria
    
    fprintf('\n=== Simple Enhanced Filter Test ===\n');
    fprintf('Testing 3-criteria filter to remove noise like ROI 19\n');
    fprintf('while keeping real signals like ROI 29 & 32\n\n');
    
    try
        % Load modules
        addpath(genpath(pwd));
        modules = module_loader();
        fprintf('✓ Modules loaded\n');
        
    catch ME
        fprintf('✗ Error loading modules: %s\n', ME.message);
        return;
    end
    
    % Select test file
    fprintf('Step 1: Select Excel file\n');
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
    fprintf('\nStep 3: Comparing filtering methods...\n');
    
    % Method 1: Original filtering (disable enhanced first)
    cfg = modules.config;
    originalEnhanced = cfg.filtering.ENABLE_ENHANCED_FILTERING;
    cfg.filtering.ENABLE_ENHANCED_FILTERING = false;
    
    [originalData, originalHeaders, originalThresh, originalStats] = ...
        modules.filter.filterROIs(dF_values, validHeaders, thresholds, experimentType, ppfTimepoint);
    
    % Method 2: Enhanced filtering (enable enhanced)
    cfg.filtering.ENABLE_ENHANCED_FILTERING = true;
    
    [enhancedData, enhancedHeaders, enhancedThresh, enhancedStats] = ...
        modules.filter.filterROIs(dF_values, validHeaders, thresholds, experimentType, ppfTimepoint);
    
    % Restore original setting
    cfg.filtering.ENABLE_ENHANCED_FILTERING = originalEnhanced;
    
    % Extract ROI numbers for comparison
    originalROIs = modules.utils.extractROINumbers(originalHeaders);
    enhancedROIs = modules.utils.extractROINumbers(enhancedHeaders);
    
    % Display results
    fprintf('\n=== COMPARISON RESULTS ===\n');
    fprintf('Original filtering:  %d ROIs passed\n', length(originalROIs));
    fprintf('Enhanced filtering:  %d ROIs passed\n', length(enhancedROIs));
    
    % Find differences
    if ~isempty(originalROIs) && ~isempty(enhancedROIs)
        bothPassed = intersect(originalROIs, enhancedROIs);
        removedByEnhanced = setdiff(originalROIs, enhancedROIs);
        addedByEnhanced = setdiff(enhancedROIs, originalROIs);
        
        fprintf('Both methods:        %d ROIs\n', length(bothPassed));
        fprintf('Net change:          %+d ROIs\n', length(enhancedROIs) - length(originalROIs));
        
        % Show ROIs removed by enhanced filter
        if ~isempty(removedByEnhanced)
            fprintf('\n=== ROIs REMOVED by Enhanced Filter ===\n');
            fprintf('These %d ROIs were filtered out (potential noise):\n', length(removedByEnhanced));
            
            for i = 1:length(removedByEnhanced)
                fprintf('  ROI %d\n', removedByEnhanced(i));
            end
            
            % Check specific ROIs mentioned in the issue
            if ismember(19, removedByEnhanced)
                fprintf('✓ ROI 19 (noisy) was REMOVED - GOOD!\n');
            else
                fprintf('⚠ ROI 19 (noisy) was NOT removed\n');
            end
            
            if ismember(29, removedByEnhanced)
                fprintf('⚠ ROI 29 (real signal) was REMOVED - BAD!\n');
            end
            
            if ismember(32, removedByEnhanced)
                fprintf('⚠ ROI 32 (real signal) was REMOVED - BAD!\n');
            end
            
        else
            fprintf('\n✓ Enhanced filter did not remove any ROIs\n');
        end
        
        % Show ROIs added (unlikely with this filter)
        if ~isempty(addedByEnhanced)
            fprintf('\n=== ROIs ADDED by Enhanced Filter ===\n');
            for i = 1:length(addedByEnhanced)
                fprintf('  ROI %d\n', addedByEnhanced(i));
            end
        end
        
        % Show detailed criteria results
        if isfield(enhancedStats, 'criteria_stats')
            cs = enhancedStats.criteria_stats;
            fprintf('\n=== Enhanced Filter Criteria Results ===\n');
            fprintf('SNR >= 3.0:               %d/%d ROIs passed\n', cs.snr_passed, enhancedStats.basic_passed);
            fprintf('Timing 5-100ms:           %d/%d ROIs passed\n', cs.timing_passed, enhancedStats.basic_passed);
            fprintf('Prominence >= 2%%:         %d/%d ROIs passed\n', cs.prominence_passed, enhancedStats.basic_passed);
            fprintf('Final (2/3 criteria):     %d/%d ROIs passed\n', enhancedStats.enhanced_passed, enhancedStats.basic_passed);
        end
        
        % Plot some example ROIs
        if ~isempty(removedByEnhanced)
            fprintf('\nStep 4: Plotting removed ROIs...\n');
            plotRemovedROIs(dF_values, validHeaders, removedByEnhanced, thresholds);
        end
        
    else
        fprintf('ERROR: Could not extract ROI numbers for comparison\n');
    end
    
    fprintf('\n=== RECOMMENDATION ===\n');
    
    netChange = length(enhancedROIs) - length(originalROIs);
    
    if netChange < -5
        fprintf('🟢 ENHANCED FILTER WORKING WELL\n');
        fprintf('   Removed %d noisy ROIs while keeping real signals\n', -netChange);
        fprintf('   Check the plots above to verify correct filtering\n');
    elseif netChange < 0
        fprintf('🟡 ENHANCED FILTER MODEST IMPROVEMENT\n');
        fprintf('   Removed %d ROIs - verify these are noise not signals\n', -netChange);
    else
        fprintf('🔵 ENHANCED FILTER MINIMAL CHANGE\n');
        fprintf('   Your original filtering may already be well-tuned\n');
    end
    
    fprintf('\nTo enable enhanced filtering permanently:\n');
    fprintf('1. In your GluSnFRConfig.m, set:\n');
    fprintf('   config.filtering.ENABLE_ENHANCED_FILTERING = true;\n');
    fprintf('2. Run your normal pipeline - it will use enhanced filtering\n');
    
    fprintf('\nTest complete!\n');
end

function plotRemovedROIs(dF_values, headers, removedROIs, thresholds)
    % Plot traces of ROIs removed by enhanced filtering
    
    if isempty(removedROIs)
        return;
    end
    
    numToPlot = min(9, length(removedROIs));
    cfg = GluSnFRConfig();
    time_ms = (0:size(dF_values, 1)-1) * cfg.timing.MS_PER_FRAME;
    stimTime = cfg.timing.STIMULUS_TIME_MS;
    
    figure('Position', [100, 100, 1200, 800], 'Name', 'ROIs Removed by Enhanced Filter');
    
    plotCount = 0;
    for i = 1:length(removedROIs)
        roiNum = removedROIs(i);
        
        % Find this ROI in headers
        roiIdx = findROIIndex(headers, roiNum);
        if isempty(roiIdx)
            continue;
        end
        
        plotCount = plotCount + 1;
        if plotCount > numToPlot
            break;
        end
        
        subplot(3, 3, plotCount);
        
        % Plot trace
        plot(time_ms, dF_values(:, roiIdx), 'k-', 'LineWidth', 1.5);
        hold on;
        
        % Add stimulus line
        plot([stimTime, stimTime], ylim, 'g--', 'LineWidth', 1);
        
        % Add threshold if available
        if roiIdx <= length(thresholds)
            plot([0, max(time_ms)], [thresholds(roiIdx), thresholds(roiIdx)], 'r--', 'LineWidth', 1);
        end
        
        % Calculate and show criteria
        stimFrame = cfg.timing.STIMULUS_FRAME;
        baselineWindow = 1:min(stimFrame-10, 200);
        postStimWindow = stimFrame + (1:30);
        postStimWindow = postStimWindow(postStimWindow <= size(dF_values, 1));
        
        if ~isempty(postStimWindow)
            baselineNoise = std(dF_values(baselineWindow, roiIdx));
            peakValue = max(dF_values(postStimWindow, roiIdx));
            snr = peakValue / baselineNoise;
            
            [~, peakIdx] = max(dF_values(postStimWindow, roiIdx));
            peakFrame = postStimWindow(peakIdx);
            timeToPeak = (peakFrame - stimFrame) * cfg.timing.MS_PER_FRAME;
            
            baseline_mean = mean(dF_values(baselineWindow, roiIdx));
            prominence = peakValue - baseline_mean;
            
            % Show criteria results
            snr_pass = snr >= 3.0;
            timing_pass = timeToPeak >= 5 && timeToPeak <= 100;
            prominence_pass = prominence >= 0.02;
            
            title(sprintf('ROI %d - REMOVED', roiNum), 'FontWeight', 'bold', 'Color', 'red');
            text(0.02, 0.98, sprintf('SNR: %.1f %s\nTime: %.1fms %s\nProm: %.3f %s', ...
                 snr, ternary(snr_pass, '✓', '✗'), ...
                 timeToPeak, ternary(timing_pass, '✓', '✗'), ...
                 prominence, ternary(prominence_pass, '✓', '✗')), ...
                 'Units', 'normalized', 'VerticalAlignment', 'top', ...
                 'BackgroundColor', 'white', 'FontSize', 8);
        else
            title(sprintf('ROI %d - REMOVED', roiNum), 'FontWeight', 'bold', 'Color', 'red');
        end
        
        xlabel('Time (ms)');
        ylabel('ΔF/F');
        grid on;
        
        if plotCount == 1
            legend('ROI trace', 'Stimulus', 'Threshold', 'Location', 'best', 'FontSize', 8);
        end
    end
    
    sgtitle('ROIs Removed by Enhanced Filter (Check if these look like noise)', ...
            'FontSize', 14, 'FontWeight', 'bold');
end

function roiIdx = findROIIndex(headers, roiNumber)
    % Find ROI index in headers
    
    roiIdx = [];
    for i = 1:length(headers)
        headerStr = char(headers{i});
        
        % Try different patterns
        if contains(headerStr, sprintf('ROI %d', roiNumber)) || ...
           contains(headerStr, sprintf('ROI%d', roiNumber)) || ...
           contains(headerStr, sprintf('roi %d', roiNumber)) || ...
           contains(headerStr, sprintf('%03d', roiNumber)) || ...
           contains(headerStr, sprintf('%d)', roiNumber))
            roiIdx = i;
            return;
        end
    end
end

function result = ternary(condition, trueVal, falseVal)
    % Simple ternary operator
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end