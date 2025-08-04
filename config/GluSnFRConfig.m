function config = GluSnFRConfig()
    % GLUSNFRCONFIG - Performance-optimized configuration with enhanced plotting controls
    
    %% Version Info
    version_info = PipelineVersion();
    config.version = version_info.version;
    config.legacy_version = version_info.legacy_version;
    config.build_date = version_info.build_date;
    config.created = datestr(now, 'yyyy-mm-dd');
    
    %% Timing Parameters
    config.timing = struct();
    config.timing.SAMPLING_RATE_HZ = 200;
    config.timing.MS_PER_FRAME = 5;
    config.timing.STIMULUS_FRAME = 267;
    config.timing.STIMULUS_TIME_MS = 1335;
    config.timing.BASELINE_FRAMES = 1:200;
    config.timing.POST_STIMULUS_WINDOW = 30;
    
    %% Threshold Parameters
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
    
    %% Processing Parameters
    config.processing = struct();
    config.processing.USE_SINGLE_PRECISION = true;
    config.processing.GPU_MIN_DATA_SIZE = 20000;
    config.processing.GPU_MEMORY_FRACTION = 0.9;
    config.processing.GPU_BATCH_SIZE = 100000;
    config.processing.GPU_CHUNK_OVERLAP = 0.1;
    config.processing.GPU_WARMUP_ITERATIONS = 2;
    config.processing.PARALLEL_MIN_GROUPS = 1;
    config.processing.PARALLEL_MIN_FILES = 2;
    config.processing.MAX_PARALLEL_WORKERS = 6;
    config.processing.ENABLE_MEMORY_POOLING = true;
    config.processing.PREALLOCATE_RESULTS = true;
    config.processing.GARBAGE_COLLECT_FREQUENCY = 5;
    
    %% File I/O Optimization Parameters
    config.io = struct();
    config.io.USE_PARALLEL_FILE_READING = true;
    config.io.FILE_READ_BUFFER_SIZE = 8192;
    config.io.EXCEL_READ_METHOD = 'auto';
    config.io.CACHE_PARSED_FILES = false;
    config.io.VALIDATE_FILES_PARALLEL = true;

    %% File I/O Parameters
    config.io = struct();
    config.io.USE_PARALLEL_FILE_READING = true;
    config.io.FILE_READ_BUFFER_SIZE = 8192;
    config.io.EXCEL_READ_METHOD = 'readcell';  % Use best method only
    config.io.CACHE_PARSED_FILES = false;
    config.io.VALIDATE_FILES_PARALLEL = true;
    
    %% Excel Output Configuration
    config.output = struct();
    
    % Main Excel output control
    config.output.ENABLE_EXCEL_OUTPUT = true;             % Master switch for all Excel output
    
    % Individual sheet controls
    config.output.ENABLE_INDIVIDUAL_SHEETS = true;        % Raw individual data sheets
    config.output.ENABLE_AVERAGED_SHEETS = true;          % Averaged data sheets
    config.output.ENABLE_NOISE_SEPARATED_SHEETS = true;   % Low_noise/High_noise sheets (1AP)
    config.output.ENABLE_ROI_AVERAGE_SHEET = true;        % ROI_Average sheet
    config.output.ENABLE_TOTAL_AVERAGE_SHEET = true;      % Total_Average sheet
    config.output.ENABLE_METADATA_SHEET = true;           % ROI_Metadata sheet
    
    % Output quality controls
    config.output.ENABLE_VERBOSE_OUTPUT = false;          % Detailed Excel writing messages
    config.output.VALIDATE_EXCEL_WRITES = true;           % Validate Excel files after writing
    config.output.CLEANUP_FAILED_FILES = true;            % Delete incomplete Excel files
    
    %% PLOTTING CONFIGURATION
    config.plotting = struct();

    % ===== INDIVIDUAL PLOT TYPE CONTROLS =====
    config.plotting.ENABLE_INDIVIDUAL_TRIALS = true;
    config.plotting.ENABLE_ROI_AVERAGES = true; 
    config.plotting.ENABLE_COVERSLIP_AVERAGES = true;
    config.plotting.ENABLE_PPF_INDIVIDUAL = true;
    config.plotting.ENABLE_PPF_AVERAGED = true;
    config.plotting.ENABLE_METADATA_PLOTS = false;
    
    % Save/layout settings only
    config.plotting.DPI = 300;
    config.plotting.MAX_PLOTS_PER_FIGURE = 12;
        
    % ===== PERFORMANCE CONTROLS =====
    config.plotting.ENABLE_PARALLEL = true;               % Enable parallel plot generation
    config.plotting.PARALLEL_THRESHOLD = 3;               % Min plots for parallel processing
    config.plotting.MAX_CONCURRENT_PLOTS = 4;             % Max concurrent plot workers
    config.plotting.USE_FAST_MODE = false;                % Fast mode: lower DPI, simplified
    config.plotting.ENABLE_PLOT_CACHING = true;           % Cache layouts, colors, etc.
    config.plotting.EARLY_EXIT_ON_NO_DATA = true;         % Skip plot creation if no data
    
    
    %% File Patterns (cached regex patterns)
    config.patterns = struct();
    config.patterns.PPF_TIMEPOINT = 'PPF-(\d+)ms';
    config.patterns.DOC2B = '_Doc2b-[A-Z0-9]+';
    config.patterns.COVERSLIP = '_Cs(\d+)-c(\d+)_';
    config.patterns.EXPERIMENT = '_(1AP|PPF)';
    config.patterns.ROI_NAME = 'roi[_\s]*(\d+)';
    
    %% Validation
    config.validation = struct();
    config.validation.MIN_FRAMES = 600;
    config.validation.MAX_ROI_NUMBER = 1200;
    config.validation.MIN_BASELINE_FRAMES = 100;
    
    %% Performance Monitoring
    config.performance = struct();
    config.performance.ENABLE_TIMING = true;
    config.performance.ENABLE_MEMORY_MONITORING = true;
    config.performance.ENABLE_GPU_MONITORING = true;
    config.performance.LOG_PERFORMANCE_STATS = true;
    config.performance.BENCHMARK_MODE = false;
    
    %% Adaptive Settings
    config.adaptive = struct();
    config.adaptive.ENABLE_ADAPTIVE_GPU_THRESHOLD = true;
    config.adaptive.ENABLE_ADAPTIVE_PARALLEL_WORKERS = true;
    config.adaptive.ENABLE_ADAPTIVE_BATCH_SIZE = true;
    config.adaptive.LEARNING_RATE = 0.1;
    
    %% Debug and Logging
    config.debug = struct();
    config.debug.VERBOSE_FILTERING = false;
    config.debug.SAVE_INTERMEDIATE_RESULTS = false;
    config.debug.PLOT_THRESHOLD_DISTRIBUTION = false;
    config.debug.ENABLE_PROFILING = false;
    config.debug.LOG_LEVEL = 'INFO';                      % 'DEBUG', 'INFO', 'WARNING', 'ERROR'
    config.debug.ENABLE_PLOT_DEBUG = false;               % Debug mode for plotting
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