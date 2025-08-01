function coordinator = plot_parallel_coordinator()
    % PLOT_PARALLEL_COORDINATOR - Manages parallel plotting decisions
    
    coordinator.generate1APPlots = @generate1APPlotsCoordinated;
    coordinator.generatePPFPlots = @generatePPFPlotsCoordinated;
    coordinator.createParallelPool = @createPlottingPool;
    coordinator.shouldUseParallel = @shouldUseParallelPlotting;
end

function generate1APPlotsCoordinated(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Coordinate 1AP plotting with parallel decision
    
    % Create plot tasks
    tasks = identify1APPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    
    if shouldUseParallelPlotting(tasks)
        executeParallelPlots(tasks);
    else
        plot1AP = plot_1ap_generator();
        plot1AP.generateSequential(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    end
end

function generatePPFPlotsCoordinated(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Coordinate PPF plotting with parallel decision
    
    tasks = identifyPPFPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    
    if shouldUseParallelPlotting(tasks)
        executeParallelPlots(tasks);
    else
        plotPPF = plot_ppf_generator();
        plotPPF.generateSequential(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    end
end

function useParallel = shouldUseParallelPlotting(tasks)
    % Improved parallel plotting decision
    
    numTasks = length(tasks);
    poolObj = gcp('nocreate');
    hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox');
    hasEnoughCores = feature('numcores') >= 2;
    
    % Use parallel if:
    % 1. More than 1 task AND
    % 2. (Pool exists OR can create one) AND  
    % 3. Tasks are computationally heavy enough
    
    useParallel = numTasks > 1 && hasParallelToolbox && hasEnoughCores && ...
                  (~isempty(poolObj) || createPlottingPool());
    
    if useParallel
        fprintf('    Using PARALLEL plotting (%d tasks)\n', numTasks);
    else
        fprintf('    Using sequential plotting (%d tasks)\n', numTasks);
    end
end

function success = createPlottingPool()
    % Create parallel pool specifically for plotting
    success = false;
    
    try
        if isempty(gcp('nocreate'))
            workers = min(4, feature('numcores'));  % Max 4 workers for plotting
            parpool('Processes', workers);
            fprintf('      Created plotting pool with %d workers\n', workers);
        end
        success = true;
    catch
        success = false;
    end
end