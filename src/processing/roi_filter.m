function filter = roi_filter()
    % ROI_FILTER - Enhanced ROI filtering with Schmitt trigger as default
    % 
    % Updated with Schmitt trigger integration and minimal output for cleaner user experience
    
    filter.filterROIs = @filterROIsMain;
    filter.filterROIsOriginal = @filterROIsOriginal;
    filter.filterROIsSchmitt = @filterROIsSchmitt;  % NEW: Schmitt trigger method
    filter.calculateAdaptiveThresholds = @calculateAdaptiveThresholds;
    filter.classifyNoiseLevel = @classifyNoiseLevel;
    filter.getStimulusResponse = @getStimulusResponse;
    filter.applySchmittTrigger = @applySchmittTrigger;  % NEW: Core Schmitt logic
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsMain(dF_values, headers, thresholds, experimentType, varargin)
    % UPDATED: Main filtering function with Schmitt trigger as default
    
    cfg = GluSnFRConfig();
    
    % Check if Schmitt trigger is enabled (default)
    if isfield(cfg.filtering, 'USE_SCHMITT_TRIGGER') && cfg.filtering.USE_SCHMITT_TRIGGER
        try
            [filteredData, filteredHeaders, filteredThresholds, stats] = ...
                filterROIsSchmitt(dF_values, headers, thresholds, experimentType, varargin{:});
            stats.filtering_method = 'schmitt_trigger';
            
        catch ME
            % Fallback to enhanced filtering if Schmitt fails
            if isfield(cfg.filtering, 'ENABLE_ENHANCED_FILTERING') && cfg.filtering.ENABLE_ENHANCED_FILTERING
                [filteredData, filteredHeaders, filteredThresholds, stats] = ...
                    filterROIsEnhanced(dF_values, headers, thresholds, experimentType, varargin{:});
                stats.filtering_method = 'enhanced_fallback';
            else
                [filteredData, filteredHeaders, filteredThresholds, stats] = ...
                    filterROIsOriginal(dF_values, headers, thresholds, experimentType, varargin{:});
                stats.filtering_method = 'original_fallback';
            end
        end
        
    elseif isfield(cfg.filtering, 'ENABLE_ENHANCED_FILTERING') && cfg.filtering.ENABLE_ENHANCED_FILTERING
        % Use enhanced filtering
        try
            [filteredData, filteredHeaders, filteredThresholds, stats] = ...
                filterROIsEnhanced(dF_values, headers, thresholds, experimentType, varargin{:});
            stats.filtering_method = 'enhanced';
            
        catch ME
            [filteredData, filteredHeaders, filteredThresholds, stats] = ...
                filterROIsOriginal(dF_values, headers, thresholds, experimentType, varargin{:});
            stats.filtering_method = 'original_fallback';
        end
        
    else
        % Use original filtering
        [filteredData, filteredHeaders, filteredThresholds, stats] = ...
            filterROIsOriginal(dF_values, headers, thresholds, experimentType, varargin{:});
        stats.filtering_method = 'original';
    end
end

%% ========================================================================
%% NEW: SCHMITT TRIGGER FILTERING FUNCTIONS
%% ========================================================================

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsSchmitt(dF_values, headers, thresholds, experimentType, varargin)
    % Main Schmitt trigger filtering function using centralized config
    
    cfg = GluSnFRConfig();
    
    % Parse inputs
    isPPF = strcmp(experimentType, 'PPF');
    timepoint_ms = [];
    if isPPF && ~isempty(varargin)
        timepoint_ms = varargin{1};
    end
    
    [n_frames, n_rois] = size(dF_values);
    
    % Step 1: Remove empty ROIs (same as current method)
    validMask = ~all(isnan(dF_values), 1) & var(dF_values, 0, 1, 'omitnan') > 0;
    dF_values = dF_values(:, validMask);
    headers = headers(validMask);
    thresholds = thresholds(validMask);
    [~, n_rois_after_cleanup] = size(dF_values);
    
    if n_rois_after_cleanup == 0
        filteredData = [];
        filteredHeaders = {};
        filteredThresholds = [];
        stats = createEmptyStats(experimentType);
        return;
    end
    
    % Step 2: Classify noise levels and calculate Schmitt thresholds
    [noiseClassification, upperThresholds, lowerThresholds] = calculateSchmittThresholds(thresholds, cfg);
    
    % Step 3: Apply Schmitt trigger for each ROI
    schmittMask = false(1, n_rois_after_cleanup);
    schmitt_details = cell(n_rois_after_cleanup, 1);
    
    for roi = 1:n_rois_after_cleanup
        [passes, details] = applySchmittTrigger(dF_values(:, roi), upperThresholds(roi), ...
                                              lowerThresholds(roi), experimentType, timepoint_ms, cfg);
        schmittMask(roi) = passes;
        schmitt_details{roi} = details;
    end
    
    % Step 4: Apply filtered results
    filteredData = dF_values(:, schmittMask);
    filteredHeaders = headers(schmittMask);
    filteredThresholds = thresholds(schmittMask);
    
    % Step 5: Generate statistics
    stats = generateSchmittStats(headers, schmittMask, noiseClassification, ...
                                schmitt_details, experimentType, cfg);
    
    % Add Schmitt-specific information
    stats.schmitt_info = struct();
    stats.schmitt_info.upper_thresholds = upperThresholds;
    stats.schmitt_info.lower_thresholds = lowerThresholds;
    stats.schmitt_info.noise_classification = noiseClassification;
    stats.schmitt_info.details = schmitt_details;
end

function [noiseClassification, upperThresholds, lowerThresholds] = calculateSchmittThresholds(baseThresholds, cfg)
    % Calculate thresholds using centralized configuration parameters
    
    n_rois = length(baseThresholds);
    noiseClassification = cell(n_rois, 1);
    upperThresholds = zeros(n_rois, 1);
    lowerThresholds = zeros(n_rois, 1);
    
    for i = 1:n_rois
        threshold = baseThresholds(i);
        
        % Classify noise level
        if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
            noiseClassification{i} = 'low';
            upperThresholds(i) = threshold * cfg.filtering.schmitt.LOW_NOISE_UPPER_MULT;
            lowerThresholds(i) = threshold * cfg.filtering.schmitt.LOWER_THRESHOLD_MULT;
        else
            noiseClassification{i} = 'high';
            upperThresholds(i) = threshold * cfg.filtering.schmitt.HIGH_NOISE_UPPER_MULT;
            lowerThresholds(i) = threshold * cfg.filtering.schmitt.LOWER_THRESHOLD_MULT;
        end
    end
end

function [passes, details] = applySchmittTrigger(trace, upperThreshold, lowerThreshold, experimentType, timepoint_ms, cfg)
    % Apply Schmitt trigger logic using centralized configuration
    
    details = struct();
    details.triggered = false;
    details.valid_signals = 0;
    details.invalid_signals = 0;
    details.signal_durations = [];
    details.debug_info = struct();
    
    % Define stimulus frames using configuration parameters
    stimFrame1 = cfg.timing.STIMULUS_FRAME;
    if strcmp(experimentType, 'PPF') && ~isempty(timepoint_ms)
        stimFrame2 = stimFrame1 + round(timepoint_ms / cfg.timing.MS_PER_FRAME);
        search_windows = [stimFrame1 + 1 : stimFrame1 + cfg.filtering.schmitt.PPF_WINDOW1_FRAMES, ...
                         stimFrame2 + 1 : min(stimFrame2 + cfg.filtering.schmitt.PPF_WINDOW2_FRAMES, length(trace))];
    else
        search_windows = stimFrame1 + 1 : min(stimFrame1 + cfg.filtering.schmitt.POST_STIM_SEARCH_FRAMES, length(trace));
    end
    
    % Ensure search windows are within trace bounds
    search_windows = search_windows(search_windows > 0 & search_windows <= length(trace));
    
    if isempty(search_windows)
        passes = false;
        return;
    end
    
    % Find all crossings of upper threshold in search windows
    upper_crossings = find(trace(search_windows) > upperThreshold);
    
    if isempty(upper_crossings)
        passes = false;
        return;
    end
    
    % Convert back to original trace indices
    upper_crossings = search_windows(upper_crossings);
    details.triggered = true;
    details.debug_info.upper_crossings = upper_crossings;
    
    valid_signals = 0;
    
    for i = 1:length(upper_crossings)
        crossing_frame = upper_crossings(i);
        
        % Use configurable decay analysis window
        decay_search_start = crossing_frame + 1;
        decay_search_end = min(crossing_frame + cfg.filtering.schmitt.DECAY_ANALYSIS_FRAMES, length(trace));
        
        if decay_search_start > length(trace)
            continue;
        end
        
        % Find when signal decays below lower threshold
        below_lower = find(trace(decay_search_start:decay_search_end) < lowerThreshold, 1);
        
        if isempty(below_lower)
            % Signal never decays below lower threshold - likely valid signal
            signal_duration = decay_search_end - crossing_frame;
            valid_signals = valid_signals + 1;
            details.signal_durations(end+1) = signal_duration;
            
        else
            % Signal decays below lower threshold
            decay_frame = decay_search_start + below_lower - 1;
            signal_duration = decay_frame - crossing_frame;
            
            % Use configurable validation criteria
            is_valid = validateSignalCharacteristics(trace, crossing_frame, decay_frame, ...
                                                   upperThreshold, lowerThreshold, cfg);
            
            if is_valid
                valid_signals = valid_signals + 1;
                details.signal_durations(end+1) = signal_duration;
            else
                details.invalid_signals = details.invalid_signals + 1;
            end
        end
    end
    
    details.valid_signals = valid_signals;
    passes = valid_signals > 0;
end

function is_valid = validateSignalCharacteristics(trace, crossing_frame, decay_frame, upperThreshold, lowerThreshold, cfg)
    % Enhanced signal validation using centralized configuration parameters
    
    signal_duration = decay_frame - crossing_frame;
    schmitt_params = cfg.filtering.schmitt;
    
    % Criterion 1: Minimum duration check
    if signal_duration <= schmitt_params.MIN_SIGNAL_DURATION
        is_valid = false;
        return;
    end
    
    % Criterion 2: Signal amplitude and shape analysis
    signal_window = crossing_frame:decay_frame;
    if signal_window(end) > length(trace)
        signal_window = signal_window(signal_window <= length(trace));
    end
    
    if length(signal_window) < 2
        is_valid = false;
        return;
    end
    
    signal_trace = trace(signal_window);
    
    % Criterion 3: Peak amplitude check
    peak_amplitude = max(signal_trace);
    if peak_amplitude < upperThreshold * schmitt_params.PEAK_AMPLITUDE_FACTOR
        is_valid = false;
        return;
    end
    
    % Criterion 4: For short signals, use lenient validation
    if signal_duration <= schmitt_params.SHORT_SIGNAL_THRESHOLD
        is_valid = true;
        return;
    end
    
    % Criterion 5: For longer signals, check decay pattern
    first_half = signal_trace(1:ceil(length(signal_trace)/2));
    second_half = signal_trace(ceil(length(signal_trace)/2)+1:end);
    
    if ~isempty(first_half) && ~isempty(second_half)
        mean_first = mean(first_half);
        mean_second = mean(second_half);
        
        if mean_first > 0
            decay_ratio = mean_second / mean_first;
            if decay_ratio > schmitt_params.MAX_DECAY_RATIO
                is_valid = false;
                return;
            end
        end
    end
    
    % Criterion 6: Check for excessive noise
    signal_noise = std(signal_trace);
    signal_mean = mean(signal_trace);
    if signal_mean > 0 && signal_noise > signal_mean * schmitt_params.MAX_NOISE_RATIO && ...
       signal_duration < schmitt_params.SHORT_SIGNAL_THRESHOLD
        is_valid = false;
        return;
    end
    
    is_valid = true;
end

function stats = generateSchmittStats(headers, schmittMask, noiseClassification, schmitt_details, experimentType, cfg)
    % Generate comprehensive statistics for Schmitt trigger filtering
    
    stats = struct();
    stats.experimentType = experimentType;
    stats.method = 'Schmitt Trigger';
    stats.totalROIs = length(headers);
    stats.passedROIs = sum(schmittMask);
    stats.filterRate = stats.passedROIs / stats.totalROIs;
    
    % Noise level breakdown
    passedNoise = noiseClassification(schmittMask);
    stats.lowNoiseROIs = sum(strcmp(passedNoise, 'low'));
    stats.highNoiseROIs = sum(strcmp(passedNoise, 'high'));
    
    % Schmitt trigger specific stats
    triggered_count = sum(cellfun(@(x) x.triggered, schmitt_details));
    valid_signals_total = sum(cellfun(@(x) x.valid_signals, schmitt_details));
    invalid_signals_total = sum(cellfun(@(x) x.invalid_signals, schmitt_details));
    
    stats.triggered_rois = triggered_count;
    stats.valid_signals_total = valid_signals_total;
    stats.invalid_signals_total = invalid_signals_total;
    stats.trigger_rate = triggered_count / stats.totalROIs;
    
    if triggered_count > 0
        stats.signal_validity_rate = valid_signals_total / (valid_signals_total + invalid_signals_total);
    else
        stats.signal_validity_rate = 0;
    end
    
    % Configuration used
    stats.configUsed = cfg.filtering.schmitt;
    stats.configUsed.lowNoiseCutoff = cfg.thresholds.LOW_NOISE_CUTOFF;
    
    % Create summary string
    stats.summary = sprintf('%s Schmitt: %d/%d ROIs passed (%.1f%%), %d triggered, %.1f%% signals valid', ...
        experimentType, stats.passedROIs, stats.totalROIs, stats.filterRate*100, ...
        stats.triggered_rois, stats.signal_validity_rate*100);
end

function stats = createEmptyStats(experimentType)
    % Create empty stats structure
    stats = struct();
    stats.experimentType = experimentType;
    stats.method = 'Schmitt Trigger';
    stats.totalROIs = 0;
    stats.passedROIs = 0;
    stats.filterRate = 0;
    stats.summary = sprintf('%s Schmitt: No ROIs to filter', experimentType);
end

%% ========================================================================
%% EXISTING FUNCTIONS (Enhanced and Original filtering methods)
%% ========================================================================

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsEnhanced(dF_values, headers, thresholds, experimentType, varargin)
    % UPDATED: SIMPLIFIED enhanced filtering with minimal output
    
    cfg = GluSnFRConfig();
    
    % Parse inputs
    isPPF = strcmp(experimentType, 'PPF');
    timepoint_ms = [];
    if isPPF && ~isempty(varargin)
        timepoint_ms = varargin{1};
    end
    
    % STEP 1: Start with original filtering
    [basicData, basicHeaders, basicThresholds, basicStats] = ...
        filterROIsOriginal(dF_values, headers, thresholds, experimentType, varargin{:});
    
    if isempty(basicData)
        filteredData = basicData;
        filteredHeaders = basicHeaders;
        filteredThresholds = basicThresholds;
        stats = basicStats;
        stats.enhancement_applied = false;
        return;
    end
    
    % STEP 2: Apply 3 simple enhancement criteria
    [n_frames, n_rois] = size(basicData);
    enhancedMask = true(1, n_rois);
    
    stimFrame = cfg.timing.STIMULUS_FRAME;
    baselineWindow = 1:min(stimFrame-10, 200);
    postStimWindow = stimFrame + (1:30); % 150ms window
    postStimWindow = postStimWindow(postStimWindow <= n_frames);
    
    criteria_stats = struct();
    criteria_stats.snr_passed = 0;
    criteria_stats.timing_passed = 0;
    criteria_stats.prominence_passed = 0;
    
    for roi = 1:n_rois
        trace = basicData(:, roi);
        
        % CRITERION 1: Signal-to-Noise Ratio
        baselineNoise = std(trace(baselineWindow), 'omitnan');
        if isempty(postStimWindow)
            peakValue = 0;
        else
            peakValue = max(trace(postStimWindow));
        end
        
        if baselineNoise > 0
            snr = peakValue / baselineNoise;
        else
            snr = 0;
        end
        
        % SNR threshold: real signals should have SNR > 3
        snr_pass = snr >= 3.0;
        if snr_pass, criteria_stats.snr_passed = criteria_stats.snr_passed + 1; end
        
        % CRITERION 2: Peak Timing
        if ~isempty(postStimWindow)
            [~, peakIdx] = max(trace(postStimWindow));
            peakFrame = postStimWindow(peakIdx);
            timeToPeak_ms = (peakFrame - stimFrame) * cfg.timing.MS_PER_FRAME;
        else
            timeToPeak_ms = 999;
        end
        
        % Timing threshold: peak should occur 5-100ms after stimulus
        timing_pass = timeToPeak_ms >= 5 && timeToPeak_ms <= 100;
        if timing_pass, criteria_stats.timing_passed = criteria_stats.timing_passed + 1; end
        
        % CRITERION 3: Peak Prominence
        if ~isempty(postStimWindow)
            baseline_mean = mean(trace(baselineWindow), 'omitnan');
            peak_prominence = peakValue - baseline_mean;
        else
            peak_prominence = 0;
        end
        
        % Prominence threshold: peak should be at least 2% above baseline
        prominence_pass = peak_prominence >= 0.02;
        if prominence_pass, criteria_stats.prominence_passed = criteria_stats.prominence_passed + 1; end
        
        % ROI passes if it meets at least 2 out of 3 criteria
        criteriaScore = snr_pass + timing_pass + prominence_pass;
        enhancedMask(roi) = criteriaScore >= 2;
    end
    
    % Apply enhanced filtering
    if any(enhancedMask)
        filteredData = basicData(:, enhancedMask);
        filteredHeaders = basicHeaders(enhancedMask);
        filteredThresholds = basicThresholds(enhancedMask);
    else
        % Fallback to basic filtering if enhanced removes everything
        filteredData = basicData;
        filteredHeaders = basicHeaders;
        filteredThresholds = basicThresholds;
    end
    
    % Generate enhanced stats
    stats = basicStats;
    stats.enhancement_applied = true;
    stats.basic_passed = n_rois;
    stats.enhanced_passed = sum(enhancedMask);
    stats.additional_removed = n_rois - sum(enhancedMask);
    stats.criteria_stats = criteria_stats;
    
    % MINIMAL OUTPUT: No detailed enhancement logging
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsOriginal(dF_values, headers, thresholds, experimentType, varargin)
    % UPDATED: ORIGINAL filtering method with minimal output
    
    cfg = GluSnFRConfig();
    
    % Parse inputs
    isPPF = strcmp(experimentType, 'PPF');
    timepoint_ms = [];
    if isPPF && ~isempty(varargin)
        timepoint_ms = varargin{1};
    end
    
    % MINIMAL OUTPUT: No detailed filtering steps
    
    % More lenient initial cleanup
    [dF_values, headers, thresholds] = removeEmptyROIs(dF_values, headers, thresholds, cfg);
    
    % Configurable duplicate removal (currently disabled in config)
    if cfg.filtering.ENABLE_DUPLICATE_REMOVAL
        [dF_values, headers, thresholds] = removeDuplicateROIs(dF_values, headers, thresholds, cfg);
    end
    
    % Use configuration parameters for adaptive thresholds
    [adaptiveThresholds, noiseClassification] = calculateAdaptiveThresholds(thresholds, cfg);
    
    % Apply stimulus response filtering with configurable parameters
    if isPPF
        [responseFilter, peakResponses] = applyPPFFiltering(dF_values, thresholds, timepoint_ms, cfg);
    else
        responseFilter = apply1APFiltering(dF_values, thresholds, cfg);
        peakResponses = []; % Not applicable for 1AP
    end
    
    % Apply filters
    filteredData = dF_values(:, responseFilter);
    filteredHeaders = headers(responseFilter);
    filteredThresholds = thresholds(responseFilter);
    
    % Generate statistics
    stats = generateFilteringStats(headers, responseFilter, noiseClassification, experimentType, cfg);
    
    % Add PPF-specific peak response information to stats
    if isPPF && ~isempty(peakResponses)
        stats.peakResponses = peakResponses;
        stats.peakResponses.filteredBothPeaks = peakResponses.bothPeaks(responseFilter);
        stats.peakResponses.filteredPeak1Only = peakResponses.peak1Only(responseFilter);
        stats.peakResponses.filteredPeak2Only = peakResponses.peak2Only(responseFilter);
    end
    
    % MINIMAL OUTPUT: No detailed completion message
end

function [adaptiveThresholds, noiseClassification] = calculateAdaptiveThresholds(baseThresholds, cfg)
    % Use configuration parameters instead of hardcoded values (minimal output)
    
    lowNoiseROIs = baseThresholds <= cfg.thresholds.LOW_NOISE_CUTOFF;
    
    adaptiveThresholds = baseThresholds;
    adaptiveThresholds(~lowNoiseROIs) = cfg.thresholds.HIGH_NOISE_MULTIPLIER * baseThresholds(~lowNoiseROIs);
    
    noiseClassification = repmat({'high'}, size(baseThresholds));
    noiseClassification(lowNoiseROIs) = {'low'};
    
    % MINIMAL OUTPUT: No adaptive threshold logging
end

function responseFilter = apply1APFiltering(dF_values, thresholds, cfg)
    % UPDATED: Use configurable threshold percentage with minimal output
    
    stimulusFrame = cfg.timing.STIMULUS_FRAME;
    postWindow = cfg.timing.POST_STIMULUS_WINDOW;
    
    maxResponses = getStimulusResponse(dF_values, stimulusFrame, postWindow);
    
    thresholdPercentage = cfg.filtering.THRESHOLD_PERCENTAGE_1AP;
    responseFilter = maxResponses >= (thresholdPercentage * thresholds) & isfinite(maxResponses);
    
    if isfield(cfg.filtering, 'MIN_RESPONSE_AMPLITUDE')
        amplitudeFilter = maxResponses >= cfg.filtering.MIN_RESPONSE_AMPLITUDE;
        responseFilter = responseFilter & amplitudeFilter;
    end
    
    % MINIMAL OUTPUT: No detailed 1AP filtering logging
end

function [responseFilter, peakResponses] = applyPPFFiltering(dF_values, thresholds, timepoint_ms, cfg)
    % UPDATED: Use configurable threshold percentage with minimal output
    
    stimulusFrame1 = cfg.timing.STIMULUS_FRAME;
    stimulusFrame2 = stimulusFrame1 + round(timepoint_ms / cfg.timing.MS_PER_FRAME);
    postWindow = cfg.timing.POST_STIMULUS_WINDOW;
    
    maxResponses1 = getStimulusResponse(dF_values, stimulusFrame1, postWindow);
    maxResponses2 = getStimulusResponse(dF_values, stimulusFrame2, postWindow);
    
    thresholdPercentage = cfg.filtering.THRESHOLD_PERCENTAGE_PPF;
    response1Filter = maxResponses1 >= (thresholdPercentage * thresholds) & isfinite(maxResponses1);
    response2Filter = maxResponses2 >= (thresholdPercentage * thresholds) & isfinite(maxResponses2);
    responseFilter = response1Filter | response2Filter;
    
    if isfield(cfg.filtering, 'MIN_RESPONSE_AMPLITUDE')
        amplitude1Filter = maxResponses1 >= cfg.filtering.MIN_RESPONSE_AMPLITUDE;
        amplitude2Filter = maxResponses2 >= cfg.filtering.MIN_RESPONSE_AMPLITUDE;
        amplitudeFilter = amplitude1Filter | amplitude2Filter;
        responseFilter = responseFilter & amplitudeFilter;
    end
    
    % NEW: Track peak response patterns
    peakResponses = struct();
    peakResponses.response1Filter = response1Filter;
    peakResponses.response2Filter = response2Filter;
    peakResponses.maxResponses1 = maxResponses1;
    peakResponses.maxResponses2 = maxResponses2;
    
    % Classify response patterns
    peakResponses.bothPeaks = response1Filter & response2Filter;
    peakResponses.peak1Only = response1Filter & ~response2Filter;
    peakResponses.peak2Only = ~response1Filter & response2Filter;
    
    % MINIMAL OUTPUT: No detailed PPF filtering logging
end

function maxResponse = getStimulusResponse(dF_values, stimulusFrame, postWindow)
    % Get maximum response in post-stimulus window
    
    if size(dF_values, 1) > stimulusFrame
        responseStart = stimulusFrame + 1;
        responseEnd = min(stimulusFrame + postWindow, size(dF_values, 1));
        responseData = dF_values(responseStart:responseEnd, :);
        maxResponse = max(responseData, [], 1, 'omitnan');
    else
        maxResponse = zeros(1, size(dF_values, 2));
    end
end

function [cleanData, cleanHeaders, cleanThresholds] = removeEmptyROIs(dF_values, headers, thresholds, cfg)
    % UPDATED: Remove empty ROIs with minimal output
    
    nonEmptyROIs = ~all(isnan(dF_values), 1) & var(dF_values, 0, 1, 'omitnan') > 0;
    
    if isfield(cfg.filtering, 'MAX_BASELINE_NOISE')
        baselineWindow = cfg.timing.BASELINE_FRAMES;
        baselineNoise = std(dF_values(baselineWindow, :), 0, 1, 'omitnan');
        noiseFilter = baselineNoise <= cfg.filtering.MAX_BASELINE_NOISE;
        nonEmptyROIs = nonEmptyROIs & noiseFilter;
    end
    
    cleanData = dF_values(:, nonEmptyROIs);
    cleanHeaders = headers(nonEmptyROIs);
    cleanThresholds = thresholds(nonEmptyROIs);
    
    % MINIMAL OUTPUT: No empty ROI removal logging
end

function [cleanData, cleanHeaders, cleanThresholds] = removeDuplicateROIs(dF_values, headers, thresholds, cfg)
    % Duplicate ROI removal (placeholder - currently disabled)
    
    cleanData = dF_values;
    cleanHeaders = headers;
    cleanThresholds = thresholds;
    
    % MINIMAL OUTPUT: No duplicate removal logging
end

function stats = generateFilteringStats(originalHeaders, responseFilter, noiseClassification, experimentType, cfg)
    % UPDATED: Generate comprehensive filtering statistics with minimal output
    
    stats = struct();
    stats.experimentType = experimentType;
    stats.totalROIs = length(originalHeaders);
    stats.passedROIs = sum(responseFilter);
    stats.filterRate = stats.passedROIs / stats.totalROIs;
    
    % Configuration used
    stats.configUsed = struct();
    stats.configUsed.highNoiseMultiplier = cfg.thresholds.HIGH_NOISE_MULTIPLIER;
    stats.configUsed.lowNoiseCutoff = cfg.thresholds.LOW_NOISE_CUTOFF;
    
    if strcmp(experimentType, 'PPF')
        stats.configUsed.thresholdPercentage = cfg.filtering.THRESHOLD_PERCENTAGE_PPF;
    else
        stats.configUsed.thresholdPercentage = cfg.filtering.THRESHOLD_PERCENTAGE_1AP;
    end
    
    % Noise level statistics for passed ROIs
    if iscell(noiseClassification)
        passedNoise = noiseClassification(responseFilter);
        stats.lowNoiseROIs = sum(strcmp(passedNoise, 'low'));
        stats.highNoiseROIs = sum(strcmp(passedNoise, 'high'));
    else
        stats.lowNoiseROIs = 0;
        stats.highNoiseROIs = stats.passedROIs;
    end
    
    stats.summary = sprintf('%s: %d/%d ROIs passed (%.1f%%), %d low noise, %d high noise', ...
        experimentType, stats.passedROIs, stats.totalROIs, stats.filterRate*100, ...
        stats.lowNoiseROIs, stats.highNoiseROIs);
end

function noiseLevel = classifyNoiseLevel(threshold, cfg)
    % Classify noise level based on threshold
    
    if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
        noiseLevel = 'low';
    else
        noiseLevel = 'high';
    end
end