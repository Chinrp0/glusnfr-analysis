function diagnose_excel_files()
    % DIAGNOSE_EXCEL_FILES - Examine your Excel files to understand their structure
    %
    % This script will help you understand exactly what's in your Excel files
    % and why they might be failing validation.
    
    fprintf('\n');
    fprintf('=======================================================\n');
    fprintf('    Excel File Structure Diagnostic Tool            \n');
    fprintf('=======================================================\n');
    fprintf('This will examine your Excel files in detail...\n\n');
    
    % Get the data folder
    defaultDir = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\';
    
    if exist(defaultDir, 'dir')
        fprintf('Default directory found: %s\n', defaultDir);
        dataFolder = uigetdir(defaultDir, 'Select folder with Excel files');
    else
        fprintf('Please select your data folder\n');
        dataFolder = uigetdir(pwd, 'Select folder with Excel files');
    end
    
    if isequal(dataFolder, 0)
        fprintf('No folder selected, exiting...\n');
        return;
    end
    
    % Find Excel files
    excelFiles = dir(fullfile(dataFolder, '*.xlsx'));
    
    if isempty(excelFiles)
        fprintf('No .xlsx files found in selected folder\n');
        return;
    end
    
    fprintf('\nFound %d Excel files\n', length(excelFiles));
    fprintf('Examining the first few files in detail...\n\n');
    
    % Examine first 3 files in detail
    numToExamine = min(3, length(excelFiles));
    
    for i = 1:numToExamine
        filepath = fullfile(excelFiles(i).folder, excelFiles(i).name);
        fprintf('==================================================\n');
        fprintf('FILE %d: %s\n', i, excelFiles(i).name);
        fprintf('==================================================\n');
        
        examineExcelFile(filepath);
        fprintf('\n');
    end
    
    % Summary and recommendations
    fprintf('=======================================================\n');
    fprintf('SUMMARY AND RECOMMENDATIONS\n');
    fprintf('=======================================================\n');
    
    fprintf('Based on the file examination above:\n\n');
    
    fprintf('1. If files look correct:\n');
    fprintf('   - Try running: quick_start()\n');
    fprintf('   - The fixed validation should work\n\n');
    
    fprintf('2. If files have unexpected structure:\n');
    fprintf('   - Check if row 2 contains ROI identifiers\n');
    fprintf('   - Make sure numeric data starts in row 3\n');
    fprintf('   - Verify files aren''t corrupted\n\n');
    
    fprintf('3. If you still have issues:\n');
    fprintf('   - Use the working monolithic script: s6_SnFR_mean_dF_filter_group_plot_v50\n');
    fprintf('   - Or share one sample file for further debugging\n\n');
end

function examineExcelFile(filepath)
    % Examine a single Excel file in detail
    
    try
        fprintf('Reading file...\n');
        
        % Try to read the first 10 rows and 10 columns
        try
            raw = readcell(filepath, 'Range', 'A1:J10', 'NumHeaderLines', 0);
            fprintf('✓ File readable with readcell\n');
        catch
            fprintf('! readcell failed, trying xlsread...\n');
            [~, ~, raw] = xlsread(filepath, 1, 'A1:J10'); %#ok<XLSRD>
            fprintf('✓ File readable with xlsread\n');
        end
        
        % Basic info
        fprintf('File dimensions (first 10x10): %d rows × %d columns\n', size(raw, 1), size(raw, 2));
        
        % Examine each row
        for row = 1:min(5, size(raw, 1))
            fprintf('\nRow %d contents:\n', row);
            
            for col = 1:min(5, size(raw, 2))
                cellValue = raw{row, col};
                
                if isempty(cellValue)
                    fprintf('  [%d,%d]: <empty>\n', row, col);
                elseif isnumeric(cellValue)
                    fprintf('  [%d,%d]: %.3f (numeric)\n', row, col, cellValue);
                elseif ischar(cellValue) || isstring(cellValue)
                    fprintf('  [%d,%d]: "%s" (text)\n', row, col, char(cellValue));
                else
                    fprintf('  [%d,%d]: <%s> (other)\n', row, col, class(cellValue));
                end
            end
        end
        
        % Special focus on row 2 (should be ROI headers)
        if size(raw, 1) >= 2
            fprintf('\n=== ROW 2 ANALYSIS (Expected ROI Headers) ===\n');
            row2 = raw(2, :);
            roiCount = 0;
            
            for col = 1:min(size(raw, 2), 10)
                if col <= length(row2) && ~isempty(row2{col})
                    cellValue = row2{col};
                    if ischar(cellValue) || isstring(cellValue)
                        cellStr = char(cellValue);
                        fprintf('  Col %d: "%s"', col, cellStr);
                        
                        % Check for ROI patterns
                        if contains(lower(cellStr), 'roi')
                            roiCount = roiCount + 1;
                            fprintf(' <- ROI detected!');
                        elseif contains(cellStr, {'001', '002', '003'}) % Common ROI numbering
                            roiCount = roiCount + 1;
                            fprintf(' <- ROI number detected!');
                        end
                        fprintf('\n');
                    else
                        fprintf('  Col %d: %s (not text)\n', col, class(cellValue));
                    end
                else
                    fprintf('  Col %d: <empty>\n', col);
                end
            end
            
            fprintf('Total ROI-like headers found in row 2: %d\n', roiCount);
            
            if roiCount == 0
                fprintf('! WARNING: No ROI identifiers found in row 2\n');
                fprintf('  This might cause validation to fail\n');
            else
                fprintf('✓ ROI structure looks good\n');
            end
        end
        
        % Check for numeric data in row 3+
        if size(raw, 1) >= 3
            fprintf('\n=== NUMERIC DATA CHECK (Row 3+) ===\n');
            numericCols = 0;
            
            for col = 1:min(5, size(raw, 2))
                if size(raw, 1) >= 3 && col <= size(raw, 2)
                    testValues = [];
                    for row = 3:min(6, size(raw, 1))
                        if row <= size(raw, 1) && col <= size(raw, 2)
                            val = raw{row, col};
                            if isnumeric(val) && isfinite(val)
                                testValues(end+1) = val;
                            end
                        end
                    end
                    
                    if length(testValues) >= 2
                        numericCols = numericCols + 1;
                        fprintf('  Col %d: %.1f, %.1f, ... (numeric data ✓)\n', col, testValues(1), testValues(2));
                    else
                        fprintf('  Col %d: No numeric data found\n', col);
                    end
                end
            end
            
            if numericCols > 0
                fprintf('✓ Found numeric data in %d columns\n', numericCols);
            else
                fprintf('! WARNING: No numeric data found starting from row 3\n');
            end
        end
        
        % Overall assessment
        fprintf('\n=== OVERALL ASSESSMENT ===\n');
        
        if size(raw, 1) >= 3 && size(raw, 2) >= 2
            fprintf('✓ File has sufficient rows and columns\n');
        else
            fprintf('✗ File too small (need at least 3 rows, 2 columns)\n');
        end
        
        % Read the entire file to check real size
        try
            fullData = readcell(filepath, 'NumHeaderLines', 0);
            fprintf('✓ Full file size: %d rows × %d columns\n', size(fullData, 1), size(fullData, 2));
            
            % Check if this looks like time series data
            if size(fullData, 1) > 100
                fprintf('✓ Looks like time series data (%d time points)\n', size(fullData, 1));
            end
            
        catch
            fprintf('! Could not read full file\n');
        end
        
    catch ME
        fprintf('✗ ERROR reading file: %s\n', ME.message);
        fprintf('File may be corrupted or in wrong format\n');
    end
end