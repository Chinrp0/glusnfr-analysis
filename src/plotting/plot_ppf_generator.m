function plotPPF = plot_ppf_generator()
    % PLOT_PPF_GENERATOR - Complete PPF plotting implementation
    
    plotPPF.generateSequential = @generatePPFSequential;
    plotPPF.generateIndividualPlots = @generatePPFIndividualPlots;
    plotPPF.generateAveragedPlots = @generatePPFAveragedPlots;
    plotPPF.generateParallel = @generatePPFParallel;
end

function generatePPFSequential(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Sequential PPF plot generation
    
    plotsGenerated = 0;
    
    % Individual plots
    if hasValidPPFData(organizedData)
        success = generatePPFIndividualPlots(organizedData, roiInfo, groupKey, outputFolders.roi_trials);
        if success, plotsGenerated = plotsGenerated + 1; end
    end
    
    % Averaged plots
    if isstruct(averagedData)
        % All Data averaged
        if isfield(averagedData, 'allData') && width(averagedData.allData) > 1
            success = generatePPFAveragedPlots(averagedData.allData, roiInfo, groupKey, outputFolders.coverslip_averages, 'AllData');
            if success, plotsGenerated = plotsGenerated + 1; end
        end
        
        % Both Peaks averaged
        if isfield(averagedData, 'bothPeaks') && width(averagedData.bothPeaks) > 1
            success = generatePPFAveragedPlots(averagedData.bothPeaks, roiInfo, groupKey, outputFolders.coverslip_averages, 'BothPeaks');
            if success, plotsGenerated = plotsGenerated + 1; end
        end
    end
    
    fprintf('    Generated %d PPF plots successfully\n', plotsGenerated);
end

function generatePPFParallel(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Parallel PPF plot generation
    
    tasks = createPPFPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    
    if isempty(tasks)
        return;
    end
    
    pool = gcp('nocreate');
    if ~isempty(pool) && length(tasks) > 1
        futures = cell(length(tasks), 1);
        
        for i = 1:length(tasks)
            futures{i} = parfeval(pool, @executePPFPlotTask, 1, tasks{i});
        end
        
        plotsGenerated = 0;
        for i = 1:length(tasks)
            try
                success = fetchOutputs(futures{i});
                if success, plotsGenerated = plotsGenerated + 1; end
            catch
                % Silent failure
            end
        end
        
        fprintf('    Generated %d/%d PPF plots (parallel)\n', plotsGenerated, length(tasks));
    else
        generatePPFSequential(organizedData, averagedData, roiInfo, groupKey, outputFolders);
    end
end

function tasks = createPPFPlotTasks(organizedData, averagedData, roiInfo, groupKey, outputFolders)
    % Create PPF plotting tasks
    
    tasks = {};
    
    % Individual plots task
    if hasValidPPFData(organizedData)
        tasks{end+1} = struct('type', 'individual', 'data', getPrimaryPPFData(organizedData), ...
                             'roiInfo', roiInfo, 'groupKey', groupKey, ...
                             'outputFolder', outputFolders.roi_trials);
    end
    
    % Averaged plots tasks
    if isstruct(averagedData)
        if isfield(averagedData, 'allData') && width(averagedData.allData) > 1
            tasks{end+1} = struct('type', 'averaged_alldata', 'data', averagedData.allData, ...
                                 'roiInfo', roiInfo, 'groupKey', groupKey, ...
                                 'outputFolder', outputFolders.coverslip_averages, ...
                                 'plotType', 'AllData');
        end
        
        if isfield(averagedData, 'bothPeaks') && width(averagedData.bothPeaks) > 1
            tasks{end+1} = struct('type', 'averaged_bothpeaks', 'data', averagedData.bothPeaks, ...
                                 'roiInfo', roiInfo, 'groupKey', groupKey, ...
                                 'outputFolder', outputFolders.coverslip_averages, ...
                                 'plotType', 'BothPeaks');
        end
    end
end

function success = executePPFPlotTask(task)
    % Execute PPF plotting task
    
    success = false;
    
    try
        switch task.type
            case 'individual'
                success = generatePPFIndividualPlots(task.data, task.roiInfo, task.groupKey, task.outputFolder);
            case {'averaged_alldata', 'averaged_bothpeaks'}
                success = generatePPFAveragedPlots(task.data, task.roiInfo, task.groupKey, task.outputFolder, task.plotType);
        end
    catch
        success = false;
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

function success = generatePPFIndividualPlots(organizedData, roiInfo, groupKey, plotsFolder)
    % Generate individual PPF plots by coverslip
    
    success = false;
    
    try
        cfg = GluSnFRConfig();
        utils = plot_utils();
        
        % Get the data to plot
        if isstruct(organizedData)
            plotData = getPrimaryPPFData(organizedData);
        else
            plotData = organizedData;
        end
        
        if isempty(plotData) || ~istable(plotData) || width(plotData) <= 1
            return;
        end
        
        timeData_ms = plotData.Frame;
        stimulusTime_ms1 = cfg.timing.STIMULUS_TIME_MS;
        stimulusTime_ms2 = stimulusTime_ms1 + roiInfo.timepoint;
        
        % Extract genotype
        genotype = utils.extractGenotypeFromGroupKey(groupKey);
        
        % Extract coverslip groups
        dataVarNames = plotData.Properties.VariableNames(2:end);
        coverslipCells = extractCoverslipCells(dataVarNames);
        
        if isempty(coverslipCells)
            return;
        end
        
        % Generate plots for each coverslip
        for csIdx = 1:length(coverslipCells)
            csCell = coverslipCells{csIdx};
            
            % Find ROIs for this coverslip
            csROIs = findCoverslipROIs(dataVarNames, csCell);
            
            if isempty(csROIs)
                continue;
            end
            
            success = generateCoverslipIndividualPlots(plotData, csROIs, csCell, genotype, roiInfo, plotsFolder, cfg, utils) || success;
        end
        
    catch
        success = false;
    end
end

function coverslipCells = extractCoverslipCells(dataVarNames)
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
end

function csROIs = findCoverslipROIs(dataVarNames, csCell)
    % Find ROI variables for specific coverslip
    
    csROIs = {};
    csPattern = [csCell '_ROI'];
    
    for i = 1:length(dataVarNames)
        if contains(dataVarNames{i}, csPattern)
            csROIs{end+1} = dataVarNames{i};
        end
    end
end

function success = generateCoverslipIndividualPlots(plotData, csROIs, csCell, genotype, roiInfo, plotsFolder, cfg, utils)
    % Generate individual plots for one coverslip
    
    success = false;
    
    try
        timeData_ms = plotData.Frame;
        stimulusTime_ms1 = cfg.timing.STIMULUS_TIME_MS;
        stimulusTime_ms2 = stimulusTime_ms1 + roiInfo.timepoint;
        
        maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
        numFigures = ceil(length(csROIs) / maxPlotsPerFigure);
        
        for figNum = 1:numFigures
            fig = utils.createStandardFigure('standard');
            
            startROI = (figNum - 1) * maxPlotsPerFigure + 1;
            endROI = min(figNum * maxPlotsPerFigure, length(csROIs));
            
            [nRows, nCols] = utils.calculateOptimalLayout(endROI - startROI + 1);
            hasData = false;
            
            for roiIdx = startROI:endROI
                subplotIdx = roiIdx - startROI + 1;
                varName = csROIs{roiIdx};
                traceData = plotData.(varName);
                
                subplot(nRows, nCols, subplotIdx);
                hold on;
                
                if ~all(isnan(traceData))
                    hasData = true;
                    
                    % Determine trace color (red for single peak, black for others)
                    if checkIfSinglePeakROI(varName, csCell, roiInfo)
                        traceColor = [0.8, 0.2, 0.2]; % Red for single peak
                    else
                        traceColor = [0, 0, 0]; % Black for both peaks
                    end
                    
                    plot(timeData_ms, traceData, 'Color', traceColor, 'LineWidth', 1.0);
                    
                    % Add threshold
                    threshold = getPPFROIThreshold(varName, roiInfo);
                    utils.addStandardElements(timeData_ms, stimulusTime_ms1, threshold, cfg, ...
                                            'PPFTimepoint', roiInfo.timepoint);
                end
                
                % Title
                roiMatch = regexp(varName, '.*_ROI(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    roiTitle = sprintf('ROI %s', roiMatch{1}{1});
                    if checkIfSinglePeakROI(varName, csCell, roiInfo)
                        roiTitle = sprintf('%s (SP)', roiTitle);
                    end
                    title(roiTitle, 'FontSize', 10, 'FontWeight', 'bold');
                end
                
                hold off;
            end
            
            % Save if we have data
            if hasData
                if numFigures > 1
                    titleText = sprintf('PPF %dms %s %s (Part %d/%d)', roiInfo.timepoint, genotype, csCell, figNum, numFigures);
                    plotFile = sprintf('PPF_%dms_%s_%s_individual_part%d.png', roiInfo.timepoint, genotype, csCell, figNum);
                else
                    titleText = sprintf('PPF %dms %s %s', roiInfo.timepoint, genotype, csCell);
                    plotFile = sprintf('PPF_%dms_%s_%s_individual.png', roiInfo.timepoint, genotype, csCell);
                end
                
                sgtitle(titleText, 'FontSize', 12, 'FontWeight', 'bold');
                utils.savePlotWithFormat(fig, fullfile(plotsFolder, plotFile), cfg);
                success = true;
            end
            
            close(fig);
        end
        
    catch
        success = false;
    end
end

function success = generatePPFAveragedPlots(averagedData, roiInfo, groupKey, plotsFolder, plotType)
    % Generate PPF averaged plots
    
    success = false;
    
    try
        cfg = GluSnFRConfig();
        utils = plot_utils();
        
        if nargin < 5, plotType = 'AllData'; end
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        genotype = utils.extractGenotypeFromGroupKey(groupKey);
        
        if width(averagedData) <= 1
            return;
        end
        
        timeData_ms = averagedData.Frame;
        stimulusTime_ms1 = cfg.timing.STIMULUS_TIME_MS;
        stimulusTime_ms2 = stimulusTime_ms1 + roiInfo.timepoint;
        
        avgVarNames = averagedData.Properties.VariableNames(2:end);
        numAvgPlots = length(avgVarNames);
        
        % Determine trace color
        traceColor = getPPFTraceColor(plotType, genotype, cfg);
        
        maxPlotsPerFigure = cfg.plotting.MAX_PLOTS_PER_FIGURE;
        numFigures = ceil(numAvgPlots / maxPlotsPerFigure);
        
        for figNum = 1:numFigures
            fig = utils.createStandardFigure('standard');
            
            startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
            endPlot = min(figNum * maxPlotsPerFigure, numAvgPlots);
            
            [nRows, nCols] = utils.calculateOptimalLayout(endPlot - startPlot + 1);
            hasData = false;
            
            for plotIdx = startPlot:endPlot
                subplotIdx = plotIdx - startPlot + 1;
                
                subplot(nRows, nCols, subplotIdx);
                hold on;
                
                varName = avgVarNames{plotIdx};
                avgData = averagedData.(varName);
                
                if ~all(isnan(avgData))
                    hasData = true;
                    
                    plot(timeData_ms, avgData, 'Color', traceColor, 'LineWidth', 2.0);
                    
                    % Add threshold and stimuli
                    avgThreshold = calculatePPFAverageThreshold(avgData, cfg);
                    utils.addStandardElements(timeData_ms, stimulusTime_ms1, avgThreshold, cfg, ...
                                            'PPFTimepoint', roiInfo.timepoint);
                end
                
                % Title with genotype and plot type
                roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    titleStr = sprintf('%s %s, n=%s', genotype, roiMatch{1}{1}, roiMatch{1}{2});
                    if strcmp(plotType, 'BothPeaks')
                        titleStr = sprintf('%s (Both Peaks)', titleStr);
                    elseif strcmp(plotType, 'SinglePeak')
                        titleStr = sprintf('%s (Single Peak)', titleStr);
                    end
                    title(titleStr, 'FontSize', 10, 'FontWeight', 'bold');
                else
                    title([genotype ' ' varName], 'FontSize', 10);
                end
                
                hold off;
            end
            
            % Save if we have data
            if hasData
                typeLabel = getPlotTypeLabel(plotType);
                
                if numFigures > 1
                    titleText = sprintf('PPF %dms %s - %s Averaged (Part %d/%d)', roiInfo.timepoint, genotype, typeLabel, figNum, numFigures);
                    plotFile = sprintf('PPF_%dms_%s_%s_averaged_part%d.png', roiInfo.timepoint, genotype, plotType, figNum);
                else
                    titleText = sprintf('PPF %dms %s - %s Averaged', roiInfo.timepoint, genotype, typeLabel);
                    plotFile = sprintf('PPF_%dms_%s_%s_averaged.png', roiInfo.timepoint, genotype, plotType);
                end
                
                sgtitle(titleText, 'FontSize', 12, 'FontWeight', 'bold');
                utils.savePlotWithFormat(fig, fullfile(plotsFolder, plotFile), cfg);
                success = true;
            end
            
            close(fig);
        end
        
    catch
        success = false;
    end
end

function traceColor = getPPFTraceColor(plotType, genotype, cfg)
    % Get appropriate trace color for PPF plots
    
    if strcmp(plotType, 'SinglePeak')
        traceColor = [0.8, 0.2, 0.2]; % Red for single peak
    else
        % Use genotype-specific colors
        if strcmp(genotype, 'WT')
            traceColor = cfg.colors.WT;
        elseif strcmp(genotype, 'R213W')
            traceColor = cfg.colors.R213W;
        else
            traceColor = [0, 0, 1]; % Blue for unknown
        end
    end
end

function typeLabel = getPlotTypeLabel(plotType)
    % Get display label for plot type
    
    switch plotType
        case 'AllData'
            typeLabel = 'All Data';
        case 'BothPeaks'
            typeLabel = 'Both Peaks';
        case 'SinglePeak'
            typeLabel = 'Single Peak';
        otherwise
            typeLabel = plotType;
    end
end

function isSinglePeak = checkIfSinglePeakROI(varName, csCell, roiInfo)
    % Check if ROI is classified as single peak
    
    isSinglePeak = false;
    
    try
        roiMatch = regexp(varName, 'ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            
            for fileIdx = 1:length(roiInfo.coverslipFiles)
                fileData = roiInfo.coverslipFiles(fileIdx);
                if strcmp(fileData.coverslipCell, csCell)
                    roiIdx = find(fileData.roiNumbers == roiNum, 1);
                    
                    if ~isempty(roiIdx) && ~isempty(fileData.peakResponses)
                        isPeak1Only = roiIdx <= length(fileData.peakResponses.filteredPeak1Only) && ...
                                      fileData.peakResponses.filteredPeak1Only(roiIdx);
                        isPeak2Only = roiIdx <= length(fileData.peakResponses.filteredPeak2Only) && ...
                                      fileData.peakResponses.filteredPeak2Only(roiIdx);
                        
                        isSinglePeak = isPeak1Only || isPeak2Only;
                        return;
                    end
                end
            end
        end
    catch
        isSinglePeak = false;
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

function avgThreshold = calculatePPFAverageThreshold(avgData, cfg)
    % Calculate threshold for PPF averaged data
    
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