function plotPPF = plot_ppf()
    % PLOT_PPF - PPF experiment plotting functions with enhanced threshold styling
    
    plotPPF.execute = @executePlotTask;
    plotPPF.generateIndividual = @generateIndividualPlot;
    plotPPF.generateAveraged = @generateAveragedPlot;
end

function success = executePlotTask(task, config, varargin)
    % Execute a PPF plotting task with standardized signature
    
    success = false;
    
    try
        switch task.type
            case 'individual'
                success = generateIndividualPlot(task.data, config, ...
                    'roiInfo', task.roiInfo, 'groupKey', task.groupKey, ...
                    'outputFolder', task.outputFolder, varargin{:});
                    
            case 'averaged'
                success = generateAveragedPlot(task.data, config, ...
                    'roiInfo', task.roiInfo, 'groupKey', task.groupKey, ...
                    'outputFolder', task.outputFolder, 'plotSubtype', task.plotSubtype, varargin{:});
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    PPF plot task failed: %s\n', ME.message);
        end
        success = false;
    end
end

function success = generateIndividualPlot(organizedData, config, varargin)
    % Generate individual PPF plots by coverslip with enhanced threshold styling
    
    success = false;
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    parse(p, varargin{:});
    
    roiInfo = p.Results.roiInfo;
    groupKey = p.Results.groupKey;
    outputFolder = p.Results.outputFolder;
    
    if isempty(roiInfo) || isempty(groupKey) || isempty(outputFolder)
        return;
    end
    
    try
        utils = plot_utilities();
        plotConfig = utils.getPlotConfig(config);
        
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
        stimulusTime_ms1 = plotConfig.timing.STIMULUS_TIME_MS;
        genotype = utils.extractGenotype(groupKey);
        
        % Extract coverslip groups
        dataVarNames = plotData.Properties.VariableNames(2:end);
        coverslipCells = extractCoverslipCells(dataVarNames);
        
        if isempty(coverslipCells)
            return;
        end
        
        % Generate plots for each coverslip
        for csIdx = 1:length(coverslipCells)
            csCell = coverslipCells{csIdx};
            csROIs = findCoverslipROIs(dataVarNames, csCell);
            
            if ~isempty(csROIs)
                success = generateCoverslipIndividualPlots(plotData, csROIs, csCell, genotype, ...
                    roiInfo, outputFolder, utils, plotConfig) || success;
            end
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateIndividualPlot error: %s\n', ME.message);
        end
        success = false;
    end
end

function success = generateCoverslipIndividualPlots(plotData, csROIs, csCell, genotype, ...
    roiInfo, outputFolder, utils, plotConfig)
    % Generate individual plots for one coverslip with enhanced threshold styling
    
    success = false;
    
    try
        timeData_ms = plotData.Frame;
        stimulusTime_ms1 = plotConfig.timing.STIMULUS_TIME_MS;
        
        numFigures = ceil(length(csROIs) / plotConfig.maxPlotsPerFigure);
        
        for figNum = 1:numFigures
            success = generateCoverslipFigure(figNum, numFigures, csROIs, plotData, csCell, ...
                genotype, roiInfo, timeData_ms, stimulusTime_ms1, outputFolder, utils, plotConfig) || success;
        end
        
    catch ME
        if plotConfig.colors && isfield(plotConfig, 'debug') && plotConfig.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateCoverslipIndividualPlots error: %s\n', ME.message);
        end
        success = false;
    end
end

function success = generateCoverslipFigure(figNum, numFigures, csROIs, plotData, csCell, ...
    genotype, roiInfo, timeData_ms, stimulusTime_ms1, outputFolder, utils, plotConfig)
    % OPTIMIZED: Use pre-calculated thresholds and noise levels
    
    success = false;
    
    % Calculate ROI range for this figure
    startROI = (figNum - 1) * plotConfig.maxPlotsPerFigure + 1;
    endROI = min(figNum * plotConfig.maxPlotsPerFigure, length(csROIs));
    numPlotsThisFig = endROI - startROI + 1;
    
    [nRows, nCols] = utils.calculateLayout(numPlotsThisFig);
    
    fig = utils.createFigure('standard');
    hasData = false;
    
    for roiIdx = startROI:endROI
        subplotIdx = roiIdx - startROI + 1;
        varName = csROIs{roiIdx};
        traceData = plotData.(varName);
        
        subplot(nRows, nCols, subplotIdx);
        hold on;
        
        if ~all(isnan(traceData))
            hasData = true;
            
            % Determine trace color based on peak response type
            isSinglePeak = checkIfSinglePeakROI(varName, csCell, roiInfo);
            if isSinglePeak
                traceColor = [0.8, 0.2, 0.2]; % Red for single peak
            else
                traceColor = [0, 0, 0]; % Black for both peaks
            end
            
            plot(timeData_ms, traceData, 'Color', traceColor, 'LineWidth', plotConfig.lines.trace);
            
            % OPTIMIZED: Get pre-calculated threshold and noise level
            [threshold, roiNoiseLevel, upperThreshold, lowerThreshold] = ...
                getPPFROIData(varName, roiInfo);
            
            % Use upper threshold for display if available
            displayThreshold = threshold;
            if ~isnan(upperThreshold)
                displayThreshold = upperThreshold;
            end
            
            % Add threshold and stimulus markers with optimized styling
            utils.addPlotElements(timeData_ms, stimulusTime_ms1, displayThreshold, plotConfig, ...
                'ShowStimulus', true, 'ShowThreshold', true, ...
                'PPFTimepoint', roiInfo.timepoint, ...
                'PlotType', 'individual', 'NoiseLevel', roiNoiseLevel, ...
                'TraceColor', traceColor, 'UpperThreshold', upperThreshold, ...
                'LowerThreshold', lowerThreshold);
        end
        
        % Format title with pre-calculated values
        roiMatch = regexp(varName, '.*_ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            roiTitle = sprintf('ROI %s', roiMatch{1}{1});
            if checkIfSinglePeakROI(varName, csCell, roiInfo)
                roiTitle = sprintf('%s (SP)', roiTitle);
            end
            
            % Add noise level indicator using pre-calculated value
            [~, roiNoiseLevel] = getPPFROIData(varName, roiInfo);
            if strcmp(roiNoiseLevel, 'low')
                roiTitle = sprintf('%s (Low)', roiTitle);
            elseif strcmp(roiNoiseLevel, 'high')
                roiTitle = sprintf('%s (High)', roiTitle);
            end
            
            title(roiTitle, 'FontSize', plotConfig.fonts.subtitle, 'FontWeight', 'bold');
        end
        
        utils.formatSubplot(plotConfig);
        
        % Add legend for first subplot only
        if subplotIdx == 1 && hasData
            utils.createLegend('genotype', plotConfig, 'Genotype', genotype, ...
                'IncludeStimulus', true, 'IncludeThreshold', true, 'FontSize', 9);
        end
        
        hold off;
    end
    
    % Save figure if it has data
    if hasData
        if numFigures > 1
            titleText = sprintf('PPF %dms %s %s (Part %d/%d)', roiInfo.timepoint, genotype, csCell, figNum, numFigures);
            filename = sprintf('PPF_%dms_%s_%s_individual_part%d.png', roiInfo.timepoint, genotype, csCell, figNum);
        else
            titleText = sprintf('PPF %dms %s %s', roiInfo.timepoint, genotype, csCell);
            filename = sprintf('PPF_%dms_%s_%s_individual.png', roiInfo.timepoint, genotype, csCell);
        end
        
        sgtitle(titleText, 'FontSize', plotConfig.fonts.title, 'FontWeight', 'bold');
        
        filepath = fullfile(outputFolder, filename);
        success = utils.savePlot(fig, filepath, plotConfig);
    end
    
    close(fig);
end

function [threshold, noiseLevel, upperThreshold, lowerThreshold, standardDeviation] = getPPFROIData(varName, roiInfo)
% RETRIEVE ONLY: Get all PPF ROI data using existing ROI number extraction
    % NO FALLBACK CALCULATIONS - return defaults if data not available
    
    threshold = NaN;
    noiseLevel = 'unknown';
    upperThreshold = NaN;
    lowerThreshold = NaN;
    
    % Extract coverslip and ROI info
    roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
    if isempty(roiMatch)
        return;
    end
    
    csCell = roiMatch{1}{1};
    roiNum = str2double(roiMatch{1}{2});
    
    % RETRIEVE from pre-calculated filtering statistics using ROI number as key
    if isfield(roiInfo, 'filteringStats') && roiInfo.filteringStats.available
        
        % Get noise level (pre-calculated)
        if isfield(roiInfo.filteringStats, 'roiNoiseMap') && ...
           isa(roiInfo.filteringStats.roiNoiseMap, 'containers.Map') && ...
           isKey(roiInfo.filteringStats.roiNoiseMap, roiNum)
            noiseLevel = roiInfo.filteringStats.roiNoiseMap(roiNum);
        end
        
        % Get upper threshold (pre-calculated)
        if isfield(roiInfo.filteringStats, 'roiUpperThresholds') && ...
           isa(roiInfo.filteringStats.roiUpperThresholds, 'containers.Map') && ...
           isKey(roiInfo.filteringStats.roiUpperThresholds, roiNum)
            upperThreshold = roiInfo.filteringStats.roiUpperThresholds(roiNum);
        end
        
        % Get lower threshold (pre-calculated)
        if isfield(roiInfo.filteringStats, 'roiLowerThresholds') && ...
           isa(roiInfo.filteringStats.roiLowerThresholds, 'containers.Map') && ...
           isKey(roiInfo.filteringStats.roiLowerThresholds, roiNum)
            lowerThreshold = roiInfo.filteringStats.roiLowerThresholds(roiNum);
        end
        
        % Get basic threshold (pre-calculated)
        if isfield(roiInfo.filteringStats, 'roiStandardDeviations') && ...
           isa(roiInfo.filteringStats.roiStandardDeviations, 'containers.Map') && ...
           isKey(roiInfo.filteringStats.roiStandardDeviations, roiNum)
            standardDeviation = roiInfo.filteringStats.roiStandardDeviations(roiNum);
            % Calculate threshold from standard deviation if needed for display
            if strcmp(noiseLevel, 'low')
                threshold = 3.0 * standardDeviation;  % Use config values
            else
                threshold = 3.5 * standardDeviation;  % Use config values  
            end
        end
        
        % If we have all pre-calculated data, we're done
        if ~strcmp(noiseLevel, 'unknown') && ~isnan(upperThreshold)
            return;
        end
    end
    
    % NO FALLBACK CALCULATIONS - if data isn't pre-calculated, return defaults
end

function success = generateAveragedPlot(averagedData, config, varargin)
    % Generate PPF averaged plots with enhanced threshold styling
    
    success = false;
    
    % Parse inputs
    p = inputParser;
    addParameter(p, 'roiInfo', [], @isstruct);
    addParameter(p, 'groupKey', '', @ischar);
    addParameter(p, 'outputFolder', '', @ischar);
    addParameter(p, 'plotSubtype', 'AllData', @ischar);
    parse(p, varargin{:});
    
    roiInfo = p.Results.roiInfo;
    groupKey = p.Results.groupKey;
    outputFolder = p.Results.outputFolder;
    plotSubtype = p.Results.plotSubtype;
    
    if isempty(roiInfo) || isempty(groupKey) || isempty(outputFolder)
        return;
    end
    
    try
        utils = plot_utilities();
        plotConfig = utils.getPlotConfig(config);
        
        cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
        genotype = utils.extractGenotype(groupKey);
        
        if width(averagedData) <= 1
            return;
        end
        
        timeData_ms = averagedData.Frame;
        stimulusTime_ms1 = plotConfig.timing.STIMULUS_TIME_MS;
        
        avgVarNames = averagedData.Properties.VariableNames(2:end);
        numAvgPlots = length(avgVarNames);
        numFigures = ceil(numAvgPlots / plotConfig.maxPlotsPerFigure);
        
        % Determine trace color based on plot type and genotype
        traceColor = getPPFTraceColor(plotSubtype, genotype, plotConfig);
        
        % Generate figures
        for figNum = 1:numFigures
            success = generateAveragedFigure(figNum, numFigures, avgVarNames, averagedData, ...
                timeData_ms, stimulusTime_ms1, genotype, plotSubtype, traceColor, ...
                roiInfo, cleanGroupKey, outputFolder, utils, plotConfig) || success;
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    generateAveragedPlot error: %s\n', ME.message);
        end
        success = false;
    end
end

function success = generateAveragedFigure(figNum, numFigures, avgVarNames, averagedData, ...
    timeData_ms, stimulusTime_ms1, genotype, plotSubtype, traceColor, ...
    roiInfo, cleanGroupKey, outputFolder, utils, plotConfig)
    % Generate a single averaged figure with enhanced threshold styling
    
    success = false;
    
    % Calculate plot range for this figure
    startPlot = (figNum - 1) * plotConfig.maxPlotsPerFigure + 1;
    endPlot = min(figNum * plotConfig.maxPlotsPerFigure, length(avgVarNames));
    numPlotsThisFig = endPlot - startPlot + 1;
    
    [nRows, nCols] = utils.calculateLayout(numPlotsThisFig);
    
    fig = utils.createFigure('standard');
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
            
            % Calculate threshold for averaged data
            avgThreshold = calculateAverageThreshold(avgData, plotConfig, config);

            
            % ENHANCED: Use average plot type to get green threshold for averages
            utils.addPlotElements(timeData_ms, stimulusTime_ms1, avgThreshold, plotConfig, ...
                'ShowStimulus', true, 'ShowThreshold', true, ...
                'PPFTimepoint', roiInfo.timepoint, ...
                'PlotType', 'average', 'TraceColor', traceColor);
        end
        
        % Format title with genotype and plot type
        roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
        if ~isempty(roiMatch)
            titleStr = sprintf('%s %s, n=%s', genotype, roiMatch{1}{1}, roiMatch{1}{2});
            if strcmp(plotSubtype, 'BothPeaks')
                titleStr = sprintf('%s (Both Peaks)', titleStr);
            elseif strcmp(plotSubtype, 'SinglePeak')
                titleStr = sprintf('%s (Single Peak)', titleStr);
            end
            title(titleStr, 'FontSize', plotConfig.fonts.subtitle, 'FontWeight', 'bold');
        else
            title([genotype ' ' varName], 'FontSize', plotConfig.fonts.subtitle);
        end
        
        utils.formatSubplot(plotConfig);
        hold off;
    end
    
    % Save figure if it has data
    if hasData
        typeLabel = getPlotTypeLabel(plotSubtype);
        
        if numFigures > 1
            titleText = sprintf('PPF %dms %s - %s Averaged (Part %d/%d)', roiInfo.timepoint, genotype, typeLabel, figNum, numFigures);
            filename = sprintf('PPF_%dms_%s_%s_averaged_part%d.png', roiInfo.timepoint, genotype, plotSubtype, figNum);
        else
            titleText = sprintf('PPF %dms %s - %s Averaged', roiInfo.timepoint, genotype, typeLabel);
            filename = sprintf('PPF_%dms_%s_%s_averaged.png', roiInfo.timepoint, genotype, plotSubtype);
        end
        
        sgtitle(titleText, 'FontSize', plotConfig.fonts.title, 'FontWeight', 'bold');
        
        filepath = fullfile(outputFolder, filename);
        success = utils.savePlot(fig, filepath, plotConfig);
    end
    
    close(fig);
end

% Helper functions
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


function traceColor = getPPFTraceColor(plotSubtype, genotype, plotConfig)
    % Get appropriate trace color for PPF plots
    
    if strcmp(plotSubtype, 'SinglePeak')
        traceColor = [0.8, 0.2, 0.2]; % Red for single peak
    else
        % Use genotype-specific colors
        if strcmp(genotype, 'WT')
            traceColor = plotConfig.colors.wt;
        elseif strcmp(genotype, 'R213W')
            traceColor = plotConfig.colors.r213w;
        else
            traceColor = [0, 0, 1]; % Blue for unknown
        end
    end
end

function typeLabel = getPlotTypeLabel(plotSubtype)
    % Get display label for plot type
    
    switch plotSubtype
        case 'AllData'
            typeLabel = 'All Data';
        case 'BothPeaks'
            typeLabel = 'Both Peaks';
        case 'SinglePeak'
            typeLabel = 'Single Peak';
        otherwise
            typeLabel = plotSubtype;
    end
end

function avgThreshold = calculateAverageThreshold(avgData, plotConfig, cfg)
    % CALCULATEAVERAGETHRESHOLD - Calculate threshold for averaged data using config
    % 
    % This function should REPLACE the existing calculateAverageThreshold
    % in both plot_1ap.m (around line 410) and plot_ppf.m (around line 619)
    %
    % INPUTS:
    %   avgData - averaged trace data
    %   plotConfig - plot configuration structure  
    %   cfg - main GluSnFR configuration (optional)
    %
    % OUTPUT:
    %   avgThreshold - calculated threshold for averaged data
    
    % Get config if not provided
    if nargin < 3
        cfg = GluSnFRConfig();
    end
    
    % Use baseline window from config
    baselineWindow = cfg.timing.BASELINE_FRAMES;
    
    % Ensure we have valid data for baseline
    if length(avgData) >= max(baselineWindow)
        baselineData = avgData(baselineWindow);
        
        % Calculate threshold using CONFIG multiplier, not hardcoded 3.0
        baselineSD = std(baselineData, 'omitnan');
        avgThreshold = cfg.thresholds.SD_MULTIPLIER * baselineSD;
    else
        % Not enough data for baseline calculation
        avgThreshold = NaN;
    end
    
    % Apply default threshold if calculation failed
    if ~isfinite(avgThreshold)
        avgThreshold = cfg.thresholds.DEFAULT_THRESHOLD;
    end
end