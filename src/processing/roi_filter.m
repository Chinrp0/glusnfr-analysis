function filter = roi_filter()
    % ROI_FILTER - Enhanced with simple signal quality filtering
    % 
    % Now includes simple enhanced filtering to remove noise like ROI 19
    % while keeping real signals like ROI 29 & 32
    
    filter.filterROIs = @filterROIsMain;
    filter.filterROIsOriginal = @filterROIsOriginal;
    filter.calculateAdaptiveThresholds = @calculateAdaptiveThresholds;
    filter.classifyNoiseLevel = @classifyNoiseLevel;
    filter.getStimulusResponse = @getStimulusResponse;
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsMain(dF_values, headers, thresholds, experimentType, varargin)
    % Main filtering function - chooses between original and enhanced
    
    cfg = GluSnFRConfig();
    
    % Check if enhanced filtering is enabled
    if isfield(cfg.filtering, 'ENABLE_ENHANCED_FILTERING') && cfg.filtering.ENABLE_ENHANCED_FILTERING
        if cfg.debug.VERBOSE_FILTERING
            fprintf('    Using simple enhanced filtering\n');
        end
        
        try
            [filteredData, filteredHeaders, filteredThresholds, stats] = ...
                filterROIsEnhanced(dF_values, headers, thresholds, experimentType, varargin{:});
            stats.filtering_method = 'enhanced';
            
        catch ME
            if cfg.debug.VERBOSE_FILTERING
                fprintf('    Enhanced filtering failed (%s), using original\n', ME.message);
            end
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

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsEnhanced(dF_values, headers, thresholds, experimentType, varargin)
    % SIMPLIFIED enhanced filtering - 3 simple criteria to remove noise
    
    cfg = GluSnFRConfig();
    
    % Parse inputs
    isPPF = strcmp(experimentType, 'PPF');
    timepoint_ms = [];
    if isPPF && ~isempty(varargin)
        timepoint_ms = varargin{1};
    end
    
    if cfg.debug.VERBOSE_FILTERING
        fprintf('    Enhanced filtering: 3 simple criteria to remove noise\n');
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
        % Real signals should have clear peaks above noise
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
        % Real signals should peak within reasonable time after stimulus
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
        % Real signals should have peaks that clearly stand out
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
        if cfg.debug.VERBOSE_FILTERING
            fprintf('    WARNING: Enhanced filter removed all ROIs, using basic\n');
        end
    end
    
    % Generate enhanced stats
    stats = basicStats;
    stats.enhancement_applied = true;
    stats.basic_passed = n_rois;
    stats.enhanced_passed = sum(enhancedMask);
    stats.additional_removed = n_rois - sum(enhancedMask);
    stats.criteria_stats = criteria_stats;
    
    if cfg.debug.VERBOSE_FILTERING
        fprintf('    Enhanced: %d→%d ROIs (SNR:%d, Timing:%d, Prominence:%d)\n', ...
                n_rois, stats.enhanced_passed, ...
                criteria_stats.snr_passed, criteria_stats.timing_passed, criteria_stats.prominence_passed);
    end
end

%% ========================================================================
%% ORIGINAL FILTERING METHOD (unchanged)
%% ========================================================================

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIsOriginal(dF_values, headers, thresholds, experimentType, varargin)
    % ORIGINAL: Your existing working method (unchanged)
    
    cfg = GluSnFRConfig();
    
    % Parse inputs
    isPPF = strcmp(experimentType, 'PPF');
    timepoint_ms = [];
    if isPPF && ~isempty(varargin)
        timepoint_ms = varargin{1};
    end
    
    if cfg.debug.VERBOSE_FILTERING
        fprintf('    Filtering ROIs: %s experiment (original method)\n', experimentType);
    end
    
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
        fprintf('    Original filtering complete: %d/%d ROIs passed (%s)\n', ...
                length(filteredHeaders), length(headers), experimentType);
    end
end

function [adaptiveThresholds, noiseClassification] = calculateAdaptiveThresholds(baseThresholds, cfg)
    % Use configuration parameters instead of hardcoded values
    
    lowNoiseROIs = baseThresholds <= cfg.thresholds.LOW_NOISE_CUTOFF;
    
    adaptiveThresholds = baseThresholds;
    adaptiveThresholds(~lowNoiseROIs) = cfg.thresholds.HIGH_NOISE_MULTIPLIER * baseThresholds(~lowNoiseROIs);
    
    noiseClassification = repmat({'high'}, size(baseThresholds));
    noiseClassification(lowNoiseROIs) = {'low'};
    
    if cfg.debug.VERBOSE_FILTERING
        fprintf('    Adaptive thresholds: %d low noise, %d high noise ROIs (multiplier=%.1fx)\n', ...
                sum(lowNoiseROIs), sum(~lowNoiseROIs), cfg.thresholds.HIGH_NOISE_MULTIPLIER);
    end
end

function responseFilter = apply1APFiltering(dF_values, thresholds, cfg)
    % Use configurable threshold percentage from config
    
    stimulusFrame = cfg.timing.STIMULUS_FRAME;
    postWindow = cfg.timing.POST_STIMULUS_WINDOW;
    
    maxResponses = getStimulusResponse(dF_values, stimulusFrame, postWindow);
    
    thresholdPercentage = cfg.filtering.THRESHOLD_PERCENTAGE_1AP;
    responseFilter = maxResponses >= (thresholdPercentage * thresholds) & isfinite(maxResponses);
    
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
    % Use configurable threshold percentage from config
    
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
    % Remove empty ROIs with configurable noise threshold
    
    nonEmptyROIs = ~all(isnan(dF_values), 1) & var(dF_values, 0, 1, 'omitnan') > 0;
    
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
    % Duplicate ROI removal (placeholder - currently disabled)
    
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