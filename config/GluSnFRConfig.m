function config = GluSnFRConfigOptimized()
    % GLUSNFRCONFIGOPTIMIZED - Performance-optimized configuration
    % 
    % Changes from original:
    % - Lower GPU threshold for better utilization
    % - Optimized memory fractions
    % - Enhanced parallel processing settings
    % - Improved file I/O parameters
    % - Better plotting performance settings
    
    %% Version Info
    version_info = PipelineVersion();
    config.version = version_info.version;
    config.legacy_version = version_info.legacy_version;
    config.build_date = version_info.build_date;
    config.created = datestr(now, 'yyyy-mm-dd');
    
    %% Timing Parameters (unchanged)
    config.timing = struct();
    config.timing.SAMPLING_RATE_HZ = 200;
    config.timing.MS_PER_FRAME = 5;
    config.timing.STIMULUS_FRAME = 267;
    config.timing.STIMULUS_TIME_MS = 1335;
    config.timing.BASELINE_FRAMES = 1:200;
    config.timing.POST_STIMULUS_WINDOW = 30;
    
    %% Threshold Parameters (unchanged)
    config.thresholds = struct();
    config.thresholds.SD_MULTIPLIER = 3;
    config.thresholds.LOW_NOISE_CUTOFF = 0.02;
    config.thresholds.HIGH_NOISE_MULTIPLIER = 1.5;
    config.thresholds.DEFAULT_THRESHOLD = 0.02;
    config.thresholds.MIN_F0 = 1e-6;
    
    %% Filtering Parameters
    config.filtering = struct();
    config.filtering.THRESHOLD_PERCENTAGE_1AP = 1.0;
    config.filtering.THRESHOLD_PERCENTAGE_PPF = 1.0;
    config.filtering.MIN_RESPONSE_AMPLITUDE = 0.01;
    config.filtering.MAX_BASELINE_NOISE = 0.05;
    config.filtering.ENABLE_DUPLICATE_REMOVAL = false;
    config.filtering.ENABLE_ENHANCED_FILTERING = true;
    
    %% OPTIMIZED: Processing Parameters
    config.processing = struct();
    config.processing.USE_SINGLE_PRECISION = true;
    
    % OPTIMIZED: Lower GPU threshold for better utilization
    config.processing.GPU_MIN_DATA_SIZE = 20000;  % Reduced from 50000
    
    % OPTIMIZED: Higher memory utilization for better performance
    config.processing.GPU_MEMORY_FRACTION = 0.9;  % Increased from 0.8
    
    % NEW: Advanced GPU settings
    config.processing.GPU_BATCH_SIZE = 100000;    % Optimal batch size
    config.processing.GPU_CHUNK_OVERLAP = 0.1;   % 10% overlap for chunked processing
    config.processing.GPU_WARMUP_ITERATIONS = 2; % Warm up GPU for consistent timing
    
    % OPTIMIZED: Parallel processing settings
    config.processing.PARALLEL_MIN_GROUPS = 1;    % Reduced from 2
    config.processing.PARALLEL_MIN_FILES = 2;     % NEW: Min files for parallel processing within groups
    config.processing.MAX_PARALLEL_WORKERS = 6;   % NEW: Limit workers to prevent resource contention
    
    % NEW: Memory management settings
    config.processing.ENABLE_MEMORY_POOLING = true;
    config.processing.PREALLOCATE_RESULTS = true;
    config.processing.GARBAGE_COLLECT_FREQUENCY = 5; % Clean up every 5 groups
    
    %% NEW: File I/O Optimization Parameters
    config.io = struct();
    config.io.USE_PARALLEL_FILE_READING = true;
    config.io.FILE_READ_BUFFER_SIZE = 8192;      % 8KB buffer
    config.io.EXCEL_READ_METHOD = 'auto';        % 'readmatrix', 'readcell', 'auto'
    config.io.CACHE_PARSED_FILES = false;        % Disable caching to save memory
    config.io.VALIDATE_FILES_PARALLEL = true;    % Validate files in parallel
    
    %% OPTIMIZED: Plotting Parameters
    config.plotting = struct();
    config.plotting.MAX_PLOTS_PER_FIGURE = 12;
    config.plotting.DPI = 300;
    config.plotting.Y_LIMITS = [-0.02, 0.08];
    config.plotting.TRANSPARENCY = 0.7;
    
    % NEW: Performance optimizations for plotting
    config.plotting.USE_PARALLEL_PLOTTING = true;
    config.plotting.MAX_PARALLEL_PLOTS = 3;      % Max concurrent plot generation
    config.plotting.RENDERER = 'painters';       % Faster than 'zbuffer' for 2D plots
    config.plotting.FIGURE_VISIBLE = 'off';      % Always create invisible figures
    config.plotting.PRECOMPUTE_LAYOUTS = true;   % Pre-calculate subplot layouts
    config.plotting.VECTORIZED_DATA_PREP = true; % Use vectorized data preparation
    
    % NEW: Memory optimization for plots
    config.plotting.CLOSE_FIGURES_IMMEDIATELY = true;
    config.plotting.OPTIMIZE_LINE_OBJECTS = true; % Combine line segments
    config.plotting.REDUCE_PLOT_RESOLUTION = false; % Keep full resolution
    
    %% Colors (unchanged)
    config.colors = struct();
    config.colors.STIMULUS = [0, 0.8, 0];
    config.colors.THRESHOLD = [0, 0.8, 0];
    config.colors.WT = [0, 0, 0];
    config.colors.R213W = [1, 0, 1];
    
    %% File Patterns (cached regex patterns)
    config.patterns = struct();
    config.patterns.PPF_TIMEPOINT = 'PPF-(\d+)ms';
    config.patterns.DOC2B = '_Doc2b-[A-Z0-9]+';
    config.patterns.COVERSLIP = '_Cs(\d+)-c(\d+)_';
    config.patterns.EXPERIMENT = '_(1AP|PPF)';
    config.patterns.ROI_NAME = 'roi[_\s]*(\d+)';
    
    %% Validation (unchanged)
    config.validation = struct();
    config.validation.MIN_FRAMES = 600;
    config.validation.MAX_ROI_NUMBER = 1200;
    config.validation.MIN_BASELINE_FRAMES = 100;
    
    %% NEW: Performance Monitoring
    config.performance = struct();
    config.performance.ENABLE_TIMING = true;
    config.performance.ENABLE_MEMORY_MONITORING = true;
    config.performance.ENABLE_GPU_MONITORING = true;
    config.performance.LOG_PERFORMANCE_STATS = true;
    config.performance.BENCHMARK_MODE = false; % Set to true for detailed benchmarking
    
    %% NEW: Adaptive Settings
    config.adaptive = struct();
    config.adaptive.ENABLE_ADAPTIVE_GPU_THRESHOLD = true;
    config.adaptive.ENABLE_ADAPTIVE_PARALLEL_WORKERS = true;
    config.adaptive.ENABLE_ADAPTIVE_BATCH_SIZE = true;
    config.adaptive.LEARNING_RATE = 0.1; % How quickly to adapt settings
    
    %% Debug and Logging
    config.debug = struct();
    config.debug.VERBOSE_FILTERING = false;       % Reduced verbosity for performance
    config.debug.SAVE_INTERMEDIATE_RESULTS = false;
    config.debug.PLOT_THRESHOLD_DISTRIBUTION = false;
    config.debug.ENABLE_PROFILING = false;       % Set to true for detailed profiling
    config.debug.LOG_LEVEL = 'INFO';             % 'DEBUG', 'INFO', 'WARNING', 'ERROR'
end

function performanceConfig = getOptimalPerformanceSettings()
    % Get performance-optimized settings based on system capabilities
    
    performanceConfig = struct();
    
    % Detect system capabilities
    numCores = feature('numcores');
    hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox');
    hasGPU = gpuDeviceCount > 0;
    
    if hasGPU
        gpu = gpuDevice();
        gpuMemoryGB = gpu.AvailableMemory / 1e9;
    else
        gpuMemoryGB = 0;
    end
    
    % System memory
    try
        [~, sys] = memory;
        systemMemoryGB = sys.PhysicalMemory.Total / 1e9;
    catch
        systemMemoryGB = 8; % Conservative estimate
    end
    
    % Optimize based on system
    if hasGPU && gpuMemoryGB >= 4
        performanceConfig.gpu_strategy = 'aggressive';
        performanceConfig.gpu_min_data_size = 10000;
        performanceConfig.gpu_memory_fraction = 0.95;
    elseif hasGPU && gpuMemoryGB >= 2
        performanceConfig.gpu_strategy = 'moderate';
        performanceConfig.gpu_min_data_size = 25000;
        performanceConfig.gpu_memory_fraction = 0.85;
    else
        performanceConfig.gpu_strategy = 'conservative';
        performanceConfig.gpu_min_data_size = 50000;
        performanceConfig.gpu_memory_fraction = 0.7;
    end
    
    % Parallel processing optimization
    if hasParallelToolbox && numCores >= 8
        performanceConfig.parallel_strategy = 'aggressive';
        performanceConfig.max_workers = min(8, numCores - 1);
        performanceConfig.parallel_file_threshold = 1;
    elseif hasParallelToolbox && numCores >= 4
        performanceConfig.parallel_strategy = 'moderate';
        performanceConfig.max_workers = min(4, numCores - 1);
        performanceConfig.parallel_file_threshold = 2;
    else
        performanceConfig.parallel_strategy = 'minimal';
        performanceConfig.max_workers = 2;
        performanceConfig.parallel_file_threshold = 4;
    end
    
    % Memory optimization
    if systemMemoryGB >= 32
        performanceConfig.memory_strategy = 'high_performance';
        performanceConfig.preallocation_factor = 1.5;
        performanceConfig.enable_caching = true;
    elseif systemMemoryGB >= 16
        performanceConfig.memory_strategy = 'balanced';
        performanceConfig.preallocation_factor = 1.2;
        performanceConfig.enable_caching = false;
    else
        performanceConfig.memory_strategy = 'conservative';
        performanceConfig.preallocation_factor = 1.0;
        performanceConfig.enable_caching = false;
    end
    
    % I/O optimization
    performanceConfig.io_buffer_size = min(16384, systemMemoryGB * 1024); % Scale with memory
    performanceConfig.parallel_io_threshold = performanceConfig.parallel_file_threshold;
    
    fprintf('Performance configuration optimized for:\n');
    fprintf('  GPU: %s (%.1f GB)\n', performanceConfig.gpu_strategy, gpuMemoryGB);
    fprintf('  Parallel: %s (%d workers)\n', performanceConfig.parallel_strategy, performanceConfig.max_workers);
    fprintf('  Memory: %s (%.1f GB)\n', performanceConfig.memory_strategy, systemMemoryGB);
end

function adaptiveConfig = createAdaptiveConfiguration(baseConfig, performanceHistory)
    % Create adaptive configuration based on performance history
    
    adaptiveConfig = baseConfig;
    
    if nargin < 2 || isempty(performanceHistory)
        return;
    end
    
    % Analyze performance trends
    if isfield(performanceHistory, 'gpu_speedup')
        avgSpeedup = mean(performanceHistory.gpu_speedup);
        
        if avgSpeedup < 1.5  % GPU not providing significant speedup
            adaptiveConfig.processing.GPU_MIN_DATA_SIZE = ...
                adaptiveConfig.processing.GPU_MIN_DATA_SIZE * 1.5;
        elseif avgSpeedup > 3.0  % GPU very effective
            adaptiveConfig.processing.GPU_MIN_DATA_SIZE = ...
                max(10000, adaptiveConfig.processing.GPU_MIN_DATA_SIZE * 0.8);
        end
    end
    
    % Adaptive parallel processing
    if isfield(performanceHistory, 'parallel_efficiency')
        avgEfficiency = mean(performanceHistory.parallel_efficiency);
        
        if avgEfficiency < 0.6  % Poor parallel efficiency
            adaptiveConfig.processing.PARALLEL_MIN_FILES = ...
                adaptiveConfig.processing.PARALLEL_MIN_FILES + 1;
        elseif avgEfficiency > 0.8  % Good parallel efficiency
            adaptiveConfig.processing.PARALLEL_MIN_FILES = ...
                max(1, adaptiveConfig.processing.PARALLEL_MIN_FILES - 1);
        end
    end
    
    fprintf('Configuration adapted based on performance history\n');
end