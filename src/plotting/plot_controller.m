function controller = plot_controller()
    % PLOT_CONTROLLER - Enhanced plotting orchestration with modular architecture
    % 
    % KEY IMPROVEMENTS:
    % - Uses dedicated ROI cache module for cache management
    % - Delegates to specialized plot generators
    % - Eliminates all legacy threshold calculations
    % - Centralized configuration and styling
    
    controller.generateGroupPlots = @generateGroupPlots;
    controller.shouldUseParallel = @shouldUseParallel;
    controller.createPlotTasks = @createPlotTasks;
    controller.validateROICache = @validateROICache;
end

function generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Main plotting dispatcher with FIXED ROI cache optimization
    
    config = GluSnFRConfig();
    
    % Quick validation - exit early if no data
    if ~hasValidPlotData(organizedData, roiInfo, config)
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    No valid plot data for group %s\n', groupKey);
        end
        return;
    end
    
    % FIXED: Use dedicated ROI cache module
    cache_manager = roi_cache();
    roiCache = cache_manager.create(roiInfo, organizedData, roiInfo.experimentType);
    
    if ~cache_manager.validate(roiCache)
        % DETAILED ERROR REPORTING for invalid cache
        fprintf('    ❌ ROI cache validation FAILED for group %s\n', groupKey);
        
        if isfield(roiCache, 'errorMessage') && ~isempty(roiCache.errorMessage)
            fprintf('       Error: %s\n', roiCache.errorMessage);
        end
        
        % Detailed diagnostics
        if isstruct(roiCache)
            fprintf('       Cache diagnostics:\n');
            fprintf('         - Valid flag: %s\n', string(roiCache.valid));
            fprintf('         - Experiment type: %s\n', roiCache.experimentType);
            fprintf('         - Has filtering stats: %s\n', string(roiCache.hasFilteringStats));
            
            if isfield(roiCache, 'numbers')
                fprintf('         - ROI count: %d\n', length(roiCache.numbers));
                if ~isempty(roiCache.numbers)
                    fprintf('         - ROI range: %d - %d\n', min(roiCache.numbers), max(roiCache.numbers));
                end
            else
                fprintf('         - ROI numbers: MISSING\n');
            end
            
            if roiCache.hasFilteringStats
                fprintf('       Filtering statistics status:\n');
                if isfield(roiCache, 'noiseMap') && isa(roiCache.noiseMap, 'containers.Map')
                    fprintf('         - Noise classifications: %d ROIs\n', length(roiCache.noiseMap));
                else
                    fprintf('         - Noise classifications: INVALID/MISSING\n');
                end
                
                if isfield(roiCache, 'upperThresholds') && isa(roiCache.upperThresholds, 'containers.Map')
                    fprintf('         - Upper thresholds: %d ROIs\n', length(roiCache.upperThresholds));
                else
                    fprintf('         - Upper thresholds: INVALID/MISSING\n');
                end
                
                if isfield(roiCache, 'standardDeviations') && isa(roiCache.standardDeviations, 'containers.Map')
                    fprintf('         - Standard deviations: %d ROIs\n', length(roiCache.standardDeviations));
                else
                    fprintf('         - Standard deviations: INVALID/MISSING\n');
                end
            end
        else
            fprintf('       Cache is not a valid structure\n');
        end
        
        fprintf('       → Skipping plot generation for this group\n\n');
        return;
    end
    
    % Set up plotting environment
    setupPlotEnvironment();
    
    try
        % Create plot tasks with validated cache
        tasks = createPlotTasks(organizedData, averagedData, roiInfo, roiCache, groupKey, outputFolders, config);
        
        if isempty(tasks)
            if config.debug.ENABLE_PLOT_DEBUG
                fprintf('    No plot tasks created for group %s\n', groupKey);
            end
            return;
        end
        
        % Execute plotting with enhanced error handling
        plotsGenerated = executePlotTasks(tasks, config);
        
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Generated %d plots for group %s\n', plotsGenerated, groupKey);
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Plot generation error for group %s: %s\n', groupKey, ME.message);
        end
    finally
        cleanupPlotEnvironment();
    end
end

function tasks = createPlotTasks(organizedData, averagedData, roiInfo, roiCache, groupKey, outputFolders, config)
    % Create plotting tasks with enhanced validation
    
    tasks = {};
    
    if strcmp(roiInfo.experimentType, 'PPF')
        tasks = createPPFTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache);
    else
        tasks = create1APTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache);
    end
    
    % Validate all tasks have valid cache
    tasks = validateTasksWithCache(tasks, config);
end

function tasks = create1APTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache)
    % Create 1AP plotting tasks with enhanced validation and cache integration
    
    tasks = {};
    
    % Individual trials - ENHANCED validation
    if config.plotting.ENABLE_INDIVIDUAL_TRIALS && istable(organizedData) && width(organizedData) > 1
        % Verify we have ROIs in the cache that match the data
        cache_manager = roi_cache();
        cacheROIs = cache_manager.getROINumbers(roiCache);
        
        if ~isempty(cacheROIs)
            tasks{end+1} = struct('type', 'trials', 'experimentType', '1AP', ...
                                 'data', organizedData, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.roi_trials, ...
                                 'expectedROIs', length(cacheROIs));
        elseif config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Skipping trials plot: no ROIs in cache\n');
        end
    end
    
    % ROI averages - ENHANCED validation
    if config.plotting.ENABLE_ROI_AVERAGES
        if isfield(averagedData, 'roi') && istable(averagedData.roi) && width(averagedData.roi) > 1
            tasks{end+1} = struct('type', 'averages', 'experimentType', '1AP', ...
                                 'data', averagedData.roi, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.roi_averages);
        elseif config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Skipping ROI averages: %s\n', diagnoseAveragedData(averagedData, 'roi'));
        end
    end
    
    % Coverslip averages - ENHANCED validation
    if config.plotting.ENABLE_COVERSLIP_AVERAGES
        if isfield(averagedData, 'total') && istable(averagedData.total) && width(averagedData.total) > 1
            tasks{end+1} = struct('type', 'coverslip', 'experimentType', '1AP', ...
                                 'data', averagedData.total, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages);
        elseif config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Skipping coverslip averages: %s\n', diagnoseAveragedData(averagedData, 'total'));
        end
    end
end

function tasks = createPPFTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache)
    % Create PPF plotting tasks (enhanced but similar structure)
    
    tasks = {};
    
    % Individual plots
    if config.plotting.ENABLE_PPF_INDIVIDUAL && hasValidPPFData(organizedData)
        tasks{end+1} = struct('type', 'individual', 'experimentType', 'PPF', ...
                             'data', getPrimaryPPFData(organizedData), 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                             'groupKey', groupKey, 'outputFolder', outputFolders.roi_trials);
    end
    
    % Averaged plots
    if config.plotting.ENABLE_PPF_AVERAGED && isstruct(averagedData)
        ppfSubtypes = {'allData', 'bothPeaks', 'singlePeak'};
        ppfSheetNames = {'AllData', 'BothPeaks', 'SinglePeak'};
        
        for i = 1:length(ppfSubtypes)
            subtype = ppfSubtypes{i};
            if isfield(averagedData, subtype) && width(averagedData.(subtype)) > 1
                tasks{end+1} = struct('type', 'averaged', 'experimentType', 'PPF', ...
                                     'data', averagedData.(subtype), 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                                     'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages, ...
                                     'plotSubtype', ppfSheetNames{i});
            end
        end
    end
end

function validTasks = validateTasksWithCache(tasks, config)
    % Validate that all tasks have proper cache data
    
    validTasks = {};
    
    for i = 1:length(tasks)
        task = tasks{i};
        
        % Validate cache exists and is valid
        if isfield(task, 'roiCache') && ~isempty(task.roiCache) && task.roiCache.valid
            % For 1AP trials, verify we have matching ROIs
            if strcmp(task.experimentType, '1AP') && strcmp(task.type, 'trials')
                if isfield(task, 'expectedROIs') && task.expectedROIs > 0
                    validTasks{end+1} = task;
                elseif config.debug.ENABLE_PLOT_DEBUG
                    fprintf('    Task %d: No ROIs expected, skipping\n', i);
                end
            else
                validTasks{end+1} = task;
            end
        elseif config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Task %d: Invalid cache, skipping (%s)\n', i, task.type);
        end
    end
    
    if config.debug.ENABLE_PLOT_DEBUG
        fprintf('    Validated %d/%d tasks\n', length(validTasks), length(tasks));
    end
end

function plotsGenerated = executePlotTasks(tasks, config)
    % Enhanced task execution with better error handling
    
    if shouldUseParallel(tasks, config)
        plotsGenerated = executePlotTasksParallel(tasks, config);
    else
        plotsGenerated = executePlotTasksSequential(tasks, config);
    end
end

function plotsGenerated = executePlotTasksParallel(tasks, config)
    % Parallel execution with enhanced error handling
    
    pool = gcp('nocreate');
    if isempty(pool)
        plotsGenerated = executePlotTasksSequential(tasks, config);
        return;
    end
    
    try
        futures = cell(length(tasks), 1);
        for i = 1:length(tasks)
            futures{i} = parfeval(pool, @executeSinglePlotTaskSafe, 1, tasks{i}, config);
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
                    fprintf('    Parallel task %d failed: %s\n', i, ME.message);
                end
            end
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Parallel execution failed, falling back to sequential: %s\n', ME.message);
        end
        plotsGenerated = executePlotTasksSequential(tasks, config);
    end
end

function plotsGenerated = executePlotTasksSequential(tasks, config)
    % Sequential execution with enhanced error handling
    
    plotsGenerated = 0;
    
    for i = 1:length(tasks)
        try
            success = executeSinglePlotTaskSafe(tasks{i}, config);
            if success
                plotsGenerated = plotsGenerated + 1;
            end
        catch ME
            if config.debug.ENABLE_PLOT_DEBUG
                fprintf('    Sequential task %d failed: %s\n', i, ME.message);
            end
        end
    end
end

function success = executeSinglePlotTaskSafe(task, config)
    % Safe wrapper for single plot task execution
    
    success = false;
    
    try
        % Validate task before execution
        if ~isfield(task, 'experimentType') || ~isfield(task, 'type') || ~isfield(task, 'roiCache')
            if config.debug.ENABLE_PLOT_DEBUG
                fprintf('    Invalid task structure\n');
            end
            return;
        end
        
        % Execute based on experiment type
        if strcmp(task.experimentType, '1AP')
            plot1AP = plot_1ap();
            success = plot1AP.execute(task, config);
        elseif strcmp(task.experimentType, 'PPF')
            plotPPF = plot_ppf();
            success = plotPPF.execute(task, config);
        else
            if config.debug.ENABLE_PLOT_DEBUG
                fprintf('    Unknown experiment type: %s\n', task.experimentType);
            end
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Plot task execution failed: %s\n', ME.message);
            if ~isempty(ME.stack)
                fprintf('    Stack: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
            end
        end
        success = false;
    end
end

function isValid = validateROICache(roiCache, roiInfo)
    % DELEGATES to ROI cache module for validation
    
    cache_manager = roi_cache();
    isValid = cache_manager.validate(roiCache);
end

function diagMsg = diagnoseAveragedData(averagedData, fieldName)
    % Diagnostic helper for averaged data issues
    
    if ~isfield(averagedData, fieldName)
        diagMsg = sprintf('%s field missing', fieldName);
    elseif ~istable(averagedData.(fieldName))
        diagMsg = sprintf('%s not a table', fieldName);
    elseif width(averagedData.(fieldName)) <= 1
        diagMsg = sprintf('%s has %d columns (need >1)', fieldName, width(averagedData.(fieldName)));
    else
        diagMsg = 'unknown issue';
    end
end

% ========================================================================
% HELPER FUNCTIONS (mostly unchanged)
% ========================================================================

function useParallel = shouldUseParallel(tasks, config)
    % Determine if parallel execution is beneficial
    
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

function hasData = hasValidPlotData(organizedData, roiInfo, config)
    % Quick validation of plot data availability
    
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
    % Check for valid PPF data
    
    hasData = isstruct(organizedData) && ...
              ((isfield(organizedData, 'allData') && width(organizedData.allData) > 1) || ...
               (isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1) || ...
               (isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1));
end

function plotData = getPrimaryPPFData(organizedData)
    % Get primary PPF data table
    
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
    % Setup plotting environment
    
    set(groot, 'DefaultFigureVisible', 'off');
    set(groot, 'DefaultFigureRenderer', 'painters');
    set(groot, 'DefaultFigureColor', 'white');
end

function cleanupPlotEnvironment()
    % Cleanup plotting environment
    
    close all;
    drawnow;
    set(groot, 'DefaultFigureVisible', 'on');
end