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
    % FIXED: Complete experiment results writing with all expected sheets
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    filename = [cleanGroupKey '_grouped.xlsx'];
    filepath = fullfile(outputFolder, filename);
    
    % Delete existing file
    if exist(filepath, 'file')
        delete(filepath);
    end
    
    fprintf('    Writing Excel results: %s\n', filename);
    
    try
            % FIXED: Better check for valid data
            hasValidData = false;
            
            if strcmp(roiInfo.experimentType, 'PPF')
                % For PPF, check if any of the organized data tables have content
                if isstruct(organizedData)
                    if (isfield(organizedData, 'allData') && width(organizedData.allData) > 1) || ...
                       (isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1) || ...
                       (isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1)
                        hasValidData = true;
                    end
                end
            else
                % For 1AP, check if organized data table has content
                if istable(organizedData) && width(organizedData) > 1
                    hasValidData = true;
                end
            end
            
            if ~hasValidData
                warning('No data to write for group %s', groupKey);
                return;
            end
        
        if strcmp(roiInfo.experimentType, 'PPF')
            writePPFResults(organizedData, averagedData, roiInfo, filepath);
        else
            % FIXED: Write ALL 1AP sheets
            write1APResultsComplete(organizedData, averagedData, roiInfo, filepath);
        end
        
        % Always write metadata sheet
        writeMetadataSheet(organizedData, roiInfo, filepath);
        
        fprintf('    Excel file saved: %s\n', filepath);
        
    catch ME
        fprintf('    ERROR saving Excel file %s: %s\n', filename, ME.message);
        fprintf('    Stack: %s\n', ME.stack(1).name);
        rethrow(ME);
    end
end


function writePPFResults(organizedData, averagedData, roiInfo, filepath)
    % Write PPF results with separate sheets for different response patterns
    % Now with robust error handling and fallbacks
    
    fprintf('      Writing PPF sheets...\n');
    
    sheetsWritten = 0;
    
    % Always write All_Data sheet first (this should always exist)
    if isfield(organizedData, 'allData') && width(organizedData.allData) > 1
        try
            writeSheetWithCustomHeaders(organizedData.allData, filepath, 'All_Data', 'PPF', roiInfo);
            fprintf('      ✓ All_Data sheet: %d columns\n', width(organizedData.allData)-1);
            sheetsWritten = sheetsWritten + 1;
        catch ME
            fprintf('      ⚠ Failed to write All_Data sheet: %s\n', ME.message);
        end
    end
    
    % Write Both_Peaks sheet if available
    if isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1
        try
            writeSheetWithCustomHeaders(organizedData.bothPeaks, filepath, 'Both_Peaks', 'PPF', roiInfo);
            fprintf('      ✓ Both_Peaks sheet: %d columns\n', width(organizedData.bothPeaks)-1);
            sheetsWritten = sheetsWritten + 1;
        catch ME
            fprintf('      ⚠ Failed to write Both_Peaks sheet: %s\n', ME.message);
        end
    else
        fprintf('      - No Both_Peaks data available\n');
    end
    
    % Write Single_Peak sheet if available
    if isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1
        try
            writeSheetWithCustomHeaders(organizedData.singlePeak, filepath, 'Single_Peak', 'PPF', roiInfo);
            fprintf('      ✓ Single_Peak sheet: %d columns\n', width(organizedData.singlePeak)-1);
            sheetsWritten = sheetsWritten + 1;
        catch ME
            fprintf('      ⚠ Failed to write Single_Peak sheet: %s\n', ME.message);
        end
    else
        fprintf('      - No Single_Peak data available\n');
    end
    
    % Write averaged sheets
    if isfield(averagedData, 'allData') && width(averagedData.allData) > 1
        try
            writeSheetWithCustomHeaders(averagedData.allData, filepath, 'All_Data_Avg', 'PPF', roiInfo);
            fprintf('      ✓ All_Data_Avg sheet written\n');
            sheetsWritten = sheetsWritten + 1;
        catch ME
            fprintf('      ⚠ Failed to write All_Data_Avg sheet: %s\n', ME.message);
        end
    end
    
    if isfield(averagedData, 'bothPeaks') && width(averagedData.bothPeaks) > 1
        try
            writeSheetWithCustomHeaders(averagedData.bothPeaks, filepath, 'Both_Peaks_Avg', 'PPF', roiInfo);
            fprintf('      ✓ Both_Peaks_Avg sheet written\n');
            sheetsWritten = sheetsWritten + 1;
        catch ME
            fprintf('      ⚠ Failed to write Both_Peaks_Avg sheet: %s\n', ME.message);
        end
    end
    
    if isfield(averagedData, 'singlePeak') && width(averagedData.singlePeak) > 1
        try
            writeSheetWithCustomHeaders(averagedData.singlePeak, filepath, 'Single_Peak_Avg', 'PPF', roiInfo);
            fprintf('      ✓ Single_Peak_Avg sheet written\n');
            sheetsWritten = sheetsWritten + 1;
        catch ME
            fprintf('      ⚠ Failed to write Single_Peak_Avg sheet: %s\n', ME.message);
        end
    end
    
    if sheetsWritten == 0
        error('No PPF sheets could be written - check data organization');
    else
        fprintf('      PPF Excel writing complete: %d sheets written\n', sheetsWritten);
    end
end

function write1APResultsComplete(organizedData, averagedData, roiInfo, filepath)
    % FIXED: Write ALL expected 1AP sheets including noise-based separation
    
    fprintf('      Writing 1AP sheets...\n');
    
    % SHEET 1: Write noise-based trial sheets (Low_noise, High_noise)
    writeNoiseBasedTrialsSheets(organizedData, roiInfo, filepath);
    
    % SHEET 2: Write ROI_Average sheet
    if isfield(averagedData, 'roi') && ~isempty(averagedData.roi) && width(averagedData.roi) > 1
        writeROIAveragedSheet(averagedData.roi, roiInfo, filepath);
        fprintf('      ✓ ROI_Average sheet written\n');
    else
        fprintf('      ⚠ No ROI averaged data to write\n');
    end
    
    % SHEET 3: Write Total_Average sheet
    if isfield(averagedData, 'total') && ~isempty(averagedData.total) && width(averagedData.total) > 1
        writeTotalAverageSheet(averagedData.total, filepath);
        fprintf('      ✓ Total_Average sheet written\n');
    else
        fprintf('      ⚠ No total averaged data to write\n');
    end
end

function writeNoiseBasedTrialsSheets(organizedData, roiInfo, filepath)
    % FIXED: Write separate Low_noise and High_noise sheets
    
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
        fprintf('      ✓ Low_noise sheet: %d columns\n', length(lowNoiseColumns)-1);
    else
        fprintf('      ⚠ No low noise data to write\n');
    end
    
    % Write High_noise sheet
    if length(highNoiseColumns) > 1
        highNoiseData = organizedData(:, highNoiseColumns);
        writeSheetWithCustomHeaders(highNoiseData, filepath, 'High_noise', '1AP', roiInfo);
        fprintf('      ✓ High_noise sheet: %d columns\n', length(highNoiseColumns)-1);
    else
        fprintf('      ⚠ No high noise data to write\n');
    end
end

function writeROIAveragedSheet(averagedData, roiInfo, filepath)
    % FIXED: Write ROI_Average sheet with proper headers and data validation
    
    if width(averagedData) <= 1
        fprintf('      ⚠ ROI averaged data is empty\n');
        return;
    end
    
    varNames = averagedData.Properties.VariableNames;
    timeData_ms = averagedData.Frame;
    numFrames = length(timeData_ms);
    
    % Create header rows
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    row1{1} = 'n';
    row2{1} = 'Time (ms)';
    
    % Process each variable
    for i = 2:length(varNames)
        varName = varNames{i};
        
        roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
        if ~isempty(roiMatch)
            roiNum = roiMatch{1}{1};
            nTrials = roiMatch{1}{2};
            
            row1{i} = nTrials;
            row2{i} = ['ROI ' roiNum];
        else
            row1{i} = '';
            row2{i} = varName;
        end
    end
    
    % FIXED: Write data with validation
    try
        dataMatrix = [timeData_ms, table2array(averagedData(:, 2:end))];
        
        % Validate data matrix
        if any(isnan(dataMatrix(:)))
            fprintf('      ⚠ ROI averaged data contains NaN values\n');
        end
        
        cellData = cell(numFrames + 2, length(varNames));
        
        cellData(1, :) = row1;
        cellData(2, :) = row2;
        
        for i = 1:numFrames
            for j = 1:size(dataMatrix, 2)
                cellData{i+2, j} = dataMatrix(i, j);
            end
        end
        
        writecell(cellData, filepath, 'Sheet', 'ROI_Average');
        
    catch ME
        fprintf('      ⚠ ROI averaged sheet writing failed (%s), using fallback\n', ME.message);
        writetable(averagedData, filepath, 'Sheet', 'ROI_Average', 'WriteVariableNames', true);
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
    % FIXED: Write Total_Average sheet with proper validation
    
    if width(totalAveragedData) <= 1
        fprintf('      ⚠ Total averaged data is empty\n');
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
        
        % Validate data matrix
        if size(dataMatrix, 2) <= 1
            fprintf('      ⚠ Total averaged data has no data columns\n');
            return;
        end
        
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
        fprintf('      ⚠ Total averaged sheet writing failed (%s), using fallback\n', ME.message);
        writetable(totalAveragedData, filepath, 'Sheet', 'Total_Average', 'WriteVariableNames', true);
    end
end


function writeMetadataSheet(organizedData, roiInfo, filepath)
    % FIXED: Write metadata sheet with proper PPF structure handling
    
    try
        if strcmp(roiInfo.experimentType, 'PPF')
            % For PPF, need to use experiment analyzer to generate metadata
            analyzer = experiment_analyzer();
            metadataTable = analyzer.generateMetadata(organizedData, roiInfo, filepath);
        else
            writeMetadataSheet1AP(organizedData, roiInfo, filepath);
        end
        
        if ~isempty(metadataTable)
            fprintf('      ✓ ROI_Metadata sheet written\n');
        end
        
    catch ME
        fprintf('      ⚠ Metadata sheet writing failed: %s\n', ME.message);
        
        % Debug: Show what type of data we're trying to process
        if strcmp(roiInfo.experimentType, 'PPF')
            fprintf('        Debug: PPF organizedData type = %s\n', class(organizedData));
            if isstruct(organizedData)
                fprintf('        Debug: PPF organizedData fields = %s\n', strjoin(fieldnames(organizedData), ', '));
            end
        end
    end
end

function writeMetadataSheet1AP(organizedData, roiInfo, filepath)
    % Write 1AP metadata
    
    cfg = GluSnFRConfig();
    maxEntries = length(roiInfo.roiNumbers) * roiInfo.numTrials;
    
    if maxEntries == 0
        fprintf('        ⚠ No metadata entries to write\n');
        return;
    end
    
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
        fprintf('        ✓ 1AP metadata: %d entries\n', entryCount);
    else
        fprintf('        ⚠ No valid 1AP metadata to write\n');
    end
end

function writeMetadataSheetPPF(organizedData, roiInfo, filepath)
    % Write PPF metadata - simplified version
    
    cfg = GluSnFRConfig();
    maxEntries = 0;
    for fileIdx = 1:length(roiInfo.coverslipFiles)
        maxEntries = maxEntries + length(roiInfo.coverslipFiles(fileIdx).roiNumbers);
    end
    
    if maxEntries == 0
        return;
    end
    
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
                entryCount = entryCount + 1;
                allMetadata(entryCount).CoverslipCell = csCell;
                allMetadata(entryCount).ROI_Number = roiNum;
                allMetadata(entryCount).Column_Name = columnName;
                
                if roiIdx <= length(fileData.thresholds)
                    threshold = fileData.thresholds(roiIdx);
                    allMetadata(entryCount).Threshold_dF_F = threshold;
                    allMetadata(entryCount).Baseline_SD = threshold / cfg.thresholds.SD_MULTIPLIER;
                end
                
                allMetadata(entryCount).Baseline_Mean = 0;
                allMetadata(entryCount).Experiment_Type = 'PPF';
                allMetadata(entryCount).Timepoint_ms = roiInfo.timepoint;
                allMetadata(entryCount).Stimulus1_Time_ms = cfg.timing.STIMULUS_TIME_MS;
                allMetadata(entryCount).Stimulus2_Time_ms = cfg.timing.STIMULUS_TIME_MS + roiInfo.timepoint;
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