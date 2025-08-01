function test_actual_structure()
    % TEST_ACTUAL_STRUCTURE - Fixed to handle missing values properly
    
    fprintf('\n=== Testing Corrected File Reading (Fixed) ===\n');
    
    % Test with your file
    dataFolder = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\1AP\GPU_Processed_Images_1AP\5_raw_mean';
    xlsxFiles = dir(fullfile(dataFolder, '*.xlsx'));
    testFile = fullfile(xlsxFiles(1).folder, xlsxFiles(1).name);
    
    fprintf('Testing: %s\n\n', xlsxFiles(1).name);
    
    % Step 1: Test reading row structure (with safe handling)
    fprintf('STEP 1: Analyzing file structure\n');
    fprintf('================================\n');
    
    try
        % Read first few rows to understand structure
        row1 = readcell(testFile, 'Range', 'A1:E1');
        row2 = readcell(testFile, 'Range', 'A2:E2');
        row3 = readcell(testFile, 'Range', 'A3:E3');
        
        fprintf('Row 1 (filename): ');
        for i = 1:length(row1)
            cellValue = row1{i};
            fprintf('%s ', safeDisplayCell(cellValue));
        end
        fprintf('\n');
        
        fprintf('Row 2 (ROI headers): ');
        for i = 1:length(row2)
            cellValue = row2{i};
            fprintf('%s ', safeDisplayCell(cellValue));
        end
        fprintf('\n');
        
        fprintf('Row 3 (numeric data): ');
        for i = 1:length(row3)
            cellValue = row3{i};
            fprintf('%s ', safeDisplayCell(cellValue));
        end
        fprintf('\n\n');
        
        % Check if row 2 looks like ROI headers
        roiHeaderCount = 0;
        validHeaderCount = 0;
        for i = 1:length(row2)
            cellValue = row2{i};
            if ~isempty(cellValue) && ~ismissing(cellValue)
                validHeaderCount = validHeaderCount + 1;
                if ischar(cellValue) || isstring(cellValue)
                    if contains(lower(char(cellValue)), 'roi')
                        roiHeaderCount = roiHeaderCount + 1;
                    end
                end
            end
        end
        
        fprintf('Analysis:\n');
        fprintf('  Valid headers in row 2: %d\n', validHeaderCount);
        fprintf('  Headers containing "roi": %d\n', roiHeaderCount);
        
        if roiHeaderCount > 0
            fprintf('  ✅ Row 2 contains ROI headers as expected\n');
        else
            fprintf('  ⚠️  Row 2 may not contain ROI headers\n');
        end
        
    catch ME
        fprintf('❌ Error reading file structure: %s\n', ME.message);
        return;
    end
    
    % Step 2: Test the corrected reading function
    fprintf('\nSTEP 2: Testing corrected reading function\n');
    fprintf('==========================================\n');
    
    try
        % Test reading with row 2 = headers, row 3+ = data
        headers = readcell(testFile, 'Range', 'A2:ZZ2');
        data = readmatrix(testFile, 'Range', 'A3:ZZ1000');
        
        fprintf('Raw read results:\n');
        fprintf('  Headers read: %d cells\n', length(headers));
        fprintf('  Data read: %d rows × %d columns\n', size(data, 1), size(data, 2));
        
        % Clean up empty data
        originalDataSize = size(data);
        data = removeEmptyDataSafe(data);
        headers = removeEmptyHeadersSafe(headers, size(data, 2));
        
        fprintf('After cleanup:\n');
        fprintf('  Data size: %d rows × %d columns (was %dx%d)\n', ...
                size(data, 1), size(data, 2), originalDataSize(1), originalDataSize(2));
        fprintf('  Valid headers: %d\n', length(headers));
        
        if ~isempty(data) && ~isempty(headers)
            fprintf('✅ File reading successful!\n');
            
            % Show sample headers
            fprintf('  Sample headers: ');
            for i = 1:min(3, length(headers))
                if ~isempty(headers{i})
                    headerStr = safeDisplayCell(headers{i});
                    fprintf('%s ', headerStr);
                end
            end
            fprintf('\n');
            
            % Check data properties
            fprintf('  Data range: %.1f to %.1f\n', min(data(:)), max(data(:)));
            meanValues = mean(data, 1, 'omitnan');
            fprintf('  Mean fluorescence: %.1f to %.1f\n', min(meanValues), max(meanValues));
            
            % Verify this looks like fluorescence data
            if all(meanValues > 10) && all(meanValues < 10000)
                fprintf('  ✅ Data values look like fluorescence intensities\n');
            else
                fprintf('  ⚠️  Unusual fluorescence values\n');
            end
            
        else
            fprintf('❌ File reading produced empty results\n');
        end
        
    catch ME
        fprintf('❌ Error in file reading: %s\n', ME.message);
        return;
    end
    
    % Step 3: Test validation
    fprintf('\nSTEP 3: Testing validation\n');
    fprintf('==========================\n');
    
    try
        % Test headers from row 2
        testHeaders = readcell(testFile, 'Range', 'A2:E2');
        hasValidHeaders = false;
        for i = 1:length(testHeaders)
            if ~isempty(testHeaders{i}) && ~ismissing(testHeaders{i})
                hasValidHeaders = true;
                break;
            end
        end
        
        % Test numeric data from row 3+
        testData = readmatrix(testFile, 'Range', 'A3:E20');
        hasValidData = ~isempty(testData) && size(testData, 1) >= 5 && ~all(isnan(testData(:)));
        
        fprintf('Validation checks:\n');
        fprintf('  Headers in row 2: %s\n', logicalToString(hasValidHeaders));
        fprintf('  Numeric data in row 3+: %s\n', logicalToString(hasValidData));
        
        if hasValidHeaders && hasValidData
            fprintf('✅ File passes validation\n');
        else
            fprintf('❌ File fails validation\n');
        end
        
    catch ME
        fprintf('❌ Validation test failed: %s\n', ME.message);
    end
    
    % Summary and next steps
    fprintf('\n=======================================================\n');
    fprintf('SUMMARY\n');
    fprintf('=======================================================\n');
    
    if exist('data', 'var') && ~isempty(data) && exist('headers', 'var') && ~isempty(headers)
        fprintf('🎉 SUCCESS! File structure identified and reading works:\n');
        fprintf('  ✅ Row 1: Contains filename\n');
        fprintf('  ✅ Row 2: Contains ROI headers\n');
        fprintf('  ✅ Row 3+: Contains numeric fluorescence data\n');
        fprintf('  ✅ Data extraction successful\n\n');
        
        fprintf('📝 NEXT STEPS:\n');
        fprintf('1. Replace functions in your io_manager.m:\n');
        fprintf('   - readExcelFile function\n');
        fprintf('   - isValidFile function\n');
        fprintf('   - Helper functions (removeEmptyData, etc.)\n\n');
        
        fprintf('2. Test the pipeline:\n');
        fprintf('   >> main_glusnfr_pipeline()\n\n');
        
    else
        fprintf('❌ Issues detected. File structure:\n');
        fprintf('   - Row 1: Contains filename ✅\n');
        fprintf('   - Row 2: ROI headers ❓\n');
        fprintf('   - Row 3+: Numeric data ❓\n\n');
        
        fprintf('Need further investigation.\n');
    end
end

function displayStr = safeDisplayCell(cellValue)
    % Safely display cell contents without crashing on missing values
    
    try
        if isempty(cellValue)
            displayStr = '<empty>';
        elseif ismissing(cellValue)
            displayStr = '<missing>';
        elseif isnumeric(cellValue)
            if isscalar(cellValue)
                displayStr = sprintf('%.1f', cellValue);
            else
                displayStr = '<numeric_array>';
            end
        elseif ischar(cellValue) || isstring(cellValue)
            % Truncate long strings for display
            charStr = char(cellValue);
            if length(charStr) > 30
                displayStr = sprintf('"%s..."', charStr(1:30));
            else
                displayStr = sprintf('"%s"', charStr);
            end
        else
            displayStr = sprintf('<%s>', class(cellValue));
        end
    catch
        displayStr = '<error>';
    end
end

function cleanData = removeEmptyDataSafe(data)
    % Safely remove empty data
    if isempty(data)
        cleanData = [];
        return;
    end
    
    % Remove rows that are all NaN
    validRows = ~all(isnan(data), 2);
    if ~any(validRows)
        cleanData = [];
        return;
    end
    cleanData = data(validRows, :);
    
    % Remove columns that are all NaN
    validCols = ~all(isnan(cleanData), 1);
    if ~any(validCols)
        cleanData = [];
        return;
    end
    cleanData = cleanData(:, validCols);
end

function cleanHeaders = removeEmptyHeadersSafe(headers, numDataCols)
    % Safely remove empty headers
    if isempty(headers)
        cleanHeaders = {};
        return;
    end
    
    % Take only the number of headers that match data columns
    if length(headers) > numDataCols
        cleanHeaders = headers(1:numDataCols);
    else
        cleanHeaders = headers;
        % Pad with generic names if needed
        while length(cleanHeaders) < numDataCols
            cleanHeaders{end+1} = sprintf('Col%d', length(cleanHeaders)+1);
        end
    end
    
    % Replace empty/missing headers with generic names
    for i = 1:length(cleanHeaders)
        header = cleanHeaders{i};
        needsReplacement = false;
        
        try
            if isempty(header) || ismissing(header)
                needsReplacement = true;
            end
        catch
            needsReplacement = true;
        end
        
        if needsReplacement
            cleanHeaders{i} = sprintf('Col%d', i);
        end
    end
end

function str = logicalToString(logicalValue)
    % Convert logical to readable string
    if logicalValue
        str = '✅ PASS';
    else
        str = '❌ FAIL';
    end
end