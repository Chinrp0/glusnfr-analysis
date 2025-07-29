function plotter = plot_generator()
    % PLOT_GENERATOR - Publication-ready plotting module
    % 
    % This module generates all plots for the pipeline:
    % - Individual trial plots
    % - ROI averaged plots  
    % - Total averaged plots
    % - PPF-specific plots with genotype color coding
    % - Consistent styling and layouts
    
    plotter.generateGroupPlots = @generateGroupPlots;
    plotter.generate1APPlots = @generate1APIndividualPlots;
    plotter.generatePPFPlots = @generatePPFIndividualPlots;
    plotter.generateAveragedPlots = @generateAveragedPlots;
    plotter.generateTotalAveragePlots = @generateTotalAveragePlots;
    plotter.calculateOptimalLayout = @calculateOptimalLayout;
end

function generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, plotsIndividualFolder, plotsAveragedFolder)
    % Main plot generation dispatcher
    
    cfg = GluSnFRConfig();
    utils = string_utils();
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    genotype = utils.extractGenotype(groupKey);
    
    if strcmp(roiInfo.experimentType, 'PPF')
        generatePPFGroupPlots(organizedData, averagedData, roiInfo, cleanGroupKey, genotype, ...
                             plotsIndividualFolder, plotsAveragedFolder, cfg);
    else
        % Create subfolders for better organization
        roiPlotsFolder = fullfile(plotsAveragedFolder, 'ROI_Averages');
        totalPlotsFolder = fullfile(plotsAveragedFolder, 'Total_Averages');
        
        if ~exist(roiPlotsFolder, 'dir'), mkdir(roiPlotsFolder); end
        if ~exist(totalPlotsFolder, 'dir'), mkdir(totalPlotsFolder); end
        
        generate1APGroupPlots(organizedData, averagedData.roi, roiInfo, cleanGroupKey, ...
                             plotsIndividualFolder, roiPlotsFolder, cfg);
        generateTotalAveragePlots(averagedData.total, roiInfo, cleanGroupKey, totalPlotsFolder, cfg);
    end
end

function generatePPFGroupPlots(organizedData, averagedData, roiInfo, cleanGroupKey, genotype, ...
                              plotsIndividualFolder, plotsAveragedFolder, cfg)
    % PPF-specific plotting with genotype color coding
    
    timeData_ms = organizedData.Frame;
    stimulusTime_ms1 = cfg.timing.STIMULUS_TIME_MS;
    stimulusTime_ms2 = stimulusTime_ms1 + roiInfo.timepoint;
    
    fprintf('    PPF plotting: %dms, genotype=%s\n', roiInfo.timepoint, genotype);
    
    % Generate individual plots by coverslip
    generatePPFIndividualPlots(organizedData, roiInfo, genotype, plotsIndividualFolder, ...
                              timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg);
    
    % Generate averaged plots
    generatePPFAveragedPlots(averagedData, roiInfo, cleanGroupKey, genotype, plotsAveragedFolder, ...
                            timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg);
end

function generatePPFIndividualPlots(organizedData, roiInfo, genotype, plotsFolder, ...
                                   timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg)
    % Generate individual PPF plots separated by coverslip
    
    dataVarNames = organizedData.Properties.VariableNames(2:end);
    
    if isempty(dataVarNames)
        fprintf('    No PPF data to plot\n');
        return;
    end
    
    % Extract unique coverslip combinations
    coverslipCells = {};
    for i = 1:length(dataVarNames)
        varName = dataVarNames{i};
        roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            csCell = roiMatch{1}{1};
            if ~any(strcmp(csCell, coverslipCells))
                coverslipCells{end+1} = csCell;
            end
        end
    end
    
    % Create separate plot for each coverslip
    for csIdx = 1:length(coverslipCells)
        csCell = coverslipCells{csIdx};
        
        % Find all ROIs for this coverslip
        csROIs = {};
        csPattern = [csCell '_ROI'];
        for i = 1:length(dataVarNames)
            varName = dataVarNames{i};
            if contains(varName, csPattern)
                csROIs{end+1} = varName;
            end
        end
        
        if isempty(csROIs)
            continue;
        end
        
        try
            % Calculate layout
            numROIs = length(csROIs);
            maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
            numFigures = ceil(numROIs / maxPlotsPerFigure);
            
            for figNum = 1:numFigures
                fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
                
                startROI = (figNum - 1) * maxPlotsPerFigure + 1;
                endROI = min(figNum * maxPlotsPerFigure, numROIs);
                numPlotsThisFig = endROI - startROI + 1;
                
                [nRows, nCols] = calculateOptimalLayout(numPlotsThisFig);
                
                for roiIdx = startROI:endROI
                    subplotIdx = roiIdx - startROI + 1;
                    varName = csROIs{roiIdx};
                    traceData = organizedData.(varName);
                    
                    subplot(nRows, nCols, subplotIdx);
                    hold on;
                    
                    % Plot trace in black
                    if ~all(isnan(traceData))
                        plot(timeData_ms, traceData, 'k-', 'LineWidth', 1.0);
                        
                        % Add threshold line
                        threshold = getPPFROIThreshold(varName, roiInfo);
                        if isfinite(threshold)
                            plot([timeData_ms(1), timeData_ms(100)], [threshold, threshold], ...
                                'Color', cfg.colors.THRESHOLD, 'LineStyle', '--', 'LineWidth', 1.5);
                        end
                    end
                    
                    % Set limits and add stimulus markers
                    ylim(cfg.plotting.Y_LIMITS);
                    addStimulusMarkers(stimulusTime_ms1, stimulusTime_ms2, cfg.plotting.Y_LIMITS(1), cfg);
                    
                    % ROI title
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
                    titleText = sprintf('PPI %dms %s %s (Part %d/%d)', ...
                                       roiInfo.timepoint, genotype, csCell, figNum, numFigures);
                    plotFile = sprintf('PPF_%dms_%s_%s_individual_part%d.png', ...
                                      roiInfo.timepoint, genotype, csCell, figNum);
                else
                    titleText = sprintf('PPI %dms %s %s', roiInfo.timepoint, genotype, csCell);
                    plotFile = sprintf('PPF_%dms_%s_%s_individual.png', ...
                                      roiInfo.timepoint, genotype, csCell);
                end
                
                sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold');
                print(fig, fullfile(plotsFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
                close(fig);
            end
            
        catch ME
            fprintf('    ERROR in PPF individual plot for %s: %s\n', csCell, ME.message);
            if exist('fig', 'var')
                close(fig);
            end
        end
    end
end

function generatePPFAveragedPlots(averagedData, roiInfo, cleanGroupKey, genotype, plotsFolder, ...
                                 timeData_ms, stimulusTime_ms1, stimulusTime_ms2, cfg)
    % Generate PPF averaged plots with genotype-specific colors
    
    if width(averagedData) <= 1
        return;
    end
    
    avgVarNames = averagedData.Properties.VariableNames(2:end);
    numAvgPlots = length(avgVarNames);
    
    % Determine trace color based on genotype
    if strcmp(genotype, 'WT')
        traceColor = cfg.colors.WT;
    elseif strcmp(genotype, 'R213W')
        traceColor = cfg.colors.R213W;
    else
        traceColor = [0.2, 0.2, 0.8]; % Blue for unknown
    end
    
    maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
    numFigures = ceil(numAvgPlots / maxPlotsPerFigure);
    
    for figNum = 1:numFigures
        try
            fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
            
            startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
            endPlot = min(figNum * maxPlotsPerFigure, numAvgPlots);
            numPlotsThisFig = endPlot - startPlot + 1;
            
            [nRows, nCols] = calculateOptimalLayout(numPlotsThisFig);
            
            for plotIdx = startPlot:endPlot
                subplotIdx = plotIdx - startPlot + 1;
                
                subplot(nRows, nCols, subplotIdx);
                hold on;
                
                varName = avgVarNames{plotIdx};
                avgData = averagedData.(varName);
                
                % Plot in genotype-specific color
                plot(timeData_ms, avgData, 'Color', traceColor, 'LineWidth', 2.0);
                
                % Add threshold line
                avgThreshold = calculateAveragedThreshold(avgData, cfg);
                if isfinite(avgThreshold)
                    plot([timeData_ms(1), timeData_ms(100)], [avgThreshold, avgThreshold], ...
                         'Color', cfg.colors.THRESHOLD, 'LineStyle', '--', 'LineWidth', 1.5);
                end
                
                % Title with genotype
                roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    csCell = roiMatch{1}{1};
                    nROIs = str2double(roiMatch{1}{2});
                    title(sprintf('%s %s, n=%d', genotype, csCell, nROIs), ...
                          'FontSize', 10, 'FontWeight', 'bold');
                end
                
                ylim([-0.005, 0.05]);
                addStimulusMarkers(stimulusTime_ms1, stimulusTime_ms2, -0.005, cfg);
                
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Title and save
            if numFigures > 1
                titleText = sprintf('PPI %dms %s - Averaged Traces (Part %d/%d)', ...
                                   roiInfo.timepoint, genotype, figNum, numFigures);
                plotFile = sprintf('PPF_%dms_%s_FoV_averaged_part%d.png', ...
                                  roiInfo.timepoint, genotype, figNum);
            else
                titleText = sprintf('PPI %dms %s - Averaged Traces', roiInfo.timepoint, genotype);
                plotFile = sprintf('PPF_%dms_%s_FoV_averaged.png', roiInfo.timepoint, genotype);
            end
            
            sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold');
            print(fig, fullfile(plotsFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
            close(fig);
            
        catch ME
            fprintf('    ERROR in PPF averaged plot %d: %s\n', figNum, ME.message);
            if exist('fig', 'var'), close(fig); end
        end
    end
end

function generate1APGroupPlots(organizedData, averagedData, roiInfo, cleanGroupKey, ...
                              plotsIndividualFolder, plotsAveragedFolder, cfg)
    % Generate 1AP individual and averaged plots
    
    timeData_ms = organizedData.Frame;
    stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    
    % Generate individual trial plots
    generate1APIndividualPlots(organizedData, roiInfo, cleanGroupKey, plotsIndividualFolder, ...
                              timeData_ms, stimulusTime_ms, cfg);
    
    % Generate ROI averaged plots
    generateROIAveragedPlots(averagedData, roiInfo, cleanGroupKey, plotsAveragedFolder, ...
                            timeData_ms, stimulusTime_ms, cfg);
end

function generate1APIndividualPlots(organizedData, roiInfo, cleanGroupKey, plotsFolder, ...
                                   timeData_ms, stimulusTime_ms, cfg)
    % Generate individual trial plots for 1AP experiments
    
    numROIs = length(roiInfo.roiNumbers);
    maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
    
    if numROIs == 0
        return;
    end
    
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
    
    uniqueTrials = unique(roiInfo.originalTrialNumbers);
    uniqueTrials = uniqueTrials(isfinite(uniqueTrials));
    uniqueTrials = sort(uniqueTrials);
    
    numFigures = ceil(numROIs / maxPlotsPerFigure);
    
    for figNum = 1:numFigures
        try
            fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
            
            startROI = (figNum - 1) * maxPlotsPerFigure + 1;
            endROI = min(figNum * maxPlotsPerFigure, numROIs);
            numPlotsThisFig = endROI - startROI + 1;
            
            [nRows, nCols] = calculateOptimalLayout(numPlotsThisFig);
            
            % Track legend
            legendHandles = [];
            legendLabels = {};
            
            for roiIdx = startROI:endROI
                subplotIdx = roiIdx - startROI + 1;
                roiNum = roiInfo.roiNumbers(roiIdx);
                
                subplot(nRows, nCols, subplotIdx);
                hold on;
                
                trialCount = 0;
                
                for i = 1:length(uniqueTrials)
                    trialNum = uniqueTrials(i);
                    colName = sprintf('ROI%d_T%g', roiNum, trialNum);
                    
                    if ismember(colName, organizedData.Properties.VariableNames)
                        trialData = organizedData.(colName);
                        if ~all(isnan(trialData))
                            trialCount = trialCount + 1;
                            
                            colorIdx = mod(i-1, size(trialColors, 1)) + 1;
                            h_line = plot(timeData_ms, trialData, 'Color', trialColors(colorIdx, :), ...
                                         'LineWidth', 1.0);
                            h_line.Color(4) = cfg.plotting.TRANSPARENCY;
                            
                            % Add to legend (first subplot only)
                            if subplotIdx == 1 && ~ismember(sprintf('Trial %g', trialNum), legendLabels)
                                legendHandles(end+1) = h_line;
                                legendLabels{end+1} = sprintf('Trial %g', trialNum);
                            end
                            
                            % Add individual threshold
                            trialIdx = find(roiInfo.originalTrialNumbers == trialNum, 1);
                            if ~isempty(trialIdx) && roiIdx <= size(roiInfo.thresholds, 1) && ...
                               trialIdx <= size(roiInfo.thresholds, 2) && ...
                               isfinite(roiInfo.thresholds(roiIdx, trialIdx))
                                threshold = roiInfo.thresholds(roiIdx, trialIdx);
                                plot([timeData_ms(1), timeData_ms(100)], [threshold, threshold], ...
                                     ':', 'Color', trialColors(colorIdx, :), 'LineWidth', 1.5, ...
                                     'HandleVisibility', 'off');
                            end
                        end
                    end
                end
                
                ylim(cfg.plotting.Y_LIMITS);
                addStimulusMarkers(stimulusTime_ms, NaN, cfg.plotting.Y_LIMITS(1), cfg);
                
                title(sprintf('ROI %d (n=%d)', roiNum, trialCount), 'FontSize', 10, 'FontWeight', 'bold');
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Add legend
            if ~isempty(legendHandles)
                try
                    legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 8);
                catch
                    % Legend failed, continue
                end
            end
            
            % Title and save
            if numFigures > 1
                titleText = sprintf('%s - Individual Trials (Part %d/%d)', cleanGroupKey, figNum, numFigures);
                plotFile = sprintf('%s_trials_part%d.png', cleanGroupKey, figNum);
            else
                titleText = sprintf('%s - Individual Trials', cleanGroupKey);
                plotFile = sprintf('%s_trials.png', cleanGroupKey);
            end
            
            sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
            print(fig, fullfile(plotsFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
            close(fig);
            
        catch ME
            fprintf('    ERROR creating 1AP trials plot %d: %s\n', figNum, ME.message);
            if exist('fig', 'var'), close(fig); end
        end
    end
end

function generateROIAveragedPlots(averagedData, roiInfo, cleanGroupKey, plotsFolder, ...
                                 timeData_ms, stimulusTime_ms, cfg)
    % Generate ROI averaged plots for 1AP experiments
    
    if width(averagedData) <= 1
        return;
    end
    
    avgVarNames = averagedData.Properties.VariableNames(2:end);
    numAvgPlots = length(avgVarNames);
    maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
    numFigures = ceil(numAvgPlots / maxPlotsPerFigure);
    
    for figNum = 1:numFigures
        try
            fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
            
            startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
            endPlot = min(figNum * maxPlotsPerFigure, numAvgPlots);
            numPlotsThisFig = endPlot - startPlot + 1;
            
            [nRows, nCols] = calculateOptimalLayout(numPlotsThisFig);
            
            for plotIdx = startPlot:endPlot
                subplotIdx = plotIdx - startPlot + 1;
                
                subplot(nRows, nCols, subplotIdx);
                hold on;
                
                varName = avgVarNames{plotIdx};
                avgData = averagedData.(varName);
                
                % Plot average trace
                plot(timeData_ms, avgData, 'k-', 'LineWidth', 2.0);
                
                % Add averaged threshold
                avgThreshold = calculateAveragedThreshold(avgData, cfg);
                if isfinite(avgThreshold)
                    plot([timeData_ms(1), timeData_ms(100)], [avgThreshold, avgThreshold], ...
                         'Color', cfg.colors.THRESHOLD, 'LineStyle', '--', 'LineWidth', 2);
                end
                
                roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    roiNum = str2double(roiMatch{1}{1});
                    nTrials = str2double(roiMatch{1}{2});
                    title(sprintf('ROI %d (n=%d)', roiNum, nTrials), 'FontSize', 10, 'FontWeight', 'bold');
                end
                
                ylim(cfg.plotting.Y_LIMITS);
                addStimulusMarkers(stimulusTime_ms, NaN, cfg.plotting.Y_LIMITS(1), cfg);
                
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Title and save
            if numFigures > 1
                titleText = sprintf('%s - Averaged Traces (Part %d/%d)', cleanGroupKey, figNum, numFigures);
                plotFile = sprintf('%s_averaged_part%d.png', cleanGroupKey, figNum);
            else
                titleText = sprintf('%s - Averaged Traces', cleanGroupKey);
                plotFile = sprintf('%s_averaged.png', cleanGroupKey);
            end
            
            sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
            print(fig, fullfile(plotsFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
            close(fig);
            
        catch ME
            fprintf('    ERROR creating averaged plot %d: %s\n', figNum, ME.message);
            if exist('fig', 'var'), close(fig); end
        end
    end
end

function generateTotalAveragePlots(totalAveragedData, roiInfo, cleanGroupKey, plotsFolder, cfg)
    % Generate total average plots by noise level
    
    if width(totalAveragedData) <= 1
        return;
    end
    
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
        
        ylim([-0.02, max(ylim)*1.1]);
        addStimulusMarkers(stimulusTime_ms, NaN, -0.02, cfg);
        
        title(sprintf('%s - Total Averages by Noise Level', cleanGroupKey), ...
              'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
        xlabel('Time (ms)', 'FontSize', 12);
        ylabel('ΔF/F', 'FontSize', 12);
        grid on; box on;
        
        legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 10);
        hold off;
        
        plotFile = sprintf('%s_total_averages.png', cleanGroupKey);
        print(fig, fullfile(plotsFolder, plotFile), '-dpng', sprintf('-r%d', cfg.plotting.DPI));
        close(fig);
        
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

function addStimulusMarkers(stimTime1, stimTime2, yPos, cfg)
    % Add stimulus markers to plots
    
    % First stimulus (green star)
    plot([stimTime1, stimTime1], [yPos, yPos], ':gpentagram', 'LineWidth', 1.0);
    
    % Second stimulus for PPF (cyan star)
    if nargin >= 2 && ~isnan(stimTime2) && isfinite(stimTime2)
        plot([stimTime2, stimTime2], [yPos, yPos], ':cpentagram', 'LineWidth', 1.0);
    end
end

function avgThreshold = calculateAveragedThreshold(avgData, cfg)
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

function writeTableWithHeaders(dataTable, filepath, sheetName, io, roiInfo, isTrialData)
    % Write table with appropriate headers based on experiment type
    
    if width(dataTable) <= 1 % Only Frame column
        return;
    end
    
    if strcmp(roiInfo.experimentType, 'PPF')
        [row1, row2] = createPPFHeaders(dataTable, roiInfo, isTrialData);
    else
        [row1, row2] = create1APHeaders(dataTable, roiInfo, isTrialData);
    end
    
    io.writeExcelWithHeaders(dataTable, filepath, sheetName, row1, row2);
end

function [row1, row2] = createPPFHeaders(dataTable, roiInfo, isTrialData)
    % Create headers for PPF data
    
    varNames = dataTable.Properties.VariableNames;
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    % First column
    row1{1} = sprintf('%dms', roiInfo.timepoint);
    row2{1} = 'Time (ms)';
    
    % Process other columns
    for i = 2:length(varNames)
        varName = varNames{i};
        
        if isTrialData
            % Format: Cs1-c2_ROI3
            roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
            if ~isempty(roiMatch)
                row1{i} = roiMatch{1}{1};  % Cs1-c2
                row2{i} = sprintf('ROI %s', roiMatch{1}{2});  % ROI 3
            end
        else
            % Format: Cs1-c2_n24
            roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
            if ~isempty(roiMatch)
                row1{i} = roiMatch{1}{2};  % 24
                row2{i} = roiMatch{1}{1};  % Cs1-c2
            end
        end
    end
end

function [row1, row2] = create1APHeaders(dataTable, roiInfo, isTrialData)
    % Create headers for 1AP data
    
    varNames = dataTable.Properties.VariableNames;
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    % First column
    if isTrialData
        row1{1} = 'Trial';
        row2{1} = 'Time (ms)';
    else
        row1{1} = 'n';
        row2{1} = 'Time (ms)';
    end
    
    % Process other columns
    for i = 2:length(varNames)
        varName = varNames{i};
        
        if isTrialData
            % Format: ROI123_T5
            roiMatch = regexp(varName, 'ROI(\d+)_T(\d+)', 'tokens');
            if ~isempty(roiMatch)
                row1{i} = roiMatch{1}{2};  % Trial number
                row2{i} = sprintf('ROI %s', roiMatch{1}{1});  % ROI number
            end
        else
            % Format: ROI123_n5 or Low_Noise_n15
            if contains(varName, 'ROI')
                roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    row1{i} = roiMatch{1}{2};  % n count
                    row2{i} = sprintf('ROI %s', roiMatch{1}{1});  % ROI number
                end
            else
                % Total averages
                nMatch = regexp(varName, 'n(\d+)', 'tokens');
                if ~isempty(nMatch)
                    row1{i} = nMatch{1}{1};  % n count
                    if contains(varName, 'Low_Noise')
                        row2{i} = 'Low Noise';
                    elseif contains(varName, 'High_Noise')
                        row2{i} = 'High Noise';
                    else
                        row2{i} = 'All';
                    end
                end
            end
        end
    end
end
