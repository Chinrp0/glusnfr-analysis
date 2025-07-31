function test_rolling_median()
    % TEST_ROLLING_MEDIAN - Quick demo of rolling median baseline correction
    %
    % This script allows you to test the rolling median method on your data
    % without modifying your main pipeline. Just run this function!
    
    fprintf('\n');
    fprintf('=========================================================\n');
    fprintf('   Rolling Median Baseline Correction - Quick Test     \n');
    fprintf('=========================================================\n');
    fprintf('This will test the rolling median method on your data\n');
    fprintf('and show you the comparison with your current method.\n\n');
    
    % Setup - add paths if needed
    try
        % Try to use your existing module system
        addpath(genpath(pwd));
        modules = module_loader();
        cfg = modules.config;
        fprintf('✓ Using your existing pipeline modules\n');
        use_modules = true;
    catch
        fprintf('⚠ Module system not found, using standalone mode\n');
        use_modules = false;
        cfg = createBasicConfig();
    end
    
    % Select file to test
    fprintf('\nStep 1: Select test file\n');
    [filename, pathname] = uigetfile('*.xlsx', 'Select an Excel file to test');
    
    if isequal(filename, 0)
        fprintf('No file selected, exiting...\n');
        return;
    end
    
    filepath = fullfile(pathname, filename);
    fprintf('Selected: %s\n', filename);
    
    % Read data
    fprintf('\nStep 2: Reading data...\n');
    try
        if use_modules
            [rawData, headers, success] = modules.io.readExcelFile(filepath, true);
            if ~success || isempty(rawData)
                error('Failed to read file');
            end
            % Skip first column (time) and extract numeric data
            traces = single(rawData(:, 2:end));
            validHeaders = headers(2:end);
        else
            [traces, validHeaders] = readExcelFileBasic(filepath);
        end
        
        [n_frames, n_rois] = size(traces);
        fprintf('✓ Read %d frames × %d ROIs\n', n_frames, n_rois);
        
    catch ME
        fprintf('✗ Error reading file: %s\n', ME.message);
        return;
    end
    
    % System detection
    fprintf('\nStep 3: Detecting system capabilities...\n');
    hasGPU = gpuDeviceCount > 0;
    if hasGPU
        try
            gpu = gpuDevice();
            gpuInfo.name = gpu.Name;
            gpuInfo.memory = gpu.AvailableMemory / 1e9; % GB
            fprintf('✓ GPU detected: %s (%.1f GB available)\n', gpuInfo.name, gpuInfo.memory);
        catch
            hasGPU = false;
            gpuInfo = struct('name', 'None', 'memory', 0);
            fprintf('⚠ GPU detected but not accessible\n');
        end
    else
        gpuInfo = struct('name', 'None', 'memory', 0);
        fprintf('ℹ No GPU detected, using CPU\n');
    end
    
    % Load rolling median functions
    fprintf('\nStep 4: Loading rolling median baseline correction...\n');
    try
        baseline_corrector = rolling_median_baseline();
        fprintf('✓ Rolling median module loaded\n');
    catch ME
        fprintf('✗ Error loading rolling median module: %s\n', ME.message);
        fprintf('Make sure rolling_median_baseline.m is in your path\n');
        return;
    end
    
    % Calculate traditional baseline
    fprintf('\nStep 5: Calculating traditional baseline (your current method)...\n');
    tic;
    baseline_frames = 1:min(200, cfg.timing.STIMULUS_FRAME-1);
    F0_traditional = mean(traces(baseline_frames, :), 1, 'omitnan');
    F0_traditional(F0_traditional <= 0) = 1e-6; % Protect against zeros
    dF_traditional = (traces - F0_traditional) ./ F0_traditional;
    dF_traditional(~isfinite(dF_traditional)) = 0;
    
    % Calculate traditional thresholds
    baseline_dF = dF_traditional(baseline_frames, :);
    thresh_traditional = cfg.thresholds.SD_MULTIPLIER * std(baseline_dF, 1, 'omitnan');
    thresh_traditional(isnan(thresh_traditional)) = cfg.thresholds.DEFAULT_THRESHOLD;
    
    time_traditional = toc;
    fprintf('✓ Traditional method: %.3f seconds\n', time_traditional);
    
    % Calculate rolling median baseline
    fprintf('\nStep 6: Calculating rolling median baseline...\n');
    window_sizes = [500, 750, 1000]; % Test multiple window sizes
    
    best_score = 0;
    best_results = [];
    best_window = 750;
    
    for i = 1:length(window_sizes)
        window_ms = window_sizes(i);
        fprintf('  Testing %d ms window...', window_ms);
        
        try
            tic;
            [dF_rolling, thresh_rolling, baseline_trace, stats] = ...
                baseline_corrector.calculateRollingMedianDF(traces, hasGPU, gpuInfo, ...
                'WindowSizeMs', window_ms, 'Verbose', false);
            time_rolling = toc;
            
            % Quick quality assessment
            correlations = zeros(1, n_rois);
            for roi = 1:n_rois
                if std(dF_traditional(:, roi)) > 0 && std(dF_rolling(:, roi)) > 0
                    correlations(roi) = corr(dF_traditional(:, roi), dF_rolling(:, roi), 'rows', 'complete');
                end
            end
            signal_preservation = nanmean(correlations);
            
            baseline_var_traditional = var(dF_traditional(baseline_frames, :), [], 1, 'omitnan');
            baseline_var_rolling = var(dF_rolling(baseline_frames, :), [], 1, 'omitnan');
            noise_reduction = 1 - nanmean(baseline_var_rolling) / nanmean(baseline_var_traditional);
            
            % Simple scoring
            score = signal_preservation + 0.5 * max(0, noise_reduction);
            
            fprintf(' Score: %.3f (r=%.3f, noise↓=%.1f%%)\n', ...
                    score, signal_preservation, noise_reduction*100);
            
            if score > best_score
                best_score = score;
                best_window = window_ms;
                best_results = struct('dF', dF_rolling, 'thresh', thresh_rolling, ...
                                    'baseline', baseline_trace, 'stats', stats, ...
                                    'time', time_rolling, 'signal_preservation', signal_preservation, ...
                                    'noise_reduction', noise_reduction);
            end
            
        catch ME
            fprintf(' Failed: %s\n', ME.message);
        end
    end
    
    if isempty(best_results)
        fprintf('✗ All rolling median tests failed\n');
        return;
    end
    
    fprintf('✓ Best configuration: %d ms window (score: %.3f)\n', best_window, best_score);
    
    % Display comparison results
    fprintf('\nStep 7: Comparison Results\n');
    fprintf('=========================\n');
    fprintf('Traditional Method:\n');
    fprintf('  Processing time: %.3f seconds\n', time_traditional);
    fprintf('  Average threshold: %.4f ± %.4f\n', mean(thresh_traditional), std(thresh_traditional));
    fprintf('  Baseline variance: %.6f\n', nanmean(baseline_var_traditional));
    
    fprintf('\nRolling Median Method (%d ms window):\n', best_window);
    fprintf('  Processing time: %.3f seconds (%.1fx slower)\n', best_results.time, best_results.time/time_traditional);
    fprintf('  Average threshold: %.4f ± %.4f\n', mean(best_results.thresh), std(best_results.thresh));
    fprintf('  Baseline variance: %.6f (%.1f%% reduction)\n', ...
            nanmean(baseline_var_rolling), best_results.noise_reduction*100);
    fprintf('  Signal preservation: %.1f%% correlation\n', best_results.signal_preservation*100);
    fprintf('  Processing mode: %s\n', ternary(best_results.stats.gpu_used, 'GPU', 'CPU'));
    
    if isfield(best_results.stats, 'outliers_detected') && ~isempty(best_results.stats.outliers_detected)
        total_outliers = sum(best_results.stats.outliers_detected);
        outlier_percentage = total_outliers / numel(traces) * 100;
        fprintf('  Artifacts detected: %d (%.2f%% of data)\n', total_outliers, outlier_percentage);
    end
    
    % Generate recommendation
    fprintf('\nStep 8: Recommendation\n');
    fprintf('=====================\n');
    
    if best_results.signal_preservation > 0.95 && best_results.noise_reduction > 0.1
        fprintf('🟢 STRONG RECOMMENDATION: Use rolling median method\n');
        fprintf('   • Excellent signal preservation (%.1f%%)\n', best_results.signal_preservation*100);
        fprintf('   • Significant noise reduction (%.1f%%)\n', best_results.noise_reduction*100);
        fprintf('   • Your data will benefit substantially from this method\n');
        recommend_use = true;
    elseif best_results.signal_preservation > 0.9 && best_results.noise_reduction > 0.05
        fprintf('🟡 MODERATE RECOMMENDATION: Consider rolling median method\n');
        fprintf('   • Good signal preservation (%.1f%%)\n', best_results.signal_preservation*100);
        fprintf('   • Moderate noise reduction (%.1f%%)\n', best_results.noise_reduction*100);
        fprintf('   • Beneficial for noisy data or long recordings\n');
        recommend_use = true;
    else
        fprintf('🔵 TRADITIONAL METHOD SUFFICIENT\n');
        fprintf('   • Rolling median provides minimal benefit\n');
        fprintf('   • Your data is already quite clean\n');
        recommend_use = false;
    end
    
    % Create comparison plots
    fprintf('\nStep 9: Generating comparison plots...\n');
    try
        plotQuickComparison(traces, dF_traditional, best_results.dF, best_results.baseline, ...
                           validHeaders, best_window, best_results);
        fprintf('✓ Comparison plots generated\n');
    catch ME
        fprintf('⚠ Plotting failed: %s\n', ME.message);
    end
    
    % Implementation instructions
    if recommend_use
        fprintf('\nStep 10: Implementation Instructions\n');
        fprintf('===================================\n');
        fprintf('To use rolling median in your pipeline:\n\n');
        fprintf('1. Add to your GluSnFRConfig.m:\n');
        fprintf('   config.baseline.METHOD = ''rolling_median'';\n');
        fprintf('   config.baseline.WINDOW_SIZE_MS = %d;\n', best_window);
        fprintf('\n2. Update your df_calculator calls:\n');
        fprintf('   [dF, thresh, gpu] = calc.calculate(data, hasGPU, gpuInfo, ...\n');
        fprintf('       ''Method'', ''rolling_median'', ''WindowSizeMs'', %d);\n', best_window);
        fprintf('\n3. Or modify processSingleFile in pipeline_controller.m\n');
    end
    
    fprintf('\nTest completed! Check the generated plots to see the differences.\n');
end

function plotQuickComparison(traces, dF_traditional, dF_rolling, baseline_rolling, headers, window_ms, results)
    % Create quick comparison plots
    
    % Find most interesting ROIs
    [n_frames, n_rois] = size(traces);
    signal_strength = max(dF_traditional, [], 1) - min(dF_traditional, [], 1);
    [~, sorted_idx] = sort(signal_strength, 'descend');
    
    % Select top 4 ROIs for plotting
    plot_rois = sorted_idx(1:min(4, n_rois));
    
    figure('Position', [100, 100, 1400, 1000], 'Name', 'Rolling Median Baseline Correction Test');
    
    time_ms = (0:n_frames-1) * 5; % 5ms per frame
    
    for i = 1:length(plot_rois)
        roi = plot_rois(i);
        
        % Plot traditional method
        subplot(4, 3, (i-1)*3 + 1);
        plot(time_ms, dF_traditional(:, roi), 'b-', 'LineWidth', 1);
        title(sprintf('Traditional - ROI %d', roi));
        ylabel('ΔF/F'); xlabel('Time (ms)');
        ylim([-0.02, 0.1]); grid on;
        
        % Plot rolling median method
        subplot(4, 3, (i-1)*3 + 2);
        plot(time_ms, dF_rolling(:, roi), 'r-', 'LineWidth', 1);
        title(sprintf('Rolling Median (%dms) - ROI %d', window_ms, roi));
        ylabel('ΔF/F'); xlabel('Time (ms)');
        ylim([-0.02, 0.1]); grid on;
        
        % Plot both together with baselines
        subplot(4, 3, (i-1)*3 + 3);
        plot(time_ms, traces(:, roi), 'k-', 'LineWidth', 0.5, 'DisplayName', 'Raw');
        hold on;
        plot(time_ms, baseline_rolling(:, roi), 'r-', 'LineWidth', 2, 'DisplayName', 'Rolling Baseline');
        
        % Traditional baseline
        baseline_frames = 1:200;
        trad_baseline = mean(traces(baseline_frames, roi));
        plot(time_ms, repmat(trad_baseline, n_frames, 1), 'b--', 'LineWidth', 2, 'DisplayName', 'Traditional Baseline');
        
        title(sprintf('Baselines - ROI %d', roi));
        ylabel('Fluorescence'); xlabel('Time (ms)');
        if i == 1
            legend('Location', 'best');
        end
        grid on;
    end
    
    % Add summary text
    sgtitle(sprintf('Rolling Median Test Results (Window: %dms, Signal Preservation: %.1f%%, Noise Reduction: %.1f%%)', ...
                   window_ms, results.signal_preservation*100, results.noise_reduction*100), ...
           'FontSize', 14, 'FontWeight', 'bold');
    
    % Summary statistics subplot (bottom)
    figure('Position', [1500, 100, 600, 400], 'Name', 'Performance Summary');
    
    metrics = [results.signal_preservation * 100, ...
               abs(results.noise_reduction) * 100, ...
               results.time / 0.01]; % Relative to 0.01s baseline
    
    metric_names = {'Signal Preservation (%)', 'Noise Reduction (%)', 'Processing Time (relative)'};
    colors = [0.2 0.7 0.2; 0.2 0.2 0.7; 0.7 0.2 0.2];
    
    bar(metrics, 'FaceColor', 'flat', 'CData', colors);
    set(gca, 'XTickLabel', metric_names, 'XTickLabelRotation', 45);
    title('Rolling Median Performance Metrics');
    ylabel('Value');
    grid on;
    
    % Add target lines
    hold on;
    plot([0.5, 3.5], [95, 95], 'g--', 'LineWidth', 2, 'DisplayName', 'Target: 95%');
    plot([1.5, 2.5], [10, 10], 'g--', 'LineWidth', 2, 'DisplayName', 'Target: 10%');
    
    ylim([0, max(metrics) * 1.1]);
end

function traces_clean = readExcelFileBasic(filepath)
    % Basic Excel file reader for standalone mode
    
    fprintf('  Reading Excel file (basic mode)...\n');
    
    try
        % Try readcell first (newer MATLAB)
        raw = readcell(filepath, 'NumHeaderLines', 0);
    catch
        % Fallback to xlsread
        [~, ~, raw] = xlsread(filepath); %#ok<XLSRD>
    end
    
    if size(raw, 1) < 3
        error('File has insufficient data rows');
    end
    
    % Extract headers (row 2)
    headers = raw(2, :);
    
    % Extract data (rows 3+)
    data_rows = raw(3:end, :);
    
    % Convert to numeric
    [n_rows, n_cols] = size(data_rows);
    traces_clean = NaN(n_rows, n_cols-1, 'single'); % Skip first column (time)
    validHeaders = cell(n_cols-1, 1);
    
    valid_col = 0;
    for col = 2:n_cols % Skip first column
        col_data = data_rows(:, col);
        
        % Convert to numeric
        numeric_data = NaN(n_rows, 1);
        for row = 1:n_rows
            if isnumeric(col_data{row}) && isfinite(col_data{row})
                numeric_data(row) = single(col_data{row});
            end
        end
        
        % Check if column has enough valid data
        if sum(isfinite(numeric_data)) > n_rows * 0.5
            valid_col = valid_col + 1;
            traces_clean(:, valid_col) = numeric_data;
            if col <= length(headers)
                validHeaders{valid_col} = char(headers{col});
            else
                validHeaders{valid_col} = sprintf('ROI_%d', valid_col);
            end
        end
    end
    
    % Trim to actual size
    traces_clean = traces_clean(:, 1:valid_col);
    validHeaders = validHeaders(1:valid_col);
    
    fprintf('  Extracted %d frames × %d ROIs\n', size(traces_clean, 1), size(traces_clean, 2));
end

function cfg = createBasicConfig()
    % Create basic configuration for standalone mode
    
    cfg = struct();
    cfg.timing = struct();
    cfg.timing.STIMULUS_FRAME = 267;
    cfg.timing.BASELINE_FRAMES = 1:200;
    cfg.timing.MS_PER_FRAME = 5;
    cfg.timing.POST_STIMULUS_WINDOW = 30;
    
    cfg.thresholds = struct();
    cfg.thresholds.SD_MULTIPLIER = 3;
    cfg.thresholds.DEFAULT_THRESHOLD = 0.02;
    cfg.thresholds.LOW_NOISE_CUTOFF = 0.02;
end

function result = ternary(condition, trueVal, falseVal)
    % Utility function for ternary operator
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end