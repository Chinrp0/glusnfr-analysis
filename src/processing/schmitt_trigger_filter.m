function filter = schmitt_trigger_filter()
    % SCHMITT_TRIGGER_FILTER - ROI filtering using Schmitt trigger logic
    %
    % This implements a Schmitt trigger-based ROI filtering system that:
    % - Uses configurable upper/lower thresholds
    % - Filters out signals that decay too quickly
    % - Integrates with existing noise level classification
    
    filter.filterROIs = @filterROIsSchmitt;
    filter.applySchmittTrigger = @applySchmittTrigger;
    filter.classifyNoiseLevel = @classifyNoiseLevel;
    filter.calculateThresholds = @calculateSchmittThresholds;
    filter.getParams = @getSchmittParams;
    filter.calculateSingleThreshold = @calculateSingleThreshold;
end

% ========================================================================
% CONFIGURABLE PARAMETERS - Modify these values for tuning
% ========================================================================

function params = getSchmittParams()
    params = struct();
    
    % Keep your current amplitude thresholds (they look good)
    params.LOW_NOISE_UPPER_MULT = 1.0;      % 3σ
    params.HIGH_NOISE_UPPER_MULT = 1.166;     % 3.3σ 
    params.LOWER_THRESHOLD_MULT = 0.5;      % 1.5σ
    
    % EXTEND search window for async release
    params.POST_STIM_SEARCH_FRAMES = 50;  
    params.DECAY_ANALYSIS_FRAMES = 50;      
    
    % RELAX signal validation (main issue!)
    params.MIN_SIGNAL_DURATION = 0;         % At least 2 frames (10ms) - reject 1-frame noise
    params.PEAK_AMPLITUDE_FACTOR = 1.0;    % Only 1% above threshold (was 1.05)
    params.MAX_DECAY_RATIO = 2.0;           % More lenient decay (was 2.0)
    params.SHORT_SIGNAL_THRESHOLD = 10;     % More signals get lenient validation
    
    % Very lenient quality checks
    params.MAX_NOISE_RATIO = 0.6;           % Allow noisier signals (was 0.6)
    
    % PPF parameters  
    params.PPF_WINDOW1_FRAMES = 50;        % Extend these too
    params.PPF_WINDOW2_FRAMES = 50;
end

% ========================================================================
% MAIN FILTERING FUNCTIONS
% ========================================================================

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsSchmitt(dF_values, headers, thresholds, experimentType, varargin)
    % Main Schmitt trigger filtering function
    
    cfg = GluSnFRConfig();
    params = getSchmittParams();
    
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
    [noiseClassification, upperThresholds, lowerThresholds] = calculateSchmittThresholds(thresholds, cfg, params);
    
    % Step 3: Apply Schmitt trigger for each ROI
    schmittMask = false(1, n_rois_after_cleanup);
    schmitt_details = cell(n_rois_after_cleanup, 1);
    
    for roi = 1:n_rois_after_cleanup
        [passes, details] = applySchmittTrigger(dF_values(:, roi), upperThresholds(roi), ...
                                              lowerThresholds(roi), experimentType, timepoint_ms, cfg, params);
        schmittMask(roi) = passes;
        schmitt_details{roi} = details;
    end
    
    % Step 4: Apply filtered results
    filteredData = dF_values(:, schmittMask);
    filteredHeaders = headers(schmittMask);
    filteredThresholds = thresholds(schmittMask);
    
    % Step 5: Generate statistics
    stats = generateSchmittStats(headers, schmittMask, noiseClassification, ...
                                schmitt_details, experimentType, cfg, params);
    
    % Add Schmitt-specific information
    stats.schmitt_info = struct();
    stats.schmitt_info.upper_thresholds = upperThresholds;
    stats.schmitt_info.lower_thresholds = lowerThresholds;
    stats.schmitt_info.noise_classification = noiseClassification;
    stats.schmitt_info.details = schmitt_details;
    stats.schmitt_info.params_used = params;
end

function [noiseClassification, upperThresholds, lowerThresholds] = calculateSchmittThresholds(baseThresholds, cfg, params)
    % Calculate thresholds using configurable parameters
    
    n_rois = length(baseThresholds);
    noiseClassification = cell(n_rois, 1);
    upperThresholds = zeros(n_rois, 1);
    lowerThresholds = zeros(n_rois, 1);
    
    for i = 1:n_rois
        threshold = baseThresholds(i);
        
        % Classify noise level
        if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
            noiseClassification{i} = 'low';
            upperThresholds(i) = threshold * params.LOW_NOISE_UPPER_MULT;
            lowerThresholds(i) = threshold * params.LOWER_THRESHOLD_MULT;
        else
            noiseClassification{i} = 'high';
            upperThresholds(i) = threshold * params.HIGH_NOISE_UPPER_MULT;
            lowerThresholds(i) = threshold * params.LOWER_THRESHOLD_MULT;
        end
    end
end

function [passes, details] = applySchmittTrigger(trace, upperThreshold, lowerThreshold, experimentType, timepoint_ms, cfg, params)
    % Apply Schmitt trigger logic with configurable parameters
    
    % Handle optional params argument for backward compatibility
    if nargin < 7 || isempty(params)
        params = getSchmittParams();
    end
    
    details = struct();
    details.triggered = false;
    details.valid_signals = 0;
    details.invalid_signals = 0;
    details.signal_durations = [];
    details.debug_info = struct();
    
    % Define stimulus frames using configurable parameters
    stimFrame1 = cfg.timing.STIMULUS_FRAME;
    if strcmp(experimentType, 'PPF') && ~isempty(timepoint_ms)
        stimFrame2 = stimFrame1 + round(timepoint_ms / cfg.timing.MS_PER_FRAME);
        search_windows = [stimFrame1 + 1 : stimFrame1 + params.PPF_WINDOW1_FRAMES, ...
                         stimFrame2 + 1 : min(stimFrame2 + params.PPF_WINDOW2_FRAMES, length(trace))];
    else
        search_windows = stimFrame1 + 1 : min(stimFrame1 + params.POST_STIM_SEARCH_FRAMES, length(trace));
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
        decay_search_end = min(crossing_frame + params.DECAY_ANALYSIS_FRAMES, length(trace));
        
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
            is_valid = validate_signal_characteristics(trace, crossing_frame, decay_frame, ...
                                                     upperThreshold, lowerThreshold, params);
            
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

function is_valid = validate_signal_characteristics(trace, crossing_frame, decay_frame, upperThreshold, lowerThreshold, params)
    % Enhanced signal validation using ONLY configurable parameters - NO MAGIC NUMBERS
    
    signal_duration = decay_frame - crossing_frame;
    
    % Criterion 1: Minimum duration check (uses params)
    if signal_duration <= params.MIN_SIGNAL_DURATION
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
    
    % Criterion 3: Peak amplitude check (ALWAYS uses params.PEAK_AMPLITUDE_FACTOR)
    peak_amplitude = max(signal_trace);
    if peak_amplitude < upperThreshold * params.PEAK_AMPLITUDE_FACTOR
        is_valid = false;
        return;
    end
    
    % Criterion 4: For short signals, use lenient validation (uses params.SHORT_SIGNAL_THRESHOLD)
    if signal_duration <= params.SHORT_SIGNAL_THRESHOLD
        % For short signals, only require peak amplitude check (already passed above)
        is_valid = true;
        return;
    end
    
    % Criterion 5: For longer signals, check decay pattern (uses params.MAX_DECAY_RATIO)
    first_half = signal_trace(1:ceil(length(signal_trace)/2));
    second_half = signal_trace(ceil(length(signal_trace)/2)+1:end);
    
    if ~isempty(first_half) && ~isempty(second_half)
        mean_first = mean(first_half);
        mean_second = mean(second_half);
        
        decay_ratio = mean_second / mean_first;
        if decay_ratio > params.MAX_DECAY_RATIO
            is_valid = false;
            return;
        end
    end
    
    % Criterion 6: Check for excessive noise (uses params.MAX_NOISE_RATIO and params.SHORT_SIGNAL_THRESHOLD)
    signal_noise = std(signal_trace);
    signal_mean = mean(signal_trace);
    if signal_noise > signal_mean * params.MAX_NOISE_RATIO && signal_duration < params.SHORT_SIGNAL_THRESHOLD
        is_valid = false;
        return;
    end
    
    is_valid = true;
end

% ========================================================================
% SUPPORTING FUNCTIONS (unchanged)
% ========================================================================

function stats = generateSchmittStats(headers, schmittMask, noiseClassification, schmitt_details, experimentType, cfg, params)
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
    
    % Configuration used (now from parameters)
    stats.configUsed = params;
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

function [noiseLabel, upperThresh, lowerThresh] = calculateSingleThreshold(baseThreshold, cfg, params)
    % Calculate Schmitt thresholds for a single ROI using centralized parameters
    % This ensures plotting functions use the same logic as filtering
    
    if nargin < 3
        params = getSchmittParams();
    end
    
    if baseThreshold <= cfg.thresholds.LOW_NOISE_CUTOFF
        noiseLabel = 'Low';
        upperThresh = baseThreshold * params.LOW_NOISE_UPPER_MULT;
        lowerThresh = baseThreshold * params.LOWER_THRESHOLD_MULT;
    else
        noiseLabel = 'High';
        upperThresh = baseThreshold * params.HIGH_NOISE_UPPER_MULT;
        lowerThresh = baseThreshold * params.LOWER_THRESHOLD_MULT;
    end
end