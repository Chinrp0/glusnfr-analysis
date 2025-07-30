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

function excelFiles = getExcelFilesValidated(folder)
    % FIXED: Get and validate Excel files in folder with RELAXED validation
    
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
    
    % RELAXED validation - just check if file can be read
    validFiles = [];
    
    for i = 1:length(allFiles)
        filepath = fullfile(allFiles(i).folder, allFiles(i).name);
        
        % MUCH MORE PERMISSIVE validation
        if validateExcelFileRelaxed(filepath)
            validFiles = [validFiles; allFiles(i)];
        else
            fprintf('    Skipping invalid file: %s\n', allFiles(i).name);
        end
    end
    
    excelFiles = validFiles;
    fprintf('Found %d valid Excel files (out of %d total)\n', ...
            length(excelFiles), length(allFiles));
    
    % If no files pass validation, be more permissive
    if isempty(excelFiles) && ~isempty(allFiles)
        fprintf('WARNING: No files passed strict validation, using all .xlsx files\n');
        excelFiles = allFiles;
    end
end

function isValid = validateExcelFileRelaxed(filepath)
    % MUCH MORE RELAXED validation - just check if file is readable
    
    isValid = false;
    
    if ~exist(filepath, 'file')
        return;
    end
    
    try
        % Try to read just the first few cells to see if it's a valid Excel file
        raw = readcell(filepath, 'Range', 'A1:E5', 'NumHeaderLines', 0);
        
        % Very basic checks - just needs to be readable with some content
        if ~isempty(raw) && size(raw, 1) >= 2 && size(raw, 2) >= 2
            isValid = true;
        end
        
    catch
        % If readcell fails, try xlsread
        try
            [~, ~, raw] = xlsread(filepath, 1, 'A1:E5'); %#ok<XLSRD>
            if ~isempty(raw) && size(raw, 1) >= 2
                isValid = true;
            end
        catch
            isValid = false;
        end
    end
end

function isValid = validateExcelFile(filepath)
    % UPDATED: Legacy function - now just calls the relaxed version
    isValid = validateExcelFileRelaxed(filepath);
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

function writeExperimentResults(organizedData, averagedData, roiInfo, groupKey, outputFolder)
    % COMPLETE IMPLEMENTATION: Write comprehensive experiment results to Excel
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    filename = [cleanGroupKey '_grouped_v50.xlsx'];
    filepath = fullfile(outputFolder, filename);
    
    % Delete existing file
    if exist(filepath, 'file')
        delete(filepath);
    end
    
    fprintf('    Writing Excel results: %s\n', filename);
    
    try
        if strcmp(roiInfo.experimentType, 'PPF')
            % PPF: Write specialized sheets
            writePPFResults(organizedData, averagedData, roiInfo, filepath);
        else
            % 1AP: Write noise-based sheets and total averages
            write1APResults(organizedData, averagedData, roiInfo, filepath);
        end
        
        % Always write metadata sheet
        writeMetadataSheet(organizedData, roiInfo, filepath);
        
        fprintf('    Excel file saved: %s\n', filepath);
        
    catch ME
        fprintf('    ERROR saving Excel file %s: %s\n', filename, ME.message);
        rethrow(ME);
    end
end

function writePPFResults(organizedData, averagedData, roiInfo, filepath)
    % Write PPF-specific Excel sheets
    
    % Sheet 1: All_Data with PPF structure
    writeSheetWithCustomHeaders(organizedData, filepath, 'All_Data', 'PPF', roiInfo);
    
    % Sheet 2: Averaged data
    writeSheetWithCustomHeaders(averagedData, filepath, 'Averaged', 'PPF', roiInfo);
end

function write1APResults(organizedData, averagedData, roiInfo, filepath)
    % Write 1AP-specific Excel sheets with noise separation
    
    % Get column names for noise level separation
    varNames = organizedData.Properties.VariableNames;
    lowNoiseColumns = {'Frame'};
    highNoiseColumns = {'Frame'};
    
    % Separate columns by noise level
    for i = 2:length(varNames)
        colName = varNames{i};
        roiMatch = regexp(colName, 'ROI(\d+)_T', 'tokens');
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            if isKey(roiInfo.roiNoiseMap, roiNum)
                noiseLevel = roiInfo.roiNoiseMap(roiNum);
                if strcmp(noiseLevel, 'low')
                    lowNoiseColumns{end+1} = colName;
                elseif strcmp(noiseLevel, 'high')
                    highNoiseColumns{end+1} = colName;
                end
            end
        end
    end
    
    % Write Low_noise sheet
    if length(lowNoiseColumns) > 1
        lowNoiseData = organizedData(:, lowNoiseColumns);
        writeSheetWithCustomHeaders(lowNoiseData, filepath, 'Low_noise', '1AP', roiInfo);
    end
    
    % Write High_noise sheet
    if length(highNoiseColumns) > 1
        highNoiseData = organizedData(:, highNoiseColumns);
        writeSheetWithCustomHeaders(highNoiseData, filepath, 'High_noise', '1AP', roiInfo);
    end
    
    % Write ROI_Average sheet
    if isfield(averagedData, 'roi') && ~isempty(averagedData.roi)
        writeSheetWithCustomHeaders(averagedData.roi, filepath, 'ROI_Average', '1AP', roiInfo);
    end
    
    % Write Total_Average sheet
    if isfield(averagedData, 'total') && ~isempty(averagedData.total)
        writeTotalAverageSheet(averagedData.total, filepath);
    end
end

function writeSheetWithCustomHeaders(dataTable, filepath, sheetName, expType, roiInfo)
    % Write Excel sheet with custom two-row headers
    
    varNames = dataTable.Properties.VariableNames;
    numFrames = height(dataTable);
    
    % Create header rows
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    % First column (always Frame/Time)
    if strcmp(expType, 'PPF')
        row1{1} = sprintf('%dms', roiInfo.timepoint);
    else
        row1{1} = 'Trial/n';
    end
    row2{1} = 'Time (ms)';
    
    % Process remaining columns
    for i = 2:length(varNames)
        varName = varNames{i};
        
        if strcmp(expType, 'PPF')
            % PPF format parsing
            if contains(sheetName, 'Averaged')
                % Averaged: Cs1-c2_n24 format
                roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    row1{i} = roiMatch{1}{2};  % n count
                    row2{i} = roiMatch{1}{1};  % Cs-c
                else
                    row1{i} = '';
                    row2{i} = varName;
                end
            else
                % Individual: Cs1-c2_ROI3 format
                roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    row1{i} = roiMatch{1}{1};  % Cs-c
                    row2{i} = sprintf('ROI %s', roiMatch{1}{2});
                else
                    row1{i} = '';
                    row2{i} = varName;
                end
            end
        else
            % 1AP format parsing
            if contains(varName, '_n')
                % Averaged: ROI1_n3 format
                roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    row1{i} = roiMatch{1}{2};  % n count
                    row2{i} = sprintf('ROI %s', roiMatch{1}{1});
                else
                    row1{i} = '';
                    row2{i} = varName;
                end
            else
                % Individual: ROI1_T2 format
                roiMatch = regexp(varName, 'ROI(\d+)_T(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    row1{i} = roiMatch{1}{2};  % Trial number
                    row2{i} = sprintf('ROI %s', roiMatch{1}{1});
                else
                    row1{i} = '';
                    row2{i} = varName;
                end
            end
        end
    end
    
    % Write to Excel with custom headers
    try
        % Create data matrix
        timeData = dataTable.Frame;
        dataMatrix = [timeData, table2array(dataTable(:, 2:end))];
        
        % Create cell array for writing
        cellData = cell(numFrames + 2, length(varNames));
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
        fprintf('    WARNING: Custom header writing failed for %s (%s), using standard format\n', ...
                sheetName, ME.message);
        writetable(dataTable, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
    end
end

function writeTotalAverageSheet(totalAveragedData, filepath)
    % Write Total_Average sheet for 1AP experiments
    
    if width(totalAveragedData) <= 1
        return;
    end
    
    varNames = totalAveragedData.Properties.VariableNames;
    timeData_ms = totalAveragedData.Frame;
    numFrames = length(timeData_ms);
    
    % Create headers
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    row1{1} = 'Average Type';
    row2{1} = 'Time (ms)';
    
    for i = 2:length(varNames)
        varName = varNames{i};
        
        if contains(varName, 'Low_Noise')
            nMatch = regexp(varName, 'n(\d+)', 'tokens');
            if ~isempty(nMatch)
                row1{i} = nMatch{1}{1};
            else
                row1{i} = '';
            end
            row2{i} = 'Low Noise';
        elseif contains(varName, 'High_Noise')
            nMatch = regexp(varName, 'n(\d+)', 'tokens');
            if ~isempty(nMatch)
                row1{i} = nMatch{1}{1};
            else
                row1{i} = '';
            end
            row2{i} = 'High Noise';
        elseif contains(varName, 'All_')
            nMatch = regexp(varName, 'n(\d+)', 'tokens');
            if ~isempty(nMatch)
                row1{i} = nMatch{1}{1};
            else
                row1{i} = '';
            end
            row2{i} = 'All';
        else
            row1{i} = '';
            row2{i} = varName;
        end
    end
    
    % Write to Excel
    try
        dataMatrix = [timeData_ms, table2array(totalAveragedData(:, 2:end))];
        cellData = cell(numFrames + 2, length(varNames));
        
        cellData(1, :) = row1;
        cellData(2, :) = row2;
        
        for i = 1:numFrames
            for j = 1:size(dataMatrix, 2)
                cellData{i+2, j} = dataMatrix(i, j);
            end
        end
        
        writecell(cellData, filepath, 'Sheet', 'Total_Average');
        
    catch ME
        fprintf('    WARNING: Total average sheet writing failed (%s), using fallback\n', ME.message);
        writetable(totalAveragedData, filepath, 'Sheet', 'Total_Average', 'WriteVariableNames', true);
    end
end

function writeMetadataSheet(organizedData, roiInfo, filepath)
    % Write comprehensive metadata sheet
    
    if strcmp(roiInfo.experimentType, 'PPF')
        writeMetadataSheetPPF(organizedData, roiInfo, filepath);
    else
        writeMetadataSheet1AP(organizedData, roiInfo, filepath);
    end
end

function writeMetadataSheet1AP(organizedData, roiInfo, filepath)
    % Write 1AP metadata with noise levels
    
    cfg = GluSnFRConfig();
    maxEntries = length(roiInfo.roiNumbers) * roiInfo.numTrials;
    
    if maxEntries == 0
        return;
    end
    
    % Preallocate metadata
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
                        
                        % Extract threshold
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
        writetable(metadataTable, filepath, 'Sheet', 'ROI_Metadata');
    end
end

function writeMetadataSheetPPF(organizedData, roiInfo, filepath)
    % Write PPF metadata
    
    cfg = GluSnFRConfig();
    maxEntries = 0;
    for fileIdx = 1:length(roiInfo.coverslipFiles)
        maxEntries = maxEntries + length(roiInfo.coverslipFiles(fileIdx).roiNumbers);
    end
    
    if maxEntries == 0
        return;
    end
    
    % Preallocate metadata
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
                        allMetadata(entryCount).Baseline_Mean = 0;
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
        writetable(metadataTable, filepath, 'Sheet', 'ROI_Metadata');
    end
end

function writeExcelWithCustomHeaders(dataTable, filepath, sheetName, headerType, varargin)
    % COMPLETE IMPLEMENTATION: Write Excel with custom headers
    % This is a wrapper for the more specific functions above
    
    if nargin < 4
        headerType = 'standard';
    end
    
    try
        if strcmp(headerType, 'standard')
            writetable(dataTable, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
        else
            % Use the specialized header writing function
            if nargin >= 5
                roiInfo = varargin{1};
            else
                roiInfo = struct();
            end
            writeSheetWithCustomHeaders(dataTable, filepath, sheetName, headerType, roiInfo);
        end
        
    catch ME
        fprintf('ERROR writing Excel sheet %s: %s\n', sheetName, ME.message);
        rethrow(ME);
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

function [validHeaders, validColumns] = extractValidHeaders(headers)
    % Extract valid headers from raw header row
    
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