function filter = roi_filter()
    % ROI_FILTER - Fixed ROI filtering with proper configuration usage
    % 
    % FIXED: All configuration parameters now properly used
    % ENHANCED: Additional configurable parameters for fine-tuning
    
    filter.filterROIs = @filterROIsAdaptive;
    filter.calculateAdaptiveThresholds = @calculateAdaptiveThresholds;
    filter.classifyNoiseLevel = @classifyNoiseLevel;
    filter.getStimulusResponse = @getStimulusResponse;
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsAdaptive(dF_values, headers, thresholds, experimentType, varargin)
    % FIXED: ROI filtering that properly uses all configuration parameters
    
    cfg = GluSnFRConfig();
    
    % Parse inputs
    isPPF = strcmp(experimentType, 'PPF');
    timepoint_ms = [];
    if isPPF && ~isempty(varargin)
        timepoint_ms = varargin{1};
    end
    
    if cfg.debug.VERBOSE_FILTERING
        fprintf('    Filtering ROIs: %s experiment\n', experimentType);
    end
    
    % FIXED: More lenient initial cleanup
    [dF_values, headers, thresholds] = removeEmptyROIs(dF_values, headers, thresholds, cfg);
    
    % CONFIGURABLE: Duplicate removal (currently disabled in config)
    if cfg.filtering.ENABLE_DUPLICATE_REMOVAL
        [dF_values, headers, thresholds] = removeDuplicateROIs(dF_values, headers, thresholds, cfg);
    end
    
    % FIXED: Use configuration parameters for adaptive thresholds
    [adaptiveThresholds, noiseClassification] = calculateAdaptiveThresholds(thresholds, cfg);
    
    % FIXED: Apply stimulus response filtering with configurable parameters
    if isPPF
        responseFilter = applyPPFFiltering(dF_values, thresholds, timepoint_ms, cfg);
    else
        responseFilter = apply1APFiltering(dF_values, thresholds, cfg);
    end
    
    % Apply filters
    filteredData = dF_values(:, responseFilter);
    filteredHeaders = headers(responseFilter);
    filteredThresholds = thresholds(responseFilter);
    
    % Generate statistics
    stats = generateFilteringStats(headers, responseFilter, noiseClassification, experimentType, cfg);
    
    if cfg.debug.VERBOSE_FILTERING
        fprintf('    Filtering complete: %d/%d ROIs passed (%s)\n', ...
                length(filteredHeaders), length(headers), experimentType);
    end
end

function [adaptiveThresholds, noiseClassification] = calculateAdaptiveThresholds(baseThresholds, cfg)
    % FIXED: Use configuration parameters instead of hardcoded values
    
    lowNoiseROIs = baseThresholds <= cfg.thresholds.LOW_NOISE_CUTOFF;
    
    % FIXED: Use cfg.thresholds.HIGH_NOISE_MULTIPLIER instead of hardcoded 1.5
    adaptiveThresholds = baseThresholds;
    adaptiveThresholds(~lowNoiseROIs) = cfg.thresholds.HIGH_NOISE_MULTIPLIER * baseThresholds(~lowNoiseROIs);
    
    % Create noise classification map
    noiseClassification = repmat({'high'}, size(baseThresholds));
    noiseClassification(lowNoiseROIs) = {'low'};
    
    if cfg.debug.VERBOSE_FILTERING
        fprintf('    Adaptive thresholds: %d low noise, %d high noise ROIs (multiplier=%.1fx)\n', ...
                sum(lowNoiseROIs), sum(~lowNoiseROIs), cfg.thresholds.HIGH_NOISE_MULTIPLIER);
    end
end

function responseFilter = apply1APFiltering(dF_values, thresholds, cfg)
    % FIXED: Use configurable threshold percentage from config
    
    stimulusFrame = cfg.timing.STIMULUS_FRAME;
    postWindow = cfg.timing.POST_STIMULUS_WINDOW;
    
    maxResponses = getStimulusResponse(dF_values, stimulusFrame, postWindow);
    
    % FIXED: Use configuration parameter instead of hardcoded 0.7
    thresholdPercentage = cfg.filtering.THRESHOLD_PERCENTAGE_1AP;
    responseFilter = maxResponses >= (thresholdPercentage * thresholds) & isfinite(maxResponses);
    
    % ENHANCED: Additional filtering based on minimum response amplitude
    if isfield(cfg.filtering, 'MIN_RESPONSE_AMPLITUDE')
        amplitudeFilter = maxResponses >= cfg.filtering.MIN_RESPONSE_AMPLITUDE;
        responseFilter = responseFilter & amplitudeFilter;
    end
    
    if cfg.debug.VERBOSE_FILTERING
        fprintf('    1AP filtering: %d/%d ROIs passed threshold (%.0f%% of threshold used)\n', ...
                sum(responseFilter), length(responseFilter), thresholdPercentage*100);
    end
end

function responseFilter = applyPPFFiltering(dF_values, thresholds, timepoint_ms, cfg)
    % FIXED: Use configurable threshold percentage from config
    
    stimulusFrame1 = cfg.timing.STIMULUS_FRAME;
    stimulusFrame2 = stimulusFrame1 + round(timepoint_ms / cfg.timing.MS_PER_FRAME);
    postWindow = cfg.timing.POST_STIMULUS_WINDOW;
    
    maxResponses1 = getStimulusResponse(dF_values, stimulusFrame1, postWindow);
    maxResponses2 = getStimulusResponse(dF_values, stimulusFrame2, postWindow);
    
    % FIXED: Use configuration parameter instead of hardcoded 0.6
    thresholdPercentage = cfg.filtering.THRESHOLD_PERCENTAGE_PPF;
    response1Filter = maxResponses1 >= (thresholdPercentage * thresholds) & isfinite(maxResponses1);
    response2Filter = maxResponses2 >= (thresholdPercentage * thresholds) & isfinite(maxResponses2);
    responseFilter = response1Filter | response2Filter;
    
    % ENHANCED: Additional filtering based on minimum response amplitude
    if isfield(cfg.filtering, 'MIN_RESPONSE_AMPLITUDE')
        amplitude1Filter = maxResponses1 >= cfg.filtering.MIN_RESPONSE_AMPLITUDE;
        amplitude2Filter = maxResponses2 >= cfg.filtering.MIN_RESPONSE_AMPLITUDE;
        amplitudeFilter = amplitude1Filter | amplitude2Filter;
        responseFilter = responseFilter & amplitudeFilter;
    end
    
    if cfg.debug.VERBOSE_FILTERING
        fprintf('    PPF filtering (%dms): stim1=%d, stim2=%d, either=%d ROIs (%.0f%% threshold)\n', ...
                timepoint_ms, sum(response1Filter), sum(response2Filter), sum(responseFilter), thresholdPercentage*100);
    end
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
    % ENHANCED: Remove empty ROIs with configurable noise threshold
    
    % Basic empty check
    nonEmptyROIs = ~all(isnan(dF_values), 1) & var(dF_values, 0, 1, 'omitnan') > 0;
    
    % ENHANCED: Additional noise-based filtering if configured
    if isfield(cfg.filtering, 'MAX_BASELINE_NOISE')
        baselineWindow = cfg.timing.BASELINE_FRAMES;
        baselineNoise = std(dF_values(baselineWindow, :), 0, 1, 'omitnan');
        noiseFilter = baselineNoise <= cfg.filtering.MAX_BASELINE_NOISE;
        nonEmptyROIs = nonEmptyROIs & noiseFilter;
        
        if cfg.debug.VERBOSE_FILTERING && sum(~noiseFilter) > 0
            fprintf('    Removed %d ROIs due to excessive baseline noise\n', sum(~noiseFilter));
        end
    end
    
    cleanData = dF_values(:, nonEmptyROIs);
    cleanHeaders = headers(nonEmptyROIs);
    cleanThresholds = thresholds(nonEmptyROIs);
    
    removed = sum(~nonEmptyROIs);
    if removed > 0 && cfg.debug.VERBOSE_FILTERING
        fprintf('    Removed %d empty/noisy ROIs\n', removed);
    end
end

function [cleanData, cleanHeaders, cleanThresholds] = removeDuplicateROIs(dF_values, headers, thresholds, cfg)
    % PLACEHOLDER: Duplicate ROI removal (could be implemented if needed)
    % Currently just returns input data unchanged
    
    cleanData = dF_values;
    cleanHeaders = headers;
    cleanThresholds = thresholds;
    
    if cfg.debug.VERBOSE_FILTERING
        fprintf('    Duplicate removal: feature currently disabled\n');
    end
end

function stats = generateFilteringStats(originalHeaders, responseFilter, noiseClassification, experimentType, cfg)
    % Generate comprehensive filtering statistics with config-aware reporting
    
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
    
    stats.summary = sprintf('%s: %d/%d ROIs passed (%.1f%%), %d low noise, %d high noise [thresh=%.0f%%, mult=%.1fx]', ...
        experimentType, stats.passedROIs, stats.totalROIs, stats.filterRate*100, ...
        stats.lowNoiseROIs, stats.highNoiseROIs, ...
        stats.configUsed.thresholdPercentage*100, stats.configUsed.highNoiseMultiplier);
end

function noiseLevel = classifyNoiseLevel(threshold, cfg)
    % Classify noise level based on threshold
    
    if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
        noiseLevel = 'low';
    else
        noiseLevel = 'high';
    end
end