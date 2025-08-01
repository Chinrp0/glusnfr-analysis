function diagnose_processing()
    % DIAGNOSE_PROCESSING - Find exactly where file processing is failing
    
    fprintf('\n=======================================================\n');
    fprintf('    File Processing Diagnostic Tool                   \n');
    fprintf('=======================================================\n');
    
    % Test with one of your files
    dataFolder = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\1AP\GPU_Processed_Images_1AP\5_raw_mean';
    xlsxFiles = dir(fullfile(dataFolder, '*.xlsx'));
    
    if isempty(xlsxFiles)
        fprintf('❌ No files found\n');
        return;
    end
    
    % Test with first file
    testFile = fullfile(xlsxFiles(1).folder, xlsxFiles(1).name);
    fprintf('Testing file: %s\n\n', xlsxFiles(1).name);
    
    try
        % Load modules
        addpath(genpath(pwd));
        modules = module_loader();
        
        % Step 1: Test file reading
        fprintf('STEP 1: Testing file reading\n');
        fprintf('============================\n');
        [rawData, headers, readSuccess] = modules.io.readExcelFile(testFile, true);
        
        if ~readSuccess || isempty(rawData)
            fprintf('❌ File reading failed\n');
            return;
        end
        
        fprintf('✅ File read successfully\n');
        fprintf('   Raw data size: %d rows × %d columns\n', size(rawData, 1), size(rawData, 2));
        fprintf('   Headers found: %d\n', length(headers));
        
        % Show sample headers
        fprintf('   Sample headers: ');
        for i = 1:min(5, length(headers))
            if ~isempty(headers{i})
                fprintf('"%s" ', char(headers{i}));
            end
        end
        fprintf('\n');
        
        % Show data properties
        fprintf('   Data range: %.3f to %.3f\n', min(rawData(:)), max(rawData(:)));
        fprintf('   NaN percentage: %.1f%%\n', sum(isnan(rawData(:)))/numel(rawData)*100);
        
        % Step 2: Test header extraction
        fprintf('\nSTEP 2: Testing header extraction\n');
        fprintf('==================================\n');
        [validHeaders, validColumns] = modules.io.extractValidHeaders(headers);
        
        if isempty(validHeaders)
            fprintf('❌ No valid headers found\n');
            fprintf('   This is likely the problem!\n');
            
            % Diagnose header issues
            fprintf('\nDiagnosing header issues:\n');
            for i = 1:min(10, length(headers))
                header = headers{i};
                if isempty(header)
                    fprintf('   Header %d: <empty>\n', i);
                elseif ismissing(header)
                    fprintf('   Header %d: <missing>\n', i);
                else
                    fprintf('   Header %d: "%s" (class: %s)\n', i, char(header), class(header));
                end
            end
            return;
        end
        
        fprintf('✅ Headers extracted successfully\n');
        fprintf('   Valid headers: %d out of %d\n', length(validHeaders), length(headers));
        fprintf('   Sample valid headers: ');
        for i = 1:min(3, length(validHeaders))
            fprintf('"%s" ', validHeaders{i});
        end
        fprintf('\n');
        
        % Step 3: Test numeric data extraction
        fprintf('\nSTEP 3: Testing numeric data extraction\n');
        fprintf('========================================\n');
        numericData = single(rawData(:, validColumns));
        
        if isempty(numericData)
            fprintf('❌ No numeric data extracted\n');
            return;
        end
        
        fprintf('✅ Numeric data extracted\n');
        fprintf('   Numeric data size: %d rows × %d columns\n', size(numericData, 1), size(numericData, 2));
        fprintf('   Data range: %.3f to %.3f\n', min(numericData(:)), max(numericData(:)));
        
        % Check for typical fluorescence data properties
        meanValues = mean(numericData, 1, 'omitnan');
        fprintf('   Mean values per ROI: %.1f to %.1f\n', min(meanValues), max(meanValues));
        
        if any(meanValues < 10) || any(meanValues > 10000)
            fprintf('   ⚠️  Unusual fluorescence values detected\n');
        end
        
        % Step 4: Test dF/F calculation
        fprintf('\nSTEP 4: Testing dF/F calculation\n');
        fprintf('=================================\n');
        
        cfg = modules.config;
        timeData_ms = single((0:(size(numericData, 1)-1))' * cfg.timing.MS_PER_FRAME);
        
        fprintf('   Time data: 0 to %.1f ms (%d frames)\n', max(timeData_ms), length(timeData_ms));
        fprintf('   Expected stimulus at: %.1f ms (frame %d)\n', cfg.timing.STIMULUS_TIME_MS, cfg.timing.STIMULUS_FRAME);
        
        try
            hasGPU = gpuDeviceCount > 0;
            gpuInfo = struct('memory', 4);
            [dF_values, thresholds, gpuUsed] = modules.calc.calculate(numericData, hasGPU, gpuInfo);
            
            fprintf('✅ dF/F calculation successful (GPU: %s)\n', string(gpuUsed));
            fprintf('   dF/F size: %d rows × %d columns\n', size(dF_values, 1), size(dF_values, 2));
            fprintf('   dF/F range: %.4f to %.4f\n', min(dF_values(:)), max(dF_values(:)));
            fprintf('   Thresholds: %.4f to %.4f\n', min(thresholds), max(thresholds));
            
        catch ME
            fprintf('❌ dF/F calculation failed: %s\n', ME.message);
            return;
        end
        
        % Step 5: Test filename parsing
        fprintf('\nSTEP 5: Testing filename parsing\n');
        fprintf('=================================\n');
        [trialNum, expType, ppiValue, coverslipCell] = modules.utils.extractTrialOrPPI(xlsxFiles(1).name);
        
        fprintf('   Trial number: %s\n', string(trialNum));
        fprintf('   Experiment type: %s\n', expType);
        fprintf('   PPI value: %s\n', string(ppiValue));
        fprintf('   Coverslip cell: %s\n', coverslipCell);
        
        if isnan(trialNum) || isempty(expType)
            fprintf('   ⚠️  Filename parsing issues detected\n');
        end
        
        % Step 6: Test ROI filtering
        fprintf('\nSTEP 6: Testing ROI filtering\n');
        fprintf('==============================\n');
        
        try
            if strcmp(expType, 'PPF') && isfinite(ppiValue)
                [filteredData, filteredHeaders, filteredThresholds, filterStats] = ...
                    modules.filter.filterROIs(dF_values, validHeaders, thresholds, 'PPF', ppiValue);
            else
                [filteredData, filteredHeaders, filteredThresholds, filterStats] = ...
                    modules.filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
            end
            
            if isempty(filteredData)
                fprintf('❌ ROI filtering removed ALL ROIs\n');
                fprintf('   This is likely the main problem!\n');
                fprintf('   Original ROIs: %d\n', length(validHeaders));
                fprintf('   Filtered ROIs: 0\n');
                
                if isfield(filterStats, 'summary')
                    fprintf('   Filter summary: %s\n', filterStats.summary);
                end
                
                % Check why ROIs are being filtered out
                cfg = modules.config;
                stimFrame = cfg.timing.STIMULUS_FRAME;
                postWindow = cfg.timing.POST_STIMULUS_WINDOW;
                
                if stimFrame <= size(dF_values, 1)
                    responseStart = stimFrame + 1;
                    responseEnd = min(stimFrame + postWindow, size(dF_values, 1));
                    maxResponses = max(dF_values(responseStart:responseEnd, :), [], 1);
                    
                    fprintf('\n   Diagnosis:\n');
                    fprintf('   Max responses: %.4f to %.4f\n', min(maxResponses), max(maxResponses));
                    fprintf('   Thresholds: %.4f to %.4f\n', min(thresholds), max(thresholds));
                    
                    passingROIs = maxResponses >= thresholds;
                    fprintf('   ROIs above threshold: %d/%d\n', sum(passingROIs), length(passingROIs));
                    
                    if sum(passingROIs) == 0
                        fprintf('   ❌ No ROIs have responses above threshold\n');
                        fprintf('   Suggested fixes:\n');
                        fprintf('     1. Lower threshold multiplier in config\n');
                        fprintf('     2. Check stimulus timing\n');
                        fprintf('     3. Verify baseline calculation\n');
                    end
                end
                
            else
                fprintf('✅ ROI filtering successful\n');
                fprintf('   Original ROIs: %d\n', length(validHeaders));
                fprintf('   Filtered ROIs: %d\n', length(filteredHeaders));
                fprintf('   Filter rate: %.1f%%\n', length(filteredHeaders)/length(validHeaders)*100);
            end
            
        catch ME
            fprintf('❌ ROI filtering failed: %s\n', ME.message);
            return;
        end
        
        % Summary
        fprintf('\n=======================================================\n');
        fprintf('DIAGNOSIS SUMMARY\n');
        fprintf('=======================================================\n');
        
        if isempty(filteredData)
            fprintf('🔍 PROBLEM IDENTIFIED: All ROIs are being filtered out\n');
            fprintf('\n🔧 LIKELY SOLUTIONS:\n');
            fprintf('1. Reduce filtering strictness in config:\n');
            fprintf('   config.thresholds.SD_MULTIPLIER = 2; %% (current: 3)\n');
            fprintf('   config.filtering.THRESHOLD_PERCENTAGE_1AP = 0.5; %% (current: 1.0)\n\n');
            
            fprintf('2. Check if stimulus timing is correct:\n');
            fprintf('   Expected stimulus at frame %d (%.1f ms)\n', cfg.timing.STIMULUS_FRAME, cfg.timing.STIMULUS_TIME_MS);
            fprintf('   Verify this matches your experimental setup\n\n');
            
            fprintf('3. Inspect your data manually:\n');
            fprintf('   - Are there visible responses after stimulus?\n');
            fprintf('   - Is the baseline stable?\n');
            fprintf('   - Are fluorescence values reasonable?\n');
            
        else
            fprintf('✅ No obvious problems detected!\n');
            fprintf('   File processing should work correctly\n');
        end
        
    catch ME
        fprintf('❌ Diagnostic failed: %s\n', ME.message);
        fprintf('Stack trace:\n');
        for i = 1:min(3, length(ME.stack))
            fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
        end
    end
end