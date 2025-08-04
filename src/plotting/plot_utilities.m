function utils = plot_utilities()
    % PLOT_UTILITIES - Centralized plotting utilities and configuration
    % Simplified and standardized version of plot_utils.m
    
    utils.getPlotConfig = @getPlotConfig;
    utils.createFigure = @createFigure;
    utils.calculateLayout = @calculateLayout;
    utils.addPlotElements = @addPlotElements;
    utils.formatSubplot = @formatSubplot;
    utils.savePlot = @savePlot;
    utils.getColors = @getColors;
    utils.extractGenotype = @extractGenotype;
    utils.createLegend = @createLegend;
    utils.addStimulusToLegend = @addStimulusToLegend;
    utils.createTrialLegend = @createTrialLegend;
end

function plotConfig = getPlotConfig(glusnfrConfig)
    % Centralized plotting configuration
    % Only pulls minimal save/timing settings from GluSnFRConfig
    % All visual styling is self-contained here
    
    plotConfig = struct();
    
    % Only pull essential settings from main config
    plotConfig.dpi = glusnfrConfig.plotting.DPI;  % Save setting
    plotConfig.maxPlotsPerFigure = glusnfrConfig.plotting.MAX_PLOTS_PER_FIGURE;  % Layout setting
    plotConfig.timing = glusnfrConfig.timing;  % Need stimulus timing
    
    % All visual settings centralized here
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
    plotConfig.lines.stimulus = 1.0;
    
    % Colors (all centralized here)
    plotConfig.colors = struct();
    plotConfig.colors.stimulus = [0, 0.8, 0];      % Green
    plotConfig.colors.threshold = [0, 0.8, 0];     % Green
    plotConfig.colors.wt = [0, 0, 0];              % Black
    plotConfig.colors.r213w = [1, 0, 1];           % Magenta
    plotConfig.colors.lowNoise = [0.2, 0.6, 0.2];  % Green
    plotConfig.colors.highNoise = [0.8, 0.2, 0.2]; % Red
    plotConfig.colors.bothPeaks = [0, 0, 0];       % Black for both peaks
    plotConfig.colors.singlePeak = [0.8, 0.2, 0.2]; % Red for single peak
    
    % Figure type controls (centralized here)
    plotConfig.figureTypes = struct();
    plotConfig.figureTypes.default = 'standard';    % 'standard', 'wide', 'compact'
    plotConfig.figureTypes.ppf = 'wide';            % PPF plots use wide format
    plotConfig.figureTypes.coverslip = 'standard';  % Coverslip plots
    plotConfig.figureTypes.autoSelect = true;       % Auto-select based on content
    
    % Stimulus/threshold line settings (NEW - easy customization)
    plotConfig.stimulus = struct();
    plotConfig.stimulus.style = 'line';            % 'line', 'marker', 'pentagram'
    plotConfig.stimulus.color = [0, 0.8, 0];       % Green
    plotConfig.stimulus.width = 1.0;
    plotConfig.stimulus.length = 'zero';           % 'full', 'zero', or [ymin, ymax]
    plotConfig.stimulus.enableDual = true;         % Show both stimuli for PPF
    plotConfig.stimulus.ppfColor = [0, 0.8, 0.8];  % Cyan for second stimulus
    
    plotConfig.threshold = struct();
    plotConfig.threshold.color = [0, 0.8, 0];      % Green
    plotConfig.threshold.width = 1.5;
    plotConfig.threshold.style = '--';
    plotConfig.threshold.length = 100;             % frames or 'all'
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
    % Add standard plot elements (stimulus lines, threshold lines)
    % This replaces the hard-coded elements with configurable ones
    
    % Parse optional inputs
    p = inputParser;
    addParameter(p, 'ShowStimulus', true, @islogical);
    addParameter(p, 'ShowThreshold', true, @islogical);
    addParameter(p, 'PPFTimepoint', [], @isnumeric);
    parse(p, varargin{:});
    
    % Set y-limits first
    ylim(plotConfig.ylimits);
    currentYLim = ylim;
    
    % Add stimulus line(s) with improved control
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
    
    % Add threshold line with improved control
    if p.Results.ShowThreshold && isfinite(threshold)
        addThresholdLine(timeData_ms, threshold, plotConfig.threshold);
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
    
    % Draw stimulus based on style
    switch lower(stimConfig.style)
        case 'line'
            plot([stimulusTime_ms, stimulusTime_ms], yRange, ...
                 ':', 'Color', stimConfig.color, 'LineWidth', stimConfig.width, ...
                 'HandleVisibility', 'off');
                 
        case 'marker'
            % Place marker at bottom of plot
            stimY = yRange(1) + 0.002;
            plot(stimulusTime_ms, stimY, 'v', ...
                 'Color', stimConfig.color, 'MarkerSize', 8, ...
                 'MarkerFaceColor', stimConfig.color, 'HandleVisibility', 'off');
                 
        case 'pentagram'
            % Place pentagram at bottom of plot
            stimY = yRange(1) + 0.002;
            plot(stimulusTime_ms, stimY, 'pentagram', ...
                 'Color', stimConfig.color, 'MarkerSize', 8, ...
                 'MarkerFaceColor', stimConfig.color, 'HandleVisibility', 'off');
                 
        otherwise
            % Default to line
            plot([stimulusTime_ms, stimulusTime_ms], yRange, ...
                 ':', 'Color', stimConfig.color, 'LineWidth', stimConfig.width, ...
                 'HandleVisibility', 'off');
    end
end

function addThresholdLine(timeData_ms, threshold, threshConfig)
    % Add threshold line with configurable appearance and length
    
    % Determine x-range for threshold line
    if isnumeric(threshConfig.length) && threshConfig.length > 0
        if threshConfig.length <= length(timeData_ms)
            xEnd = timeData_ms(threshConfig.length);
        else
            xEnd = timeData_ms(end);
        end
    else
        xEnd = timeData_ms(end); % Full length
    end
    
    plot([timeData_ms(1), xEnd], [threshold, threshold], ...
         threshConfig.style, 'Color', threshConfig.color, ...
         'LineWidth', threshConfig.width, 'HandleVisibility', 'off');
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

function colors = getColors(colorType, count)
    % Get color scheme for different plot types
    
    if nargin < 2, count = 10; end
    
    switch lower(colorType)
        case 'trials'
            colors = [
                0.0 0.0 0.0;    % Black
                0.8 0.2 0.2;    % Red  
                0.2 0.6 0.8;    % Blue
                0.2 0.8 0.2;    % Green
                0.8 0.5 0.2;    % Orange
                0.6 0.2 0.8;    % Purple
                0.8 0.8 0.2;    % Yellow
                0.4 0.4 0.4;    % Gray
                0.0 0.8 0.8;    % Cyan
                0.8 0.0 0.8;    % Magenta
            ];
            
        case 'genotype'
            colors = [0, 0, 0; 1, 0, 1]; % WT=black, R213W=magenta
            
        case 'noise'
            colors = [0.2, 0.6, 0.2; 0.8, 0.2, 0.2]; % Green=low, Red=high
            
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

function legendHandle = createLegend(legendType, plotConfig, varargin)
    % Create standardized legends for different plot types
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'Location', 'northeast', @ischar);
    addParameter(p, 'FontSize', 9, @isnumeric);
    addParameter(p, 'NumTrials', 10, @isnumeric);
    addParameter(p, 'TrialNumbers', [], @isnumeric);
    addParameter(p, 'Genotype', 'WT', @ischar);
    addParameter(p, 'IncludeStimulus', false, @islogical);
    addParameter(p, 'IncludeThreshold', false, @islogical);
    parse(p, varargin{:});
    
    legendHandle = [];
    
    switch lower(legendType)
        case 'trials'
            legendHandle = createTrialLegend(plotConfig, p.Results);
            
        case 'noise_level'
            legendHandle = createNoiseLevelLegend(plotConfig, p.Results);
            
        case 'genotype'
            legendHandle = createGenotypeLegend(plotConfig, p.Results);
            
        case 'basic'
            legendHandle = createBasicLegend(plotConfig, p.Results);
    end
end

function legendHandle = createTrialLegend(plotConfig, options)
    % Create legend for trial plots with consistent styling
    
    handles = [];
    labels = {};
    
    % Get trial colors
    trialColors = getColors('trials', options.NumTrials);
    
    % Add trial entries (only show first few to avoid clutter)
    maxTrialsInLegend = min(5, options.NumTrials);
    
    if ~isempty(options.TrialNumbers)
        trialsToShow = options.TrialNumbers(1:min(maxTrialsInLegend, length(options.TrialNumbers)));
    else
        trialsToShow = 1:maxTrialsInLegend;
    end
    
    for i = 1:length(trialsToShow)
        h = plot(NaN, NaN, 'Color', trialColors(i, :), 'LineWidth', plotConfig.lines.trace);
        handles(end+1) = h;
        labels{end+1} = sprintf('Trial %d', trialsToShow(i));
    end
    
    % Add stimulus line if requested
    if options.IncludeStimulus
        hStim = plot(NaN, NaN, ':', 'Color', plotConfig.stimulus.color, 'LineWidth', plotConfig.stimulus.width);
        handles(end+1) = hStim;
        labels{end+1} = 'Stimulus';
    end
    
    % Add threshold line if requested
    if options.IncludeThreshold
        hThresh = plot(NaN, NaN, plotConfig.threshold.style, 'Color', plotConfig.threshold.color, ...
            'LineWidth', plotConfig.threshold.width);
        handles(end+1) = hThresh;
        labels{end+1} = 'Threshold';
    end
    
    if ~isempty(handles)
        legendHandle = legend(handles, labels, 'Location', options.Location, 'FontSize', options.FontSize);
    end
end

function legendHandle = createNoiseLevelLegend(plotConfig, options)
    % Create legend for noise level plots
    
    handles = [];
    labels = {};
    
    % Add noise level entries
    hLow = plot(NaN, NaN, 'Color', plotConfig.colors.lowNoise, 'LineWidth', 2);
    handles(end+1) = hLow;
    labels{end+1} = 'Low Noise';
    
    hHigh = plot(NaN, NaN, 'Color', plotConfig.colors.highNoise, 'LineWidth', 2);
    handles(end+1) = hHigh;
    labels{end+1} = 'High Noise';
    
    hAll = plot(NaN, NaN, 'Color', [0.2, 0.2, 0.8], 'LineWidth', 2);
    handles(end+1) = hAll;
    labels{end+1} = 'All ROIs';
    
    % Add stimulus line if requested
    handles = addStimulusToLegend(handles, labels, plotConfig, options);
    
    legendHandle = legend(handles, labels, 'Location', options.Location, 'FontSize', options.FontSize);
end

function legendHandle = createGenotypeLegend(plotConfig, options)
    % Create legend for genotype plots
    
    handles = [];
    labels = {};
    
    % Add genotype-specific color
    if strcmp(options.Genotype, 'WT')
        color = plotConfig.colors.wt;
    elseif strcmp(options.Genotype, 'R213W')
        color = plotConfig.colors.r213w;
    else
        color = [0, 0, 1]; % Blue for unknown
    end
    
    h = plot(NaN, NaN, 'Color', color, 'LineWidth', 2);
    handles(end+1) = h;
    labels{end+1} = options.Genotype;
    
    % Add stimulus line if requested
    [handles, labels] = addStimulusToLegend(handles, labels, plotConfig, options);
    
    legendHandle = legend(handles, labels, 'Location', options.Location, 'FontSize', options.FontSize);
end

function legendHandle = createBasicLegend(plotConfig, options)
    % Create basic legend with average trace
    
    handles = [];
    labels = {};
    
    % Add average trace
    hAvg = plot(NaN, NaN, 'k-', 'LineWidth', plotConfig.lines.trace);
    handles(end+1) = hAvg;
    labels{end+1} = 'Average';
    
    % Add stimulus and threshold if requested
    [handles, labels] = addStimulusToLegend(handles, labels, plotConfig, options);
    
    if options.IncludeThreshold
        hThresh = plot(NaN, NaN, plotConfig.threshold.style, 'Color', plotConfig.threshold.color, ...
            'LineWidth', plotConfig.threshold.width);
        handles(end+1) = hThresh;
        labels{end+1} = 'Threshold';
    end
    
    legendHandle = legend(handles, labels, 'Location', options.Location, 'FontSize', options.FontSize);
end

function [handles, labels] = addStimulusToLegend(handles, labels, plotConfig, options)
    % Helper function to add stimulus line to legend
    
    if options.IncludeStimulus
        hStim = plot(NaN, NaN, ':', 'Color', plotConfig.stimulus.color, 'LineWidth', plotConfig.stimulus.width);
        handles(end+1) = hStim;
        labels{end+1} = 'Stimulus';
    end
end