
%% ========================================================================
%% MODULE 2: src/processing/roi_filter.m  
%% ========================================================================

function filter = roi_filter()
    % ROI_FILTER - Advanced ROI filtering with adaptive thresholds
    %
    % This module provides sophisticated ROI filtering that adapts
    % thresholds based on noise levels and experiment type.
    
    filter.filterROIs = @filterROIsAdaptive;
    filter.calculateAdaptiveThresholds = @calculateAdaptiveThresholds;
    filter.classifyNoiseLevel = @classifyNoiseLevel;
    filter.getStimulusResponse = @getStimulusResponse;
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsAdaptive(dF_values, headers, thresholds, experimentType, varargin)
    % Advanced ROI filtering with adaptive thresholds
    %
    % INPUTS:
    %   dF_values      - dF/F data matrix (frames × ROIs)
    %   headers        - ROI names/headers
    %   thresholds     - base thresholds for each ROI
    %   experimentType - '1AP' or 'PPF'
    %   varargin       - for PPF: timepoint_ms
    
    cfg = GluSnFRConfig();
    
    % Parse inputs
    isPPF = strcmp(experimentType, 'PPF');
    timepoint_ms = [];
    if isPPF && ~isempty(varargin)
        timepoint_ms = varargin{1};
    end
    
    fprintf('    Filtering ROIs: %s experiment\n', experimentType);
    
    % Initial cleanup
    [dF_values, headers, thresholds] = removeEmptyROIs(dF_values, headers, thresholds);
    [dF_values, headers, thresholds] = removeDuplicateROIs(dF_values, headers, thresholds);
    
    % Calculate adaptive thresholds
    [adaptiveThresholds, noiseClassification] = calculateAdaptiveThresholds(thresholds, cfg);
    
    % Apply stimulus response filtering
    if isPPF
        responseFilter = applyPPFFiltering(dF_values, adaptiveThresholds, timepoint_ms, cfg);
    else
        responseFilter = apply1APFiltering(dF_values, adaptiveThresholds, cfg);
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
    % Calculate adaptive thresholds based on noise level
    
    lowNoiseROIs = baseThresholds <= cfg.thresholds.LOW_NOISE_CUTOFF;
    
    adaptiveThresholds = baseThresholds;
    adaptiveThresholds(~lowNoiseROIs) = cfg.thresholds.HIGH_NOISE_MULTIPLIER * baseThresholds(~lowNoiseROIs);
    
    % Create noise classification map
    noiseClassification = repmat({'high'}, size(baseThresholds));
    noiseClassification(lowNoiseROIs) = {'low'};
    
    fprintf('    Adaptive thresholds: %d low noise, %d high noise ROIs\n', ...
            sum(lowNoiseROIs), sum(~lowNoiseROIs));
end

function responseFilter = apply1APFiltering(dF_values, adaptiveThresholds, cfg)
    % Apply filtering for 1AP experiments
    
    stimulusFrame = cfg.timing.STIMULUS_FRAME;
    postWindow = cfg.timing.POST_STIMULUS_WINDOW;
    
    maxResponses = getStimulusResponse(dF_values, stimulusFrame, postWindow);
    responseFilter = maxResponses >= adaptiveThresholds & isfinite(maxResponses);
    
    fprintf('    1AP filtering: %d/%d ROIs passed threshold\n', ...
            sum(responseFilter), length(responseFilter));
end

function responseFilter = applyPPFFiltering(dF_values, adaptiveThresholds, timepoint_ms, cfg)
    % Apply filtering for PPF experiments
    
    stimulusFrame1 = cfg.timing.STIMULUS_FRAME;
    stimulusFrame2 = stimulusFrame1 + round(timepoint_ms / cfg.timing.MS_PER_FRAME);
    postWindow = cfg.timing.POST_STIMULUS_WINDOW;
    
    maxResponses1 = getStimulusResponse(dF_values, stimulusFrame1, postWindow);
    maxResponses2 = getStimulusResponse(dF_values, stimulusFrame2, postWindow);
    
    % PPF: pass if EITHER stimulus meets criteria
    response1Filter = maxResponses1 >= adaptiveThresholds & isfinite(maxResponses1);
    response2Filter = maxResponses2 >= adaptiveThresholds & isfinite(maxResponses2);
    responseFilter = response1Filter | response2Filter;
    
    fprintf('    PPF filtering (%dms): stim1=%d, stim2=%d, either=%d ROIs\n', ...
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
    % Remove ROIs with all NaN or empty data
    
    nonEmptyROIs = ~all(isnan(dF_values), 1);
    
    cleanData = dF_values(:, nonEmptyROIs);
    cleanHeaders = headers(nonEmptyROIs);
    cleanThresholds = thresholds(nonEmptyROIs);
    
    removed = sum(~nonEmptyROIs);
    if removed > 0
        fprintf('    Removed %d empty ROIs\n', removed);
    end
end

function [uniqueData, uniqueHeaders, uniqueThresholds] = removeDuplicateROIs(dF_values, headers, thresholds)
    % Remove duplicate ROI data
    
    if size(dF_values, 2) <= 1
        uniqueData = dF_values;
        uniqueHeaders = headers;
        uniqueThresholds = thresholds;
        return;
    end
    
    tolerance = 1e-10;
    [~, uniqueIdx] = uniquetol(dF_values', tolerance, 'ByRows', true, 'DataScale', 1);
    
    if length(uniqueIdx) < size(dF_values, 2)
        duplicates = size(dF_values, 2) - length(uniqueIdx);
        fprintf('    Removed %d duplicate ROIs\n', duplicates);
    end
    
    uniqueData = dF_values(:, uniqueIdx);
    uniqueHeaders = headers(uniqueIdx);
    uniqueThresholds = thresholds(uniqueIdx);
end

function stats = generateFilteringStats(originalHeaders, responseFilter, noiseClassification, experimentType)
    % Generate comprehensive filtering statistics
    
    stats = struct();
    stats.experimentType = experimentType;
    stats.totalROIs = length(originalHeaders);
    stats.passedROIs = sum(responseFilter);
    stats.filterRate = stats.passedROIs / stats.totalROIs;
    
    % Noise level statistics for passed ROIs
    passedNoise = noiseClassification(responseFilter);
    stats.lowNoiseROIs = sum(strcmp(passedNoise, 'low'));
    stats.highNoiseROIs = sum(strcmp(passedNoise, 'high'));
    
    stats.summary = sprintf('%s: %d/%d ROIs passed (%.1f%%), %d low noise, %d high noise', ...
        experimentType, stats.passedROIs, stats.totalROIs, stats.filterRate*100, ...
        stats.lowNoiseROIs, stats.highNoiseROIs);
end
