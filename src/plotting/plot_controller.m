function controller = plot_controller()
    % PLOT_CONTROLLER - Central plotting orchestration (FIXED)
    % Eliminates redundant computations and ensures only filtered data is plotted
    
    controller.generateGroupPlots = @generateGroupPlots;
    controller.shouldUseParallel = @shouldUseParallel;
    controller.createPlotTasks = @createPlotTasks;
    controller.validateROICache = @validateROICache;  % NEW: Cache validation
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
    
    % FIXED: Create and validate ROI cache
    roiCache = createROICacheFixed(roiInfo, organizedData, averagedData);
    
    if ~validateROICache(roiCache, roiInfo)
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    ROI cache validation failed for group %s\n', groupKey);
        end
        return;
    end
    
    % Set up plotting environment
    setupPlotEnvironment();
    
    % Create plot tasks with validated cache
    tasks = createPlotTasks(organizedData, averagedData, roiInfo, roiCache, groupKey, outputFolders, config);
    
    if isempty(tasks)
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    No plot tasks created for group %s\n', groupKey);
        end
        cleanupPlotEnvironment();
        return;
    end
    
    % Execute plotting
    if shouldUseParallel(tasks, config)
        plotsGenerated = executePlotTasksParallel(tasks);
    else
        plotsGenerated = executePlotTasksSequential(tasks);
    end
    
    if config.debug.ENABLE_PLOT_DEBUG
        fprintf('    Generated %d plots for group %s\n', plotsGenerated, groupKey);
    end
    
    cleanupPlotEnvironment();
end

function roiCache = createROICacheFixed(roiInfo, organizedData, averagedData)
    % FIXED: Create ROI cache with proper filtering statistics and NO fallbacks
    
    roiCache = struct();
    roiCache.valid = false;
    roiCache.experimentType = roiInfo.experimentType;
    roiCache.hasFilteringStats = false;
    roiCache.numbers = [];
    
    try
        cfg = GluSnFRConfig();
        utils = string_utils(cfg);
        
        % FIXED: Handle different experiment types properly
        if strcmp(roiInfo.experimentType, '1AP')
            roiCache = create1APCacheFixed(roiInfo, organizedData, averagedData, utils, cfg);
        elseif strcmp(roiInfo.experimentType, 'PPF')
            roiCache = createPPFCacheFixed(roiInfo, organizedData, averagedData, utils, cfg);
        end
        
    catch ME
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    Cache creation failed: %s\n', ME.message);
        end
        roiCache.valid = false;
    end
end

function roiCache = create1APCacheFixed(roiInfo, organizedData, averagedData, utils, cfg)
    % FIXED: Create cache for 1AP experiments with complete filtering statistics
    
    roiCache = struct();
    roiCache.experimentType = '1AP';
    roiCache.valid = false;
    roiCache.hasFilteringStats = false;
    
    % Extract ROI numbers from organized data (these are the FILTERED ROIs only)
    if istable(organizedData) && width(organizedData) > 1
        varNames = organizedData.Properties.VariableNames(2:end); % Skip Frame column
        roiNumbers = [];
        
        for i = 1:length(varNames)
            roiMatch = regexp(varNames{i}, 'ROI(\d+)_T', 'tokens');
            if ~isempty(roiMatch)
                roiNumbers(end+1) = str2double(roiMatch{1}{1});
            end
        end
        
        if ~isempty(roiNumbers)
            uniqueROIs = unique(roiNumbers);
            roiCache.numbers = sort(uniqueROIs);
            
            % Create lookup maps
            roiCache.numberToIndex = containers.Map('KeyType', 'int32', 'ValueType', 'int32');
            for i = 1:length(roiCache.numbers)
                roiCache.numberToIndex(roiCache.numbers(i)) = i;
            end
            
            % CRITICAL: Extract filtering statistics from roiInfo (from pipeline processing)
            if isfield(roiInfo, 'filteringStats') && ...
               isstruct(roiInfo.filteringStats) && ...
               isfield(roiInfo.filteringStats, 'available') && ...
               roiInfo.filteringStats.available && ...
               strcmp(roiInfo.filteringStats.method, 'schmitt_trigger')
                
                % REQUIRED: All filtering statistics must be present and properly populated
                if isfield(roiInfo.filteringStats, 'roiNoiseMap') && ...
                   isa(roiInfo.filteringStats.roiNoiseMap, 'containers.Map') && ...
                   isfield(roiInfo.filteringStats, 'roiUpperThresholds') && ...
                   isa(roiInfo.filteringStats.roiUpperThresholds, 'containers.Map') && ...
                   isfield(roiInfo.filteringStats, 'roiLowerThresholds') && ...
                   isa(roiInfo.filteringStats.roiLowerThresholds, 'containers.Map') && ...
                   isfield(roiInfo.filteringStats, 'roiStandardDeviations') && ...
                   isa(roiInfo.filteringStats.roiStandardDeviations, 'containers.Map')
                    
                    % FIXED: Store the complete filtering statistics
                    roiCache.hasFilteringStats = true;
                    roiCache.noiseMap = roiInfo.filteringStats.roiNoiseMap;
                    roiCache.upperThresholds = roiInfo.filteringStats.roiUpperThresholds;
                    roiCache.lowerThresholds = roiInfo.filteringStats.roiLowerThresholds;
                    roiCache.standardDeviations = roiInfo.filteringStats.roiStandardDeviations;
                    
                    if cfg.debug.ENABLE_PLOT_DEBUG
                        fprintf('    Cache: Using Schmitt filtering statistics (%d ROIs with complete data)\n', ...
                                length(roiCache.noiseMap));
                    end
                else
                    if cfg.debug.ENABLE_PLOT_DEBUG
                        fprintf('    Cache: Incomplete Schmitt statistics - missing required maps\n');
                    end
                end
            else
                if cfg.debug.ENABLE_PLOT_DEBUG
                    fprintf('    Cache: No Schmitt filtering statistics available\n');
                    if isfield(roiInfo, 'filteringStats')
                        if isfield(roiInfo.filteringStats, 'method')
                            fprintf('           Filtering method used: %s\n', roiInfo.filteringStats.method);
                        end
                        fprintf('           Available: %s\n', ...
                                string(roiInfo.filteringStats.available));
                    end
                end
            end
            
            % REMOVED: No fallback calculations - if filtering stats aren't available, 
            % that means the pipeline didn't generate them properly
            
            roiCache.valid = true;
        end
    end
end

function roiCache = createPPFCacheFixed(roiInfo, organizedData, averagedData, utils, cfg)
    % FIXED: Create cache for PPF experiments with complete filtering statistics
    
    roiCache = struct();
    roiCache.experimentType = 'PPF';
    roiCache.valid = false;
    roiCache.hasFilteringStats = false;
    
    % Extract ROI numbers from PPF organized data
    if isstruct(organizedData)
        % Get primary data table
        if isfield(organizedData, 'allData') && istable(organizedData.allData) && width(organizedData.allData) > 1
            dataTable = organizedData.allData;
        elseif isfield(organizedData, 'bothPeaks') && istable(organizedData.bothPeaks) && width(organizedData.bothPeaks) > 1
            dataTable = organizedData.bothPeaks;
        elseif isfield(organizedData, 'singlePeak') && istable(organizedData.singlePeak) && width(organizedData.singlePeak) > 1
            dataTable = organizedData.singlePeak;
        else
            return; % No valid data
        end
        
        varNames = dataTable.Properties.VariableNames(2:end); % Skip Frame column
        roiNumbers = [];
        
        for i = 1:length(varNames)
            roiMatch = regexp(varNames{i}, 'ROI(\d+)', 'tokens');
            if ~isempty(roiMatch)
                roiNumbers(end+1) = str2double(roiMatch{1}{1});
            end
        end
        
        if ~isempty(roiNumbers)
            uniqueROIs = unique(roiNumbers);
            roiCache.numbers = sort(uniqueROIs);
            
            % Create lookup maps
            roiCache.numberToIndex = containers.Map('KeyType', 'int32', 'ValueType', 'int32');
            for i = 1:length(roiCache.numbers)
                roiCache.numberToIndex(roiCache.numbers(i)) = i;
            end
            
            % CRITICAL: Extract filtering statistics (same logic as 1AP)
            if isfield(roiInfo, 'filteringStats') && ...
               isstruct(roiInfo.filteringStats) && ...
               isfield(roiInfo.filteringStats, 'available') && ...
               roiInfo.filteringStats.available && ...
               strcmp(roiInfo.filteringStats.method, 'schmitt_trigger')
                
                % REQUIRED: All filtering statistics must be present
                if isfield(roiInfo.filteringStats, 'roiNoiseMap') && ...
                   isa(roiInfo.filteringStats.roiNoiseMap, 'containers.Map') && ...
                   isfield(roiInfo.filteringStats, 'roiUpperThresholds') && ...
                   isa(roiInfo.filteringStats.roiUpperThresholds, 'containers.Map') && ...
                   isfield(roiInfo.filteringStats, 'roiLowerThresholds') && ...
                   isa(roiInfo.filteringStats.roiLowerThresholds, 'containers.Map') && ...
                   isfield(roiInfo.filteringStats, 'roiStandardDeviations') && ...
                   isa(roiInfo.filteringStats.roiStandardDeviations, 'containers.Map')
                    
                    roiCache.hasFilteringStats = true;
                    roiCache.noiseMap = roiInfo.filteringStats.roiNoiseMap;
                    roiCache.upperThresholds = roiInfo.filteringStats.roiUpperThresholds;
                    roiCache.lowerThresholds = roiInfo.filteringStats.roiLowerThresholds;
                    roiCache.standardDeviations = roiInfo.filteringStats.roiStandardDeviations;
                    
                    if cfg.debug.ENABLE_PLOT_DEBUG
                        fprintf('    PPF Cache: Using Schmitt filtering statistics (%d ROIs)\n', ...
                                length(roiCache.noiseMap));
                    end
                end
            end
            
            % REMOVED: No fallback calculations for PPF either
            
            roiCache.valid = true;
        end
    end
end

function isValid = validateROICache(roiCache, roiInfo)
    % ENHANCED: Validate that ROI cache contains all required data for plotting
    
    isValid = false;
    
    try
        % Basic structure validation
        if ~isstruct(roiCache) || ~isfield(roiCache, 'valid') || ~roiCache.valid
            return;
        end
        
        % Check required fields
        requiredFields = {'numbers', 'numberToIndex', 'experimentType', 'hasFilteringStats'};
        for i = 1:length(requiredFields)
            if ~isfield(roiCache, requiredFields{i})
                fprintf('    Cache validation failed: missing field %s\n', requiredFields{i});
                return;
            end
        end
        
        % Check that we have ROI numbers
        if isempty(roiCache.numbers) || ~isnumeric(roiCache.numbers)
            fprintf('    Cache validation failed: no valid ROI numbers\n');
            return;
        end
        
        % Check that maps are properly sized
        if ~isa(roiCache.numberToIndex, 'containers.Map') || ...
           length(roiCache.numberToIndex) ~= length(roiCache.numbers)
            fprintf('    Cache validation failed: numberToIndex map size mismatch\n');
            return;
        end
        
        % CRITICAL: If filtering statistics are claimed to be available, validate them completely
        if roiCache.hasFilteringStats
            requiredMaps = {'noiseMap', 'upperThresholds', 'lowerThresholds', 'standardDeviations'};
            for i = 1:length(requiredMaps)
                mapName = requiredMaps{i};
                if ~isfield(roiCache, mapName)
                    fprintf('    Cache validation failed: missing %s\n', mapName);
                    return;
                elseif ~isa(roiCache.(mapName), 'containers.Map')
                    fprintf('    Cache validation failed: %s is not a containers.Map\n', mapName);
                    return;
                elseif isempty(roiCache.(mapName))
                    fprintf('    Cache validation failed: %s is empty\n', mapName);
                    return;
                end
            end
            
            % Verify that filtering statistics contain data for at least some ROIs
            numROIsWithNoise = length(roiCache.noiseMap);
            numROIsWithThresholds = length(roiCache.standardDeviations);
            
            if numROIsWithNoise == 0 || numROIsWithThresholds == 0
                fprintf('    Cache validation failed: no ROIs have complete filtering data\n');
                return;
            end
            
            % QUALITY CHECK: Verify that the ROI numbers in the cache match the filtering data
            roiKeysInNoise = cell2mat(keys(roiCache.noiseMap));
            if isempty(roiKeysInNoise)
                fprintf('    Cache validation failed: noise map has no numeric keys\n');
                return;
            end
            
            % Check that we have overlap between cache ROIs and filtering data
            commonROIs = intersect(roiCache.numbers, roiKeysInNoise);
            if isempty(commonROIs)
                fprintf('    Cache validation failed: no ROIs overlap between cache and filtering data\n');
                return;
            end
        end
        
        isValid = true;
        
    catch ME
        fprintf('    Cache validation error: %s\n', ME.message);
        isValid = false;
    end
end

function tasks = createPlotTasks(organizedData, averagedData, roiInfo, roiCache, groupKey, outputFolders, config)
    % Create plotting tasks based on experiment type and configuration
    
    tasks = {};
    
    if strcmp(roiInfo.experimentType, 'PPF')
        tasks = createPPFTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache);
    else
        tasks = create1APTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache);
    end
end

function tasks = create1APTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache)
    % Create 1AP plotting tasks with FIXED validation
    
    tasks = {};
    
    % Individual trials - FIXED: Validate data exists
    if config.plotting.ENABLE_INDIVIDUAL_TRIALS && istable(organizedData) && width(organizedData) > 1
        tasks{end+1} = struct('type', 'trials', 'experimentType', '1AP', ...
                             'data', organizedData, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                             'groupKey', groupKey, 'outputFolder', outputFolders.roi_trials);
    end
    
    % ROI averages - FIXED: Better validation and debugging
    if config.plotting.ENABLE_ROI_AVERAGES
        if isfield(averagedData, 'roi') && istable(averagedData.roi) && width(averagedData.roi) > 1
            tasks{end+1} = struct('type', 'averages', 'experimentType', '1AP', ...
                                 'data', averagedData.roi, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.roi_averages);
        elseif config.debug.ENABLE_PLOT_DEBUG
            if ~isfield(averagedData, 'roi')
                fprintf('    ROI averages: averagedData.roi field missing\n');
            elseif ~istable(averagedData.roi)
                fprintf('    ROI averages: averagedData.roi not a table\n');
            elseif width(averagedData.roi) <= 1
                fprintf('    ROI averages: averagedData.roi has %d columns (need >1)\n', width(averagedData.roi));
            end
        end
    end
    
    % Coverslip averages - FIXED: Better validation
    if config.plotting.ENABLE_COVERSLIP_AVERAGES
        if isfield(averagedData, 'total') && istable(averagedData.total) && width(averagedData.total) > 1
            tasks{end+1} = struct('type', 'coverslip', 'experimentType', '1AP', ...
                                 'data', averagedData.total, 'roiInfo', roiInfo, 'roiCache', roiCache, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages);
        elseif config.debug.ENABLE_PLOT_DEBUG
            if ~isfield(averagedData, 'total')
                fprintf('    Coverslip averages: averagedData.total field missing\n');
            elseif ~istable(averagedData.total)
                fprintf('    Coverslip averages: averagedData.total not a table\n');
            elseif width(averagedData.total) <= 1
                fprintf('    Coverslip averages: averagedData.total has %d columns (need >1)\n', width(averagedData.total));
            end
        end
    end
end

function tasks = createPPFTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, config, roiCache)
    % Create PPF plotting tasks (unchanged from original)
    
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

% REMAINING FUNCTIONS UNCHANGED - just reference by name:
% - shouldUseParallel
% - executePlotTasksParallel  
% - executePlotTasksSequential
% - executeSinglePlotTask
% - hasValidPlotData
% - hasValidPPFData
% - getPrimaryPPFData
% - setupPlotEnvironment
% - cleanupPlotEnvironment

function useParallel = shouldUseParallel(tasks, config)
    % Unchanged from original
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
    % Unchanged from original
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
                if GluSnFRConfig().debug.ENABLE_PLOT_DEBUG
                    fprintf('    Task %d failed (parallel): %s\n', i, ME.message);
                end
            end
        end
        
    catch
        plotsGenerated = executePlotTasksSequential(tasks);
    end
end

function plotsGenerated = executePlotTasksSequential(tasks)
    % Unchanged from original
    plotsGenerated = 0;
    
    for i = 1:length(tasks)
        try
            success = executeSinglePlotTask(tasks{i});
            if success
                plotsGenerated = plotsGenerated + 1;
            end
        catch ME
            if GluSnFRConfig().debug.ENABLE_PLOT_DEBUG
                fprintf('    Plot task %d failed: %s\n', i, ME.message);
            end
        end
    end
end

function success = executeSinglePlotTask(task)
    % Execute a single plotting task - FIXED to remove legacy fallbacks
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
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Plot task failed: %s\n', ME.message);
        end
        success = false;
    end
end

function hasData = hasValidPlotData(organizedData, roiInfo, config)
    % Unchanged from original
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
    % Unchanged from original
    hasData = isstruct(organizedData) && ...
              ((isfield(organizedData, 'allData') && width(organizedData.allData) > 1) || ...
               (isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1) || ...
               (isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1));
end

function plotData = getPrimaryPPFData(organizedData)
    % Unchanged from original
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
    % Unchanged from original
    set(groot, 'DefaultFigureVisible', 'off');
    set(groot, 'DefaultFigureRenderer', 'painters');
    set(groot, 'DefaultFigureColor', 'white');
end

function cleanupPlotEnvironment()
    % Unchanged from original
    close all;
    drawnow;
    set(groot, 'DefaultFigureVisible', 'on');
end