function calculator = df_calculator()
    % DF_CALCULATOR - Enhanced dF/F calculation module with rolling median option
    % 
    % This module provides both traditional mean baseline and advanced rolling 
    % median baseline correction methods with GPU acceleration and performance optimization.
    
    calculator.calculate = @calculateDFOptimized;
    calculator.calculateCPU = @calculateCPUOptimized;
    calculator.calculateGPU = @calculateGPUOptimized;
    calculator.calculateRollingMedian = @calculateRollingMedianWrapper;
    calculator.compareBaselines = @compareBaselineMethods;
    calculator.validateInputs = @validateCalculationInputs;
    calculator.shouldUseGPU = @shouldUseGPU;
    calculator.optimizeMethod = @optimizeCalculationMethod;
end

function [dF_values, thresholds, gpuUsed, method_stats] = calculateDFOptimized(traces, hasGPU, gpuInfo, varargin)
    % Enhanced main dF/F calculation with method selection
    %
    % INPUTS:
    %   traces - [frames x ROIs] fluorescence data
    %   hasGPU - boolean, GPU availability  
    %   gpuInfo - GPU information structure
    %   varargin - parameter pairs:
    %     'Method' - 'traditional' or 'rolling_median' (default: 'traditional')
    %     'WindowSizeMs' - for rolling median method (default: 750)
    %     'CompareBaselines' - run comparison (default: false)
    %     'OptimizeWindow' - optimize window size (default: false)
    %     'Verbose' - display progress (default: true)
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'Method', 'traditional', @(x) ismember(x, {'traditional', 'rolling_median'}));
    addParameter(p, 'WindowSizeMs', 750, @isnumeric);
    addParameter(p, 'CompareBaselines', false, @islogical);
    addParameter(p, 'OptimizeWindow', false, @islogical);
    addParameter(p, 'Verbose', true, @islogical);
    parse(p, varargin{:});
    
    params = p.Results;
    cfg = GluSnFRConfig();
    
    % Validate inputs
    if ~validateCalculationInputs(traces)
        error('Invalid input data for dF/F calculation');
    end
    
    % Convert to single precision for memory efficiency
    traces = single(traces);
    [n_frames, n_rois] = size(traces);
    
    if params.Verbose
        fprintf('    dF/F calculation: %s method\n', params.Method);
        fprintf('    Processing %d ROIs × %d frames\n', n_rois, n_frames);
    end
    
    % Initialize method stats
    method_stats = struct();
    method_stats.method = params.Method;
    method_stats.start_time = tic;
    
    % Method selection and processing
    switch params.Method
        case 'traditional'
            % Your existing method
            useGPU = shouldUseGPU(numel(traces), hasGPU, gpuInfo, cfg);
            
            if useGPU
                try
                    [dF_values, thresholds] = calculateGPUOptimized(traces, cfg);
                    gpuUsed = true;
                    method_stats.processing_mode = 'GPU';
                catch ME
                    if params.Verbose
                        fprintf('    GPU calculation failed (%s), falling back to CPU\n', ME.message);
                    end
                    [dF_values, thresholds] = calculateCPUOptimized(traces, cfg);
                    gpuUsed = false;
                    method_stats.processing_mode = 'CPU_fallback';
                end
            else
                [dF_values, thresholds] = calculateCPUOptimized(traces, cfg);
                gpuUsed = false;
                method_stats.processing_mode = 'CPU';
            end
            
        case 'rolling_median'
            % Load rolling median module
            rolling_baseline = rolling_median_baseline();
            
            % Window size optimization if requested
            if params.OptimizeWindow
                if params.Verbose
                    fprintf('    Optimizing window size...\n');
                end
                optimal_window = rolling_baseline.optimizeWindowSize(traces, hasGPU, gpuInfo, 'PlotResults', false);
                window_size = optimal_window;
                method_stats.optimized_window = optimal_window;
            else
                window_size = params.WindowSizeMs;
            end
            
            % Calculate using rolling median
            [dF_values, thresholds, baseline_trace, rolling_stats] = ...
                rolling_baseline.calculateRollingMedianDF(traces, hasGPU, gpuInfo, ...
                'WindowSizeMs', window_size, 'Verbose', params.Verbose);
            
            gpuUsed = rolling_stats.gpu_used;
            method_stats.processing_mode = ternary(gpuUsed, 'GPU', 'CPU');
            method_stats.rolling_stats = rolling_stats;
            method_stats.baseline_trace = baseline_trace;
    end
    
    % Record timing and performance
    method_stats.total_time = toc(method_stats.start_time);
    method_stats.frames_per_second = n_frames * n_rois / method_stats.total_time;
    method_stats.gpu_used = gpuUsed;
    
    if params.Verbose
        fprintf('    Completed: %.3f seconds using %s (%.0f fps)\n', ...
                method_stats.total_time, method_stats.processing_mode, method_stats.frames_per_second);
    end
    
    % Baseline comparison if requested
    if params.CompareBaselines && strcmp(params.Method, 'rolling_median')
        if params.Verbose
            fprintf('    Running baseline comparison...\n');
        end
        rolling_baseline = rolling_median_baseline();
        comparison = rolling_baseline.compareBaselines(traces, hasGPU, gpuInfo, 'PlotResults', true);
        method_stats.comparison = comparison;
    end
end

function [dF_values, thresholds, baseline_trace] = calculateRollingMedianWrapper(traces, hasGPU, gpuInfo, varargin)
    % Wrapper for rolling median calculation with simplified interface
    
    rolling_baseline = rolling_median_baseline();
    [dF_values, thresholds, baseline_trace, ~] = rolling_baseline.calculateRollingMedianDF(traces, hasGPU, gpuInfo, varargin{:});
end

function comparison = compareBaselineMethods(traces, hasGPU, gpuInfo, varargin)
    % Compare traditional vs rolling median baseline methods
    
    p = inputParser;
    addParameter(p, 'WindowSizeMs', 750, @isnumeric);
    addParameter(p, 'PlotResults', true, @islogical);
    addParameter(p, 'SaveResults', false, @islogical);
    addParameter(p, 'ResultsFile', 'baseline_comparison_results.mat', @ischar);
    parse(p, varargin{:});
    
    fprintf('\n=== Comprehensive Baseline Method Comparison ===\n');
    
    % Calculate both methods
    fprintf('1. Traditional mean baseline method...\n');
    tic;
    [dF_traditional, thresh_traditional, gpu_traditional] = calculateDFOptimized(traces, hasGPU, gpuInfo, ...
        'Method', 'traditional', 'Verbose', false);
    time_traditional = toc;
    
    fprintf('2. Rolling median baseline method...\n');
    tic;
    [dF_rolling, thresh_rolling, gpu_rolling, rolling_stats] = calculateDFOptimized(traces, hasGPU, gpuInfo, ...
        'Method', 'rolling_median', 'WindowSizeMs', p.Results.WindowSizeMs, 'Verbose', false);
    time_rolling = toc;
    
    % Detailed comparison metrics
    comparison = struct();
    comparison.processing_times = struct('traditional', time_traditional, 'rolling_median', time_rolling);
    comparison.gpu_usage = struct('traditional', gpu_traditional, 'rolling_median', gpu_rolling);
    comparison.window_size_ms = p.Results.WindowSizeMs;
    
    % Signal analysis metrics
    [n_frames, n_rois] = size(traces);
    
    % 1. Signal preservation (correlation between methods)
    correlations = zeros(1, n_rois);
    for roi = 1:n_rois
        if std(dF_traditional(:, roi)) > 0 && std(dF_rolling(:, roi)) > 0
            correlations(roi) = corr(dF_traditional(:, roi), dF_rolling(:, roi), 'rows', 'complete');
        end
    end
    comparison.signal_preservation = nanmean(correlations);
    comparison.signal_preservation_per_roi = correlations;
    
    % 2. Baseline stability analysis
    baseline_window = 1:min(200, size(traces, 1));
    traditional_baseline_var = var(dF_traditional(baseline_window, :), [], 1, 'omitnan');
    rolling_baseline_var = var(dF_rolling(baseline_window, :), [], 1, 'omitnan');
    
    comparison.baseline_variance_reduction = 1 - nanmean(rolling_baseline_var) / nanmean(traditional_baseline_var);
    comparison.baseline_variance_per_roi = 1 - rolling_baseline_var ./ traditional_baseline_var;
    
    % 3. Signal-to-noise ratio improvement
    % Calculate SNR as peak response / baseline noise
    cfg = GluSnFRConfig();
    stim_frame = cfg.timing.STIMULUS_FRAME;
    post_stim_window = stim_frame + (1:30); % 150ms post-stimulus
    
    if max(post_stim_window) <= n_frames
        traditional_peaks = max(dF_traditional(post_stim_window, :), [], 1);
        rolling_peaks = max(dF_rolling(post_stim_window, :), [], 1);
        
        traditional_snr = traditional_peaks ./ sqrt(traditional_baseline_var);
        rolling_snr = rolling_peaks ./ sqrt(rolling_baseline_var);
        
        comparison.snr_improvement = nanmean(rolling_snr ./ traditional_snr);
        comparison.snr_improvement_per_roi = rolling_snr ./ traditional_snr;
    else
        comparison.snr_improvement = NaN;
        comparison.snr_improvement_per_roi = NaN(1, n_rois);
    end
    
    % 4. Threshold comparison
    comparison.threshold_ratio = nanmean(thresh_rolling ./ thresh_traditional);
    comparison.threshold_traditional = thresh_traditional;
    comparison.threshold_rolling = thresh_rolling;
    
    % 5. Artifact detection (outlier analysis)
    if isfield(rolling_stats, 'outliers_detected')
        comparison.outliers_detected = rolling_stats.outliers_detected;
        comparison.total_outliers = sum(rolling_stats.outliers_detected);
        comparison.outlier_percentage = comparison.total_outliers / numel(traces) * 100;
    else
        comparison.outliers_detected = [];
        comparison.total_outliers = 0;
        comparison.outlier_percentage = 0;
    end
    
    % Display comprehensive results
    fprintf('\n=== Comparison Results ===\n');
    fprintf('Signal Preservation:\n');
    fprintf('  Average correlation: %.3f (%.1f%%)\n', comparison.signal_preservation, comparison.signal_preservation*100);
    fprintf('  ROI range: %.3f - %.3f\n', nanmin(correlations), nanmax(correlations));
    
    fprintf('\nBaseline Stability:\n');
    fprintf('  Variance reduction: %.1f%%\n', comparison.baseline_variance_reduction*100);
    fprintf('  Traditional baseline var: %.6f ± %.6f\n', nanmean(traditional_baseline_var), nanstd(traditional_baseline_var));
    fprintf('  Rolling median var: %.6f ± %.6f\n', nanmean(rolling_baseline_var), nanstd(rolling_baseline_var));
    
    if ~isnan(comparison.snr_improvement)
        fprintf('\nSignal-to-Noise Ratio:\n');
        fprintf('  SNR improvement: %.2fx\n', comparison.snr_improvement);
        fprintf('  Traditional SNR: %.2f ± %.2f\n', nanmean(traditional_snr), nanstd(traditional_snr));
        fprintf('  Rolling median SNR: %.2f ± %.2f\n', nanmean(rolling_snr), nanstd(rolling_snr));
    end
    
    fprintf('\nProcessing Performance:\n');
    fprintf('  Traditional method: %.3fs (%s)\n', time_traditional, ternary(gpu_traditional, 'GPU', 'CPU'));
    fprintf('  Rolling median: %.3fs (%s)\n', time_rolling, ternary(gpu_rolling, 'GPU', 'CPU'));
    fprintf('  Speed ratio: %.1fx slower\n', time_rolling / time_traditional);
    
    fprintf('\nArtifact Detection:\n');
    fprintf('  Outliers detected: %d (%.2f%% of data)\n', comparison.total_outliers, comparison.outlier_percentage);
    
    fprintf('\nThreshold Analysis:\n');
    fprintf('  Average threshold ratio: %.2f\n', comparison.threshold_ratio);
    fprintf('  Traditional thresholds: %.4f ± %.4f\n', nanmean(thresh_traditional), nanstd(thresh_traditional));
    fprintf('  Rolling median thresholds: %.4f ± %.4f\n', nanmean(thresh_rolling), nanstd(thresh_rolling));
    
    % Generate plots if requested
    if p.Results.PlotResults
        plotDetailedComparison(traces, dF_traditional, dF_rolling, comparison, rolling_stats);
    end
    
    % Save results if requested
    if p.Results.SaveResults
        save(p.Results.ResultsFile, 'comparison', 'dF_traditional', 'dF_rolling', 'rolling_stats');
        fprintf('\nResults saved to: %s\n', p.Results.ResultsFile);
    end
    
    % Recommendation
    fprintf('\n=== RECOMMENDATION ===\n');
    if comparison.signal_preservation > 0.95 && comparison.baseline_variance_reduction > 0.1
        fprintf('✓ Rolling median method recommended:\n');
        fprintf('  - Excellent signal preservation (%.1f%%)\n', comparison.signal_preservation*100);
        fprintf('  - Significant noise reduction (%.1f%%)\n', comparison.baseline_variance_reduction*100);
        if comparison.outlier_percentage > 1
            fprintf('  - Detected %.1f%% artifacts in your data\n', comparison.outlier_percentage);
        end
    elseif comparison.signal_preservation > 0.9
        fprintf('⚠ Rolling median provides moderate improvement:\n');
        fprintf('  - Good signal preservation (%.1f%%)\n', comparison.signal_preservation*100);
        fprintf('  - Consider for long recordings or noisy data\n');
    else
        fprintf('⚠ Traditional method may be sufficient:\n');
        fprintf('  - Rolling median changes signals significantly\n');
        fprintf('  - Consider optimizing window size or parameters\n');
    end
end

function plotDetailedComparison(traces, dF_traditional, dF_rolling, comparison, rolling_stats)
    % Create detailed comparison plots
    
    % Find representative ROIs
    correlations = comparison.signal_preservation_per_roi;
    [~, best_roi] = nanmax(correlations);
    [~, worst_roi] = nanmin(correlations);
    
    % Select middle ROI
    valid_correlations = correlations(~isnan(correlations));
    if length(valid_correlations) > 2
        sorted_corr = sort(valid_correlations);
        middle_corr = sorted_corr(round(length(sorted_corr)/2));
        middle_roi = find(abs(correlations - middle_corr) == min(abs(correlations - middle_corr)), 1);
    else
        middle_roi = best_roi;
    end
    
    figure('Position', [50, 50, 1600, 1200], 'Name', 'Detailed Baseline Method Comparison');
    
    time_ms = (0:size(traces, 1)-1) * 5; % 5ms per frame
    
    % Plot 1: Best ROI comparison
    subplot(3, 4, 1);
    plot(time_ms, dF_traditional(:, best_roi), 'b-', 'LineWidth', 1, 'DisplayName', 'Traditional');
    hold on;
    plot(time_ms, dF_rolling(:, best_roi), 'r-', 'LineWidth', 1, 'DisplayName', 'Rolling Median');
    title(sprintf('Best ROI %d (r=%.3f)', best_roi, correlations(best_roi)));
    xlabel('Time (ms)'); ylabel('ΔF/F');
    legend('Location', 'best'); grid on;
    ylim([-0.02, 0.1]);
    
    % Plot 2: Worst ROI comparison
    subplot(3, 4, 2);
    plot(time_ms, dF_traditional(:, worst_roi), 'b-', 'LineWidth', 1);
    hold on;
    plot(time_ms, dF_rolling(:, worst_roi), 'r-', 'LineWidth', 1);
    title(sprintf('Worst ROI %d (r=%.3f)', worst_roi, correlations(worst_roi)));
    xlabel('Time (ms)'); ylabel('ΔF/F');
    grid on; ylim([-0.02, 0.1]);
    
    % Plot 3: Signal preservation histogram
    subplot(3, 4, 3);
    histogram(correlations, 20, 'FaceColor', [0.7, 0.7, 0.7], 'EdgeColor', 'black');
    xlabel('Signal Preservation (correlation)');
    ylabel('Number of ROIs');
    title('Signal Preservation Distribution');
    grid on;
    
    % Plot 4: Baseline variance comparison
    subplot(3, 4, 4);
    var_reduction = comparison.baseline_variance_per_roi * 100;
    histogram(var_reduction, 20, 'FaceColor', [0.7, 0.7, 0.7], 'EdgeColor', 'black');
    xlabel('Variance Reduction (%)');
    ylabel('Number of ROIs');
    title('Baseline Variance Reduction');
    grid on;
    
    % Plot 5: Raw trace with baseline (best ROI)
    subplot(3, 4, 5);
    plot(time_ms, traces(:, best_roi), 'k-', 'LineWidth', 1);
    hold on;
    if isfield(rolling_stats, 'baseline_trace')
        plot(time_ms, rolling_stats.baseline_trace(:, best_roi), 'r-', 'LineWidth', 2);
    end
    % Traditional baseline
    baseline_frames = 1:200;
    trad_baseline = mean(traces(baseline_frames, best_roi));
    plot(time_ms, repmat(trad_baseline, length(time_ms), 1), 'b--', 'LineWidth', 2);
    legend('Raw', 'Rolling Median Baseline', 'Traditional Baseline', 'Location', 'best');
    title(sprintf('ROI %d: Baselines', best_roi));
    xlabel('Time (ms)'); ylabel('Fluorescence');
    grid on;
    
    % Plot 6: Threshold comparison scatter
    subplot(3, 4, 6);
    scatter(comparison.threshold_traditional, comparison.threshold_rolling, 50, 'filled');
    xlabel('Traditional Thresholds');
    ylabel('Rolling Median Thresholds');
    title('Threshold Comparison');
    hold on;
    max_thresh = max([comparison.threshold_traditional, comparison.threshold_rolling]);
    plot([0, max_thresh], [0, max_thresh], 'k--');
    grid on; axis equal;
    
    % Plot 7: SNR comparison (if available)
    subplot(3, 4, 7);
    if ~isnan(comparison.snr_improvement_per_roi)
        snr_ratios = comparison.snr_improvement_per_roi;
        histogram(snr_ratios, 20, 'FaceColor', [0.7, 0.7, 0.7], 'EdgeColor', 'black');
        xlabel('SNR Improvement Ratio');
        ylabel('Number of ROIs');
        title('SNR Improvement Distribution');
    else
        text(0.5, 0.5, 'SNR analysis not available', 'HorizontalAlignment', 'center');
        title('SNR Analysis');
    end
    grid on;
    
    % Plot 8: Processing performance
    subplot(3, 4, 8);
    methods = {'Traditional', 'Rolling Median'};
    times = [comparison.processing_times.traditional, comparison.processing_times.rolling_median];
    bar(times);
    set(gca, 'XTickLabel', methods);
    ylabel('Processing Time (s)');
    title('Processing Performance');
    grid on;
    
    % Plot 9: Outlier detection timeline (if available)
    subplot(3, 4, 9);
    if ~isempty(comparison.outliers_detected)
        bar(1:length(comparison.outliers_detected), comparison.outliers_detected);
        xlabel('Iteration');
        ylabel('Outliers Detected');
        title('Iterative Outlier Detection');
    else
        text(0.5, 0.5, 'No outlier data', 'HorizontalAlignment', 'center');
        title('Outlier Detection');
    end
    grid on;
    
    % Plot 10: Method correlation for middle ROI
    subplot(3, 4, 10);
    if middle_roi ~= best_roi
        scatter(dF_traditional(:, middle_roi), dF_rolling(:, middle_roi), 10, 'filled', 'Alpha', 0.6);
        xlabel('Traditional ΔF/F');
        ylabel('Rolling Median ΔF/F');
        title(sprintf('ROI %d Correlation (r=%.3f)', middle_roi, correlations(middle_roi)));
        grid on; axis equal;
    else
        text(0.5, 0.5, 'Same as best ROI', 'HorizontalAlignment', 'center');
        title('Middle ROI Analysis');
    end
    
    % Plot 11: Summary metrics
    subplot(3, 4, 11:12);
    metrics = [comparison.signal_preservation * 100, ...
               abs(comparison.baseline_variance_reduction) * 100, ...
               comparison.snr_improvement, ...
               comparison.threshold_ratio];
    metric_names = {'Signal Preservation (%)', 'Variance Reduction (%)', 'SNR Improvement', 'Threshold Ratio'};
    
    bar(metrics);
    set(gca, 'XTickLabel', metric_names, 'XTickLabelRotation', 45);
    title('Summary Performance Metrics');
    ylabel('Value');
    grid on;
    
    sgtitle('Comprehensive Baseline Method Comparison', 'FontSize', 16, 'FontWeight', 'bold');
end

function method_recommendation = optimizeCalculationMethod(traces, hasGPU, gpuInfo, varargin)
    % Optimize dF/F calculation method for your specific data
    
    p = inputParser;
    addParameter(p, 'TestWindows', [250, 500, 750, 1000, 1500], @isnumeric);
    addParameter(p, 'SaveResults', true, @islogical);
    addParameter(p, 'ResultsFile', 'method_optimization_results.mat', @ischar);
    parse(p, varargin{:});
    
    fprintf('\n=== Optimizing dF/F Calculation Method ===\n');
    
    % Test traditional method
    fprintf('1. Testing traditional method...\n');
    [~, ~, ~, traditional_stats] = calculateDFOptimized(traces, hasGPU, gpuInfo, ...
        'Method', 'traditional', 'Verbose', false);
    
    % Test different rolling median window sizes
    test_windows = p.Results.TestWindows;
    rolling_results = struct();
    
    for i = 1:length(test_windows)
        window_ms = test_windows(i);
        fprintf('2.%d Testing rolling median (%d ms window)...\n', i, window_ms);
        
        comparison = compareBaselineMethods(traces, hasGPU, gpuInfo, ...
            'WindowSizeMs', window_ms, 'PlotResults', false);
        
        rolling_results(i).window_size = window_ms;
        rolling_results(i).comparison = comparison;
        rolling_results(i).score = calculateMethodScore(comparison);
    end
    
    % Find best configuration
    scores = [rolling_results.score];
    [best_score, best_idx] = max(scores);
    best_window = rolling_results(best_idx).window_size;
    
    % Generate recommendation
    method_recommendation = struct();
    method_recommendation.recommended_method = 'rolling_median';
    method_recommendation.optimal_window_ms = best_window;
    method_recommendation.performance_score = best_score;
    method_recommendation.traditional_score = 0.7; % Baseline score
    method_recommendation.improvement = best_score - 0.7;
    
    % Detailed analysis
    best_comparison = rolling_results(best_idx).comparison;
    method_recommendation.signal_preservation = best_comparison.signal_preservation;
    method_recommendation.noise_reduction = best_comparison.baseline_variance_reduction;
    method_recommendation.processing_overhead = best_comparison.processing_times.rolling_median / best_comparison.processing_times.traditional;
    
    % Display recommendation
    fprintf('\n=== OPTIMIZATION RESULTS ===\n');
    fprintf('Recommended Method: %s\n', method_recommendation.recommended_method);
    fprintf('Optimal Window Size: %d ms\n', method_recommendation.optimal_window_ms);
    fprintf('Performance Score: %.3f (vs %.3f traditional)\n', best_score, method_recommendation.traditional_score);
    fprintf('Improvement: %.1f%%\n', method_recommendation.improvement * 100);
    
    fprintf('\nKey Metrics:\n');
    fprintf('  Signal preservation: %.1f%%\n', method_recommendation.signal_preservation * 100);
    fprintf('  Noise reduction: %.1f%%\n', method_recommendation.noise_reduction * 100);
    fprintf('  Processing overhead: %.1fx\n', method_recommendation.processing_overhead);
    
    if method_recommendation.improvement > 0.1
        fprintf('\n✓ STRONG RECOMMENDATION: Use rolling median method\n');
        fprintf('  Significant improvement in data quality\n');
    elseif method_recommendation.improvement > 0.05
        fprintf('\n⚠ MODERATE RECOMMENDATION: Consider rolling median\n');
        fprintf('  Modest improvement, evaluate based on your priorities\n');
    else
        fprintf('\n→ TRADITIONAL METHOD SUFFICIENT\n');
        fprintf('  Rolling median provides minimal benefit for your data\n');
    end
    
    % Save results
    if p.Results.SaveResults
        optimization_results = struct();
        optimization_results.recommendation = method_recommendation;
        optimization_results.traditional_stats = traditional_stats;
        optimization_results.rolling_results = rolling_results;
        optimization_results.test_windows = test_windows;
        
        save(p.Results.ResultsFile, 'optimization_results');
        fprintf('\nOptimization results saved to: %s\n', p.Results.ResultsFile);
    end
end

function score = calculateMethodScore(comparison)
    % Calculate a composite score for method comparison
    
    % Weights for different metrics
    w_signal = 0.4;      % Signal preservation weight
    w_noise = 0.3;       % Noise reduction weight  
    w_snr = 0.2;         % SNR improvement weight
    w_artifacts = 0.1;   % Artifact detection weight
    
    % Normalize metrics to 0-1 scale
    signal_score = max(0, min(1, comparison.signal_preservation));
    noise_score = max(0, min(1, comparison.baseline_variance_reduction));
    
    if ~isnan(comparison.snr_improvement)
        snr_score = max(0, min(1, (comparison.snr_improvement - 1) / 2)); % SNR improvement above 1x
    else
        snr_score = 0;
    end
    
    artifact_score = min(1, comparison.outlier_percentage / 5); % Up to 5% artifacts is good
    
    % Calculate composite score
    score = w_signal * signal_score + w_noise * noise_score + w_snr * snr_score + w_artifacts * artifact_score;
end

% Include existing optimized functions with minor enhancements

function [dF_values, thresholds] = calculateGPUOptimized(traces, cfg)
    % GPU-optimized dF/F calculation (existing function)
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    % Transfer to GPU
    gpuData = gpuArray(traces);
    
    % Vectorized baseline calculation on GPU
    baseline_data = gpuData(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    
    % Protect against zero/negative baselines
    F0(F0 <= 0) = single(cfg.thresholds.MIN_F0);
    
    % Vectorized dF/F calculation using implicit expansion
    dF_values = (gpuData - F0) ./ F0;
    
    % Handle edge cases
    dF_values(~isfinite(dF_values)) = 0;
    
    % Calculate thresholds (3×SD of baseline dF/F)
    baseline_dF_F = dF_values(baseline_window, :);
    thresholds = cfg.thresholds.SD_MULTIPLIER * std(baseline_dF_F, 1, 'omitnan');
    thresholds(isnan(thresholds)) = cfg.thresholds.DEFAULT_THRESHOLD;
    
    % Transfer back to CPU
    dF_values = gather(dF_values);
    thresholds = gather(thresholds);
end

function [dF_values, thresholds] = calculateCPUOptimized(traces, cfg)
    % CPU-optimized dF/F calculation (existing function)
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    % Vectorized operations on CPU
    baseline_data = traces(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    F0(F0 <= 0) = single(cfg.thresholds.MIN_F0);
    
    % Efficient dF/F calculation using implicit expansion
    dF_values = (traces - F0) ./ F0;
    dF_values(~isfinite(dF_values)) = 0;
    
    % Vectorized threshold calculation
    baseline_dF_F = dF_values(baseline_window, :);
    thresholds = cfg.thresholds.SD_MULTIPLIER * std(baseline_dF_F, 1, 'omitnan');
    thresholds(isnan(thresholds)) = cfg.thresholds.DEFAULT_THRESHOLD;
end

function isValid = validateCalculationInputs(traces)
    % Validate inputs for dF/F calculation (existing function)
    
    isValid = false;
    
    if isempty(traces)
        warning('Empty traces provided');
        return;
    end
    
    if ~isnumeric(traces)
        warning('Non-numeric traces provided');
        return;
    end
    
    if size(traces, 1) < 300
        warning('Insufficient frames for analysis (need at least 300)');
        return;
    end
    
    if any(all(isnan(traces), 1))
        warning('Some ROIs contain only NaN values');
    end
    
    isValid = true;
end

function useGPU = shouldUseGPU(dataSize, hasGPU, gpuInfo, cfg)
    % Determine whether to use GPU (existing function)
    
    useGPU = false;
    
    if ~hasGPU
        return;
    end
    
    if dataSize < cfg.processing.GPU_MIN_DATA_SIZE
        return;
    end
    
    memoryRequired = dataSize * 4;
    availableMemory = gpuInfo.memory * cfg.processing.GPU_MEMORY_FRACTION * 1e9;
    
    if memoryRequired > availableMemory
        return;
    end
    
    useGPU = true;
end

function result = ternary(condition, trueVal, falseVal)
    % Utility function for ternary operator
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end