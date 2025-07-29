function io = io_manager()
    % IO_MANAGER - File input/output operations module
    % 
    % This module handles all file I/O operations including:
    % - Excel file reading with multiple fallback methods
    % - Excel file writing with custom headers
    % - Directory management
    % - File validation
    
    io.readExcelFile = @readExcelFileRobust;
    io.writeExcelWithHeaders = @writeExcelWithCustomHeaders;
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
        if useReadMatrix && verLessThan('matlab', '9.6') == false % R2019a+
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

function writeExcelWithCustomHeaders(data, filepath, sheetName, row1Headers, row2Headers)
    % Write Excel file with custom two-row headers
    
    if nargin < 5
        row2Headers = row1Headers;
        row1Headers = {};
    end
    
    try
        % Get variable names if data is a table
        if istable(data)
            if isempty(row1Headers)
                row1Headers = cell(1, width(data));
                row2Headers = data.Properties.VariableNames;
            end
            dataMatrix = table2array(data);
        else
            dataMatrix = data;
        end
        
        [numRows, numCols] = size(dataMatrix);
        
        % Create cell array for writing
        if ~isempty(row1Headers) && length(row1Headers) == numCols
            cellData = cell(numRows + 2, numCols);
            cellData(1, :) = row1Headers;
            cellData(2, :) = row2Headers;
            
            % Add data
            for i = 1:numRows
                for j = 1:numCols
                    cellData{i+2, j} = dataMatrix(i, j);
                end
            end
            
            % Write to Excel
            writecell(cellData, filepath, 'Sheet', sheetName);
            
        else
            % Fallback to standard table writing
            if istable(data)
                writetable(data, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
            else
                writematrix(dataMatrix, filepath, 'Sheet', sheetName);
            end
        end
        
        fprintf('    Written sheet "%s" to %s\n', sheetName, filepath);
        
    catch ME
        warning('Failed to write Excel file %s: %s', filepath, ME.message);
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

function excelFiles = getExcelFilesValidated(folder)
    % Get and validate Excel files in folder
    
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
    
    % Validate each file (optional - can be slow for many files)
    validFiles = [];
    for i = 1:length(allFiles)
        filepath = fullfile(allFiles(i).folder, allFiles(i).name);
        if validateExcelFile(filepath)
            validFiles = [validFiles; allFiles(i)];
        else
            fprintf('    Skipping invalid file: %s\n', allFiles(i).name);
        end
    end
    
    excelFiles = validFiles;
    fprintf('Found %d valid Excel files (out of %d total)\n', ...
            length(excelFiles), length(allFiles));
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
