function coordinator = plot_parallel_coordinator()
    % PLOT_PARALLEL_COORDINATOR - Simplified coordinator (no plot-level parallel)
    
    coordinator.generate1APPlots = @generate1APPlots;
    coordinator.generatePPFPlots = @generatePPFPlots;
    coordinator.createParallelPool = @createPlottingPool;
    coordinator.shouldUseParallel = @shouldUseParallelPlotting;
end

function generate1APPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Generate 1AP plots (sequential only - no parallel within group)
    
    plot1AP = plot_1ap_generator();
    plot1AP.generateSequential(organizedData, averagedData, roiInfo, groupKey, outputFolders);
end

function generatePPFPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Generate PPF plots (sequential only - no parallel within group)
    
    plotPPF = plot_ppf_generator();
    plotPPF.generateSequential(organizedData, averagedData, roiInfo, groupKey, outputFolders);
end

function useParallel = shouldUseParallelPlotting(tasks)
    % Always return false - no plot-level parallelization
    useParallel = false;
end

function success = createPlottingPool()
    % Not needed for plot-level parallel, but keep for compatibility
    success = true;
end