function plot1AP = plot_1ap()
    % PLOT_1AP - 1AP experiment plotting functions with per-trial threshold styling
    
    plot1AP.execute = @executePlotTask;
    plot1AP.generateTrials = @generateTrialsPlot;
    plot1AP.generateAverages = @generateAveragesPlot;
    plot1AP.generateCoverslip = @generateCoverslipPlot;
end

function success = executePlotTask(task, config, varargin)
    % Execute a 1AP plotting task with standardized signature
    
    success = false;
    
    try
        switch task.type
            case 'trials'
                success = generateTrialsPlot(task.data, config, ...
                    'roiInfo', task.roiInfo, 'groupKey', task.groupKey, ...
                    'outputFolder', task.outputFolder, varargin{:});
                    
            case 'averages'
                success = generateAveragesPlot(task.data, config, ...
                    'roiInfo', task.roiInfo, 'groupKey', task.groupKey, ...
                    'outputFolder', task.outputFolder, varargin{:});
                    
            case 'coverslip'
                success = generateCoverslipPlot(task.data, config, ...
                    'roiInfo', task.roiInfo, 'groupKey', task.groupKey, ...
                    'outputFolder', task.outputFolder, varargin{:});
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    1AP plot task failed: %s\n', ME.message);
        end
        success = false;
    end
end

function success = generateTrialsPlot(organizedData, config, varargin)
    % Generate individual trials plots with ROI cache optimization
    
    success = false;
    
    % Parse inputs INCLUDING roiCache
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'roiCache', [], @isstruct);  % ADD THIS
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    roiInfo = p.Results.roiInfo;
    roiCache = p.Results.roiCache;  % ADD THIS
    groupKey = p.Results.groupKey;
    outputFolder = p.Results.outputFolder;
    
    if isempty(roiInfo) || isempty(groupKey) || isempty(outputFolder)
        return;
    end
    
    try
        utils = plot_utilities();
        plotConfig = utils.getPlotConfig(config);
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        timeData_ms = organizedData.Frame;
        stimulusTime_ms = config.timing.STIMULUS_TIME_MS;
        
        if isempty(roiInfo.roiNumbers)
            return;
        end
        
        % Calculate figure layout
        numROIs = length(roiInfo.roiNumbers);
        numFigures = ceil(numROIs / plotConfig.maxPlotsPerFigure);
        
        % Get trial colors
        trialColors = utils.getColors('trials', 10);
        uniqueTrials = unique(roiInfo.originalTrialNumbers);
        uniqueTrials = uniqueTrials(isfinite(uniqueTrials));
        uniqueTrials = sort(uniqueTrials);
        
        if isempty(uniqueTrials)
            return;
        end
        
        % Pass roiCache to generateTrialsFigure
        for figNum = 1:numFigures
            success = generateTrialsFigure(figNum, numFigures, numROIs, organizedData, ...
                roiInfo, roiCache, timeData_ms, stimulusTime_ms, uniqueTrials, trialColors, ...
                cleanGroupKey, outputFolder, utils, plotConfig, config) || success;
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateTrialsPlot error: %s\n', ME.message);
        end
        success = false;
    end
end

% FIX 3: Update generateTrialsFigure to use roiCache properly
function success = generateTrialsFigure(figNum, numFigures, numROIs, organizedData, ...
    roiInfo, roiCache, timeData_ms, stimulusTime_ms, uniqueTrials, trialColors, ...
    cleanGroupKey, outputFolder, utils, plotConfig, config)
    % WITH CACHE OPTIMIZATION - No redundant lookups!
    
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
        originalROI = roiInfo.roiNumbers(roiIdx);
        
        subplot(nRows, nCols, subplotIdx);
        hold on;
        
        trialCount = 0;
        
        % USE CACHE FOR FAST LOOKUP - This is the optimization!
        roiNoiseLevel = 'unknown';
        upperThreshold = NaN;
        lowerThreshold = NaN;
        basicThreshold = NaN;
        
        if ~isempty(roiCache) && roiCache.hasFilteringStats
            % O(1) lookups using cache instead of repeated string parsing
            if isKey(roiCache.noiseMap, originalROI)
                roiNoiseLevel = roiCache.noiseMap(originalROI);
            end
            
            if isKey(roiCache.upperThresholds, originalROI)
                upperThreshold = roiCache.upperThresholds(originalROI);
            end
            
            if isKey(roiCache.lowerThresholds, originalROI)
                lowerThreshold = roiCache.lowerThresholds(originalROI);
            end
            
            if isKey(roiCache.basicThresholds, originalROI)
                basicThreshold = roiCache.basicThresholds(originalROI);
            end
        else
            % Fallback if cache not available (shouldn't happen)
            if isfield(roiInfo, 'roiNoiseMap') && isa(roiInfo.roiNoiseMap, 'containers.Map') && ...
               isKey(roiInfo.roiNoiseMap, originalROI)
                roiNoiseLevel = roiInfo.roiNoiseMap(originalROI);
            end
        end
        
        % Plot trials for this ROI
        for i = 1:length(uniqueTrials)
            trialNum = uniqueTrials(i);
            colName = sprintf('ROI%d_T%g', originalROI, trialNum);
            
            if ismember(colName, organizedData.Properties.VariableNames)
                trialData = organizedData.(colName);
                if ~all(isnan(trialData))
                    trialCount = trialCount + 1;
                    hasData = true;
                    
                    colorIdx = mod(i-1, size(trialColors, 1)) + 1;
                    traceColor = trialColors(colorIdx, :);
                    
                    h_line = plot(timeData_ms, trialData, 'Color', traceColor, ...
                        'LineWidth', plotConfig.lines.trace);
                    h_line.Color(4) = plotConfig.transparency;
                    
                    % Use cached Schmitt upper threshold if available
                    displayThreshold = upperThreshold;
                    if ~isfinite(displayThreshold)
                        % Fallback to basic threshold
                        trialIdx = find(roiInfo.originalTrialNumbers == trialNum, 1);
                        if isempty(trialIdx)
                            trialIdx = i;
                        end
                        displayThreshold = getValidThreshold(roiIdx, trialIdx, roiInfo, config);
                    end
                    
                    % Add threshold line with pre-calculated styling
                    if isfinite(displayThreshold) && displayThreshold > 0
                        utils.addPlotElements(timeData_ms, stimulusTime_ms, displayThreshold, plotConfig, ...
                            'ShowStimulus', false, 'ShowThreshold', true, ...
                            'PlotType', 'individual', 'NoiseLevel', roiNoiseLevel, ...
                            'TraceColor', traceColor, 'UpperThreshold', upperThreshold, ...
                            'LowerThreshold', lowerThreshold);
                    end
                end
            end
        end
        
        % Add stimulus line (once per subplot)
        utils.addPlotElements(timeData_ms, stimulusTime_ms, NaN, plotConfig, ...
            'ShowStimulus', true, 'ShowThreshold', false);
        
        % Format title with cached noise level
        noiseLevelText = createNoiseLevelSummary(roiNoiseLevel, trialCount);
        
        title(sprintf('ROI %d%s (n=%d)', originalROI, noiseLevelText, trialCount), ...
            'FontSize', plotConfig.fonts.subtitle, 'FontWeight', 'bold');
        utils.formatSubplot(plotConfig);
        
        % Add legend for first subplot only
        if subplotIdx == 1 && trialCount > 0
            utils.createLegend('trials', plotConfig, 'NumTrials', length(uniqueTrials), ...
                'TrialNumbers', uniqueTrials, 'IncludeStimulus', true, 'FontSize', 8);
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

function noiseLevelText = createNoiseLevelSummary(roiNoiseLevel, trialCount)
    % OPTIMIZED: Use pre-calculated noise level instead of analyzing multiple trials
    
    switch roiNoiseLevel
        case 'low'
            noiseLevelText = ' (Low)';
        case 'high'
            noiseLevelText = ' (High)';
        case 'unknown'
            noiseLevelText = ' (?)';
        otherwise
            noiseLevelText = '';
    end
end

function success = generateAveragesPlot(averagedData, config, varargin)
    % Generate ROI averaged plots with enhanced threshold styling
    
    success = false;
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    roiInfo = p.Results.roiInfo;
    groupKey = p.Results.groupKey;
    outputFolder = p.Results.outputFolder;
    
    if isempty(roiInfo) || isempty(groupKey) || isempty(outputFolder)
        return;
    end
    
    try
        utils = plot_utilities();
        plotConfig = utils.getPlotConfig(config);
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        timeData_ms = averagedData.Frame;
        stimulusTime_ms = config.timing.STIMULUS_TIME_MS;
        
        if width(averagedData) <= 1
            return;
        end
        
        avgVarNames = averagedData.Properties.VariableNames(2:end);
        numAvgPlots = length(avgVarNames);
        numFigures = ceil(numAvgPlots / plotConfig.maxPlotsPerFigure);
        
        % Generate figures
        for figNum = 1:numFigures
            success = generateAveragesFigure(figNum, numFigures, avgVarNames, averagedData, ...
                timeData_ms, stimulusTime_ms, roiInfo, cleanGroupKey, outputFolder, utils, plotConfig) || success;
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateAveragesPlot error: %s\n', ME.message);
        end
        success = false;
    end
end

function success = generateAveragesFigure(figNum, numFigures, avgVarNames, averagedData, ...
    timeData_ms, stimulusTime_ms, roiInfo, cleanGroupKey, outputFolder, utils, plotConfig)
    % Generate a single averages figure with enhanced threshold styling
    
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
            traceColor = [0, 0, 0]; % Black for averages
            plot(timeData_ms, avgData, 'Color', traceColor, 'LineWidth', plotConfig.lines.trace);
            
            % Calculate and add threshold with AVERAGE styling (green)
            avgThreshold = calculateAverageThreshold(avgData, plotConfig, config);
            
            % Use average plot type to get green threshold
            utils.addPlotElements(timeData_ms, stimulusTime_ms, avgThreshold, plotConfig, ...
                'ShowStimulus', true, 'ShowThreshold', true, ...
                'PlotType', 'average', 'TraceColor', traceColor);
        end
        
        % Parse and format title
        roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
        if ~isempty(roiMatch)
            originalROI = str2double(roiMatch{1}{1});
            
            % For averages, show the predominant noise level for context
            roiNoiseLevel = 'unknown';
            if isKey(roiInfo.roiNoiseMap, originalROI)
                roiNoiseLevel = roiInfo.roiNoiseMap(originalROI);
            end
            
            noiseLevelText = '';
            if strcmp(roiNoiseLevel, 'low')
                noiseLevelText = ' (Avg-Low)';
            elseif strcmp(roiNoiseLevel, 'high')
                noiseLevelText = ' (Avg-High)';
            else
                noiseLevelText = ' (Avg)';
            end
            
            title(sprintf('ROI %d%s (n=%s)', originalROI, noiseLevelText, roiMatch{1}{2}), ...
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

function success = generateCoverslipPlot(totalAveragedData, config, varargin)
    % Generate coverslip average plots (unchanged - no per-trial thresholds here)
    
    success = false;
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    roiInfo = p.Results.roiInfo;
    groupKey = p.Results.groupKey;
    outputFolder = p.Results.outputFolder;
    
    if isempty(roiInfo) || isempty(groupKey) || isempty(outputFolder)
        return;
    end
    
    try
        utils = plot_utilities();
        plotConfig = utils.getPlotConfig(config);
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        
        if width(totalAveragedData) <= 1
            return;
        end
        
        timeData_ms = totalAveragedData.Frame;
        stimulusTime_ms = config.timing.STIMULUS_TIME_MS;
        varNames = totalAveragedData.Properties.VariableNames(2:end);
        
        fig = utils.createFigure('standard');
        hold on;
        
        hasData = false;
        
        % Get noise level colors
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
                
                % Determine color and display name based on noise level
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
                
                h = plot(timeData_ms, data, 'Color', color, 'LineWidth', 2);
            end
        end
        
        % Add stimulus line and formatting (no threshold for coverslips)
        if hasData
            utils.addPlotElements(timeData_ms, stimulusTime_ms, NaN, plotConfig, ...
                'ShowStimulus', true, 'ShowThreshold', false, ...
                'PlotType', 'coverslip');
            
            utils.formatSubplot(plotConfig);
            title(sprintf('%s - Coverslip Averages by Noise Level', cleanGroupKey), ...
                  'FontSize', plotConfig.fonts.title, 'FontWeight', 'bold', 'Interpreter', 'none');
            
            % Create standardized noise level legend
            utils.createLegend('noise_level', plotConfig, 'IncludeStimulus', true, 'FontSize', 10);
            
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

function avgThreshold = calculateAverageThreshold(avgData, plotConfig, cfg)
    % CALCULATEAVERAGETHRESHOLD - Calculate threshold for averaged data using config
    %
    % INPUTS:
    %   avgData - averaged trace data
    %   plotConfig - plot configuration structure  
    %   cfg - main GluSnFR configuration (optional)
    %
    % OUTPUT:
    %   avgThreshold - calculated threshold for averaged data
    
    % Get config if not provided
    if nargin < 3
        cfg = GluSnFRConfig();
    end
    
    % Use baseline window from config
    baselineWindow = cfg.timing.BASELINE_FRAMES;
    
    % Ensure we have valid data for baseline
    if length(avgData) >= max(baselineWindow)
        baselineData = avgData(baselineWindow);
        
        % Calculate threshold using CONFIG multiplier, not hardcoded 3.0
        baselineSD = std(baselineData, 'omitnan');
        avgThreshold = cfg.thresholds.SD_MULTIPLIER * baselineSD;
    else
        % Not enough data for baseline calculation
        avgThreshold = NaN;
    end
    
    % Apply default threshold if calculation failed
    if ~isfinite(avgThreshold)
        avgThreshold = cfg.thresholds.DEFAULT_THRESHOLD;
    end
end

function displayThreshold = getValidThreshold(roiIdx, trialIdx, roiInfo, config)
    % GETVALIDTHRESHOLD - Robust threshold retrieval with fallbacks
    %
    % REPLACE the threshold retrieval logic in plot_1ap.m generateTrialsFigure
    % (around lines 195-205) with a call to this function
    
    displayThreshold = NaN;
    
    % Priority 1: Try to get Schmitt upper threshold from filtering stats
    if isfield(roiInfo, 'filteringStats') && roiInfo.filteringStats.available
        roiNum = roiInfo.roiNumbers(roiIdx);
        
        if isKey(roiInfo.filteringStats.roiUpperThresholds, roiNum)
            displayThreshold = roiInfo.filteringStats.roiUpperThresholds(roiNum);
            if isfinite(displayThreshold)
                return; % Found valid Schmitt threshold
            end
        end
    end
    
    % Priority 2: Try to get basic threshold from thresholds array
    if isfield(roiInfo, 'thresholds')
        [nROIs, nTrials] = size(roiInfo.thresholds);
        
        % Bounds checking
        if roiIdx <= nROIs && trialIdx <= nTrials
            threshold = roiInfo.thresholds(roiIdx, trialIdx);
            if isfinite(threshold) && threshold > 0
                displayThreshold = threshold;
                return; % Found valid basic threshold
            end
        end
        
        % Priority 3: If specific trial invalid, try to get any valid threshold for this ROI
        if roiIdx <= nROIs
            roiThresholds = roiInfo.thresholds(roiIdx, :);
            validThresholds = roiThresholds(isfinite(roiThresholds) & roiThresholds > 0);
            
            if ~isempty(validThresholds)
                % Use median of valid thresholds as fallback
                displayThreshold = median(validThresholds);
                return;
            end
        end
    end
    
    % Priority 4: Ultimate fallback - use config default
    if ~isfinite(displayThreshold)
        displayThreshold = config.thresholds.DEFAULT_THRESHOLD;
    end
end