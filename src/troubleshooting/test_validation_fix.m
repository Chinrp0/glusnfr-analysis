function test_validation_fix()
    % TEST_VALIDATION_FIX - Test the fixed validation function
    
    fprintf('\n=== Testing Validation Fix ===\n');
    
    % Add path
    addpath(genpath(pwd));
    
    % Load fixed io manager
    io = io_manager();
    
    % Test folder
    testFolder = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\1AP\GPU_Processed_Images_1AP\5_raw_mean';
    
    if ~exist(testFolder, 'dir')
        fprintf('Test folder not found, please select folder with Excel files\n');
        testFolder = uigetdir(pwd, 'Select folder with Excel files');
        if isequal(testFolder, 0)
            return;
        end
    end
    
    % Get Excel files
    excelFiles = dir(fullfile(testFolder, '*.xlsx'));
    fprintf('Found %d Excel files\n', length(excelFiles));
    
    % Test validation on each file
    validCount = 0;
    
    for i = 1:min(5, length(excelFiles))  % Test first 5 files
        filepath = fullfile(excelFiles(i).folder, excelFiles(i).name);
        fprintf('Testing %s... ', excelFiles(i).name);
        
        try
            isValid = io.validateFile(filepath);
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
    
    fprintf('\nValidation Results:\n');
    fprintf('  Files tested: %d\n', min(5, length(excelFiles)));
    fprintf('  Valid files: %d\n', validCount);
    
    if validCount > 0
        fprintf('✓ Validation fix successful!\n');
        
        % Test getExcelFiles function
        fprintf('\nTesting getExcelFiles function...\n');
        try
            validFiles = io.getExcelFiles(testFolder);
            fprintf('✓ getExcelFiles found %d valid files\n', length(validFiles));
        catch ME
            fprintf('❌ getExcelFiles failed: %s\n', ME.message);
        end
        
    else
        fprintf('❌ Still no valid files found\n');
    end
end