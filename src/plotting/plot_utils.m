function utils = plot_utils()
    % PLOT_UTILS - Comprehensive plotting utilities and configuration
    
    utils.calculateOptimalLayout = @calculateOptimalLayout;
    utils.extractGenotypeFromGroupKey = @extractGenotypeFromGroupKey;
    utils.createColorScheme = @createColorScheme;
    utils.setupFigureDefaults = @setupFigureDefaults;
    utils.savePlotWithFormat = @savePlotWithFormat;
    utils.getFigureConfig = @getFigureConfig;
    utils.createStandardFigure = @createStandardFigure;
    utils.addStandardElements = @addStandardElements;
    utils.formatSubplot = @formatSubplot;
end

function config = getFigureConfig()
    % Get standardized figure configuration
    
    config = struct();
    
    % Standard figure positions (minimized whitespace for larger subplots)
    config.positions = struct();
    config.positions.standard = [50, 50, 1920, 1080];      % Full standard figure
    config.positions.wide = [50, 200, 1600, 800];          % Wide format for coverslips
    config.positions.compact = [100, 100, 1200, 600];      % Compact format
    
    % Standard figure properties
    config.properties = struct();
    config.properties.Visible = 'off';
    config.properties.Color = 'white';
    config.properties.Renderer = 'painters';
    config.properties.PaperPositionMode = 'auto';
    
    % Subplot margins (tighter for more subplot space)
    config.margins = struct();
    config.margins.left = 0.05;
    config.margins.right = 0.02;
    config.margins.top = 0.08;
    config.margins.bottom = 0.08;
    config.margins.hspace = 0.05;  % Horizontal spacing between subplots
    config.margins.vspace = 0.06;  % Vertical spacing between subplots
    
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

function fig = createStandardFigure(figureType, titleText)
    % Create standardized figure with optimized layout
    
    if nargin < 1, figureType = 'standard'; end
    if nargin < 2, titleText = ''; end
    
    config = getFigureConfig();
    
    % Select position based on type
    switch figureType
        case 'wide'
            position = config.positions.wide;
        case 'compact' 
            position = config.positions.compact;
        otherwise
            position = config.positions.standard;
    end
    
    % Create figure with standard properties
    fig = figure('Position', position, ...
                 'Visible', config.properties.Visible, ...
                 'Color', config.properties.Color, ...
                 'Renderer', config.properties.Renderer, ...
                 'PaperPositionMode', config.properties.PaperPositionMode);
    
    % Add title if provided
    if ~isempty(titleText)
        sgtitle(titleText, 'FontSize', config.fonts.title, ...
                'FontWeight', 'bold', 'Interpreter', 'none');
    end
end

function addStandardElements(timeData_ms, stimulusTime_ms, threshold, cfg, varargin)
    % UPDATED: Add standard plot elements with configurable stimulus markers
    
    % Parse optional inputs
    p = inputParser;
    addParameter(p, 'ShowThreshold', true, @islogical);
    addParameter(p, 'ShowStimulus', true, @islogical);
    addParameter(p, 'StimulusColor', cfg.colors.STIMULUS, @isnumeric);
    addParameter(p, 'ThresholdColor', cfg.colors.THRESHOLD, @isnumeric);
    addParameter(p, 'PPFTimepoint', [], @isnumeric);
    addParameter(p, 'StimulusStyle', 'line', @ischar); % 'line' or 'pentagram'
    parse(p, varargin{:});
    
    config = getFigureConfig();
    
    % Set y-limits first
    ylim(cfg.plotting.Y_LIMITS);
    
    % Add stimulus marker(s) with configurable style
    if p.Results.ShowStimulus
        stimulusStyle = p.Results.StimulusStyle;
        
        % Get stimulus marker style from config if available
        if isfield(cfg.plotting, 'STIMULUS_MARKER_STYLE')
            stimulusStyle = cfg.plotting.STIMULUS_MARKER_STYLE;
        end
        
        switch lower(stimulusStyle)
            case 'line'
                % Green vertical line (consistent across all plots)
                plot([stimulusTime_ms, stimulusTime_ms], cfg.plotting.Y_LIMITS, ...
                     '-', 'Color', p.Results.StimulusColor, ...
                     'LineWidth', config.lines.stimulus, 'HandleVisibility', 'off');
                
                % Add second stimulus for PPF
                if ~isempty(p.Results.PPFTimepoint)
                    stimulusTime_ms2 = stimulusTime_ms + p.Results.PPFTimepoint;
                    plot([stimulusTime_ms2, stimulusTime_ms2], cfg.plotting.Y_LIMITS, ...
                         '-', 'Color', 'c', ...
                         'LineWidth', config.lines.stimulus, 'HandleVisibility', 'off');
                end
                
            case 'pentagram'
                % Pentagram markers at bottom of plot
                stimY = cfg.plotting.Y_LIMITS(1);
                plot([stimulusTime_ms, stimulusTime_ms], [stimY, stimY], ...
                     ':pentagram', 'Color', p.Results.StimulusColor, ...
                     'LineWidth', config.lines.stimulus, 'HandleVisibility', 'off');
                
                % Add second stimulus for PPF
                if ~isempty(p.Results.PPFTimepoint)
                    stimulusTime_ms2 = stimulusTime_ms + p.Results.PPFTimepoint;
                    plot([stimulusTime_ms2, stimulusTime_ms2], [stimY, stimY], ...
                         ':pentagram', 'Color', 'c', ...
                         'LineWidth', config.lines.stimulus, 'HandleVisibility', 'off');
                end
                
            otherwise
                % Default to line
                plot([stimulusTime_ms, stimulusTime_ms], cfg.plotting.Y_LIMITS, ...
                     '-', 'Color', p.Results.StimulusColor, ...
                     'LineWidth', config.lines.stimulus, 'HandleVisibility', 'off');
        end
    end
    
    % Add threshold line
    if p.Results.ShowThreshold && isfinite(threshold)
        thresholdEnd = min(timeData_ms(100), timeData_ms(end));
        plot([timeData_ms(1), thresholdEnd], [threshold, threshold], ...
             '--', 'Color', p.Results.ThresholdColor, ...
             'LineWidth', config.lines.threshold, 'HandleVisibility', 'off');
    end
    
    % Standard formatting
    formatSubplot();
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

function [nRows, nCols] = calculateOptimalLayout(nSubplots)
    % Calculate optimal subplot layout for minimal whitespace
    
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
        % For more than 16, use 4 columns
        nCols = 4;
        nRows = ceil(nSubplots / nCols);
    end
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
    % Create color schemes for plotting
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
    % Save plot with specified format and optimal settings
    if nargin < 4, format = 'png'; end
    
    try
        switch lower(format)
            case 'png'
                print(fig, filepath, '-dpng', sprintf('-r%d', cfg.plotting.DPI), '-painters');
            case 'pdf'
                print(fig, filepath, '-dpdf', '-painters');
            case 'eps'
                print(fig, filepath, '-depsc', '-painters');
            otherwise
                error('Unsupported format: %s', format);
        end
        success = true;
    catch
        success = false;
    end
end

function setupFastPlotting()
    % Configure MATLAB for faster plotting
    set(groot, 'DefaultFigureVisible', 'off');
    set(groot, 'DefaultFigureRenderer', 'painters');
    set(groot, 'DefaultFigureInvertHardcopy', 'off');
    set(groot, 'DefaultAxesFontSize', 8);
    set(groot, 'DefaultLineLineWidth', 0.8);
end

function cleanupFastPlotting()
    % Quick cleanup after plotting
    close all;
    drawnow limitrate;
    
    % Only garbage collect if memory is high
    try
        [~, sys] = memory;
        memUsed = (sys.PhysicalMemory.Total - sys.PhysicalMemory.Available) / sys.PhysicalMemory.Total;
        if memUsed > 0.8
            java.lang.System.gc();
        end
    catch
        % Skip if memory check fails
    end
end

function success = savePlotFast(fig, filepath, dpi)
    % Save plot with lower DPI for speed
    if nargin < 3, dpi = 150; end  % Default to 150 instead of 300
    
    try
        print(fig, filepath, '-dpng', sprintf('-r%d', dpi), '-painters');
        success = true;
    catch
        try
            % Fallback with even lower DPI
            print(fig, filepath, '-dpng', '-r100');
            success = true;
        catch
            success = false;
        end
    end
end