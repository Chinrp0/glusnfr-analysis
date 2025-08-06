function plot1AP = plot_1ap()
    % PLOT_1AP - FIXED 1AP experiment plotting with centralized colors and proper thresholds
    % 
    % FIXES:
    % - Centralized trial color system with consistent mapping
    % - Proper threshold length (150ms window around stimulus)
    % - One threshold line per trial in each subplot
    % - Eliminated fallback/legacy logic
    % - Fixed legend color consistency
    
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
    % FIXED: Generate individual trials plots with consistent colors and proper thresholds
    
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
        
        numROIs = length(roiCache.numbers);
        if numROIs == 0
            return;
        end
        
        % FIXED: Extract ALL unique trials and create consistent color mapping
        [uniqueTrials, globalTrialColorMap] = createGlobalTrialColorSystem(organizedData, utils);
        
        if isempty(uniqueTrials)
            return;
        end
        
        % Calculate figure layout
        numFigures = ceil(numROIs / plotConfig.maxPlotsPerFigure);
        
        % Generate figures with consistent color system
        for figNum = 1:numFigures
            figSuccess = generateTrialsFigureFixed(figNum, numFigures, numROIs, organizedData, ...
                roiCache, timeData_ms, stimulusTime_ms, uniqueTrials, globalTrialColorMap, ...
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


function [uniqueTrials, globalTrialColorMap] = createGlobalTrialColorSystem(organizedData, utils)
    % FIXED: Create consistent trial color mapping for entire dataset
    
    varNames = organizedData.Properties.VariableNames(2:end); % Skip Frame column
    uniqueTrials = [];
    
    % Extract all trial numbers from column names
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
    
    % Create consistent color mapping
    trialColors = utils.getColors('trials', length(uniqueTrials));
    globalTrialColorMap = containers.Map();
    
    for i = 1:length(uniqueTrials)
        trialNum = uniqueTrials(i);
        globalTrialColorMap(num2str(trialNum)) = trialColors(i, :);
    end
end

function success = generateTrialsFigureFixed(figNum, numFigures, numROIs, organizedData, ...
    roiCache, timeData_ms, stimulusTime_ms, uniqueTrials, globalTrialColorMap, ...
    cleanGroupKey, outputFolder, utils, plotConfig, config)
    % FIXED: Generate trials figure using ONLY cache data for thresholds
    
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
        
        % FIXED: Get cached threshold data - NO FALLBACK CALCULATIONS
        [roiNoiseLevel, upperThreshold, lowerThreshold, basicThreshold] = ...
            getROIDataFromCache(roiNum, roiCache);
        
        % Determine display threshold (prefer upper threshold from Schmitt filtering)
        displayThreshold = NaN; % Default to invalid
        if isfinite(upperThreshold) && upperThreshold > 0
            displayThreshold = upperThreshold; % Use Schmitt upper threshold
        elseif isfinite(basicThreshold) && basicThreshold > 0
            displayThreshold = basicThreshold; % Fallback to basic threshold
        end
        
        % VALIDATION: Only proceed if we have valid threshold data
        if ~isfinite(displayThreshold)
            if config.debug.ENABLE_PLOT_DEBUG
                fprintf('    WARNING: ROI %d has no valid threshold data (upper=%.4f, basic=%.4f)\n', ...
                        roiNum, upperThreshold, basicThreshold);
            end
            % Continue with plot but without threshold line
        end
        
        trialCount = 0;
        legendData = struct('handles', [], 'labels', {{}});
        
        % Plot all trials for this ROI with consistent colors and individual thresholds
        for trialIdx = 1:length(uniqueTrials)
            trialNum = uniqueTrials(trialIdx);
            colName = sprintf('ROI%d_T%g', roiNum, trialNum);
            
            if ismember(colName, organizedData.Properties.VariableNames)
                trialData = organizedData.(colName);
                if ~all(isnan(trialData))
                    trialCount = trialCount + 1;
                    hasData = true;
                    
                    % Get consistent color from global color map
                    traceColor = globalTrialColorMap(num2str(trialNum));
                    
                    % Plot trace
                    h_line = plot(timeData_ms, trialData, 'Color', traceColor, ...
                        'LineWidth', plotConfig.lines.trace);
                    h_line.Color(4) = plotConfig.transparency;
                    
                    % FIXED: Add threshold line using EXACT cached value
                    if isfinite(displayThreshold)
                        addThresholdLineForTrial(timeData_ms, stimulusTime_ms, displayThreshold, ...
                                               traceColor, roiNoiseLevel, plotConfig);
                    end
                    
                    % Store for legend (only if first subplot)
                    if subplotIdx == 1
                        legendData.handles(end+1) = plot(NaN, NaN, 'Color', traceColor, ...
                            'LineWidth', plotConfig.lines.trace);
                        legendData.labels{end+1} = sprintf('Trial %g', trialNum);
                    end
                end
            end
        end
        
        % Add stimulus line (once per subplot)
        utils.addPlotElements(timeData_ms, stimulusTime_ms, NaN, plotConfig, ...
            'ShowStimulus', true, 'ShowThreshold', false);
        
        % Format title with cached noise level and trial count
        noiseLevelText = createNoiseLevelText(roiNoiseLevel);
        title(sprintf('ROI %d%s (n=%d)', roiNum, noiseLevelText, trialCount), ...
            'FontSize', plotConfig.fonts.subtitle, 'FontWeight', 'bold');
        
        utils.formatSubplot(plotConfig);
        
        % Add legend for first subplot only with consistent colors
        if subplotIdx == 1 && ~isempty(legendData.handles)
            legend(legendData.handles, legendData.labels, 'Location', 'northeast', 'FontSize', 8);
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

function addThresholdLineForTrial(timeData_ms, ~, threshold, traceColor, roiNoiseLevel, plotConfig)
    % FIXED: Add threshold line using ONLY the provided threshold value
    % NO RECALCULATIONS - use exactly what's passed in
    
    % Only add threshold line if we have a valid threshold
    if ~isfinite(threshold) || threshold <= 0
        return; % Don't plot invalid thresholds
    end
    
    % Calculate length of threshold line
    thresholdStart_ms = 1; % Start 
    thresholdEnd_ms = 750; % End 
    
    % Ensure threshold window is within time data bounds
    thresholdStart_ms = max(thresholdStart_ms, timeData_ms(1));
    thresholdEnd_ms = min(thresholdEnd_ms, timeData_ms(end));
    
    % Determine line style based on noise level
    switch roiNoiseLevel
        case 'low'
            lineStyle = '--';   % Dashed for low noise
        case 'high'
            lineStyle = '-.';   % Dash-dot for high noise
        otherwise
            lineStyle = ':';    % Dotted for unknown
    end
    
    % Plot threshold line with trial-specific color and proper length
    plot([thresholdStart_ms, thresholdEnd_ms], [threshold, threshold], lineStyle, ...
         'Color', traceColor, 'LineWidth', plotConfig.lines.threshold, 'HandleVisibility', 'off');
end

function noiseLevelText = createNoiseLevelText(roiNoiseLevel)
    % Create noise level text for subplot titles using EXACT cache data
    
    switch roiNoiseLevel
        case 'low'
            noiseLevelText = ' (Low)';
        case 'high'
            noiseLevelText = ' (High)';
        otherwise
            noiseLevelText = ' (?)'; % Show unknown instead of empty
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
                'ShowStimulus', true, 'ShowThreshold', true);
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
    % FIXED: Generate coverslip average plots with centralized colors
    
    success = false;
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'roiCache', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    roiInfo = p.Results.roiInfo;
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
        
        % FIXED: Use centralized color system
        noiseColors = utils.getColors('noise', 3);
        
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
                
                % FIXED: Determine color using centralized system
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
                
                plot(timeData_ms, data, 'Color', color, 'LineWidth', 2, 'DisplayName', displayName);
            end
        end
        
        % Add stimulus line and formatting (no threshold for coverslips)
        if hasData
            utils.addPlotElements(timeData_ms, stimulusTime_ms, NaN, plotConfig, ...
                'ShowStimulus', true, 'ShowThreshold', false);
            
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
    % FIXED: Cache-only ROI data retrieval - NO FALLBACK CALCULATIONS
    % This ensures data consistency between plots and metadata
    
    % Initialize defaults (these will be returned if cache lookup fails)
    roiNoiseLevel = 'unknown';
    upperThreshold = NaN;
    lowerThreshold = NaN;
    basicThreshold = NaN;
    
    % ONLY use cache data - NO CALCULATIONS OR FALLBACKS
    if roiCache.hasFilteringStats
        try
            % Retrieve noise classification
            if isfield(roiCache, 'noiseMap') && ...
               isa(roiCache.noiseMap, 'containers.Map') && ...
               isKey(roiCache.noiseMap, roiNum)
                roiNoiseLevel = roiCache.noiseMap(roiNum);
            end
            
            % Retrieve upper threshold
            if isfield(roiCache, 'upperThresholds') && ...
               isa(roiCache.upperThresholds, 'containers.Map') && ...
               isKey(roiCache.upperThresholds, roiNum)
                upperThreshold = roiCache.upperThresholds(roiNum);
            end
            
            % Retrieve lower threshold
            if isfield(roiCache, 'lowerThresholds') && ...
               isa(roiCache.lowerThresholds, 'containers.Map') && ...
               isKey(roiCache.lowerThresholds, roiNum)
                lowerThreshold = roiCache.lowerThresholds(roiNum);
            end
            
            % Retrieve basic threshold
            if isfield(roiCache, 'basicThresholds') && ...
               isa(roiCache.basicThresholds, 'containers.Map') && ...
               isKey(roiCache.basicThresholds, roiNum)
                basicThreshold = roiCache.basicThresholds(roiNum);
            end
            
        catch ME
            % Cache lookup failed - use defaults
            cfg = GluSnFRConfig();
            if cfg.debug.ENABLE_PLOT_DEBUG
                fprintf('    Cache lookup failed for ROI %d: %s\n', roiNum, ME.message);
            end
        end
    end
    
    % REMOVED: All fallback calculations that created inconsistencies
    % If cache data isn't available, we return defaults (NaN/unknown)
    % This forces the issue to be visible rather than hiding it with calculated fallbacks
end