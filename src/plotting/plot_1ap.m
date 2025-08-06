function plot1AP = plot_1ap()
    % PLOT_1AP - FIXED 1AP experiment plotting functions
    % Eliminates redundant computations and ensures proper threshold display
    
    plot1AP.execute = @executePlotTask;
    plot1AP.generateTrials = @generateTrialsPlot;
    plot1AP.generateAverages = @generateAveragesPlot;
    plot1AP.generateCoverslip = @generateCoverslipPlot;
end

function success = executePlotTask(task, config, varargin)
    % Execute a 1AP plotting task with validated ROI cache
    
    success = false;
    
    % Validate task structure
    if ~isstruct(task) || ~isfield(task, 'type') || ~isfield(task, 'roiCache')
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Invalid task structure\n');
        end
        return;
    end
    
    % Validate cache
    if isempty(task.roiCache) || ~task.roiCache.valid
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Invalid or missing ROI cache\n');
        end
        return;
    end
    
    try
        switch task.type
            case 'trials'
                success = generateTrialsPlot(task.data, config, ...
                    'roiInfo', task.roiInfo, 'roiCache', task.roiCache, ...
                    'groupKey', task.groupKey, 'outputFolder', task.outputFolder);
                    
            case 'averages'
                success = generateAveragesPlot(task.data, config, ...
                    'roiInfo', task.roiInfo, 'roiCache', task.roiCache, ...
                    'groupKey', task.groupKey, 'outputFolder', task.outputFolder);
                    
            case 'coverslip'
                success = generateCoverslipPlot(task.data, config, ...
                    'roiInfo', task.roiInfo, 'roiCache', task.roiCache, ...
                    'groupKey', task.groupKey, 'outputFolder', task.outputFolder);
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    1AP plot task failed: %s\n', ME.message);
            if ~isempty(ME.stack)
                fprintf('    Stack: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
            end
        end
        success = false;
    end
end

function success = generateTrialsPlot(organizedData, config, varargin)
    % FIXED: Generate individual trials plots with proper threshold display
    
    success = false;
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'roiCache', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    roiInfo = p.Results.roiInfo;
    roiCache = p.Results.roiCache;
    groupKey = p.Results.groupKey;
    outputFolder = p.Results.outputFolder;
    
    % Validation
    if isempty(roiInfo) || isempty(roiCache) || isempty(groupKey) || isempty(outputFolder)
        return;
    end
    
    if ~istable(organizedData) || width(organizedData) <= 1
        return;
    end
    
    try
        utils = plot_utilities();
        plotConfig = utils.getPlotConfig(config);
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        timeData_ms = organizedData.Frame;
        stimulusTime_ms = config.timing.STIMULUS_TIME_MS;
        
        % FIXED: Get unique trial numbers from the cache
        numROIs = length(roiCache.numbers);
        if numROIs == 0
            return;
        end
        
        % Extract unique trials from organized data
        varNames = organizedData.Properties.VariableNames(2:end);
        uniqueTrials = [];
        for i = 1:length(varNames)
            trialMatch = regexp(varNames{i}, 'ROI\d+_T(\d+)', 'tokens');
            if ~isempty(trialMatch)
                trialNum = str2double(trialMatch{1}{1});
                if ~ismember(trialNum, uniqueTrials)
                    uniqueTrials(end+1) = trialNum;
                end
            end
        end
        uniqueTrials = sort(uniqueTrials);
        
        if isempty(uniqueTrials)
            return;
        end
        
        % Calculate figure layout
        numFigures = ceil(numROIs / plotConfig.maxPlotsPerFigure);
        
        % Get trial colors
        trialColors = utils.getColors('trials', length(uniqueTrials));
        
        % Generate figures
        for figNum = 1:numFigures
            figSuccess = generateTrialsFigureFixed(figNum, numFigures, numROIs, organizedData, ...
                roiCache, timeData_ms, stimulusTime_ms, uniqueTrials, trialColors, ...
                cleanGroupKey, outputFolder, utils, plotConfig, config);
            success = success || figSuccess;
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateTrialsPlot error: %s\n', ME.message);
        end
        success = false;
    end
end

function success = generateTrialsFigureFixed(figNum, numFigures, numROIs, organizedData, ...
    roiCache, timeData_ms, stimulusTime_ms, uniqueTrials, trialColors, ...
    cleanGroupKey, outputFolder, utils, plotConfig, config)
    % FIXED: Generate trials figure with proper threshold display per ROI
    
    success = false;
    
    % Calculate ROI range for this figure
    startROI = (figNum - 1) * plotConfig.maxPlotsPerFigure + 1;
    endROI = min(figNum * plotConfig.maxPlotsPerFigure, numROIs);
    numPlotsThisFig = endROI - startROI + 1;
    
    [nRows, nCols] = utils.calculateLayout(numPlotsThisFig);
    
    fig = utils.createFigure('standard');
    hasData = false;
    
    for roiIdx = startROI:endROI
        subplotIdx = roiIdx - startROI + 1;
        roiNum = roiCache.numbers(roiIdx);
        
        subplot(nRows, nCols, subplotIdx);
        hold on;
        
        % FIXED: Get cached threshold data for this ROI
        [roiNoiseLevel, upperThreshold, lowerThreshold, basicThreshold] = ...
            getROIDataFromCache(roiNum, roiCache);
        
        trialCount = 0;
        trialThresholds = []; % Store thresholds for each trial
        
        % Plot all trials for this ROI
        for trialIdx = 1:length(uniqueTrials)
            trialNum = uniqueTrials(trialIdx);
            colName = sprintf('ROI%d_T%g', roiNum, trialNum);
            
            if ismember(colName, organizedData.Properties.VariableNames)
                trialData = organizedData.(colName);
                if ~all(isnan(trialData))
                    trialCount = trialCount + 1;
                    hasData = true;
                    
                    % Plot trace with color
                    colorIdx = mod(trialIdx-1, size(trialColors, 1)) + 1;
                    traceColor = trialColors(colorIdx, :);
                    
                    h_line = plot(timeData_ms, trialData, 'Color', traceColor, ...
                        'LineWidth', plotConfig.lines.trace);
                    h_line.Color(4) = plotConfig.transparency;
                    
                    % FIXED: Add threshold line for each trial
                    displayThreshold = upperThreshold;
                    if ~isfinite(displayThreshold)
                        displayThreshold = basicThreshold;
                    end
                    
                    if isfinite(displayThreshold) && displayThreshold > 0
                        % Add threshold line with proper styling
                        thresholdStyle = utils.getThresholdStyle(plotConfig, 'individual', ...
                                                               roiNoiseLevel, traceColor);
                        addThresholdLineForTrial(timeData_ms, displayThreshold, thresholdStyle, traceColor);
                        trialThresholds(end+1) = displayThreshold;
                    end
                end
            end
        end
        
        % Add stimulus line (once per subplot)
        utils.addPlotElements(timeData_ms, stimulusTime_ms, NaN, plotConfig, ...
            'ShowStimulus', true, 'ShowThreshold', false);
        
        % Format title with noise level and trial count
        noiseLevelText = createNoiseLevelText(roiNoiseLevel);
        title(sprintf('ROI %d%s (n=%d)', roiNum, noiseLevelText, trialCount), ...
            'FontSize', plotConfig.fonts.subtitle, 'FontWeight', 'bold');
        
        utils.formatSubplot(plotConfig);
        
        % Add legend for first subplot only
        if subplotIdx == 1 && trialCount > 0
            legendEntries = createTrialLegend(uniqueTrials, trialColors, plotConfig);
        end
        
        hold off;
    end
    
    % Save figure if it has data
    if hasData
        if numFigures > 1
            titleText = sprintf('%s - Individual Trials (Part %d/%d)', cleanGroupKey, figNum, numFigures);
            filename = sprintf('%s_trials_part%d.png', cleanGroupKey, figNum);
        else
            titleText = sprintf('%s - Individual Trials', cleanGroupKey);
            filename = sprintf('%s_trials.png', cleanGroupKey);
        end
        
        sgtitle(titleText, 'FontSize', plotConfig.fonts.title, 'Interpreter', 'none', 'FontWeight', 'bold');
        
        filepath = fullfile(outputFolder, filename);
        success = utils.savePlot(fig, filepath, plotConfig);
    end
    
    close(fig);
end

function addThresholdLineForTrial(timeData_ms, threshold, thresholdStyle, traceColor)
    % FIXED: Add threshold line that matches the trace color for individual trials
    
    % Use trace color for threshold line in individual plots
    thresholdColor = traceColor;
    
    % Determine line style based on threshold style
    lineStyle = thresholdStyle.style;
    lineWidth = thresholdStyle.width;
    
    % Draw threshold line across time range
    xRange = [timeData_ms(1), timeData_ms(end)];
    plot(xRange, [threshold, threshold], lineStyle, ...
         'Color', thresholdColor, 'LineWidth', lineWidth, 'HandleVisibility', 'off');
end

function legendEntries = createTrialLegend(uniqueTrials, trialColors, plotConfig)
    % Create legend for trial plots
    
    legendEntries = {};
    
    % Add trial entries (show first few to avoid clutter)
    maxTrialsInLegend = min(5, length(uniqueTrials));
    
    for i = 1:maxTrialsInLegend
        h = plot(NaN, NaN, 'Color', trialColors(i, :), 'LineWidth', plotConfig.lines.trace);
        legendEntries{end+1} = sprintf('Trial %g', uniqueTrials(i));
    end
    
    % Add stimulus entry
    h_stim = plot(NaN, NaN, '--', 'Color', plotConfig.colors.stimulus, ...
                  'LineWidth', plotConfig.lines.stimulus);
    legendEntries{end+1} = 'Stimulus';
    
    if length(legendEntries) > 1
        legend(legendEntries, 'Location', 'northeast', 'FontSize', 8);
    end
end

function noiseLevelText = createNoiseLevelText(roiNoiseLevel)
    % Create noise level text for subplot titles
    
    switch roiNoiseLevel
        case 'low'
            noiseLevelText = ' (Low)';
        case 'high'
            noiseLevelText = ' (High)';
        otherwise
            noiseLevelText = '';
    end
end

function success = generateAveragesPlot(averagedData, config, varargin)
    % FIXED: Generate ROI averaged plots with enhanced threshold styling
    
    success = false;
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'roiCache', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    roiInfo = p.Results.roiInfo;
    roiCache = p.Results.roiCache;
    groupKey = p.Results.groupKey;
    outputFolder = p.Results.outputFolder;
    
    % Validation
    if isempty(roiInfo) || isempty(roiCache) || isempty(groupKey) || isempty(outputFolder)
        return;
    end
    
    if ~istable(averagedData) || width(averagedData) <= 1
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    No averaged data to plot\n');
        end
        return;
    end
    
    try
        utils = plot_utilities();
        plotConfig = utils.getPlotConfig(config);
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        timeData_ms = averagedData.Frame;
        stimulusTime_ms = config.timing.STIMULUS_TIME_MS;
        
        avgVarNames = averagedData.Properties.VariableNames(2:end);
        numAvgPlots = length(avgVarNames);
        numFigures = ceil(numAvgPlots / plotConfig.maxPlotsPerFigure);
        
        % Generate figures
        for figNum = 1:numFigures
            figSuccess = generateAveragesFigureFixed(figNum, numFigures, avgVarNames, averagedData, ...
                timeData_ms, stimulusTime_ms, roiCache, cleanGroupKey, outputFolder, utils, plotConfig, config);
            success = success || figSuccess;
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateAveragesPlot error: %s\n', ME.message);
        end
        success = false;
    end
end

function success = generateAveragesFigureFixed(figNum, numFigures, avgVarNames, averagedData, ...
    timeData_ms, stimulusTime_ms, roiCache, cleanGroupKey, outputFolder, utils, plotConfig, config)
    % FIXED: Generate averages figure with proper threshold calculation
    
    success = false;
    
    % Calculate plot range for this figure
    startPlot = (figNum - 1) * plotConfig.maxPlotsPerFigure + 1;
    endPlot = min(figNum * plotConfig.maxPlotsPerFigure, length(avgVarNames));
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
            plot(timeData_ms, avgData, 'Color', traceColor, 'LineWidth', plotConfig.lines.trace);
            
            % FIXED: Calculate threshold from averaged data baseline
            avgThreshold = calculateAverageThreshold(avgData, config);
            
            % Add plot elements with average styling (green threshold)
            utils.addPlotElements(timeData_ms, stimulusTime_ms, avgThreshold, plotConfig, ...
                'ShowStimulus', true, 'ShowThreshold', true, ...
                'PlotType', 'average', 'TraceColor', traceColor);
        end
        
        % Parse and format title
        roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            nTrials = roiMatch{1}{2};
            
            % Get noise level from cache for context
            if roiCache.hasFilteringStats && isKey(roiCache.noiseMap, roiNum)
                roiNoiseLevel = roiCache.noiseMap(roiNum);
                noiseLevelText = createNoiseLevelText(roiNoiseLevel);
            else
                noiseLevelText = '';
            end
            
            title(sprintf('ROI %d%s (Avg, n=%s)', roiNum, noiseLevelText, nTrials), ...
                'FontSize', plotConfig.fonts.subtitle, 'FontWeight', 'bold');
        else
            title(varName, 'FontSize', plotConfig.fonts.subtitle);
        end
        
        utils.formatSubplot(plotConfig);
        hold off;
    end
    
    % Save figure if it has data
    if hasData
        if numFigures > 1
            titleText = sprintf('%s - Averaged Traces (Part %d/%d)', cleanGroupKey, figNum, numFigures);
            filename = sprintf('%s_averaged_part%d.png', cleanGroupKey, figNum);
        else
            titleText = sprintf('%s - Averaged Traces', cleanGroupKey);
            filename = sprintf('%s_averaged.png', cleanGroupKey);
        end
        
        sgtitle(titleText, 'FontSize', plotConfig.fonts.title, 'FontWeight', 'bold', 'Interpreter', 'none');
        
        filepath = fullfile(outputFolder, filename);
        success = utils.savePlot(fig, filepath, plotConfig);
    end
    
    close(fig);
end

function avgThreshold = calculateAverageThreshold(avgData, config)
    % FIXED: Calculate threshold for averaged data using baseline
    
    % Use baseline window from config
    baselineWindow = config.timing.BASELINE_FRAMES;
    
    % Ensure we have valid data for baseline
    if length(avgData) >= max(baselineWindow)
        baselineData = avgData(baselineWindow);
        
        % Calculate threshold using config multiplier
        baselineSD = std(baselineData, 'omitnan');
        avgThreshold = config.thresholds.SD_MULTIPLIER * baselineSD;
    else
        avgThreshold = NaN;
    end
    
    % Apply default threshold if calculation failed
    if ~isfinite(avgThreshold)
        avgThreshold = config.thresholds.DEFAULT_THRESHOLD;
    end
end

function success = generateCoverslipPlot(totalAveragedData, config, varargin)
    % Generate coverslip average plots (unchanged implementation)
    
    success = false;
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'roiCache', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    roiInfo = p.Results.roiInfo;
    roiCache = p.Results.roiCache;
    groupKey = p.Results.groupKey;
    outputFolder = p.Results.outputFolder;
    
    if isempty(roiInfo) || isempty(groupKey) || isempty(outputFolder)
        return;
    end
    
    if ~istable(totalAveragedData) || width(totalAveragedData) <= 1
        return;
    end
    
    try
        utils = plot_utilities();
        plotConfig = utils.getPlotConfig(config);
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        timeData_ms = totalAveragedData.Frame;
        stimulusTime_ms = config.timing.STIMULUS_TIME_MS;
        varNames = totalAveragedData.Properties.VariableNames(2:end);
        
        fig = utils.createFigure('standard');
        hold on;
        
        hasData = false;
        colors = utils.getColors('noise', 3);
        
        % Plot each data series
        allData = table2array(totalAveragedData(:, 2:end));
        validCols = ~all(isnan(allData), 1);
        validData = allData(:, validCols);
        validVarNames = varNames(validCols);
        
        if ~isempty(validData)
            for i = 1:size(validData, 2)
                data = validData(:, i);
                varName = validVarNames{i};
                hasData = true;
                
                % Determine color based on noise level
                if contains(varName, 'Low_Noise')
                    color = colors(1, :);
                    displayName = 'Low Noise';
                elseif contains(varName, 'High_Noise')
                    color = colors(2, :);
                    displayName = 'High Noise';
                elseif contains(varName, 'All_')
                    color = [0, 0, 0];
                    displayName = 'All ROIs';
                else
                    color = [0.4, 0.4, 0.4];
                    displayName = varName;
                end
                
                % Extract n count for display
                nMatch = regexp(varName, 'n(\d+)', 'tokens');
                if ~isempty(nMatch)
                    displayName = sprintf('%s (n=%s)', displayName, nMatch{1}{1});
                end
                
                plot(timeData_ms, data, 'Color', color, 'LineWidth', 2, 'DisplayName', displayName);
            end
        end
        
        % Add stimulus line and formatting (no threshold for coverslips)
        if hasData
            utils.addPlotElements(timeData_ms, stimulusTime_ms, NaN, plotConfig, ...
                'ShowStimulus', true, 'ShowThreshold', false, 'PlotType', 'coverslip');
            
            utils.formatSubplot(plotConfig);
            title(sprintf('%s - Coverslip Averages by Noise Level', cleanGroupKey), ...
                  'FontSize', plotConfig.fonts.title, 'FontWeight', 'bold', 'Interpreter', 'none');
            
            legend('Location', 'northeast', 'FontSize', 10);
            
            filename = sprintf('%s_coverslip_averages.png', cleanGroupKey);
            filepath = fullfile(outputFolder, filename);
            success = utils.savePlot(fig, filepath, plotConfig);
        end
        
        hold off;
        close(fig);
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateCoverslipPlot error: %s\n', ME.message);
        end
        success = false;
    end
end

function [roiNoiseLevel, upperThreshold, lowerThreshold, basicThreshold] = getROIDataFromCache(roiNum, roiCache)
    % FIXED: Fast ROI data retrieval using validated cache
    
    % Initialize defaults
    roiNoiseLevel = 'unknown';
    upperThreshold = NaN;
    lowerThreshold = NaN;
    basicThreshold = NaN;
    
    % Retrieve from cache if available
    if roiCache.hasFilteringStats
        try
            if isKey(roiCache.noiseMap, roiNum)
                roiNoiseLevel = roiCache.noiseMap(roiNum);
            end
            
            if isKey(roiCache.upperThresholds, roiNum)
                upperThreshold = roiCache.upperThresholds(roiNum);
            end
            
            if isKey(roiCache.lowerThresholds, roiNum)
                lowerThreshold = roiCache.lowerThresholds(roiNum);
            end
            
            if isKey(roiCache.basicThresholds, roiNum)
                basicThreshold = roiCache.basicThresholds(roiNum);
            end
        catch
            % Cache lookup failed, use defaults
        end
    end
end