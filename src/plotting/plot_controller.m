function controller = plot_controller()
    % PLOT_CONTROLLER - Central plotting orchestration
    % Consolidates plot_generator.m and plot_parallel_coordinator.m
    
    controller.generateGroupPlots = @generateGroupPlots;
    controller.shouldUseParallel = @shouldUseParallel;
    controller.createPlotTasks = @createPlotTasks;
end

function generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Main plotting dispatcher - replaces plot_generator.generateGroupPlots
    
    config = GluSnFRConfig();
    roiCache = createROICache(roiInfo);
    
    % Quick validation - exit early if no data
    if ~hasValidPlotData(organizedData, roiInfo, config)
        return;
    end
    
    % Set up plotting environment
    setupPlotEnvironment();
    
    % Create plot tasks based on experiment type and configuration
    tasks = createPlotTasks(organizedData, averagedData, roiInfo, roiCache, groupKey, outputFolders, config);

    if isempty(tasks)
        return;
    end
    
    % Decide parallel vs sequential
    if shouldUseParallel(tasks, config)
        plotsGenerated = executePlotTasksParallel(tasks);
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Generated %d plots (parallel)\n', plotsGenerated);
        end
    else
        plotsGenerated = executePlotTasksSequential(tasks);
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Generated %d plots (sequential)\n', plotsGenerated);
        end
    end
    
    % Cleanup
    cleanupPlotEnvironment();
end

function roiCache = createROICache(roiInfo)
    % CREATEROICACHE - Pre-process ROI data for efficient lookups
    % 
    % Call this ONCE at the beginning of plot generation, then pass
    % the cache to all plotting functions instead of repeatedly extracting
    % ROI numbers from strings.
    %
    % This function should be called in plot_controller.m before 
    % executing plot tasks (around line 50-60)
    %
    % INPUT:
    %   roiInfo - ROI information structure from data organization
    %
    % OUTPUT:
    %   roiCache - Cached ROI data for fast lookups
    
    roiCache = struct();
    
    % Create config and utils once
    cfg = GluSnFRConfig();
    utils = string_utils(cfg);
    
    % Pre-extract all ROI numbers if we have names to process
    if isfield(roiInfo, 'roiNames') && ~isempty(roiInfo.roiNames)
        roiCache.numbers = utils.extractROINumbers(roiInfo.roiNames);
        
        % Create a map for O(1) lookups: ROI name -> index
        roiCache.nameToIndex = containers.Map();
        for i = 1:length(roiInfo.roiNames)
            roiCache.nameToIndex(roiInfo.roiNames{i}) = i;
        end
        
        % Create a map for O(1) lookups: ROI number -> index  
        roiCache.numberToIndex = containers.Map('KeyType', 'int32', 'ValueType', 'int32');
        for i = 1:length(roiCache.numbers)
            roiCache.numberToIndex(roiCache.numbers(i)) = i;
        end
    else
        % For other experiment types, build cache from available data
        roiCache.numbers = [];
        roiCache.nameToIndex = containers.Map();
        roiCache.numberToIndex = containers.Map('KeyType', 'int32', 'ValueType', 'int32');
    end
    
    % Cache filtering statistics if available
    if isfield(roiInfo, 'filteringStats') && roiInfo.filteringStats.available
        roiCache.hasFilteringStats = true;
        roiCache.noiseMap = roiInfo.filteringStats.roiNoiseMap;
        roiCache.upperThresholds = roiInfo.filteringStats.roiUpperThresholds;
        roiCache.lowerThresholds = roiInfo.filteringStats.roiLowerThresholds;
        roiCache.basicThresholds = roiInfo.filteringStats.roiBasicThresholds;
    else
        roiCache.hasFilteringStats = false;
    end
    
    % Cache experiment type
    roiCache.experimentType = roiInfo.experimentType;
end



function tasks = createPlotTasks(organizedData, averagedData, roiInfo, roiCache, groupKey, outputFolders, config)    % Create plotting tasks based on experiment type and configuration
    
    tasks = {};
    
    if strcmp(roiInfo.experimentType, 'PPF')
        tasks = createPPFTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache);
    else
        tasks = create1APTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache);
    end
end

function tasks = create1APTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache)
    % Create 1AP plotting tasks
    
    tasks = {};
    
    % Individual trials
    if config.plotting.ENABLE_INDIVIDUAL_TRIALS && istable(organizedData) && width(organizedData) > 1
        tasks{end+1} = struct('type', 'trials', 'experimentType', '1AP', ...
                             'data', organizedData, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                             'groupKey', groupKey, 'outputFolder', outputFolders.roi_trials);
    end
    
    % ROI averages
    if config.plotting.ENABLE_ROI_AVERAGES && isfield(averagedData, 'roi') && width(averagedData.roi) > 1
        tasks{end+1} = struct('type', 'averages', 'experimentType', '1AP', ...
                             'data', averagedData.roi, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                             'groupKey', groupKey, 'outputFolder', outputFolders.roi_averages);
    end
    
    % Coverslip averages
    if config.plotting.ENABLE_COVERSLIP_AVERAGES && isfield(averagedData, 'total') && width(averagedData.total) > 1
        tasks{end+1} = struct('type', 'coverslip', 'experimentType', '1AP', ...
                             'data', averagedData.total, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                             'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages);
    end
end

function tasks = createPPFTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache)
    % Create PPF plotting tasks
    
    tasks = {};
    
    % Individual plots
    if config.plotting.ENABLE_PPF_INDIVIDUAL && hasValidPPFData(organizedData)
        tasks{end+1} = struct('type', 'individual', 'experimentType', 'PPF', ...
                             'data', getPrimaryPPFData(organizedData), 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                             'groupKey', groupKey, 'outputFolder', outputFolders.roi_trials);
    end
    
    % Averaged plots
    if config.plotting.ENABLE_PPF_AVERAGED && isstruct(averagedData)
        if isfield(averagedData, 'allData') && width(averagedData.allData) > 1
            tasks{end+1} = struct('type', 'averaged', 'experimentType', 'PPF', ...
                                 'data', averagedData.allData, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages, ...
                                 'plotSubtype', 'AllData');
        end
        
        if isfield(averagedData, 'bothPeaks') && width(averagedData.bothPeaks) > 1
            tasks{end+1} = struct('type', 'averaged', 'experimentType', 'PPF', ...
                                 'data', averagedData.bothPeaks, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages, ...
                                 'plotSubtype', 'BothPeaks');
        end
        
        if isfield(averagedData, 'singlePeak') && width(averagedData.singlePeak) > 1
            tasks{end+1} = struct('type', 'averaged', 'experimentType', 'PPF', ...
                                 'data', averagedData.singlePeak, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages, ...
                                 'plotSubtype', 'SinglePeak');
        end
    end
end

function useParallel = shouldUseParallel(tasks, config)
    % Decide whether to use parallel processing
    
    useParallel = false;
    
    if ~config.plotting.ENABLE_PARALLEL
        return;
    end
    
    if length(tasks) < config.plotting.PARALLEL_THRESHOLD
        return;
    end
    
    pool = gcp('nocreate');
    if isempty(pool) || pool.NumWorkers < 2
        return;
    end
    
    useParallel = true;
end

function plotsGenerated = executePlotTasksParallel(tasks)
    % Execute plot tasks in parallel
    
    pool = gcp('nocreate');
    if isempty(pool)
        plotsGenerated = executePlotTasksSequential(tasks);
        return;
    end
    
    try
        futures = cell(length(tasks), 1);
        for i = 1:length(tasks)
            futures{i} = parfeval(pool, @executeSinglePlotTask, 1, tasks{i});
        end
        
        plotsGenerated = 0;
        for i = 1:length(futures)
            try
                success = fetchOutputs(futures{i});
                if success
                    plotsGenerated = plotsGenerated + 1;
                end
            catch ME
                if config.debug.ENABLE_PLOT_DEBUG
                    fprintf('    Task %d failed (parallel): %s\n', i, ME.message);
                end
            end
        end
        
    catch
        % Fallback to sequential
        plotsGenerated = executePlotTasksSequential(tasks);
    end
end

function plotsGenerated = executePlotTasksSequential(tasks)
    % Execute plot tasks sequentially
    
    plotsGenerated = 0;
    
    for i = 1:length(tasks)
        try
            success = executeSinglePlotTask(tasks{i});
            if success
                plotsGenerated = plotsGenerated + 1;
            end
        catch ME
            % Continue with other plots even if one fails
            if GluSnFRConfig().debug.ENABLE_PLOT_DEBUG
                fprintf('    Plot task %d failed: %s\n', i, ME.message);
            end
        end
    end
end

function success = executeSinglePlotTask(task)
    % Execute a single plotting task
    
    success = false;
    config = GluSnFRConfig();
    
    try
        if strcmp(task.experimentType, '1AP')
            plot1AP = plot_1ap();
            success = plot1AP.execute(task, config);
        elseif strcmp(task.experimentType, 'PPF')
            plotPPF = plot_ppf();
            success = plotPPF.execute(task, config);
        end
    catch
        success = false;
    end
end

% Helper functions (unchanged from original files)
function hasData = hasValidPlotData(organizedData, roiInfo, config)
    if strcmp(roiInfo.experimentType, 'PPF')
        hasData = isstruct(organizedData) && ...
                  ((isfield(organizedData, 'allData') && width(organizedData.allData) > 1) || ...
                   (isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1) || ...
                   (isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1));
    else
        hasData = istable(organizedData) && width(organizedData) > 1;
    end
end

function hasData = hasValidPPFData(organizedData)
    hasData = isstruct(organizedData) && ...
              ((isfield(organizedData, 'allData') && width(organizedData.allData) > 1) || ...
               (isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1) || ...
               (isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1));
end

function plotData = getPrimaryPPFData(organizedData)
    plotData = [];
    if isfield(organizedData, 'allData') && width(organizedData.allData) > 1
        plotData = organizedData.allData;
    elseif isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1
        plotData = organizedData.bothPeaks;
    elseif isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1
        plotData = organizedData.singlePeak;
    end
end

function setupPlotEnvironment()
    % Set up optimal plotting environment
    set(groot, 'DefaultFigureVisible', 'off');
    set(groot, 'DefaultFigureRenderer', 'painters');
    set(groot, 'DefaultFigureColor', 'white');
end

function cleanupPlotEnvironment()
    % Clean up after plotting
    close all;
    drawnow;
    set(groot, 'DefaultFigureVisible', 'on');
end