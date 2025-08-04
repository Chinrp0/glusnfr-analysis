function utils = plot_utils()
    % PLOT_UTILS - Enhanced plotting utilities with consistency fixes and caching
    
    % Initialize persistent cache for performance
    persistent colorCache layoutCache;
    if isempty(colorCache), colorCache = containers.Map(); end
    if isempty(layoutCache), layoutCache = containers.Map(); end
    
    % Return function handles
    utils.calculateOptimalLayout = @calculateOptimalLayout;
    utils.extractGenotypeFromGroupKey = @extractGenotypeFromGroupKey;
    utils.createColorScheme = @createColorScheme;
    utils.setupFigureDefaults = @setupFigureDefaults;
    utils.savePlotWithFormat = @savePlotWithFormat;
    utils.getFigureConfig = @getFigureConfig;
    utils.createStandardFigure = @createStandardFigure;
    utils.addStandardElements = @addStandardElements;
    utils.formatSubplot = @formatSubplot;
    
    % NEW: Enhanced utilities
    utils.getPlotColors = @getPlotColors;                  % Consistent color schemes
    utils.calculatePlotLayout = @calculatePlotLayout;      % Enhanced layout calculation
    utils.shouldSkipPlot = @shouldSkipPlot;               % Early exit logic
    utils.clearPlotCache = @clearPlotCache;               % Cache management
    utils.getOptimalFigureType = @getOptimalFigureType;   % Auto figure type selection
end

function config = getFigureConfig()
    % Get standardized figure configuration
    
    config = struct();
    
    % Enhanced figure positions with better aspect ratios
    config.positions = struct();
    config.positions.standard = [50, 50, 1920, 1080];      % 16:9 aspect ratio
    config.positions.wide = [50, 200, 2560, 800];          % Ultra-wide for coverslips  
    config.positions.compact = [100, 100, 1200, 600];      % Compact 2:1 ratio
    
    % Standard figure properties
    config.properties = struct();
    config.properties.Visible = 'off';
    config.properties.Color = 'white';
    config.properties.Renderer = 'painters';
    config.properties.PaperPositionMode = 'auto';
    
    % Optimized subplot margins
    config.margins = struct();
    config.margins.left = 0.06;       % Slightly more room for y-labels
    config.margins.right = 0.02;
    config.margins.top = 0.08;
    config.margins.bottom = 0.08;
    config.margins.hspace = 0.04;     % Horizontal spacing between subplots
    config.margins.vspace = 0.06;     % Vertical spacing between subplots
    
    % Font settings
    config.fonts = struct();
    config.fonts.title = 12;
    config.fonts.subtitle = 10;
    config.fonts.axis_label = 9;
    config.fonts.tick_label = 8;
    config.fonts.legend = 9;
    
    % Line widths
    config.lines = struct();
    config.lines.trace = 1.0;
    config.lines.threshold = 1.5;
    config.lines.stimulus = 1.0;
    config.lines.average = 2.0;
end

function fig = createStandardFigure(figureType, titleText, cfg)
    % ENHANCED: Create standardized figure with auto-type selection
    
    if nargin < 1, figureType = 'standard'; end
    if nargin < 2, titleText = ''; end
    if nargin < 3, cfg = GluSnFRConfig(); end
    
    config = getFigureConfig();
    
    % Auto-select figure type if enabled
    if strcmp(figureType, 'auto') && cfg.plotting.AUTO_FIGURE_TYPE
        figureType = getOptimalFigureType(titleText, cfg);
    end
    
    % Select position based on type
    switch figureType
        case 'wide'
            position = config.positions.wide;
        case 'compact' 
            position = config.positions.compact;
        otherwise
            position = config.positions.standard;
    end
    
    % Create figure with enhanced properties
    fig = figure('Position', position, ...
                 'Visible', config.properties.Visible, ...
                 'Color', config.properties.Color, ...
                 'Renderer', config.properties.Renderer, ...
                 'PaperPositionMode', config.properties.PaperPositionMode, ...
                 'InvertHardcopy', 'off');  % Better for saving
    
    % Add title if provided
    if ~isempty(titleText)
        sgtitle(titleText, 'FontSize', config.fonts.title, ...
                'FontWeight', 'bold', 'Interpreter', 'none');
    end
end

function addStandardElements(timeData_ms, stimulusTime_ms, threshold, cfg, varargin)
    % FIXED: Add standard plot elements with proper config respect
    
    % Parse optional inputs
    p = inputParser;
    addParameter(p, 'ShowThreshold', true, @islogical);
    addParameter(p, 'ShowStimulus', true, @islogical);
    addParameter(p, 'StimulusColor', cfg.colors.STIMULUS, @isnumeric);
    addParameter(p, 'ThresholdColor', cfg.colors.THRESHOLD, @isnumeric);
    addParameter(p, 'PPFTimepoint', [], @isnumeric);
    addParameter(p, 'StimulusStyle', 'line', @ischar);
    parse(p, varargin{:});
    
    config = getFigureConfig();
    
    % Set y-limits first
    ylim(cfg.plotting.Y_LIMITS);
    
    % FIXED: Properly respect config stimulus marker style
    if p.Results.ShowStimulus
        stimulusStyle = p.Results.StimulusStyle;
        
        % FIXED: Actually use the config value if available
        if isfield(cfg.plotting, 'STIMULUS_MARKER_STYLE')
            stimulusStyle = cfg.plotting.STIMULUS_MARKER_STYLE;
        end
        
        % Use config colors and width
        stimColor = cfg.plotting.STIMULUS_COLOR;
        stimWidth = cfg.plotting.STIMULUS_WIDTH;
        
        switch lower(stimulusStyle)
            case 'line'
                % Primary stimulus line
                plot([stimulusTime_ms, stimulusTime_ms], cfg.plotting.Y_LIMITS, ...
                     ':', 'Color', stimColor, 'LineWidth', stimWidth, 'HandleVisibility', 'off');
                
                % ENHANCED: Add second stimulus for PPF with proper color
                if ~isempty(p.Results.PPFTimepoint) && cfg.plotting.ENABLE_DUAL_STIMULI
                    stimulusTime_ms2 = stimulusTime_ms + p.Results.PPFTimepoint;
                    plot([stimulusTime_ms2, stimulusTime_ms2], cfg.plotting.Y_LIMITS, ...
                         ':', 'Color', cfg.plotting.PPF_STIMULUS2_COLOR, ...
                         'LineWidth', stimWidth, 'HandleVisibility', 'off');
                end
                
            case 'pentagram'
                % Pentagram markers at bottom of plot
                stimY = cfg.plotting.Y_LIMITS(1) + 0.002;  % Slightly above bottom
                plot(stimulusTime_ms, stimY, 'pentagram', ...
                     'Color', stimColor, 'MarkerSize', 8, ...
                     'MarkerFaceColor', stimColor, 'HandleVisibility', 'off');
                
                % Second stimulus for PPF
                if ~isempty(p.Results.PPFTimepoint) && cfg.plotting.ENABLE_DUAL_STIMULI
                    stimulusTime_ms2 = stimulusTime_ms + p.Results.PPFTimepoint;
                    plot(stimulusTime_ms2, stimY, 'pentagram', ...
                         'Color', cfg.plotting.PPF_STIMULUS2_COLOR, 'MarkerSize', 8, ...
                         'MarkerFaceColor', cfg.plotting.PPF_STIMULUS2_COLOR, 'HandleVisibility', 'off');
                end
                
            otherwise
                % Default to line if unknown style
                plot([stimulusTime_ms, stimulusTime_ms], cfg.plotting.Y_LIMITS, ...
                     '-', 'Color', stimColor, 'LineWidth', stimWidth, 'HandleVisibility', 'off');
        end
    end
    
    % Add threshold line with consistent styling
    if p.Results.ShowThreshold && isfinite(threshold)
        thresholdEnd = min(timeData_ms(100), timeData_ms(end));
        plot([timeData_ms(1), thresholdEnd], [threshold, threshold], ...
             '--', 'Color', p.Results.ThresholdColor, ...
             'LineWidth', config.lines.threshold, 'HandleVisibility', 'off');
    end
    
    % Standard formatting
    formatSubplot();
end

function [nRows, nCols] = calculateOptimalLayout(nSubplots)
    % ENHANCED: Calculate optimal subplot layout with caching
    
    persistent layoutCache;
    if isempty(layoutCache)
        layoutCache = containers.Map('KeyType', 'int32', 'ValueType', 'any');
    end
    
    % Check cache first
    if isKey(layoutCache, nSubplots)
        cached = layoutCache(nSubplots);
        nRows = cached(1);
        nCols = cached(2);
        return;
    end
    
    % Calculate optimal layout
    if nSubplots <= 1
        nRows = 1; nCols = 1;
    elseif nSubplots <= 2
        nRows = 1; nCols = 2;
    elseif nSubplots <= 4
        nRows = 2; nCols = 2;
    elseif nSubplots <= 6
        nRows = 2; nCols = 3;
    elseif nSubplots <= 9
        nRows = 3; nCols = 3;
    elseif nSubplots <= 12
        nRows = 3; nCols = 4;
    elseif nSubplots <= 16
        nRows = 4; nCols = 4;
    else
        % For more than 16, use aspect ratio optimization
        aspectRatio = 16/9;  % Target aspect ratio
        nCols = ceil(sqrt(nSubplots * aspectRatio));
        nRows = ceil(nSubplots / nCols);
    end
    
    % Cache the result
    layoutCache(nSubplots) = [nRows, nCols];
end

function layout = calculatePlotLayout(numPlots, varargin)
    % NEW: Enhanced layout calculation with options
    
    p = inputParser;
    addParameter(p, 'Type', 'optimal', @ischar);        % 'optimal', 'square', 'wide'
    addParameter(p, 'MaxPerFigure', 12, @isnumeric);
    addParameter(p, 'AspectRatio', 16/9, @isnumeric);
    parse(p, varargin{:});
    
    maxPlotsPerFigure = p.Results.MaxPerFigure;
    numFigures = ceil(numPlots / maxPlotsPerFigure);
    
    layout = struct();
    layout.numFigures = numFigures;
    layout.figures = cell(numFigures, 1);
    
    for figNum = 1:numFigures
        startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
        endPlot = min(figNum * maxPlotsPerFigure, numPlots);
        numPlotsThisFig = endPlot - startPlot + 1;
        
        [nRows, nCols] = calculateOptimalLayout(numPlotsThisFig);
        
        layout.figures{figNum} = struct(...
            'startPlot', startPlot, ...
            'endPlot', endPlot, ...
            'numPlots', numPlotsThisFig, ...
            'nRows', nRows, ...
            'nCols', nCols);
    end
end

function colors = getPlotColors(experimentType, genotype, plotType, cfg)
    % NEW: Consistent color scheme function
    
    persistent colorCache;
    if isempty(colorCache)
        colorCache = containers.Map();
    end
    
    % Create cache key
    cacheKey = sprintf('%s_%s_%s', experimentType, genotype, plotType);
    
    if isKey(colorCache, cacheKey)
        colors = colorCache(cacheKey);
        return;
    end
    
    % Generate colors based on context
    switch lower(plotType)
        case 'trials'
            colors = createColorScheme(10, 'trials');
            
        case 'genotype'
            if strcmp(genotype, 'WT')
                colors = cfg.colors.WT;
            elseif strcmp(genotype, 'R213W')
                colors = cfg.colors.R213W;
            else
                colors = [0, 0, 1];  % Blue for unknown
            end
            
        case 'noise_level'
            colors = [cfg.colors.LOW_NOISE; cfg.colors.HIGH_NOISE];
            
        case 'peak_response'
            colors = [cfg.colors.BOTH_PEAKS; cfg.colors.SINGLE_PEAK];
            
        otherwise
            colors = createColorScheme(5, 'default');
    end
    
    % Cache the result
    colorCache(cacheKey) = colors;
end

function shouldSkip = shouldSkipPlot(plotType, cfg)
    % NEW: Check if plot type should be skipped based on config
    
    shouldSkip = false;
    
    switch lower(plotType)
        case {'individual_trials', 'trials'}
            shouldSkip = ~cfg.plotting.ENABLE_INDIVIDUAL_TRIALS;
        case {'roi_averages', 'averaged'}
            shouldSkip = ~cfg.plotting.ENABLE_ROI_AVERAGES;
        case {'coverslip_averages', 'coverslip'}
            shouldSkip = ~cfg.plotting.ENABLE_COVERSLIP_AVERAGES;
        case 'ppf_individual'
            shouldSkip = ~cfg.plotting.ENABLE_PPF_INDIVIDUAL;
        case 'ppf_averaged'
            shouldSkip = ~cfg.plotting.ENABLE_PPF_AVERAGED;
        case 'metadata'
            shouldSkip = ~cfg.plotting.ENABLE_METADATA_PLOTS;
    end
end

function figureType = getOptimalFigureType(titleText, cfg)
    % NEW: Auto-select optimal figure type based on content
    
    if contains(titleText, 'PPF') && ~isempty(cfg.plotting.PPF_FIGURE_TYPE)
        figureType = cfg.plotting.PPF_FIGURE_TYPE;
    elseif contains(titleText, 'Coverslip') && ~isempty(cfg.plotting.COVERSLIP_FIGURE_TYPE)
        figureType = cfg.plotting.COVERSLIP_FIGURE_TYPE;
    else
        figureType = cfg.plotting.DEFAULT_FIGURE_TYPE;
    end
end

function clearPlotCache()
    % NEW: Clear plotting caches to free memory
    
    clear colorCache layoutCache;
    fprintf('Plot caches cleared\n');
end

function genotype = extractGenotypeFromGroupKey(groupKey)
    % Extract genotype from group key
    if contains(groupKey, 'R213W')
        genotype = 'R213W';
    elseif contains(groupKey, 'WT')
        genotype = 'WT';
    else
        genotype = 'Unknown';
    end
end

function colors = createColorScheme(numColors, scheme)
    % Create color schemes for plotting with caching
    
    persistent schemeCache;
    if isempty(schemeCache)
        schemeCache = containers.Map();
    end
    
    cacheKey = sprintf('%s_%d', scheme, numColors);
    if isKey(schemeCache, cacheKey)
        colors = schemeCache(cacheKey);
        return;
    end
    
    if nargin < 2, scheme = 'trials'; end
    
    switch lower(scheme)
        case 'trials'
            colors = [
                0.0 0.0 0.0;      % Black
                0.8 0.2 0.2;      % Red  
                0.2 0.6 0.8;      % Blue
                0.2 0.8 0.2;      % Green
                0.8 0.5 0.2;      % Orange
                0.6 0.2 0.8;      % Purple
                0.8 0.8 0.2;      % Yellow
                0.4 0.4 0.4;      % Gray
                0.0 0.8 0.8;      % Cyan
                0.8 0.0 0.8;      % Magenta
            ];
        case 'genotype'
            colors = [0, 0, 0; 1, 0, 1];  % WT=black, R213W=magenta
        case 'noise_level'
            colors = [0.2, 0.6, 0.2; 0.8, 0.2, 0.2];  % Green=low, Red=high
        otherwise
            colors = lines(numColors);
    end
    
    % Repeat pattern if more colors needed
    if size(colors, 1) < numColors
        repeatFactor = ceil(numColors / size(colors, 1));
        colors = repmat(colors, repeatFactor, 1);
    end
    colors = colors(1:numColors, :);
    
    % Cache the result
    schemeCache(cacheKey) = colors;
end

function setupFigureDefaults()
    % Set optimal figure defaults for publication
    config = getFigureConfig();
    
    set(groot, 'DefaultFigureVisible', config.properties.Visible);
    set(groot, 'DefaultFigureRenderer', config.properties.Renderer);
    set(groot, 'DefaultFigureColor', config.properties.Color);
    set(groot, 'DefaultAxesFontSize', config.fonts.tick_label);
    set(groot, 'DefaultLineLineWidth', config.lines.trace);
end

function success = savePlotWithFormat(fig, filepath, cfg, format)
    % ENHANCED: Save plot with format options and quality controls
    
    if nargin < 4, format = 'png'; end
    
    % Select DPI based on mode
    if cfg.plotting.USE_FAST_MODE
        dpi = cfg.plotting.DPI_FAST;
    else
        dpi = cfg.plotting.DPI_STANDARD;
    end
    
    try
        switch lower(format)
            case 'png'
                if cfg.plotting.ENABLE_ANTIALIASING
                    print(fig, filepath, '-dpng', sprintf('-r%d', dpi), '-painters');
                else
                    print(fig, filepath, '-dpng', sprintf('-r%d', dpi), '-painters', '-noui');
                end
                
            case 'pdf'
                print(fig, filepath, '-dpdf', '-painters');
                
            case 'eps'
                print(fig, filepath, '-depsc', '-painters');
                
            otherwise
                error('Unsupported format: %s', format);
        end
        
        % Also save vector format if enabled
        if cfg.plotting.ENABLE_VECTOR_OUTPUT && strcmp(format, 'png')
            [pathstr, name, ~] = fileparts(filepath);
            pdfPath = fullfile(pathstr, [name '.pdf']);
            print(fig, pdfPath, '-dpdf', '-vector');
        end
        
        success = true;
        
    catch ME
        fprint('Plot save failed: %s', ME.message);
        success = false;
    end
end

function formatSubplot()
    % Apply standard subplot formatting
    
    config = getFigureConfig();
    
    xlabel('Time (ms)', 'FontSize', config.fonts.axis_label);
    ylabel('ΔF/F', 'FontSize', config.fonts.axis_label);
    
    set(gca, 'FontSize', config.fonts.tick_label);
    grid on;
    box on;
end