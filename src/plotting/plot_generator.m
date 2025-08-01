function plot = plot_generator()
    % PLOT_GENERATOR - Main plotting coordinator
    % 
    % This is now a thin wrapper that coordinates the modular plotting system
    
    plot.generateGroupPlots = @generateGroupPlots;
    plot.calculateLayout = @calculateOptimalLayout;  % From plot_utils
    
    % Load sub-modules
    plot.parallel = plot_parallel_coordinator();
    plot.plot1AP = plot_1ap_generator();
    plot.plotPPF = plot_ppf_generator(); 
    plot.utils = plot_utils();
end

function generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % SIMPLIFIED: Main plotting dispatcher
    
    % Quick validation
    if ~hasValidData(organizedData, roiInfo)
        return;
    end
    
    % Load modules
    parallel_coord = plot_parallel_coordinator();
    
    % Determine strategy and execute
    if strcmp(roiInfo.experimentType, 'PPF')
        parallel_coord.generatePPFPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    else
        parallel_coord.generate1APPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    end
end

function hasData = hasValidData(organizedData, roiInfo)
    % Quick data validation
    if strcmp(roiInfo.experimentType, 'PPF')
        hasData = isstruct(organizedData) && ...
                  ((isfield(organizedData, 'allData') && width(organizedData.allData) > 1) || ...
                   (isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1) || ...
                   (isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1));
    else
        hasData = istable(organizedData) && width(organizedData) > 1;
    end
end

function [nRows, nCols] = calculateOptimalLayout(nSubplots)
    % Moved to plot_utils, but keep for compatibility
    utils = plot_utils();
    [nRows, nCols] = utils.calculateOptimalLayout(nSubplots);
end