function io = io_manager()
    % IO_MANAGER - Streamlined file input/output operations
    
    % Core functions (keep these names simple)
    io.readExcelFile = @readExcelFile;
    io.getExcelFiles = @getExcelFiles;  % Fixed: matches function name
    io.writeExperimentResults = @writeExperimentResults;
    io.createDirectories = @createDirectoriesIfNeeded;
    io.saveLog = @saveLogToFile;
    io.extractValidHeaders = @extractValidHeaders;
    
    % Legacy support (keep existing function handles for compatibility)
    io.processFileData = @processFileData;
    io.writeExcelWithCustomHeaders = @writeExcelWithCustomHeaders;
end

function [data, headers, success] = readExcelFile(filepath, useMatrix)
    % READEXCELFILE - Fixed for your file structure
    % Row 1: Headers (ROI names)
    % Row 2+: Numeric fluorescence data
    
    success = false;
    data = [];
    headers = {};
    
    if ~exist(filepath, 'file')
        warning('File does not exist: %s', filepath);
        return;
    end
    
    try
        % Method 1: Read headers from row 1, data from row 2+
        headers = readcell(filepath, 'Range', 'A1:ZZ1');  % Row 1 only
        data = readmatrix(filepath, 'Range', 'A2:ZZ10000');  % From row 2 onwards
        
        % Clean up empty data
        data = removeEmptyData(data);
        headers = removeEmptyHeaders(headers, size(data, 2));
        
        if isempty(data) || size(data, 1) < 10  % At least 10 time points
            error('Insufficient data rows');
        end
        
        success = true;
        
    catch ME
        % Fallback method - read everything and parse
        try
            raw = readcell(filepath);  % Read entire file
            
            if size(raw, 1) < 2
                error('File has less than 2 rows');
            end
            
            headers = raw(1, :);  % First row = headers
            dataRows = raw(2:end, :);  % Rest = data
            data = convertCellToNumeric(dataRows);
            
            % Clean up
            data = removeEmptyData(data);
            headers = removeEmptyHeaders(headers, size(data, 2));
            
            success = true;
            
        catch ME2
            error('Failed to read Excel file %s: %s', filepath, ME2.message);
        end
    end
end

function excelFiles = getExcelFiles(folder)
    % GETEXCELFILES - Fixed validation
    
    if ~exist(folder, 'dir')
        error('Folder does not exist: %s', folder);
    end
    
    allFiles = dir(fullfile(folder, '*.xlsx'));
    
    if isempty(allFiles)
        error('No Excel files found in folder: %s', folder);
    end
    
    % Use parallel validation for large sets
    if length(allFiles) > 10
        validFiles = validateFilesParallel(allFiles);
    else
        validFiles = validateFilesSequential(allFiles);
    end
    
    if isempty(validFiles)
        error('No valid Excel files found in folder: %s', folder);
    end
    
    excelFiles = validFiles;
    fprintf('Found %d valid Excel files\n', length(excelFiles));
end

% Helper functions for file reading
function cleanData = removeEmptyData(data)
    % Remove completely empty rows and columns
    validRows = ~all(isnan(data), 2);
    cleanData = data(validRows, :);
    validCols = ~all(isnan(cleanData), 1);
    cleanData = cleanData(:, validCols);
end

function cleanHeaders = removeEmptyHeaders(headers, numDataCols)
    % Match headers to data columns
    if length(headers) > numDataCols
        cleanHeaders = headers(1:numDataCols);
    else
        cleanHeaders = headers;
        while length(cleanHeaders) < numDataCols
            cleanHeaders{end+1} = sprintf('Col%d', length(cleanHeaders)+1);
        end
    end
    
    for i = 1:length(cleanHeaders)
        if isempty(cleanHeaders{i}) || ismissing(cleanHeaders{i})
            cleanHeaders{i} = sprintf('Col%d', i);
        end
    end
end

function numericData = convertCellToNumeric(cellData)
    % Convert cell array to numeric matrix
    [numRows, numCols] = size(cellData);
    numericData = NaN(numRows, numCols, 'single');
    
    for col = 1:numCols
        colData = cellData(:, col);
        
        % Handle numeric cells
        numericMask = cellfun(@isnumeric, colData) & ~cellfun(@isempty, colData);
        if any(numericMask)
            numericValues = cell2mat(colData(numericMask));
            numericData(numericMask, col) = single(numericValues);
        end
        
        % Convert string/char numbers
        stringMask = cellfun(@(x) ischar(x) || isstring(x), colData) & ~cellfun(@isempty, colData);
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

function validFiles = validateFilesSequential(allFiles)
    % Sequential validation
    validFiles = [];
    for i = 1:length(allFiles)
        filepath = fullfile(allFiles(i).folder, allFiles(i).name);
        if isValidFile(filepath)
            validFiles = [validFiles; allFiles(i)];
        end
    end
end

function validFiles = validateFilesParallel(allFiles)
    % Parallel validation
    numFiles = length(allFiles);
    isValid = false(numFiles, 1);
    
    parfor i = 1:numFiles
        filepath = fullfile(allFiles(i).folder, allFiles(i).name);
        isValid(i) = isValidFile(filepath);
    end
    
    validFiles = allFiles(isValid);
end

function isValid = isValidFile(filepath)
    % FIXED validation - matches your file structure
    
    try
        % Test 1: Can we read headers from row 1?
        headers = readcell(filepath, 'Range', 'A1:E1');  % FIXED: removed NumHeaderLines
        if isempty(headers)
            isValid = false;
            return;
        end
        
        % Test 2: Can we read numeric data from row 2+?
        testData = readmatrix(filepath, 'Range', 'A2:E20');  % FIXED: removed NumHeaderLines
        if isempty(testData) || size(testData, 1) < 10
            isValid = false;
            return;
        end
        
        % Test 3: Do we have actual numeric values (not all NaN)?
        if all(isnan(testData(:)))
            isValid = false;
            return;
        end
        
        isValid = true;
        
    catch
        isValid = false;
    end
end

% Keep existing functions for compatibility
function [data, metadata] = processFileData(rawData, headers, fileInfo, calc, filter, utils, hasGPU, gpuInfo)
    % Process individual file data
    cfg = GluSnFRConfig();
    
    [validHeaders, validColumns] = extractValidHeaders(headers);
    if isempty(validHeaders)
        error('No valid ROI headers found');
    end
    
    numericData = single(rawData(:, validColumns));
    timeData_ms = single((0:(size(numericData, 1)-1))' * cfg.timing.MS_PER_FRAME);
    
    [dF_values, thresholds, gpuUsed] = calc.calculate(numericData, hasGPU, gpuInfo);
    
    [trialNum, expType, ppiValue, coverslipCell] = utils.extractTrialOrPPI(fileInfo.name);
    
    if strcmp(expType, 'PPF') && isfinite(ppiValue)
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, 'PPF', ppiValue);
    else
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
    end
    
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

function writeExperimentResults(organizedData, averagedData, roiInfo, groupKey, outputFolder, cfg)
    % Write experiment results to Excel
    if nargin < 6
        cfg = GluSnFRConfig();
    end
    
    if ~cfg.output.ENABLE_EXCEL_OUTPUT
        return;
    end
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    filename = [cleanGroupKey '_grouped.xlsx'];
    filepath = fullfile(outputFolder, filename);
    
    if exist(filepath, 'file')
        delete(filepath);
    end
    
    try
        if strcmp(roiInfo.experimentType, 'PPF')
            writePPFResults(organizedData, averagedData, roiInfo, filepath, cfg);
        else
            write1APResults(organizedData, averagedData, roiInfo, filepath, cfg);
        end
        
        if cfg.output.ENABLE_METADATA_SHEET
            writeMetadataSheet(organizedData, roiInfo, filepath);
        end
        
    catch ME
        if cfg.output.ENABLE_VERBOSE_OUTPUT
            fprintf('ERROR saving Excel file %s: %s\n', filename, ME.message);
        end
        rethrow(ME);
    end
end

function writePPFResults(organizedData, averagedData, roiInfo, filepath, cfg)
    % Write PPF results
    if cfg.output.ENABLE_INDIVIDUAL_SHEETS
        fields = {'allData', 'bothPeaks', 'singlePeak'};
        sheetNames = {'All_Data', 'Both_Peaks', 'Single_Peak'};
        
        for i = 1:length(fields)
            if isfield(organizedData, fields{i}) && width(organizedData.(fields{i})) > 1
                try
                    writetable(organizedData.(fields{i}), filepath, 'Sheet', sheetNames{i});
                catch, end
            end
        end
    end
    
    if cfg.output.ENABLE_AVERAGED_SHEETS && isstruct(averagedData)
        fields = {'allData', 'bothPeaks', 'singlePeak'};
        sheetNames = {'All_Data_Avg', 'Both_Peaks_Avg', 'Single_Peak_Avg'};
        
        for i = 1:length(fields)
            if isfield(averagedData, fields{i}) && width(averagedData.(fields{i})) > 1
                try
                    writetable(averagedData.(fields{i}), filepath, 'Sheet', sheetNames{i});
                catch, end
            end
        end
    end
end

function write1APResults(organizedData, averagedData, roiInfo, filepath, cfg)
    % Write 1AP results
    if cfg.output.ENABLE_NOISE_SEPARATED_SHEETS
        writeNoiseBasedSheets(organizedData, roiInfo, filepath);
    end
    
    if cfg.output.ENABLE_ROI_AVERAGE_SHEET && isfield(averagedData, 'roi') && width(averagedData.roi) > 1
        try
            writetable(averagedData.roi, filepath, 'Sheet', 'ROI_Average');
        catch, end
    end
    
    if cfg.output.ENABLE_TOTAL_AVERAGE_SHEET && isfield(averagedData, 'total') && width(averagedData.total) > 1
        try
            writetable(averagedData.total, filepath, 'Sheet', 'Total_Average');
        catch, end
    end
end

function writeNoiseBasedSheets(organizedData, roiInfo, filepath)
    % Write Low_noise and High_noise sheets
    varNames = organizedData.Properties.VariableNames;
    lowNoiseColumns = {'Frame'};
    highNoiseColumns = {'Frame'};
    
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
    
    if length(lowNoiseColumns) > 1
        try
            lowNoiseData = organizedData(:, lowNoiseColumns);
            writetable(lowNoiseData, filepath, 'Sheet', 'Low_noise');
        catch, end
    end
    
    if length(highNoiseColumns) > 1
        try
            highNoiseData = organizedData(:, highNoiseColumns);
            writetable(highNoiseData, filepath, 'Sheet', 'High_noise');
        catch, end
    end
end

function writeMetadataSheet(organizedData, roiInfo, filepath)
    % Write metadata sheet
    try
        analyzer = experiment_analyzer();
        metadataTable = analyzer.generateMetadata(organizedData, roiInfo, filepath);
    catch
        % Silent failure for metadata
    end
end

function writeExcelWithCustomHeaders(dataTable, filepath, sheetName, headerType, varargin)
    % Write Excel with custom headers
    if nargin < 4
        headerType = 'standard';
    end
    
    try
        if strcmp(headerType, 'standard')
            writetable(dataTable, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
        else
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

function writeSheetWithCustomHeaders(dataTable, filepath, sheetName, expType, roiInfo)
    % Write Excel sheet with custom headers
    try
        % Simple fallback to standard table writing
        writetable(dataTable, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
    catch ME
        error('Failed to write sheet %s: %s', sheetName, ME.message);
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
    
    validHeaders = validHeaders(1:validCount);
    validColumns = validColumns(1:validCount);
end