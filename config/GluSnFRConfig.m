function config = GluSnFRConfig()
    % GLUSNFRCONFIG - Simplified configuration for GluSnFR analysis pipeline
    % 
    % SIMPLIFIED: Removed complex enhanced filtering parameters
    % Added simple enhanced filtering toggle
    
    %% Version Info
    config.version = '55'; % Updated for simplified enhanced filtering
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
    
    %% Filtering Parameters (SIMPLIFIED)
    config.filtering = struct();
    
    % Basic filtering (existing)
    config.filtering.THRESHOLD_PERCENTAGE_1AP = 1.0;
    config.filtering.THRESHOLD_PERCENTAGE_PPF = 1.0;
    config.filtering.MIN_RESPONSE_AMPLITUDE = 0.01;
    config.filtering.MAX_BASELINE_NOISE = 0.05;
    config.filtering.ENABLE_DUPLICATE_REMOVAL = false;
    
    % SIMPLE enhanced filtering toggle
    config.filtering.ENABLE_ENHANCED_FILTERING = true;    % Enable simple enhanced filtering
    
    % REMOVED: All the complex enhanced filtering parameters
    % The simplified filter uses only 3 hardcoded criteria:
    % 1. SNR >= 3.0
    % 2. Peak timing 5-100ms after stimulus  
    % 3. Peak prominence >= 2% above baseline
    % ROI passes if it meets 2 out of 3 criteria
    
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
    config.plotting.Y_LIMITS = [-0.02, 0.08];
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
end