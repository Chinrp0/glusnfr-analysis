function filter = roi_filter()
    % ROI_FILTER - SIMPLIFIED: SD-based threshold and noise classification
    % 
    % MAJOR CHANGE: Now accepts standard deviations directly from df_calculator
    % Determines noise level based on SD, not pre-calculated thresholds
    % Calculates all thresholds from SD using configurable multipliers
    
    filter.filterROIs = @filterROIs;
    filter.applySchmittTrigger = @applySchmittTrigger;
    filter.calculateSchmittThresholds = @calculateSchmittThresholds;
    filter.calculateDisplayThreshold = @calculateDisplayThreshold; % NEW: For Excel output
end

function [filteredData, filteredHeaders, filteredStandardDeviations, stats] = filterROIs(dF_values, headers, standardDeviations, experimentType, varargin)
    % UPDATED: Main filtering function using standard deviations directly
    
    cfg = GluSnFRConfig();
    
    % Parse inputs
    isPPF = strcmp(experimentType, 'PPF');
    timepoint_ms = [];
    if isPPF && ~isempty(varargin)
        timepoint_ms = varargin{1};
    end
    
    [n_frames, n_rois] = size(dF_values);
    
    % STEP 1: Remove empty ROIs and store original mapping
    validMask = ~all(isnan(dF_values), 1) & var(dF_values, 0, 1, 'omitnan') > 0;
    originalHeaders = headers;
    originalStandardDeviations = standardDeviations;
    
    dF_values = dF_values(:, validMask);
    headers = headers(validMask);
    standardDeviations = standardDeviations(validMask);
    [~, n_rois_after_cleanup] = size(dF_values);
    
    if n_rois_after_cleanup == 0
        filteredData = [];
        filteredHeaders = {};
        filteredStandardDeviations = [];
        stats = createEmptyStats(experimentType);
        return;
    end
    
    % STEP 2: Extract ROI numbers for ALL ROIs (before and after filtering)
    cfg_temp = GluSnFRConfig();
    utils = string_utils(cfg_temp);
    originalROINumbers = utils.extractROINumbers(originalHeaders);
    cleanROINumbers = utils.extractROINumbers(headers);
    
    % STEP 3: Calculate noise levels and thresholds directly from SD
    [noiseClassification, upperThresholds, lowerThresholds, displayThresholds] = ...
        calculateSchmittThresholds(standardDeviations, cfg);
    
    % STEP 4: Apply Schmitt trigger for each ROI
    schmittMask = false(1, n_rois_after_cleanup);
    schmitt_details = cell(n_rois_after_cleanup, 1);
    
    for roi = 1:n_rois_after_cleanup
        [passes, details] = applySchmittTrigger(dF_values(:, roi), upperThresholds(roi), ...
                                              lowerThresholds(roi), experimentType, timepoint_ms, cfg);
        schmittMask(roi) = passes;
        schmitt_details{roi} = details;
    end
    
    % STEP 5: Apply filtered results
    filteredData = dF_values(:, schmittMask);
    filteredHeaders = headers(schmittMask);
    filteredStandardDeviations = standardDeviations(schmittMask);
    filteredROINumbers = cleanROINumbers(schmittMask);
    
    % STEP 6: Generate complete statistics with ROI number mapping
    stats = generateCompleteSchmittStats(originalHeaders, originalStandardDeviations, originalROINumbers, ...
                                        headers, standardDeviations, cleanROINumbers, ...
                                        filteredHeaders, filteredStandardDeviations, filteredROINumbers, ...
                                        schmittMask, noiseClassification, upperThresholds, ...
                                        lowerThresholds, displayThresholds, schmitt_details, experimentType, cfg);
    
    if cfg.debug.ENABLE_PLOT_DEBUG
        fprintf('    roi_filter: %d→%d→%d ROIs (original→clean→filtered)\n', ...
                length(originalHeaders), n_rois_after_cleanup, sum(schmittMask));
        fprintf('    roi_filter: Complete stats generated with %d ROI mappings\n', ...
                length(stats.schmitt_info.roi_number_to_data));
    end
end

function [noiseClassification, upperThresholds, lowerThresholds, displayThresholds] = calculateSchmittThresholds(standardDeviations, cfg)
    % UPDATED: Calculate thresholds directly from standard deviations
    % Noise classification based on SD, not pre-multiplied thresholds
    
    n_rois = length(standardDeviations);
    noiseClassification = cell(n_rois, 1);
    upperThresholds = zeros(n_rois, 1);
    lowerThresholds = zeros(n_rois, 1);
    displayThresholds = zeros(n_rois, 1); % For Excel output compatibility
    
    % UPDATED: Noise cutoff based on standard deviation directly
    % Old: if basicThreshold (3×SD) <= 0.02 → "low"
    % New: if SD <= 0.02/3 = 0.0067 → "low"
    %SD_NOISE_CUTOFF = cfg.thresholds.LOW_NOISE_CUTOFF / cfg.thresholds.SD_MULTIPLIER; d
    SD_NOISE_CUTOFF = cfg.thresholds.SD_NOISE_CUTOFF;
    
    for i = 1:n_rois
        sd = standardDeviations(i);
        
        % UPDATED: Classify noise level based on standard deviation
        if sd <= SD_NOISE_CUTOFF
            noiseClassification{i} = 'low';
            % Calculate thresholds from SD and multipliers
            baseThreshold = cfg.thresholds.SD_MULTIPLIER * sd; % This is the "3σ" threshold
            upperThresholds(i) = baseThreshold * cfg.filtering.schmitt.LOW_NOISE_UPPER_MULT;
            lowerThresholds(i) = baseThreshold * cfg.filtering.schmitt.LOWER_THRESHOLD_MULT;
        else
            noiseClassification{i} = 'high';
            % Calculate thresholds from SD and multipliers
            baseThreshold = cfg.thresholds.SD_MULTIPLIER * sd; % This is the "3σ" threshold
            upperThresholds(i) = baseThreshold * cfg.filtering.schmitt.HIGH_NOISE_UPPER_MULT;
            lowerThresholds(i) = baseThreshold * cfg.filtering.schmitt.LOWER_THRESHOLD_MULT;
        end
        
        % Display threshold for Excel output (traditional 3σ)
        displayThresholds(i) = cfg.thresholds.SD_MULTIPLIER * sd;
    end
    
    if cfg.debug.ENABLE_PLOT_DEBUG
        lowCount = sum(strcmp(noiseClassification, 'low'));
        highCount = sum(strcmp(noiseClassification, 'high'));
        fprintf('    Noise classification: %d low, %d high (SD cutoff: %.4f)\n', ...
                lowCount, highCount, SD_NOISE_CUTOFF);
    end
end

function displayThreshold = calculateDisplayThreshold(standardDeviation, cfg)
    % NEW: Calculate display threshold for Excel output from standard deviation
    % This provides backward compatibility for Excel files that expect "threshold" values
    
    if nargin < 2
        cfg = GluSnFRConfig();
    end
    
    displayThreshold = cfg.thresholds.SD_MULTIPLIER * standardDeviation;
end

function stats = generateCompleteSchmittStats(originalHeaders, originalStandardDeviations, originalROINumbers, ...
                                            cleanHeaders, cleanStandardDeviations, cleanROINumbers, ...
                                            filteredHeaders, filteredStandardDeviations, filteredROINumbers, ...
                                            schmittMask, noiseClassification, upperThresholds, ...
                                            lowerThresholds, displayThresholds, schmitt_details, experimentType, cfg)
    % UPDATED: Generate complete statistics using standard deviations
    
    stats = struct();
    stats.experimentType = experimentType;
    stats.method = 'Schmitt Trigger';
    stats.totalROIs = length(originalHeaders);
    stats.cleanROIs = length(cleanHeaders);
    stats.passedROIs = sum(schmittMask);
    stats.filterRate = stats.passedROIs / stats.totalROIs;
    
    % Noise level breakdown for passed ROIs only
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
    stats.trigger_rate = triggered_count / stats.cleanROIs;
    
    if triggered_count > 0
        stats.signal_validity_rate = valid_signals_total / (valid_signals_total + invalid_signals_total);
    else
        stats.signal_validity_rate = 0;
    end
    
    % UPDATED: Create complete ROI number-based data mapping with SD
    stats.schmitt_info = struct();
    stats.schmitt_info.roi_number_to_data = containers.Map('KeyType', 'int32', 'ValueType', 'any');
    
    % Map ALL clean ROIs (not just filtered ones) with their complete data
    for i = 1:length(cleanROINumbers)
        roiNum = cleanROINumbers(i);
        
        % Store complete data for this ROI
        roiData = struct();
        roiData.header = cleanHeaders{i};
        roiData.standard_deviation = cleanStandardDeviations(i); % NEW: Store SD
        roiData.display_threshold = displayThresholds(i); % NEW: For Excel compatibility
        roiData.noise_classification = noiseClassification{i};
        roiData.upper_threshold = upperThresholds(i);
        roiData.lower_threshold = lowerThresholds(i);
        roiData.passed_filtering = schmittMask(i);
        roiData.schmitt_details = schmitt_details{i};
        
        % Store in map using ROI number as key
        stats.schmitt_info.roi_number_to_data(roiNum) = roiData;
    end
    
    % UPDATED: Legacy format for backward compatibility (using display thresholds)
    stats.schmitt_info.noise_classification = noiseClassification;
    stats.schmitt_info.upper_thresholds = upperThresholds;
    stats.schmitt_info.lower_thresholds = lowerThresholds;
    stats.schmitt_info.basic_thresholds = displayThresholds; % For Excel compatibility
    stats.schmitt_info.standard_deviations = cleanStandardDeviations; % NEW: Include SDs
    stats.schmitt_info.details = schmitt_details;
    stats.schmitt_info.passed_mask = schmittMask;
    stats.schmitt_info.roi_numbers = cleanROINumbers;
    
    % Store original data for reference
    stats.original_info = struct();
    stats.original_info.headers = originalHeaders;
    stats.original_info.standard_deviations = originalStandardDeviations;
    stats.original_info.roi_numbers = originalROINumbers;
    
    % Configuration used
    stats.configUsed = cfg.filtering.schmitt;
    stats.configUsed.sdNoiseCutoff = cfg.thresholds.LOW_NOISE_CUTOFF / cfg.thresholds.SD_MULTIPLIER;
    stats.configUsed.legacyNoiseCutoff = cfg.thresholds.LOW_NOISE_CUTOFF;
    
    % Summary
    stats.summary = sprintf('%s Schmitt: %d/%d ROIs passed (%.1f%%), %d triggered, %.1f%% signals valid', ...
        experimentType, stats.passedROIs, stats.totalROIs, stats.filterRate*100, ...
        stats.triggered_rois, stats.signal_validity_rate*100);
    
    if cfg.debug.ENABLE_PLOT_DEBUG
        fprintf('    Complete stats: %d ROI mappings created with SD-based processing\n', ...
                length(stats.schmitt_info.roi_number_to_data));
        
        % Debug first few ROIs
        roiKeys = keys(stats.schmitt_info.roi_number_to_data);
        for i = 1:min(3, length(roiKeys))
            roiNum = roiKeys{i};
            roiData = stats.schmitt_info.roi_number_to_data(roiNum);
            fprintf('    ROI %d: %s noise, SD=%.4f, display_thresh=%.4f, upper=%.4f, passed=%s\n', ...
                    roiNum, roiData.noise_classification, roiData.standard_deviation, ...
                    roiData.display_threshold, roiData.upper_threshold, string(roiData.passed_filtering));
        end
    end
end

% UNCHANGED: These functions remain the same as they work with the calculated thresholds
function [passes, details] = applySchmittTrigger(trace, upperThreshold, lowerThreshold, experimentType, timepoint_ms, cfg)
    % Apply Schmitt trigger logic for signal detection - UNCHANGED
    
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
    % Enhanced signal validation using configurable parameters - UNCHANGED
    
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

function stats = createEmptyStats(experimentType)
    % Create empty stats structure for cases with no ROIs - UPDATED for SD
    
    stats = struct();
    stats.experimentType = experimentType;
    stats.method = 'Schmitt Trigger';
    stats.totalROIs = 0;
    stats.passedROIs = 0;
    stats.filterRate = 0;
    stats.summary = sprintf('%s Schmitt: No ROIs to filter', experimentType);
    
    % Empty schmitt_info structure
    stats.schmitt_info = struct();
    stats.schmitt_info.roi_number_to_data = containers.Map('KeyType', 'int32', 'ValueType', 'any');
    stats.schmitt_info.noise_classification = {};
    stats.schmitt_info.upper_thresholds = [];
    stats.schmitt_info.lower_thresholds = [];
    stats.schmitt_info.basic_thresholds = [];
    stats.schmitt_info.standard_deviations = []; % NEW: Include SDs
    stats.schmitt_info.details = {};
    stats.schmitt_info.passed_mask = logical([]);
    stats.schmitt_info.roi_numbers = [];
end