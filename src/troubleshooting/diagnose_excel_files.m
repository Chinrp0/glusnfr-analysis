function diagnose_excel_files()
    % DIAGNOSE_EXCEL_FILES - Examine your Excel files to understand validation issues
    
    fprintf('\n=======================================================\n');
    fprintf('    Excel File Diagnostic Tool                        \n');
    fprintf('=======================================================\n');
    
    % Use the same default directory as your pipeline
    defaultDir = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\1AP\GPU_Processed_Images_1AP\5_raw_mean';
    
    if exist(defaultDir, 'dir')
        fprintf('Checking default folder: %s\n\n', defaultDir);
        dataFolder = defaultDir;
    else
        fprintf('Default folder not found. Please select your folder.\n');
        dataFolder = uigetdir(pwd, 'Select folder with Excel files');
        if isequal(dataFolder, 0)
            fprintf('No folder selected, exiting...\n');
            return;
        end
    end
    
    % Step 1: Check what files exist
    fprintf('STEP 1: Checking what files exist in folder\n');
    fprintf('==========================================\n');
    
    allFiles = dir(fullfile(dataFolder, '*.*'));
    xlsxFiles = dir(fullfile(dataFolder, '*.xlsx'));
    xlsFiles = dir(fullfile(dataFolder, '*.xls'));
    
    fprintf('Total files: %d\n', length(allFiles) - 2); % Subtract . and ..
    fprintf('.xlsx files: %d\n', length(xlsxFiles));
    fprintf('.xls files: %d\n', length(xlsFiles));
    
    if isempty(xlsxFiles) && isempty(xlsFiles)
        fprintf('\n❌ PROBLEM FOUND: No Excel files (.xlsx or .xls) in folder!\n');
        fprintf('\nFiles in folder:\n');
        for i = 1:min(10, length(allFiles))
            if ~allFiles(i).isdir
                fprintf('  %s\n', allFiles(i).name);
            end
        end
        if length(allFiles) > 10
            fprintf('  ... and %d more files\n', length(allFiles) - 10);
        end
        return;
    end
    
    % Step 2: Test validation on each Excel file
    fprintf('\nSTEP 2: Testing validation on each Excel file\n');
    fprintf('==============================================\n');
    
    allExcelFiles = [xlsxFiles; xlsFiles];
    validCount = 0;
    
    for i = 1:length(allExcelFiles)
        filepath = fullfile(allExcelFiles(i).folder, allExcelFiles(i).name);
        fprintf('\nFile %d: %s\n', i, allExcelFiles(i).name);
        
        % Test the current validation function
        [isValid, reason] = testFileValidation(filepath);
        
        if isValid
            fprintf('  ✅ VALID - passes validation\n');
            validCount = validCount + 1;
        else
            fprintf('  ❌ INVALID - %s\n', reason);
        end
        
        % Show file details
        showFileDetails(filepath);
    end
    
    % Step 3: Summary and recommendations
    fprintf('\n=======================================================\n');
    fprintf('SUMMARY\n');
    fprintf('=======================================================\n');
    fprintf('Total Excel files found: %d\n', length(allExcelFiles));
    fprintf('Files passing validation: %d\n', validCount);
    fprintf('Files failing validation: %d\n', length(allExcelFiles) - validCount);
    
    if validCount == 0
        fprintf('\n🔧 RECOMMENDATIONS:\n');
        fprintf('1. Check if your files have the expected structure:\n');
        fprintf('   - Row 1: Optional (headers)\n');
        fprintf('   - Row 2: ROI names (ROI 001, ROI 002, etc.)\n');
        fprintf('   - Row 3+: Numeric fluorescence data\n\n');
        
        fprintf('2. Try the more lenient validation:\n');
        fprintf('   Run: use_lenient_validation()\n\n');
        
        fprintf('3. If files are corrupted, try re-exporting from ImageJ\n\n');
    else
        fprintf('\n✅ %d files are valid and should work with the pipeline\n', validCount);
    end
end

function [isValid, reason] = testFileValidation(filepath)
    % Test file validation and return reason for failure
    
    isValid = false;
    reason = 'Unknown error';
    
    try
        % Test 1: Can we read the file at all?
        try
            testData = readmatrix(filepath, 'Range', 'A1:E5', 'NumHeaderLines', 0);
        catch ME
            reason = sprintf('Cannot read file: %s', ME.message);
            return;
        end
        
        % Test 2: Does it have data?
        if isempty(testData)
            reason = 'File is empty';
            return;
        end
        
        % Test 3: Does it have enough rows?
        if size(testData, 1) < 3
            reason = sprintf('Only %d rows, need at least 3', size(testData, 1));
            return;
        end
        
        % Test 4: Can we read headers from row 2?
        try
            headers = readcell(filepath, 'Range', 'A2:Z2', 'NumHeaderLines', 0);
            if isempty(headers)
                reason = 'No headers found in row 2';
                return;
            end
        catch ME
            reason = sprintf('Cannot read headers: %s', ME.message);
            return;
        end
        
        % Test 5: Can we read full data from row 3+?
        try
            fullData = readmatrix(filepath, 'Range', 'A3:Z1000', 'NumHeaderLines', 0);
            if isempty(fullData)
                reason = 'No numeric data found from row 3 onwards';
                return;
            end
            if size(fullData, 1) < 10
                reason = sprintf('Only %d data rows, expected more', size(fullData, 1));
                return;
            end
        catch ME
            reason = sprintf('Cannot read numeric data: %s', ME.message);
            return;
        end
        
        % If we get here, file is valid
        isValid = true;
        reason = 'File passes all validation tests';
        
    catch ME
        reason = sprintf('Validation error: %s', ME.message);
    end
end

function showFileDetails(filepath)
    % Show basic file details
    
    try
        fileInfo = dir(filepath);
        fprintf('    Size: %.1f KB\n', fileInfo.bytes / 1024);
        
        % Try to get sheet names
        try
            [~, sheets] = xlsfinfo(filepath);
            if ~isempty(sheets)
                fprintf('    Sheets: %s\n', strjoin(sheets, ', '));
            end
        catch
            fprintf('    Sheets: Cannot determine\n');
        end
        
        % Try to get dimensions
        try
            testRead = readcell(filepath, 'Range', 'A1:Z100', 'NumHeaderLines', 0);
            if ~isempty(testRead)
                fprintf('    Dimensions: %d rows x %d cols (first 100 rows)\n', ...
                        size(testRead, 1), size(testRead, 2));
            end
        catch
            fprintf('    Dimensions: Cannot determine\n');
        end
        
    catch
        fprintf('    Details: Cannot access file\n');
    end
end

function use_lenient_validation()
    % Create a more lenient validation function
    
    fprintf('\n=======================================================\n');
    fprintf('    Creating Lenient Validation Function             \n');
    fprintf('=======================================================\n');
    
    % This creates a temporary fix in your io_manager
    fprintf('This will modify your io_manager.m to use more lenient validation.\n');
    fprintf('Do you want to proceed? (y/n): ');
    
    response = input('', 's');
    if ~strcmpi(response, 'y')
        fprintf('Operation cancelled.\n');
        return;
    end
    
    % Create the lenient validation replacement
    fprintf('\nCreating lenient validation...\n');
    
    % Instructions for manual replacement
    fprintf('\n📋 MANUAL REPLACEMENT INSTRUCTIONS:\n');
    fprintf('Replace the isValidFile function in your io_manager.m with:\n\n');
    
    fprintf('function isValid = isValidFile(filepath)\n');
    fprintf('    %% LENIENT validation - accept any readable Excel file\n');
    fprintf('    try\n');
    fprintf('        %% Just check if we can read something from the file\n');
    fprintf('        testData = readcell(filepath, ''Range'', ''A1:E10'', ''NumHeaderLines'', 0);\n');
    fprintf('        isValid = ~isempty(testData) && size(testData, 1) >= 2;\n');
    fprintf('    catch\n');
    fprintf('        isValid = false;\n');
    fprintf('    end\n');
    fprintf('end\n\n');
    
    fprintf('After making this change, try running your pipeline again.\n');
end