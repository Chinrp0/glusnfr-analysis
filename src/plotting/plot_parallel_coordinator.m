function coordinator = plot_parallel_coordinator()
    % PLOT_PARALLEL_COORDINATOR - Enhanced with actual parallel processing support
    
    coordinator.generate1APPlots = @generate1APPlots;
    coordinator.generatePPFPlots = @generatePPFPlots;
    coordinator.createParallelPool = @createPlottingPool;
    coordinator.shouldUseParallel = @shouldUseParallelPlotting;
    coordinator.generatePlotsInParallel = @generatePlotsInParallel;  % NEW
    coordinator.cleanupParallelPlotting = @cleanupParallelPlotting;  % NEW
end

function generate1APPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % ENHANCED: Generate 1AP plots with optional parallel processing
    
    cfg = GluSnFRConfig();
    utils = plot_utils();
    
    % Early exit if plots disabled
    if ~cfg.plotting.ENABLE_INDIVIDUAL_TRIALS && ~cfg.plotting.ENABLE_ROI_AVERAGES && ...
       ~cfg.plotting.ENABLE_COVERSLIP_AVERAGES
        fprintf('    All 1AP plots disabled in configuration\n');
        return;
    end
    
    % Create plot tasks
    tasks = create1APPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, cfg);
    
    if isempty(tasks)
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    No 1AP plot tasks created\n');
        end
        return;
    end
    
    % Decide parallel vs sequential
    if shouldUseParallelPlotting(tasks, cfg)
        plotsGenerated = generatePlotsInParallel(tasks, '1AP');
        fprintf('    Generated %d/% d 1AP plots (parallel)\n', plotsGenerated, length(tasks));
    else
        plotsGenerated = generate1APSequential(tasks);
        fprintf('    Generated %d/%d 1AP plots (sequential)\n', plotsGenerated, length(tasks));
    end
end

function generatePPFPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % ENHANCED: Generate PPF plots with optional parallel processing
    
    cfg = GluSnFRConfig();
    utils = plot_utils();
    
    % Early exit if plots disabled
    if ~cfg.plotting.ENABLE_PPF_INDIVIDUAL && ~cfg.plotting.ENABLE_PPF_AVERAGED
        fprintf('    All PPF plots disabled in configuration\n');
        return;
    end
    
    % Create plot tasks
    tasks = createPPFPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, cfg);
    
    if isempty(tasks)
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    No PPF plot tasks created\n');
        end
        return;
    end
    
    % Decide parallel vs sequential
    if shouldUseParallelPlotting(tasks, cfg)
        plotsGenerated = generatePlotsInParallel(tasks, 'PPF');
        fprintf('    Generated %d/%d PPF plots (parallel)\n', plotsGenerated, length(tasks));
    else
        plotsGenerated = generatePPFSequential(tasks);
        fprintf('    Generated %d/%d PPF plots (sequential)\n', plotsGenerated, length(tasks));
    end
end

function useParallel = shouldUseParallelPlotting(tasks, cfg)
    % FIXED: Actually implement parallel plotting decision logic
    
    if nargin < 2
        cfg = GluSnFRConfig();
    end
    
    useParallel = false;
    
    % Check if parallel plotting is enabled in config
    if ~cfg.plotting.ENABLE_PARALLEL
        return;
    end
    
    % Check if we have enough tasks to justify parallel processing
    if length(tasks) < cfg.plotting.PARALLEL_THRESHOLD
        return;
    end
    
    % Check if parallel pool is available
    pool = gcp('nocreate');
    if isempty(pool)
        return;
    end
    
    % Check if we have enough workers
    if pool.NumWorkers < 2
        return;
    end
    
    useParallel = true;
    
    if cfg.debug.ENABLE_PLOT_DEBUG
        fprintf('    Parallel plotting enabled: %d tasks, %d workers\n', ...
                length(tasks), pool.NumWorkers);
    end
end

function success = createPlottingPool()
    % NEW: Create or verify parallel pool for plotting
    
    cfg = GluSnFRConfig();
    success = false;
    
    if ~cfg.plotting.ENABLE_PARALLEL
        return;
    end
    
    try
        pool = gcp('nocreate');
        if isempty(pool)
            % Create pool with limited workers for plotting
            maxWorkers = min(cfg.plotting.MAX_CONCURRENT_PLOTS, feature('numcores') - 1);
            pool = parpool('Processes', maxWorkers);
            pool.IdleTimeout = 30;  % Shorter timeout for plotting pool
        end
        
        success = ~isempty(pool);
        
        if success && cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    Plotting pool ready: %d workers\n', pool.NumWorkers);
        end
        
    catch ME
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    Could not create plotting pool: %s\n', ME.message);
        end
        success = false;
    end
end

function plotsGenerated = generatePlotsInParallel(tasks, experimentType)
    % NEW: Execute plot tasks in parallel
    
    cfg = GluSnFRConfig();
    pool = gcp('nocreate');
    
    if isempty(pool)
        % Fallback to sequential
        plotsGenerated = generateSequentialPlots(tasks);
        return;
    end
    
    try
        % Limit concurrent tasks to avoid overwhelming the system
        maxConcurrent = min(cfg.plotting.MAX_CONCURRENT_PLOTS, length(tasks));
        
        % Submit tasks in batches
        futures = cell(length(tasks), 1);
        activeFutures = 0;
        completedFutures = 0;
        
        for i = 1:length(tasks)
            % Wait if we've reached the concurrent limit
            while activeFutures >= maxConcurrent
                % Check for completed futures
                for j = 1:i-1
                    if ~isempty(futures{j}) && strcmp(futures{j}.State, 'finished')
                        try
                            fetchOutputs(futures{j});
                            completedFutures = completedFutures + 1;
                        catch
                            % Silent failure for individual plots
                        end
                        futures{j} = [];  % Mark as processed
                        activeFutures = activeFutures - 1;
                    end
                end
                
                if activeFutures >= maxConcurrent
                    pause(0.1);  % Brief pause to avoid busy waiting
                end
            end
            
            % Submit task
            futures{i} = parfeval(pool, @executePlotTask, 1, tasks{i});
            activeFutures = activeFutures + 1;
        end
        
        % Wait for remaining futures
        for i = 1:length(futures)
            if ~isempty(futures{i})
                try
                    success = fetchOutputs(futures{i});
                    if success
                        completedFutures = completedFutures + 1;
                    end
                catch
                    % Silent failure for individual plots
                end
            end
        end
        
        plotsGenerated = completedFutures;
        
    catch ME
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    Parallel plotting failed: %s\n', ME.message);
        end
        % Fallback to sequential
        plotsGenerated = generateSequentialPlots(tasks);
    end
end

function plotsGenerated = generateSequentialPlots(tasks)
    % Execute plot tasks sequentially
    
    plotsGenerated = 0;
    
    for i = 1:length(tasks)
        try
            success = executePlotTask(tasks{i});
            if success
                plotsGenerated = plotsGenerated + 1;
            end
        catch ME
            % Continue with other plots even if one fails
            fprintf('    Plot task %d failed: %s\n', i, ME.message);
        end
    end
end

function plotsGenerated = generate1APSequential(tasks)
    % Sequential 1AP plot generation using tasks
    
    plotsGenerated = 0;
    plot1AP = plot_1ap_generator();
    
    for i = 1:length(tasks)
        task = tasks{i};
        try
            switch task.type
                case 'trials'
                    success = plot1AP.generateTrialsPlot(task.data, task.roiInfo, task.groupKey, task.outputFolder);
                case 'averaged'
                    success = plot1AP.generateAveragedPlot(task.data, task.roiInfo, task.groupKey, task.outputFolder);
                case 'coverslip'
                    success = plot1AP.generateCoverslipPlot(task.data, task.roiInfo, task.groupKey, task.outputFolder);
                otherwise
                    success = false;
            end
            
            if success
                plotsGenerated = plotsGenerated + 1;
            end
            
        catch ME
            fprintf('    1AP plot task failed: %s\n', ME.message);
        end
    end
end

function plotsGenerated = generatePPFSequential(tasks)
    % Sequential PPF plot generation using tasks
    
    plotsGenerated = 0;
    plotPPF = plot_ppf_generator();
    
    for i = 1:length(tasks)
        task = tasks{i};
        try
            switch task.type
                case 'individual'
                    success = plotPPF.generateIndividualPlots(task.data, task.roiInfo, task.groupKey, task.outputFolder);
                case {'averaged_alldata', 'averaged_bothpeaks', 'averaged_singlepeak'}
                    success = plotPPF.generateAveragedPlots(task.data, task.roiInfo, task.groupKey, task.outputFolder, task.plotType);
                otherwise
                    success = false;
            end
            
            if success
                plotsGenerated = plotsGenerated + 1;
            end
            
        catch ME
            fprintf('    PPF plot task failed: %s\n', ME.message);
        end
    end
end

function success = executePlotTask(task)
    % Execute a single plotting task (for parallel execution)
    
    success = false;
    
    try
        % Load required modules (each worker needs its own instances)
        if strcmp(task.experimentType, '1AP')
            plot1AP = plot_1ap_generator();
            
            switch task.type
                case 'trials'
                    success = plot1AP.generateTrialsPlot(task.data, task.roiInfo, task.groupKey, task.outputFolder);
                case 'averaged'
                    success = plot1AP.generateAveragedPlot(task.data, task.roiInfo, task.groupKey, task.outputFolder);
                case 'coverslip'
                    success = plot1AP.generateCoverslipPlot(task.data, task.roiInfo, task.groupKey, task.outputFolder);
            end
            
        elseif strcmp(task.experimentType, 'PPF')
            plotPPF = plot_ppf_generator();
            
            switch task.type
                case 'individual'
                    success = plotPPF.generateIndividualPlots(task.data, task.roiInfo, task.groupKey, task.outputFolder);
                case {'averaged_alldata', 'averaged_bothpeaks', 'averaged_singlepeak'}
                    success = plotPPF.generateAveragedPlots(task.data, task.roiInfo, task.groupKey, task.outputFolder, task.plotType);
            end
        end
        
    catch ME
        % Silent failure for parallel execution
        success = false;
    end
end

function tasks = create1APPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, cfg)
    % Create 1AP plotting tasks based on configuration
    
    tasks = {};
    
    % Individual trials plot
    if cfg.plotting.ENABLE_INDIVIDUAL_TRIALS && istable(organizedData) && width(organizedData) > 1
        tasks{end+1} = struct('type', 'trials', 'experimentType', '1AP', ...
                             'data', organizedData, 'roiInfo', roiInfo, ...
                             'groupKey', groupKey, 'outputFolder', outputFolders.roi_trials);
    end
    
    % ROI averaged plots
    if cfg.plotting.ENABLE_ROI_AVERAGES && isfield(averagedData, 'roi') && width(averagedData.roi) > 1
        tasks{end+1} = struct('type', 'averaged', 'experimentType', '1AP', ...
                             'data', averagedData.roi, 'roiInfo', roiInfo, ...
                             'groupKey', groupKey, 'outputFolder', outputFolders.roi_averages);
    end
    
    % Coverslip averages
    if cfg.plotting.ENABLE_COVERSLIP_AVERAGES && isfield(averagedData, 'total') && width(averagedData.total) > 1
        tasks{end+1} = struct('type', 'coverslip', 'experimentType', '1AP', ...
                             'data', averagedData.total, 'roiInfo', roiInfo, ...
                             'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages);
    end
end

function tasks = createPPFPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders, cfg)
    % Create PPF plotting tasks based on configuration
    
    tasks = {};
    
    % Individual plots
    if cfg.plotting.ENABLE_PPF_INDIVIDUAL && hasValidPPFData(organizedData)
        tasks{end+1} = struct('type', 'individual', 'experimentType', 'PPF', ...
                             'data', getPrimaryPPFData(organizedData), 'roiInfo', roiInfo, ...
                             'groupKey', groupKey, 'outputFolder', outputFolders.roi_trials);
    end
    
    % Averaged plots
    if cfg.plotting.ENABLE_PPF_AVERAGED && isstruct(averagedData)
        if isfield(averagedData, 'allData') && width(averagedData.allData) > 1
            tasks{end+1} = struct('type', 'averaged_alldata', 'experimentType', 'PPF', ...
                                 'data', averagedData.allData, 'roiInfo', roiInfo, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages, ...
                                 'plotType', 'AllData');
        end
        
        if isfield(averagedData, 'bothPeaks') && width(averagedData.bothPeaks) > 1
            tasks{end+1} = struct('type', 'averaged_bothpeaks', 'experimentType', 'PPF', ...
                                 'data', averagedData.bothPeaks, 'roiInfo', roiInfo, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages, ...
                                 'plotType', 'BothPeaks');
        end
        
        if isfield(averagedData, 'singlePeak') && width(averagedData.singlePeak) > 1
            tasks{end+1} = struct('type', 'averaged_singlepeak', 'experimentType', 'PPF', ...
                                 'data', averagedData.singlePeak, 'roiInfo', roiInfo, ...
                                 'groupKey', groupKey, 'outputFolder', outputFolders.coverslip_averages, ...
                                 'plotType', 'SinglePeak');
        end
    end
end

function hasData = hasValidPPFData(organizedData)
    % Check if PPF data structure has valid data
    
    hasData = isstruct(organizedData) && ...
              ((isfield(organizedData, 'allData') && width(organizedData.allData) > 1) || ...
               (isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1) || ...
               (isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1));
end

function plotData = getPrimaryPPFData(organizedData)
    % Get primary data for PPF plotting (priority: allData > bothPeaks > singlePeak)
    
    plotData = [];
    
    if isfield(organizedData, 'allData') && width(organizedData.allData) > 1
        plotData = organizedData.allData;
    elseif isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1
        plotData = organizedData.bothPeaks;
    elseif isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1
        plotData = organizedData.singlePeak;
    end
end

function cleanupParallelPlotting()
    % NEW: Clean up after parallel plotting
    
    try
        % Close any remaining figures
        close all;
        
        % Force graphics processing
        drawnow;
        
        % Optional: Clear plot caches
        utils = plot_utils();
        if isfield(utils, 'clearPlotCache')
            utils.clearPlotCache();
        end
        
    catch ME
        % Silent cleanup
    end
end