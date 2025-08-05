function filter = schmitt_trigger_filter()
    % SCHMITT_TRIGGER_FILTER - ROI filtering using Schmitt trigger logic
    %
    % This implements a Schmitt trigger-based ROI filtering system that:
    % - Uses 3σ upper threshold (4.5σ for high noise ROIs)
    % - Uses 1.5σ lower threshold
    % - Filters out signals that decay below lower threshold within 1 frame
    % - Integrates with existing noise level classification
    
    filter.filterROIs = @filterROIsSchmitt;
    filter.applySchmittTrigger = @applySchmittTrigger;
    filter.classifyNoiseLevel = @classifyNoiseLevel;
    filter.calculateThresholds = @calculateSchmittThresholds;
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsSchmitt(dF_values, headers, thresholds, experimentType, varargin)
    % Main Schmitt trigger filtering function
    
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
    % IMPROVED: Calculate thresholds with option for more lenient lower threshold
    
    n_rois = length(baseThresholds);
    noiseClassification = cell(n_rois, 1);
    upperThresholds = zeros(n_rois, 1);
    lowerThresholds = zeros(n_rois, 1);
    
    % IMPROVEMENT 5: More lenient lower threshold option
    % Previous: always 0.5 (1.5σ)
    % New: configurable, default to more lenient 0.33 (1σ)
    if isfield(cfg.thresholds, 'SCHMITT_LOWER_MULTIPLIER')
        lower_multiplier = cfg.thresholds.SCHMITT_LOWER_MULTIPLIER;
    else
        lower_multiplier = 0.33;  % 1σ instead of 1.5σ - more lenient
    end
    
    for i = 1:n_rois
        threshold = baseThresholds(i);
        
        % Classify noise level
        if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
            noiseClassification{i} = 'low';
            % Low noise: 3σ upper, 1σ lower (more lenient)
            upperThresholds(i) = threshold;  % Already 3σ from dF/F calculation
            lowerThresholds(i) = threshold * lower_multiplier;  % More lenient lower threshold
        else
            noiseClassification{i} = 'high';
            % High noise: 4.0σ upper, 1σ lower (more lenient)
            upperThresholds(i) = threshold * 1.333;  % 4.0σ = 3σ * 1.333
            lowerThresholds(i) = threshold * lower_multiplier;  % More lenient lower threshold
        end
    end
end

function [passes, details] = applySchmittTrigger(trace, upperThreshold, lowerThreshold, experimentType, timepoint_ms, cfg)
    % IMPROVED: Apply Schmitt trigger logic with reduced false negatives
    
    details = struct();
    details.triggered = false;
    details.valid_signals = 0;
    details.invalid_signals = 0;
    details.signal_durations = [];
    details.debug_info = struct(); % For debugging
    
    % Define stimulus frames
    stimFrame1 = cfg.timing.STIMULUS_FRAME;
    if strcmp(experimentType, 'PPF') && ~isempty(timepoint_ms)
        stimFrame2 = stimFrame1 + round(timepoint_ms / cfg.timing.MS_PER_FRAME);
        search_windows = [stimFrame1 + 1 : stimFrame1 + 50, ...  % Window 1: 50 frames after stim1
                         stimFrame2 + 1 : min(stimFrame2 + 50, length(trace))]; % Window 2: 50 frames after stim2
    else
        search_windows = stimFrame1 + 1 : min(stimFrame1 + 50, length(trace)); % 50 frames after stimulus
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
    
    % IMPROVEMENT 1: More lenient signal duration criteria
    % Previous: signal_duration <= 1 frame was invalid
    % New: Use different criteria based on signal characteristics
    
    % IMPROVEMENT 2: Consider signal shape and decay pattern
    % Real calcium signals typically have:
    % - Fast rise (1-2 frames)
    % - Slower decay (exponential-like)
    % - Duration of 10-100ms (2-20 frames)
    
    valid_signals = 0;
    
    for i = 1:length(upper_crossings)
        crossing_frame = upper_crossings(i);
        
        % IMPROVEMENT 3: Adaptive decay analysis window
        % Use shorter window for initial analysis (50 frames = 250ms)
        decay_search_start = crossing_frame + 1;
        decay_search_end = min(crossing_frame + 50, length(trace)); % Reduced from 100 to 50
        
        if decay_search_start > length(trace)
            continue; % Can't analyze decay if at end of trace
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
            
            % IMPROVEMENT 4: More sophisticated validation criteria
            is_valid = validate_signal_characteristics(trace, crossing_frame, decay_frame, ...
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
    
    % ROI passes if it has at least one valid signal
    passes = valid_signals > 0;
end

function is_valid = validate_signal_characteristics(trace, crossing_frame, decay_frame, upperThreshold, lowerThreshold, cfg)
    % IMPROVEMENT 4: Enhanced signal validation logic
    
    signal_duration = decay_frame - crossing_frame;
    
    % Criterion 1: Minimum duration (more lenient than before)
    % Previous: duration > 1 frame (5ms)
    % New: duration > 0 frames BUT with additional quality checks
    if signal_duration <= 0
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
    if peak_amplitude < upperThreshold * 1.1  % Peak should be meaningfully above threshold
        is_valid = false;
        return;
    end
    
    % Criterion 4: Signal shape check - should have reasonable decay
    % For very short signals (1-2 frames), be more permissive
    if signal_duration <= 2
        % For very short signals, just check if they're above a reasonable amplitude
        is_valid = peak_amplitude >= upperThreshold;
        return;
    end
    
    % Criterion 5: For longer signals, check decay pattern
    % Real calcium signals should show some decay, not just noise
    first_half = signal_trace(1:ceil(length(signal_trace)/2));
    second_half = signal_trace(ceil(length(signal_trace)/2)+1:end);
    
    if ~isempty(first_half) && ~isempty(second_half)
        mean_first = mean(first_half);
        mean_second = mean(second_half);
        
        % Signal should generally decay (first half > second half)
        % But allow some tolerance for noise
        decay_ratio = mean_second / mean_first;
        if decay_ratio > 1.5  % Signal increases too much - likely noise
            is_valid = false;
            return;
        end
    end
    
    % Criterion 6: Check for excessive noise within signal
    signal_noise = std(signal_trace);
    signal_mean = mean(signal_trace);
    if signal_noise > signal_mean * 0.5 && signal_duration < 5  % Very noisy short signals
        is_valid = false;
        return;
    end
    
    % If we get here, signal passes all criteria
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
    stats.configUsed = struct();
    stats.configUsed.upper_multiplier_low_noise = 1.0;  % 3σ
    stats.configUsed.upper_multiplier_high_noise = 1.5; % 4.5σ
    stats.configUsed.lower_multiplier = 0.5;            % 1.5σ
    stats.configUsed.min_signal_duration_frames = 2;    % >1 frame
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