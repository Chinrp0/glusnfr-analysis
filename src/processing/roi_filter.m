function filter = roi_filter()
    % ROI_FILTER - Schmitt trigger-based ROI filtering
    % 
    % Simplified version using only Schmitt trigger method for enhanced signal detection
    
    filter.filterROIs = @filterROIs;
    filter.applySchmittTrigger = @applySchmittTrigger;
    filter.calculateSchmittThresholds = @calculateSchmittThresholds;
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIs(dF_values, headers, thresholds, experimentType, varargin)
    % Main filtering function using Schmitt trigger method
    
    cfg = GluSnFRConfig();
    
    % Parse inputs
    isPPF = strcmp(experimentType, 'PPF');
    timepoint_ms = [];
    if isPPF && ~isempty(varargin)
        timepoint_ms = varargin{1};
    end
    
    [n_frames, n_rois] = size(dF_values);
    
    % Step 1: Remove empty ROIs
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
    
    % Step 2: Calculate Schmitt trigger thresholds
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
                                upperThresholds, lowerThresholds, thresholds, ...
                                schmitt_details, experimentType, cfg);
end

function [noiseClassification, upperThresholds, lowerThresholds] = calculateSchmittThresholds(baseThresholds, cfg)
    % Calculate Schmitt trigger thresholds based on noise classification
    
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
    % Apply Schmitt trigger logic for signal detection
    
    details = struct();
    details.triggered = false;
    details.valid_signals = 0;
    details.invalid_signals = 0;
    details.signal_durations = [];
    details.debug_info = struct();
    
    % Define stimulus frames
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
            
            % Validate signal characteristics
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
    % Enhanced signal validation using configurable parameters
    
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

function stats = generateSchmittStats(headers, schmittMask, noiseClassification, ...
                                     upperThresholds, lowerThresholds, basicThresholds, ...
                                     schmitt_details, experimentType, cfg)
    % Generate comprehensive Schmitt trigger statistics
    
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
    
    % Store Schmitt info for data organizer
    stats.schmitt_info = struct();
    stats.schmitt_info.noise_classification = noiseClassification;
    stats.schmitt_info.upper_thresholds = upperThresholds;
    stats.schmitt_info.lower_thresholds = lowerThresholds;
    stats.schmitt_info.basic_thresholds = basicThresholds;
    stats.schmitt_info.details = schmitt_details;
    stats.schmitt_info.passed_mask = schmittMask;
    
    % Configuration used
    stats.configUsed = cfg.filtering.schmitt;
    stats.configUsed.lowNoiseCutoff = cfg.thresholds.LOW_NOISE_CUTOFF;
    
    % Create summary string
    stats.summary = sprintf('%s Schmitt: %d/%d ROIs passed (%.1f%%), %d triggered, %.1f%% signals valid', ...
        experimentType, stats.passedROIs, stats.totalROIs, stats.filterRate*100, ...
        stats.triggered_rois, stats.signal_validity_rate*100);
    
    if cfg.debug.ENABLE_PLOT_DEBUG
        fprintf('    Generated Schmitt stats with %d ROIs, %d noise classifications\n', ...
                length(basicThresholds), length(noiseClassification));
    end
end

function stats = createEmptyStats(experimentType)
    % Create empty stats structure for cases with no ROIs
    
    stats = struct();
    stats.experimentType = experimentType;
    stats.method = 'Schmitt Trigger';
    stats.totalROIs = 0;
    stats.passedROIs = 0;
    stats.filterRate = 0;
    stats.summary = sprintf('%s Schmitt: No ROIs to filter', experimentType);
    
    % Empty schmitt_info structure
    stats.schmitt_info = struct();
    stats.schmitt_info.noise_classification = {};
    stats.schmitt_info.upper_thresholds = [];
    stats.schmitt_info.lower_thresholds = [];
    stats.schmitt_info.basic_thresholds = [];
    stats.schmitt_info.details = {};
    stats.schmitt_info.passed_mask = logical([]);
end