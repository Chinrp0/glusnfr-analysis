function plot1APAverage = plot_1AP_average()
    % PLOT_1AP_AVERAGE - Average plotting module for 1AP experiments
    % 
    % FOCUSED RESPONSIBILITIES:
    % - ROI averaged plots
    % - Coverslip averaged plots (by noise level)
    % - Simplified without avgThreshold calculations
    
    plot1APAverage.execute = @executePlotTask;
    plot1APAverage.generateAveragesPlot = @generateAveragesPlot;
    plot1APAverage.generateCoverslipPlot = @generateCoverslipPlot;
end

function success = executePlotTask(task, config, varargin)
    % Main task dispatcher for average plots
    
    success = false;
    
    % Validate task and cache
    sharedUtils = plot_1AP_shared_utils();
    if ~sharedUtils.validateTaskAndCache(task, config)
        return;
    end
    
    try
        switch task.type
            case 'averages'
                success = generateAveragesPlot(task.data, config, ...
                    'roiInfo', task.roiInfo, 'roiCache', task.roiCache, ...
                    'groupKey', task.groupKey, 'outputFolder', task.outputFolder);
                    
            case 'coverslip'
                success = generateCoverslipPlot(task.data, config, ...
                    'roiInfo', task.roiInfo, 'roiCache', task.roiCache, ...
                    'groupKey', task.groupKey, 'outputFolder', task.outputFolder);
                    
            otherwise
                if config.debug.ENABLE_PLOT_DEBUG
                    fprintf('    Unknown 1AP average plot task type: %s\n', task.type);
                end
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    1AP average plot task failed: %s\n', ME.message);
        end
        success = false;
    end
end

function success = generateAveragesPlot(averagedData, config, varargin)
    % Generate ROI averaged plots with simplified styling
    
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
        
        % Generate averaged plots
        success = generateAllAveragesFigures(averagedData, p.Results.roiCache, ...
            p.Results.groupKey, p.Results.outputFolder, utils, styleConfig, config);
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateAveragesPlot error: %s\n', ME.message);
        end
    end
end

function success = generateCoverslipPlot(totalAveragedData, config, varargin)
    % Generate coverslip average plots by noise level
    
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
        
        % Generate coverslip plots
        success = generateCoverslipFigure(totalAveragedData, p.Results.roiInfo, ...
            p.Results.groupKey, p.Results.outputFolder, utils, styleConfig, config);
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateCoverslipPlot error: %s\n', ME.message);
        end
    end
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
    % Generate a single averaged figure without avgThreshold calculations
    
    success = false;
    
    % Calculate plot range
    startPlot = (figNum - 1) * styleConfig.maxPlotsPerFigure + 1;
    endPlot = min(figNum * styleConfig.maxPlotsPerFigure, length(avgVarNames));
    numPlotsThisFig = endPlot - startPlot + 1;
    
    [nRows, nCols] = utils.calculateLayout(numPlotsThisFig);
    
    fig = utils.createFigure('standard');
    hasData = false;
    
    % Get cache manager
    cache_manager = roi_cache();
    
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
            
            % SIMPLIFIED: No threshold calculation - just plot data
            
            % Add stimulus line only
            utils.addPlotElements(timeData_ms, stimulusTime_ms, NaN, styleConfig, ...
                'ShowStimulus', true, 'ShowThreshold', false);
        end
        
        % Parse and format title with noise level if available
        roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            nTrials = roiMatch{1}{2};
            
            % Get noise level from cache if available
            noiseLevelText = '';
            if cache_manager.hasFilteringStats(roiCache)
                [roiNoiseLevel, ~, ~, ~, ~] = cache_manager.retrieve(roiCache, roiNum);
                sharedUtils = plot_1AP_shared_utils();
                noiseLevelText = sharedUtils.createNoiseLevelDisplayText(roiNoiseLevel);
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

% Removed duplicate functions - using shared utilities:

function success = saveFigureWithTitle(fig, figNum, numFigures, cleanGroupKey, plotType, outputFolder, utils, styleConfig)
    % Save figure with consistent naming
    
    sharedUtils = plot_1AP_shared_utils();
    
    if numFigures > 1
        titleText = sprintf('%s - %s (Part %d/%d)', cleanGroupKey, sharedUtils.titleCase(plotType), figNum, numFigures);
        filename = sprintf('%s_%s_part%d.png', cleanGroupKey, plotType, figNum);
    else
        titleText = sprintf('%s - %s', cleanGroupKey, sharedUtils.titleCase(plotType));
        filename = sprintf('%s_%s.png', cleanGroupKey, plotType);
    end
    
    sgtitle(titleText, 'FontSize', styleConfig.fonts.title, 'Interpreter', 'none', 'FontWeight', 'bold');
    
    filepath = fullfile(outputFolder, filename);
    success = utils.savePlot(fig, filepath, styleConfig);
end

% - plot_1AP_shared_utils() provides shared validation and formatting