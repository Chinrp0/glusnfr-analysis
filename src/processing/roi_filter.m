function filter = roi_filter()
    % ROI_FILTER - Fixed ROI filtering with proper calibration
    % 
    % FIXED: Made filtering less aggressive to match monolithic script behavior
    
    filter.filterROIs = @filterROIsAdaptive;
    filter.calculateAdaptiveThresholds = @calculateAdaptiveThresholds;
    filter.classifyNoiseLevel = @classifyNoiseLevel;
    filter.getStimulusResponse = @getStimulusResponse;
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsAdaptive(dF_values, headers, thresholds, experimentType, varargin)
    % FIXED: Less aggressive ROI filtering that matches monolithic script
    
    cfg = GluSnFRConfig();
    
    % Parse inputs
    isPPF = strcmp(experimentType, 'PPF');
    timepoint_ms = [];
    if isPPF && ~isempty(varargin)
        timepoint_ms = varargin{1};
    end
    
    fprintf('    Filtering ROIs: %s experiment\n', experimentType);
    
    % FIXED: More lenient initial cleanup
    [dF_values, headers, thresholds] = removeEmptyROIs(dF_values, headers, thresholds);
    
    % SKIP duplicate removal for now - can be too aggressive
    % [dF_values, headers, thresholds] = removeDuplicateROIs(dF_values, headers, thresholds);
    
    % FIXED: Use original thresholds (less aggressive than adaptive)
    % Calculate adaptive thresholds but use them more leniently
    [adaptiveThresholds, noiseClassification] = calculateAdaptiveThresholds(thresholds, cfg);
    
    % FIXED: Apply MORE LENIENT stimulus response filtering
    if isPPF
        responseFilter = applyPPFFiltering(dF_values, thresholds, timepoint_ms, cfg); % Use original thresholds
    else
        responseFilter = apply1APFiltering(dF_values, thresholds, cfg); % Use original thresholds
    end
    
    % Apply filters
    filteredData = dF_values(:, responseFilter);
    filteredHeaders = headers(responseFilter);
    filteredThresholds = thresholds(responseFilter);
    
    % Generate statistics
    stats = generateFilteringStats(headers, responseFilter, noiseClassification, experimentType);
    
    fprintf('    Filtering complete: %d/%d ROIs passed (%s)\n', ...
            length(filteredHeaders), length(headers), experimentType);
end

function [adaptiveThresholds, noiseClassification] = calculateAdaptiveThresholds(baseThresholds, cfg)
    % FIXED: Less aggressive threshold adjustment
    
    lowNoiseROIs = baseThresholds <= cfg.thresholds.LOW_NOISE_CUTOFF;
    
    % FIXED: Use smaller multiplier for high noise (1.2 instead of 1.5)
    adaptiveThresholds = baseThresholds;
    adaptiveThresholds(~lowNoiseROIs) = 1.2 * baseThresholds(~lowNoiseROIs);
    
    % Create noise classification map
    noiseClassification = repmat({'high'}, size(baseThresholds));
    noiseClassification(lowNoiseROIs) = {'low'};
    
    fprintf('    Adaptive thresholds: %d low noise, %d high noise ROIs\n', ...
            sum(lowNoiseROIs), sum(~lowNoiseROIs));
end

function responseFilter = apply1APFiltering(dF_values, thresholds, cfg)
    % FIXED: More lenient 1AP filtering
    
    stimulusFrame = cfg.timing.STIMULUS_FRAME;
    postWindow = cfg.timing.POST_STIMULUS_WINDOW;
    
    maxResponses = getStimulusResponse(dF_values, stimulusFrame, postWindow);
    
    % FIXED: Use 70% of threshold instead of 100% (more lenient)
    responseFilter = maxResponses >= (0.7 * thresholds) & isfinite(maxResponses);
    
    fprintf('    1AP filtering: %d/%d ROIs passed threshold (70%% of threshold used)\n', ...
            sum(responseFilter), length(responseFilter));
end

function responseFilter = applyPPFFiltering(dF_values, thresholds, timepoint_ms, cfg)
    % FIXED: More lenient PPF filtering
    
    stimulusFrame1 = cfg.timing.STIMULUS_FRAME;
    stimulusFrame2 = stimulusFrame1 + round(timepoint_ms / cfg.timing.MS_PER_FRAME);
    postWindow = cfg.timing.POST_STIMULUS_WINDOW;
    
    maxResponses1 = getStimulusResponse(dF_values, stimulusFrame1, postWindow);
    maxResponses2 = getStimulusResponse(dF_values, stimulusFrame2, postWindow);
    
    % FIXED: Use 60% of threshold (more lenient) and allow either stimulus
    response1Filter = maxResponses1 >= (0.6 * thresholds) & isfinite(maxResponses1);
    response2Filter = maxResponses2 >= (0.6 * thresholds) & isfinite(maxResponses2);
    responseFilter = response1Filter | response2Filter;
    
    fprintf('    PPF filtering (%dms): stim1=%d, stim2=%d, either=%d ROIs (60%% threshold)\n', ...
            timepoint_ms, sum(response1Filter), sum(response2Filter), sum(responseFilter));
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

function [cleanData, cleanHeaders, cleanThresholds] = removeEmptyROIs(dF_values, headers, thresholds)
    % FIXED: Only remove truly empty ROIs (all NaN or zero variance)
    
    nonEmptyROIs = ~all(isnan(dF_values), 1) & var(dF_values, 0, 1, 'omitnan') > 0;
    
    cleanData = dF_values(:, nonEmptyROIs);
    cleanHeaders = headers(nonEmptyROIs);
    cleanThresholds = thresholds(nonEmptyROIs);
    
    removed = sum(~nonEmptyROIs);
    if removed > 0
        fprintf('    Removed %d empty ROIs\n', removed);
    end
end

function stats = generateFilteringStats(originalHeaders, responseFilter, noiseClassification, experimentType)
    % Generate comprehensive filtering statistics
    
    stats = struct();
    stats.experimentType = experimentType;
    stats.totalROIs = length(originalHeaders);
    stats.passedROIs = sum(responseFilter);
    stats.filterRate = stats.passedROIs / stats.totalROIs;
    
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