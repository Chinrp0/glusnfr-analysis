function enhanced_filter = enhanced_filtering_system()
    % ENHANCED_FILTERING_SYSTEM - Advanced ROI filtering optimized for iGlu3Fast
    % 
    % This module provides enhanced filtering with temporal validation,
    % kinetic analysis, and comparison with original filtering methods.
    % Optimized for iGlu3Fast ultrafast glutamate sensor kinetics.
    
    enhanced_filter.filterROIs = @filterROIs;
    enhanced_filter.compareFilteringMethods = @compareFilteringMethods;
    enhanced_filter.validateTemporalCharacteristics = @validateTemporalCharacteristics;
    enhanced_filter.analyzeSignalKinetics = @analyzeSignalKinetics;
    enhanced_filter.calculateTrialConsistency = @calculateTrialConsistency;
    enhanced_filter.optimizeFilteringParameters = @optimizeFilteringParameters;
end

function [filteredData, filteredHeaders, filteredThresholds, stats] = filterROIs(dF_values, headers, thresholds, experimentType, varargin)
    % Enhanced ROI filtering with temporal validation and kinetic analysis
    % Optimized for iGlu3Fast ultrafast kinetics
    
    p = inputParser;
    addParameter(p, 'EnableTemporalValidation', true, @islogical);
    addParameter(p, 'EnableKineticAnalysis', true, @islogical);
    addParameter(p, 'EnableConsistencyCheck', false, @islogical);  % Requires multiple trials
    addParameter(p, 'Verbose', true, @islogical);
    addParameter(p, 'PPFTimepoint', [], @isnumeric);
    parse(p, varargin{:});
    
    cfg = getConfig();  % iGlu3Fast optimized parameters
    
    if p.Results.Verbose
        fprintf('    Enhanced filtering (iGlu3Fast optimized):\n');
        fprintf('      Temporal validation: %s\n', string(p.Results.EnableTemporalValidation));
        fprintf('      Kinetic analysis: %s\n', string(p.Results.EnableKineticAnalysis));
    end
    
    % Start with basic filtering (your original method)
    filter_module = roi_filter();  % FIXED: Changed variable name
    [basicFiltered, basicHeaders, basicThresholds, basicStats] = ...
        filter_module.filterROIs(dF_values, headers, thresholds, experimentType, p.Results.PPFTimepoint);
    
    if isempty(basicFiltered)
        % Return empty if basic filtering removes everything
        filteredData = basicFiltered;
        filteredHeaders = basicHeaders;
        filteredThresholds = basicThresholds;
        stats = basicStats;
        stats.enhancement_applied = false;
        return;
    end
    
    % Enhanced filtering stages
    [n_frames, n_rois] = size(basicFiltered);
    enhancedMask = true(1, n_rois);  % Start with all ROIs from basic filtering
    
    stats = basicStats;
    stats.enhancement_applied = true;
    stats.temporal_validation = struct();
    stats.kinetic_analysis = struct();
    stats.filtering_stages = struct();
    
    % Stage 1: Temporal characteristics validation
    if p.Results.EnableTemporalValidation
        temporalMask = validateAllROIsTemporalCharacteristics(basicFiltered, basicHeaders, cfg, experimentType, p.Results.PPFTimepoint);
        enhancedMask = enhancedMask & temporalMask;
        
        stats.temporal_validation.total_rois = n_rois;
        stats.temporal_validation.passed_temporal = sum(temporalMask);
        stats.temporal_validation.temporal_pass_rate = sum(temporalMask) / n_rois;
        
        if p.Results.Verbose
            fprintf('      Temporal validation: %d/%d ROIs passed (%.1f%%)\n', ...
                    sum(temporalMask), n_rois, sum(temporalMask)/n_rois*100);
        end
    end
    
    % Stage 2: Kinetic analysis (iGlu3Fast specific)
    if p.Results.EnableKineticAnalysis
        kineticMask = validateKineticCharacteristics(basicFiltered, basicHeaders, cfg, experimentType);
        enhancedMask = enhancedMask & kineticMask;
        
        stats.kinetic_analysis.total_rois = sum(enhancedMask & ~kineticMask) + sum(kineticMask);
        stats.kinetic_analysis.passed_kinetic = sum(kineticMask);
        stats.kinetic_analysis.kinetic_pass_rate = sum(kineticMask) / stats.kinetic_analysis.total_rois;
        
        if p.Results.Verbose
            fprintf('      Kinetic validation: %d/%d ROIs passed (%.1f%%)\n', ...
                    sum(kineticMask), stats.kinetic_analysis.total_rois, ...
                    stats.kinetic_analysis.kinetic_pass_rate*100);
        end
    end
    
    % Apply final filtering
    if any(enhancedMask)
        filteredData = basicFiltered(:, enhancedMask);
        filteredHeaders = basicHeaders(enhancedMask);
        filteredThresholds = basicThresholds(enhancedMask);
        
        stats.filtering_stages.basic_pass = n_rois;
        stats.filtering_stages.pass = sum(enhancedMask);
        stats.filtering_stages.rate = sum(enhancedMask) / n_rois;
        stats.filtering_stages.additional_filtering = n_rois - sum(enhancedMask);
        
    else
        % If enhanced filtering removes everything, fall back to basic filtering
        filteredData = basicFiltered;
        filteredHeaders = basicHeaders;
        filteredThresholds = basicThresholds;
        
        stats.filtering_stages.fallback_to_basic = true;
        
        if p.Results.Verbose
            fprintf('      WARNING: Enhanced filtering removed all ROIs, using basic filtering\n');
        end
    end
    
    % Final statistics
    stats.final_summary = sprintf('Enhanced: %d→%d ROIs (%s)', ...
        length(headers), length(filteredHeaders), experimentType);
    
    if p.Results.Verbose
        fprintf('      %s\n', stats.final_summary);
    end
end

function comparison = compareFilteringMethods(dF_values, headers, thresholds, experimentType, varargin)
    % Compare original vs enhanced filtering methods
    
    p = inputParser;
    addParameter(p, 'PlotResults', true, @islogical);
    addParameter(p, 'SaveResults', false, @islogical);
    addParameter(p, 'PPFTimepoint', [], @isnumeric);
    addParameter(p, 'AnalyzeKnownResponders', [], @isnumeric);  % ROI numbers known to respond
    parse(p, varargin{:});
    
    fprintf('\n=== Filtering Methods Comparison ===\n');
    fprintf('Dataset: %d frames × %d ROIs (%s)\n', size(dF_values, 1), size(dF_values, 2), experimentType);
    
    % Run original filtering
    fprintf('1. Running original filtering...\n');
    filter_module = roi_filter();  % FIXED: Changed variable name
    [originalFiltered, originalHeaders, originalThresholds, originalStats] = ...
        filter_module.filterROIs(dF_values, headers, thresholds, experimentType, p.Results.PPFTimepoint);
    
    % Run enhanced filtering
    fprintf('2. Running enhanced filtering...\n');
    enhanced_filter_instance = enhanced_filtering_system();
    [filteredData, filteredHeaders, filteredThresholds, stats] = ...
        enhanced_filter_instance.filterROIs(dF_values, headers, thresholds, experimentType, ...
        'PPFTimepoint', p.Results.PPFTimepoint, 'Verbose', false);
    
    % Analysis
    comparison = struct();
    comparison.original = struct('count', length(originalHeaders), 'headers', originalHeaders, 'stats', originalStats);
    comparison.enhanced = struct('count', length(filteredHeaders), 'headers', filteredHeaders, 'stats', stats);
    
    % ROI overlap analysis
    [comparison.overlap, comparison.original_only, comparison.enhanced_only] = analyzeROIOverlap(originalHeaders, filteredHeaders);
    
    % Known responder analysis (if provided)
    if ~isempty(p.Results.AnalyzeKnownResponders)
        comparison.known_responders = analyzeKnownResponders(p.Results.AnalyzeKnownResponders, originalHeaders, filteredHeaders);
    end
    
    % Performance metrics
    comparison.metrics = struct();
    comparison.metrics.selectivity_improvement = (length(originalHeaders) - length(filteredHeaders)) / length(originalHeaders);
    comparison.metrics.additional_filtering_rate = length(comparison.enhanced_only) / length(originalHeaders);
    
    % Display results
    fprintf('\n=== Comparison Results ===\n');
    fprintf('Original filtering: %d ROIs\n', comparison.original.count);
    fprintf('Enhanced filtering: %d ROIs\n', comparison.enhanced.count);
    fprintf('Overlap: %d ROIs\n', length(comparison.overlap));
    fprintf('Original only: %d ROIs\n', length(comparison.original_only));
    fprintf('Enhanced only: %d ROIs\n', length(comparison.enhanced_only));
    fprintf('Selectivity improvement: %.1f%% (enhanced removes %.1f%% more)\n', ...
            comparison.metrics.selectivity_improvement*100, abs(comparison.metrics.selectivity_improvement)*100);
    
    % HIGHLIGHT THE ROIs THAT ENHANCED FILTER REMOVES
    if ~isempty(comparison.original_only)
        fprintf('\n=== ROIs REMOVED by Enhanced Filter ===\n');
        fprintf('These %d ROIs passed original filtering but failed enhanced:\n', length(comparison.original_only));
        for i = 1:length(comparison.original_only)
            fprintf('  ROI %d\n', comparison.original_only(i));
        end
        fprintf('(These are potential false positives caught by enhanced filtering)\n');
    end
    
    if ~isempty(p.Results.AnalyzeKnownResponders)
        fprintf('\nKnown Responders Analysis:\n');
        fprintf('  Known responders provided: %d\n', length(p.Results.AnalyzeKnownResponders));
        fprintf('  Original method detected: %d/%d (%.1f%%)\n', ...
                comparison.known_responders.original_detected, length(p.Results.AnalyzeKnownResponders), ...
                comparison.known_responders.original_detection_rate*100);
        fprintf('  Enhanced method detected: %d/%d (%.1f%%)\n', ...
                comparison.known_responders.detected, length(p.Results.AnalyzeKnownResponders), ...
                comparison.known_responders.detection_rate*100);
    end
    
    % Generate plots
    if p.Results.PlotResults
        plotFilteringComparison(dF_values, headers, originalHeaders, filteredHeaders, comparison, experimentType);
    end
    
    % Generate recommendations
    generateFilteringRecommendations(comparison);
end

function temporalMask = validateAllROIsTemporalCharacteristics(dF_values, headers, cfg, experimentType, ppfTimepoint)
    % Validate temporal characteristics for all ROIs
    
    [n_frames, n_rois] = size(dF_values);
    temporalMask = false(1, n_rois);
    
    for roi = 1:n_rois
        dF_trace = dF_values(:, roi);
        temporalMask(roi) = validateTemporalCharacteristics(dF_trace, cfg, experimentType, ppfTimepoint);
    end
end

function isValid = validateTemporalCharacteristics(dF_trace, cfg, experimentType, ppfTimepoint)
    % Validate temporal characteristics optimized for iGlu3Fast kinetics
    
    stimFrame = cfg.timing.STIMULUS_FRAME;
    
    if strcmp(experimentType, 'PPF') && ~isempty(ppfTimepoint)
        % PPF analysis with two stimuli
        stimFrame2 = stimFrame + round(ppfTimepoint / cfg.timing.MS_PER_FRAME);
        isValid = validatePPFTemporalCharacteristics(dF_trace, stimFrame, stimFrame2, cfg);
    else
        % 1AP analysis
        isValid = validate1APTemporalCharacteristics(dF_trace, stimFrame, cfg);
    end
end

function isValid = validate1APTemporalCharacteristics(dF_trace, stimFrame, cfg)
    % Validate 1AP temporal characteristics for iGlu3Fast
    
    % Find response window - iGlu3Fast has faster kinetics
    postStimWindow = stimFrame + (1:cfg.filtering.RESPONSE_WINDOW_FRAMES);
    postStimWindow = postStimWindow(postStimWindow <= length(dF_trace));
    
    if isempty(postStimWindow)
        isValid = false;
        return;
    end
    
    % Find peak response
    [peak_value, peak_idx] = max(dF_trace(postStimWindow));
    peak_frame = postStimWindow(peak_idx);
    
    % Check minimum amplitude
    if peak_value < cfg.filtering.MIN_RESPONSE_AMPLITUDE
        isValid = false;
        return;
    end
    
    % Check rise time (iGlu3Fast should be faster)
    rise_time_ms = (peak_frame - stimFrame) * cfg.timing.MS_PER_FRAME;
    if rise_time_ms < cfg.filtering.MIN_RISE_TIME_MS || rise_time_ms > cfg.filtering.MAX_RISE_TIME_MS
        isValid = false;
        return;
    end
    
    % Check decay characteristics (iGlu3Fast decays much faster)
    decayValid = validateDecayCharacteristics(dF_trace, peak_frame, cfg);
    if ~decayValid
        isValid = false;
        return;
    end
    
    % Check signal-to-noise ratio in response window
    baseline_window = 1:min(stimFrame-1, cfg.timing.BASELINE_FRAMES(end));
    baseline_noise = std(dF_trace(baseline_window));
    snr = peak_value / baseline_noise;
    
    if snr < cfg.filtering.MIN_SNR
        isValid = false;
        return;
    end
    
    isValid = true;
end

function isValid = validatePPFTemporalCharacteristics(dF_trace, stimFrame1, stimFrame2, cfg)
    % Validate PPF temporal characteristics
    
    % Validate first stimulus response
    valid1 = validate1APTemporalCharacteristics(dF_trace, stimFrame1, cfg);
    
    % Validate second stimulus response (if present)
    postStim2Window = stimFrame2 + (1:cfg.filtering.RESPONSE_WINDOW_FRAMES);
    postStim2Window = postStim2Window(postStim2Window <= length(dF_trace));
    
    valid2 = false;
    if ~isempty(postStim2Window)
        [peak_value2, ~] = max(dF_trace(postStim2Window));
        if peak_value2 > cfg.filtering.MIN_RESPONSE_AMPLITUDE
            valid2 = true;
        end
    end
    
    % PPF ROI should respond to at least one stimulus
    isValid = valid1 || valid2;
end

function isValid = validateDecayCharacteristics(dF_trace, peakFrame, cfg)
    % Validate decay characteristics specific to iGlu3Fast ultrafast kinetics
    
    % iGlu3Fast decay time constant ≈ 3.3ms (1/304 s^-1)
    expectedDecayFrames = round(cfg.filtering.EXPECTED_DECAY_TIME_MS / cfg.timing.MS_PER_FRAME);
    
    % Check decay window
    decayWindow = peakFrame + (1:min(expectedDecayFrames*3, length(dF_trace)-peakFrame));
    if length(decayWindow) < expectedDecayFrames
        isValid = false;
        return;
    end
    
    decayTrace = dF_trace(decayWindow);
    peakValue = dF_trace(peakFrame);
    
    % Check that signal decays (shouldn't increase significantly after peak)
    if any(decayTrace > peakValue * 1.2)  % Allow 20% noise above peak
        isValid = false;
        return;
    end
    
    % Check decay rate is reasonable (should drop to ~37% within decay constant)
    halfDecayIdx = min(expectedDecayFrames, length(decayTrace));
    if halfDecayIdx > 1
        decayRatio = decayTrace(halfDecayIdx) / peakValue;
        if decayRatio > cfg.filtering.MAX_DECAY_RATIO
            isValid = false;
            return;
        end
    end
    
    isValid = true;
end

function kineticMask = validateKineticCharacteristics(dF_values, headers, cfg, experimentType)
    % Advanced kinetic analysis for iGlu3Fast characteristics
    
    [n_frames, n_rois] = size(dF_values);
    kineticMask = false(1, n_rois);
    
    for roi = 1:n_rois
        dF_trace = dF_values(:, roi);
        kineticMask(roi) = analyzeSignalKinetics(dF_trace, cfg);
    end
end

function isValid = analyzeSignalKinetics(dF_trace, cfg)
    % Analyze individual ROI kinetics for iGlu3Fast compatibility
    
    stimFrame = cfg.timing.STIMULUS_FRAME;
    postStimWindow = stimFrame + (1:cfg.filtering.RESPONSE_WINDOW_FRAMES);
    postStimWindow = postStimWindow(postStimWindow <= length(dF_trace));
    
    if isempty(postStimWindow)
        isValid = false;
        return;
    end
    
    % Find peak
    [peakValue, peakIdx] = max(dF_trace(postStimWindow));
    peakFrame = postStimWindow(peakIdx);
    
    if peakValue < cfg.filtering.MIN_RESPONSE_AMPLITUDE
        isValid = false;
        return;
    end
    
    % Analyze rise phase (should be fast for iGlu3Fast)
    risePhase = dF_trace(stimFrame:peakFrame);
    riseRate = (peakValue - dF_trace(stimFrame)) / length(risePhase);
    
    if riseRate < cfg.filtering.MIN_RISE_RATE
        isValid = false;
        return;
    end
    
    % Analyze decay phase (should be very fast for iGlu3Fast)
    maxDecayFrames = min(cfg.filtering.MAX_DECAY_FRAMES, length(dF_trace) - peakFrame);
    if maxDecayFrames > 0
        decayPhase = dF_trace(peakFrame:peakFrame+maxDecayFrames);
        
        % Fit exponential decay and check time constant
        try
            decayTimeConstant = fitDecayTimeConstant(decayPhase, cfg.timing.MS_PER_FRAME);
            if decayTimeConstant > cfg.filtering.MAX_DECAY_TIME_CONSTANT_MS
                isValid = false;
                return;
            end
        catch
            % If fitting fails, use simple decay check
            endValue = decayPhase(end);
            decayRatio = endValue / peakValue;
            if decayRatio > cfg.filtering.MAX_DECAY_RATIO
                isValid = false;
                return;
            end
        end
    end
    
    isValid = true;
end

function timeConstant = fitDecayTimeConstant(decayTrace, msPerFrame)
    % Fit exponential decay and return time constant in ms
    
    % Simple exponential fit: y = A * exp(-t/tau)
    t = (0:length(decayTrace)-1) * msPerFrame;
    y = decayTrace / decayTrace(1);  % Normalize
    
    % Fit using linear regression on log scale
    validIdx = y > 0.1 & isfinite(log(y));  % Avoid log of very small/zero values
    if sum(validIdx) < 3
        error('Insufficient data for decay fitting');
    end
    
    t_fit = t(validIdx);
    log_y_fit = log(y(validIdx));
    
    % Linear fit: log(y) = log(A) - t/tau
    p = polyfit(t_fit, log_y_fit, 1);
    timeConstant = -1 / p(1);  % tau = -1/slope
end

function [overlap, original_only, enhanced_only] = analyzeROIOverlap(originalHeaders, filteredHeaders)
    % Analyze overlap between filtering methods
    
    % Extract ROI numbers
    originalROIs = extractROINumbers(originalHeaders);
    filteredROIs = extractROINumbers(filteredHeaders);
    
    overlap = intersect(originalROIs, filteredROIs);
    original_only = setdiff(originalROIs, filteredROIs);
    enhanced_only = setdiff(filteredROIs, originalROIs);
end

function roiNumbers = extractROINumbers(headers)
    % Extract ROI numbers from headers
    
    roiNumbers = [];
    for i = 1:length(headers)
        matches = regexp(headers{i}, 'ROI\s*(\d+)', 'tokens', 'ignorecase');
        if ~isempty(matches)
            roiNumbers(end+1) = str2double(matches{1}{1});
        end
    end
end

function known_analysis = analyzeKnownResponders(knownROIs, originalHeaders, filteredHeaders)
    % Analyze detection of known responding ROIs
    
    originalROIs = extractROINumbers(originalHeaders);
    filteredROIs = extractROINumbers(filteredHeaders);
    
    known_analysis = struct();
    known_analysis.original_detected = sum(ismember(knownROIs, originalROIs));
    known_analysis.detected = sum(ismember(knownROIs, filteredROIs));
    known_analysis.original_detection_rate = known_analysis.original_detected / length(knownROIs);
    known_analysis.detection_rate = known_analysis.detected / length(knownROIs);
    known_analysis.missed_by_original = setdiff(knownROIs, originalROIs);
    known_analysis.missed_by_enhanced = setdiff(knownROIs, filteredROIs);
end

function plotFilteringComparison(dF_values, headers, originalHeaders, filteredHeaders, comparison, experimentType)
    % Create comprehensive filtering comparison plots
    
    figure('Position', [100, 100, 1600, 1200], 'Name', 'Enhanced Filtering Comparison');
    
    time_ms = (0:size(dF_values, 1)-1) * 5;  % 5ms per frame
    
    % Get ROI categories
    originalROIs = extractROINumbers(originalHeaders);
    filteredROIs = extractROINumbers(filteredHeaders);
    
    % Plot examples from each category
    plotROICategory(dF_values, headers, comparison.overlap, time_ms, 1, 'Both Methods Passed', 'green');
    plotROICategory(dF_values, headers, comparison.original_only, time_ms, 2, 'Original Only (False Positives?)', 'red');
    plotROICategory(dF_values, headers, comparison.enhanced_only, time_ms, 3, 'Enhanced Only', 'orange');
    
    % Summary statistics
    subplot(2, 3, 4);
    categories = {'Overlap', 'Original Only', 'Enhanced Only'};
    counts = [length(comparison.overlap), length(comparison.original_only), length(comparison.enhanced_only)];
    colors = [0.2 0.8 0.2; 0.8 0.2 0.2; 0.8 0.5 0.2];
    
    bar(counts, 'FaceColor', 'flat', 'CData', colors);
    set(gca, 'XTickLabel', categories, 'XTickLabelRotation', 45);
    title('ROI Count by Category');
    ylabel('Number of ROIs');
    grid on;
    
    % ROI distribution
    subplot(2, 3, 5);
    allROIs = extractROINumbers(headers);
    originalMask = ismember(allROIs, originalROIs);
    filteredMask = ismember(allROIs, filteredROIs);
    
    scatter(allROIs(originalMask & filteredMask), ones(sum(originalMask & filteredMask), 1)*3, 50, 'g', 'filled', 'DisplayName', 'Both');
    hold on;
    scatter(allROIs(originalMask & ~filteredMask), ones(sum(originalMask & ~filteredMask), 1)*2, 50, 'r', 'filled', 'DisplayName', 'Original Only');
    scatter(allROIs(~originalMask & filteredMask), ones(sum(~originalMask & filteredMask), 1)*1, 50, 'b', 'filled', 'DisplayName', 'Enhanced Only');
    
    xlabel('ROI Number');
    ylabel('Method');
    title('ROI Selection by Method');
    legend('Location', 'best');
    ylim([0.5, 3.5]);
    set(gca, 'YTick', [1, 2, 3], 'YTickLabel', {'Enhanced Only', 'Original Only', 'Both'});
    grid on;
    
    % Performance metrics
    subplot(2, 3, 6);
    metrics = [comparison.original.count, comparison.enhanced.count, length(comparison.overlap)];
    metric_names = {'Original', 'Enhanced', 'Overlap'};
    
    bar(metrics, 'FaceColor', [0.7, 0.7, 0.7]);
    set(gca, 'XTickLabel', metric_names);
    title('Method Performance');
    ylabel('ROI Count');
    grid on;
    
    sgtitle(sprintf('Enhanced Filtering Analysis - %s', experimentType), 'FontSize', 14, 'FontWeight', 'bold');
end

function plotROICategory(dF_values, headers, roiNumbers, time_ms, subplot_num, title_text, color)
    % Plot representative ROIs from a category
    
    if isempty(roiNumbers)
        subplot(2, 3, subplot_num);
        text(0.5, 0.5, 'No ROIs in this category', 'HorizontalAlignment', 'center');
        title(title_text);
        return;
    end
    
    % Find up to 4 ROIs to plot
    plotROIs = roiNumbers(1:min(4, length(roiNumbers)));
    
    subplot(2, 3, subplot_num);
    hold on;
    
    for i = 1:length(plotROIs)
        roi_num = plotROIs(i);
        roi_idx = findROIIndex(headers, roi_num);
        
        if ~isempty(roi_idx)
            plot(time_ms, dF_values(:, roi_idx) + (i-1)*0.02, 'Color', color, 'LineWidth', 1, ...
                 'DisplayName', sprintf('ROI %d', roi_num));
        end
    end
    
    title(sprintf('%s (n=%d)', title_text, length(roiNumbers)));
    xlabel('Time (ms)');
    ylabel('ΔF/F (offset)');
    xlim([0, max(time_ms)]);
    grid on;
    
    if length(plotROIs) <= 4
        legend('Location', 'best');
    end
end

function roi_idx = findROIIndex(headers, roi_number)
    % Find the index of a ROI number in headers
    
    roi_idx = [];
    for i = 1:length(headers)
        matches = regexp(headers{i}, 'ROI\s*(\d+)', 'tokens', 'ignorecase');
        if ~isempty(matches) && str2double(matches{1}{1}) == roi_number
            roi_idx = i;
            return;
        end
    end
end

function generateFilteringRecommendations(comparison)
    % Generate recommendations based on comparison results
    
    fprintf('\n=== FILTERING RECOMMENDATIONS ===\n');
    
    selectivity_change = comparison.metrics.selectivity_improvement;
    
    if selectivity_change > 0.1
        fprintf('✓ ENHANCED FILTERING RECOMMENDED\n');
        fprintf('  • Removes %.1f%% more false positives\n', selectivity_change*100);
        fprintf('  • Better temporal validation\n');
        fprintf('  • Optimized for iGlu3Fast kinetics\n');
    elseif selectivity_change > 0.05
        fprintf('⚠ MODERATE IMPROVEMENT\n');
        fprintf('  • Enhanced filtering removes %.1f%% more ROIs\n', selectivity_change*100);
        fprintf('  • Consider based on your false positive tolerance\n');
    elseif selectivity_change < -0.05
        fprintf('⚠ ENHANCED FILTERING TOO AGGRESSIVE\n');
        fprintf('  • May be removing valid responses\n');
        fprintf('  • Consider relaxing parameters\n');
    else
        fprintf('→ BOTH METHODS SIMILAR\n');
        fprintf('  • Minimal difference between methods\n');
        fprintf('  • Original filtering appears adequate\n');
    end
    
    if isfield(comparison, 'known_responders')
        fprintf('\nKnown Responder Performance:\n');
        if comparison.known_responders.detection_rate >= comparison.known_responders.original_detection_rate
            fprintf('  ✓ Enhanced method maintains or improves detection\n');
        else
            fprintf('  ⚠ Enhanced method misses some known responders\n');
            fprintf('  Consider relaxing enhanced parameters\n');
        end
    end
end

function cfg = getConfig()
    % Get configuration optimized for iGlu3Fast kinetics
    
    cfg = GluSnFRConfig();  % Start with base config
    
    % Enhanced filtering parameters optimized for iGlu3Fast
    cfg.filtering.MIN_RESPONSE_AMPLITUDE = 0.01;       % Minimum ΔF/F for valid response
    cfg.filtering.MIN_RISE_TIME_MS = 5;                 % Faster than iGluSnFR3 (was 5ms)
    cfg.filtering.MAX_RISE_TIME_MS = 150;                % Ultrafast kinetics (was 50ms)  
    cfg.filtering.RESPONSE_WINDOW_FRAMES = 20;          % 100ms window post-stimulus
    cfg.filtering.MIN_SNR = 2.5;                        % Signal-to-noise ratio
    
    % iGlu3Fast specific decay parameters 
    cfg.filtering.EXPECTED_DECAY_TIME_MS = 5;         % From kinetic table
    cfg.filtering.MAX_DECAY_TIME_CONSTANT_MS = 15;      % Allow up to 5x expected
    cfg.filtering.MAX_DECAY_RATIO = 0.7;                % Should decay to <70% of peak
    cfg.filtering.MAX_DECAY_FRAMES = 10;                % 50ms maximum decay analysis
    cfg.filtering.MIN_RISE_RATE = 0.001;                % Minimum dF/F per frame
    
    % Temporal validation
    cfg.filtering.ENABLE_TEMPORAL_VALIDATION = true;
    cfg.filtering.ENABLE_KINETIC_ANALYSIS = true;
    cfg.filtering.ENABLE_CONSISTENCY_CHECK = false;     % Requires multiple trials
end

% Placeholder functions for missing functionality
function calculateTrialConsistency(varargin)
    warning('calculateTrialConsistency not yet implemented');
end

function optimizeFilteringParameters(varargin)
    warning('optimizeFilteringParameters not yet implemented');
end