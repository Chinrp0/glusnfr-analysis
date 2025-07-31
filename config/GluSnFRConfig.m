function config = GluSnFRConfig()
    % GLUSNFRCONFIG - Enhanced configuration for GluSnFR analysis pipeline
    % 
    % Updated with iGlu3Fast optimized parameters and enhanced filtering options
    
    %% Version Info
    config.version = '54'; % Updated for enhanced filtering
    config.created = datestr(now, 'yyyy-mm-dd');
    
    %% Timing Parameters
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
    config.thresholds.HIGH_NOISE_MULTIPLIER = 1.5;
    config.thresholds.DEFAULT_THRESHOLD = 0.02;
    config.thresholds.MIN_F0 = 1e-6;
    
    %% ENHANCED: Filtering Parameters for iGlu3Fast
    config.filtering = struct();
    
    % Basic filtering (existing)
    config.filtering.THRESHOLD_PERCENTAGE_1AP = 1.0;
    config.filtering.THRESHOLD_PERCENTAGE_PPF = 1.0;
    config.filtering.MIN_RESPONSE_AMPLITUDE = 0.005;
    config.filtering.MAX_BASELINE_NOISE = 0.05;
    config.filtering.ENABLE_DUPLICATE_REMOVAL = false;
    
    % NEW: Enhanced filtering for iGlu3Fast ultrafast kinetics
    config.filtering.ENABLE_ENHANCED_FILTERING = true;    % Enable enhanced filtering
    config.filtering.ENABLE_TEMPORAL_VALIDATION = true;   % Temporal characteristics
    config.filtering.ENABLE_KINETIC_ANALYSIS = true;      % Kinetic validation
    config.filtering.ENABLE_COMPARISON_MODE = true;       % Compare with original
    
    % NEW: Temporal validation parameters (optimized for iGlu3Fast)
    config.filtering.MIN_RISE_TIME_MS = 2;                % Faster than iGluSnFR3 (ultrafast)
    config.filtering.MAX_RISE_TIME_MS = 25;               % Very fast response (was 50ms for iGluSnFR3)
    config.filtering.RESPONSE_WINDOW_FRAMES = 20;         % 100ms post-stimulus window
    config.filtering.MIN_SNR = 2.0;                       % Signal-to-noise ratio requirement
    
    % NEW: Kinetic analysis parameters (based on k-2 = 304 s^-1)
    config.filtering.EXPECTED_DECAY_TIME_MS = 3.3;        % τ = 1/304 ≈ 3.3ms
    config.filtering.MAX_DECAY_TIME_CONSTANT_MS = 15;     % Allow up to 5× expected
    config.filtering.MAX_DECAY_RATIO = 0.7;               % Should decay to <70% of peak
    config.filtering.MAX_DECAY_FRAMES = 10;               % 50ms maximum decay analysis
    config.filtering.MIN_RISE_RATE = 0.001;               % Minimum dF/F per frame rise rate
    
    % NEW: Peak characteristics (iGlu3Fast specific)
    config.filtering.MIN_PEAK_WIDTH_MS = 5;               % Minimum signal duration
    config.filtering.MAX_PEAK_WIDTH_MS = 50;              % Maximum signal duration (ultrafast)
    config.filtering.PEAK_SHARPNESS_THRESHOLD = 0.5;      % Peak sharpness requirement
    
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
    
    %% Debug and Logging
    config.debug = struct();
    config.debug.VERBOSE_FILTERING = true;
    config.debug.SAVE_INTERMEDIATE_RESULTS = false;
    config.debug.PLOT_THRESHOLD_DISTRIBUTION = false;
    config.debug.SAVE_FILTERING_COMPARISON = true;        % NEW: Save comparison results
end