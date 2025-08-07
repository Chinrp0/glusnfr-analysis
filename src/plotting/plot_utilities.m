function utils = plot_utilities()
    % PLOT_UTILITIES - Enhanced centralized plotting utilities with threshold styling
    
    utils.getPlotConfig = @getPlotConfig;
    utils.getPlotStyles = @getPlotStyles;  % NEW: Centralized styling configuration
    utils.createFigure = @createFigure;
    utils.calculateLayout = @calculateLayout;
    utils.addPlotElements = @addPlotElements;
    utils.formatSubplot = @formatSubplot;
    utils.savePlot = @savePlot;
    utils.getColors = @getColors;
    utils.extractGenotype = @extractGenotype;
    
    % NEW: Threshold-specific utilities
    utils.createNoiseLevelText = @createNoiseLevelText;
    utils.getThresholdRenderer = @getThresholdRenderer;
end

function styleConfig = getPlotStyles(glusnfrConfig)
    % NEW: Centralized plot styling configuration including threshold styles
    
    styleConfig = struct();
    
    % Import basic config
    basicConfig = getPlotConfig(glusnfrConfig);
    styleConfig = basicConfig; % Inherit all basic settings
    
    % ENHANCED: Threshold styling configuration
    styleConfig.thresholds = struct();
    
    % Threshold colors by context
    styleConfig.thresholds.colors = struct();
    styleConfig.thresholds.colors.average = [0, 0.8, 0];           % Green for averages
    styleConfig.thresholds.colors.individual = 'match_trace';      % Match trace color for individuals
    styleConfig.thresholds.colors.schmitt_upper = [0.8, 0, 0.8];  % Magenta for Schmitt upper
    styleConfig.thresholds.colors.schmitt_lower = [0, 0.8, 0.8];  % Cyan for Schmitt lower
    
    % Line styles by noise level
    styleConfig.thresholds.lineStyles = struct();
    styleConfig.thresholds.lineStyles.low = '--';      % Dashed for low noise
    styleConfig.thresholds.lineStyles.high = '-.';     % Dash-dot for high noise  
    styleConfig.thresholds.lineStyles.unknown = ':';   % Dotted for unknown
    styleConfig.thresholds.lineStyles.average = '--';  % Dashed for averages
    
    % Threshold line properties
    styleConfig.thresholds.lineWidth = 1.0;
    styleConfig.thresholds.transparency = 0.8;
    
    % Threshold window settings
    styleConfig.thresholds.window = struct();
    styleConfig.thresholds.window.start_ms = 1;        % Start time
    styleConfig.thresholds.window.end_ms = 750;        % End time
    styleConfig.thresholds.window.fullTrace = false;   % Whether to span full trace
    
    % Helper functions within the style config
    styleConfig.thresholds.getLineStyle = @(noiseLevel) getThresholdLineStyle(noiseLevel, styleConfig);
    styleConfig.thresholds.getColor = @(context, traceColor) getThresholdColor(context, traceColor, styleConfig);
    styleConfig.thresholds.createRenderer = @(roiNum, noiseLevel, threshold) createThresholdRenderer(roiNum, noiseLevel, threshold, styleConfig);
end

function lineStyle = getThresholdLineStyle(noiseLevel, styleConfig)
    % Get appropriate line style for noise level
    
    switch lower(noiseLevel)
        case 'low'
            lineStyle = styleConfig.thresholds.lineStyles.low;
        case 'high'
            lineStyle = styleConfig.thresholds.lineStyles.high;
        case 'average'
            lineStyle = styleConfig.thresholds.lineStyles.average;
        otherwise
            lineStyle = styleConfig.thresholds.lineStyles.unknown;
    end
end

function color = getThresholdColor(context, traceColor, styleConfig)
    % Get appropriate threshold color based on context
    
    switch lower(context)
        case 'average'
            color = styleConfig.thresholds.colors.average;
        case 'individual'
            if strcmp(styleConfig.thresholds.colors.individual, 'match_trace')
                color = traceColor;
            else
                color = styleConfig.thresholds.colors.individual;
            end
        case 'schmitt_upper'
            color = styleConfig.thresholds.colors.schmitt_upper;
        case 'schmitt_lower'  
            color = styleConfig.thresholds.colors.schmitt_lower;
        otherwise
            color = [0.5, 0.5, 0.5]; % Gray default
    end
end

function renderer = createThresholdRenderer(roiNum, noiseLevel, threshold, styleConfig)
    % Create a specialized threshold renderer for specific ROI
    % FIXES the overwriting issue by creating unique identifiers
    
    renderer = struct();
    renderer.roiNum = roiNum;
    renderer.noiseLevel = noiseLevel;
    renderer.threshold = threshold;
    renderer.styleConfig = styleConfig;
    renderer.renderCount = 0;  % Track number of thresholds rendered
    
    % Function handles
    renderer.addForTrial = @(timeData_ms, stimulusTime_ms, traceColor, trialNum) ...
        addThresholdForTrial(renderer, timeData_ms, stimulusTime_ms, traceColor, trialNum);
    
    renderer.addForAverage = @(timeData_ms, stimulusTime_ms) ...
        addThresholdForAverage(renderer, timeData_ms, stimulusTime_ms);
end

function addThresholdForTrial(renderer, timeData_ms, stimulusTime_ms, traceColor, trialNum)
    % Add threshold line for individual trial with unique identifier
    
    % Validate threshold
    if ~isfinite(renderer.threshold) || renderer.threshold <= 0
        return;
    end
    
    % Calculate window
    window = calculateThresholdWindow(timeData_ms, renderer.styleConfig.thresholds.window);
    
    % Get styling
    lineStyle = renderer.styleConfig.thresholds.getLineStyle(renderer.noiseLevel);
    color = renderer.styleConfig.thresholds.getColor('individual', traceColor);
    
    % CRITICAL: Create unique tag to prevent overwriting
    renderer.renderCount = renderer.renderCount + 1;
    uniqueTag = sprintf('threshold_roi%d_trial%g_render%d', ...
        renderer.roiNum, trialNum, renderer.renderCount);
    
    % Plot threshold line
    plot([window.start_ms, window.end_ms], ...
         [renderer.threshold, renderer.threshold], ...
         lineStyle, 'Color', color, ...
         'LineWidth', renderer.styleConfig.thresholds.lineWidth, ...
         'HandleVisibility', 'off', 'Tag', uniqueTag);
    
    % Apply transparency if specified
    h = findobj(gca, 'Tag', uniqueTag);
    if ~isempty(h)
        h.Color(4) = renderer.styleConfig.thresholds.transparency;
    end
end

function addThresholdForAverage(renderer, timeData_ms, stimulusTime_ms)
    % Add threshold line for averaged data
    
    if ~isfinite(renderer.threshold) || renderer.threshold <= 0
        return;
    end
    
    window = calculateThresholdWindow(timeData_ms, renderer.styleConfig.thresholds.window);
    lineStyle = renderer.styleConfig.thresholds.getLineStyle('average');
    color = renderer.styleConfig.thresholds.getColor('average', []);
    
    % Full-length threshold for averages
    plot([timeData_ms(1), timeData_ms(end)], ...
         [renderer.threshold, renderer.threshold], ...
         lineStyle, 'Color', color, ...
         'LineWidth', renderer.styleConfig.thresholds.lineWidth, ...
         'HandleVisibility', 'off');
end

function window = calculateThresholdWindow(timeData_ms, windowConfig)
    % Calculate threshold display window
    
    if windowConfig.fullTrace
        window.start_ms = timeData_ms(1);
        window.end_ms = timeData_ms(end);
    else
        window.start_ms = max(windowConfig.start_ms, timeData_ms(1));
        window.end_ms = min(windowConfig.end_ms, timeData_ms(end));
    end
end

function renderer = getThresholdRenderer(roiNum, noiseLevel, threshold, styleConfig)
    % Factory function for threshold renderers
    
    renderer = createThresholdRenderer(roiNum, noiseLevel, threshold, styleConfig);
end

function noiseLevelText = createNoiseLevelText(roiNoiseLevel)
    % Create standardized noise level text for titles
    
    switch lower(roiNoiseLevel)
        case 'low'
            noiseLevelText = ' (Low)';
        case 'high'
            noiseLevelText = ' (High)';
        otherwise
            noiseLevelText = ' (?)';
    end
end

% ========================================================================
% EXISTING FUNCTIONS (unchanged but cleaned up)
% ========================================================================

function plotConfig = getPlotConfig(glusnfrConfig)
    % Centralized plotting configuration - CLEANED and enhanced
    
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
    plotConfig.lines.threshold = 1.5;  % Will be overridden by styleConfig
    plotConfig.lines.stimulus = 1.5;
    
    % Stimulus settings
    plotConfig.stimulus = struct();
    plotConfig.stimulus.style = 'line';
    plotConfig.stimulus.color = [0, 0.8, 0];
    plotConfig.stimulus.width = 1.0;
    plotConfig.stimulus.length = 'zero';
    plotConfig.stimulus.enableDual = true;
    plotConfig.stimulus.ppfColor = [0, 0.8, 0.8];
end

function colors = getColors(colorType, count)
    % CENTRALIZED color system (unchanged from previous version)
    
    if nargin < 2, count = 10; end
    
    switch lower(colorType)
        case 'trials'
            colors = [
                0.0 0.4 0.8;    % Blue
                0.8 0.2 0.2;    % Red  
                0.2 0.6 0.2;    % Green
                0.8 0.5 0.0;    % Orange
                0.6 0.2 0.8;    % Purple
                0.8 0.8 0.2;    % Yellow
                0.4 0.4 0.4;    % Gray
                0.0 0.8 0.8;    % Cyan
                0.8 0.0 0.8;    % Magenta
                0.0 0.0 0.0;    % Black
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
    % Create standardized figure (unchanged)
    
    if nargin < 1, figureType = 'standard'; end
    if nargin < 2, titleText = ''; end
    if nargin < 3, plotConfig = getPlotConfig(GluSnFRConfig()); end
    
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
    % Calculate optimal subplot layout (unchanged)
    
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
        nCols = ceil(sqrt(nSubplots * 16/9));
        nRows = ceil(nSubplots / nCols);
    end
end

function addPlotElements(timeData_ms, stimulusTime_ms, threshold, plotConfig, varargin)
    % Add plot elements - stimulus lines and average thresholds only
    % Individual thresholds handled by specialized renderers
    
    p = inputParser;
    addParameter(p, 'ShowStimulus', true, @islogical);
    addParameter(p, 'ShowThreshold', true, @islogical);
    addParameter(p, 'PPFTimepoint', [], @isnumeric);
    parse(p, varargin{:});
    
    ylim(plotConfig.ylimits);
    currentYLim = ylim;
    
    % Add stimulus line(s)
    if p.Results.ShowStimulus
        addStimulusLine(stimulusTime_ms, currentYLim, plotConfig.stimulus);
        
        if ~isempty(p.Results.PPFTimepoint) && plotConfig.stimulus.enableDual
            stimulusTime_ms2 = stimulusTime_ms + p.Results.PPFTimepoint;
            stimConfig2 = plotConfig.stimulus;
            stimConfig2.color = plotConfig.stimulus.ppfColor;
            addStimulusLine(stimulusTime_ms2, currentYLim, stimConfig2);
        end
    end
    
    % Add threshold line (for averages only)
    if p.Results.ShowThreshold && isfinite(threshold) && threshold > 0
        plot([timeData_ms(1), timeData_ms(end)], [threshold, threshold], '--', ...
             'Color', [0, 0.8, 0], 'LineWidth', plotConfig.lines.threshold, ...
             'HandleVisibility', 'off');
    end
end

function addStimulusLine(stimulusTime_ms, currentYLim, stimConfig)
    % Add stimulus line (unchanged)
    
    switch stimConfig.length
        case 'full'
            yRange = currentYLim;
        case 'zero'
            yRange = [currentYLim(1), 0];
        otherwise
            if isnumeric(stimConfig.length) && length(stimConfig.length) == 2
                yRange = stimConfig.length;
            else
                yRange = [currentYLim(1), 0];
            end
    end
    
    plot([stimulusTime_ms, stimulusTime_ms], yRange, ...
         '--', 'Color', stimConfig.color, 'LineWidth', stimConfig.width, ...
         'HandleVisibility', 'off');
end

function formatSubplot(plotConfig)
    % Apply standard subplot formatting (unchanged)
    
    if nargin < 1, plotConfig = getPlotConfig(GluSnFRConfig()); end
    
    xlabel('Time (ms)', 'FontSize', plotConfig.fonts.axis);
    ylabel('ΔF/F', 'FontSize', plotConfig.fonts.axis);
    set(gca, 'FontSize', plotConfig.fonts.tick);
    grid on;
    box on;
end

function success = savePlot(fig, filepath, plotConfig)
    % Save plot with standard settings (unchanged)
    
    if nargin < 3, plotConfig = getPlotConfig(GluSnFRConfig()); end
    
    success = false;
    
    try
        [pathstr, ~, ~] = fileparts(filepath);
        if ~exist(pathstr, 'dir')
            mkdir(pathstr);
        end
        
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
    % Extract genotype from group key (unchanged)
    
    if contains(groupKey, 'R213W')
        genotype = 'R213W';
    elseif contains(groupKey, 'WT')
        genotype = 'WT';
    else
        genotype = 'Unknown';
    end
end