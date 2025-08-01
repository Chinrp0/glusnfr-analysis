function io = io_manager()
    % IO_MANAGER - Streamlined file input/output operations
    
    io.readExcelFile = @readExcelFileFast;  % Changed
    io.writeExperimentResults = @writeExperimentResults;
    io.createDirectories = @createDirectoriesIfNeeded;
    io.validateFile = @validateExcelFile;
    io.getExcelFiles = @getExcelFiles;  % Changed
    io.saveLog = @saveLogToFile;
    io.extractValidHeaders = @extractValidHeaders;
    
    % Keep these existing function handles
    io.readExcelFileOptimized = @readExcelFileOptimized;
    io.processFileData = @processFileData;
    io.writeExcelWithCustomHeaders = @writeExcelWithCustomHeaders;
end

function [data, headers, success] = readExcelFileFast(filepath, useReadMatrix)
    % FAST: Streamlined Excel reading with best method only
    
    success = false;
    data = [];
    headers = {};
    
    if ~exist(filepath, 'file')
        warning('File does not exist: %s', filepath);
        return;
    end
    
    try
        % Use readcell - fastest and most reliable for R2019a+
        raw = readcell(filepath, 'NumHeaderLines', 0);
        
        if isempty(raw) || size(raw, 1) < 3
            error('Insufficient data rows');
        end
        
        % Extract headers and data
        headers = raw(2, :);  % Row 2 contains ROI headers
        dataRows = raw(3:end, :);  % Row 3+ contains data
        
        % Fast numeric conversion
        data = convertToNumericFast(dataRows);
        success = true;
        
    catch ME
        error('Failed to read Excel file %s: %s', filepath, ME.message);
    end
end

function numericData = convertToNumericFast(dataRows)
    % FAST: Vectorized numeric conversion
    
    [numRows, numCols] = size(dataRows);
    numericData = NaN(numRows, numCols, 'single');
    
    % Vectorized approach for numeric columns
    for col = 1:numCols
        colData = dataRows(:, col);
        
        % Check if column is already numeric
        isNumericCol = cellfun(@isnumeric, colData);
        isEmptyCol = cellfun(@isempty, colData);
        
        % Handle numeric values
        numericMask = isNumericCol & ~isEmptyCol;
        if any(numericMask)
            numericValues = cell2mat(colData(numericMask));
            numericData(numericMask, col) = single(numericValues);
        end
        
        % Handle string/char values that might be numbers
        stringMask = ~isNumericCol & ~isEmptyCol;
        if any(stringMask)
            stringIndices = find(stringMask);
            for idx = stringIndices'
                val = str2double(colData{idx});
                if isfinite(val)
                    numericData(idx, col) = single(val);
                end
            end
        end
    end
end

function excelFiles = getExcelFiles(folder)
    % FAST: Get Excel files with minimal validation
    
    if ~exist(folder, 'dir')
        error('Folder does not exist: %s', folder);
    end
    
    % Get all Excel files
    allFiles = dir(fullfile(folder, '*.xlsx'));
    
    if isempty(allFiles)
        error('No Excel files found in folder: %s', folder);
    end
    
    % Basic validation - just check if readable
    validFiles = [];
    for i = 1:length(allFiles)
        filepath = fullfile(allFiles(i).folder, allFiles(i).name);
        if validateExcelFile(filepath)
            validFiles = [validFiles; allFiles(i)];
        end
    end
    
    if isempty(validFiles)
        error('No valid Excel files found in folder: %s', folder);
    end
    
    excelFiles = validFiles;
    fprintf('Found %d valid Excel files\n', length(excelFiles));
end

function isValid = validateExcelFile(filepath)
    % FAST: Minimal validation - just check if readable
    
    try
        % Quick test read of first few cells
        testData = readcell(filepath, 'Range', 'A1:E5', 'NumHeaderLines', 0);
        isValid = ~isempty(testData) && size(testData, 1) >= 3;
    catch
        isValid = false;
    end
end

function [rawData, headers, success] = readExcelFileOptimized(filepath, io)
    % OPTIMIZED: Faster Excel reading with better fallback strategy
    
    success = false;
    rawData = [];
    headers = {};
    
    try
        % Method 1: readmatrix (fastest for numeric data) - MATLAB R2019a+
        if ~verLessThan('matlab', '9.6')
            try
                % Read data portion directly as matrix
                rawMatrix = readmatrix(filepath, 'Range', 'A3:ZZ10000'); % Adjust range as needed
                % Read headers separately  
                headerTable = readtable(filepath, 'Range', 'A2:ZZ2', 'ReadVariableNames', false);
                headers = table2cell(headerTable);
                rawData = rawMatrix;
                success = true;
                return;
            catch
                % Fall back to original method
            end
        end
        
        % Method 2: Original method as fallback
        [rawData, headers, success] = io.readExcelFile(filepath, true);
        
    catch ME
        error('Optimized Excel reading failed: %s', ME.message);
        success = false;
    end
end

function [data, metadata] = processFileData(rawData, headers, fileInfo, calc, filter, utils, hasGPU, gpuInfo)
    % Process individual file data (extracted from processSingleFile for parallel use)
    
    cfg = calc.config;
    
    % Extract valid data
    [validHeaders, validColumns] = extractValidHeadersOptimized(headers);
    if isempty(validHeaders)
        error('No valid ROI headers found');
    end
    
    % Vectorized data extraction
    numericData = single(rawData(:, validColumns));
    timeData_ms = single((0:(size(numericData, 1)-1))' * cfg.timing.MS_PER_FRAME);
    
    % Calculate dF/F with optimized GPU decision
    [dF_values, thresholds, gpuUsed] = calc.calculate(numericData, hasGPU, gpuInfo);
    
    % Extract experiment info
    [trialNum, expType, ppiValue, coverslipCell] = utils.extractTrialOrPPI(fileInfo.name);
    
    % Apply filtering
    if strcmp(expType, 'PPF') && isfinite(ppiValue)
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, 'PPF', ppiValue);
    else
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
    end
    
    % Package results
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
end

function [validHeaders, validColumns] = extractValidHeadersOptimized(headers)
    % OPTIMIZED: Vectorized header extraction
    
    % Vectorized approach - much faster than loops
    isValidCell = ~cellfun(@isempty, headers) & ...
                  (cellfun(@ischar, headers) | cellfun(@isstring, headers));
    
    validIndices = find(isValidCell);
    validHeaders = headers(validIndices);
    
    % Remove empty strings
    nonEmptyMask = ~cellfun(@(x) isempty(strtrim(char(x))), validHeaders);
    validHeaders = validHeaders(nonEmptyMask);
    validColumns = validIndices(nonEmptyMask);
    
    fprintf('      Extracted %d valid headers (vectorized)\n', length(validHeaders));
end

function writeExperimentResults(organizedData, averagedData, roiInfo, groupKey, outputFolder, cfg)
    % Write experiment results with configurable Excel output
    
    if nargin < 6
        cfg = GluSnFRConfig();
    end
    
    % Check if Excel output is enabled
    if ~cfg.output.ENABLE_EXCEL_OUTPUT
        return;
    end
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    filename = [cleanGroupKey '_grouped.xlsx'];
    filepath = fullfile(outputFolder, filename);
    
    % Delete existing file
    if exist(filepath, 'file')
        delete(filepath);
    end
    
    try
        hasValidData = false;
        sheetsWritten = 0;
        
        if strcmp(roiInfo.experimentType, 'PPF')
            if isstruct(organizedData)
                if (isfield(organizedData, 'allData') && width(organizedData.allData) > 1) || ...
                   (isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1) || ...
                   (isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1)
                    hasValidData = true;
                end
            end
        else
            if istable(organizedData) && width(organizedData) > 1
                hasValidData = true;
            end
        end
        
        if ~hasValidData
            if cfg.output.ENABLE_VERBOSE_OUTPUT
                warning('No data to write for group %s', groupKey);
            end
            return;
        end
        
        if strcmp(roiInfo.experimentType, 'PPF')
            sheetsWritten = writePPFResults(organizedData, averagedData, roiInfo, filepath, cfg);
        else
            sheetsWritten = write1APResults(organizedData, averagedData, roiInfo, filepath, cfg);
        end
        
        % Write metadata sheet if enabled
        if cfg.output.ENABLE_METADATA_SHEET
            writeMetadataSheet(organizedData, roiInfo, filepath);
            sheetsWritten = sheetsWritten + 1;
        end
        
    catch ME
        if cfg.output.ENABLE_VERBOSE_OUTPUT
            fprintf('ERROR saving Excel file %s: %s\n', filename, ME.message);
        end
        rethrow(ME);
    end
end

function sheetsWritten = writePPFResults(organizedData, averagedData, roiInfo, filepath, cfg)
    % Write PPF results based on configuration
    
    sheetsWritten = 0;
    
    % Write individual data sheets if enabled
    if cfg.output.ENABLE_INDIVIDUAL_SHEETS
        if isfield(organizedData, 'allData') && width(organizedData.allData) > 1
            try
                writeSheetWithHeaders(organizedData.allData, filepath, 'All_Data', 'PPF', roiInfo);
                sheetsWritten = sheetsWritten + 1;
            catch, end
        end
        
        if isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1
            try
                writeSheetWithHeaders(organizedData.bothPeaks, filepath, 'Both_Peaks', 'PPF', roiInfo);
                sheetsWritten = sheetsWritten + 1;
            catch, end
        end
        
        if isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1
            try
                writeSheetWithHeaders(organizedData.singlePeak, filepath, 'Single_Peak', 'PPF', roiInfo);
                sheetsWritten = sheetsWritten + 1;
            catch, end
        end
    end
    
    % Write averaged sheets if enabled
    if cfg.output.ENABLE_AVERAGED_SHEETS && isstruct(averagedData)
        if isfield(averagedData, 'allData') && width(averagedData.allData) > 1
            try
                writeSheetWithHeaders(averagedData.allData, filepath, 'All_Data_Avg', 'PPF', roiInfo);
                sheetsWritten = sheetsWritten + 1;
            catch, end
        end
        
        if isfield(averagedData, 'bothPeaks') && width(averagedData.bothPeaks) > 1
            try
                writeSheetWithHeaders(averagedData.bothPeaks, filepath, 'Both_Peaks_Avg', 'PPF', roiInfo);
                sheetsWritten = sheetsWritten + 1;
            catch, end
        end
        
        if isfield(averagedData, 'singlePeak') && width(averagedData.singlePeak) > 1
            try
                writeSheetWithHeaders(averagedData.singlePeak, filepath, 'Single_Peak_Avg', 'PPF', roiInfo);
                sheetsWritten = sheetsWritten + 1;
            catch, end
        end
    end
end

function sheetsWritten = write1APResults(organizedData, averagedData, roiInfo, filepath, cfg)
    % Write 1AP results based on configuration
    
    sheetsWritten = 0;
    
    % Write noise-based sheets if enabled
    if cfg.output.ENABLE_NOISE_SEPARATED_SHEETS
        sheetsWritten = sheetsWritten + writeNoiseBasedSheets(organizedData, roiInfo, filepath);
    end
    
    % Write ROI averaged sheet if enabled
    if cfg.output.ENABLE_ROI_AVERAGE_SHEET && isfield(averagedData, 'roi') && width(averagedData.roi) > 1
        try
            writeROIAverageSheet(averagedData.roi, roiInfo, filepath);
            sheetsWritten = sheetsWritten + 1;
        catch, end
    end
    
    % Write total average sheet if enabled
    if cfg.output.ENABLE_TOTAL_AVERAGE_SHEET && isfield(averagedData, 'total') && width(averagedData.total) > 1
        try
            writeTotalAverageSheet(averagedData.total, filepath);
            sheetsWritten = sheetsWritten + 1;
        catch, end
    end
end


function sheetsWritten = writeNoiseBasedSheets(organizedData, roiInfo, filepath)
    % Write separate Low_noise and High_noise sheets
    
    sheetsWritten = 0;
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
    
    % Write sheets
    if length(lowNoiseColumns) > 1
        try
            lowNoiseData = organizedData(:, lowNoiseColumns);
            writeSheetWithHeaders(lowNoiseData, filepath, 'Low_noise', '1AP', []);
            sheetsWritten = sheetsWritten + 1;
        catch, end
    end
    
    if length(highNoiseColumns) > 1
        try
            highNoiseData = organizedData(:, highNoiseColumns);
            writeSheetWithHeaders(highNoiseData, filepath, 'High_noise', '1AP', []);
            sheetsWritten = sheetsWritten + 1;
        catch, end
    end
end

function writeSheetWithHeaders(dataTable, filepath, sheetName, expType, roiInfo)
    % Write Excel sheet with custom headers
    
    try
        writetable(dataTable, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
    catch ME
        error('Failed to write sheet %s: %s', sheetName, ME.message);
    end
end

function writeROIAverageSheet(averagedData, roiInfo, filepath)
    % Write ROI_Average sheet
    
    try
        writetable(averagedData, filepath, 'Sheet', 'ROI_Average', 'WriteVariableNames', true);
    catch ME
        error('Failed to write ROI_Average sheet: %s', ME.message);
    end
end

function writeTotalAverageSheet(totalAveragedData, filepath)
    % Write Total_Average sheet
    
    try
        writetable(totalAveragedData, filepath, 'Sheet', 'Total_Average', 'WriteVariableNames', true);
    catch ME
        error('Failed to write Total_Average sheet: %s', ME.message);
    end
end

function writeMetadataSheet(organizedData, roiInfo, filepath)
    % Write metadata sheet if enabled
    
    try
        analyzer = experiment_analyzer();
        metadataTable = analyzer.generateMetadata(organizedData, roiInfo, filepath);
    catch
        % Silent failure for metadata
    end
end

function writeMetadataSheet1AP(organizedData, roiInfo, filepath)
    % UPDATED: Write 1AP metadata with minimal output
    
    cfg = GluSnFRConfig();
    maxEntries = length(roiInfo.roiNumbers) * roiInfo.numTrials;
    
    if maxEntries == 0
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
            catch ME
                warning('Failed to create directory %s: %s', dir_path, ME.message);
            end
        end
    end
end

function writeSheetWithCustomHeaders(dataTable, filepath, sheetName, expType, roiInfo)
    % UPDATED: Write Excel sheet with custom two-row headers (minimal output)
    
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
        % Fallback to standard format
        writetable(dataTable, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
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
        
        for i = 1:length(logBuffer)
            fprintf(fid, '%s\n', logBuffer{i});
        end
        
        fclose(fid);
        
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
end