function plot = plot_generator()
    % PLOT_GENERATOR - Main plotting coordinator
    % 
    % This is the main entry point for the modular plotting system.
    % It coordinates between the specialized plotting modules and handles
    % the decision of whether to use parallel or sequential processing.
    
    plot.generateGroupPlots = @generateGroupPlots;
    plot.calculateLayout = @calculateOptimalLayout;  % Backward compatibility
    
    % Load sub-modules (lazy loading for better performance)
    plot.parallel = [];  % Loaded on demand
    plot.plot1AP = [];   % Loaded on demand
    plot.plotPPF = [];   % Loaded on demand
    plot.utils = [];     % Loaded on demand
end

function generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Main plotting dispatcher with intelligent routing
    
    % Quick validation - exit early if no data
    if ~hasValidPlotData(organizedData, roiInfo)
        return;
    end
    
    % Load modules on demand
    parallel_coord = plot_parallel_coordinator();
    utils = plot_utils();
    
    % Set up optimal plotting environment
    utils.setupFigureDefaults();
    
    % Route to appropriate plotting system based on experiment type
    if strcmp(roiInfo.experimentType, 'PPF')
        parallel_coord.generatePPFPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    else
        parallel_coord.generate1APPlots(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    end
    
    % Cleanup - close any remaining figures and reset defaults
    cleanupPlottingEnvironment();
end

function hasData = hasValidPlotData(organizedData, roiInfo)
    % Quick validation of plot data structure
    
    if strcmp(roiInfo.experimentType, 'PPF')
        % PPF: Check if any of the organized data tables have content
        hasData = isstruct(organizedData) && ...
                  ((isfield(organizedData, 'allData') && width(organizedData.allData) > 1) || ...
                   (isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1) || ...
                   (isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1));
    else
        % 1AP: Check organized data directly
        hasData = istable(organizedData) && width(organizedData) > 1;
    end
end

function cleanupPlottingEnvironment()
    % Clean up plotting environment after batch processing
    
    % Close any figures that might be left open
    close all;
    
    % Force MATLAB to process all pending graphics events
    drawnow;
    
    % Reset to default figure visibility (in case it was changed)
    set(groot, 'DefaultFigureVisible', 'on');
    
    % Optional: Force garbage collection to free memory
    if feature('HotLinks')  % Only if Java is available
        java.lang.System.gc();
    end
end

function [nRows, nCols] = calculateOptimalLayout(nSubplots)
    % Backward compatibility function - delegates to utils
    
    utils = plot_utils();
    [nRows, nCols] = utils.calculateOptimalLayout(nSubplots);
end