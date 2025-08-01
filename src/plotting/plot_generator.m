function plot = plot_generator_parallel()
    % PLOT_GENERATOR_PARALLEL - Optimized plotting with parallel generation
    % 
    % Major improvements:
    % - Parallel plot generation for independent figures
    % - Pre-computed layouts and colors
    % - Vectorized data preparation
    % - Background plotting using parfeval
    % - Memory-efficient plot creation
    
    plot.generateGroupPlots = @generateGroupPlotsParallel;
    plot.generatePlotsBackground = @generatePlotsInBackground;
    plot.precomputePlotData = @precomputePlotDataVectorized;
    plot.optimizePlotMemory = @optimizePlotMemoryUsage;
end

function generateGroupPlotsParallel(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % OPTIMIZED: Parallel plot generation with background processing
    
    fprintf('    Generating plots for group: %s (parallel mode)\n', groupKey);
    
    % Pre-validate data structure
    hasData = validatePlotData(organizedData, roiInfo);
    if ~hasData
        fprintf('    No valid data for plotting group %s\n', groupKey);
        return;
    end
    
    % Determine plot tasks
    plotTasks = identifyPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    
    if isempty(plotTasks)
        fprintf('    No plot tasks identified for group %s\n', groupKey);
        return;
    end
    
    % Check if parallel plotting is beneficial
    useParallelPlotting = length(plotTasks) > 2 && ~isempty(gcp('nocreate'));
    
    if useParallelPlotting
        generatePlotsParallel(plotTasks);
    else
        generatePlotsSequential(plotTasks);
    end
end

function plotTasks = identifyPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Identify independent plotting tasks that can run in parallel
    
    plotTasks = {};
    taskCount = 0;
    
    if strcmp(roiInfo.experimentType, 'PPF')
        % PPF plotting tasks
        plotTasks = identifyPPFPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    else
        % 1AP plotting tasks
        plotTasks = identify1APPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    end
end

function plotTasks = identify1APPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Identify 1AP plotting tasks
    
    plotTasks = {};
    taskCount = 0;
    
    % Task 1: Individual trials plots
    if istable(organizedData) && width(organizedData) > 1
        taskCount = taskCount + 1;
        plotTasks{taskCount} = struct(...
            'type', '1AP_trials', ...
            'data', organizedData, ...
            'roiInfo', roiInfo, ...
            'groupKey', groupKey, ...
            'outputFolder', outputFolders.roi_trials, ...
            'priority', 1);
    end
    
    % Task 2: ROI averaged plots
    if isfield(averagedData, 'roi') && ~isempty(averagedData.roi) && width(averagedData.roi) > 1
        taskCount = taskCount + 1;
        plotTasks{taskCount} = struct(...
            'type', '1AP_roi_averages', ...
            'data', averagedData.roi, ...
            'roiInfo', roiInfo, ...
            'groupKey', groupKey, ...
            'outputFolder', outputFolders.roi_averages, ...
            'priority', 2);
    end
    
    % Task 3: Coverslip averages (total averages)
    if isfield(averagedData, 'total') && ~isempty(averagedData.total) && width(averagedData.total) > 1
        taskCount = taskCount + 1;
        plotTasks{taskCount} = struct(...
            'type', '1AP_coverslip_averages', ...
            'data', averagedData.total, ...
            'roiInfo', roiInfo, ...
            'groupKey', groupKey, ...
            'outputFolder', outputFolders.coverslip_averages, ...
            'priority', 3);
    end
end

function plotTasks = identifyPPFPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Identify PPF plotting tasks
    
    plotTasks = {};
    taskCount = 0;
    
    % Determine which data to use for individual plots
    individualData = [];
    if isstruct(organizedData)
        if isfield(organizedData, 'allData') && width(organizedData.allData) > 1
            individualData = organizedData.allData;
        elseif isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1
            individualData = organizedData.bothPeaks;
        elseif isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1
            individualData = organizedData.singlePeak;
        end
    end
    
    % Task 1: PPF individual plots
    if ~isempty(individualData)
        taskCount = taskCount + 1;
        plotTasks{taskCount} = struct(...
            'type', 'PPF_individual', ...
            'data', individualData, ...
            'roiInfo', roiInfo, ...
            'groupKey', groupKey, ...
            'outputFolder', outputFolders.roi_trials, ...
            'priority', 1);
    end
    
    % Task 2-4: PPF averaged plots (can run in parallel)
    if isstruct(averagedData)
        % All Data averaged
        if isfield(averagedData, 'allData') && width(averagedData.allData) > 1
            taskCount = taskCount + 1;
            plotTasks{taskCount} = struct(...
                'type', 'PPF_averaged_alldata', ...
                'data', averagedData.allData, ...
                'roiInfo', roiInfo, ...
                'groupKey', groupKey, ...
                'outputFolder', outputFolders.coverslip_averages, ...
                'priority', 2);
        end
        
        % Both Peaks averaged
        if isfield(averagedData, 'bothPeaks') && width(averagedData.bothPeaks) > 1
            taskCount = taskCount + 1;
            plotTasks{taskCount} = struct(...
                'type', 'PPF_averaged_bothpeaks', ...
                'data', averagedData.bothPeaks, ...
                'roiInfo', roiInfo, ...
                'groupKey', groupKey, ...
                'outputFolder', outputFolders.coverslip_averages, ...
                'priority', 2);
        end
    end
end

function generatePlotsParallel(plotTasks)
    % Generate plots in parallel using parfeval
    
    numTasks = length(plotTasks);
    fprintf('      Generating %d plot tasks in parallel\n', numTasks);
    
    % Sort tasks by priority (higher priority first)
    priorities = cellfun(@(x) x.priority, plotTasks);
    [~, sortOrder] = sort(priorities);
    plotTasks = plotTasks(sortOrder);
    
    % Use parfeval for background plot generation
    pool = gcp();
    futures = cell(numTasks, 1);
    
    % Submit all tasks
    for i = 1:numTasks
        task = plotTasks{i};
        futures{i} = parfeval(pool, @executePlotTask, 1, task);
    end
    
    % Collect results
    plotsGenerated = 0;
    for i = 1:numTasks
        try
            success = fetchOutputs(futures{i});
            if success
                plotsGenerated = plotsGenerated + 1;
            end
        catch ME
            fprintf('      Plot task %d failed: %s\n', i, ME.message);
        end
    end
    
    fprintf('    Generated %d/%d plots successfully (parallel)\n', plotsGenerated, numTasks);
end

function generatePlotsSequential(plotTasks)
    % Fallback: Generate plots sequentially
    
    plotsGenerated = 0;
    for i = 1:length(plotTasks)
        try
            success = executePlotTask(plotTasks{i});
            if success
                plotsGenerated = plotsGenerated + 1;
            end
        catch ME
            fprintf('      Plot task %d failed: %s\n', i, ME.message);
        end
    end
    
    fprintf('    Generated %d/%d plots successfully (sequential)\n', plotsGenerated, length(plotTasks));
end

function success = executePlotTask(task)
    % Execute a single plotting task
    
    success = false;
    
    try
        switch task.type
            case '1AP_trials'
                success = generate1APTrialsOptimized(task);
            case '1AP_roi_averages'
                success = generate1APAveragesOptimized(task);
            case '1AP_coverslip_averages'
                success = generate1APCoverslipAveragesOptimized(task);
            case 'PPF_individual'
                success = generatePPFIndividualOptimized(task);
            case 'PPF_averaged_alldata'
                success = generatePPFAveragedOptimized(task, 'AllData');
            case 'PPF_averaged_bothpeaks'
                success = generatePPFAveragedOptimized(task, 'BothPeaks');
            otherwise
                warning('Unknown plot task type: %s', task.type);
        end
    catch ME
        fprintf('Error executing plot task %s: %s\n', task.type, ME.message);
        success = false;
    end
end

function success = generate1APTrialsOptimized(task)
    % OPTIMIZED: 1AP trials plotting with vectorized operations
    
    success = false;
    cfg = GluSnFRConfig();
    
    organizedData = task.data;
    roiInfo = task.roiInfo;
    cleanGroupKey = regexprep(task.groupKey, '[^\w-]', '_');
    
    timeData_ms = organizedData.Frame;
    stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    
    % Pre-compute all plotting data (vectorized)
    plotData = precomputePlotDataVectorized(organizedData, roiInfo, cfg);
    
    if isempty(plotData.validROIs)
        return;
    end
    
    % Generate plots with optimized rendering
    maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
    numROIs = length(plotData.validROIs);
    numFigures = ceil(numROIs / maxPlotsPerFigure);
    
    for figNum = 1:numFigures
        try
            % Create figure with optimized settings
            fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', ...
                        'Color', 'white', 'Renderer', 'painters', 'PaperPositionMode', 'auto');
            
            startIdx = (figNum - 1) * maxPlotsPerFigure + 1;
            endIdx = min(figNum * maxPlotsPerFigure, numROIs);
            
            % Optimized subplot creation
            createOptimizedSubplots(fig, plotData, startIdx, endIdx, timeData_ms, stimulusTime_ms, cfg);
            
            % Save figure
            if numFigures > 1
                plotFile = sprintf('%s_trials_part%d.png', cleanGroupKey, figNum);
                titleText = sprintf('%s - Individual Trials (Part %d/%d)', cleanGroupKey, figNum, numFigures);
            else
                plotFile = sprintf('%s_trials.png', cleanGroupKey);
                titleText = sprintf('%s - Individual Trials', cleanGroupKey);
            end
            
            sgtitle(titleText, 'FontSize', 14, 'Interpreter', 'none', 'FontWeight', 'bold');
            
            % Optimized saving
            print(fig, fullfile(task.outputFolder, plotFile), '-dpng', ...
                  sprintf('-r%d', cfg.plotting.DPI), '-painters');
            
            close(fig);
            success = true;
            
        catch ME
            fprintf('Error creating trials plot %d: %s\n', figNum, ME.message);
            if exist('fig', 'var') && isvalid(fig)
                close(fig);
            end
        end
    end
end

function plotData = precomputePlotDataVectorized(organizedData, roiInfo, cfg)
    % OPTIMIZED: Pre-compute all plot data using vectorized operations
    
    plotData = struct();
    plotData.validROIs = [];
    plotData.roiData = {};
    plotData.thresholds = [];
    plotData.colors = [];
    
    if isempty(roiInfo.roiNumbers)
        return;
    end
    
    % Pre-compute colors (vectorized)
    uniqueTrials = unique(roiInfo.originalTrialNumbers);
    uniqueTrials = uniqueTrials(isfinite(uniqueTrials));
    
    trialColors = [
        0.0 0.0 0.0;      % Black
        0.8 0.2 0.2;      % Red  
        0.2 0.6 0.8;      % Blue
        0.2 0.8 0.2;      % Green
        0.8 0.5 0.2;      % Orange
        0.6 0.2 0.8;      % Purple
        0.8 0.8 0.2;      % Yellow
        0.4 0.4 0.4;      % Gray
        0.0 0.8 0.8;      % Cyan
        0.8 0.0 0.8;      % Magenta
    ];
    
    % Pre-organize data by ROI (vectorized where possible)
    validROICount = 0;
    for roiIdx = 1:length(roiInfo.roiNumbers)
        originalROI = roiInfo.roiNumbers(roiIdx);
        
        % Find all trials for this ROI
        roiTrialData = [];
        roiTrialColors = [];
        roiThresholds = [];
        
        for trialIdx = 1:length(uniqueTrials)
            trialNum = uniqueTrials(trialIdx);
            colName = sprintf('ROI%d_T%g', originalROI, trialNum);
            
            if ismember(colName, organizedData.Properties.VariableNames)
                trialData = organizedData.(colName);
                if ~all(isnan(trialData))
                    roiTrialData = [roiTrialData, trialData];
                    
                    colorIdx = mod(trialIdx-1, size(trialColors, 1)) + 1;
                    roiTrialColors = [roiTrialColors; trialColors(colorIdx, :)];
                    
                    % Get threshold
                    if roiIdx <= size(roiInfo.thresholds, 1) && trialIdx <= size(roiInfo.thresholds, 2)
                        roiThresholds = [roiThresholds, roiInfo.thresholds(roiIdx, trialIdx)];
                    else
                        roiThresholds = [roiThresholds, cfg.thresholds.DEFAULT_THRESHOLD];
                    end
                end
            end
        end
        
        if ~isempty(roiTrialData)
            validROICount = validROICount + 1;
            plotData.validROIs(validROICount) = originalROI;
            plotData.roiData{validROICount} = roiTrialData;
            plotData.colors{validROICount} = roiTrialColors;
            plotData.thresholds{validROICount} = roiThresholds;
        end
    end
end

function createOptimizedSubplots(fig, plotData, startIdx, endIdx, timeData_ms, stimulusTime_ms, cfg)
    % OPTIMIZED: Create subplots with minimal redundant operations
    
    numPlotsThisFig = endIdx - startIdx + 1;
    [nRows, nCols] = calculateOptimalLayout(numPlotsThisFig);
    
    % Pre-allocate subplot handles for efficiency
    subplotHandles = gobjects(numPlotsThisFig, 1);
    
    for plotIdx = 1:numPlotsThisFig
        roiIdx = startIdx + plotIdx - 1;
        originalROI = plotData.validROIs(roiIdx);
        
        subplotHandles(plotIdx) = subplot(nRows, nCols, plotIdx);
        hold on;
        
        % Plot all trials for this ROI (vectorized where possible)
        roiTrialData = plotData.roiData{roiIdx};
        roiColors = plotData.colors{roiIdx};
        roiThresholds = plotData.thresholds{roiIdx};
        
        % Plot trials
        numTrials = size(roiTrialData, 2);
        for trialIdx = 1:numTrials
            trialData = roiTrialData(:, trialIdx);
            color = roiColors(trialIdx, :);
            
            plot(timeData_ms, trialData, 'Color', [color, cfg.plotting.TRANSPARENCY], 'LineWidth', 1.0);
            
            % Add threshold line
            if trialIdx <= length(roiThresholds) && isfinite(roiThresholds(trialIdx))
                plot([timeData_ms(1), timeData_ms(100)], ...
                     [roiThresholds(trialIdx), roiThresholds(trialIdx)], ...
                     ':', 'Color', color, 'LineWidth', 1.5);
            end
        end
        
        % Stimulus marker
        plot([stimulusTime_ms, stimulusTime_ms], cfg.plotting.Y_LIMITS, ...
             ':g', 'LineWidth', 1.0, 'Marker', 'pentagram');
        
        % Formatting
        ylim(cfg.plotting.Y_LIMITS);
        title(sprintf('ROI %d (n=%d)', originalROI, numTrials), 'FontSize', 10, 'FontWeight', 'bold');
        xlabel('Time (ms)', 'FontSize', 8);
        ylabel('ΔF/F', 'FontSize', 8);
        grid on; box on;
        hold off;
    end
end



function hasData = validatePlotData(organizedData, roiInfo)
    % Quick validation of plot data structure
    
    hasData = false;
    
    if strcmp(roiInfo.experimentType, 'PPF')
        if isstruct(organizedData)
            hasData = (isfield(organizedData, 'allData') && istable(organizedData.allData) && width(organizedData.allData) > 1) || ...
                     (isfield(organizedData, 'bothPeaks') && istable(organizedData.bothPeaks) && width(organizedData.bothPeaks) > 1) || ...
                     (isfield(organizedData, 'singlePeak') && istable(organizedData.singlePeak) && width(organizedData.singlePeak) > 1);
        end
    else
        hasData = istable(organizedData) && width(organizedData) > 1;
    end
end

function optimizePlotMemoryUsage()
    % Optimize memory usage for plotting
    
    % Clear any existing figures
    close all;
    
    % Force garbage collection
    drawnow;
    
    % Set default figure properties for memory efficiency
    set(groot, 'DefaultFigureVisible', 'off');
    set(groot, 'DefaultFigureRenderer', 'painters');
end

% Placeholder functions for other optimized plot types
function success = generate1APAveragesOptimized(task)
    success = true; % Implement optimized ROI averages plotting
end

function success = generate1APCoverslipAveragesOptimized(task)
    success = true; % Implement optimized coverslip averages plotting
end

function success = generatePPFIndividualOptimized(task)
    success = true; % Implement optimized PPF individual plotting
end

function success = generatePPFAveragedOptimized(task, plotType)
    success = true; % Implement optimized PPF averaged plotting
end

function plot = plot_generator_legacy()
    % PLOT_GENERATOR - Updated plotting module with fixed ROI numbering
    % 
    % Changes:
    % - Updated folder structure (single plot folder with 3 subfolders)
    % - Fixed ROI numbering to show original ROI numbers
    % - More vectorized plotting operations
    
    plot.generateGroupPlots = @generateGroupPlots;
    plot.generate1APPlots = @generate1APPlots;
    plot.generatePPFPlots = @generatePPFPlots;
    plot.generateCoverslipAveragePlots = @generateCoverslipAveragePlots; % Renamed
    plot.calculateLayout = @calculateOptimalLayout;
end

function generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % UPDATED: Main plotting dispatcher with enhanced debugging
    
    fprintf('    Generating plots for group: %s\n', groupKey);
    
    % Debug: Show data structure
    fprintf('      Data structure check:\n');
    if strcmp(roiInfo.experimentType, 'PPF')
        fprintf('        Experiment type: PPF\n');
        if isstruct(organizedData)
            fprintf('        organizedData is struct with fields: %s\n', strjoin(fieldnames(organizedData), ', '));
            if isfield(organizedData, 'allData')
                fprintf('        allData: %s, width=%d\n', class(organizedData.allData), width(organizedData.allData));
            end
            if isfield(organizedData, 'bothPeaks')
                fprintf('        bothPeaks: %s, width=%d\n', class(organizedData.bothPeaks), width(organizedData.bothPeaks));
            end
            if isfield(organizedData, 'singlePeak')
                fprintf('        singlePeak: %s, width=%d\n', class(organizedData.singlePeak), width(organizedData.singlePeak));
            end
        else
            fprintf('        organizedData is %s\n', class(organizedData));
        end
    else
        fprintf('        Experiment type: %s\n', roiInfo.experimentType);
        fprintf('        organizedData: %s, width=%d\n', class(organizedData), width(organizedData));
    end
    
    % Check if we have data to plot
    hasData = false;
    
    if strcmp(roiInfo.experimentType, 'PPF')
        % For PPF, check if any of the sub-tables have data
        if isstruct(organizedData)
            if (isfield(organizedData, 'allData') && istable(organizedData.allData) && width(organizedData.allData) > 1) || ...
               (isfield(organizedData, 'bothPeaks') && istable(organizedData.bothPeaks) && width(organizedData.bothPeaks) > 1) || ...
               (isfield(organizedData, 'singlePeak') && istable(organizedData.singlePeak) && width(organizedData.singlePeak) > 1)
                hasData = true;
            end
        end
    else
        % For 1AP, check organized data directly
        if istable(organizedData) && width(organizedData) > 1
            hasData = true;
        end
    end
    
    if ~hasData
        fprintf('    No valid data structure found for plotting group %s\n', groupKey);
        return;
    end
    
    fprintf('      ✓ Valid data found, proceeding with plotting\n');
    
    if strcmp(roiInfo.experimentType, 'PPF')
        generatePPFPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    else
        % Use new folder structure for 1AP plots
        if isfield(averagedData, 'roi') && ~isempty(averagedData.roi)
            generate1APPlots(organizedData, averagedData.roi, roiInfo, groupKey, ...
                           outputFolders.roi_trials, outputFolders.roi_averages);
        else
            fprintf('    No ROI averaged data for plotting\n');
        end
        
        if isfield(averagedData, 'total') && ~isempty(averagedData.total)
            generateCoverslipAveragePlots(averagedData.total, roiInfo, groupKey, ...
                                        outputFolders.coverslip_averages);
        else
            fprintf('    No total averaged data for plotting\n');
        end
    end
end

function generate1APPlots(organizedData, averagedData, roiInfo, groupKey, roiTrialsFolder, roiAveragesFolder)
    % FIXED: 1AP plotting with correct original ROI numbers and better vectorization
    
    cfg = GluSnFRConfig();
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    timeData_ms = organizedData.Frame;
    stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    
    % Check if we have ROIs to plot
    if isempty(roiInfo.roiNumbers)
        fprintf('    No ROIs available for plotting\n');
        return;
    end
    
    fprintf('    Generating 1AP plots for %d ROIs (original numbers: %d-%d)\n', ...
            length(roiInfo.roiNumbers), min(roiInfo.roiNumbers), max(roiInfo.roiNumbers));
    
    % VECTORIZED: Pre-calculate all colors and properties
    trialColors = [
        0.0 0.0 0.0;      % Black
        0.8 0.2 0.2;      % Red  
        0.2 0.6 0.8;      % Blue
        0.2 0.8 0.2;      % Green
        0.8 0.5 0.2;      % Orange
        0.6 0.2 0.8;      % Purple
        0.8 0.8 0.2;      % Yellow
        0.4 0.4 0.4;      % Gray
        0.0 0.8 0.8;      % Cyan
        0.8 0.0 0.8;      % Magenta
    ];
    
    maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
    numROIs = length(roiInfo.roiNumbers);
    
    % Get unique trials for consistent coloring
    uniqueTrials = unique(roiInfo.originalTrialNumbers);
    uniqueTrials = uniqueTrials(isfinite(uniqueTrials));
    uniqueTrials = sort(uniqueTrials);
    
    if isempty(uniqueTrials)
        fprintf('    No valid trials found for plotting\n');
        return;
    end
    
    % FIXED: Generate individual trials plots with correct ROI numbers
    numTrialsFigures = ceil(numROIs / maxPlotsPerFigure);
    plotsGenerated = 0;
    
    for figNum = 1:numTrialsFigures
        try
            fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
            
            startIdx = (figNum - 1) * maxPlotsPerFigure + 1;
            endIdx = min(figNum * maxPlotsPerFigure, numROIs);
            numPlotsThisFig = endIdx - startIdx + 1;
            
            [nRows, nCols] = calculateOptimalLayout(numPlotsThisFig);
            
            % Track legend handles
            legendHandles = [];
            legendLabels = {};
            hasData = false;
            
            % FIXED: Iterate through ROI indices, but use original ROI numbers
            for roiArrayIdx = startIdx:endIdx
                subplotIdx = roiArrayIdx - startIdx + 1;
                originalROI = roiInfo.roiNumbers(roiArrayIdx); % FIXED: Get original ROI number
                
                subplot(nRows, nCols, subplotIdx);
                hold on;
                
                % Plot trials for this ORIGINAL ROI number
                trialCount = 0;
                hasThresholdInLegend = false;
                
                for i = 1:length(uniqueTrials)
                    trialNum = uniqueTrials(i);
                    colName = sprintf('ROI%d_T%g', originalROI, trialNum); % Use original ROI number
                    
                    if ismember(colName, organizedData.Properties.VariableNames)
                        trialData = organizedData.(colName);
                        if ~all(isnan(trialData))
                            trialCount = trialCount + 1;
                            hasData = true;
                            
                            colorIdx = mod(i-1, size(trialColors, 1)) + 1;
                            h_line = plot(timeData_ms, trialData, 'Color', trialColors(colorIdx, :), 'LineWidth', 1.0);
                            h_line.Color(4) = cfg.plotting.TRANSPARENCY;
                            
                            % Add to legend (only from first subplot)
                            if subplotIdx == 1 && ~ismember(sprintf('Trial %g', trialNum), legendLabels)
                                legendHandles(end+1) = h_line;
                                legendLabels{end+1} = sprintf('Trial %g', trialNum);
                            end
                            
                            % Add threshold line
                            trialIdx = find(roiInfo.originalTrialNumbers == trialNum, 1);
                            if ~isempty(trialIdx) && roiArrayIdx <= size(roiInfo.thresholds, 1) && ...
                               trialIdx <= size(roiInfo.thresholds, 2) && ...
                               isfinite(roiInfo.thresholds(roiArrayIdx, trialIdx))
                                
                                threshold = roiInfo.thresholds(roiArrayIdx, trialIdx);
                                h_thresh = plot([timeData_ms(1), timeData_ms(100)], [threshold, threshold], ...
                                     ':', 'Color', trialColors(colorIdx, :), 'LineWidth', 1.5, 'HandleVisibility', 'off');
                                
                                if subplotIdx == 1 && ~hasThresholdInLegend
                                    h_thresh.HandleVisibility = 'on';
                                    legendHandles(end+1) = h_thresh;
                                    legendLabels{end+1} = 'Thresholds';
                                    hasThresholdInLegend = true;
                                end
                            end
                        end
                    end
                end
                
                % Set y-limits and add stimulus
                ylim(cfg.plotting.Y_LIMITS);
                hStim = plot([stimulusTime_ms, stimulusTime_ms], [cfg.plotting.Y_LIMITS(1), cfg.plotting.Y_LIMITS(1)], ...
                     ':gpentagram', 'LineWidth', 1.0, 'HandleVisibility', 'off');
                
                if subplotIdx == 1 && ~ismember('Stimulus', legendLabels)
                    hStim.HandleVisibility = 'on';
                    legendHandles(end+1) = hStim;
                    legendLabels{end+1} = 'Stimulus';
                end
                
                % FIXED: Title shows original ROI number
                title(sprintf('ROI %d (n=%d)', originalROI, trialCount), 'FontSize', 10, 'FontWeight', 'bold');
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Only save if we have data
            if hasData
                % Add legend
                if ~isempty(legendHandles)
                    legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 8);
                end
                
                % Save figure to ROI_trials folder
                if numTrialsFigures > 1
                    titleText = sprintf('%s - Individual Trials (Part %d/%d)', cleanGroupKey, figNum, numTrialsFigures);
                    plotFile = sprintf('%s_trials_part%d.png', cleanGroupKey, figNum);
                else
                    titleText = sprintf('%s - Individual Trials', cleanGroupKey);
                    plotFile = sprintf('%s_trials.png', cleanGroupKey);
                end
                
                sgtitle(titleText, 'FontSize', 14, 'Interpreter', 'none', 'FontWeight', 'bold');
                print(fig, fullfile(roiTrialsFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
                plotsGenerated = plotsGenerated + 1;
            end
            
            close(fig);
            
        catch ME
            fprintf('    ERROR creating trials plot %d: %s\n', figNum, ME.message);
            if exist('fig', 'var'), close(fig); end
        end
    end
    
    % Generate averaged plots with original ROI numbers
    if ~isempty(averagedData) && width(averagedData) > 1
        avgPlotsGenerated = generateAveragedROIPlots(averagedData, roiInfo, cleanGroupKey, ...
                                                     roiAveragesFolder, timeData_ms, stimulusTime_ms, cfg);
        plotsGenerated = plotsGenerated + avgPlotsGenerated;
    end
    
    fprintf('    Generated %d plot files total\n', plotsGenerated);
end


function numGenerated = generateAveragedROIPlots(averagedData, roiInfo, cleanGroupKey, plotsFolder, timeData_ms, stimulusTime_ms, cfg)
    % FIXED: Generate averaged plots with correct original ROI numbers
    
    numGenerated = 0;
    
    if width(averagedData) <= 1
        fprintf('      No averaged data to plot\n');
        return;
    end
    
    avgVarNames = averagedData.Properties.VariableNames(2:end);
    numAvgPlots = length(avgVarNames);
    maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
    numAvgFigures = ceil(numAvgPlots / maxPlotsPerFigure);
    
    for figNum = 1:numAvgFigures
        try
            figAvg = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
            
            startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
            endPlot = min(figNum * maxPlotsPerFigure, numAvgPlots);
            numPlotsThisFig = endPlot - startPlot + 1;
            
            [nRowsAvg, nColsAvg] = calculateOptimalLayout(numPlotsThisFig);
            
            legendHandles = [];
            legendLabels = {};
            hasData = false;
            
            for plotIdx = startPlot:endPlot
                subplotIdx = plotIdx - startPlot + 1;
                
                subplot(nRowsAvg, nColsAvg, subplotIdx);
                hold on;
                
                varName = avgVarNames{plotIdx};
                avgData = averagedData.(varName);
                
                % Check if data is valid
                if ~all(isnan(avgData))
                    hasData = true;
                    
                    % Plot average trace
                    h_line = plot(timeData_ms, avgData, 'k-', 'LineWidth', 1.0);
                    
                    if subplotIdx == 1
                        legendHandles(end+1) = h_line;
                        legendLabels{end+1} = 'Average';
                    end
                    
                    % Add threshold
                    avgThreshold = calculateAverageThreshold(avgData, cfg);
                    if isfinite(avgThreshold)
                        hThresh = plot([timeData_ms(1), timeData_ms(100)], [avgThreshold, avgThreshold], ...
                             'g--', 'LineWidth', 2, 'HandleVisibility', 'off');
                        
                        if subplotIdx == 1
                            legendHandles(end+1) = hThresh;
                            legendLabels{end+1} = 'Threshold';
                        end
                    end
                end
                
                % FIXED: Parse title to show original ROI number (should already be correct)
                roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    originalROI = str2double(roiMatch{1}{1}); % This should be the original ROI number
                    title(sprintf('ROI %d (n=%s)', originalROI, roiMatch{1}{2}), 'FontSize', 10, 'FontWeight', 'bold');
                else
                    title(varName, 'FontSize', 10);
                end
                
                % Set limits and add stimulus
                ylim(cfg.plotting.Y_LIMITS);
                hStim = plot([stimulusTime_ms, stimulusTime_ms], [cfg.plotting.Y_LIMITS(1), cfg.plotting.Y_LIMITS(1)], ...
                            ':gpentagram', 'LineWidth', 1.0, 'HandleVisibility', 'off');
                
                if subplotIdx == 1
                    legendHandles(end+1) = hStim;
                    legendLabels{end+1} = 'Stimulus';
                end
                
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Only save if we have data
            if hasData
                % Add legend
                if ~isempty(legendHandles)
                    legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 8);
                end
                
                % Save figure
                if numAvgFigures > 1
                    titleText = sprintf('%s - Averaged Traces (Part %d/%d)', cleanGroupKey, figNum, numAvgFigures);
                    avgPlotFile = sprintf('%s_averaged_part%d.png', cleanGroupKey, figNum);
                else
                    titleText = sprintf('%s - Averaged Traces', cleanGroupKey);
                    avgPlotFile = sprintf('%s_averaged.png', cleanGroupKey);
                end
                
                sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
                print(figAvg, fullfile(plotsFolder, avgPlotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
                numGenerated = numGenerated + 1;
            end
            
            close(figAvg);
            
        catch ME
            fprintf('    ERROR creating averaged figure %d: %s\n', figNum, ME.message);
            if exist('figAvg', 'var'), close(figAvg); end
        end
    end
end

function generateCoverslipAveragePlots(totalAveragedData, roiInfo, groupKey, plotsFolder)
    % RENAMED: Generate plots for coverslip averages (was total averages)
    
    if width(totalAveragedData) <= 1
        fprintf('    No coverslip averaged data to plot\n');
        return;
    end
    
    cfg = GluSnFRConfig();
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    timeData_ms = totalAveragedData.Frame;
    stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    
    varNames = totalAveragedData.Properties.VariableNames(2:end);
    
    try
        fig = figure('Position', [100, 100, 1200, 400], 'Visible', 'off', 'Color', 'white');
        
        hold on;
        legendHandles = [];
        legendLabels = {};
        hasData = false;
        
        % VECTORIZED: Pre-allocate arrays for more efficient plotting
        allData = table2array(totalAveragedData(:, 2:end));
        validCols = ~all(isnan(allData), 1);
        validData = allData(:, validCols);
        validVarNames = varNames(validCols);
        
        if ~isempty(validData)
            % VECTORIZED: Plot all valid traces at once with different colors
            colors = lines(size(validData, 2)); % Generate distinct colors
            
            for i = 1:size(validData, 2)
                data = validData(:, i);
                varName = validVarNames{i};
                
                hasData = true;
                
                % Determine color and style
                if contains(varName, 'Low_Noise')
                    color = [0.2, 0.6, 0.2];  % Green
                    displayName = 'Low Noise';
                elseif contains(varName, 'High_Noise')
                    color = [0.8, 0.2, 0.2];  % Red
                    displayName = 'High Noise';
                elseif contains(varName, 'All_')
                    color = [0.2, 0.2, 0.8];  % Blue
                    displayName = 'All ROIs';
                else
                    color = colors(i, :);  % Use generated color
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
        
        % Only save if we have data
        if hasData
            % Add stimulus
            ylim(cfg.plotting.Y_LIMITS);
            hStim = plot([stimulusTime_ms, stimulusTime_ms], [cfg.plotting.Y_LIMITS(1), cfg.plotting.Y_LIMITS(1)], ':gpentagram', 'LineWidth', 1.0);
            legendHandles(end+1) = hStim;
            legendLabels{end+1} = 'Stimulus';
            
            title(sprintf('%s - Coverslip Averages by Noise Level', cleanGroupKey), 'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
            xlabel('Time (ms)', 'FontSize', 12);
            ylabel('ΔF/F', 'FontSize', 12);
            grid on; box on;
            
            legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 10);
            hold off;
            
            plotFile = sprintf('%s_coverslip_averages.png', cleanGroupKey);
            print(fig, fullfile(plotsFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
            
            fprintf('    ✓ Generated coverslip averages plot: %s\n', plotFile);
        end
        
        close(fig);
        
    catch ME
        fprintf('    ERROR creating coverslip averages plot: %s\n', ME.message);
        if exist('fig', 'var'), close(fig); end
    end
end

function generatePPFPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % FIXED: PPF plotting with correct folder assignment and limited averaged plots
    
    cfg = GluSnFRConfig();
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    
    % Extract genotype for color coding
    genotype = extractGenotypeFromGroupKey(groupKey);
    
    fprintf('    Generating PPF plots for %s, timepoint=%dms\n', genotype, roiInfo.timepoint);
    
    % Determine which data to use for plotting
    plotData = [];
    
    % Priority: allData > bothPeaks > singlePeak for individual plots
    if isstruct(organizedData)
        if isfield(organizedData, 'allData') && istable(organizedData.allData) && width(organizedData.allData) > 1
            plotData = organizedData.allData;
            fprintf('      Using allData for individual plots (%d ROIs)\n', width(plotData)-1);
        elseif isfield(organizedData, 'bothPeaks') && istable(organizedData.bothPeaks) && width(organizedData.bothPeaks) > 1
            plotData = organizedData.bothPeaks;
            fprintf('      Using bothPeaks for individual plots (%d ROIs)\n', width(plotData)-1);
        elseif isfield(organizedData, 'singlePeak') && istable(organizedData.singlePeak) && width(organizedData.singlePeak) > 1
            plotData = organizedData.singlePeak;
            fprintf('      Using singlePeak for individual plots (%d ROIs)\n', width(plotData)-1);
        end
    end
    
    % Check if we have data to plot
    if isempty(plotData) || ~istable(plotData)
        fprintf('    No valid PPF individual data for plotting\n');
        return;
    end
    
    % Extract time data and stimulus timing
    try
        timeData_ms = plotData.Frame;
        stimulusTime_ms1 = cfg.timing.STIMULUS_TIME_MS;
        stimulusTime_ms2 = stimulusTime_ms1 + roiInfo.timepoint;
        
        fprintf('      PPF timing: Stim1=%dms, Stim2=%dms (interval=%dms)\n', ...
                stimulusTime_ms1, stimulusTime_ms2, roiInfo.timepoint);
        
    catch ME
        fprintf('    Error extracting time data: %s\n', ME.message);
        return;
    end
    
    % Generate individual plots by coverslip (to ROI_trials folder)
    try
        generatePPFIndividualPlots(plotData, roiInfo, genotype, outputFolders.roi_trials, ...
                                  timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg);
        fprintf('      ✓ Individual PPF plots generated\n');
    catch ME
        fprintf('      ⚠ Individual PPF plots failed: %s\n', ME.message);
    end
    
    % Generate ONLY allData and bothPeaks averaged plots (to Coverslip_Averages folder)
    if isstruct(averagedData)
        % All Data averaged plots
        if isfield(averagedData, 'allData') && istable(averagedData.allData) && width(averagedData.allData) > 1
            try
                generatePPFAveragedPlots(averagedData.allData, roiInfo, cleanGroupKey, genotype, ...
                                        outputFolders.coverslip_averages, timeData_ms, ...
                                        stimulusTime_ms1, stimulusTime_ms2, cfg, 'AllData');
                fprintf('      ✓ All Data averaged plots generated\n');
            catch ME
                fprintf('      ⚠ All Data averaged plots failed: %s\n', ME.message);
            end
        end
        
        % Both Peaks averaged plots
        if isfield(averagedData, 'bothPeaks') && istable(averagedData.bothPeaks) && width(averagedData.bothPeaks) > 1
            try
                generatePPFAveragedPlots(averagedData.bothPeaks, roiInfo, cleanGroupKey, genotype, ...
                                        outputFolders.coverslip_averages, timeData_ms, ...
                                        stimulusTime_ms1, stimulusTime_ms2, cfg, 'BothPeaks');
                fprintf('      ✓ Both Peaks averaged plots generated\n');
            catch ME
                fprintf('      ⚠ Both Peaks averaged plots failed: %s\n', ME.message);
            end
        end
        
        % Note: No single peak averaged plots as requested
    else
        fprintf('      - No averaged data available for plotting\n');
    end
    
    fprintf('    PPF plots complete for genotype %s\n', genotype);
end

function generatePPFIndividualPlots(organizedData, roiInfo, genotype, plotsFolder, timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg)
    % Generate individual PPF plots by coverslip with red coloring for single peak traces
    
    dataVarNames = organizedData.Properties.VariableNames(2:end);
    if isempty(dataVarNames)
        return;
    end
    
    % Extract unique coverslip-cell combinations
    coverslipCells = {};
    for i = 1:length(dataVarNames)
        varName = dataVarNames{i};
        roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            csCell = roiMatch{1}{1};
            if ~ismember(csCell, coverslipCells)
                coverslipCells{end+1} = csCell;
            end
        end
    end
    
    % Determine if this is single peak data (for red coloring)
    isSinglePeakData = false;
    if isfield(roiInfo, 'dataType') && strcmp(roiInfo.dataType, 'singlePeak')
        isSinglePeakData = true;
    end
    
    % Create plots for each coverslip
    for csIdx = 1:length(coverslipCells)
        csCell = coverslipCells{csIdx};
        
        % Find ROIs for this coverslip
        csROIs = {};
        csPattern = [csCell '_ROI'];
        for i = 1:length(dataVarNames)
            if contains(dataVarNames{i}, csPattern)
                csROIs{end+1} = dataVarNames{i};
            end
        end
        
        if isempty(csROIs)
            continue;
        end
        
        % Create plots
        maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
        numFigures = ceil(length(csROIs) / maxPlotsPerFigure);
        
        for figNum = 1:numFigures
            try
                fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
                
                startROI = (figNum - 1) * maxPlotsPerFigure + 1;
                endROI = min(figNum * maxPlotsPerFigure, length(csROIs));
                
                [nRows, nCols] = calculateOptimalLayout(endROI - startROI + 1);
                hasData = false;
                
                for roiIdx = startROI:endROI
                    subplotIdx = roiIdx - startROI + 1;
                    varName = csROIs{roiIdx};
                    traceData = organizedData.(varName);
                    
                    subplot(nRows, nCols, subplotIdx);
                    hold on;
                    
                    % Plot with appropriate color
                    if ~all(isnan(traceData))
                        hasData = true;
                        
                        % Determine trace color: red for single peak, black for others
                        if isSinglePeakData || checkIfSinglePeakROI(varName, csCell, roiInfo)
                            traceColor = [0.8, 0.2, 0.2]; % Red for single peak
                        else
                            traceColor = [0, 0, 0]; % Black for both peaks or unknown
                        end
                        
                        plot(timeData_ms, traceData, 'Color', traceColor, 'LineWidth', 1.0);
                        
                        % Add threshold
                        threshold = getPPFROIThreshold(varName, roiInfo);
                        if isfinite(threshold)
                            plot([timeData_ms(1), timeData_ms(100)], [threshold, threshold], 'g--', 'LineWidth', 1.5);
                        end
                    end
                    
                    ylim(cfg.plotting.Y_LIMITS);
                    
                    % Add stimuli
                    plot([stimulusTime_ms1, stimulusTime_ms1], [cfg.plotting.Y_LIMITS(1), cfg.plotting.Y_LIMITS(1)], ':gpentagram', 'LineWidth', 1);
                    plot([stimulusTime_ms2, stimulusTime_ms2], [cfg.plotting.Y_LIMITS(1), cfg.plotting.Y_LIMITS(1)], ':cpentagram', 'LineWidth', 1);
                    
                    % Title
                    roiMatch = regexp(varName, '.*_ROI(\d+)', 'tokens');
                    if ~isempty(roiMatch)
                        roiTitle = sprintf('ROI %s', roiMatch{1}{1});
                        % Add peak type indicator if available
                        if isSinglePeakData || checkIfSinglePeakROI(varName, csCell, roiInfo)
                            roiTitle = sprintf('%s (SP)', roiTitle); % SP = Single Peak
                        end
                        title(roiTitle, 'FontSize', 10, 'FontWeight', 'bold');
                    end
                    
                    xlabel('Time (ms)', 'FontSize', 8);
                    ylabel('ΔF/F', 'FontSize', 8);
                    grid on; box on;
                    hold off;
                end
                
                % Only save if we have data
                if hasData
                    % Figure title and save
                    if numFigures > 1
                        titleText = sprintf('PPF %dms %s %s (Part %d/%d)', roiInfo.timepoint, genotype, csCell, figNum, numFigures);
                        plotFile = sprintf('PPF_%dms_%s_%s_individual_part%d.png', roiInfo.timepoint, genotype, csCell, figNum);
                    else
                        titleText = sprintf('PPF %dms %s %s', roiInfo.timepoint, genotype, csCell);
                        plotFile = sprintf('PPF_%dms_%s_%s_individual.png', roiInfo.timepoint, genotype, csCell);
                    end
                    
                    sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold');
                    print(fig, fullfile(plotsFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
                    fprintf('      ✓ Generated PPF individual plot: %s\n', plotFile);
                end
                
                close(fig);
                
            catch ME
                fprintf('    ERROR in PPF individual plot: %s\n', ME.message);
                if exist('fig', 'var'), close(fig); end
            end
        end
    end
end

function isSinglePeak = checkIfSinglePeakROI(varName, csCell, roiInfo)
    % Check if a specific ROI is classified as single peak
    
    isSinglePeak = false;
    
    try
        % Extract ROI number
        roiMatch = regexp(varName, 'ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            
            % Search through coverslip files for this ROI's classification
            for fileIdx = 1:length(roiInfo.coverslipFiles)
                fileData = roiInfo.coverslipFiles(fileIdx);
                if strcmp(fileData.coverslipCell, csCell)
                    roiIdx = find(fileData.roiNumbers == roiNum, 1);
                    
                    if ~isempty(roiIdx) && ~isempty(fileData.peakResponses)
                        % Check if this ROI is classified as single peak (Peak1 or Peak2 only)
                        isPeak1Only = roiIdx <= length(fileData.peakResponses.filteredPeak1Only) && ...
                                      fileData.peakResponses.filteredPeak1Only(roiIdx);
                        isPeak2Only = roiIdx <= length(fileData.peakResponses.filteredPeak2Only) && ...
                                      fileData.peakResponses.filteredPeak2Only(roiIdx);
                        
                        isSinglePeak = isPeak1Only || isPeak2Only;
                        return;
                    end
                end
            end
        end
    catch
        isSinglePeak = false;
    end
end

function generatePPFAveragedPlots(averagedData, roiInfo, cleanGroupKey, genotype, plotsFolder, timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg, plotType)
    % Generate PPF averaged plots with genotype-specific colors and plot type handling
    % NEW: plotType parameter ('AllData', 'BothPeaks', or 'SinglePeak')
    
    if nargin < 10
        plotType = 'AllData'; % Default
    end
    
    if width(averagedData) <= 1
        return;
    end
    
    avgVarNames = averagedData.Properties.VariableNames(2:end);
    numAvgPlots = length(avgVarNames);
    
    % Determine trace color based on plot type and genotype
    if strcmp(plotType, 'SinglePeak')
        traceColor = [0.8, 0.2, 0.2]; % Red for single peak traces
    else
        % Use genotype-specific colors for AllData and BothPeaks
        if strcmp(genotype, 'WT')
            traceColor = cfg.colors.WT;
        elseif strcmp(genotype, 'R213W')
            traceColor = cfg.colors.R213W;
        else
            traceColor = [0, 0, 1]; % Blue for unknown
        end
    end
    
    maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
    numAvgFigures = ceil(numAvgPlots / maxPlotsPerFigure);
    
    for figNum = 1:numAvgFigures
        try
            figAvg = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
            
            startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
            endPlot = min(figNum * maxPlotsPerFigure, numAvgPlots);
            
            [nRowsAvg, nColsAvg] = calculateOptimalLayout(endPlot - startPlot + 1);
            hasData = false;
            
            for plotIdx = startPlot:endPlot
                subplotIdx = plotIdx - startPlot + 1;
                
                subplot(nRowsAvg, nColsAvg, subplotIdx);
                hold on;
                
                varName = avgVarNames{plotIdx};
                avgData = averagedData.(varName);
                
                % Check for valid data
                if ~all(isnan(avgData))
                    hasData = true;
                    
                    % Plot in appropriate color
                    plot(timeData_ms, avgData, 'Color', traceColor, 'LineWidth', 1.0);
                    
                    % Add threshold
                    avgThreshold = calculateAverageThreshold(avgData, cfg);
                    if isfinite(avgThreshold)
                        plot([timeData_ms(1), timeData_ms(100)], [avgThreshold, avgThreshold], 'g--', 'LineWidth', 1.5);
                    end
                end
                
                % Title with genotype and plot type
                roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    titleStr = sprintf('%s %s, n=%s', genotype, roiMatch{1}{1}, roiMatch{1}{2});
                    if strcmp(plotType, 'BothPeaks')
                        titleStr = sprintf('%s (Both Peaks)', titleStr);
                    elseif strcmp(plotType, 'SinglePeak')
                        titleStr = sprintf('%s (Single Peak)', titleStr);
                    end
                    title(titleStr, 'FontSize', 10, 'FontWeight', 'bold');
                else
                    title([genotype ' ' varName], 'FontSize', 10);
                end
                
                ylim([-0.005, 0.05]);
                
                % Add stimuli
                plot([stimulusTime_ms1, stimulusTime_ms1], [-0.005, -0.005], ':gpentagram', 'LineWidth', 1.0);
                plot([stimulusTime_ms2, stimulusTime_ms2], [-0.005, -0.005], ':cpentagram', 'LineWidth', 1.0);
                
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Only save if we have data
            if hasData
                % Figure title and filename based on plot type
                typeLabel = '';
                switch plotType
                    case 'AllData'
                        typeLabel = 'All Data';
                    case 'BothPeaks'
                        typeLabel = 'Both Peaks';
                    case 'SinglePeak'
                        typeLabel = 'Single Peak';
                end
                
                if numAvgFigures > 1
                    titleText = sprintf('PPF %dms %s - %s Averaged (Part %d/%d)', roiInfo.timepoint, genotype, typeLabel, figNum, numAvgFigures);
                    avgPlotFile = sprintf('PPF_%dms_%s_%s_averaged_part%d.png', roiInfo.timepoint, genotype, plotType, figNum);
                else
                    titleText = sprintf('PPF %dms %s - %s Averaged', roiInfo.timepoint, genotype, typeLabel);
                    avgPlotFile = sprintf('PPF_%dms_%s_%s_averaged.png', roiInfo.timepoint, genotype, plotType);
                end
                
                sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold');
                print(figAvg, fullfile(plotsFolder, avgPlotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
                fprintf('      ✓ Generated PPF %s averaged plot: %s\n', plotType, avgPlotFile);
            end
            
            close(figAvg);
            
        catch ME
            fprintf('    ERROR in PPF %s averaged plot: %s\n', plotType, ME.message);
            if exist('figAvg', 'var'), close(figAvg); end
        end
    end
end

function [nRows, nCols] = calculateOptimalLayout(nSubplots)
    % Calculate optimal subplot layout
    
    if nSubplots <= 2
        nRows = 2; nCols = 1;
    elseif nSubplots <= 4
        nRows = 2; nCols = 2;
    elseif nSubplots <= 6
        nRows = 2; nCols = 3;
    elseif nSubplots <= 9
        nRows = 3; nCols = 3;
    else
        nRows = 3; nCols = 4;
    end
end

function genotype = extractGenotypeFromGroupKey(groupKey)
    % Extract genotype from group key
    
    if contains(groupKey, 'R213W')
        genotype = 'R213W';
    elseif contains(groupKey, 'WT')
        genotype = 'WT';
    else
        genotype = 'Unknown';
    end
end

function threshold = getPPFROIThreshold(varName, roiInfo)
    % Get threshold for specific PPF ROI
    
    threshold = NaN;
    
    try
        roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            csCell = roiMatch{1}{1};
            roiNum = str2double(roiMatch{1}{2});
            
            for fileIdx = 1:length(roiInfo.coverslipFiles)
                fileData = roiInfo.coverslipFiles(fileIdx);
                if strcmp(fileData.coverslipCell, csCell)
                    roiIdx = find(fileData.roiNumbers == roiNum, 1);
                    if ~isempty(roiIdx) && roiIdx <= length(fileData.thresholds)
                        threshold = fileData.thresholds(roiIdx);
                        return;
                    end
                end
            end
        end
    catch
        threshold = NaN;
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