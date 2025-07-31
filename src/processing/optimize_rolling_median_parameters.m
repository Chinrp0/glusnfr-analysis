function optimize_rolling_median_parameters()
    % Test different parameter combinations to find what works for your data
    
    fprintf('=== Rolling Median Parameter Optimization ===\n');
    
    % Load your data (replace with your file path)
    [filename, pathname] = uigetfile('*.xlsx', 'Select test file');
    filepath = fullfile(pathname, filename);
    
    % Read data using your pipeline
    modules = module_loader();
    [rawData, ~, ~] = modules.io.readExcelFile(filepath, true);
    traces = single(rawData(:, 2:end));
    
    % Test parameter combinations
    window_sizes = [200, 300, 500, 750];      % Smaller windows!
    outlier_thresholds = [1.0, 1.5, 2.0, 2.5];
    
    best_score = 0;
    best_params = [];
    results = [];
    
    baseline_corrector = rolling_median_baseline();
    gpuInfo = struct('memory', 4);
    
    % Calculate reference (traditional method)
    cfg = GluSnFRConfig();
    baseline_frames = 1:200;
    F0_trad = mean(traces(baseline_frames, :), 1, 'omitnan');
    dF_trad = (traces - F0_trad) ./ F0_trad;
    dF_trad(~isfinite(dF_trad)) = 0;
    
    fprintf('\nTesting parameter combinations:\n');
    
    for i = 1:length(window_sizes)
        for j = 1:length(outlier_thresholds)
            window_ms = window_sizes(i);
            threshold = outlier_thresholds(j);
            
            fprintf('Window: %dms, Threshold: %.1f...', window_ms, threshold);
            
            try
                [dF_rolling, thresh_rolling, baseline_trace, stats] = ...
                    baseline_corrector.calculateRollingMedianDF(traces, false, gpuInfo, ...
                    'WindowSizeMs', window_ms, ...
                    'OutlierThreshold', threshold, ...
                    'MaxIterations', 3, ...
                    'Verbose', false);
                
                % Calculate quality metrics
                correlations = zeros(1, size(traces, 2));
                for roi = 1:size(traces, 2)
                    if std(dF_trad(:, roi)) > 0 && std(dF_rolling(:, roi)) > 0
                        correlations(roi) = corr(dF_trad(:, roi), dF_rolling(:, roi), 'rows', 'complete');
                    end
                end
                signal_preservation = nanmean(correlations);
                
                % Baseline variance comparison
                baseline_var_trad = var(dF_trad(baseline_frames, :), [], 1, 'omitnan');
                baseline_var_roll = var(dF_rolling(baseline_frames, :), [], 1, 'omitnan');
                noise_reduction = 1 - nanmean(baseline_var_roll) / nanmean(baseline_var_trad);
                
                % Threshold difference (should be more adaptive)
                thresh_trad = 3 * std(dF_trad(baseline_frames, :), 1, 'omitnan');
                thresh_difference = mean(abs(thresh_rolling - thresh_trad) ./ thresh_trad);
                
                % Baseline adaptation score (how much baseline changes)
                baseline_change = mean(std(baseline_trace, [], 1)) / mean(mean(baseline_trace, 1));
                
                % Outlier detection
                outlier_pct = 0;
                if isfield(stats, 'outliers_detected')
                    outlier_pct = sum(stats.outliers_detected) / numel(traces) * 100;
                end
                
                % Composite score - we want good signal preservation BUT significant baseline adaptation
                score = signal_preservation * 0.4 + ...  % Signal preservation (should be >0.9)
                        max(0, noise_reduction) * 0.3 + ... % Noise reduction 
                        min(1, thresh_difference) * 0.2 + ... % Threshold adaptation
                        min(1, baseline_change * 100) * 0.1; % Baseline adaptation
                
                fprintf(' Score: %.3f (r=%.3f, noise↓=%.1f%%, adapt=%.1f%%, outliers=%.1f%%)\n', ...
                        score, signal_preservation, noise_reduction*100, thresh_difference*100, outlier_pct);
                
                results(end+1) = struct('window', window_ms, 'threshold', threshold, ...
                                      'score', score, 'signal_preservation', signal_preservation, ...
                                      'noise_reduction', noise_reduction, 'threshold_adaptation', thresh_difference, ...
                                      'outlier_percentage', outlier_pct, 'baseline_change', baseline_change);
                
                if score > best_score
                    best_score = score;
                    best_params = struct('window', window_ms, 'threshold', threshold);
                end
                
            catch ME
                fprintf(' Failed: %s\n', ME.message);
            end
        end
    end
    
    % Display results
    fprintf('\n=== OPTIMIZATION RESULTS ===\n');
    if ~isempty(best_params)
        fprintf('Best parameters:\n');
        fprintf('  Window size: %d ms\n', best_params.window);
        fprintf('  Outlier threshold: %.1f\n', best_params.threshold);
        fprintf('  Score: %.3f\n', best_score);
        
        % Show top 3 configurations
        [~, sorted_idx] = sort([results.score], 'descend');
        fprintf('\nTop 3 configurations:\n');
        for i = 1:min(3, length(results))
            r = results(sorted_idx(i));
            fprintf('%d. Window=%dms, Threshold=%.1f: Score=%.3f (r=%.3f, noise↓=%.1f%%, adapt=%.1f%%)\n', ...
                    i, r.window, r.threshold, r.score, r.signal_preservation, ...
                    r.noise_reduction*100, r.threshold_adaptation*100);
        end
        
        % Test best configuration
        fprintf('\n=== TESTING BEST CONFIGURATION ===\n');
        [dF_best, thresh_best, baseline_best, stats_best] = ...
            baseline_corrector.calculateRollingMedianDF(traces, false, gpuInfo, ...
            'WindowSizeMs', best_params.window, ...
            'OutlierThreshold', best_params.threshold, ...
            'MaxIterations', 5, ...
            'Verbose', true);
        
        % Plot comparison
        plotOptimizedComparison(traces, dF_trad, dF_best, baseline_best, best_params);
        
    else
        fprintf('No successful parameter combinations found\n');
    end
end

function plotOptimizedComparison(traces, dF_trad, dF_rolling, baseline_rolling, params)
    % Plot results with optimized parameters
    
    % Select 4 most variable ROIs for comparison
    roi_variability = std(dF_trad, [], 1);
    [~, sorted_idx] = sort(roi_variability, 'descend');
    plot_rois = sorted_idx(1:4);
    
    figure('Position', [100, 100, 1600, 1000], 'Name', 'Optimized Rolling Median Results');
    
    time_ms = (0:size(traces, 1)-1) * 5;
    
    for i = 1:4
        roi = plot_rois(i);
        
        % Traditional
        subplot(4, 3, (i-1)*3 + 1);
        plot(time_ms, dF_trad(:, roi), 'b-', 'LineWidth', 1);
        title(sprintf('Traditional - ROI %d', roi));
        ylabel('ΔF/F'); ylim([-0.02, 0.1]); grid on;
        
        % Rolling median
        subplot(4, 3, (i-1)*3 + 2);
        plot(time_ms, dF_rolling(:, roi), 'r-', 'LineWidth', 1);
        title(sprintf('Rolling Median (%dms) - ROI %d', params.window, roi));
        ylabel('ΔF/F'); ylim([-0.02, 0.1]); grid on;
        
        % Baselines comparison
        subplot(4, 3, (i-1)*3 + 3);
        plot(time_ms, traces(:, roi), 'k-', 'LineWidth', 0.5, 'DisplayName', 'Raw');
        hold on;
        plot(time_ms, baseline_rolling(:, roi), 'r-', 'LineWidth', 2, 'DisplayName', 'Rolling Baseline');
        
        % Traditional baseline
        baseline_frames = 1:200;
        trad_baseline = mean(traces(baseline_frames, roi));
        plot(time_ms, repmat(trad_baseline, length(time_ms), 1), 'b--', 'LineWidth', 2, 'DisplayName', 'Traditional');
        
        title(sprintf('Baselines - ROI %d', roi));
        ylabel('Fluorescence'); xlabel('Time (ms)');
        if i == 1, legend('Location', 'best'); end
        grid on;
    end
    
    sgtitle(sprintf('Optimized Parameters: Window=%dms, Threshold=%.1f', params.window, params.threshold), ...
           'FontSize', 14, 'FontWeight', 'bold');
end