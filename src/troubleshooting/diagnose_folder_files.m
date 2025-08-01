function diagnose_folder_files()
    % DIAGNOSE_FOLDER_FILES - Debug why getExcelFiles is failing
    
    fprintf('\n=== Folder Files Diagnostic ===\n');
    
    % Add path
    addpath(genpath(pwd));
    
    % Get the folder that's failing
    defaultFolder = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\1AP\GPU_Processed_Images_1AP\5_raw_mean';
    
    fprintf('Checking folder: %s\n', defaultFolder);
    
    % Check if folder exists
    if ~exist(defaultFolder, 'dir')
        fprintf('❌ Folder does not exist!\n');
        
        % Try to find the correct folder
        fprintf('\nLet''s find the correct folder...\n');
        folder = uigetdir(pwd, 'Select the folder with Excel files');
        if isequal(folder, 0)
            fprintf('No folder selected, exiting...\n');
            return;
        end
        defaultFolder = folder;
    else
        fprintf('✓ Folder exists\n');
    end
    
    % List all files in the folder
    fprintf('\nListing all files in folder...\n');
    allFiles = dir(defaultFolder);
    fileCount = 0;
    excelCount = 0;
    
    for i = 1:length(allFiles)
        if ~allFiles(i).isdir
            fileCount = fileCount + 1;
            fprintf('  %d. %s (%.1f KB)\n', fileCount, allFiles(i).name, allFiles(i).bytes/1024);
            
            if endsWith(allFiles(i).name, '.xlsx')
                excelCount = excelCount + 1;
            end
        end
    end
    
    fprintf('Total files: %d, Excel files: %d\n', fileCount, excelCount);
    
    if excelCount == 0
        fprintf('❌ No Excel files found in this folder!\n');
        
        % Check for other Excel formats
        xlsFiles = dir(fullfile(defaultFolder, '*.xls'));
        csvFiles = dir(fullfile(defaultFolder, '*.csv'));
        
        if ~isempty(xlsFiles)
            fprintf('Found %d .xls files (old format)\n', length(xlsFiles));
        end
        if ~isempty(csvFiles)
            fprintf('Found %d .csv files\n', length(csvFiles));
        end
        
        return;
    end
    
    % Test each Excel file with validation
    fprintf('\nTesting Excel file validation...\n');
    excelFiles = dir(fullfile(defaultFolder, '*.xlsx'));
    validCount = 0;
    
    for i = 1:length(excelFiles)
        filepath = fullfile(excelFiles(i).folder, excelFiles(i).name);
        fprintf('  Testing %s... ', excelFiles(i).name);
        
        try
            % Test with our validation function
            isValid = testFileValidation(filepath);
            
            if isValid
                fprintf('✓ VALID\n');
                validCount = validCount + 1;
            else
                fprintf('❌ INVALID\n');
            end
            
        catch ME
            fprintf('❌ ERROR: %s\n', ME.message);
        end
    end
    
    fprintf('\nValidation Summary:\n');
    fprintf('  Total Excel files: %d\n', length(excelFiles));
    fprintf('  Valid files: %d\n', validCount);
    fprintf('  Invalid files: %d\n', length(excelFiles) - validCount);
    
    if validCount == 0
        fprintf('\n❌ NO VALID FILES FOUND!\n');
        fprintf('This explains why the pipeline is failing.\n\n');
        
        % Test one file in detail
        if ~isempty(excelFiles)
            fprintf('Testing first file in detail...\n');
            testFilepath = fullfile(excelFiles(1).folder, excelFiles(1).name);
            testFileInDetail(testFilepath);
        end
    else
        fprintf('\n✓ Found %d valid files - pipeline should work\n', validCount);
    end
end

function isValid = testFileValidation(filepath)
    % Test the exact validation logic from io_manager
    
    try
        % Quick test read of first few cells
        testData = readcell(filepath, 'Range', 'A1:E5', 'NumHeaderLines', 0);
        isValid = ~isempty(testData) && size(testData, 1) >= 3;
    catch
        isValid = false;
    end
end

function testFileInDetail(filepath)
    % Test file in detail to see what's wrong
    
    fprintf('Detailed analysis of: %s\n', filepath);
    
    try
        % Try to read the file
        fprintf('  Attempting to read file...\n');
        testData = readcell(filepath, 'Range', 'A1:E5', 'NumHeaderLines', 0);
        
        if isempty(testData)
            fprintf('  ❌ File is empty or unreadable\n');
            return;
        end
        
        fprintf('  ✓ File readable, size: %d×%d\n', size(testData));
        
        if size(testData, 1) < 3
            fprintf('  ❌ File has only %d rows (need at least 3)\n', size(testData, 1));
            return;
        end
        
        fprintf('  ✓ File has %d rows (≥3 required)\n', size(testData, 1));
        
        % Check each row
        for row = 1:min(3, size(testData, 1))
            fprintf('  Row %d: ', row);
            hasData = false;
            for col = 1:min(3, size(testData, 2))
                if ~isempty(testData{row, col})
                    hasData = true;
                    break;
                end
            end
            if hasData
                fprintf('Has data\n');
            else
                fprintf('Empty\n');
            end
        end
        
        fprintf('  ✓ File structure looks valid\n');
        
    catch ME
        fprintf('  ❌ Error reading file: %s\n', ME.message);
        
        % Try different read methods
        fprintf('  Trying alternative read methods...\n');
        
        try
            [~, ~, raw] = xlsread(filepath, 1, 'A1:E5');
            fprintf('  ✓ xlsread worked, size: %d×%d\n', size(raw));
        catch
            fprintf('  ❌ xlsread also failed\n');
        end
        
        try
            data = readmatrix(filepath, 'Range', 'A1:E5');
            fprintf('  ✓ readmatrix worked, size: %d×%d\n', size(data));
        catch
            fprintf('  ❌ readmatrix also failed\n');
        end
    end
end