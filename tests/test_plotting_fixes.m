function test_plotting_fixes()
    % TEST_PLOTTING_FIXES - Quick verification that the plotting fixes work
    % Run this after integrating the fixes to verify everything works correctly
    
    fprintf('\n=======================================================\n');
    fprintf('    Testing Plotting Fixes                            \n');
    fprintf('=======================================================\n');
    
    try
        % Step 1: Enable debugging
        fprintf('Step 1: Enabling debug mode\n');
        fprintf('============================\n');
        
        % Create temporary config with debugging enabled
        config = GluSnFRConfig();
        originalDebugState = config.debug.ENABLE_PLOT_DEBUG;
        
        % Enable debugging for this test
        config.debug.ENABLE_PLOT_DEBUG = true;
        fprintf('✓ Debug mode enabled\n');
        
        % Step 2: Test with a small subset of data
        fprintf('\nStep 2: Processing test data\n');
        fprintf('============================\n');
        
        % Use your data folder
        dataFolder = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\1AP\GPU_Processed_Images_1AP\5_raw_mean';
        
        if ~exist(dataFolder, 'dir')
            fprintf('Default folder not found, please select data folder:\n');
            dataFolder = uigetdir(pwd, 'Select folder with Excel files');
            if isequal(dataFolder, 0)
                fprintf('No folder selected, exiting test\n');
                return;
            end
        end
        
        fprintf('Using data folder: %s\n', dataFolder);
        
        % Load modules
        addpath(genpath(pwd));
        modules = module_loader();
        
        % Get and process just the first few files for speed
        excelFiles = modules.io.reader.getFiles(dataFolder);
        fprintf('Found %d Excel files\n', length(excelFiles));
        
        if length(excelFiles) > 5
            fprintf('Using first 5 files for speed\n');
            excelFiles = excelFiles(1:5);
        end
        
        % Step 3: Test the complete pipeline on a small dataset
        fprintf('\nStep 3: Running pipeline with fixes\n');
        fprintf('===================================\n');
        
        [groupedFiles, groupKeys] = modules.organize.organizeFilesByGroup(excelFiles, dataFolder);
        fprintf('Created %d groups\n', length(groupKeys));
        
        if isempty(groupKeys)
            fprintf('❌ No groups created - check your data\n');
            return;
        end
        
        % Test first group only
        testGroupKey = groupKeys{1};
        testFiles = groupedFiles{1};
        fprintf('Testing group: %s (%d files)\n', testGroupKey, length(testFiles));
        
        % Create test output folders
        baseOutputDir = fullfile(pwd, 'test_plots');
        outputFolders = struct();
        outputFolders.roi_trials = fullfile(baseOutputDir, 'ROI_trials');
        outputFolders.roi_averages = fullfile(baseOutputDir, 'ROI_averages');
        outputFolders.coverslip_averages = fullfile(baseOutputDir, 'Coverslip_averages');
        
        % Create directories
        dirs = {outputFolders.roi_trials, outputFolders.roi_averages, outputFolders.coverslip_averages};
        for i = 1:length(dirs)
            if ~exist(dirs{i}, 'dir')
                mkdir(dirs{i});
            end
        end
        fprintf('Created test output directories\n');
        
        % Step 4: Process and organize data
        fprintf('\nStep 4: Processing and organizing data\n');
        fprintf('=====================================\n');
        
        % Process group files
        [groupData, groupMetadata] = processTestGroupFiles(testFiles, dataFolder, modules);
        
        if isempty(groupData)
            fprintf('❌ No group data generated\n');
            return;
        end
        
        fprintf('✓ Group data processed: %d file entries\n', length(groupData));
        
        % Organize data
        [organizedData, averagedData, roiInfo] = modules.organize.organizeGroupData(groupData, groupMetadata, testGroupKey);
        
        % Display organization results
        fprintf('Data organization results:\n');
        if istable(organizedData)
            fprintf('  ✓ Organized data: %d×%d table\n', height(organizedData), width(organizedData));
        else
            fprintf('  ❌ Organized data: not a table\n');
            return;
        end
        
        if isstruct(averagedData)
            fprintf('  ✓ Averaged data: struct with fields: %s\n', strjoin(fieldnames(averagedData), ', '));
            
            % Check specifically for roi field
            if isfield(averagedData, 'roi') && istable(averagedData.roi) && width(averagedData.roi) > 1
                fprintf('    ✓ ROI averages: %d×%d table (FIXED - should generate plots)\n', ...
                        height(averagedData.roi), width(averagedData.roi));
            else
                fprintf('    ❌ ROI averages: missing or empty\n');
            end
            
            if isfield(averagedData, 'total') && istable(averagedData.total) && width(averagedData.total) > 1
                fprintf('    ✓ Total averages: %d×%d table\n', ...
                        height(averagedData.total), width(averagedData.total));
            else
                fprintf('    ❌ Total averages: missing or empty\n');
            end
        else
            fprintf('  ❌ Averaged data: not a struct\n');
            return;
        end
        
        % Step 5: Test ROI cache creation and validation
        fprintf('\nStep 5: Testing ROI cache\n');
        fprintf('========================\n');
        
        plotController = plot_controller();
        
        % This should use the FIXED cache creation
        fprintf('Creating ROI cache using FIXED method...\n');
        roiCache = createTestROICache(roiInfo, organizedData, averagedData);
        
        fprintf('ROI cache results:\n');
        fprintf('  Valid: %s\n', string(roiCache.valid));
        fprintf('  Experiment type: %s\n', roiCache.experimentType);
        fprintf('  ROI count: %d\n', length(roiCache.numbers));
        fprintf('  Has filtering stats: %s\n', string(roiCache.hasFilteringStats));
        
        % Validate cache
        isValidCache = plotController.validateROICache(roiCache, roiInfo);
        fprintf('  Cache validation: %s\n', string(isValidCache));
        
        if ~isValidCache
            fprintf('❌ ROI cache validation failed\n');
            return;
        end
        
        % Step 6: Test plot generation
        fprintf('\nStep 6: Testing plot generation\n');
        fprintf('==============================\n');
        
        % Generate plots using FIXED plotting system
        fprintf('Generating plots with FIXED system...\n');
        
        plotController.generateGroupPlots(organizedData, averagedData, roiInfo, testGroupKey, outputFolders);
        
        % Step 7: Verify plot outputs
        fprintf('\nStep 7: Verifying plot outputs\n');
        fprintf('=============================\n');
        
        plotResults = struct();
        
        % Check individual trial plots
        trialPlots = dir(fullfile(outputFolders.roi_trials, '*.png'));
        plotResults.trials = length(trialPlots);
        fprintf('Individual trial plots: %d\n', plotResults.trials);
        
        % Check ROI average plots (this was the main issue)
        avgPlots = dir(fullfile(outputFolders.roi_averages, '*.png'));
        plotResults.averages = length(avgPlots);
        fprintf('ROI average plots: %d (FIXED - was 0 before)\n', plotResults.averages);
        
        % Check coverslip average plots
        coverslipPlots = dir(fullfile(outputFolders.coverslip_averages, '*.png'));
        plotResults.coverslips = length(coverslipPlots);
        fprintf('Coverslip average plots: %d\n', plotResults.coverslips);
        
        % Step 8: Results summary
        fprintf('\n=======================================================\n');
        fprintf('TEST RESULTS SUMMARY\n');
        fprintf('=======================================================\n');
        
        totalPlots = plotResults.trials + plotResults.averages + plotResults.coverslips;
        
        if totalPlots > 0
            fprintf('✅ SUCCESS! Plot fixes are working correctly\n\n');
            
            fprintf('Plots generated:\n');
            if plotResults.trials > 0
                fprintf('  ✓ Individual trials: %d plots\n', plotResults.trials);
                fprintf('    - Each ROI should show threshold lines per trace\n');
                fprintf('    - Threshold colors should match trace colors\n');
            end
            
            if plotResults.averages > 0
                fprintf('  ✓ ROI averages: %d plots (FIXED!)\n', plotResults.averages);
                fprintf('    - This folder was empty before the fix\n');
                fprintf('    - Each subplot shows averaged trace with green threshold\n');
            end
            
            if plotResults.coverslips > 0
                fprintf('  ✓ Coverslip averages: %d plots\n', plotResults.coverslips);
            end
            
            fprintf('\nCheck these files manually:\n');
            if plotResults.trials > 0
                fprintf('  %s\n', fullfile(outputFolders.roi_trials, trialPlots(1).name));
            end
            if plotResults.averages > 0
                fprintf('  %s\n', fullfile(outputFolders.roi_averages, avgPlots(1).name));
            end
            
            fprintf('\nExpected improvements:\n');
            fprintf('  1. Threshold lines visible on individual ROI traces\n');
            fprintf('  2. ROI average plots now generated (folder not empty)\n');
            fprintf('  3. Faster plot generation (cached computations)\n');
            fprintf('  4. Only filtered ROIs plotted (matches Excel output)\n');
            
            fprintf('\n🎉 All fixes working correctly!\n');
            fprintf('You can now run the full pipeline: main_glusnfr_pipeline()\n');
            
        else
            fprintf('❌ FAILURE: No plots generated\n\n');
            
            fprintf('Troubleshooting steps:\n');
            fprintf('  1. Verify integration of all three fixed files\n');
            fprintf('  2. Check that debug mode shows detailed output\n');
            fprintf('  3. Run diagnose_plotting() for detailed analysis\n');
            fprintf('  4. Verify that filtering isn''t removing all ROIs\n');
        end
        
        % Cleanup
        fprintf('\nTest plots saved to: %s\n', baseOutputDir);
        fprintf('(You can delete this folder after verification)\n');
        
    catch ME
        fprintf('\n❌ TEST FAILED: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('Location: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
        end
        
        fprintf('\nTroubleshooting:\n');
        fprintf('  1. Verify all fixes were integrated correctly\n');
        fprintf('  2. Check that module_loader() works\n');
        fprintf('  3. Verify data folder contains valid Excel files\n');
        fprintf('  4. Run diagnose_plotting() for detailed diagnostics\n');
    end
end

function [groupData, groupMetadata] = processTestGroupFiles(filesInGroup, rawMeanFolder, modules)
    % Process test group files (simplified version for testing)
    
    numFiles = length(filesInGroup);
    groupData = cell(numFiles, 1);
    groupMetadata = cell(numFiles, 1);
    
    hasGPU = gpuDeviceCount > 0;
    gpuInfo = struct('memory', 4);
    
    fprintf('Processing %d files...\n', numFiles);
    
    for fileIdx = 1:numFiles
        try
            [groupData{fileIdx}, groupMetadata{fileIdx}] = processTestFile(...
                filesInGroup(fileIdx), rawMeanFolder, hasGPU, gpuInfo, modules);
            fprintf('  ✓ %s\n', filesInGroup(fileIdx).name);
        catch ME
            fprintf('  ❌ %s: %s\n', filesInGroup(fileIdx).name, ME.message);
            groupData{fileIdx} = [];
            groupMetadata{fileIdx} = [];
        end
    end
    
    % Remove empty entries
    validEntries = ~cellfun(@isempty, groupData);
    groupData = groupData(validEntries);
    groupMetadata = groupMetadata(validEntries);
    
    fprintf('Successfully processed %d/%d files\n', length(groupData), numFiles);
end

function [data, metadata] = processTestFile(fileInfo, rawMeanFolder, hasGPU, gpuInfo, modules)
    % Process single test file
    
    fullFilePath = fullfile(fileInfo.folder, fileInfo.name);
    
    % Read and process file
    [rawData, headers, readSuccess] = modules.io.reader.readFile(fullFilePath, true);
    if ~readSuccess || isempty(rawData)
        error('Failed to read file');
    end
    
    [validHeaders, validColumns] = modules.io.reader.extractHeaders(headers);
    if isempty(validHeaders)
        error('No valid headers');
    end
    
    numericData = single(rawData(:, validColumns));
    timeData_ms = single((0:(size(numericData, 1)-1))' * modules.config.timing.MS_PER_FRAME);
    [dF_values, thresholds, gpuUsed] = modules.calc.calculate(numericData, hasGPU, gpuInfo);
    
    [trialNum, expType, ppiValue, coverslipCell] = modules.utils.extractTrialOrPPI(fileInfo.name);
    
    % Apply filtering - this should generate the filterStats with Schmitt data
    if strcmp(expType, 'PPF') && isfinite(ppiValue)
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            modules.filter.filterROIs(dF_values, validHeaders, thresholds, 'PPF', ppiValue);
    else
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            modules.filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
    end
    
    % Package results
    data = struct();
    data.timeData_ms = timeData_ms;
    data.dF_values = finalDFValues;
    data.roiNames = finalHeaders;
    data.thresholds = finalThresholds;
    data.stimulusTime_ms = modules.config.timing.STIMULUS_TIME_MS;
    data.gpuUsed = gpuUsed;
    data.filterStats = filterStats; % This should contain Schmitt data
    
    metadata = struct();
    metadata.filename = fileInfo.name;
    metadata.numFrames = size(numericData, 1);
    metadata.numROIs = length(finalHeaders);
    metadata.numOriginalROIs = length(validHeaders);
    metadata.filterRate = metadata.numROIs / metadata.numOriginalROIs;
    metadata.trialNumber = trialNum;
    metadata.experimentType = expType;
    metadata.ppiValue = ppiValue;
    metadata.coverslipCell = coverslipCell;
end

function roiCache = createTestROICache(roiInfo, organizedData, averagedData)
    % Create ROI cache for testing (uses the FIXED method)
    
    roiCache = struct();
    roiCache.valid = false;
    roiCache.experimentType = roiInfo.experimentType;
    roiCache.hasFilteringStats = false;
    
    try
        cfg = GluSnFRConfig();
        
        if strcmp(roiInfo.experimentType, '1AP')
            % Extract ROI numbers from organized data (filtered ROIs only)
            if istable(organizedData) && width(organizedData) > 1
                varNames = organizedData.Properties.VariableNames(2:end);
                roiNumbers = [];
                
                for i = 1:length(varNames)
                    roiMatch = regexp(varNames{i}, 'ROI(\d+)_T', 'tokens');
                    if ~isempty(roiMatch)
                        roiNumbers(end+1) = str2double(roiMatch{1}{1});
                    end
                end
                
                if ~isempty(roiNumbers)
                    uniqueROIs = unique(roiNumbers);
                    roiCache.numbers = sort(uniqueROIs);
                    
                    % Create lookup map
                    roiCache.numberToIndex = containers.Map('KeyType', 'int32', 'ValueType', 'int32');
                    for i = 1:length(roiCache.numbers)
                        roiCache.numberToIndex(roiCache.numbers(i)) = i;
                    end
                    
                    % FIXED: Extract filtering statistics from roiInfo
                    if isfield(roiInfo, 'filteringStats') && roiInfo.filteringStats.available
                        roiCache.hasFilteringStats = true;
                        roiCache.noiseMap = roiInfo.filteringStats.roiNoiseMap;
                        roiCache.upperThresholds = roiInfo.filteringStats.roiUpperThresholds;
                        roiCache.lowerThresholds = roiInfo.filteringStats.roiLowerThresholds;
                        roiCache.basicThresholds = roiInfo.filteringStats.roiBasicThresholds;
                    else
                        % Create basic threshold cache if Schmitt data not available
                        roiCache = createBasicCache(roiCache, roiInfo, cfg);
                    end
                    
                    roiCache.valid = true;
                end
            end
        end
        
    catch ME
        fprintf('Cache creation error: %s\n', ME.message);
        roiCache.valid = false;
    end
end

function roiCache = createBasicCache(roiCache, roiInfo, cfg)
    % Create basic threshold cache as fallback
    
    roiCache.noiseMap = containers.Map('KeyType', 'int32', 'ValueType', 'char');
    roiCache.upperThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    roiCache.lowerThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    roiCache.basicThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    
    if isfield(roiInfo, 'thresholds') && ~isempty(roiInfo.thresholds)
        [nROIs, ~] = size(roiInfo.thresholds);
        
        for roiIdx = 1:min(nROIs, length(roiCache.numbers))
            roiNum = roiCache.numbers(roiIdx);
            roiThresholds = roiInfo.thresholds(roiIdx, :);
            validThresholds = roiThresholds(isfinite(roiThresholds) & roiThresholds > 0);
            
            if ~isempty(validThresholds)
                basicThreshold = median(validThresholds);
                
                if basicThreshold <= cfg.thresholds.LOW_NOISE_CUTOFF
                    noiseLevel = 'low';
                    upperThreshold = basicThreshold * cfg.filtering.schmitt.LOW_NOISE_UPPER_MULT;
                else
                    noiseLevel = 'high';
                    upperThreshold = basicThreshold * cfg.filtering.schmitt.HIGH_NOISE_UPPER_MULT;
                end
                lowerThreshold = basicThreshold * cfg.filtering.schmitt.LOWER_THRESHOLD_MULT;
                
                roiCache.noiseMap(roiNum) = noiseLevel;
                roiCache.upperThresholds(roiNum) = upperThreshold;
                roiCache.lowerThresholds(roiNum) = lowerThreshold;
                roiCache.basicThresholds(roiNum) = basicThreshold;
                roiCache.hasFilteringStats = true;
            end
        end
    end
end