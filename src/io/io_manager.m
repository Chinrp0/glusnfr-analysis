function io = io_manager()
    % IO_MANAGER - Complete file input/output operations module
    % 
    % This module handles ALL file I/O operations including:
    % - Excel file reading with multiple fallback methods
    % - Excel file writing with custom headers (CONSOLIDATED)
    % - Directory management and file validation
    % - Complete experiment results writing
    
    io.readExcelFile = @readExcelFileRobust;
    io.writeExcelWithHeaders = @writeExcelWithCustomHeaders;
    io.extractValidHeaders = @extractValidHeaders;
    io.writeExperimentResults = @writeExperimentResults;
    io.createDirectories = @createDirectoriesIfNeeded;
    io.validateFile = @validateExcelFile;
    io.getExcelFiles = @getExcelFilesValidated;
    io.saveLog = @saveLogToFile;
end

function [data, headers, success] = readExcelFileRobust(filepath, useReadMatrix)
    % Robust Excel file reading with multiple fallback methods
    
    success = false;
    data = [];
    headers = {};
    
    if ~exist(filepath, 'file')
        warning('File does not exist: %s', filepath);
        return;
    end
    
    fprintf('    Reading: %s\n', filepath);
    
    try
        if useReadMatrix && ~verLessThan('matlab', '9.6') % R2019a+
            % Method 1: readcell (fastest, most reliable)
            try
                raw = readcell(filepath, 'NumHeaderLines', 0);
                if isempty(raw) || size(raw, 1) < 3
                    error('Insufficient data rows');
                end
                success = true;
                
            catch
                % Method 2: readtable fallback
                try
                    fprintf('      Using readtable fallback...\n');
                    tempTable = readtable(filepath, 'ReadVariableNames', false);
                    raw = table2cell(tempTable);
                    success = true;
                catch
                    % Method 3: xlsread as last resort
                    fprintf('      Using xlsread fallback...\n');
                    [~, ~, raw] = xlsread(filepath); %#ok<XLSRD>
                    success = true;
                end
            end
        else
            % For older MATLAB versions
            [~, ~, raw] = xlsread(filepath); %#ok<XLSRD>
            success = true;
        end
        
    catch ME
        error('Failed to read file %s: %s', filepath, ME.message);
    end
    
    % Validate and extract data
    if success && ~isempty(raw) && size(raw, 1) >= 3
        headers = raw(2, :);  % Row 2 contains ROI headers
        dataRows = raw(3:end, :);  % Row 3+ contains data
        
        % Convert to numeric
        data = convertToNumeric(dataRows);
        
        fprintf('      Successfully read %d frames × %d columns\n', ...
                size(data, 1), size(data, 2));
    else
        success = false;
        warning('File %s has insufficient data or invalid format', filepath);
    end
end

function numericData = convertToNumeric(dataRows)
    % Optimized cell array to numeric conversion
    
    [numRows, numCols] = size(dataRows);
    numericData = NaN(numRows, numCols, 'single');
    
    for col = 1:numCols
        try
            colData = dataRows(:, col);
            
            % Fast path for already numeric columns
            if all(cellfun(@isnumeric, colData(~cellfun(@isempty, colData))))
                validRows = ~cellfun(@isempty, colData);
                if any(validRows)
                    numericData(validRows, col) = single(cell2mat(colData(validRows)));
                end
            else
                % Mixed type column - element by element conversion
                for row = 1:numRows
                    cellValue = colData{row};
                    
                    if isnumeric(cellValue) && isscalar(cellValue) && isfinite(cellValue)
                        numericData(row, col) = single(cellValue);
                    elseif ischar(cellValue) || isstring(cellValue)
                        numValue = str2double(cellValue);
                        if isfinite(numValue)
                            numericData(row, col) = single(numValue);
                        end
                    end
                end
            end
            
        catch ME
            fprintf('    WARNING: Column %d conversion issue: %s\n', col, ME.message);
        end
    end
end


function excelFiles = getExcelFiles(folder)
    % Wrapper function for backward compatibility
    excelFiles = getExcelFilesValidated(folder);
end


function writeExperimentResults(organizedData, averagedData, roiInfo, groupKey, outputFolder)
    % CONSOLIDATED: Write all experiment results with proper headers
    
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
    [row1, row2] = createPPFHeaders(organizedData, roiInfo, true);
    writeExcelWithCustomHeaders(organizedData, filepath, 'All_Data', row1, row2);
    
    % Averaged data sheet
    [row1, row2] = createPPFHeaders(averagedData, roiInfo, false);
    writeExcelWithCustomHeaders(averagedData, filepath, 'Averaged', row1, row2);
end

function write1APExperimentResults(organizedData, averagedData, roiInfo, filepath)
    % Write 1AP-specific Excel results with noise-based separation
    
    % Separate by noise level
    [lowNoiseData, highNoiseData] = separateDataByNoiseLevel(organizedData, roiInfo);
    
    % Write noise-based sheets
    if width(lowNoiseData) > 1
        [row1, row2] = create1APHeaders(lowNoiseData, roiInfo, true);
        writeExcelWithCustomHeaders(lowNoiseData, filepath, 'Low_noise', row1, row2);
    end
    
    if width(highNoiseData) > 1
        [row1, row2] = create1APHeaders(highNoiseData, roiInfo, true);
        writeExcelWithCustomHeaders(highNoiseData, filepath, 'High_noise', row1, row2);
    end
    
    % Write averaged sheets
    if isfield(averagedData, 'roi') && width(averagedData.roi) > 1
        [row1, row2] = create1APHeaders(averagedData.roi, roiInfo, false);
        writeExcelWithCustomHeaders(averagedData.roi, filepath, 'ROI_Average', row1, row2);
    end
    
    if isfield(averagedData, 'total') && width(averagedData.total) > 1
        [row1, row2] = createTotalAverageHeaders(averagedData.total);
        writeExcelWithCustomHeaders(averagedData.total, filepath, 'Total_Average', row1, row2);
    end
end

function writeExcelWithCustomHeaders(dataTable, filepath, sheetName, row1, row2)
    % Write Excel with custom two-row headers
    
    if width(dataTable) <= 1 % Only Frame column
        return;
    end
    
    varNames = dataTable.Properties.VariableNames;
    timeData_ms = dataTable.Frame;
    numFrames = length(timeData_ms);
    
    try
        % Prepare data matrix
        dataMatrix = [timeData_ms, dataTable{:, 2:end}];
        
        % Create cell array for writing
        cellData = cell(numFrames + 2, length(varNames));
        
        % Add headers
        cellData(1, :) = row1;
        cellData(2, :) = row2;
        
        % Add data
        for i = 1:numFrames
            for j = 1:size(dataMatrix, 2)
                cellData{i+2, j} = dataMatrix(i, j);
            end
        end
        
        % Write to Excel
        writecell(cellData, filepath, 'Sheet', sheetName);
        
    catch ME
        fprintf('    WARNING: Custom header writing failed for %s (%s), using standard format\n', sheetName, ME.message);
        writetable(dataTable, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
    end
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

function [row1, row2] = createTotalAverageHeaders(dataTable)
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

function [validHeaders, validColumns] = extractValidHeaders(headers)
    % MISSING FUNCTION: Referenced in data_organizer.m but not in io_manager.m
    
    numHeaders = length(headers);
    validHeaders = cell(numHeaders, 1);
    validColumns = zeros(numHeaders, 1);
    validCount = 0;
    
    for i = 1:numHeaders
        header = headers{i};
        if ~isempty(header) && (ischar(header) || isstring(header))
            cleanHeader = strtrim(char(header));
            if ~isempty(cleanHeader)
                validCount = validCount + 1;
                validHeaders{validCount} = cleanHeader;
                validColumns(validCount) = i;
            end
        end
    end
    
    % Trim to actual size
    validHeaders = validHeaders(1:validCount);
    validColumns = validColumns(1:validCount);
    
    fprintf('      Extracted %d valid headers from %d total columns\n', validCount, numHeaders);
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

function excelFiles = getExcelFilesValidated(folder)
    % FIXED: Get and validate Excel files in folder
    
    if ~exist(folder, 'dir')
        error('Folder does not exist: %s', folder);
    end
    
    % Get all Excel files
    allFiles = dir(fullfile(folder, '*.xlsx'));
    
    if isempty(allFiles)
        warning('No Excel files found in folder: %s', folder);
        excelFiles = [];
        return;
    end
    
    % Validate each file
    validFiles = [];
    for i = 1:length(allFiles)
        filepath = fullfile(allFiles(i).folder, allFiles(i).name);
        if validateExcelFile(filepath)
            validFiles = [validFiles; allFiles(i)];
        else
            fprintf('    Skipping invalid file: %s\n', allFiles(i).name);
        end
    end
    
    % FIXED: Return validFiles instead of allFiles
    excelFiles = validFiles;
    fprintf('Found %d valid Excel files (out of %d total)\n', ...
            length(excelFiles), length(allFiles));
end

function isValid = validateExcelFile(filepath)
    % Validate that Excel file has required structure
    
    isValid = false;
    
    if ~exist(filepath, 'file')
        return;
    end
    
    try
        % Quick validation read
        raw = readcell(filepath, 'Range', 'A1:Z10', 'NumHeaderLines', 0);
        
        % Check basic structure
        if size(raw, 1) >= 3 && size(raw, 2) >= 2
            % Check if row 2 has ROI-like headers
            row2 = raw(2, :);
            roiCount = 0;
            
            for i = 1:length(row2)
                if ~isempty(row2{i}) && ischar(row2{i})
                    if contains(lower(row2{i}), 'roi')
                        roiCount = roiCount + 1;
                    end
                end
            end
            
            isValid = roiCount > 0;
        end
        
    catch
        isValid = false;
    end
end

function createDirectoriesIfNeeded(directories)
    % Create directories if they don't exist
    
    for i = 1:length(directories)
        dir_path = directories{i};
        if ~exist(dir_path, 'dir')
            try
                mkdir(dir_path);
                fprintf('Created directory: %s\n', dir_path);
            catch ME
                warning('Failed to create directory %s: %s', dir_path, ME.message);
            end
        end
    end
end

function saveLogToFile(logBuffer, logFileName)
    % Save log buffer to file
    
    try
        fid = fopen(logFileName, 'w');
        if fid == -1
            warning('Could not create log file: %s', logFileName);
            return;
        end
        
        % Write buffered output
        for i = 1:length(logBuffer)
            fprintf(fid, '%s\n', logBuffer{i});
        end
        
        fclose(fid);
        fprintf('Log saved to: %s\n', logFileName);
        
    catch ME
        fprintf(2, 'Error writing log file: %s\n', ME.message);
        
        if exist('fid', 'var') && fid ~= -1
            fclose(fid);
        end
    end
end
