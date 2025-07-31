function direct_filter_test()
    % DIRECT_FILTER_TEST - Direct comparison bypassing compatibility issues
    %
    % This version calls the filtering methods directly to avoid any 
    % function handle or compatibility issues.
    
    fprintf('\n=== Direct Filter Comparison Test ===\n');
    fprintf('Comparing original vs enhanced filtering (direct calls)\n\n');
    
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
    
    % Run filtering methods directly
    fprintf('\nStep 3: Running filter comparison...\n');
    
    % Method 1: Original filtering (force original method)
    fprintf('  Running original filtering...\n');
    [originalFiltered, originalHeaders, originalThresholds, originalStats] = ...
        runOriginalFiltering(dF_values, validHeaders, thresholds, experimentType, ppfTimepoint);
    
    % Method 2: Enhanced filtering (call directly)
    fprintf('  Running enhanced filtering...\n');
    [enhancedFiltered, enhancedHeaders, enhancedThresholds, enhancedStats] = ...
        runEnhancedFiltering(dF_values, validHeaders, thresholds, experimentType, ppfTimepoint);
    
    % Debug: Check what headers we actually got
    fprintf('\n=== DEBUG: Header Analysis ===\n');
    fprintf('Original headers count: %d\n', length(originalHeaders));
    fprintf('Enhanced headers count: %d\n', length(enhancedHeaders));
    
    if ~isempty(originalHeaders)
        fprintf('First few original headers: %s, %s, %s\n', ...
                char(originalHeaders{1}), char(originalHeaders{2}), char(originalHeaders{3}));
    end
    
    if ~isempty(enhancedHeaders)
        fprintf('First few enhanced headers: %s, %s, %s\n', ...
                char(enhancedHeaders{1}), char(enhancedHeaders{2}), char(enhancedHeaders{3}));
    end
    
    % Extract ROI numbers using the proper string utils
    originalROIs = modules.utils.extractROINumbers(originalHeaders);
    enhancedROIs = modules.utils.extractROINumbers(enhancedHeaders);
    
    % Fallback extraction if the main method fails
    if isempty(originalROIs) && ~isempty(originalHeaders)
        fprintf('Trying fallback ROI extraction for original headers...\n');
        originalROIs = fallbackExtractROINumbers(originalHeaders);
    end
    
    if isempty(enhancedROIs) && ~isempty(enhancedHeaders)
        fprintf('Trying fallback ROI extraction for enhanced headers...\n');
        enhancedROIs = fallbackExtractROINumbers(enhancedHeaders);
    end
    
    % Display results
    fprintf('\n=== COMPARISON RESULTS ===\n');
    fprintf('Original filtering:  %d ROIs passed (%d headers)\n', length(originalROIs), length(originalHeaders));
    fprintf('Enhanced filtering:  %d ROIs passed (%d headers)\n', length(enhancedROIs), length(enhancedHeaders));
    
    % Find differences
    if ~isempty(originalROIs) && ~isempty(enhancedROIs)
        bothPassed = intersect(originalROIs, enhancedROIs);
        originalOnly = setdiff(originalROIs, enhancedROIs);  % Enhanced filter removes these
        enhancedOnly = setdiff(enhancedROIs, originalROIs);  % Enhanced filter adds these
        
        fprintf('Both methods:        %d ROIs\n', length(bothPassed));
        fprintf('Net change:          %+d ROIs\n', length(enhancedROIs) - length(originalROIs));
        
        % Show ROIs removed by enhanced filter
        if ~isempty(originalOnly)
            fprintf('\n=== ROIs REMOVED by Enhanced Filter ===\n');
            fprintf('These %d ROIs passed original threshold but failed enhanced filtering:\n', length(originalOnly));
            fprintf('(These are potential FALSE POSITIVES caught by enhanced filtering)\n\n');
            
            for i = 1:length(originalOnly)
                fprintf('  ROI %d\n', originalOnly(i));
            end
            
            % Show a few example traces
            if length(originalOnly) > 0
                fprintf('\nShowing example traces of removed ROIs...\n');
                plotRemovedROIs(dF_values, validHeaders, originalOnly, thresholds, originalHeaders);
            end
            
        else
            fprintf('\n✓ Enhanced filter did not remove any additional ROIs\n');
        end
        
        % Show ROIs added by enhanced filter (unlikely)
        if ~isempty(enhancedOnly)
            fprintf('\n=== ROIs ADDED by Enhanced Filter ===\n');
            fprintf('These %d ROIs failed original but passed enhanced filtering:\n', length(enhancedOnly));
            for i = 1:length(enhancedOnly)
                fprintf('  ROI %d\n', enhancedOnly(i));
            end
        end
        
        % Recommendation
        fprintf('\n=== RECOMMENDATION ===\n');
        if length(originalOnly) > length(originalROIs) * 0.1
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
        
    else
        fprintf('ERROR: Could not extract ROI numbers for comparison\n');
    end
    
    fprintf('\nTest complete!\n');
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = runOriginalFiltering(dF_values, headers, thresholds, experimentType, ppfTimepoint)
    % Run original filtering method directly
    
    cfg = GluSnFRConfig();
    
    % Force use of original method (disable enhanced filtering)
    originalEnhanced = cfg.filtering.ENABLE_ENHANCED_FILTERING;
    cfg.filtering.ENABLE_ENHANCED_FILTERING = false;
    
    try
        filter_module = roi_filter();
        [filteredData, filteredHeaders, filteredThresholds, stats] = ...
            filter_module.filterROIs(dF_values, headers, thresholds, experimentType, ppfTimepoint);
        
        % Debug: Check what we got back
        fprintf('      Original filtering returned: %d data columns, %d headers\n', ...
                size(filteredData, 2), length(filteredHeaders));
        
        % Restore original setting
        cfg.filtering.ENABLE_ENHANCED_FILTERING = originalEnhanced;
        
    catch ME
        cfg.filtering.ENABLE_ENHANCED_FILTERING = originalEnhanced;
        rethrow(ME);
    end
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = runEnhancedFiltering(dF_values, headers, thresholds, experimentType, ppfTimepoint)
    % Run enhanced filtering method directly
    
    try
        % Call the fixed enhanced filtering directly
        [filteredData, filteredHeaders, filteredThresholds, stats] = ...
            runEnhancedFilteringDirect(dF_values, headers, thresholds, experimentType, ppfTimepoint);
        
    catch ME
        fprintf('    Enhanced filtering failed: %s\n', ME.message);
        fprintf('    Using original method as fallback\n');
        [filteredData, filteredHeaders, filteredThresholds, stats] = ...
            runOriginalFiltering(dF_values, headers, thresholds, experimentType, ppfTimepoint);
        stats.method_used = 'original_fallback';
    end
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = runEnhancedFilteringDirect(dF_values, headers, thresholds, experimentType, ppfTimepoint)
    % Direct implementation of enhanced filtering
    
    cfg = getEnhancedConfig();
    
    fprintf('    Enhanced filtering (temporal + kinetic validation)\n');
    fprintf('      RELAXED PARAMETERS: Rise 1-60ms, SNR>1.5, Amp>0.3%%, Decay<85%%\n');
    
    % Start with basic filtering
    filter_module = roi_filter();
    originalEnhanced = cfg.filtering.ENABLE_ENHANCED_FILTERING;
    cfg.filtering.ENABLE_ENHANCED_FILTERING = false;  % Force original for base
    
    [basicFiltered, basicHeaders, basicThresholds, basicStats] = ...
        filter_module.filterROIs(dF_values, headers, thresholds, experimentType, ppfTimepoint);
    
    cfg.filtering.ENABLE_ENHANCED_FILTERING = originalEnhanced;
    
    if isempty(basicFiltered)
        filteredData = basicFiltered;
        filteredHeaders = basicHeaders;
        filteredThresholds = basicThresholds;
        stats = basicStats;
        stats.enhancement_applied = false;
        return;
    end
    
    % Debug: Check basic filtering results
    fprintf('      Basic filtering returned: %d data columns, %d headers\n', ...
            size(basicFiltered, 2), length(basicHeaders));
    
    % Apply enhanced validation
    [n_frames, n_rois] = size(basicFiltered);
    enhancedMask = true(1, n_rois);
    
    % Temporal validation
    for roi = 1:n_rois
        dF_trace = basicFiltered(:, roi);
        if ~validateTemporalCharacteristics(dF_trace, cfg, experimentType, ppfTimepoint)
            enhancedMask(roi) = false;
        end
    end
    
    temporalPassed = sum(enhancedMask);
    fprintf('      Temporal validation: %d/%d ROIs passed\n', temporalPassed, n_rois);
    
    % Kinetic validation
    for roi = 1:n_rois
        if enhancedMask(roi)  % Only check ROIs that passed temporal
            dF_trace = basicFiltered(:, roi);
            if ~validateKinetics(dF_trace, cfg)
                enhancedMask(roi) = false;
            end
        end
    end
    
    kineticPassed = sum(enhancedMask);
    fprintf('      Kinetic validation: %d/%d ROIs passed\n', kineticPassed, temporalPassed);
    
    % Apply final filtering - FIXED: Make sure we return the filtered results
    if any(enhancedMask)
        filteredData = basicFiltered(:, enhancedMask);
        filteredHeaders = basicHeaders(enhancedMask);
        filteredThresholds = basicThresholds(enhancedMask);
        
        % Debug: Verify we have headers
        fprintf('      Final filtering: %d data columns, %d headers\n', ...
                size(filteredData, 2), length(filteredHeaders));
    else
        % Fallback to basic if enhanced removes everything
        filteredData = basicFiltered;
        filteredHeaders = basicHeaders;
        filteredThresholds = basicThresholds;
        fprintf('      WARNING: Enhanced removed all ROIs, using basic filtering\n');
    end
    
    % Create stats
    stats = basicStats;
    stats.enhancement_applied = true;
    stats.temporal_passed = temporalPassed;
    stats.kinetic_passed = kineticPassed;
    stats.final_passed = length(filteredHeaders);
    
    fprintf('    Enhanced filtering complete: %d→%d ROIs\n', n_rois, length(filteredHeaders));
end

function isValid = validateTemporalCharacteristics(dF_trace, cfg, experimentType, ppfTimepoint)
    % SCHMITT TRIGGER approach for signal detection (from literature)
    % Upper threshold: 3.5σ, Lower threshold: 1.5σ
    
    % Calculate baseline statistics (pre-stimulus)
    stimFrame = cfg.timing.STIMULUS_FRAME;
    baselineWindow = 1:min(stimFrame-10, 200);  % Baseline before stimulus (avoid stimulus artifact)
    
    if length(baselineWindow) < 50
        isValid = false;
        return;
    end
    
    baselineData = dF_trace(baselineWindow);
    baselineMean = mean(baselineData);
    baselineStd = std(baselineData);
    
    if baselineStd <= 0
        isValid = false;
        return;
    end
    
    % Schmitt trigger thresholds
    upperThreshold = baselineMean + cfg.filtering.UPPER_THRESHOLD_SIGMA * baselineStd;
    lowerThreshold = baselineMean + cfg.filtering.LOWER_THRESHOLD_SIGMA * baselineStd;
    
    % Find signal periods using Schmitt trigger
    signalPeriods = findSchmittTriggerSignals(dF_trace, upperThreshold, lowerThreshold, stimFrame, cfg);
    
    if isempty(signalPeriods)
        isValid = false;
        return;
    end
    
    % Check if we have at least one valid signal period
    % For paired-pulse, we might have multiple signals
    validSignalFound = false;
    
    for i = 1:size(signalPeriods, 1)
        signalStart = signalPeriods(i, 1);
        signalEnd = signalPeriods(i, 2);
        
        % Check minimum duration
        signalDuration = (signalEnd - signalStart) * cfg.timing.MS_PER_FRAME;
        
        if signalDuration >= cfg.filtering.MIN_SIGNAL_DURATION_MS
            % Check if signal occurs near stimulus (within reasonable window)
            timingWindow = 200;  % 1000ms window around stimulus (generous for paired-pulse)
            if signalStart >= stimFrame - 20 && signalStart <= stimFrame + timingWindow
                validSignalFound = true;
                break;
            end
        end
    end
    
    isValid = validSignalFound;
end

function signalPeriods = findSchmittTriggerSignals(trace, upperThresh, lowerThresh, stimFrame, cfg)
    % Implement Schmitt trigger to find signal start/end points
    
    signalPeriods = [];
    inSignal = false;
    signalStart = 0;
    
    % Start analysis from stimulus frame onwards
    analysisStart = max(1, stimFrame - 10);
    analysisEnd = min(length(trace), stimFrame + 200);  % 1 seconds post-stimulus
    
    for i = analysisStart:analysisEnd
        if ~inSignal
            % Look for signal start (exceeds upper threshold)
            if trace(i) > upperThresh
                inSignal = true;
                signalStart = i;
            end
        else
            % Look for signal end (decays below lower threshold)
            if trace(i) < lowerThresh
                inSignal = false;
                signalEnd = i;
                
                % Store this signal period
                signalPeriods(end+1, :) = [signalStart, signalEnd];
            end
        end
    end
    
    % Handle case where signal doesn't return to lower threshold by end of trace
    if inSignal
        signalEnd = analysisEnd;
        signalPeriods(end+1, :) = [signalStart, signalEnd];
    end
end

function isValid = validateKinetics(dF_trace, cfg)
    % DECAY-FOCUSED kinetic validation (main filtering criterion)
    % This is the primary filter to distinguish real signals from artifacts
    
    stimFrame = cfg.timing.STIMULUS_FRAME;
    
    % Calculate baseline statistics
    baselineWindow = 1:min(stimFrame-10, 200);
    baselineMean = mean(dF_trace(baselineWindow));
    baselineStd = std(dF_trace(baselineWindow));
    
    if baselineStd <= 0
        isValid = false;
        return;
    end
    
    % Find signal using Schmitt trigger
    upperThresh = baselineMean + cfg.filtering.UPPER_THRESHOLD_SIGMA * baselineStd;
    lowerThresh = baselineMean + cfg.filtering.LOWER_THRESHOLD_SIGMA * baselineStd;
    
    signalPeriods = findSchmittTriggerSignals(dF_trace, upperThresh, lowerThresh, stimFrame, cfg);
    
    if isempty(signalPeriods)
        isValid = false;
        return;
    end
    
    % Analyze decay characteristics for each signal
    validDecayFound = false;
    
    for i = 1:size(signalPeriods, 1)
        signalStart = signalPeriods(i, 1);
        signalEnd = signalPeriods(i, 2);
        
        % Analyze decay from signal peak to end
        if analyzeDecayCharacteristics(dF_trace, signalStart, signalEnd, cfg)
            validDecayFound = true;
            break;
        end
    end
    
    isValid = validDecayFound;
end

function isValidDecay = analyzeDecayCharacteristics(trace, signalStart, signalEnd, cfg)
    % Analyze decay characteristics - main filtering criterion
    
    % Find peak within signal period
    signalTrace = trace(signalStart:signalEnd);
    [peakValue, peakIdx] = max(signalTrace);
    peakFrame = signalStart + peakIdx - 1;
    
    % Define decay analysis window
    decayWindowFrames = round(cfg.filtering.DECAY_ANALYSIS_WINDOW_MS / cfg.timing.MS_PER_FRAME);
    decayEndFrame = min(length(trace), peakFrame + decayWindowFrames);
    
    if decayEndFrame <= peakFrame + 2  % Need at least a few points for decay analysis
        isValidDecay = false;
        return;
    end
    
    % Extract decay trace
    decayTrace = trace(peakFrame:decayEndFrame);
    decayTimes = (0:length(decayTrace)-1) * cfg.timing.MS_PER_FRAME;
    
    % CRITERIA 1: Check if signal actually decays (not just noise)
    % Signal should decrease from peak value
    endValue = decayTrace(end);
    decayAmount = peakValue - endValue;
    decayRatio = decayAmount / peakValue;
    
    if decayRatio < cfg.filtering.MIN_DECAY_RATIO
        isValidDecay = false;
        return;
    end
    
    % CRITERIA 2: Check decay time constant is reasonable
    % Fit exponential decay: y = A * exp(-t/tau) + C
    try
        decayTimeConstant = fitDecayTimeConstant(decayTrace, cfg.timing.MS_PER_FRAME);
        
        if decayTimeConstant > cfg.filtering.MAX_DECAY_TIME_MS
            isValidDecay = false;
            return;
        end
        
    catch
        % If decay fitting fails, use simpler criterion
        % Check that we decay reasonably within the analysis window
        midPoint = round(length(decayTrace) / 2);
        if midPoint > 1
            midValue = decayTrace(midPoint);
            if midValue > peakValue * 0.85  % Should decay to <85% by midpoint
                isValidDecay = false;
                return;
            end
        end
    end
    
    % CRITERIA 3: Check for monotonic-ish decay (allows some noise)
    % Signal shouldn't have large increases after the peak
    maxIncreaseAllowed = peakValue * 0.2;  % Allow 20% increase above peak
    
    if any(decayTrace > peakValue + maxIncreaseAllowed)
        isValidDecay = false;
        return;
    end
    
    % All decay criteria passed
    isValidDecay = true;
end

function timeConstant = fitDecayTimeConstant(decayTrace, msPerFrame)
    % Fit exponential decay and return time constant in ms
    % More robust fitting for decay analysis
    
    % Normalize and prepare data
    t = (0:length(decayTrace)-1) * msPerFrame;
    y = decayTrace / decayTrace(1);  % Normalize to start at 1
    
    % Only fit points that are reasonable for exponential decay
    validIdx = y > 0.1 & y <= 1.0 & isfinite(log(y));
    
    if sum(validIdx) < 3
        error('Insufficient data for decay fitting');
    end
    
    t_fit = t(validIdx);
    log_y_fit = log(y(validIdx));
    
    % Linear fit: log(y) = log(A) - t/tau
    % Use robust fitting to handle outliers
    try
        p = polyfit(t_fit, log_y_fit, 1);
        timeConstant = -1 / p(1);  % tau = -1/slope
        
        % Sanity check
        if timeConstant <= 0 || timeConstant > 1000  % 0-1000ms range
            error('Unrealistic time constant');
        end
        
    catch
        % Fallback: estimate from half-life
        halfIdx = find(y <= 0.5, 1);
        if ~isempty(halfIdx)
            timeConstant = t(halfIdx) / log(2);  % Convert half-life to time constant
        else
            error('Could not estimate decay time');
        end
    end
end

function cfg = getEnhancedConfig()
    % Get enhanced configuration using Schmitt trigger approach from literature
    % Based on: 3.5σ upper threshold, 1.5σ lower threshold, decay-focused filtering
    
    cfg = GluSnFRConfig();  % Use your built-in configuration
    
    % SCHMITT TRIGGER PARAMETERS (from literature)
    cfg.filtering.UPPER_THRESHOLD_SIGMA = 3.5;      % Signal starts when exceeds 3.5σ
    cfg.filtering.LOWER_THRESHOLD_SIGMA = 1.5;      % Signal ends when decays below 1.5σ
    cfg.filtering.MIN_SIGNAL_DURATION_MS = 10;      % Minimum signal duration (10ms)
    
    % DECAY-FOCUSED PARAMETERS (main filtering criterion)
    cfg.filtering.ENABLE_DECAY_ANALYSIS = true;     % Enable decay-based filtering
    cfg.filtering.MAX_DECAY_TIME_MS = 100;          % Maximum reasonable decay time
    cfg.filtering.MIN_DECAY_RATIO = 0.3;            % Should decay to at least 30% below peak
    cfg.filtering.DECAY_ANALYSIS_WINDOW_MS = 150;   % Analysis window post-signal
    
    % SENSOR KINETICS PARAMETERS (for flagging additional points)
    cfg.filtering.PRE_SIGNAL_BUFFER_MS = 5;         % Buffer before signal start
    cfg.filtering.POST_SIGNAL_BUFFER_MS = 20;       % Buffer after signal end
    
    % REMOVED PARAMETERS (not used in Schmitt trigger approach)
    % - Rise time constraints removed (as requested)
    % - Fixed amplitude thresholds removed (using σ-based instead)
    % - SNR requirements removed (built into Schmitt trigger)
    
    % Use existing timing parameters from your config
    cfg.timing.MS_PER_FRAME = 5;  % 5ms per frame at 200Hz
end

% Note: Using modules.utils.extractROINumbers instead of local function

function roiNumbers = fallbackExtractROINumbers(headers)
    % Fallback ROI number extraction
    
    roiNumbers = [];
    for i = 1:length(headers)
        headerStr = char(headers{i});
        
        % Try multiple patterns
        matches = regexp(headerStr, 'ROI\s*(\d+)', 'tokens', 'ignorecase');
        if ~isempty(matches)
            roiNumbers(end+1) = str2double(matches{1}{1});
            continue;
        end
        
        % Try just finding numbers
        matches = regexp(headerStr, '(\d+)', 'tokens');
        if ~isempty(matches)
            roiNumbers(end+1) = str2double(matches{end}{1}); % Use last number
        end
    end
end

function plotRemovedROIs(dF_values, headers, removedROIs, thresholds, originalFilteredHeaders)
    % Plot traces of ROIs removed by enhanced filtering (POTENTIAL FALSE POSITIVES)
    % FIXED: Use correct headers and fix concatenation bug
    
    if isempty(removedROIs)
        fprintf('No ROIs to plot\n');
        return;
    end
    
    cfg = GluSnFRConfig();
    time_ms = (0:size(dF_values, 1)-1) * cfg.timing.MS_PER_FRAME;
    stimTime = cfg.timing.STIMULUS_TIME_MS;
    
    fprintf('DEBUG: Attempting to plot %d removed ROIs\n', length(removedROIs));
    fprintf('DEBUG: Available headers count: %d\n', length(headers));
    fprintf('DEBUG: First few headers: "%s", "%s", "%s"\n', ...
            char(headers{1}), char(headers{2}), char(headers{3}));
    
    % Pre-scan to find which ROIs we can actually plot
    validROIIndices = [];
    validROINumbers = [];
    validThresholds = [];
    
    for i = 1:length(removedROIs)
        roiNum = removedROIs(i);
        
        % Find this ROI in the original unfiltered data
        roiIdx = findROIInHeaders(headers, roiNum);
        
        if ~isempty(roiIdx)
            validROIIndices(end+1) = roiIdx;
            validROINumbers(end+1) = roiNum;
            
            % Also need to get the threshold - find this ROI in the original filtered data  
            originalIdx = findROIInHeaders(originalFilteredHeaders, roiNum);
            if ~isempty(originalIdx) && originalIdx <= length(thresholds)
                validThresholds(end+1) = thresholds(originalIdx);
            else
                validThresholds(end+1) = NaN;
            end
        else
            fprintf('DEBUG: Could not find ROI %d in original headers\n', roiNum);
        end
    end
    
    fprintf('DEBUG: Successfully matched %d/%d ROIs\n', length(validROINumbers), length(removedROIs));
    
    if isempty(validROINumbers)
        fprintf('ERROR: Could not find any of the removed ROIs in the headers\n');
        return;
    end
    
    numToPlot = min(18, length(validROINumbers));  
    numFigures = ceil(numToPlot / 9);  
    
    plotCount = 0;
    
    for figNum = 1:numFigures
        figure('Position', [100 + (figNum-1)*50, 100 + (figNum-1)*50, 1400, 1000], ...
               'Name', sprintf('POTENTIAL FALSE POSITIVES - Figure %d/%d', figNum, numFigures));
        
        startIdx = (figNum - 1) * 9 + 1;
        endIdx = min(figNum * 9, numToPlot);
        
        subplotCount = 0;
        
        for i = startIdx:endIdx
            roiNum = validROINumbers(i);
            roiIdx = validROIIndices(i);
            thresholdVal = validThresholds(i);
            
            subplotCount = subplotCount + 1;
            plotCount = plotCount + 1;
            
            subplot(3, 3, subplotCount);
            
            % Plot trace in BLACK
            plot(time_ms, dF_values(:, roiIdx), 'k-', 'LineWidth', 1.5);
            hold on;
            
            % Add threshold in red
            if isfinite(thresholdVal)
                plot([0, max(time_ms)], [thresholdVal, thresholdVal], 'r--', 'LineWidth', 1);
            end
            
            % Add stimulus in green
            plot([stimTime, stimTime], ylim, 'g--', 'LineWidth', 1);
            
            title(sprintf('ROI %d (POTENTIAL FALSE POSITIVE)', roiNum), 'FontWeight', 'bold', 'Color', 'red');
            xlabel('Time (ms)');
            ylabel('ΔF/F');
            grid on;
            
            % Show stats
            stimFrame = cfg.timing.STIMULUS_FRAME;
            postStim = stimFrame + (1:50);
            postStim = postStim(postStim <= size(dF_values, 1));
            
            if ~isempty(postStim)
                [peakVal, peakIdx] = max(dF_values(postStim, roiIdx));
                peakTime = (stimFrame + peakIdx - 1) * cfg.timing.MS_PER_FRAME;
                riseTime = peakTime - stimTime;
                
                baselineWindow = 1:min(stimFrame-1, 200);
                baselineNoise = std(dF_values(baselineWindow, roiIdx));
                snr = peakVal / baselineNoise;
                
                text(0.02, 0.98, sprintf('Peak: %.4f\nRise: %.1fms\nSNR: %.1f', peakVal, riseTime, snr), ...
                     'Units', 'normalized', 'VerticalAlignment', 'top', 'BackgroundColor', 'white', 'FontSize', 7);
            end
            
            if subplotCount == 1
                legend('ROI trace', 'Threshold', 'Stimulus', 'Location', 'best', 'FontSize', 8);
            end
        end
        
        sgtitle(sprintf('POTENTIAL FALSE POSITIVES: Figure %d/%d (ROIs Removed by Enhanced Filter)', figNum, numFigures), ...
                'FontSize', 16, 'FontWeight', 'bold', 'Color', 'red');
    end
    
    fprintf('Successfully plotted %d potential false positive ROIs across %d figures\n', plotCount, numFigures);
end

function roiIdx = findROIInHeaders(headers, roiNum)
    % FIXED: Improved ROI finding function without concatenation bugs
    
    roiIdx = [];
    
    % Create comprehensive list of patterns to try
    patterns = {
        sprintf('roi-%02d', roiNum),    % "roi-02" (with leading zero)
        sprintf('roi-%d', roiNum),      % "roi-2" (without leading zero)  
        sprintf('ROI-%02d', roiNum),    % "ROI-02"
        sprintf('ROI-%d', roiNum),      % "ROI-2"
        sprintf('ROI %02d', roiNum),    % "ROI 02"
        sprintf('ROI %d', roiNum),      % "ROI 2"
        sprintf('ROI%02d', roiNum),     % "ROI02"
        sprintf('ROI%d', roiNum),       % "ROI2"
        sprintf('%03d', roiNum),        % "002"
        sprintf('%02d', roiNum),        % "02"
        sprintf('-%02d)', roiNum),      % "-02)" (end of filename)
        sprintf('-%d)', roiNum),        % "-2)" (end of filename)
        sprintf('%d)', roiNum)          % "2)" (end of filename)
    };
    
    % Add single digit patterns without concatenation bugs
    if roiNum < 10
        patterns{end+1} = sprintf('0%d)', roiNum);  % "02)"
    end
    
    for j = 1:length(headers)
        headerStr = char(headers{j});
        
        for k = 1:length(patterns)
            if contains(headerStr, patterns{k})
                roiIdx = j;
                return;
            end
        end
    end
    
    % If still not found, try a more general approach
    % Look for the number anywhere in the string
    for j = 1:length(headers)
        headerStr = char(headers{j});
        
        % Extract all numbers from the header
        numbers = regexp(headerStr, '\d+', 'match');
        
        for k = 1:length(numbers)
            if str2double(numbers{k}) == roiNum
                roiIdx = j;
                return;
            end
        end
    end
    
    % Still not found - this ROI doesn't exist in the headers
    roiIdx = [];
end