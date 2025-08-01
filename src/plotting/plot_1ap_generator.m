function plot1AP = plot_1ap_generator()
    % PLOT_1AP_GENERATOR - Complete 1AP plotting implementation
    
    plot1AP.generateSequential = @generate1APSequential;
    plot1AP.generateTrialsPlot = @generateTrialsPlot;
    plot1AP.generateAveragedPlot = @generateAveragedPlot;
    plot1AP.generateCoverslipPlot = @generateCoverslipPlot;
    plot1AP.generateParallel = @generate1APParallel;
end

function generate1APSequential(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Sequential 1AP plot generation
    
    plotsGenerated = 0;
    
    % Individual trials plots
    if istable(organizedData) && width(organizedData) > 1
        success = generateTrialsPlot(organizedData, roiInfo, groupKey, outputFolders.roi_trials);
        if success, plotsGenerated = plotsGenerated + 1; end
    end
    
    % ROI averaged plots  
    if isfield(averagedData, 'roi') && width(averagedData.roi) > 1
        success = generateAveragedPlot(averagedData.roi, roiInfo, groupKey, outputFolders.roi_averages);
        if success, plotsGenerated = plotsGenerated + 1; end
    end
    
    % Coverslip averages
    if isfield(averagedData, 'total') && width(averagedData.total) > 1
        success = generateCoverslipPlot(averagedData.total, roiInfo, groupKey, outputFolders.coverslip_averages);
        if success, plotsGenerated = plotsGenerated + 1; end
    end
    
    fprintf('    Generated %d/3 1AP plots successfully\n', plotsGenerated);
end

function generate1APParallel(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Parallel 1AP plot generation
    
    % Create plot tasks
    tasks = createPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    
    if isempty(tasks)
        return;
    end
    
    % Execute in parallel
    pool = gcp('nocreate');
    if ~isempty(pool) && length(tasks) > 1
        futures = cell(length(tasks), 1);
        
        % Submit tasks
        for i = 1:length(tasks)
            futures{i} = parfeval(pool, @executePlotTask, 1, tasks{i});
        end
        
        % Collect results
        plotsGenerated = 0;
        for i = 1:length(tasks)
            try
                success = fetchOutputs(futures{i});
                if success, plotsGenerated = plotsGenerated + 1; end
            catch
                % Silent failure for individual tasks
            end
        end
        
        fprintf('    Generated %d/%d 1AP plots (parallel)\n', plotsGenerated, length(tasks));
    else
        % Fallback to sequential
        generate1APSequential(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    end
end

function tasks = createPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Create independent plotting tasks for parallel execution
    
    tasks = {};
    
    if istable(organizedData) && width(organizedData) > 1
        tasks{end+1} = struct('type', 'trials', 'data', organizedData, ...
                             'roiInfo', roiInfo, 'groupKey', groupKey, ...
                             'outputFolder', outputFolders.roi_trials);
    end
    
    if isfield(averagedData, 'roi') && width(averagedData.roi) > 1
        tasks{end+1} = struct('type', 'averaged', 'data', averagedData.roi, ...
                             'roiInfo', roiInfo, 'groupKey', groupKey, ...
                             'outputFolder', outputFolders.roi_averages);
    end
    
    if isfield(averagedData, 'total') && width(averagedData.total) > 1
        tasks{end+1} = struct('type', 'coverslip', 'data', averagedData.total, ...
                             'roiInfo', roiInfo, 'groupKey', groupKey, ...
                             'outputFolder', outputFolders.coverslip_averages);
    end
end

function success = executePlotTask(task)
    % Execute a single plotting task
    
    success = false;
    
    try
        switch task.type
            case 'trials'
                success = generateTrialsPlot(task.data, task.roiInfo, task.groupKey, task.outputFolder);
            case 'averaged'
                success = generateAveragedPlot(task.data, task.roiInfo, task.groupKey, task.outputFolder);
            case 'coverslip'
                success = generateCoverslipPlot(task.data, task.roiInfo, task.groupKey, task.outputFolder);
        end
    catch
        success = false;
    end
end

function success = generateTrialsPlot(organizedData, roiInfo, groupKey, outputFolder)
    % OPTIMIZED: Pre-calculate all subplot requirements to avoid iterative resizing
    
    success = false;
    DEBUG_MODE = false; % Set to true for debugging
    
    if DEBUG_MODE, fprintf('  [DEBUG] Starting generateTrialsPlot for %s\n', groupKey); end
    
    try
        cfg = GluSnFRConfig();
        utils = plot_utils();
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        timeData_ms = organizedData.Frame;
        stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
        
        if DEBUG_MODE, fprintf('  [DEBUG] Data size: %dx%d, ROIs: %d\n', size(organizedData), length(roiInfo.roiNumbers)); end
        
        if isempty(roiInfo.roiNumbers)
            if DEBUG_MODE, fprintf('  [DEBUG] FAIL: No ROI numbers found\n'); end
            return;
        end
        
        % PRE-CALCULATE: All subplot requirements upfront
        maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
        numROIs = length(roiInfo.roiNumbers);
        numFigures = ceil(numROIs / maxPlotsPerFigure);
        
        % PRE-CALCULATE: Layout for each figure
        figureLayouts = cell(numFigures, 1);
        for figNum = 1:numFigures
            startIdx = (figNum - 1) * maxPlotsPerFigure + 1;
            endIdx = min(figNum * maxPlotsPerFigure, numROIs);
            numPlotsThisFig = endIdx - startIdx + 1;
            [nRows, nCols] = utils.calculateOptimalLayout(numPlotsThisFig);
            
            figureLayouts{figNum} = struct(...
                'startIdx', startIdx, ...
                'endIdx', endIdx, ...
                'numPlots', numPlotsThisFig, ...
                'nRows', nRows, ...
                'nCols', nCols);
        end
        
        if DEBUG_MODE, fprintf('  [DEBUG] Pre-calculated %d figures with layouts\n', numFigures); end
        
        % Get color scheme and unique trials (calculated once)
        trialColors = utils.createColorScheme(10, 'trials');
        uniqueTrials = unique(roiInfo.originalTrialNumbers);
        uniqueTrials = uniqueTrials(isfinite(uniqueTrials));
        uniqueTrials = sort(uniqueTrials);
        
        if DEBUG_MODE, fprintf('  [DEBUG] Found %d unique trials: %s\n', length(uniqueTrials), mat2str(uniqueTrials)); end
        
        if isempty(uniqueTrials)
            if DEBUG_MODE, fprintf('  [DEBUG] FAIL: No valid trials found\n'); end
            return;
        end
        
        % OPTIMIZED: Process all figures with pre-calculated layouts
        for figNum = 1:numFigures
            layout = figureLayouts{figNum};
            
            if DEBUG_MODE, fprintf('  [DEBUG] Creating figure %d/%d\n', figNum, numFigures); end
            
            % CONSISTENT: Use standard figure for all plots
            fig = utils.createStandardFigure('standard');
            
            if DEBUG_MODE, fprintf('  [DEBUG] Layout: %dx%d for %d plots\n', layout.nRows, layout.nCols, layout.numPlots); end
            
            hasData = false;
            plotsWithData = 0;
            
            % OPTIMIZED: Process subplots with pre-calculated indices
            for roiArrayIdx = layout.startIdx:layout.endIdx
                subplotIdx = roiArrayIdx - layout.startIdx + 1;
                originalROI = roiInfo.roiNumbers(roiArrayIdx);
                
                subplot(layout.nRows, layout.nCols, subplotIdx);
                hold on;
                
                % Plot trials for this ROI
                trialCount = 0;
                
                for i = 1:length(uniqueTrials)
                    trialNum = uniqueTrials(i);
                    colName = sprintf('ROI%d_T%g', originalROI, trialNum);
                    
                    if ismember(colName, organizedData.Properties.VariableNames)
                        trialData = organizedData.(colName);
                        if ~all(isnan(trialData))
                            trialCount = trialCount + 1;
                            hasData = true;
                            
                            colorIdx = mod(i-1, size(trialColors, 1)) + 1;
                            
                            % Standard plotting
                            h_line = plot(timeData_ms, trialData, 'Color', trialColors(colorIdx, :), 'LineWidth', 1.0);
                            h_line.Color(4) = cfg.plotting.TRANSPARENCY;
                            
                            % Add threshold line
                            trialIdx = find(roiInfo.originalTrialNumbers == trialNum, 1);
                            if ~isempty(trialIdx) && roiArrayIdx <= size(roiInfo.thresholds, 1) && ...
                               trialIdx <= size(roiInfo.thresholds, 2) && ...
                               isfinite(roiInfo.thresholds(roiArrayIdx, trialIdx))
                                
                                threshold = roiInfo.thresholds(roiArrayIdx, trialIdx);
                                plot([timeData_ms(1), timeData_ms(100)], [threshold, threshold], ...
                                     ':', 'Color', trialColors(colorIdx, :), 'LineWidth', 1.5);
                            end
                        end
                    end
                end
                
                if trialCount > 0
                    plotsWithData = plotsWithData + 1;
                end
                
                % CONSISTENT: Use standardized stimulus marker (green line)
                ylim(cfg.plotting.Y_LIMITS);
                plot([stimulusTime_ms, stimulusTime_ms], cfg.plotting.Y_LIMITS, '-', 'Color', cfg.colors.STIMULUS, 'LineWidth', 1.0);
                
                title(sprintf('ROI %d (n=%d)', originalROI, trialCount), 'FontSize', 10, 'FontWeight', 'bold');
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                
                hold off;
            end
            
            if DEBUG_MODE, fprintf('  [DEBUG] Figure %d: %d/%d plots have data\n', figNum, plotsWithData, layout.numPlots); end
            
            % Save if we have data
            if hasData
                if numFigures > 1
                    titleText = sprintf('%s - Individual Trials (Part %d/%d)', cleanGroupKey, figNum, numFigures);
                    plotFile = sprintf('%s_trials_part%d.png', cleanGroupKey, figNum);
                else
                    titleText = sprintf('%s - Individual Trials', cleanGroupKey);
                    plotFile = sprintf('%s_trials.png', cleanGroupKey);
                end
                
                sgtitle(titleText, 'FontSize', 12, 'Interpreter', 'none', 'FontWeight', 'bold');
                
                fullPlotPath = fullfile(outputFolder, plotFile);
                if DEBUG_MODE, fprintf('  [DEBUG] Saving to: %s\n', fullPlotPath); end
                
                if ~exist(outputFolder, 'dir')
                    if DEBUG_MODE, fprintf('  [DEBUG] Creating output folder: %s\n', outputFolder); end
                    mkdir(outputFolder);
                end
                
                try
                    print(fig, fullPlotPath, '-dpng', sprintf('-r%d', cfg.plotting.DPI));
                    if DEBUG_MODE, fprintf('  [DEBUG] Saved using standard print\n'); end
                    
                    if exist(fullPlotPath, 'file')
                        if DEBUG_MODE, fprintf('  [DEBUG] File confirmed: %s\n', plotFile); end
                        success = true;
                    else
                        if DEBUG_MODE, fprintf('  [DEBUG] ERROR: File not found after saving: %s\n', plotFile); end
                    end
                    
                catch saveError
                    if DEBUG_MODE, fprintf('  [DEBUG] Save error: %s\n', saveError.message); end
                end
            else
                if DEBUG_MODE, fprintf('  [DEBUG] Figure %d skipped - no data\n', figNum); end
            end
            
            close(fig);
        end
        
        if DEBUG_MODE, fprintf('  [DEBUG] generateTrialsPlot complete. Success: %s\n', mat2str(success)); end
        
    catch ME
        if DEBUG_MODE, fprintf('  [DEBUG] EXCEPTION in generateTrialsPlot: %s\n', ME.message); end
        success = false;
    end
end

function success = generateAveragedPlot(averagedData, roiInfo, groupKey, outputFolder)
    % OPTIMIZED: Generate averaged ROI plots with consistent styling
    
    success = false;
    
    try
        cfg = GluSnFRConfig();
        utils = plot_utils();
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        timeData_ms = averagedData.Frame;
        stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
        
        if width(averagedData) <= 1
            return;
        end
        
        avgVarNames = averagedData.Properties.VariableNames(2:end);
        numAvgPlots = length(avgVarNames);
        maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
        numFigures = ceil(numAvgPlots / maxPlotsPerFigure);
        
        % PRE-CALCULATE: All figure layouts
        figureLayouts = cell(numFigures, 1);
        for figNum = 1:numFigures
            startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
            endPlot = min(figNum * maxPlotsPerFigure, numAvgPlots);
            numPlotsThisFig = endPlot - startPlot + 1;
            [nRows, nCols] = utils.calculateOptimalLayout(numPlotsThisFig);
            
            figureLayouts{figNum} = struct(...
                'startPlot', startPlot, ...
                'endPlot', endPlot, ...
                'numPlots', numPlotsThisFig, ...
                'nRows', nRows, ...
                'nCols', nCols);
        end
        
        for figNum = 1:numFigures
            layout = figureLayouts{figNum};
            
            % CONSISTENT: Use standard figure type
            fig = utils.createStandardFigure('standard');
            
            legendHandles = [];
            legendLabels = {};
            hasData = false;
            
            for plotIdx = layout.startPlot:layout.endPlot
                subplotIdx = plotIdx - layout.startPlot + 1;
                
                subplot(layout.nRows, layout.nCols, subplotIdx);
                hold on;
                
                varName = avgVarNames{plotIdx};
                avgData = averagedData.(varName);
                
                if ~all(isnan(avgData))
                    hasData = true;
                    
                    % Plot average trace
                    h_line = plot(timeData_ms, avgData, 'k-', 'LineWidth', 2.0);
                    
                    if subplotIdx == 1
                        legendHandles(end+1) = h_line;
                        legendLabels{end+1} = 'Average';
                    end
                    
                    % Add threshold
                    avgThreshold = calculateAverageThreshold(avgData, cfg);
                    
                    % CONSISTENT: Use standardized elements with line stimulus
                    utils.addStandardElements(timeData_ms, stimulusTime_ms, avgThreshold, cfg, 'StimulusStyle', 'line');
                    
                    if subplotIdx == 1 && isfinite(avgThreshold)
                        legendHandles(end+1) = plot(NaN, NaN, 'g--', 'LineWidth', 1.5);
                        legendLabels{end+1} = 'Threshold';
                        legendHandles(end+1) = plot(NaN, NaN, '-', 'Color', cfg.colors.STIMULUS);
                        legendLabels{end+1} = 'Stimulus';
                    end
                end
                
                % Parse title
                roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    originalROI = str2double(roiMatch{1}{1});
                    title(sprintf('ROI %d (n=%s)', originalROI, roiMatch{1}{2}), 'FontSize', 10, 'FontWeight', 'bold');
                else
                    title(varName, 'FontSize', 10);
                end
                
                hold off;
            end
            
            % Save if we have data
            if hasData
                if ~isempty(legendHandles)
                    legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 8);
                end
                
                if numFigures > 1
                    titleText = sprintf('%s - Averaged Traces (Part %d/%d)', cleanGroupKey, figNum, numFigures);
                    plotFile = sprintf('%s_averaged_part%d.png', cleanGroupKey, figNum);
                else
                    titleText = sprintf('%s - Averaged Traces', cleanGroupKey);
                    plotFile = sprintf('%s_averaged.png', cleanGroupKey);
                end
                
                sgtitle(titleText, 'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'none');
                utils.savePlotWithFormat(fig, fullfile(outputFolder, plotFile), cfg);
                success = true;
            end
            
            close(fig);
        end
        
    catch
        success = false;
    end
end

function success = generateCoverslipPlot(totalAveragedData, roiInfo, groupKey, outputFolder)
    % OPTIMIZED: Generate coverslip average plots with consistent styling
    
    success = false;
    
    try
        cfg = GluSnFRConfig();
        utils = plot_utils();
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        
        if width(totalAveragedData) <= 1
            return;
        end
        
        timeData_ms = totalAveragedData.Frame;
        stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
        varNames = totalAveragedData.Properties.VariableNames(2:end);
        
        % CONSISTENT: Use standard figure type
        fig = utils.createStandardFigure('standard');
        hold on;
        
        legendHandles = [];
        legendLabels = {};
        hasData = false;
        
        % Get noise level colors
        colors = utils.createColorScheme(3, 'noise_level');
        
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
                
                % Determine color and style
                if contains(varName, 'Low_Noise')
                    color = colors(1, :);  % Green
                    displayName = 'Low Noise';
                elseif contains(varName, 'High_Noise')
                    color = colors(2, :);  % Red
                    displayName = 'High Noise';
                elseif contains(varName, 'All_')
                    color = [0.2, 0.2, 0.8];  % Blue
                    displayName = 'All ROIs';
                else
                    color = [0.4, 0.4, 0.4];  % Gray
                    displayName = varName;
                end
                
                % Extract n count
                nMatch = regexp(varName, 'n(\d+)', 'tokens');
                if ~isempty(nMatch)
                    displayName = sprintf('%s (n=%s)', displayName, nMatch{1}{1});
                end
                
                h = plot(timeData_ms, data, 'Color', color, 'LineWidth', 2);
                legendHandles(end+1) = h;
                legendLabels{end+1} = displayName;
            end
        end
        
        % Save if we have data
        if hasData
            % CONSISTENT: Use line stimulus marker
            ylim(cfg.plotting.Y_LIMITS);
            plot([stimulusTime_ms, stimulusTime_ms], cfg.plotting.Y_LIMITS, '-', 'Color', cfg.colors.STIMULUS, 'LineWidth', 1.0);
            
            % Add stimulus to legend
            hStim = plot(NaN, NaN, '-', 'Color', cfg.colors.STIMULUS, 'LineWidth', 1.0);
            legendHandles(end+1) = hStim;
            legendLabels{end+1} = 'Stimulus';
            
            % Formatting
            xlabel('Time (ms)', 'FontSize', 10);
            ylabel('ΔF/F', 'FontSize', 10);
            grid on; box on;
            
            title(sprintf('%s - Coverslip Averages by Noise Level', cleanGroupKey), ...
                  'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
            
            legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 10);
            hold off;
            
            plotFile = sprintf('%s_coverslip_averages.png', cleanGroupKey);
            utils.savePlotWithFormat(fig, fullfile(outputFolder, plotFile), cfg);
            success = true;
        end
        
        close(fig);
        
    catch
        success = false;
    end
end

function avgThreshold = calculateAverageThreshold(avgData, cfg)
    % Calculate threshold for averaged data
    
    baselineWindow = cfg.timing.BASELINE_FRAMES;
    
    if length(avgData) >= max(baselineWindow)
        baselineData = avgData(baselineWindow);
        avgThreshold = cfg.thresholds.SD_MULTIPLIER * std(baselineData, 'omitnan');
    else
        avgThreshold = NaN;
    end
    
    if ~isfinite(avgThreshold)
        avgThreshold = cfg.thresholds.DEFAULT_THRESHOLD;
    end
end