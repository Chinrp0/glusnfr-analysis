function test_fixed_io()
    % TEST_FIXED_IO - Test the fixed io_manager functions
    
    fprintf('\n=== Testing Fixed IO Manager ===\n');
    
    % Add path
    addpath(genpath(pwd));
    
    try
        % Load the fixed io manager
        io = io_manager();
        fprintf('✓ Fixed io_manager loaded\n');
        
        % Test file selection
        fprintf('\nSelect an Excel file to test...\n');
        [filename, pathname] = uigetfile('*.xlsx', 'Select Excel file for testing');
        
        if isequal(filename, 0)
            fprintf('No file selected, exiting...\n');
            return;
        end
        
        filepath = fullfile(pathname, filename);
        fprintf('Testing file: %s\n', filename);
        
        % Test file reading
        fprintf('\nTesting file reading...\n');
        [data, headers, success] = io.readExcelFile(filepath, true);
        
        if success
            fprintf('✓ File read successfully\n');
            fprintf('  Data size: %d rows × %d columns\n', size(data));
            fprintf('  Headers found: %d\n', length(headers));
            
            % Show first few original headers
            fprintf('\nOriginal headers (first 3):\n');
            for i = 1:min(3, length(headers))
                if ~isempty(headers{i})
                    fprintf('  %d. %s\n', i, char(headers{i}));
                end
            end
            
            % Test header extraction
            fprintf('\nTesting header extraction...\n');
            [validHeaders, validColumns] = io.extractValidHeaders(headers);
            
            if ~isempty(validHeaders)
                fprintf('✓ Header extraction successful\n');
                fprintf('  Valid headers: %d\n', length(validHeaders));
                fprintf('  First 10 extracted headers:\n');
                for i = 1:min(10, length(validHeaders))
                    fprintf('    %d. %s\n', i, validHeaders{i});
                end
                
                % Check for duplicate ROI numbers
                roiNumbers = zeros(length(validHeaders), 1);
                for i = 1:length(validHeaders)
                    roiMatch = regexp(validHeaders{i}, 'ROI (\d+)', 'tokens');
                    if ~isempty(roiMatch)
                        roiNumbers(i) = str2double(roiMatch{1}{1});
                    end
                end
                
                uniqueROIs = unique(roiNumbers);
                if length(uniqueROIs) == length(roiNumbers)
                    fprintf('✓ All ROI numbers are unique\n');
                else
                    fprintf('⚠ Found %d duplicate ROI numbers\n', length(roiNumbers) - length(uniqueROIs));
                end
                
            else
                fprintf('✗ No valid headers extracted\n');
            end
            
            % Test numeric data validation
            fprintf('\nTesting numeric data...\n');
            if ~isempty(data)
                numericColumns = validColumns;
                if ~isempty(numericColumns)
                    testData = data(:, numericColumns);
                    numFinite = sum(isfinite(testData(:)));
                    totalCells = numel(testData);
                    finitePercentage = (numFinite / totalCells) * 100;
                    
                    fprintf('  Numeric data extracted: %d×%d\n', size(testData));
                    fprintf('  Finite values: %.1f%% (%d/%d)\n', finitePercentage, numFinite, totalCells);
                    
                    if finitePercentage > 50
                        fprintf('✓ Numeric data looks good\n');
                    else
                        fprintf('⚠ Low percentage of finite values\n');
                    end
                else
                    fprintf('✗ No valid numeric columns found\n');
                end
            else
                fprintf('✗ No data extracted\n');
            end
            
        else
            fprintf('✗ File reading failed\n');
        end
        
        fprintf('\n=== Test Complete ===\n');
        
    catch ME
        fprintf('\n✗ Test failed with error: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('  Location: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
        end
    end
end