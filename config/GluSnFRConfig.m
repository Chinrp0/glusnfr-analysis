function config = GluSnFRConfig()
    % GLUSNFRCONFIG - Enhanced configuration for GluSnFR analysis pipeline
    % 
    % This centralizes all constants and parameters used throughout
    % the analysis pipeline, eliminating magic numbers and making
    % the code more maintainable.
    
    %% Version Info
    config.version = '53'; % Updated version
    config.created = datestr(now, 'yyyy-mm-dd');
    
    %% Timing Parameters (Previously scattered as magic numbers)
    config.timing = struct();
    config.timing.SAMPLING_RATE_HZ = 200;
    config.timing.MS_PER_FRAME = 5;
    config.timing.STIMULUS_FRAME = 267;
    config.timing.STIMULUS_TIME_MS = 1335; % 267 * 5ms
    config.timing.BASELINE_FRAMES = 1:200;
    config.timing.POST_STIMULUS_WINDOW = 30; % 150ms
    
    %% Threshold Parameters  
    config.thresholds = struct();
    config.thresholds.SD_MULTIPLIER = 3;
    config.thresholds.LOW_NOISE_CUTOFF = 0.02;
    config.thresholds.HIGH_NOISE_MULTIPLIER = 1.5; % NOW USED in roi_filter.m
    config.thresholds.DEFAULT_THRESHOLD = 0.02;     % USED in df_calculator.m
    config.thresholds.MIN_F0 = 1e-6;
    
    %% NEW: Filtering Parameters (to eliminate more hardcoded values)
    config.filtering = struct();
    config.filtering.THRESHOLD_PERCENTAGE_1AP = 1.0;  % % of threshold for 1AP
    config.filtering.THRESHOLD_PERCENTAGE_PPF = 1.0;  % % of threshold for PPF
    config.filtering.MIN_RESPONSE_AMPLITUDE = 0.005;  % Minimum dF/F amplitude
    config.filtering.MAX_BASELINE_NOISE = 0.05;       % Maximum baseline noise
    config.filtering.ENABLE_DUPLICATE_REMOVAL = false; % Currently disabled
    
    %% Processing Parameters
    config.processing = struct();
    config.processing.USE_SINGLE_PRECISION = true;
    config.processing.GPU_MIN_DATA_SIZE = 50000;
    config.processing.GPU_MEMORY_FRACTION = 0.8;
    config.processing.PARALLEL_MIN_GROUPS = 2;
    
    %% Plotting Parameters
    config.plotting = struct();
    config.plotting.MAX_PLOTS_PER_FIGURE = 12;
    config.plotting.DPI = 300;
    config.plotting.Y_LIMITS = [-0.02, 0.1];
    config.plotting.TRANSPARENCY = 0.7;
    
    %% Colors
    config.colors = struct();
    config.colors.STIMULUS = [0, 0.8, 0];      % Green
    config.colors.THRESHOLD = [0, 0.8, 0];     % Green
    config.colors.WT = [0, 0, 0];              % Black  
    config.colors.R213W = [1, 0, 1];           % Magenta
    
    %% File Patterns (Cached regex patterns)
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
    
    %% NEW: Debug and Logging
    config.debug = struct();
    config.debug.VERBOSE_FILTERING = true;
    config.debug.SAVE_INTERMEDIATE_RESULTS = false;
    config.debug.PLOT_THRESHOLD_DISTRIBUTION = false;
end