function analyzer = experiment_analyzer()
    % EXPERIMENT_ANALYZER - Experiment-specific analysis module
    % 
    % Updated to use upper thresholds in metadata instead of basic thresholds
    

    analyzer.generateMetadata = @generateExperimentMetadata;
    analyzer.validateResults = @validateExperimentResults;
    analyzer.calculateStatistics = @calculateExperimentStatistics;
    analyzer.createSummary = @createResultsSummary;
end

function metadataTable = generateExperimentMetadata(organizedData, roiInfo, filepath)
    % FIXED: Generate comprehensive metadata using upper thresholds
    
    try
        if strcmp(roiInfo.experimentType, 'PPF')
            metadataTable = generatePPFMetadata(organizedData, roiInfo);
        else
            metadataTable = generate1APMetadata(organizedData, roiInfo);
        end
        
        % Save metadata to Excel if table is valid and not empty
        if istable(metadataTable) && height(metadataTable) > 0
            try
                writetable(metadataTable, filepath, 'Sheet', 'ROI_Metadata');
                % Success - no output to keep interface clean
            catch ME
                % Silent failure - metadata is optional, don't crash pipeline
            end
        end
        
    catch ME
        % Return empty table on error to prevent pipeline crash
        metadataTable = table();
    end
end

function metadataTable = generate1APMetadata(organizedData, roiInfo)
    % Generate 1AP-specific metadata with upper thresholds and noise level classification
    
    maxEntries = length(roiInfo.roiNumbers) * roiInfo.numTrials;
    
    % Preallocate metadata structure with updated field names
    allMetadata = repmat(struct(...
        'ROI_Number', NaN, ...
        'Trial_Number', NaN, ...
        'Column_Name', '', ...
        'Noise_Level', '', ...
        'Threshold_upper', NaN, ...        % CHANGED: from Threshold_dF_F
        'Standard_Deviation', NaN, ...     % CHANGED: from Baseline_SD  
        'Baseline_Mean', NaN, ...
        'Experiment_Type', '', ...
        'Stimulus_Time_ms', NaN), maxEntries, 1);
    
    entryCount = 0;
    cfg = GluSnFRConfig();
    
    for roiIdx = 1:length(roiInfo.roiNumbers)
        roiNum = roiInfo.roiNumbers(roiIdx);
        
        % Get noise level and thresholds from filtering statistics
        [noiseLevel, upperThreshold, standardDeviation] = getROIThresholdData(roiNum, roiInfo);
        
        for trialIdx = 1:roiInfo.numTrials
            trialNum = roiInfo.originalTrialNumbers(trialIdx);
            
            if isfinite(trialNum)
                columnName = sprintf('ROI%d_T%g', roiNum, trialNum);
                
                if ismember(columnName, organizedData.Properties.VariableNames)
                    columnData = organizedData.(columnName);
                    
                    if ~all(isnan(columnData))
                        entryCount = entryCount + 1;
                        allMetadata(entryCount).ROI_Number = roiNum;
                        allMetadata(entryCount).Trial_Number = trialNum;
                        allMetadata(entryCount).Column_Name = columnName;
                        allMetadata(entryCount).Noise_Level = noiseLevel;
                        allMetadata(entryCount).Threshold_upper = upperThreshold;
                        allMetadata(entryCount).Standard_Deviation = standardDeviation;
                        allMetadata(entryCount).Baseline_Mean = 0; % dF/F baseline should be ~0
                        allMetadata(entryCount).Experiment_Type = '1AP';
                        allMetadata(entryCount).Stimulus_Time_ms = cfg.timing.STIMULUS_TIME_MS;
                    end
                end
            end
        end
    end
    
    % Convert to table
    if entryCount > 0
        allMetadata = allMetadata(1:entryCount);
        metadataTable = struct2table(allMetadata);
    else
        metadataTable = table();
    end
end

function metadataTable = generatePPFMetadata(organizedData, roiInfo)
    % FIXED: Generate PPF-specific metadata with upper thresholds
    
    % Safely calculate maximum entries across all data tables
    maxEntries = 0;
    dataFields = {'allData', 'bothPeaks', 'singlePeak'};
    
    for fieldIdx = 1:length(dataFields)
        fieldName = dataFields{fieldIdx};
        if isfield(organizedData, fieldName)
            try
                fieldData = organizedData.(fieldName);
                if istable(fieldData) && width(fieldData) > 1
                    maxEntries = maxEntries + (width(fieldData) - 1); % Subtract Frame column
                end
            catch
                % Skip problematic fields
                continue;
            end
        end
    end
    
    if maxEntries == 0
        metadataTable = table();
        return;
    end
    
    % Preallocate metadata structure with updated field names
    allMetadata = repmat(struct(...
        'CoverslipCell', '', ...
        'ROI_Number', NaN, ...
        'Column_Name', '', ...
        'Peak_Response', '', ...
        'Threshold_upper', NaN, ...        % CHANGED: from Threshold_dF_F
        'Standard_Deviation', NaN, ...     % CHANGED: from Baseline_SD
        'Baseline_Mean', NaN, ...
        'Experiment_Type', '', ...
        'Timepoint_ms', NaN, ...
        'Stimulus1_Time_ms', NaN, ...
        'Stimulus2_Time_ms', NaN), maxEntries, 1);
    
    entryCount = 0;
    cfg = GluSnFRConfig();
    
    % Process each data category safely
    for fieldIdx = 1:length(dataFields)
        fieldName = dataFields{fieldIdx};
        
        if ~isfield(organizedData, fieldName)
            continue;
        end
        
        try
            dataTable = organizedData.(fieldName);
            
            if ~istable(dataTable) || width(dataTable) <= 1
                continue;
            end
            
            % FIXED: Safe variable names access
            allVarNames = dataTable.Properties.VariableNames;
            varNames = allVarNames(2:end); % Skip Frame column
            
            % Determine peak response classification
            switch fieldName
                case 'bothPeaks'
                    peakResponseType = 'Both';
                case 'singlePeak'
                    peakResponseType = 'Single';
                otherwise
                    peakResponseType = 'Unknown';
            end
            
            for varIdx = 1:length(varNames)
                varName = varNames{varIdx};
                
                % Parse coverslip and ROI info
                roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    csCell = roiMatch{1}{1};
                    roiNum = str2double(roiMatch{1}{2});
                    
                    % Check if column exists and has valid data
                    try
                        if ismember(varName, allVarNames)
                            columnData = dataTable.(varName);
                            if ~all(isnan(columnData)) && entryCount < maxEntries
                                entryCount = entryCount + 1;
                                
                                allMetadata(entryCount).CoverslipCell = csCell;
                                allMetadata(entryCount).ROI_Number = roiNum;
                                allMetadata(entryCount).Column_Name = varName;
                                allMetadata(entryCount).Peak_Response = peakResponseType;
                                
                                % Extract upper threshold and standard deviation from filtering stats
                                [upperThreshold, standardDeviation, baselineMean] = getROIUpperThresholdAndBaseline(csCell, roiNum, roiInfo);
                                allMetadata(entryCount).Threshold_upper = upperThreshold;
                                allMetadata(entryCount).Standard_Deviation = standardDeviation;
                                allMetadata(entryCount).Baseline_Mean = baselineMean;
                                allMetadata(entryCount).Experiment_Type = 'PPF';
                                allMetadata(entryCount).Timepoint_ms = roiInfo.timepoint;
                                allMetadata(entryCount).Stimulus1_Time_ms = cfg.timing.STIMULUS_TIME_MS;
                                allMetadata(entryCount).Stimulus2_Time_ms = cfg.timing.STIMULUS_TIME_MS + roiInfo.timepoint;
                            end
                        end
                    catch
                        % Skip problematic columns
                        continue;
                    end
                end
            end
            
        catch
            % Skip problematic data fields
            continue;
        end
    end
    
    % Convert to table safely
    if entryCount > 0
        try
            validMetadata = allMetadata(1:entryCount);
            metadataTable = struct2table(validMetadata);
        catch
            metadataTable = table();
        end
    else
        metadataTable = table();
    end
end

function [noiseLevel, upperThreshold, standardDeviation] = getROIThresholdData(roiNum, roiInfo)
    % Get ROI threshold data from filtering statistics
    
    noiseLevel = 'unknown';
    upperThreshold = NaN;
    standardDeviation = NaN;
    
    try
        if isfield(roiInfo, 'filteringStats') && roiInfo.filteringStats.available
            % Get noise level
            if isfield(roiInfo.filteringStats, 'roiNoiseMap') && ...
               isKey(roiInfo.filteringStats.roiNoiseMap, roiNum)
                noiseLevel = roiInfo.filteringStats.roiNoiseMap(roiNum);
            end
            
            % Get upper threshold
            if isfield(roiInfo.filteringStats, 'roiUpperThresholds') && ...
               isKey(roiInfo.filteringStats.roiUpperThresholds, roiNum)
                upperThreshold = roiInfo.filteringStats.roiUpperThresholds(roiNum);
            end
            
            % Get standard deviation (NEW: instead of basic threshold)
            if isfield(roiInfo.filteringStats, 'roiStandardDeviations') && ...
               isKey(roiInfo.filteringStats.roiStandardDeviations, roiNum)
                standardDeviation = roiInfo.filteringStats.roiStandardDeviations(roiNum);
            end
        end
    catch
        % Use defaults if data retrieval fails
    end
end

function [upperThreshold, standardDeviation, baselineMean] = getROIUpperThresholdAndBaseline(csCell, roiNum, roiInfo)
    % Get upper threshold and baseline for specific PPF ROI
    
    upperThreshold = NaN;
    standardDeviation = NaN;
    baselineMean = 0;
    
    try
        % First try filtering statistics (preferred)
        if isfield(roiInfo, 'filteringStats') && roiInfo.filteringStats.available
            if isfield(roiInfo.filteringStats, 'roiUpperThresholds') && ...
               isKey(roiInfo.filteringStats.roiUpperThresholds, roiNum)
                upperThreshold = roiInfo.filteringStats.roiUpperThresholds(roiNum);
            end
            
            if isfield(roiInfo.filteringStats, 'roiStandardDeviations') && ...
               isKey(roiInfo.filteringStats.roiStandardDeviations, roiNum)
                standardDeviation = roiInfo.filteringStats.roiStandardDeviations(roiNum);
            end
        end
        
        % Fallback to coverslip files data
        if isnan(upperThreshold) || isnan(standardDeviation)
            for fileIdx = 1:length(roiInfo.coverslipFiles)
                fileData = roiInfo.coverslipFiles(fileIdx);
                if strcmp(fileData.coverslipCell, csCell)
                    roiIdx = find(fileData.roiNumbers == roiNum, 1);
                    
                    if ~isempty(roiIdx)
                        if roiIdx <= length(fileData.thresholds) && isnan(upperThreshold)
                            upperThreshold = fileData.thresholds(roiIdx); 
                        end
                        
                        if ~isempty(fileData.dF_values) && size(fileData.dF_values, 2) >= roiIdx
                            cfg = GluSnFRConfig();
                            baselineWindow = cfg.timing.BASELINE_FRAMES;
                            baselineData = fileData.dF_values(baselineWindow, roiIdx);
                            baselineMean = mean(baselineData, 'omitnan');
                            
                            if isnan(standardDeviation)
                                standardDeviation = std(baselineData, 'omitnan');
                            end
                        end
                        return;
                    end
                end
            end
        end
    catch
        % Use defaults if data retrieval fails
    end
end

% Keep all other functions unchanged (validateExperimentResults, calculateExperimentStatistics, createResultsSummary)
function isValid = validateExperimentResults(groupResults)
    % Validate experiment results for quality control
    
    isValid = true;
    issues = {};
    
    for i = 1:length(groupResults)
        result = groupResults{i};
        
        % Check for critical errors
        if strcmp(result.status, 'error')
            isValid = false;
            issues{end+1} = sprintf('Group %d failed with error', i);
        end
        
        % Check for reasonable ROI counts
        if isfield(result, 'numROIs') && result.numROIs == 0
            issues{end+1} = sprintf('Group %d has no valid ROIs', i);
        end
        
        % Check for reasonable filter rates
        if isfield(result, 'numROIs') && isfield(result, 'numOriginalROIs')
            filterRate = result.numROIs / result.numOriginalROIs;
            if filterRate < 0.1 % Less than 10% passed filtering
                issues{end+1} = sprintf('Group %d has very low filter rate (%.1f%%)', i, filterRate*100);
            end
        end
    end
    
    % Report issues
    if ~isempty(issues)
        fprintf('\n=== Quality Control Issues ===\n');
        for i = 1:length(issues)
            fprintf('  WARNING: %s\n', issues{i});
        end
    end
    
    if isValid
        fprintf('All experiment results passed validation\n');
    else
        fprintf('Some experiment results failed validation\n');
    end
end

function stats = calculateExperimentStatistics(groupResults)
    % Calculate comprehensive statistics across all groups
    
    stats = struct();
    stats.totalGroups = length(groupResults);
    stats.successfulGroups = 0;
    stats.totalROIs = 0;
    stats.totalOriginalROIs = 0;
    stats.gpuUsage = 0;
    stats.experimentTypes = {};
    
    % Collect statistics
    for i = 1:length(groupResults)
        result = groupResults{i};
        
        if strcmp(result.status, 'success')
            stats.successfulGroups = stats.successfulGroups + 1;
        end
        
        if isfield(result, 'numROIs')
            stats.totalROIs = stats.totalROIs + result.numROIs;
        end
        
        if isfield(result, 'numOriginalROIs')
            stats.totalOriginalROIs = stats.totalOriginalROIs + result.numOriginalROIs;
        end
        
        if isfield(result, 'gpuUsed') && result.gpuUsed
            stats.gpuUsage = stats.gpuUsage + 1;
        end
        
        if isfield(result, 'experimentType')
            if ~ismember(result.experimentType, stats.experimentTypes)
                stats.experimentTypes{end+1} = result.experimentType;
            end
        end
    end
    
    % Calculate derived statistics
    stats.successRate = stats.successfulGroups / stats.totalGroups;
    if stats.totalOriginalROIs > 0
        stats.overallFilterRate = stats.totalROIs / stats.totalOriginalROIs;
    else
        stats.overallFilterRate = 0;
    end
    stats.gpuUsageRate = stats.gpuUsage / stats.totalGroups;
    
    % Performance categories
    if stats.successRate >= 0.95
        stats.performanceCategory = 'Excellent';
    elseif stats.successRate >= 0.80
        stats.performanceCategory = 'Good';
    elseif stats.successRate >= 0.60
        stats.performanceCategory = 'Fair';
    else
        stats.performanceCategory = 'Poor';
    end
end

function summary = createResultsSummary(groupResults, processingTimes, totalTime)
    % Create comprehensive results summary
    
    stats = calculateExperimentStatistics(groupResults);
    
    summary = struct();
    summary.statistics = stats;
    summary.timing = struct();
    summary.timing.totalTime = totalTime;
    summary.timing.averageTimePerGroup = totalTime / stats.totalGroups;
    summary.timing.groupTimes = processingTimes;
    
    % Create text summary
    summaryText = {};
    summaryText{end+1} = '=== GluSnFR Analysis Summary ===';
    summaryText{end+1} = sprintf('Total groups processed: %d', stats.totalGroups);
    summaryText{end+1} = sprintf('Successful groups: %d (%.1f%%)', stats.successfulGroups, stats.successRate*100);
    summaryText{end+1} = sprintf('Experiment types: %s', strjoin(stats.experimentTypes, ', '));
    summaryText{end+1} = sprintf('Total ROIs: %d (from %d original)', stats.totalROIs, stats.totalOriginalROIs);
    summaryText{end+1} = sprintf('Overall filter rate: %.1f%%', stats.overallFilterRate*100);
    summaryText{end+1} = sprintf('GPU usage: %d/%d groups (%.1f%%)', stats.gpuUsage, stats.totalGroups, stats.gpuUsageRate*100);
    summaryText{end+1} = sprintf('Total processing time: %.2f seconds', totalTime);
    summaryText{end+1} = sprintf('Average time per group: %.2f seconds', summary.timing.averageTimePerGroup);
    summaryText{end+1} = sprintf('Performance category: %s', stats.performanceCategory);
    
    summary.textSummary = summaryText;
    
    % Display summary
    fprintf('\n');
    for i = 1:length(summaryText)
        fprintf('%s\n', summaryText{i});
    end
end