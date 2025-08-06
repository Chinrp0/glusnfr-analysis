function config = GluSnFRConfig()
    % GLUSNFRCONFIG - Simplified and performance-optimized configuration
    
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
    
    %% Simplified Threshold Parameters
    config.thresholds = struct();
    config.thresholds.LOW_NOISE_SIGMA = 3.0;        % Direct sigma multiplier for low noise ROIs
    config.thresholds.HIGH_NOISE_SIGMA = 3.5;       % Direct sigma multiplier for high noise ROIs  
    config.thresholds.LOWER_SIGMA = 1.5;            % Direct sigma multiplier for lower threshold
    config.thresholds.SD_NOISE_CUTOFF = 0.0068;     % Standard deviation cutoff for noise classification
   
    %% Filtering Parameters
    config.filtering = struct();
    config.filtering.THRESHOLD_PERCENTAGE_1AP = 1.0;
    config.filtering.THRESHOLD_PERCENTAGE_PPF = 1.0;
    config.filtering.MIN_RESPONSE_AMPLITUDE = 0.01;
    config.filtering.MAX_BASELINE_NOISE = 0.05;
    config.filtering.ENABLE_DUPLICATE_REMOVAL = false;
    config.filtering.ENABLE_ENHANCED_FILTERING = false;
    
    % Schmitt Trigger Filtering Parameters
    config.filtering.USE_SCHMITT_TRIGGER = true;
    config.filtering.schmitt = struct();
    
    % Search windows (frames)
    config.filtering.schmitt.POST_STIM_SEARCH_FRAMES = 50;    % Extended search window
    config.filtering.schmitt.DECAY_ANALYSIS_FRAMES = 50;      % Decay analysis window
    config.filtering.schmitt.PPF_WINDOW1_FRAMES = 50;         % PPF first stimulus window
    config.filtering.schmitt.PPF_WINDOW2_FRAMES = 50;         % PPF second stimulus window
    
    % Signal validation criteria
    config.filtering.schmitt.MIN_SIGNAL_DURATION = 0;         % Minimum frames (0 = no minimum)
    config.filtering.schmitt.PEAK_AMPLITUDE_FACTOR = 1.0;     % Peak must be >= threshold * factor
    config.filtering.schmitt.MAX_DECAY_RATIO = 2.0;           % Maximum allowed decay ratio
    config.filtering.schmitt.SHORT_SIGNAL_THRESHOLD = 10;     % Frames considered "short signal"
    config.filtering.schmitt.MAX_NOISE_RATIO = 0.6;           % Maximum noise-to-signal ratio
    
    %% GPU Processing Parameters
    config.gpu = struct();
    config.gpu.ENABLED = true;
    config.gpu.MIN_DATA_SIZE = 20000;                % Minimum elements to justify GPU usage
    config.gpu.MEMORY_FRACTION = 0.9;               % Fraction of GPU memory to use
    config.gpu.BATCH_SIZE = 100000;                 % Batch size for chunked processing
    config.gpu.CHUNK_OVERLAP = 0.1;                 % Overlap between chunks
    config.gpu.WARMUP_ITERATIONS = 2;               % GPU warmup iterations
    
    %% Processing Parameters
    config.processing = struct();
    config.processing.USE_SINGLE_PRECISION = true;
    config.processing.PARALLEL_MIN_GROUPS = 1;
    config.processing.PARALLEL_MIN_FILES = 2;
    config.processing.MAX_PARALLEL_WORKERS = 6;
    config.processing.ENABLE_MEMORY_POOLING = true;
    config.processing.PREALLOCATE_RESULTS = true;
    config.processing.GARBAGE_COLLECT_FREQUENCY = 5;
    
    %% File I/O Parameters
    config.io = struct();
    config.io.USE_PARALLEL_FILE_READING = true;
    config.io.FILE_READ_BUFFER_SIZE = 8192;
    config.io.EXCEL_READ_METHOD = 'readcell';
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
    
    %% Debug and Logging
    config.debug = struct();
    config.debug.VERBOSE_FILTERING = false;
    config.debug.SAVE_INTERMEDIATE_RESULTS = false;
    config.debug.PLOT_THRESHOLD_DISTRIBUTION = false;
    config.debug.ENABLE_PROFILING = false;
    config.debug.LOG_LEVEL = 'INFO';                      % 'DEBUG', 'INFO', 'WARNING', 'ERROR'
    config.debug.ENABLE_PLOT_DEBUG = true;               % Debug mode for plotting
end