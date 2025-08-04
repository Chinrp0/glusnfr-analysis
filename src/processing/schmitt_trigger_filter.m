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
    % Calculate upper and lower thresholds for Schmitt trigger
    
    n_rois = length(baseThresholds);
    noiseClassification = cell(n_rois, 1);
    upperThresholds = zeros(n_rois, 1);
    lowerThresholds = zeros(n_rois, 1);
    
    for i = 1:n_rois
        threshold = baseThresholds(i);
        
        % Classify noise level
        if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
            noiseClassification{i} = 'low';
            % Low noise: 3σ upper, 1.5σ lower
            upperThresholds(i) = threshold;  % Already 3σ from dF/F calculation
            lowerThresholds(i) = threshold * 0.5;  % 1.5σ = 3σ * 0.5
        else
            noiseClassification{i} = 'high';
            % High noise: 4.5σ upper, 1.5σ lower  
            upperThresholds(i) = threshold * 1.5;  % 4.5σ = 3σ * 1.5
            lowerThresholds(i) = threshold * 0.5;  % 1.5σ = 3σ * 0.5
        end
    end
end

function [passes, details] = applySchmittTrigger(trace, upperThreshold, lowerThreshold, experimentType, timepoint_ms, cfg)
    % Apply Schmitt trigger logic to single ROI trace
    
    details = struct();
    details.triggered = false;
    details.valid_signals = 0;
    details.invalid_signals = 0;
    details.signal_durations = [];
    
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
    
    % For each upper threshold crossing, check if signal is valid
    valid_signals = 0;
    
    for i = 1:length(upper_crossings)
        crossing_frame = upper_crossings(i);
        
        % Find when signal decays below lower threshold
        decay_search_start = crossing_frame + 1;
        decay_search_end = min(crossing_frame + 100, length(trace)); % Search up to 100 frames (500ms)
        
        if decay_search_start > length(trace)
            continue; % Can't analyze decay if at end of trace
        end
        
        % Find first frame where signal drops below lower threshold
        below_lower = find(trace(decay_search_start:decay_search_end) < lowerThreshold, 1);
        
        if isempty(below_lower)
            % Signal never decays below lower threshold - valid signal
            signal_duration = decay_search_end - crossing_frame;
            valid_signals = valid_signals + 1;
            details.signal_durations(end+1) = signal_duration;
        else
            % Signal decays below lower threshold
            decay_frame = decay_search_start + below_lower - 1;
            signal_duration = decay_frame - crossing_frame;
            
            if signal_duration <= 1
                % Signal decays within 1 frame (5ms) - invalid
                details.invalid_signals = details.invalid_signals + 1;
            else
                % Signal lasts more than 1 frame - valid
                valid_signals = valid_signals + 1;
                details.signal_durations(end+1) = signal_duration;
            end
        end
    end
    
    details.valid_signals = valid_signals;
    
    % ROI passes if it has at least one valid signal
    passes = valid_signals > 0;
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