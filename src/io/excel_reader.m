function reader = excel_reader()
    % EXCEL_READER - Specialized Excel file reading operations
    
    reader.readFile = @readExcelFile;
    reader.getFiles = @getExcelFiles;
    reader.validateFile = @validateExcelFile;
    reader.extractHeaders = @extractValidHeaders;
    reader.processFileData = @processFileData;
end

function [data, headers, success] = readExcelFile(filepath, useOptimized)
    % READEXCELFILE - Optimized Excel reading with fallback strategy
    
    success = false;
    data = [];
    headers = {};
    
    if ~exist(filepath, 'file')
        warning('File does not exist: %s', filepath);
        return;
    end
    
    if nargin < 2
        useOptimized = true;
    end
    
    try
        if useOptimized && ~verLessThan('matlab', '9.6')
            % Method 1: readmatrix (fastest for numeric data) - MATLAB R2019a+
            try
                % Read data portion directly as matrix
                rawMatrix = readmatrix(filepath, 'Range', 'A3:ZZ10000');
                % Read headers separately  
                headerTable = readtable(filepath, 'Range', 'A2:ZZ2', 'ReadVariableNames', false);
                headers = table2cell(headerTable);
                data = rawMatrix;
                success = true;
                return;
            catch
                % Fall back to readcell method
            end
        end
        
        % Method 2: readcell fallback
        raw = readcell(filepath, 'NumHeaderLines', 0);
        
        if isempty(raw) || size(raw, 1) < 3
            error('Insufficient data rows');
        end
        
        % Extract headers and data
        headers = raw(2, :);  % Row 2 contains ROI headers
        dataRows = raw(3:end, :);  % Row 3+ contains data
        
        % Convert to numeric
        data = convertToNumeric(dataRows);
        success = true;
        
    catch ME
        error('Failed to read Excel file %s: %s', filepath, ME.message);
    end
end

function numericData = convertToNumeric(dataRows)
    % CONVERTTONUMERIC - Convert cell data to numeric with error handling
    
    [numRows, numCols] = size(dataRows);
    numericData = NaN(numRows, numCols, 'single');
    
    % Process each column individually to avoid array logical operations
    for col = 1:numCols
        colData = dataRows(:, col);
        
        % Process each cell in the column
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
end

function excelFiles = getExcelFiles(folder)
    % GETEXCELFILES - Get valid Excel files with parallel validation
    
    if ~exist(folder, 'dir')
        error('Folder does not exist: %s', folder);
    end
    
    % Get all Excel files
    allFiles = dir(fullfile(folder, '*.xlsx'));
    
    if isempty(allFiles)
        error('No Excel files found in folder: %s', folder);
    end
    
    % Parallel validation if available and beneficial
    cfg = GluSnFRConfig();
    useParallel = cfg.io.VALIDATE_FILES_PARALLEL && ...
                  license('test', 'Distrib_Computing_Toolbox') && ...
                  length(allFiles) > 10;
    
    if useParallel
        validFlags = false(length(allFiles), 1);
        parfor i = 1:length(allFiles)
            filepath = fullfile(allFiles(i).folder, allFiles(i).name);
            validFlags(i) = validateExcelFile(filepath);
        end
        validFiles = allFiles(validFlags);
    else
        validFiles = [];
        for i = 1:length(allFiles)
            filepath = fullfile(allFiles(i).folder, allFiles(i).name);
            if validateExcelFile(filepath)
                validFiles = [validFiles; allFiles(i)];
            end
        end
    end
    
    if isempty(validFiles)
        error('No valid Excel files found in folder: %s', folder);
    end
    
    excelFiles = validFiles;
    fprintf('Found %d valid Excel files\n', length(excelFiles));
end

function isValid = validateExcelFile(filepath)
    % VALIDATEEXCELFILE - Quick validation without conflicting parameters
    
    try
        testData = readcell(filepath, 'Range', 'A1:E5');
        isValid = ~isempty(testData) && size(testData, 1) >= 3;
    catch
        isValid = false;
    end
end

function [validHeaders, validColumns] = extractValidHeaders(headers)
    % EXTRACTVALIDHEADERS - Extract valid headers using existing string_utils
    
    numHeaders = length(headers);
    rawHeaders = {};
    rawColumns = [];
    
    % First pass: collect non-empty headers
    for i = 1:numHeaders
        header = headers{i};
        if ~isempty(header) && (ischar(header) || isstring(header))
            cleanHeader = strtrim(char(header));
            if ~isempty(cleanHeader) && ~contains(lower(cleanHeader), 'filename')
                rawHeaders{end+1} = cleanHeader;
                rawColumns(end+1) = i;
            end
        end
    end
    
    if isempty(rawHeaders)
        validHeaders = {};
        validColumns = [];
        return;
    end
    
    % Use string_utils to extract ROI numbers
    try
        cfg = GluSnFRConfig();
        utils = string_utils(cfg);
        roiNumbers = utils.extractROINumbers(rawHeaders);
        
        % Create clean ROI headers with proper numbering
        if ~isempty(roiNumbers)
            validHeaders = cell(length(roiNumbers), 1);
            validColumns = rawColumns(1:length(roiNumbers));
            
            for i = 1:length(roiNumbers)
                validHeaders{i} = sprintf('ROI %03d', roiNumbers(i));
            end
        else
            % Fallback: use sequential numbering
            validHeaders = cell(length(rawHeaders), 1);
            validColumns = rawColumns;
            
            for i = 1:length(rawHeaders)
                validHeaders{i} = sprintf('ROI %03d', i);
            end
        end
        
    catch
        % Fallback if string_utils fails
        validHeaders = cell(length(rawHeaders), 1);
        validColumns = rawColumns;
        
        for i = 1:length(rawHeaders)
            validHeaders{i} = sprintf('ROI %03d', i);
        end
    end
end

function [data, metadata] = processFileData(rawData, headers, fileInfo, calc, filter, utils, hasGPU, gpuInfo)
    % PROCESSFILEDATA - Process individual file data for parallel use
    
    cfg = calc.config;
    
    % Extract valid data
    [validHeaders, validColumns] = extractValidHeaders(headers);
    if isempty(validHeaders)
        error('No valid ROI headers found');
    end
    
    % Vectorized data extraction
    numericData = single(rawData(:, validColumns));
    timeData_ms = single((0:(size(numericData, 1)-1))' * cfg.timing.MS_PER_FRAME);
    
    % Calculate dF/F
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