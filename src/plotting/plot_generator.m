function io = io_manager()
    % IO_MANAGER - Consolidated file input/output operations module
    % 
    % This module handles ALL file I/O operations including:
    % - Excel file reading with multiple fallback methods
    % - Excel file writing with custom headers (CONSOLIDATED FROM plot_generator.m)
    % - Directory management
    % - File validation
    
    io.readExcelFile = @readExcelFileRobust;
    io.writeExcelWithHeaders = @writeExcelWithCustomHeaders;
    io.writeExperimentResults = @writeExperimentResults;  % NEW: High-level results writing
    io.createHeaders = @createExperimentHeaders;         % NEW: Consolidated header creation
    io.createDirectories = @createDirectoriesIfNeeded;
    io.validateFile = @validateExcelFile;
    io.getExcelFiles = @getExcelFilesValidated;
    io.saveLog = @saveLogToFile;
end

% [Keep existing functions: readExcelFileRobust, convertToNumeric, validateExcelFile, etc.]

function writeExperimentResults(organizedData, averagedData, roiInfo, groupKey, outputFolder)
    % High-level function to write all experiment results
    % CONSOLIDATES logic from multiple modules
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    filename = [cleanGroupKey '_grouped_v50_modular.xlsx'];
    filepath = fullfile(outputFolder, filename);
    
    % Delete existing file
    if exist(filepath, 'file')
        delete(filepath);
    end
    
    try
        if strcmp(roiInfo.experimentType, 'PPF')
            writePPFExperimentResults(organizedData, averagedData, roiInfo, filepath);
        else
            write1APExperimentResults(organizedData, averagedData, roiInfo, filepath);
        end
        
        % Write metadata sheet
        writeMetadataSheet(organizedData, roiInfo, filepath);
        
        fprintf('    Excel results saved: %s\n', filename);
        
    catch ME
        error('Failed to write Excel results for %s: %s', groupKey, ME.message);
    end
end

function writePPFExperimentResults(organizedData, averagedData, roiInfo, filepath)
    % Write PPF-specific Excel results
    
    % All data sheet with proper headers
    [row1, row2] = createExperimentHeaders(organizedData, roiInfo, true);
    writeExcelWithCustomHeaders(organizedData, filepath, 'All_Data', row1, row2);
    
    % Averaged data sheet
    [row1, row2] = createExperimentHeaders(averagedData, roiInfo, false);
    writeExcelWithCustomHeaders(averagedData, filepath, 'Averaged', row1, row2);
end

function write1APExperimentResults(organizedData, averagedData, roiInfo, filepath)
    % Write 1AP-specific Excel results with noise-based separation
    
    % Separate by noise level
    [lowNoiseData, highNoiseData] = separateDataByNoiseLevel(organizedData, roiInfo);
    
    % Write noise-based sheets
    if width(lowNoiseData) > 1
        [row1, row2] = createExperimentHeaders(lowNoiseData, roiInfo, true);
        writeExcelWithCustomHeaders(lowNoiseData, filepath, 'Low_noise', row1, row2);
    end
    
    if width(highNoiseData) > 1
        [row1, row2] = createExperimentHeaders(highNoiseData, roiInfo, true);
        writeExcelWithCustomHeaders(highNoiseData, filepath, 'High_noise', row1, row2);
    end
    
    % Write averaged sheets
    if isfield(averagedData, 'roi') && width(averagedData.roi) > 1
        [row1, row2] = createExperimentHeaders(averagedData.roi, roiInfo, false);
        writeExcelWithCustomHeaders(averagedData.roi, filepath, 'ROI_Average', row1, row2);
    end
    
    if isfield(averagedData, 'total') && width(averagedData.total) > 1
        [row1, row2] = createTotalAverageHeaders(averagedData.total, roiInfo);
        writeExcelWithCustomHeaders(averagedData.total, filepath, 'Total_Average', row1, row2);
    end
end

function [row1, row2] = createExperimentHeaders(dataTable, roiInfo, isTrialData)
    % CONSOLIDATED header creation for all experiment types
    % MOVED FROM plot_generator.m
    
    if strcmp(roiInfo.experimentType, 'PPF')
        [row1, row2] = createPPFHeaders(dataTable, roiInfo, isTrialData);
    else
        [row1, row2] = create1APHeaders(dataTable, roiInfo, isTrialData);
    end
end

function [row1, row2] = createPPFHeaders(dataTable, roiInfo, isTrialData)
    % Create headers for PPF data - MOVED FROM plot_generator.m
    
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
            else
                row1{i} = '';
                row2{i} = varName;
            end
        else
            % Format: Cs1-c2_n24
            roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
            if ~isempty(roiMatch)
                row1{i} = roiMatch{1}{2};  % 24
                row2{i} = roiMatch{1}{1};  % Cs1-c2
            else
                row1{i} = '';
                row2{i} = varName;
            end
        end
    end
end

function [row1, row2] = create1APHeaders(dataTable, roiInfo, isTrialData)
    % Create headers for 1AP data - MOVED FROM plot_generator.m
    
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
            else
                row1{i} = '';
                row2{i} = varName;
            end
        else
            % Format: ROI123_n5
            roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
            if ~isempty(roiMatch)
                row1{i} = roiMatch{1}{2};  % n count
                row2{i} = sprintf('ROI %s', roiMatch{1}{1});  % ROI number
            else
                row1{i} = '';
                row2{i} = varName;
            end
        end
    end
end

function [row1, row2] = createTotalAverageHeaders(dataTable, roiInfo)
    % Create headers for total average data (1AP experiments)
    
    varNames = dataTable.Properties.VariableNames;
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    row1{1} = 'Average Type';
    row2{1} = 'Time (ms)';
    
    for i = 2:length(varNames)
        varName = varNames{i};
        
        % Parse column names like "Low_Noise_n15", "High_Noise_n8", "All_n23"
        nMatch = regexp(varName, 'n(\d+)', 'tokens');
        if ~isempty(nMatch)
            row1{i} = nMatch{1}{1};  % n count
            
            if contains(varName, 'Low_Noise')
                row2{i} = 'Low Noise';
            elseif contains(varName, 'High_Noise')
                row2{i} = 'High Noise';
            elseif contains(varName, 'All_')
                row2{i} = 'All';
            else
                row2{i} = varName;
            end
        else
            row1{i} = '';
            row2{i} = varName;
        end
    end
end

function [lowNoiseData, highNoiseData] = separateDataByNoiseLevel(organizedData, roiInfo)
    % Separate 1AP data by noise level
    
    varNames = organizedData.Properties.VariableNames;
    lowNoiseCols = {'Frame'};
    highNoiseCols = {'Frame'};
    
    for i = 2:length(varNames)
        colName = varNames{i};
        roiMatch = regexp(colName, 'ROI(\d+)_T', 'tokens');
        
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            
            if isKey(roiInfo.roiNoiseMap, roiNum)
                noiseLevel = roiInfo.roiNoiseMap(roiNum);
                
                if strcmp(noiseLevel, 'low')
                    lowNoiseCols{end+1} = colName;
                elseif strcmp(noiseLevel, 'high')
                    highNoiseCols{end+1} = colName;
                end
            end
        end
    end
    
    lowNoiseData = organizedData(:, lowNoiseCols);
    highNoiseData = organizedData(:, highNoiseCols);
end

function writeMetadataSheet(organizedData, roiInfo, filepath)
    % Write comprehensive metadata sheet for Script 1 optimization
    
    cfg = GluSnFRConfig();
    
    if strcmp(roiInfo.experimentType, 'PPF')
        metadataTable = generatePPFMetadata(organizedData, roiInfo, cfg);
    else
        metadataTable = generate1APMetadata(organizedData, roiInfo, cfg);
    end
    
    if ~isempty(metadataTable)
        writetable(metadataTable, filepath, 'Sheet', 'ROI_Metadata');
        fprintf('    Metadata sheet written with %d entries\n', height(metadataTable));
    end
end

function metadataTable = generate1APMetadata(organizedData, roiInfo, cfg)
    % Generate 1AP metadata with noise level information
    
    maxEntries = length(roiInfo.roiNumbers) * roiInfo.numTrials;
    
    if maxEntries == 0
        metadataTable = table();
        return;
    end
    
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
                        
                        allMetadata(entryCount).Baseline_Mean = 0;
                        allMetadata(entryCount).Experiment_Type = '1AP';
                        allMetadata(entryCount).Stimulus_Time_ms = cfg.timing.STIMULUS_TIME_MS;
                    end
                end
            end
        end
    end
    
    if entryCount > 0
        allMetadata = allMetadata(1:entryCount);
        metadataTable = struct2table(allMetadata);
    else
        metadataTable = table();
    end
end

function metadataTable = generatePPFMetadata(organizedData, roiInfo, cfg)
    % Generate PPF metadata 
    
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
    
    for fileIdx = 1:length(roiInfo.coverslipFiles)
        fileData = roiInfo.coverslipFiles(fileIdx);
        csCell = fileData.coverslipCell;
        
        for roiIdx = 1:length(fileData.roiNumbers)
            roiNum = fileData.roiNumbers(roiIdx);
            columnName = sprintf('%s_ROI%d', csCell, roiNum);
            
            if ismember(columnName, organizedData.Properties.VariableNames)
                columnData = organizedData.(columnName);
                if ~all(isnan(columnData))
                    entryCount = entryCount + 1;
                    allMetadata(entryCount).CoverslipCell = csCell;
                    allMetadata(entryCount).ROI_Number = roiNum;
                    allMetadata(entryCount).Column_Name = columnName;
                    
                    if roiIdx <= length(fileData.thresholds)
                        threshold = fileData.thresholds(roiIdx);
                        allMetadata(entryCount).Threshold_dF_F = threshold;
                        allMetadata(entryCount).Baseline_SD = threshold / cfg.thresholds.SD_MULTIPLIER;
                        
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
    
    if entryCount > 0
        allMetadata = allMetadata(1:entryCount);
        metadataTable = struct2table(allMetadata);
    else
        metadataTable = table();
    end
end

% [Keep all other existing functions: readExcelFileRobust, createDirectoriesIfNeeded, etc.]