function utils = plot_utilities()
    % PLOT_UTILITIES - CLEANED centralized plotting utilities 
    % ONLY functions that are actually used by the plotting system
    
    utils.getPlotConfig = @getPlotConfig;
    utils.createFigure = @createFigure;
    utils.calculateLayout = @calculateLayout;
    utils.addPlotElements = @addPlotElements;
    utils.formatSubplot = @formatSubplot;
    utils.savePlot = @savePlot;
    utils.getColors = @getColors;  % FIXED: Consistent naming
    utils.extractGenotype = @extractGenotype;
    
    % REMOVED: All unused legend functions, threshold style functions, and noise calculations
end

function plotConfig = getPlotConfig(glusnfrConfig)
    % Centralized plotting configuration - CLEANED
    
    plotConfig = struct();
    
    % Essential settings from main config
    plotConfig.dpi = glusnfrConfig.plotting.DPI;
    plotConfig.maxPlotsPerFigure = glusnfrConfig.plotting.MAX_PLOTS_PER_FIGURE;
    plotConfig.timing = glusnfrConfig.timing;
    
    % Visual settings
    plotConfig.ylimits = [-0.02, 0.08];
    plotConfig.transparency = 0.7;
    
    % Figure settings
    plotConfig.figure = struct();
    plotConfig.figure.position = [50, 50, 1920, 1080];
    plotConfig.figure.visible = 'off';
    plotConfig.figure.color = 'white';
    plotConfig.figure.renderer = 'painters';
    
    % Font settings
    plotConfig.fonts = struct();
    plotConfig.fonts.title = 12;
    plotConfig.fonts.subtitle = 10;
    plotConfig.fonts.axis = 9;
    plotConfig.fonts.tick = 8;
    
    % Line settings
    plotConfig.lines = struct();
    plotConfig.lines.trace = 1.0;
    plotConfig.lines.threshold = 1.5;
    plotConfig.lines.stimulus = 1.5;
    
    % Stimulus settings (universal across all plots)
    plotConfig.stimulus = struct();
    plotConfig.stimulus.style = 'line';
    plotConfig.stimulus.color = [0, 0.8, 0]; % Green stimulus line
    plotConfig.stimulus.width = 1.0;
    plotConfig.stimulus.length = 'zero'; % From bottom to zero
    plotConfig.stimulus.enableDual = true;
    plotConfig.stimulus.ppfColor = [0, 0.8, 0.8]; % Cyan for second PPF stimulus
    
    % Figure type controls
    plotConfig.figureTypes = struct();
    plotConfig.figureTypes.default = 'standard';
    plotConfig.figureTypes.ppf = 'wide';
    plotConfig.figureTypes.coverslip = 'standard';
    plotConfig.figureTypes.autoSelect = true;
end

function colors = getColors(colorType, count)
    % CENTRALIZED color system - ALL colors come from here only
    
    if nargin < 2, count = 10; end
    
    switch lower(colorType)
        case 'trials'
            % Consistent trial colors for all plots
            colors = [
                0.0 0.4 0.8;    % Blue (Trial 1)
                0.8 0.2 0.2;    % Red (Trial 2)
                0.2 0.6 0.2;    % Green (Trial 3)
                0.8 0.5 0.0;    % Orange (Trial 4)
                0.6 0.2 0.8;    % Purple (Trial 5)
                0.8 0.8 0.2;    % Yellow (Trial 6)
                0.4 0.4 0.4;    % Gray (Trial 7)
                0.0 0.8 0.8;    % Cyan (Trial 8)
                0.8 0.0 0.8;    % Magenta (Trial 9)
                0.0 0.0 0.0;    % Black (Trial 10)
            ];
            
        case 'genotype'
            colors = [
                0.0 0.0 0.0;    % WT = Black
                1.0 0.0 1.0;    % R213W = Magenta
            ];
            
        case 'noise'
            colors = [
                0.2 0.6 0.2;    % Low noise = Green
                0.8 0.2 0.2;    % High noise = Red
                0.0 0.0 0.0;    % All = Black
            ];
            
        case 'peaks'
            colors = [
                0.0 0.0 0.0;    % Both peaks = Black
                0.8 0.2 0.2;    % Single peak = Red
            ];
            
        otherwise
            % Default to MATLAB's lines colormap
            colors = lines(count);
    end
    
    % Ensure we have enough colors
    if size(colors, 1) < count
        repeatFactor = ceil(count / size(colors, 1));
        colors = repmat(colors, repeatFactor, 1);
    end
    colors = colors(1:count, :);
end

function fig = createFigure(figureType, titleText, plotConfig)
    % Create standardized figure
    
    if nargin < 1, figureType = 'standard'; end
    if nargin < 2, titleText = ''; end
    if nargin < 3, plotConfig = getPlotConfig(GluSnFRConfig()); end
    
    % Auto-select figure type if enabled
    if strcmp(figureType, 'auto') && plotConfig.figureTypes.autoSelect
        if contains(titleText, 'PPF')
            figureType = plotConfig.figureTypes.ppf;
        elseif contains(titleText, 'Coverslip')
            figureType = plotConfig.figureTypes.coverslip;
        else
            figureType = plotConfig.figureTypes.default;
        end
    end
    
    % Adjust position based on figure type
    position = plotConfig.figure.position;
    if strcmp(figureType, 'wide')
        position = [50, 200, 2560, 800];
    elseif strcmp(figureType, 'compact')
        position = [100, 100, 1200, 600];
    end
    
    fig = figure('Position', position, ...
                 'Visible', plotConfig.figure.visible, ...
                 'Color', plotConfig.figure.color, ...
                 'Renderer', plotConfig.figure.renderer, ...
                 'PaperPositionMode', 'auto');
    
    if ~isempty(titleText)
        sgtitle(titleText, 'FontSize', plotConfig.fonts.title, ...
                'FontWeight', 'bold', 'Interpreter', 'none');
    end
end

function [nRows, nCols] = calculateLayout(nSubplots)
    % Calculate optimal subplot layout
    
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
        % For more subplots, optimize for 16:9 aspect ratio
        nCols = ceil(sqrt(nSubplots * 16/9));
        nRows = ceil(nSubplots / nCols);
    end
end

function addPlotElements(timeData_ms, stimulusTime_ms, threshold, plotConfig, varargin)
    % Add plot elements - ONLY stimulus lines and average thresholds
    % Individual trial thresholds are handled directly in plot_1ap.m
    
    % Parse optional inputs
    p = inputParser;
    addParameter(p, 'ShowStimulus', true, @islogical);
    addParameter(p, 'ShowThreshold', true, @islogical);
    addParameter(p, 'PPFTimepoint', [], @isnumeric);
    parse(p, varargin{:});
    
    % Set y-limits first
    ylim(plotConfig.ylimits);
    currentYLim = ylim;
    
    % Add stimulus line(s)
    if p.Results.ShowStimulus
        addStimulusLine(stimulusTime_ms, currentYLim, plotConfig.stimulus);
        
        % Add second stimulus for PPF if enabled
        if ~isempty(p.Results.PPFTimepoint) && plotConfig.stimulus.enableDual
            stimulusTime_ms2 = stimulusTime_ms + p.Results.PPFTimepoint;
            stimConfig2 = plotConfig.stimulus;
            stimConfig2.color = plotConfig.stimulus.ppfColor;
            addStimulusLine(stimulusTime_ms2, currentYLim, stimConfig2);
        end
    end
    
    % Add threshold line (for averages only - trials handle their own thresholds)
    if p.Results.ShowThreshold && isfinite(threshold) && threshold > 0
        % Use green for average threshold lines (full length)
        averageThresholdColor = [0, 0.8, 0]; % Green
        plot([timeData_ms(1), timeData_ms(end)], [threshold, threshold], '--', ...
             'Color', averageThresholdColor, 'LineWidth', plotConfig.lines.threshold, ...
             'HandleVisibility', 'off');
    end
end

function addStimulusLine(stimulusTime_ms, currentYLim, stimConfig)
    % Add stimulus line with configurable appearance and length
    
    % Determine y-range for stimulus line
    switch stimConfig.length
        case 'full'
            yRange = currentYLim;
        case 'zero'
            yRange = [currentYLim(1), 0]; % From ymin to zero
        otherwise
            if isnumeric(stimConfig.length) && length(stimConfig.length) == 2
                yRange = stimConfig.length;
            else
                yRange = [currentYLim(1), 0]; % Default to zero
            end
    end
    
    % Draw stimulus line
    plot([stimulusTime_ms, stimulusTime_ms], yRange, ...
         '--', 'Color', stimConfig.color, 'LineWidth', stimConfig.width, ...
         'HandleVisibility', 'off');
end

function formatSubplot(plotConfig)
    % Apply standard subplot formatting
    
    if nargin < 1, plotConfig = getPlotConfig(GluSnFRConfig()); end
    
    xlabel('Time (ms)', 'FontSize', plotConfig.fonts.axis);
    ylabel('ΔF/F', 'FontSize', plotConfig.fonts.axis);
    set(gca, 'FontSize', plotConfig.fonts.tick);
    grid on;
    box on;
end

function success = savePlot(fig, filepath, plotConfig)
    % Save plot with standard settings
    
    if nargin < 3, plotConfig = getPlotConfig(GluSnFRConfig()); end
    
    success = false;
    
    try
        % Ensure directory exists
        [pathstr, ~, ~] = fileparts(filepath);
        if ~exist(pathstr, 'dir')
            mkdir(pathstr);
        end
        
        % Save plot
        print(fig, filepath, '-dpng', sprintf('-r%d', plotConfig.dpi));
        success = exist(filepath, 'file') > 0;
        
    catch ME
        if GluSnFRConfig().debug.ENABLE_PLOT_DEBUG
            fprintf('    Plot save failed: %s\n', ME.message);
        end
        success = false;
    end
end

function genotype = extractGenotype(groupKey)
    % Extract genotype from group key
    
    if contains(groupKey, 'R213W')
        genotype = 'R213W';
    elseif contains(groupKey, 'WT')
        genotype = 'WT';
    else
        genotype = 'Unknown';
    end
end