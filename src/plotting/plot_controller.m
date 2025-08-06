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
    % FIXED: Create ROI cache with proper data validation and mapping
    
    roiCache = struct();
    roiCache.valid = false;
    roiCache.experimentType = roiInfo.experimentType;
    
    % Initialize empty containers
    roiCache.hasFilteringStats = false;
    roiCache.numbers = [];
    roiCache.nameToIndex = containers.Map();
    roiCache.numberToIndex = containers.Map('KeyType', 'int32', 'ValueType', 'int32');
    
    try
        cfg = GluSnFRConfig();
        utils = string_utils(cfg);
        
        % FIXED: Handle different experiment types properly
        if strcmp(roiInfo.experimentType, '1AP')
            roiCache = create1APCache(roiInfo, organizedData, averagedData, utils, cfg);
        elseif strcmp(roiInfo.experimentType, 'PPF')
            roiCache = createPPFCache(roiInfo, organizedData, averagedData, utils, cfg);
        end
        
    catch ME
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    Cache creation failed: %s\n', ME.message);
        end
        roiCache.valid = false;
    end
end

function roiCache = create1APCache(roiInfo, organizedData, averagedData, utils, cfg)
    % Create cache for 1AP experiments with proper ROI mapping
    
    roiCache = struct();
    roiCache.experimentType = '1AP';
    roiCache.valid = false;
    roiCache.hasFilteringStats = false;
    
    % Extract ROI numbers from organized data (filtered ROIs only)
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
            
            % FIXED: Extract filtering statistics from roiInfo
            if isfield(roiInfo, 'filteringStats') && roiInfo.filteringStats.available
                roiCache.hasFilteringStats = true;
                roiCache.noiseMap = roiInfo.filteringStats.roiNoiseMap;
                roiCache.upperThresholds = roiInfo.filteringStats.roiUpperThresholds;
                roiCache.lowerThresholds = roiInfo.filteringStats.roiLowerThresholds;
                roiCache.basicThresholds = roiInfo.filteringStats.roiBasicThresholds;
            else
                % FALLBACK: Create from basic threshold data if available
                roiCache = createBasicThresholdCache(roiCache, roiInfo, cfg);
            end
            
            roiCache.valid = true;
        end
    end
end

function roiCache = createPPFCache(roiInfo, organizedData, averagedData, utils, cfg)
    % Create cache for PPF experiments
    
    roiCache = struct();
    roiCache.experimentType = 'PPF';
    roiCache.valid = false;
    roiCache.hasFilteringStats = false;
    
    % Extract ROI numbers from PPF organized data
    if isstruct(organizedData)
        % Get primary data table
        if isfield(organizedData, 'allData') && width(organizedData.allData) > 1
            dataTable = organizedData.allData;
        elseif isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1
            dataTable = organizedData.bothPeaks;
        elseif isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1
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
            
            % Extract filtering statistics
            if isfield(roiInfo, 'filteringStats') && roiInfo.filteringStats.available
                roiCache.hasFilteringStats = true;
                roiCache.noiseMap = roiInfo.filteringStats.roiNoiseMap;
                roiCache.upperThresholds = roiInfo.filteringStats.roiUpperThresholds;
                roiCache.lowerThresholds = roiInfo.filteringStats.roiLowerThresholds;
                roiCache.basicThresholds = roiInfo.filteringStats.roiBasicThresholds;
            else
                % Create from coverslip files data
                roiCache = createPPFThresholdCache(roiCache, roiInfo, cfg);
            end
            
            roiCache.valid = true;
        end
    end
end

function roiCache = createBasicThresholdCache(roiCache, roiInfo, cfg)
    % Create threshold cache from basic threshold data
    
    roiCache.noiseMap = containers.Map('KeyType', 'int32', 'ValueType', 'char');
    roiCache.upperThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    roiCache.lowerThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    roiCache.basicThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    
    % Use threshold data if available
    if isfield(roiInfo, 'thresholds') && ~isempty(roiInfo.thresholds)
        [nROIs, nTrials] = size(roiInfo.thresholds);
        
        for roiIdx = 1:min(nROIs, length(roiCache.numbers))
            roiNum = roiCache.numbers(roiIdx);
            
            % Get a representative threshold for this ROI
            roiThresholds = roiInfo.thresholds(roiIdx, :);
            validThresholds = roiThresholds(isfinite(roiThresholds) & roiThresholds > 0);
            
            if ~isempty(validThresholds)
                basicThreshold = median(validThresholds);
                
                % Classify noise level
                if basicThreshold <= cfg.thresholds.LOW_NOISE_CUTOFF
                    noiseLevel = 'low';
                    upperThreshold = basicThreshold * cfg.filtering.schmitt.LOW_NOISE_UPPER_MULT;
                else
                    noiseLevel = 'high';
                    upperThreshold = basicThreshold * cfg.filtering.schmitt.HIGH_NOISE_UPPER_MULT;
                end
                lowerThreshold = basicThreshold * cfg.filtering.schmitt.LOWER_THRESHOLD_MULT;
                
                roiCache.noiseMap(roiNum) = noiseLevel;
                roiCache.upperThresholds(roiNum) = upperThreshold;
                roiCache.lowerThresholds(roiNum) = lowerThreshold;
                roiCache.basicThresholds(roiNum) = basicThreshold;
                roiCache.hasFilteringStats = true;
            end
        end
    end
end

function roiCache = createPPFThresholdCache(roiCache, roiInfo, cfg)
    % Create threshold cache from PPF coverslip files
    
    roiCache.noiseMap = containers.Map('KeyType', 'int32', 'ValueType', 'char');
    roiCache.upperThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    roiCache.lowerThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    roiCache.basicThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    
    if isfield(roiInfo, 'coverslipFiles') && ~isempty(roiInfo.coverslipFiles)
        for fileIdx = 1:length(roiInfo.coverslipFiles)
            fileData = roiInfo.coverslipFiles(fileIdx);
            
            if ~isempty(fileData.roiNumbers) && ~isempty(fileData.thresholds)
                for roiIdx = 1:length(fileData.roiNumbers)
                    roiNum = fileData.roiNumbers(roiIdx);
                    
                    if roiIdx <= length(fileData.thresholds)
                        basicThreshold = fileData.thresholds(roiIdx);
                        
                        if isfinite(basicThreshold) && basicThreshold > 0
                            % Classify noise level
                            if basicThreshold <= cfg.thresholds.LOW_NOISE_CUTOFF
                                noiseLevel = 'low';
                                upperThreshold = basicThreshold * cfg.filtering.schmitt.LOW_NOISE_UPPER_MULT;
                            else
                                noiseLevel = 'high';
                                upperThreshold = basicThreshold * cfg.filtering.schmitt.HIGH_NOISE_UPPER_MULT;
                            end
                            lowerThreshold = basicThreshold * cfg.filtering.schmitt.LOWER_THRESHOLD_MULT;
                            
                            roiCache.noiseMap(roiNum) = noiseLevel;
                            roiCache.upperThresholds(roiNum) = upperThreshold;
                            roiCache.lowerThresholds(roiNum) = lowerThreshold;
                            roiCache.basicThresholds(roiNum) = basicThreshold;
                            roiCache.hasFilteringStats = true;
                        end
                    end
                end
            end
        end
    end
end

function isValid = validateROICache(roiCache, roiInfo)
    % Validate that ROI cache contains expected data
    
    isValid = false;
    
    try
        % Basic structure validation
        if ~isstruct(roiCache) || ~roiCache.valid
            return;
        end
        
        % Check required fields
        requiredFields = {'numbers', 'numberToIndex', 'experimentType'};
        for i = 1:length(requiredFields)
            if ~isfield(roiCache, requiredFields{i})
                return;
            end
        end
        
        % Check that we have ROI numbers
        if isempty(roiCache.numbers)
            return;
        end
        
        % Check that maps are properly sized
        if length(roiCache.numberToIndex) ~= length(roiCache.numbers)
            return;
        end
        
        % Check filtering statistics if claimed to be available
        if roiCache.hasFilteringStats
            requiredMaps = {'noiseMap', 'upperThresholds', 'lowerThresholds', 'basicThresholds'};
            for i = 1:length(requiredMaps)
                if ~isfield(roiCache, requiredMaps{i}) || ~isa(roiCache.(requiredMaps{i}), 'containers.Map')
                    return;
                end
            end
            
            % Check that at least some ROIs have filtering data
            if length(roiCache.noiseMap) == 0
                return;
            end
        end
        
        isValid = true;
        
    catch
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