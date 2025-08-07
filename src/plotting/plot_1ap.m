function plot1AP = plot_1ap()
    % PLOT_1AP - Modular 1AP experiment plotting with clean separation of concerns
    % 
    % ARCHITECTURE:
    % - Main controller delegates to specialized generators
    % - Each generator focuses on one plot type
    % - Shared utilities handle common operations
    % - Configuration managed centrally
    
    plot1AP.execute = @executePlotTask;
    
    % Expose sub-modules for direct access if needed
    plot1AP.generators = struct();
    plot1AP.generators.trials = individual_trials_generator();
    plot1AP.generators.averages = roi_averages_generator(); 
    plot1AP.generators.coverslip = coverslip_averages_generator();
end

function success = executePlotTask(task, config, varargin)
    % Main task dispatcher - delegates to specialized generators
    
    success = false;
    
    % Validate task and cache
    if ~validateTaskAndCache(task, config)
        return;
    end
    
    % Get appropriate generator and execute
    try
        switch task.type
            case 'trials'
                generator = individual_trials_generator();
                success = generator.generate(task.data, config, ...
                    'roiInfo', task.roiInfo, 'roiCache', task.roiCache, ...
                    'groupKey', task.groupKey, 'outputFolder', task.outputFolder);
                    
            case 'averages'
                generator = roi_averages_generator();
                success = generator.generate(task.data, config, ...
                    'roiInfo', task.roiInfo, 'roiCache', task.roiCache, ...
                    'groupKey', task.groupKey, 'outputFolder', task.outputFolder);
                    
            case 'coverslip'
                generator = coverslip_averages_generator();
                success = generator.generate(task.data, config, ...
                    'roiInfo', task.roiInfo, 'roiCache', task.roiCache, ...
                    'groupKey', task.groupKey, 'outputFolder', task.outputFolder);
                    
            otherwise
                if config.debug.ENABLE_PLOT_DEBUG
                    fprintf('    Unknown 1AP plot task type: %s\n', task.type);
                end
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    1AP plot task failed: %s\n', ME.message);
        end
        success = false;
    end
end

function isValid = validateTaskAndCache(task, config)
    % Centralized task and cache validation
    
    isValid = false;
    
    if ~isstruct(task) || ~isfield(task, 'type') || ~isfield(task, 'roiCache')
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Invalid task structure\n');
        end
        return;
    end
    
    if isempty(task.roiCache) || ~task.roiCache.valid
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Invalid or missing ROI cache\n');
        end
        return;
    end
    
    isValid = true;
end

% ========================================================================
% SPECIALIZED PLOT GENERATORS
% ========================================================================

function generator = individual_trials_generator()
    % Generator for individual trial plots
    
    generator.generate = @generateTrialsPlot;
end

function success = generateTrialsPlot(organizedData, config, varargin)
    % Generate individual trials plots with proper threshold visualization
    
    success = false;
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'roiCache', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    % Validation
    if ~istable(organizedData) || width(organizedData) <= 1
        return;
    end
    
    try
        % Get utilities and configuration
        utils = plot_utilities();
        styleConfig = utils.getPlotStyles(config);  % NEW: Centralized styling
        
        % Setup base data
        timeData_ms = organizedData.Frame;
        stimulusTime_ms = config.timing.STIMULUS_TIME_MS;
        cleanGroupKey = regexprep(p.Results.groupKey, '[^\w-]', '_');
        
        % Create global trial color system
        [uniqueTrials, globalTrialColorMap] = createGlobalTrialColorSystem(organizedData, utils);
        
        if isempty(uniqueTrials)
            return;
        end
        
        % Generate figures using specialized figure generator
        figGenerator = trials_figure_generator();
        success = figGenerator.generateAllFigures(organizedData, p.Results.roiCache, ...
            timeData_ms, stimulusTime_ms, uniqueTrials, globalTrialColorMap, ...
            cleanGroupKey, p.Results.outputFolder, utils, styleConfig, config);
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateTrialsPlot error: %s\n', ME.message);
        end
    end
end

function generator = roi_averages_generator()
    % Generator for ROI averaged plots
    
    generator.generate = @generateAveragesPlot;
end

function success = generateAveragesPlot(averagedData, config, varargin)
    % Generate ROI averaged plots with centralized styling
    
    success = false;
    
    % Parse inputs  
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'roiCache', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    if ~istable(averagedData) || width(averagedData) <= 1
        return;
    end
    
    try
        % Get utilities and styling
        utils = plot_utilities();
        styleConfig = utils.getPlotStyles(config);
        
        % Generate averaged plots using specialized generator
        avgGenerator = averages_figure_generator();
        success = avgGenerator.generateAllFigures(averagedData, p.Results.roiCache, ...
            p.Results.groupKey, p.Results.outputFolder, utils, styleConfig, config);
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateAveragesPlot error: %s\n', ME.message);
        end
    end
end

function generator = coverslip_averages_generator()
    % Generator for coverslip average plots
    
    generator.generate = @generateCoverslipPlot;
end

function success = generateCoverslipPlot(totalAveragedData, config, varargin)
    % Generate coverslip average plots
    
    success = false;
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'roiCache', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    if ~istable(totalAveragedData) || width(totalAveragedData) <= 1
        return;
    end
    
    try
        % Get utilities and styling
        utils = plot_utilities();
        styleConfig = utils.getPlotStyles(config);
        
        % Generate coverslip plots using specialized generator
        covGenerator = coverslip_figure_generator();
        success = covGenerator.generateFigure(totalAveragedData, p.Results.roiInfo, ...
            p.Results.groupKey, p.Results.outputFolder, utils, styleConfig, config);
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateCoverslipPlot error: %s\n', ME.message);
        end
    end
end

% ========================================================================
% SPECIALIZED FIGURE GENERATORS
% ========================================================================

function generator = trials_figure_generator()
    % Specialized generator for trial figures with proper threshold handling
    
    generator.generateAllFigures = @generateAllTrialsFigures;
    generator.generateSingleFigure = @generateSingleTrialsFigure;
end

function success = generateAllTrialsFigures(organizedData, roiCache, timeData_ms, ...
    stimulusTime_ms, uniqueTrials, globalTrialColorMap, cleanGroupKey, ...
    outputFolder, utils, styleConfig, config)
    % Generate all trial figures with proper pagination
    
    numROIs = length(roiCache.numbers);
    if numROIs == 0
        success = false;
        return;
    end
    
    numFigures = ceil(numROIs / styleConfig.maxPlotsPerFigure);
    success = false;
    
    for figNum = 1:numFigures
        figSuccess = generateSingleTrialsFigure(figNum, numFigures, numROIs, ...
            organizedData, roiCache, timeData_ms, stimulusTime_ms, uniqueTrials, ...
            globalTrialColorMap, cleanGroupKey, outputFolder, utils, styleConfig, config);
        success = success || figSuccess;
    end
end

function success = generateSingleTrialsFigure(figNum, numFigures, numROIs, ...
    organizedData, roiCache, timeData_ms, stimulusTime_ms, uniqueTrials, ...
    globalTrialColorMap, cleanGroupKey, outputFolder, utils, styleConfig, config)
    % Generate a single trials figure with FIXED threshold visualization
    
    success = false;
    
    % Calculate ROI range
    startROI = (figNum - 1) * styleConfig.maxPlotsPerFigure + 1;
    endROI = min(figNum * styleConfig.maxPlotsPerFigure, numROIs);
    numPlotsThisFig = endROI - startROI + 1;
    
    [nRows, nCols] = utils.calculateLayout(numPlotsThisFig);
    
    fig = utils.createFigure('standard');
    hasData = false;
    
    for roiIdx = startROI:endROI
        subplotIdx = roiIdx - startROI + 1;
        roiNum = roiCache.numbers(roiIdx);
        
        subplot(nRows, nCols, subplotIdx);
        hold on;
        
        % Get ROI data from cache ONLY
        cache_manager = roi_cache();
        [roiNoiseLevel, upperThreshold, lowerThreshold, basicThreshold, standardDeviation] = ...
            cache_manager.retrieve(roiCache, roiNum);
        
        % FIXED: Create threshold renderer for this specific ROI
        thresholdRenderer = roi_threshold_renderer(roiNum, roiNoiseLevel, ...
            upperThreshold, lowerThreshold, styleConfig);
        
        trialCount = 0;
        legendData = struct('handles', [], 'labels', {{}});
        
        % Plot each trial for this ROI
        for trialIdx = 1:length(uniqueTrials)
            trialNum = uniqueTrials(trialIdx);
            colName = sprintf('ROI%d_T%g', roiNum, trialNum);
            
            if ismember(colName, organizedData.Properties.VariableNames)
                trialData = organizedData.(colName);
                if ~all(isnan(trialData))
                    trialCount = trialCount + 1;
                    hasData = true;
                    
                    % Get consistent color
                    traceColor = globalTrialColorMap(num2str(trialNum));
                    
                    % Plot trace
                    h_line = plot(timeData_ms, trialData, 'Color', traceColor, ...
                        'LineWidth', styleConfig.lines.trace);
                    h_line.Color(4) = styleConfig.transparency;
                    
                    % FIXED: Add threshold line for THIS specific trial
                    thresholdRenderer.addThresholdForTrial(timeData_ms, stimulusTime_ms, ...
                        traceColor, trialNum);
                    
                    % Store for legend
                    if subplotIdx == 1
                        legendData.handles(end+1) = plot(NaN, NaN, 'Color', traceColor, ...
                            'LineWidth', styleConfig.lines.trace);
                        legendData.labels{end+1} = sprintf('Trial %g', trialNum);
                    end
                end
            end
        end
        
        % Add stimulus line
        utils.addPlotElements(timeData_ms, stimulusTime_ms, NaN, styleConfig, ...
            'ShowStimulus', true, 'ShowThreshold', false);
        
        % Format subplot
        noiseLevelText = utils.createNoiseLevelText(roiNoiseLevel);
        title(sprintf('ROI %d%s (n=%d)', roiNum, noiseLevelText, trialCount), ...
            'FontSize', styleConfig.fonts.subtitle, 'FontWeight', 'bold');
        
        utils.formatSubplot(styleConfig);
        
        % Add legend for first subplot
        if subplotIdx == 1 && ~isempty(legendData.handles)
            legend(legendData.handles, legendData.labels, 'Location', 'northeast', 'FontSize', 8);
        end
        
        hold off;
    end
    
    % Save figure
    if hasData
        success = saveFigureWithTitle(fig, figNum, numFigures, cleanGroupKey, ...
            'trials', outputFolder, utils, styleConfig);
    end
    
    close(fig);
end

% ========================================================================
% SPECIALIZED THRESHOLD RENDERER
% ========================================================================

function renderer = roi_threshold_renderer(roiNum, noiseLevel, upperThreshold, lowerThreshold, styleConfig)
    % Specialized renderer for ROI-specific thresholds
    % FIXES the "only last threshold showing" issue by managing individual thresholds
    
    renderer.roiNum = roiNum;
    renderer.noiseLevel = noiseLevel;
    renderer.upperThreshold = upperThreshold;
    renderer.lowerThreshold = lowerThreshold;
    renderer.styleConfig = styleConfig;
    renderer.addThresholdForTrial = @addThresholdForTrial;
    
    function addThresholdForTrial(timeData_ms, stimulusTime_ms, traceColor, trialNum)
        % Add threshold line for specific trial with proper styling
        
        % Only add if we have valid threshold
        if ~isfinite(renderer.upperThreshold) || renderer.upperThreshold <= 0
            return;
        end
        
        % Calculate threshold line window
        thresholdStart_ms = max(1, timeData_ms(1));
        thresholdEnd_ms = min(750, timeData_ms(end));
        
        % Get line style based on noise level
        lineStyle = styleConfig.thresholds.getLineStyle(renderer.noiseLevel);
        
        % FIXED: Plot threshold with unique identifier to prevent overwriting
        thresholdTag = sprintf('threshold_roi%d_trial%g', renderer.roiNum, trialNum);
        
        plot([thresholdStart_ms, thresholdEnd_ms], ...
             [renderer.upperThreshold, renderer.upperThreshold], ...
             lineStyle, 'Color', traceColor, ...
             'LineWidth', styleConfig.lines.threshold, ...
             'HandleVisibility', 'off', 'Tag', thresholdTag);
    end
end

% ========================================================================
% UTILITY FUNCTIONS
% ========================================================================

function [uniqueTrials, globalTrialColorMap] = createGlobalTrialColorSystem(organizedData, utils)
    % Create consistent trial color mapping (unchanged from original)
    
    varNames = organizedData.Properties.VariableNames(2:end);
    uniqueTrials = [];
    
    for i = 1:length(varNames)
        trialMatch = regexp(varNames{i}, 'ROI\d+_T(\d+(?:\.\d+)?)', 'tokens');
        if ~isempty(trialMatch)
            trialNum = str2double(trialMatch{1}{1});
            if isfinite(trialNum) && ~ismember(trialNum, uniqueTrials)
                uniqueTrials(end+1) = trialNum;
            end
        end
    end
    
    uniqueTrials = sort(uniqueTrials);
    
    trialColors = utils.getColors('trials', length(uniqueTrials));
    globalTrialColorMap = containers.Map();
    
    for i = 1:length(uniqueTrials)
        globalTrialColorMap(num2str(uniqueTrials(i))) = trialColors(i, :);
    end
end

function success = saveFigureWithTitle(fig, figNum, numFigures, cleanGroupKey, plotType, outputFolder, utils, styleConfig)
    % Centralized figure saving with consistent naming
    
    if numFigures > 1
        titleText = sprintf('%s - %s (Part %d/%d)', cleanGroupKey, title_case(plotType), figNum, numFigures);
        filename = sprintf('%s_%s_part%d.png', cleanGroupKey, plotType, figNum);
    else
        titleText = sprintf('%s - %s', cleanGroupKey, title_case(plotType));
        filename = sprintf('%s_%s.png', cleanGroupKey, plotType);
    end
    
    sgtitle(titleText, 'FontSize', styleConfig.fonts.title, 'Interpreter', 'none', 'FontWeight', 'bold');
    
    filepath = fullfile(outputFolder, filename);
    success = utils.savePlot(fig, filepath, styleConfig);
end

function titleStr = title_case(str)
    % Convert string to title case
    words = strsplit(str, '_');
    titleStr = strjoin(cellfun(@(x) [upper(x(1)), lower(x(2:end))], words, 'UniformOutput', false), ' ');
end

% ========================================================================
% PLACEHOLDER GENERATORS (implement similar modular structure)
% ========================================================================

function generator = averages_figure_generator()
    % Generator for ROI averaged plots
    
    generator.generateAllFigures = @generateAllAveragesFigures;
    generator.generateSingleFigure = @generateSingleAveragesFigure;
end

function success = generateAllAveragesFigures(averagedData, roiCache, groupKey, outputFolder, utils, styleConfig, config)
    % Generate all averaged figures with proper pagination
    
    timeData_ms = averagedData.Frame;
    stimulusTime_ms = config.timing.STIMULUS_TIME_MS;
    avgVarNames = averagedData.Properties.VariableNames(2:end);
    numAvgPlots = length(avgVarNames);
    
    if numAvgPlots == 0
        success = false;
        return;
    end
    
    numFigures = ceil(numAvgPlots / styleConfig.maxPlotsPerFigure);
    success = false;
    
    for figNum = 1:numFigures
        figSuccess = generateSingleAveragesFigure(figNum, numFigures, avgVarNames, ...
            averagedData, roiCache, timeData_ms, stimulusTime_ms, groupKey, ...
            outputFolder, utils, styleConfig, config);
        success = success || figSuccess;
    end
end

function success = generateSingleAveragesFigure(figNum, numFigures, avgVarNames, ...
    averagedData, roiCache, timeData_ms, stimulusTime_ms, groupKey, outputFolder, ...
    utils, styleConfig, config)
    % Generate a single averaged figure
    
    success = false;
    
    % Calculate plot range
    startPlot = (figNum - 1) * styleConfig.maxPlotsPerFigure + 1;
    endPlot = min(figNum * styleConfig.maxPlotsPerFigure, length(avgVarNames));
    numPlotsThisFig = endPlot - startPlot + 1;
    
    [nRows, nCols] = utils.calculateLayout(numPlotsThisFig);
    
    fig = utils.createFigure('standard');
    hasData = false;
    
    for plotIdx = startPlot:endPlot
        subplotIdx = plotIdx - startPlot + 1;
        
        subplot(nRows, nCols, subplotIdx);
        hold on;
        
        varName = avgVarNames{plotIdx};
        avgData = averagedData.(varName);
        
        if ~all(isnan(avgData))
            hasData = true;
            
            % Plot average trace in black
            traceColor = [0, 0, 0];
            plot(timeData_ms, avgData, 'Color', traceColor, 'LineWidth', 2.0);
            
            % Calculate threshold for averaged data
            avgThreshold = calculateAverageThreshold(avgData, config);
            
            % Create threshold renderer for averaged data
            thresholdRenderer = styleConfig.thresholds.createRenderer(0, 'average', avgThreshold);
            thresholdRenderer.addForAverage(timeData_ms, stimulusTime_ms);
            
            % Add stimulus line
            utils.addPlotElements(timeData_ms, stimulusTime_ms, NaN, styleConfig, ...
                'ShowStimulus', true, 'ShowThreshold', false);
        end
        
        % Parse and format title
        roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            nTrials = roiMatch{1}{2};
            
            % Get noise level from cache
            cache_manager = roi_cache();
            if cache_manager.hasFilteringStats(roiCache)
                [roiNoiseLevel, ~, ~, ~, ~] = cache_manager.retrieve(roiCache, roiNum);
                noiseLevelText = utils.createNoiseLevelText(roiNoiseLevel);
            else
                noiseLevelText = '';
            end
            
            title(sprintf('ROI %d%s (Avg, n=%s)', roiNum, noiseLevelText, nTrials), ...
                'FontSize', styleConfig.fonts.subtitle, 'FontWeight', 'bold');
        else
            title(varName, 'FontSize', styleConfig.fonts.subtitle);
        end
        
        utils.formatSubplot(styleConfig);
        hold off;
    end
    
    % Save figure if it has data
    if hasData
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        success = saveFigureWithTitle(fig, figNum, numFigures, cleanGroupKey, ...
            'averaged', outputFolder, utils, styleConfig);
    end
    
    close(fig);
end

function generator = coverslip_figure_generator()
    % Generator for coverslip average plots
    
    generator.generateFigure = @generateCoverslipFigure;
end

function success = generateCoverslipFigure(totalAveragedData, roiInfo, groupKey, outputFolder, utils, styleConfig, config)
    % Generate coverslip average plot with noise level separation
    
    success = false;
    
    timeData_ms = totalAveragedData.Frame;
    stimulusTime_ms = config.timing.STIMULUS_TIME_MS;
    varNames = totalAveragedData.Properties.VariableNames(2:end);
    
    if isempty(varNames)
        return;
    end
    
    fig = utils.createFigure('standard');
    hold on;
    
    hasData = false;
    legendEntries = {};
    legendHandles = [];
    
    % Get noise-specific colors
    noiseColors = utils.getColors('noise', 3);
    
    % Plot each data series with appropriate styling
    for i = 1:length(varNames)
        varName = varNames{i};
        data = totalAveragedData.(varName);
        
        if ~all(isnan(data))
            hasData = true;
            
            % Determine color and display name based on variable name
            if contains(varName, 'Low_Noise')
                color = noiseColors(1, :);  % Green for low noise
                displayName = 'Low Noise';
            elseif contains(varName, 'High_Noise')
                color = noiseColors(2, :);  % Red for high noise
                displayName = 'High Noise';
            elseif contains(varName, 'All_')
                color = noiseColors(3, :);  % Black for all
                displayName = 'All ROIs';
            else
                color = [0.4, 0.4, 0.4];   % Gray for unknown
                displayName = varName;
            end
            
            % Extract n count for display
            nMatch = regexp(varName, 'n(\d+)', 'tokens');
            if ~isempty(nMatch)
                displayName = sprintf('%s (n=%s)', displayName, nMatch{1}{1});
            end
            
            % Plot the trace
            h = plot(timeData_ms, data, 'Color', color, 'LineWidth', 2, 'DisplayName', displayName);
            
            % Store for legend
            legendHandles(end+1) = h;
            legendEntries{end+1} = displayName;
        end
    end
    
    % Add stimulus line and formatting
    if hasData
        utils.addPlotElements(timeData_ms, stimulusTime_ms, NaN, styleConfig, ...
            'ShowStimulus', true, 'ShowThreshold', false);
        
        utils.formatSubplot(styleConfig);
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        title(sprintf('%s - Coverslip Averages by Noise Level', cleanGroupKey), ...
              'FontSize', styleConfig.fonts.title, 'FontWeight', 'bold', 'Interpreter', 'none');
        
        % Add legend
        if ~isempty(legendHandles)
            legend(legendHandles, legendEntries, 'Location', 'northeast', 'FontSize', 10);
        end
        
        % Save figure
        filename = sprintf('%s_coverslip_averages.png', cleanGroupKey);
        filepath = fullfile(outputFolder, filename);
        success = utils.savePlot(fig, filepath, styleConfig);
    end
    
    hold off;
    close(fig);
end

function avgThreshold = calculateAverageThreshold(avgData, config)
    % Calculate threshold for averaged data using baseline
    
    % Use baseline window from config
    baselineWindow = config.timing.BASELINE_FRAMES;
    
    % Ensure we have valid data for baseline
    if length(avgData) >= max(baselineWindow)
        baselineData = avgData(baselineWindow);
        
        % Calculate threshold using config multiplier
        baselineSD = std(baselineData, 'omitnan');
        avgThreshold = config.thresholds.LOW_NOISE_SIGMA * baselineSD;
    else
        avgThreshold = NaN;
    end
    
    % Apply default if calculation failed
    if ~isfinite(avgThreshold)
        avgThreshold = 0.01; % Default threshold
    end
end