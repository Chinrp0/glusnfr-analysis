function plot1APTrials = plot_1AP_trials()
    % PLOT_1AP_TRIALS - Individual trial plotting module for 1AP experiments
    % 
    % FOCUSED RESPONSIBILITIES:
    % - Individual ROI trial plots with proper threshold display
    % - Trial color management and legend creation
    % - ROI cache-based threshold rendering
    
    plot1APTrials.execute = @executePlotTask;
    plot1APTrials.generateTrialsPlot = @generateTrialsPlot;
end

function success = executePlotTask(task, config, varargin)
    % Main task dispatcher for trial plots
    
    success = false;
    
    % Validate task and cache
    sharedUtils = plot_1AP_shared_utils();
    if ~sharedUtils.validateTaskAndCache(task, config)
        return;
    end
    
    try
        success = generateTrialsPlot(task.data, config, ...
            'roiInfo', task.roiInfo, 'roiCache', task.roiCache, ...
            'groupKey', task.groupKey, 'outputFolder', task.outputFolder);
            
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    1AP trials plot task failed: %s\n', ME.message);
        end
        success = false;
    end
end

function success = generateTrialsPlot(organizedData, config, varargin)
    % Generate individual trials plots with FIXED threshold visualization
    
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
        styleConfig = utils.getPlotStyles(config);
        
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
        success = generateAllTrialsFigures(organizedData, p.Results.roiCache, ...
            timeData_ms, stimulusTime_ms, uniqueTrials, globalTrialColorMap, ...
            cleanGroupKey, p.Results.outputFolder, utils, styleConfig, config);
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateTrialsPlot error: %s\n', ME.message);
        end
    end
end

function success = generateAllTrialsFigures(organizedData, roiCache, timeData_ms, ...
    stimulusTime_ms, uniqueTrials, globalTrialColorMap, cleanGroupKey, ...
    outputFolder, utils, styleConfig, config)
    % Generate all trial figures with proper pagination
    
    cache_manager = roi_cache();
    roiNumbers = cache_manager.getROINumbers(roiCache);
    numROIs = length(roiNumbers);
    
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
    
    % Get cache manager
    cache_manager = roi_cache();
    roiNumbers = cache_manager.getROINumbers(roiCache);
    
    for roiIdx = startROI:endROI
        subplotIdx = roiIdx - startROI + 1;
        roiNum = roiNumbers(roiIdx);
        
        subplot(nRows, nCols, subplotIdx);
        hold on;
        
        % FIXED: Get ROI data from cache with error checking
        [roiNoiseLevel, upperThreshold, lowerThreshold, basicThreshold, standardDeviation] = ...
            cache_manager.retrieve(roiCache, roiNum);
        
        if config.debug.ENABLE_PLOT_DEBUG && roiIdx <= startROI + 2  % Debug first few
            fprintf('    ROI %d: noise=%s, upper=%.4f, lower=%.4f, basic=%.4f\n', ...
                    roiNum, roiNoiseLevel, upperThreshold, lowerThreshold, basicThreshold);
        end
        
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
                    
                    % FIXED: Add threshold line using proper renderer
                    if isfinite(upperThreshold) && upperThreshold > 0
                        addThresholdLine(timeData_ms, stimulusTime_ms, upperThreshold, ...
                                       traceColor, roiNoiseLevel, trialNum, styleConfig);
                    end
                    
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
        
        % FIXED: Format subplot with proper noise level display
        sharedUtils = plot_1AP_shared_utils();
        noiseLevelText = sharedUtils.createNoiseLevelDisplayText(roiNoiseLevel);
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
            'trials', outputFolder, utils, styleConfig, roiCache);
    end
    
    close(fig);
end

function addThresholdLine(timeData_ms, stimulusTime_ms, upperThreshold, traceColor, noiseLevel, trialNum, styleConfig)
    % FIXED: Add threshold line with proper styling and unique identifier
    
    % Calculate threshold window
    thresholdStart_ms = max(1, timeData_ms(1));
    thresholdEnd_ms = min(750, timeData_ms(end));
    
    % Get line style based on noise level
    switch lower(noiseLevel)
        case 'low'
            lineStyle = '--';
        case 'high'
            lineStyle = '-.';
        otherwise
            lineStyle = ':';
    end
    
    % CRITICAL: Create unique tag to prevent overwriting
    uniqueTag = sprintf('threshold_trial%g_%d', trialNum, round(rand()*10000));
    
    % Plot threshold line with trace color
    h_thresh = plot([thresholdStart_ms, thresholdEnd_ms], ...
         [upperThreshold, upperThreshold], ...
         lineStyle, 'Color', traceColor, ...
         'LineWidth', styleConfig.thresholds.lineWidth, ...
         'HandleVisibility', 'off', 'Tag', uniqueTag);
     
    % Apply transparency
    if ~isempty(h_thresh)
        h_thresh.Color(4) = styleConfig.thresholds.transparency;
    end
end

% Removed - using shared utility

function [uniqueTrials, globalTrialColorMap] = createGlobalTrialColorSystem(organizedData, utils)
    % Create consistent trial color mapping
    
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

function success = saveFigureWithTitle(fig, figNum, numFigures, cleanGroupKey, plotType, outputFolder, utils, styleConfig, roiCache)
    % FIXED: Save figure with descriptive title including noise level counts
    
    % Calculate noise level summary for title
    sharedUtils = plot_1AP_shared_utils();
    noiseSummary = sharedUtils.calculateNoiseSummary(roiCache);
    
    if numFigures > 1
        titleText = sprintf('%s - %s (Part %d/%d)%s', cleanGroupKey, sharedUtils.titleCase(plotType), figNum, numFigures, noiseSummary);
        filename = sprintf('%s_%s_part%d.png', cleanGroupKey, plotType, figNum);
    else
        titleText = sprintf('%s - %s%s', cleanGroupKey, sharedUtils.titleCase(plotType), noiseSummary);
        filename = sprintf('%s_%s.png', cleanGroupKey, plotType);
    end
    
    sgtitle(titleText, 'FontSize', styleConfig.fonts.title, 'Interpreter', 'none', 'FontWeight', 'bold');
    
    filepath = fullfile(outputFolder, filename);
    success = utils.savePlot(fig, filepath, styleConfig);
end

% Removed duplicate functions - using shared utilities: