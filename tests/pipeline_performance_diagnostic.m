function diagnostic_results = pipeline_performance_diagnostic(varargin)
    % PIPELINE_PERFORMANCE_DIAGNOSTIC - Comprehensive bottleneck analysis
    %
    % This tool measures timing, memory usage, and efficiency of each
    % processing step to identify bottlenecks and optimization opportunities.
    %
    % Usage:
    %   results = pipeline_performance_diagnostic()              % Interactive mode
    %   results = pipeline_performance_diagnostic('folder', path) % Specify folder
    %   results = pipeline_performance_diagnostic('debug', true) % Enable debug output
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'folder', '', @ischar);
    addParameter(p, 'debug', false, @islogical);
    addParameter(p, 'save_results', true, @islogical);
    addParameter(p, 'max_files', 5, @isnumeric);  % Limit files for testing
    parse(p, varargin{:});
    
    DEBUG = p.Results.debug;
    
    fprintf('\n========================================================\n');
    fprintf('    GluSnFR Pipeline Performance Diagnostic v1.0       \n');
    fprintf('========================================================\n');
    fprintf('Analyzing processing bottlenecks and optimization opportunities\n\n');
    
    % Initialize diagnostic results
    diagnostic_results = struct();
    diagnostic_results.system_info = [];
    diagnostic_results.step_timings = [];
    diagnostic_results.memory_usage = [];
    diagnostic_results.bottlenecks = [];
    diagnostic_results.recommendations = [];
    
    try
        % Setup and system detection
        addpath(genpath(pwd));
        
        % STEP 1: System capabilities assessment
        fprintf('=== STEP 1: System Assessment ===\n');
        step1_timer = tic;
        system_info = assess_system_capabilities(DEBUG);
        diagnostic_results.system_info = system_info;
        step1_time = toc(step1_timer);
        fprintf('System assessment completed in %.3f seconds\n\n', step1_time);
        
        % STEP 2: Module loading performance
        fprintf('=== STEP 2: Module Loading Performance ===\n');
        step2_timer = tic;
        [modules, loading_times] = time_module_loading(DEBUG);
        diagnostic_results.module_loading = loading_times;
        step2_time = toc(step2_timer);
        fprintf('Module loading completed in %.3f seconds\n\n', step2_time);
        
        % STEP 3: File I/O performance
        fprintf('=== STEP 3: File I/O Performance ===\n');
        data_folder = select_test_folder(p.Results.folder);
        if isempty(data_folder)
            fprintf('No folder selected, skipping file I/O tests\n');
            return;
        end
        
        step3_timer = tic;
        io_performance = test_file_io_performance(data_folder, modules, p.Results.max_files, DEBUG);
        diagnostic_results.io_performance = io_performance;
        step3_time = toc(step3_timer);
        fprintf('File I/O testing completed in %.3f seconds\n\n', step3_time);
        
        % STEP 4: Processing performance (GPU vs CPU)
        fprintf('=== STEP 4: Processing Performance Analysis ===\n');
        step4_timer = tic;
        processing_performance = test_processing_performance(modules, system_info, DEBUG);
        diagnostic_results.processing_performance = processing_performance;
        step4_time = toc(step4_timer);
        fprintf('Processing analysis completed in %.3f seconds\n\n', step4_time);
        
        % STEP 5: Parallel processing efficiency
        fprintf('=== STEP 5: Parallel Processing Efficiency ===\n');
        step5_timer = tic;
        parallel_performance = test_parallel_efficiency(modules, system_info, DEBUG);
        diagnostic_results.parallel_performance = parallel_performance;
        step5_time = toc(step5_timer);
        fprintf('Parallel processing analysis completed in %.3f seconds\n\n', step5_time);
        
        % STEP 6: Memory usage analysis
        fprintf('=== STEP 6: Memory Usage Analysis ===\n');
        step6_timer = tic;
        memory_analysis = analyze_memory_usage(modules, DEBUG);
        diagnostic_results.memory_analysis = memory_analysis;
        step6_time = toc(step6_timer);
        fprintf('Memory analysis completed in %.3f seconds\n\n', step6_time);
        
        % STEP 7: End-to-end pipeline timing
        if ~isempty(io_performance.test_files) && length(io_performance.test_files) > 0
            fprintf('=== STEP 7: End-to-End Pipeline Timing ===\n');
            step7_timer = tic;
            pipeline_timing = test_full_pipeline_timing(io_performance.test_files(1), modules, system_info, DEBUG);
            diagnostic_results.pipeline_timing = pipeline_timing;
            step7_time = toc(step7_timer);
            fprintf('Full pipeline timing completed in %.3f seconds\n\n', step7_time);
        else
            step7_time = 0;
            diagnostic_results.pipeline_timing = struct();
        end
        
        % STEP 8: Generate comprehensive analysis
        fprintf('=== STEP 8: Bottleneck Analysis ===\n');
        total_diagnostic_time = step1_time + step2_time + step3_time + step4_time + step5_time + step6_time + step7_time;
        analysis = generate_bottleneck_analysis(diagnostic_results, total_diagnostic_time, DEBUG);
        diagnostic_results.analysis = analysis;
        
        % Save results if requested
        if p.Results.save_results
            save_diagnostic_results(diagnostic_results);
        end
        
        % Display summary
        display_diagnostic_summary(diagnostic_results);
        
    catch ME
        fprintf('\n❌ DIAGNOSTIC FAILED\n');
        fprintf('Error: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('Location: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
        end
        rethrow(ME);
    end
end

function system_info = assess_system_capabilities(DEBUG)
    % Comprehensive system assessment
    
    system_info = struct();
    
    % MATLAB version
    system_info.matlab_version = version('-release');
    system_info.matlab_year = str2double(system_info.matlab_version(1:4));
    
    % CPU information
    system_info.cpu_cores = feature('numcores');
    system_info.cpu_logical_cores = java.lang.Runtime.getRuntime().availableProcessors();
    
    % Memory information
    try
        [~, sys] = memory;
        system_info.total_memory_gb = sys.PhysicalMemory.Total / 1e9;
        system_info.available_memory_gb = sys.PhysicalMemory.Available / 1e9;
    catch
        system_info.total_memory_gb = NaN;
        system_info.available_memory_gb = NaN;
    end
    
    % Toolbox availability
    system_info.has_parallel_toolbox = license('test', 'Distrib_Computing_Toolbox');
    system_info.has_image_toolbox = license('test', 'Image_Toolbox');
    
    % GPU information
    system_info.gpu_count = gpuDeviceCount();
    if system_info.gpu_count > 0
        try
            gpu = gpuDevice();
            system_info.gpu_name = gpu.Name;
            system_info.gpu_memory_gb = gpu.AvailableMemory / 1e9;
            system_info.gpu_compute_capability = gpu.ComputeCapability;
            system_info.gpu_supports_double = gpu.SupportsDouble;
        catch
            system_info.gpu_name = 'Unknown';
            system_info.gpu_memory_gb = NaN;
        end
    else
        system_info.gpu_name = 'None';
        system_info.gpu_memory_gb = 0;
    end
    
    % Parallel pool status (compatible with MATLAB 2023a)
    if system_info.has_parallel_toolbox
        pool = gcp('nocreate');
        if ~isempty(pool)
            system_info.parallel_pool_size = pool.NumWorkers;
            % Get pool type safely (property name varies by MATLAB version)
            try
                if isprop(pool, 'Type')
                    system_info.parallel_pool_type = pool.Type;
                elseif isprop(pool, 'Cluster') && isprop(pool.Cluster, 'Type')
                    system_info.parallel_pool_type = pool.Cluster.Type;
                else
                    system_info.parallel_pool_type = class(pool);
                end
            catch
                system_info.parallel_pool_type = 'Unknown';
            end
        else
            system_info.parallel_pool_size = 0;
            system_info.parallel_pool_type = 'None';
        end
    else
        system_info.parallel_pool_size = 0;
        system_info.parallel_pool_type = 'Not Available';
    end
    
    if DEBUG
        fprintf('System Assessment:\n');
        fprintf('  MATLAB: %s\n', system_info.matlab_version);
        fprintf('  CPU: %d cores (%d logical)\n', system_info.cpu_cores, system_info.cpu_logical_cores);
        fprintf('  Memory: %.1f GB total, %.1f GB available\n', system_info.total_memory_gb, system_info.available_memory_gb);
        fprintf('  GPU: %s (%.1f GB)\n', system_info.gpu_name, system_info.gpu_memory_gb);
        fprintf('  Parallel: %d workers (%s)\n', system_info.parallel_pool_size, system_info.parallel_pool_type);
    end
end

function [modules, loading_times] = time_module_loading(DEBUG)
    % Time each module loading step
    
    loading_times = struct();
    
    % Time config loading
    tic;
    cfg = GluSnFRConfig();
    loading_times.config = toc;
    
    % Time individual modules
    tic;
    calc = df_calculator();
    loading_times.calculator = toc;
    
    tic;
    filter_mod = roi_filter();
    loading_times.filter = toc;
    
    tic;
    mem_mgr = memory_manager();
    loading_times.memory = toc;
    
    tic;
    str_utils = string_utils(cfg);
    loading_times.string_utils = toc;
    
    % Time full module loader
    tic;
    modules = module_loader();
    loading_times.full_loader = toc;
    
    loading_times.total = loading_times.config + loading_times.calculator + ...
                         loading_times.filter + loading_times.memory + ...
                         loading_times.string_utils + loading_times.full_loader;
    
    if DEBUG
        fprintf('Module Loading Times:\n');
        fprintf('  Config: %.3f ms\n', loading_times.config * 1000);
        fprintf('  Calculator: %.3f ms\n', loading_times.calculator * 1000);
        fprintf('  Filter: %.3f ms\n', loading_times.filter * 1000);
        fprintf('  Memory: %.3f ms\n', loading_times.memory * 1000);
        fprintf('  String Utils: %.3f ms\n', loading_times.string_utils * 1000);
        fprintf('  Full Loader: %.3f ms\n', loading_times.full_loader * 1000);
        fprintf('  Total: %.3f ms\n', loading_times.total * 1000);
    end
end

function data_folder = select_test_folder(specified_folder)
    % Select folder for testing
    
    if ~isempty(specified_folder) && exist(specified_folder, 'dir')
        data_folder = specified_folder;
        return;
    end
    
    % Try default folder first
    default_folder = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\1AP\GPU_Processed_Images_1AP\5_raw_mean';
    if exist(default_folder, 'dir')
        data_folder = default_folder;
        fprintf('Using default test folder: %s\n', data_folder);
        return;
    end
    
    % Ask user to select
    fprintf('Please select a folder containing Excel files for testing:\n');
    data_folder = uigetdir(pwd, 'Select folder with Excel files for performance testing');
    if isequal(data_folder, 0)
        data_folder = '';
    end
end

function io_performance = test_file_io_performance(data_folder, modules, max_files, DEBUG)
    % Test file I/O performance with different methods
    
    io_performance = struct();
    
    % Get test files
    excel_files = dir(fullfile(data_folder, '*.xlsx'));
    test_files = excel_files(1:min(max_files, length(excel_files)));
    io_performance.test_files = test_files;
    io_performance.num_files = length(test_files);
    
    if isempty(test_files)
        fprintf('No Excel files found for I/O testing\n');
        return;
    end
    
    fprintf('Testing I/O performance on %d files...\n', length(test_files));
    
    % Test different reading methods
    methods = {'readcell', 'readmatrix', 'xlsread'};
    timing_results = struct();
    
    for method_idx = 1:length(methods)
        method = methods{method_idx};
        method_times = [];
        
        for file_idx = 1:length(test_files)
            filepath = fullfile(test_files(file_idx).folder, test_files(file_idx).name);
            
            tic;
            try
                switch method
                    case 'readcell'
                        data = readcell(filepath, 'NumHeaderLines', 0);
                    case 'readmatrix'
                        data = readmatrix(filepath, 'NumHeaderLines', 0);
                    case 'xlsread'
                        [~, ~, data] = xlsread(filepath); %#ok<XLSRD>
                end
                method_times(end+1) = toc; %#ok<AGROW>
            catch
                method_times(end+1) = NaN; %#ok<AGROW>
            end
        end
        
        timing_results.(method) = method_times;
        
        if DEBUG
            valid_times = method_times(~isnan(method_times));
            if ~isempty(valid_times)
                fprintf('  %s: %.3f ± %.3f seconds (n=%d)\n', method, ...
                        mean(valid_times), std(valid_times), length(valid_times));
            else
                fprintf('  %s: Failed on all files\n', method);
            end
        end
    end
    
    io_performance.method_timings = timing_results;
    
    % Test current pipeline I/O
    pipeline_times = [];
    for file_idx = 1:length(test_files)
        filepath = fullfile(test_files(file_idx).folder, test_files(file_idx).name);
        
        tic;
        try
            [data, headers, success] = modules.io.reader.readFile(filepath, true);
            if success
                pipeline_times(end+1) = toc; %#ok<AGROW>
            else
                pipeline_times(end+1) = NaN; %#ok<AGROW>
            end
        catch
            pipeline_times(end+1) = NaN; %#ok<AGROW>
        end
    end
    
    io_performance.pipeline_timings = pipeline_times;
    
    if DEBUG
        valid_times = pipeline_times(~isnan(pipeline_times));
        if ~isempty(valid_times)
            fprintf('  Pipeline I/O: %.3f ± %.3f seconds (n=%d)\n', ...
                    mean(valid_times), std(valid_times), length(valid_times));
        end
    end
end

function processing_performance = test_processing_performance(modules, system_info, DEBUG)
    % Compare CPU vs GPU processing performance
    
    processing_performance = struct();
    
    % Create test datasets of different sizes
    test_sizes = [
        struct('name', 'small', 'frames', 300, 'rois', 20);
        struct('name', 'medium', 'frames', 600, 'rois', 50);
        struct('name', 'large', 'frames', 1200, 'rois', 100);
    ];
    
    if system_info.gpu_count == 0
        fprintf('No GPU available, testing CPU only\n');
    end
    
    for size_idx = 1:length(test_sizes)
        test_size = test_sizes(size_idx);
        
        if DEBUG
            fprintf('Testing %s dataset (%d frames x %d ROIs):\n', ...
                    test_size.name, test_size.frames, test_size.rois);
        end
        
        % Create realistic test data
        test_data = create_realistic_test_data(test_size.frames, test_size.rois);
        
        % Test CPU performance
        cpu_times = [];
        for rep = 1:3  % Multiple repetitions for accuracy
            tic;
            [dF_cpu, thresh_cpu, gpu_used] = modules.calc.calculate(test_data, false, struct('memory', 0));
            cpu_times(end+1) = toc; %#ok<AGROW>
            assert(~gpu_used, 'CPU test used GPU');
        end
        
        result = struct();
        result.cpu_time_mean = mean(cpu_times);
        result.cpu_time_std = std(cpu_times);
        
        % Test GPU performance if available
        if system_info.gpu_count > 0
            gpu_times = [];
            for rep = 1:3
                tic;
                [dF_gpu, thresh_gpu, gpu_used] = modules.calc.calculate(test_data, true, ...
                    struct('memory', system_info.gpu_memory_gb));
                gpu_times(end+1) = toc; %#ok<AGROW>
            end
            
            result.gpu_time_mean = mean(gpu_times);
            result.gpu_time_std = std(gpu_times);
            result.speedup = result.cpu_time_mean / result.gpu_time_mean;
            
            % Verify results are equivalent
            max_diff = max(abs(dF_cpu(:) - dF_gpu(:)));
            result.max_difference = max_diff;
            result.results_match = max_diff < 1e-5;
        else
            result.gpu_time_mean = NaN;
            result.speedup = NaN;
            result.results_match = true;
        end
        
        processing_performance.(test_size.name) = result;
        
        if DEBUG
            fprintf('  CPU: %.3f ± %.3f seconds\n', result.cpu_time_mean, result.cpu_time_std);
            if ~isnan(result.gpu_time_mean)
                fprintf('  GPU: %.3f ± %.3f seconds (%.1fx speedup)\n', ...
                        result.gpu_time_mean, result.gpu_time_std, result.speedup);
                fprintf('  Results match: %s (max diff: %.2e)\n', ...
                        string(result.results_match), result.max_difference);
            end
        end
    end
end

function parallel_performance = test_parallel_efficiency(modules, system_info, DEBUG)
    % Test parallel processing efficiency
    
    parallel_performance = struct();
    
    if ~system_info.has_parallel_toolbox
        fprintf('Parallel Computing Toolbox not available\n');
        parallel_performance.available = false;
        return;
    end
    
    parallel_performance.available = true;
    
    % Create multiple test datasets
    num_datasets = min(8, system_info.cpu_cores);
    datasets = cell(num_datasets, 1);
    for i = 1:num_datasets
        datasets{i} = create_realistic_test_data(400, 30);
    end
    
    if DEBUG
        fprintf('Testing parallel efficiency with %d datasets:\n', num_datasets);
    end
    
    % Test sequential processing
    tic;
    for i = 1:num_datasets
        [dF, thresh, gpu_used] = modules.calc.calculate(datasets{i}, false, struct('memory', 0));
    end
    sequential_time = toc;
    
    % Test parallel processing
    if system_info.parallel_pool_size == 0
        % Start a pool for testing
        try
            pool = parpool('local', min(4, system_info.cpu_cores));
            created_pool = true;
        catch
            fprintf('Could not create parallel pool\n');
            parallel_performance.parallel_time = NaN;
            parallel_performance.efficiency = NaN;
            return;
        end
    else
        created_pool = false;
    end
    
    tic;
    parfor i = 1:num_datasets
        calc_local = df_calculator();  % Each worker needs its own instance
        [dF, thresh, gpu_used] = calc_local.calculate(datasets{i}, false, struct('memory', 0));
    end
    parallel_time = toc;
    
    % Clean up pool if we created it
    if created_pool
        delete(gcp('nocreate'));
    end
    
    parallel_performance.sequential_time = sequential_time;
    parallel_performance.parallel_time = parallel_time;
    parallel_performance.speedup = sequential_time / parallel_time;
    parallel_performance.efficiency = parallel_performance.speedup / system_info.cpu_cores;
    
    if DEBUG
        fprintf('  Sequential: %.3f seconds\n', sequential_time);
        fprintf('  Parallel: %.3f seconds\n', parallel_time);
        fprintf('  Speedup: %.1fx\n', parallel_performance.speedup);
        fprintf('  Efficiency: %.1f%% (%.1fx / %d cores)\n', ...
                parallel_performance.efficiency * 100, parallel_performance.speedup, system_info.cpu_cores);
    end
end

function memory_analysis = analyze_memory_usage(modules, DEBUG)
    % Analyze memory usage patterns
    
    memory_analysis = struct();
    
    % Test memory estimation accuracy
    test_configs = [
        struct('rois', 50, 'frames', 600, 'trials', 3);
        struct('rois', 100, 'frames', 1200, 'trials', 5);
        struct('rois', 200, 'frames', 2000, 'trials', 8);
    ];
    
    estimation_results = struct();
    
    for i = 1:length(test_configs)
        config = test_configs(i);
        
        % Get memory estimate
        estimated_mb = modules.memory.estimateMemoryUsage(config.rois, config.frames, config.trials, 'single');
        
        % Measure actual memory usage
        start_memory = get_memory_usage();
        test_data = single(randn(config.frames, config.rois));
        actual_mb = get_memory_usage() - start_memory;
        
        estimation_results.(sprintf('test_%d', i)) = struct(...
            'estimated', estimated_mb, ...
            'actual', actual_mb, ...
            'accuracy', abs(estimated_mb - actual_mb) / actual_mb);
        
        if DEBUG
            fprintf('Memory test %d (%dx%dx%d):\n', i, config.rois, config.frames, config.trials);
            fprintf('  Estimated: %.1f MB\n', estimated_mb);
            fprintf('  Actual: %.1f MB\n', actual_mb);
            fprintf('  Accuracy: %.1f%%\n', (1 - estimation_results.(sprintf('test_%d', i)).accuracy) * 100);
        end
        
        clear test_data;  % Clean up
    end
    
    memory_analysis.estimation_results = estimation_results;
end

function pipeline_timing = test_full_pipeline_timing(test_file, modules, system_info, DEBUG)
    % Time complete pipeline execution
    
    pipeline_timing = struct();
    filepath = fullfile(test_file.folder, test_file.name);
    
    if DEBUG
        fprintf('Testing full pipeline on: %s\n', test_file.name);
    end
    
    % Step-by-step timing
    steps = struct();
    
    % File reading
    tic;
    [rawData, headers, success] = modules.io.reader.readFile(filepath, true);
    steps.file_reading = toc;
    
    if ~success
        fprintf('File reading failed\n');
        return;
    end
    
    % Header extraction
    tic;
    [validHeaders, validColumns] = modules.io.reader.extractHeaders(headers);
    steps.header_extraction = toc;
    
    % Data processing
    tic;
    numericData = single(rawData(:, validColumns));
    steps.data_extraction = toc;
    
    % dF/F calculation
    tic;
    [dF_values, thresholds, gpuUsed] = modules.calc.calculate(numericData, ...
        system_info.gpu_count > 0, struct('memory', system_info.gpu_memory_gb));
    steps.df_calculation = toc;
    
    % ROI filtering
    tic;
    [filteredData, filteredHeaders, filteredThresholds, filterStats] = ...
        modules.filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
    steps.roi_filtering = toc;
    
    % String utilities (filename parsing)
    tic;
    [trialNum, expType, ppiValue, coverslipCell] = modules.utils.extractTrialOrPPI(test_file.name);
    steps.string_parsing = toc;
    
    pipeline_timing.steps = steps;
    pipeline_timing.total_time = sum(struct2array(steps));
    pipeline_timing.gpu_used = gpuUsed;
    
    % Calculate percentages
    step_names = fieldnames(steps);
    percentages = struct();
    for i = 1:length(step_names)
        percentages.(step_names{i}) = steps.(step_names{i}) / pipeline_timing.total_time * 100;
    end
    pipeline_timing.percentages = percentages;
    
    if DEBUG
        fprintf('Pipeline step timings:\n');
        for i = 1:length(step_names)
            step_name = step_names{i};
            fprintf('  %s: %.3f ms (%.1f%%)\n', step_name, steps.(step_name) * 1000, ...
                    percentages.(step_name));
        end
        fprintf('  Total: %.3f ms\n', pipeline_timing.total_time * 1000);
    end
end

function analysis = generate_bottleneck_analysis(diagnostic_results, total_time, DEBUG)
    % Generate comprehensive bottleneck analysis and recommendations
    
    analysis = struct();
    
    % Identify top bottlenecks
    bottlenecks = {};
    
    % Check pipeline timing if available
    if isfield(diagnostic_results, 'pipeline_timing') && ~isempty(diagnostic_results.pipeline_timing)
        steps = diagnostic_results.pipeline_timing.steps;
        percentages = diagnostic_results.pipeline_timing.percentages;
        
        step_names = fieldnames(steps);
        [sorted_times, sort_idx] = sort(struct2array(steps), 'descend');
        
        % Top 3 slowest steps are potential bottlenecks
        for i = 1:min(3, length(sorted_times))
            step_name = step_names{sort_idx(i)};
            if percentages.(step_name) > 20  % More than 20% of total time
                bottlenecks{end+1} = sprintf('%s (%.1f%% of pipeline time)', step_name, percentages.(step_name)); %#ok<AGROW>
            end
        end
    end
    
    % Check GPU efficiency
    if isfield(diagnostic_results, 'processing_performance')
        proc_perf = diagnostic_results.processing_performance;
        if isfield(proc_perf, 'medium') && ~isnan(proc_perf.medium.speedup)
            if proc_perf.medium.speedup < 1.5
                bottlenecks{end+1} = 'GPU provides minimal speedup - consider CPU-only processing';
            elseif proc_perf.medium.speedup > 4
                analysis.gpu_recommendation = 'GPU is highly effective - ensure GPU path is always used';
            end
        end
    end
    
    % Check parallel efficiency
    if isfield(diagnostic_results, 'parallel_performance') && diagnostic_results.parallel_performance.available
        par_perf = diagnostic_results.parallel_performance;
        if par_perf.efficiency < 0.3
            bottlenecks{end+1} = sprintf('Poor parallel efficiency (%.1f%%) - overhead exceeds benefits', par_perf.efficiency * 100);
        end
    end
    
    % Check memory usage
    if isfield(diagnostic_results, 'memory_analysis')
        % Add memory-related bottleneck detection if needed
    end
    
    analysis.bottlenecks = bottlenecks;
    
    % Generate recommendations
    recommendations = {};
    
    % System-specific recommendations
    system_info = diagnostic_results.system_info;
    
    if system_info.gpu_count > 0 && system_info.gpu_memory_gb < 4
        recommendations{end+1} = 'GPU has limited memory - consider reducing batch sizes or using CPU for large datasets';
    end
    
    if system_info.available_memory_gb < 8
        recommendations{end+1} = 'Limited system memory - enable memory optimization and reduce concurrent processing';
    end
    
    if system_info.has_parallel_toolbox && system_info.parallel_pool_size == 0
        recommendations{end+1} = 'Parallel toolbox available but no pool active - consider starting a pool for better performance';
    end
    
    % Performance-based recommendations
    if isfield(diagnostic_results, 'io_performance') && ~isempty(diagnostic_results.io_performance.method_timings)
        % Find fastest I/O method
        timings = diagnostic_results.io_performance.method_timings;
        methods = fieldnames(timings);
        mean_times = [];
        for i = 1:length(methods)
            times = timings.(methods{i});
            valid_times = times(~isnan(times));
            if ~isempty(valid_times)
                mean_times(i) = mean(valid_times);
            else
                mean_times(i) = Inf;
            end
        end
        [~, best_idx] = min(mean_times);
        if ~isinf(mean_times(best_idx))
            recommendations{end+1} = sprintf('Consider using %s for file I/O (fastest method tested)', methods{best_idx});
        end
    end
    
    analysis.recommendations = recommendations;
    analysis.diagnostic_time = total_time;
    analysis.timestamp = datetime('now');
end

function save_diagnostic_results(diagnostic_results)
    % Save comprehensive diagnostic results
    
    timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    filename = sprintf('pipeline_diagnostic_%s.mat', timestamp);
    
    save(filename, 'diagnostic_results');
    fprintf('Diagnostic results saved to: %s\n', filename);
    
    % Also save a summary report
    report_filename = sprintf('diagnostic_report_%s.txt', timestamp);
    fid = fopen(report_filename, 'w');
    if fid ~= -1
        fprintf(fid, 'GluSnFR Pipeline Performance Diagnostic Report\n');
        fprintf(fid, '==============================================\n\n');
        fprintf(fid, 'Generated: %s\n\n', char(diagnostic_results.analysis.timestamp));
        
        fprintf(fid, 'System Information:\n');
        fprintf(fid, '  MATLAB: %s\n', diagnostic_results.system_info.matlab_version);
        fprintf(fid, '  CPU: %d cores\n', diagnostic_results.system_info.cpu_cores);
        fprintf(fid, '  Memory: %.1f GB\n', diagnostic_results.system_info.total_memory_gb);
        fprintf(fid, '  GPU: %s\n', diagnostic_results.system_info.gpu_name);
        fprintf(fid, '\n');
        
        if ~isempty(diagnostic_results.analysis.bottlenecks)
            fprintf(fid, 'Identified Bottlenecks:\n');
            for i = 1:length(diagnostic_results.analysis.bottlenecks)
                fprintf(fid, '  - %s\n', diagnostic_results.analysis.bottlenecks{i});
            end
            fprintf(fid, '\n');
        end
        
        if ~isempty(diagnostic_results.analysis.recommendations)
            fprintf(fid, 'Recommendations:\n');
            for i = 1:length(diagnostic_results.analysis.recommendations)
                fprintf(fid, '  - %s\n', diagnostic_results.analysis.recommendations{i});
            end
        end
        
        fclose(fid);
        fprintf('Diagnostic report saved to: %s\n', report_filename);
    end
end

function display_diagnostic_summary(diagnostic_results)
    % Display comprehensive diagnostic summary
    
    fprintf('\n========================================================\n');
    fprintf('    DIAGNOSTIC SUMMARY                                 \n');
    fprintf('========================================================\n\n');
    
    % System overview
    sys = diagnostic_results.system_info;
    fprintf('System Configuration:\n');
    fprintf('  MATLAB %s on %d-core CPU\n', sys.matlab_version, sys.cpu_cores);
    fprintf('  %.1f GB RAM, GPU: %s\n', sys.total_memory_gb, sys.gpu_name);
    fprintf('  Parallel: %s\n\n', ternary(sys.has_parallel_toolbox, 'Available', 'Not Available'));
    
    % Performance highlights
    if isfield(diagnostic_results, 'processing_performance') && isfield(diagnostic_results.processing_performance, 'medium')
        perf = diagnostic_results.processing_performance.medium;
        fprintf('Processing Performance (Medium Dataset):\n');
        fprintf('  CPU: %.3f seconds\n', perf.cpu_time_mean);
        if ~isnan(perf.gpu_time_mean)
            fprintf('  GPU: %.3f seconds (%.1fx speedup)\n', perf.gpu_time_mean, perf.speedup);
        end
        fprintf('\n');
    end
    
    % Bottlenecks
    if ~isempty(diagnostic_results.analysis.bottlenecks)
        fprintf('⚠️  IDENTIFIED BOTTLENECKS:\n');
        for i = 1:length(diagnostic_results.analysis.bottlenecks)
            fprintf('  %d. %s\n', i, diagnostic_results.analysis.bottlenecks{i});
        end
        fprintf('\n');
    else
        fprintf('✅ No significant bottlenecks identified\n\n');
    end
    
    % Recommendations
    if ~isempty(diagnostic_results.analysis.recommendations)
        fprintf('💡 OPTIMIZATION RECOMMENDATIONS:\n');
        for i = 1:length(diagnostic_results.analysis.recommendations)
            fprintf('  %d. %s\n', i, diagnostic_results.analysis.recommendations{i});
        end
        fprintf('\n');
    end
    
    fprintf('Diagnostic completed in %.2f seconds\n', diagnostic_results.analysis.diagnostic_time);
    fprintf('========================================================\n\n');
end

% Helper functions
function memory_mb = get_memory_usage()
    % Get current memory usage in MB
    try
        [~, sys] = memory;
        memory_mb = (sys.PhysicalMemory.Total - sys.PhysicalMemory.Available) / 1e6;
    catch
        memory_mb = 0;
    end
end

function test_data = create_realistic_test_data(num_frames, num_rois)
    % Create realistic test data for performance testing
    F0_values = 80 + 40 * rand(1, num_rois);
    noise_level = 0.01;
    test_data = repmat(F0_values, num_frames, 1) .* (1 + noise_level * randn(num_frames, num_rois));
    test_data = single(test_data);
end

function result = ternary(condition, true_val, false_val)
    % Simple ternary operator
    if condition
        result = true_val;
    else
        result = false_val;
    end
end