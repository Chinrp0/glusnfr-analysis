function reader = excel_reader()
    % EXCEL_READER - Fixed Excel file reading operations
    
    reader.readFile = @readExcelFile;
    reader.getFiles = @getExcelFiles;
    reader.validateFile = @validateExcelFile;
    reader.extractHeaders = @extractValidHeaders;
end

function [data, headers, success] = readExcelFile(filepath, useOptimized)
    % FIXED: Dynamic range reading instead of fixed ranges
    
    success = false;
    data = [];
    headers = {};
    
    if ~exist(filepath, 'file')
        warning('File does not exist: %s', filepath);
        return;
    end
    
    try
        % Read entire file first to determine actual size
        raw = readcell(filepath, 'NumHeaderLines', 0);
        
        if isempty(raw) || size(raw, 1) < 3
            error('Insufficient data rows');
        end
        
        % Extract headers from row 2 and data from row 3+
        headers = raw(2, :);
        dataRows = raw(3:end, :);
        
        % Vectorized numeric conversion (much faster than cell-by-cell)
        data = convertToNumericVectorized(dataRows);
        success = true;
        
    catch ME
        error('Failed to read Excel file %s: %s', filepath, ME.message);
    end
end

function numericData = convertToNumericVectorized(dataRows)
    
    [numRows, numCols] = size(dataRows);
    numericData = NaN(numRows, numCols, 'single');
    
    % Process columns vectorized where possible
    for col = 1:numCols
        colData = dataRows(:, col);
        
        % Check if column is already numeric
        numericMask = cellfun(@(x) isnumeric(x) && isscalar(x) && isfinite(x), colData);
        
        if any(numericMask)
            numericValues = cell2mat(colData(numericMask));
            numericData(numericMask, col) = single(numericValues);
        end
        
        % Handle text that might be numbers
        textMask = cellfun(@(x) ischar(x) || isstring(x), colData);
        if any(textMask)
            textData = colData(textMask);
            numericValues = str2double(textData);
            validNums = isfinite(numericValues);
            
            textIndices = find(textMask);
            validTextIndices = textIndices(validNums);
            numericData(validTextIndices, col) = single(numericValues(validNums));
        end
    end
end

function excelFiles = getExcelFiles(folder)
    % Unchanged - this function is working correctly
    
    if ~exist(folder, 'dir')
        error('Folder does not exist: %s', folder);
    end
    
    allFiles = dir(fullfile(folder, '*.xlsx'));
    
    if isempty(allFiles)
        error('No Excel files found in folder: %s', folder);
    end
    
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
    % Unchanged - this function is working correctly
    
    try
        testData = readcell(filepath, 'Range', 'A1:E5');
        isValid = ~isempty(testData) && size(testData, 1) >= 3;
    catch
        isValid = false;
    end
end

function [validHeaders, validColumns] = extractValidHeaders(headers)
    % Unchanged - this function is working correctly
    
    numHeaders = length(headers);
    rawHeaders = {};
    rawColumns = [];
    
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
    
    try
        cfg = GluSnFRConfig();
        utils = string_utils(cfg);
        roiNumbers = utils.extractROINumbers(rawHeaders);
        
        if ~isempty(roiNumbers)
            validHeaders = cell(length(roiNumbers), 1);
            validColumns = rawColumns(1:length(roiNumbers));
            
            for i = 1:length(roiNumbers)
                validHeaders{i} = sprintf('ROI %03d', roiNumbers(i));
            end
        else
            validHeaders = cell(length(rawHeaders), 1);
            validColumns = rawColumns;
            
            for i = 1:length(rawHeaders)
                validHeaders{i} = sprintf('ROI %03d', i);
            end
        end
        
    catch
        validHeaders = cell(length(rawHeaders), 1);
        validColumns = rawColumns;
        
        for i = 1:length(rawHeaders)
            validHeaders{i} = sprintf('ROI %03d', i);
        end
    end
end