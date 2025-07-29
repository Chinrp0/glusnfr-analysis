function plot = plot_generator()
    % PLOT_GENERATOR - Publication-ready plotting module
    % 
    % This module handles all plotting operations:
    % - Individual trial plots with proper coloring
    % - Averaged plots with thresholds
    % - PPF-specific plotting with genotype colors
    % - 1AP plots with noise level separation
    
    plot.generateGroupPlots = @generateGroupPlots;
    plot.generate1APPlots = @generate1APPlots;
    plot.generatePPFPlots = @generatePPFPlots;
    plot.generateTotalAveragePlots = @generateTotalAveragePlots;
    plot.calculateLayout = @calculateOptimalLayout;
end

function generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, plotsIndividualFolder, plotsAveragedFolder)
    % Main plotting dispatcher
    
    if strcmp(roiInfo.experimentType, 'PPF')
        generatePPFPlots(organizedData, averagedData, roiInfo, groupKey, plotsIndividualFolder, plotsAveragedFolder);
    else
        % Create subfolders for 1AP organization
        roiPlotsFolder = fullfile(plotsAveragedFolder, 'ROI_Averages');
        totalPlotsFolder = fullfile(plotsAveragedFolder, 'Total_Averages');
        
        if ~exist(roiPlotsFolder, 'dir'), mkdir(roiPlotsFolder); end
        if ~exist(totalPlotsFolder, 'dir'), mkdir(totalPlotsFolder); end
        
        generate1APPlots(organizedData, averagedData.roi, roiInfo, groupKey, plotsIndividualFolder, roiPlotsFolder);
        generateTotalAveragePlots(averagedData.total, roiInfo, groupKey, totalPlotsFolder);
    end
end

function generate1APPlots(organizedData, averagedData, roiInfo, groupKey, plotsIndividualFolder, plotsAveragedFolder)
    % Generate 1AP-specific plots with noise level awareness
    
    cfg = GluSnFRConfig();
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    timeData_ms = organizedData.Frame;
    stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    
    % Color scheme for trials
    trialColors = [
        0.0 0.0 0.0;      % Black
        0.8 0.2 0.2;      % Red  
        0.2 0.6 0.8;      % Blue
        0.2 0.8 0.2;      % Green
        0.8 0.5 0.2;      % Orange
        0.6 0.2 0.8;      % Purple
        0.8 0.8 0.2;      % Yellow
        0.4 0.4 0.4;      % Gray
        0.0 0.8 0.8;      % Cyan
        0.8 0.0 0.8;      % Magenta
    ];
    
    maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
    numROIs = length(roiInfo.roiNumbers);
    
    if numROIs == 0
        fprintf('    No ROIs to plot for group %s\n', groupKey);
        return;
    end
    
    % Get unique trials for consistent coloring
    uniqueTrials = unique(roiInfo.originalTrialNumbers);
    uniqueTrials = uniqueTrials(isfinite(uniqueTrials));
    uniqueTrials = sort(uniqueTrials);
    
    % Generate individual trials plots
    numTrialsFigures = ceil(numROIs / maxPlotsPerFigure);
    
    for figNum = 1:numTrialsFigures
        try
            fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
            
            startROI = (figNum - 1) * maxPlotsPerFigure + 1;
            endROI = min(figNum * maxPlotsPerFigure, numROIs);
            numPlotsThisFig = endROI - startROI + 1;
            
            [nRows, nCols] = calculateOptimalLayout(numPlotsThisFig);
            
            % Track legend handles
            legendHandles = [];
            legendLabels = {};
            
            for roiIdx = startROI:endROI
                subplotIdx = roiIdx - startROI + 1;
                roiNum = roiInfo.roiNumbers(roiIdx);
                
                subplot(nRows, nCols, subplotIdx);
                hold on;
                
                % Plot trials for this ROI
                trialCount = 0;
                hasThresholdInLegend = false;
                
                for i = 1:length(uniqueTrials)
                    trialNum = uniqueTrials(i);
                    colName = sprintf('ROI%d_T%g', roiNum, trialNum);
                    
                    if ismember(colName, organizedData.Properties.VariableNames)
                        trialData = organizedData.(colName);
                        if ~all(isnan(trialData))
                            trialCount = trialCount + 1;
                            
                            colorIdx = mod(i-1, size(trialColors, 1)) + 1;
                            h_line = plot(timeData_ms, trialData, 'Color', trialColors(colorIdx, :), 'LineWidth', 1.0);
                            h_line.Color(4) = cfg.plotting.TRANSPARENCY;
                            
                            % Add to legend (only from first subplot)
                            if subplotIdx == 1 && ~ismember(sprintf('Trial %g', trialNum), legendLabels)
                                legendHandles(end+1) = h_line;
                                legendLabels{end+1} = sprintf('Trial %g', trialNum);
                            end
                            
                            % Add threshold line
                            trialIdx = find(roiInfo.originalTrialNumbers == trialNum, 1);
                            if ~isempty(trialIdx) && roiIdx <= size(roiInfo.thresholds, 1) && ...
                               trialIdx <= size(roiInfo.thresholds, 2) && ...
                               isfinite(roiInfo.thresholds(roiIdx, trialIdx))
                                
                                threshold = roiInfo.thresholds(roiIdx, trialIdx);
                                h_thresh = plot([timeData_ms(1), timeData_ms(100)], [threshold, threshold], ...
                                     ':', 'Color', trialColors(colorIdx, :), 'LineWidth', 1.5, 'HandleVisibility', 'off');
                                
                                if subplotIdx == 1 && ~hasThresholdInLegend
                                    h_thresh.HandleVisibility = 'on';
                                    legendHandles(end+1) = h_thresh;
                                    legendLabels{end+1} = 'Thresholds';
                                    hasThresholdInLegend = true;
                                end
                            end
                        end
                    end
                end
                
                % Set y-limits and add stimulus
                ylim(cfg.plotting.Y_LIMITS);
                hStim = plot([stimulusTime_ms, stimulusTime_ms], [cfg.plotting.Y_LIMITS(1), cfg.plotting.Y_LIMITS(1)], ...
                     ':gpentagram', 'LineWidth', 1.0, 'HandleVisibility', 'off');
                
                if subplotIdx == 1 && ~ismember('Stimulus', legendLabels)
                    hStim.HandleVisibility = 'on';
                    legendHandles(end+1) = hStim;
                    legendLabels{end+1} = 'Stimulus';
                end
                
                title(sprintf('ROI %d (n=%d)', roiNum, trialCount), 'FontSize', 10, 'FontWeight', 'bold');
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Add legend
            if ~isempty(legendHandles)
                legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 8);
            end
            
            % Save figure
            if numTrialsFigures > 1
                titleText = sprintf('%s - Individual Trials (Part %d/%d)', cleanGroupKey, figNum, numTrialsFigures);
                plotFile = sprintf('%s_trials_part%d.png', cleanGroupKey, figNum);
            else
                titleText = sprintf('%s - Individual Trials', cleanGroupKey);
                plotFile = sprintf('%s_trials.png', cleanGroupKey);
            end
            
            sgtitle(titleText, 'FontSize', 14, 'Interpreter', 'none', 'FontWeight', 'bold');
            print(fig, fullfile(plotsIndividualFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
            close(fig);
            
        catch ME
            fprintf('    ERROR creating trials plot %d: %s\n', figNum, ME.message);
            if exist('fig', 'var'), close(fig); end
        end
    end
    
    % Generate averaged plots
    generateAveragedPlots(averagedData, roiInfo, cleanGroupKey, plotsAveragedFolder, timeData_ms, stimulusTime_ms, cfg);
    
    fprintf('    Generated %d trials plot(s) and averaged plots\n', numTrialsFigures);
end

function generateAveragedPlots(averagedData, roiInfo, cleanGroupKey, plotsFolder, timeData_ms, stimulusTime_ms, cfg)
    % Generate averaged plots for 1AP experiments
    
    if width(averagedData) <= 1
        return;
    end
    
    avgVarNames = averagedData.Properties.VariableNames(2:end);
    numAvgPlots = length(avgVarNames);
    maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
    numAvgFigures = ceil(numAvgPlots / maxPlotsPerFigure);
    
    for figNum = 1:numAvgFigures
        try
            figAvg = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
            
            startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
            endPlot = min(figNum * maxPlotsPerFigure, numAvgPlots);
            numPlotsThisFig = endPlot - startPlot + 1;
            
            [nRowsAvg, nColsAvg] = calculateOptimalLayout(numPlotsThisFig);
            
            legendHandles = [];
            legendLabels = {};
            
            for plotIdx = startPlot:endPlot
                subplotIdx = plotIdx - startPlot + 1;
                
                subplot(nRowsAvg, nColsAvg, subplotIdx);
                hold on;
                
                varName = avgVarNames{plotIdx};
                avgData = averagedData.(varName);
                
                % Plot average trace
                h_line = plot(timeData_ms, avgData, 'k-', 'LineWidth', 1.0);
                
                if subplotIdx == 1
                    legendHandles(end+1) = h_line;
                    legendLabels{end+1} = 'Average';
                end
                
                % Add threshold
                avgThreshold = calculateAverageThreshold(avgData, cfg);
                if isfinite(avgThreshold)
                    hThresh = plot([timeData_ms(1), timeData_ms(100)], [avgThreshold, avgThreshold], ...
                         'g--', 'LineWidth', 2, 'HandleVisibility', 'off');
                    
                    if subplotIdx == 1
                        legendHandles(end+1) = hThresh;
                        legendLabels{end+1} = 'Threshold';
                    end
                end
                
                % Parse title
                roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    title(sprintf('ROI %s (n=%s)', roiMatch{1}{1}, roiMatch{1}{2}), 'FontSize', 10, 'FontWeight', 'bold');
                else
                    title(varName, 'FontSize', 10);
                end
                
                % Set limits and add stimulus
                ylim(cfg.plotting.Y_LIMITS);
                hStim = plot([stimulusTime_ms, stimulusTime_ms], [cfg.plotting.Y_LIMITS(1), cfg.plotting.Y_LIMITS(1)], ...
                            ':gpentagram', 'LineWidth', 1.0, 'HandleVisibility', 'off');
                
                if subplotIdx == 1
                    legendHandles(end+1) = hStim;
                    legendLabels{end+1} = 'Stimulus';
                end
                
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Add legend
            if ~isempty(legendHandles)
                legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 8);
            end
            
            % Save figure
            if numAvgFigures > 1
                titleText = sprintf('%s - Averaged Traces (Part %d/%d)', cleanGroupKey, figNum, numAvgFigures);
                avgPlotFile = sprintf('%s_averaged_part%d.png', cleanGroupKey, figNum);
            else
                titleText = sprintf('%s - Averaged Traces', cleanGroupKey);
                avgPlotFile = sprintf('%s_averaged.png', cleanGroupKey);
            end
            
            sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
            print(figAvg, fullfile(plotsFolder, avgPlotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
            close(figAvg);
            
        catch ME
            fprintf('    ERROR creating averaged figure %d: %s\n', figNum, ME.message);
            if exist('figAvg', 'var'), close(figAvg); end
        end
    end
end

function generatePPFPlots(organizedData, averagedData, roiInfo, groupKey, plotsIndividualFolder, plotsAveragedFolder)
    % Generate PPF-specific plots with genotype colors
    
    cfg = GluSnFRConfig();
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    timeData_ms = organizedData.Frame;
    stimulusTime_ms1 = cfg.timing.STIMULUS_TIME_MS;
    stimulusTime_ms2 = stimulusTime_ms1 + roiInfo.timepoint;
    
    % Extract genotype for color coding
    genotype = extractGenotypeFromGroupKey(groupKey);
    
    % Generate individual plots by coverslip
    generatePPFIndividualPlots(organizedData, roiInfo, genotype, plotsIndividualFolder, timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg);
    
    % Generate averaged plots
    generatePPFAveragedPlots(averagedData, roiInfo, cleanGroupKey, genotype, plotsAveragedFolder, timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg);
    
    fprintf('    PPF plots complete for genotype %s\n', genotype);
end

function generatePPFIndividualPlots(organizedData, roiInfo, genotype, plotsFolder, timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg)
    % Generate individual PPF plots by coverslip
    
    dataVarNames = organizedData.Properties.VariableNames(2:end);
    if isempty(dataVarNames)
        return;
    end
    
    % Extract unique coverslip-cell combinations
    coverslipCells = {};
    for i = 1:length(dataVarNames)
        varName = dataVarNames{i};
        roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            csCell = roiMatch{1}{1};
            if ~ismember(csCell, coverslipCells)
                coverslipCells{end+1} = csCell;
            end
        end
    end
    
    % Create plots for each coverslip
    for csIdx = 1:length(coverslipCells)
        csCell = coverslipCells{csIdx};
        
        % Find ROIs for this coverslip
        csROIs = {};
        csPattern = [csCell '_ROI'];
        for i = 1:length(dataVarNames)
            if contains(dataVarNames{i}, csPattern)
                csROIs{end+1} = dataVarNames{i};
            end
        end
        
        if isempty(csROIs)
            continue;
        end
        
        % Create plots
        maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
        numFigures = ceil(length(csROIs) / maxPlotsPerFigure);
        
        for figNum = 1:numFigures
            try
                fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
                
                startROI = (figNum - 1) * maxPlotsPerFigure + 1;
                endROI = min(figNum * maxPlotsPerFigure, length(csROIs));
                
                [nRows, nCols] = calculateOptimalLayout(endROI - startROI + 1);
                
                for roiIdx = startROI:endROI
                    subplotIdx = roiIdx - startROI + 1;
                    varName = csROIs{roiIdx};
                    traceData = organizedData.(varName);
                    
                    subplot(nRows, nCols, subplotIdx);
                    hold on;
                    
                    % Plot in black
                    if ~all(isnan(traceData))
                        plot(timeData_ms, traceData, 'k-', 'LineWidth', 1.0);
                        
                        % Add threshold
                        threshold = getPPFROIThreshold(varName, roiInfo);
                        if isfinite(threshold)
                            plot([timeData_ms(1), timeData_ms(100)], [threshold, threshold], 'g--', 'LineWidth', 1.5);
                        end
                    end
                    
                    ylim(cfg.plotting.Y_LIMITS);
                    
                    % Add stimuli
                    plot([stimulusTime_ms1, stimulusTime_ms1], [cfg.plotting.Y_LIMITS(1), cfg.plotting.Y_LIMITS(1)], ':gpentagram', 'LineWidth', 1);
                    plot([stimulusTime_ms2, stimulusTime_ms2], [cfg.plotting.Y_LIMITS(1), cfg.plotting.Y_LIMITS(1)], ':cpentagram', 'LineWidth', 1);
                    
                    % Title
                    roiMatch = regexp(varName, '.*_ROI(\d+)', 'tokens');
                    if ~isempty(roiMatch)
                        title(sprintf('ROI %s', roiMatch{1}{1}), 'FontSize', 10, 'FontWeight', 'bold');
                    end
                    
                    xlabel('Time (ms)', 'FontSize', 8);
                    ylabel('ΔF/F', 'FontSize', 8);
                    grid on; box on;
                    hold off;
                end
                
                % Figure title and save
                if numFigures > 1
                    titleText = sprintf('PPF %dms %s %s (Part %d/%d)', roiInfo.timepoint, genotype, csCell, figNum, numFigures);
                    plotFile = sprintf('PPF_%dms_%s_%s_individual_part%d.png', roiInfo.timepoint, genotype, csCell, figNum);
                else
                    titleText = sprintf('PPF %dms %s %s', roiInfo.timepoint, genotype, csCell);
                    plotFile = sprintf('PPF_%dms_%s_%s_individual.png', roiInfo.timepoint, genotype, csCell);
                end
                
                sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold');
                print(fig, fullfile(plotsFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
                close(fig);
                
            catch ME
                fprintf('    ERROR in PPF individual plot: %s\n', ME.message);
                if exist('fig', 'var'), close(fig); end
            end
        end
    end
end

function generatePPFAveragedPlots(averagedData, roiInfo, cleanGroupKey, genotype, plotsFolder, timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg)
    % Generate PPF averaged plots with genotype-specific colors
    
    if width(averagedData) <= 1
        return;
    end
    
    avgVarNames = averagedData.Properties.VariableNames(2:end);
    numAvgPlots = length(avgVarNames);
    
    % Determine trace color
    if strcmp(genotype, 'WT')
        traceColor = cfg.colors.WT;
    elseif strcmp(genotype, 'R213W')
        traceColor = cfg.colors.R213W;
    else
        traceColor = [0, 0, 1]; % Blue for unknown
    end
    
    maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
    numAvgFigures = ceil(numAvgPlots / maxPlotsPerFigure);
    
    for figNum = 1:numAvgFigures
        try
            figAvg = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
            
            startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
            endPlot = min(figNum * maxPlotsPerFigure, numAvgPlots);
            
            [nRowsAvg, nColsAvg] = calculateOptimalLayout(endPlot - startPlot + 1);
            
            for plotIdx = startPlot:endPlot
                subplotIdx = plotIdx - startPlot + 1;
                
                subplot(nRowsAvg, nColsAvg, subplotIdx);
                hold on;
                
                varName = avgVarNames{plotIdx};
                avgData = averagedData.(varName);
                
                % Plot in genotype-specific color
                plot(timeData_ms, avgData, 'Color', traceColor, 'LineWidth', 1.0);
                
                % Add threshold
                avgThreshold = calculateAverageThreshold(avgData, cfg);
                if isfinite(avgThreshold)
                    plot([timeData_ms(1), timeData_ms(100)], [avgThreshold, avgThreshold], 'g--', 'LineWidth', 1.5);
                end
                
                % Title with genotype
                roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    title(sprintf('%s %s, n=%s', genotype, roiMatch{1}{1}, roiMatch{1}{2}), 'FontSize', 10, 'FontWeight', 'bold');
                else
                    title([genotype ' ' varName], 'FontSize', 10);
                end
                
                ylim([-0.005, 0.05]);
                
                % Add stimuli
                plot([stimulusTime_ms1, stimulusTime_ms1], [-0.005, -0.005], ':gpentagram', 'LineWidth', 1.0);
                plot([stimulusTime_ms2, stimulusTime_ms2], [-0.005, -0.005], ':cpentagram', 'LineWidth', 1.0);
                
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Figure title and save
            if numAvgFigures > 1
                titleText = sprintf('PPF %dms %s - Averaged (Part %d/%d)', roiInfo.timepoint, genotype, figNum, numAvgFigures);
                avgPlotFile = sprintf('PPF_%dms_%s_averaged_part%d.png', roiInfo.timepoint, genotype, figNum);
            else
                titleText = sprintf('PPF %dms %s - Averaged', roiInfo.timepoint, genotype);
                avgPlotFile = sprintf('PPF_%dms_%s_averaged.png', roiInfo.timepoint, genotype);
            end
            
            sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold');
            print(figAvg, fullfile(plotsFolder, avgPlotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
            close(figAvg);
            
        catch ME
            fprintf('    ERROR in PPF averaged plot: %s\n', ME.message);
            if exist('figAvg', 'var'), close(figAvg); end
        end
    end
end

function generateTotalAveragePlots(totalAveragedData, roiInfo, groupKey, plotsFolder)
    % Generate plots for total averages (1AP experiments)
    
    if width(totalAveragedData) <= 1
        return;
    end
    
    cfg = GluSnFRConfig();
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    timeData_ms = totalAveragedData.Frame;
    stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    
    varNames = totalAveragedData.Properties.VariableNames(2:end);
    
    try
        fig = figure('Position', [100, 100, 1200, 400], 'Visible', 'off', 'Color', 'white');
        
        hold on;
        legendHandles = [];
        legendLabels = {};
        
        for i = 1:length(varNames)
            varName = varNames{i};
            data = totalAveragedData.(varName);
            
            % Determine color and style
            if contains(varName, 'Low_Noise')
                color = [0.2, 0.6, 0.2];  % Green
                displayName = 'Low Noise';
            elseif contains(varName, 'High_Noise')
                color = [0.8, 0.2, 0.2];  % Red
                displayName = 'High Noise';
            elseif contains(varName, 'All_')
                color = [0.2, 0.2, 0.8];  % Blue
                displayName = 'All ROIs';
            else
                color = [0.5, 0.5, 0.5];  % Gray
                displayName = varName;
            end
            
            % Extract n count
            nMatch = regexp(varName, 'n(\d+)', 'tokens');
            if ~isempty(nMatch)
                displayName = sprintf('%s (n=%s)', displayName, nMatch{1}{1});
            end
            
            h = plot(timeData_ms, data, 'Color', color, 'LineWidth', 2);
            legendHandles(end+1) = h;
            legendLabels{end+1} = displayName;
        end
        
        % Add stimulus
        ylim(cfg.plotting.Y_LIMITS);
        hStim = plot([stimulusTime_ms, stimulusTime_ms], [cfg.plotting.Y_LIMITS(1), cfg.plotting.Y_LIMITS(1)], ':gpentagram', 'LineWidth', 1.0);
        legendHandles(end+1) = hStim;
        legendLabels{end+1} = 'Stimulus';
        
        title(sprintf('%s - Total Averages by Noise Level', cleanGroupKey), 'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
        xlabel('Time (ms)', 'FontSize', 12);
        ylabel('ΔF/F', 'FontSize', 12);
        grid on; box on;
        
        legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 10);
        hold off;
        
        plotFile = sprintf('%s_total_averages.png', cleanGroupKey);
        print(fig, fullfile(plotsFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
        close(fig);
        
        fprintf('    Generated total averages plot\n');
        
    catch ME
        fprintf('    ERROR creating total averages plot: %s\n', ME.message);
        if exist('fig', 'var'), close(fig); end
    end
end

function [nRows, nCols] = calculateOptimalLayout(nSubplots)
    % Calculate optimal subplot layout
    
    if nSubplots <= 2
        nRows = 2; nCols = 1;
    elseif nSubplots <= 4
        nRows = 2; nCols = 2;
    elseif nSubplots <= 6
        nRows = 2; nCols = 3;
    elseif nSubplots <= 9
        nRows = 3; nCols = 3;
    else
        nRows = 3; nCols = 4;
    end
end

function genotype = extractGenotypeFromGroupKey(groupKey)
    % Extract genotype from group key
    
    if contains(groupKey, 'R213W')
        genotype = 'R213W';
    elseif contains(groupKey, 'WT')
        genotype = 'WT';
    else
        genotype = 'Unknown';
    end
end

function threshold = getPPFROIThreshold(varName, roiInfo)
    % Get threshold for specific PPF ROI
    
    threshold = NaN;
    
    try
        roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            csCell = roiMatch{1}{1};
            roiNum = str2double(roiMatch{1}{2});
            
            for fileIdx = 1:length(roiInfo.coverslipFiles)
                fileData = roiInfo.coverslipFiles(fileIdx);
                if strcmp(fileData.coverslipCell, csCell)
                    roiIdx = find(fileData.roiNumbers == roiNum, 1);
                    if ~isempty(roiIdx) && roiIdx <= length(fileData.thresholds)
                        threshold = fileData.thresholds(roiIdx);
                        return;
                    end
                end
            end
        end
    catch
        threshold = NaN;
    end
end

function avgThreshold = calculateAverageThreshold(avgData, cfg)
    % Calculate threshold for averaged data
    
    baselineWindow = cfg.timing.BASELINE_FRAMES;
    
    if length(avgData) >= max(baselineWindow)
        baselineData = avgData(baselineWindow);
        avgThreshold = cfg.thresholds.SD_MULTIPLIER * std(baselineData, 'omitnan');
    else
        avgThreshold = NaN;
    end
    
    if ~isfinite(avgThreshold)
        avgThreshold = cfg.thresholds.DEFAULT_THRESHOLD;
    end
end