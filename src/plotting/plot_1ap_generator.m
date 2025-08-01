function plot1AP = plot_1ap_generator()
    % PLOT_1AP_GENERATOR - Specialized 1AP plotting
    
    plot1AP.generateSequential = @generate1APSequential;
    plot1AP.generateTrialsPlot = @generateTrialsPlot;
    plot1AP.generateAveragedPlot = @generateAveragedPlot;
    plot1AP.generateCoverslipPlot = @generateCoverslipPlot;
end

function generate1APSequential(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Sequential 1AP plot generation
    
    plotsGenerated = 0;
    
    % Individual trials plots
    if istable(organizedData) && width(organizedData) > 1
        success = generateTrialsPlot(organizedData, roiInfo, groupKey, outputFolders.roi_trials);
        if success, plotsGenerated = plotsGenerated + 1; end
    end
    
    % ROI averaged plots  
    if isfield(averagedData, 'roi') && width(averagedData.roi) > 1
        success = generateAveragedPlot(averagedData.roi, roiInfo, groupKey, outputFolders.roi_averages);
        if success, plotsGenerated = plotsGenerated + 1; end
    end
    
    % Coverslip averages
    if isfield(averagedData, 'total') && width(averagedData.total) > 1
        success = generateCoverslipPlot(averagedData.total, roiInfo, groupKey, outputFolders.coverslip_averages);
        if success, plotsGenerated = plotsGenerated + 1; end
    end
    
    fprintf('    Generated %d/3 plots successfully (sequential)\n', plotsGenerated);
end

function success = generate1APTrialsOptimized(task)
    % UPDATED: 1AP trials plotting with minimal output
    
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
                  sprintf('-r%d', cfg.plotting.DPI), '-vector');
            
            close(fig);
            success = true;
            
        catch ME
            if exist('fig', 'var') && isvalid(fig)
                close(fig);
            end
        end
    end
end