function analyzer = experiment_analyzer()
    % EXPERIMENT_ANALYZER - Experiment-specific analysis module
    % 
    % This module handles analysis specific to different experiment types:
    % - 1AP (single action potential) analysis
    % - PPF (paired-pulse facilitation) analysis
    % - Statistics and summary generation
    % - Results validation and quality control
    
    analyzer.processSingleFile = @processSingleFile;
    analyzer.generateMetadata = @generateExperimentMetadata;
    analyzer.validateResults = @validateExperimentResults;
    analyzer.calculateStatistics = @calculateExperimentStatistics;
    analyzer.createSummary = @createResultsSummary;
end

function [data, metadata] = processSingleFile(fileInfo, rawMeanFolder, useReadMatrix, hasGPU, gpuInfo)
    % Process a single Excel file through the complete pipeline
    
    fullFilePath = fullfile(fileInfo.folder, fileInfo.name);
    fprintf('    Processing: %s\n', fileInfo.name);
    
    % Load modules
    io = io_manager();
    calc = df_calculator();
    filter = roi_filter();
    utils = string_utils();
    
    % Read file
    [rawData, headers, readSuccess] = io.readExcelFile(fullFilePath, useReadMatrix);
    
    if ~readSuccess || isempty(rawData)
        error('Failed to read file: %s', fileInfo.name);
    end
    
    % Extract valid headers and data
    organizer = data_organizer();
    [validHeaders, validColumns] = organizer.extractValidHeaders(headers);
    
    if isempty(validHeaders)
        error('No valid ROI headers found in %s', fileInfo.name);
    end
    
    % Extract valid data columns
    numericData = single(rawData(:, validColumns));
    
    % Create time data
    cfg = GluSnFRConfig();
    timeData_ms = single((0:(size(numericData, 1)-1))' * cfg.timing.MS_PER_FRAME);
    
    % Calculate dF/F
    [dF_values, thresholds, gpuUsed] = calc.calculate(numericData, hasGPU, gpuInfo);
    
    % Extract experiment info
    [trialNum, expType, ppiValue, coverslipCell] = utils.extractTrialInfo(fileInfo.name);
    
    % Apply filtering
    if strcmp(expType, 'PPF') && isfinite(ppiValue)
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, 'PPF', ppiValue);
    else
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
    end
    
    % Prepare output structures
    data = struct();
    data.timeData_ms = timeData_ms;
    data.dF_values = finalDFValues;
    data.roiNames = finalHeaders;
    data.thresholds = finalThresholds;
    data.stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    data.gpuUsed = gpuUsed;
    data.filterStats = filterStats;
    
    metadata = struct();
    metadata.filename = fileInfo.name;
    metadata.numFrames = size(numericData, 1);
    metadata.numROIs = length(finalHeaders);
    metadata.numOriginalROIs = length(validHeaders);
    metadata.filterRate = metadata.numROIs / metadata.numOriginalROIs;
    metadata.gpuUsed = gpuUsed;
    metadata.dataType = 'single';
    metadata.trialNumber = trialNum;
    metadata.experimentType = expType;
    metadata.ppiValue = ppiValue;
    metadata.coverslipCell = coverslipCell;
    
    % Log results
    if strcmp(expType, 'PPF')
        fprintf('      Final result: %d ROIs for %s PPI=%dms trial=%g (%.1f%% passed filter)\n', ...
                metadata.numROIs, expType, ppiValue, trialNum, metadata.filterRate*100);
    else
        fprintf('      Final result: %d ROIs for %s trial=%g (%.1f%% passed filter)\n', ...
                metadata.numROIs, expType, trialNum, metadata.filterRate*100);
    end
end

function metadataTable = generateExperimentMetadata(organizedData, roiInfo, filepath)
    % Generate comprehensive metadata for Script 1 optimization
    
    if strcmp(roiInfo.experimentType, 'PPF')
        metadataTable = generatePPFMetadata(organizedData, roiInfo);
    else
        metadataTable = generate1APMetadata(organizedData, roiInfo);
    end
    
    % Save metadata to Excel
    io = io_manager();
    try
        writetable(metadataTable, filepath, 'Sheet', 'ROI_Metadata');
        fprintf('    Metadata sheet written with %d entries\n', height(metadataTable));
    catch ME
        fprintf('Failed to write metadata: %s\n', ME.message);
    end
end

function metadataTable = generate1APMetadata(organizedData, roiInfo)
    % Generate 1AP-specific metadata with noise level classification
    
    maxEntries = length(roiInfo.roiNumbers) * roiInfo.numTrials;
    
    % Preallocate metadata structure
    allMetadata = repmat(struct(...
        'ROI_Number', NaN, ...
        'Trial_Number', NaN, ...
        'Column_Name', '', ...
        'Noise_Level', '', ...
        'Threshold_dF_F', NaN, ...
        'Baseline_SD', NaN, ...
        'Baseline_Mean', NaN, ...
        'Experiment_Type', '', ...
        'Stimulus_Time_ms', NaN), maxEntries, 1);
    
    entryCount = 0;
    cfg = GluSnFRConfig();
    
    for roiIdx = 1:length(roiInfo.roiNumbers)
        roiNum = roiInfo.roiNumbers(roiIdx);
        
        % Get noise level
        noiseLevel = 'unknown';
        if isKey(roiInfo.roiNoiseMap, roiNum)
            noiseLevel = roiInfo.roiNoiseMap(roiNum);
        end
        
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
                        
                        % Extract threshold and baseline stats
                        if roiIdx <= size(roiInfo.thresholds, 1) && trialIdx <= size(roiInfo.thresholds, 2)
                            threshold = roiInfo.thresholds(roiIdx, trialIdx);
                            allMetadata(entryCount).Threshold_dF_F = threshold;
                            allMetadata(entryCount).Baseline_SD = threshold / cfg.thresholds.SD_MULTIPLIER;
                        end
                        
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
    % Generate PPF-specific metadata
    
    % Calculate maximum entries
    maxEntries = 0;
    for fileIdx = 1:length(roiInfo.coverslipFiles)
        maxEntries = maxEntries + length(roiInfo.coverslipFiles(fileIdx).roiNumbers);
    end
    
    if maxEntries == 0
        metadataTable = table();
        return;
    end
    
    % Preallocate metadata structure
    allMetadata = repmat(struct(...
        'CoverslipCell', '', ...
        'ROI_Number', NaN, ...
        'Column_Name', '', ...
        'Threshold_dF_F', NaN, ...
        'Baseline_SD', NaN, ...
        'Baseline_Mean', NaN, ...
        'Experiment_Type', '', ...
        'Timepoint_ms', NaN, ...
        'Stimulus1_Time_ms', NaN, ...
        'Stimulus2_Time_ms', NaN), maxEntries, 1);
    
    entryCount = 0;
    cfg = GluSnFRConfig();
    
    for fileIdx = 1:length(roiInfo.coverslipFiles)
        fileData = roiInfo.coverslipFiles(fileIdx);
        csCell = fileData.coverslipCell;
        
        for roiIdx = 1:length(fileData.roiNumbers)
            roiNum = fileData.roiNumbers(roiIdx);
            columnName = sprintf('%s_ROI%d', csCell, roiNum);
            
            % Check if column exists and has data
            if ismember(columnName, organizedData.Properties.VariableNames)
                columnData = organizedData.(columnName);
                if ~all(isnan(columnData))
                    entryCount = entryCount + 1;
                    allMetadata(entryCount).CoverslipCell = csCell;
                    allMetadata(entryCount).ROI_Number = roiNum;
                    allMetadata(entryCount).Column_Name = columnName;
                    
                    % Extract threshold and baseline stats
                    if roiIdx <= length(fileData.thresholds)
                        threshold = fileData.thresholds(roiIdx);
                        allMetadata(entryCount).Threshold_dF_F = threshold;
                        allMetadata(entryCount).Baseline_SD = threshold / cfg.thresholds.SD_MULTIPLIER;
                        
                        % Calculate baseline mean from actual data
                        if ~isempty(fileData.dF_values) && size(fileData.dF_values, 2) >= roiIdx
                            baselineWindow = cfg.timing.BASELINE_FRAMES;
                            baselineData = fileData.dF_values(baselineWindow, roiIdx);
                            allMetadata(entryCount).Baseline_Mean = mean(baselineData, 'omitnan');
                        else
                            allMetadata(entryCount).Baseline_Mean = 0;
                        end
                    end
                    
                    allMetadata(entryCount).Experiment_Type = 'PPF';
                    allMetadata(entryCount).Timepoint_ms = roiInfo.timepoint;
                    allMetadata(entryCount).Stimulus1_Time_ms = cfg.timing.STIMULUS_TIME_MS;
                    allMetadata(entryCount).Stimulus2_Time_ms = cfg.timing.STIMULUS_TIME_MS + roiInfo.timepoint;
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