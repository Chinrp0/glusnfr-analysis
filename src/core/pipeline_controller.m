function controller = pipeline_controller()
    % PIPELINE_CONTROLLER - Main pipeline orchestration module
    % 
    % This is the main controller that orchestrates the entire analysis pipeline:
    % - System capability detection
    % - File organization and processing
    % - Parallel processing coordination
    % - Results compilation and saving
    % - Error handling and logging
    
    controller.runMainPipeline = @runMainPipeline;
    controller.setupSystem = @setupSystemCapabilities;
    controller.processAllGroups = @processAllGroups;
    controller.saveAllResults = @saveAllResults;
    controller.generateAllPlots = @generateAllPlots;
end

function runMainPipeline()
    % Main pipeline entry point - replaces the monolithic script
    
    scriptName = 'GluSnFR_Analysis_Pipeline_v50_Modular';
    fprintf('=== %s ===\n', scriptName);
    fprintf('Modular architecture with optimized processing\n');
    fprintf('Processing Date: %s\n', char(datetime('now')));
    
    globalTimer = tic;
    logBuffer = {};
    logBuffer{end+1} = sprintf('=== %s ===', scriptName);
    logBuffer{end+1} = sprintf('Processing Date: %s', char(datetime('now')));
    
    try
        % Load all modules
        fprintf('\nLoading pipeline modules...\n');
        modules = module_loader();
        
        % Step 1: System setup and capability detection
        fprintf('\n--- STEP 1: System Setup ---\n');
        [hasParallelToolbox, hasGPU, gpuInfo, poolObj] = setupSystemCapabilities(modules.config);
        logBuffer = [logBuffer, logSystemInfo(hasParallelToolbox, hasGPU, gpuInfo)];
        
        % Step 2: File selection and validation
        fprintf('\n--- STEP 2: File Selection ---\n');
        [rawMeanFolder, outputFolders, excelFiles] = setupFileSystem(modules.io);
        logBuffer{end+1} = sprintf('Found %d Excel files to process', length(excelFiles));
        logBuffer{end+1} = sprintf('Input folder: %s', rawMeanFolder);
        
        % Step 3: File organization
        fprintf('\n--- STEP 3: File Organization ---\n');
        step3Timer = tic;
        [groupedFiles, groupKeys] = modules.organize.organizeFilesByGroup(excelFiles, rawMeanFolder);
        step3Time = toc(step3Timer);
        logBuffer{end+1} = sprintf('File organization completed in %.3f seconds', step3Time);
        
        % Step 4: Group processing
        fprintf('\n--- STEP 4: Group Processing ---\n');
        step4Timer = tic;
        [groupResults, groupTimes] = processAllGroups(groupedFiles, groupKeys, rawMeanFolder, ...
                                                     outputFolders, hasParallelToolbox, hasGPU, gpuInfo, modules);
        step4Time = toc(step4Timer);
        logBuffer{end+1} = sprintf('Group processing completed in %.3f seconds', step4Time);
        
        % Step 5: Results analysis and summary
        fprintf('\n--- STEP 5: Results Analysis ---\n');
        step5Timer = tic;
        summary = modules.analysis.createResultsSummary(groupResults, groupTimes, toc(globalTimer));
        modules.analysis.validateExperimentResults(groupResults);
        step5Time = toc(step5Timer);
        
        % Add summary to log
        logBuffer = [logBuffer, summary.textSummary];
        logBuffer{end+1} = sprintf('Results analysis completed in %.3f seconds', step5Time);
        
        % Save comprehensive log
        totalTime = toc(globalTimer);
        logFileName = fullfile(fileparts(rawMeanFolder), 'modular_pipeline_log_v50.txt');
        modules.io.saveLog(logBuffer, logFileName);
        
        fprintf('\n=== PIPELINE COMPLETE ===\n');
        fprintf('Total processing time: %.2f seconds\n', totalTime);
        fprintf('Performance: %s\n', summary.statistics.performanceCategory);
        fprintf('Log saved to: %s\n', logFileName);
        
    catch ME
        fprintf('\n=== PIPELINE ERROR ===\n');
        fprintf('Error: %s\n', ME.message);
        fprintf('Stack trace:\n');
        for i = 1:length(ME.stack)
            fprintf('  %s at line %d\n', ME.stack(i).name, ME.stack(i).line);
        end
        
        % Save error log
        if exist('logBuffer', 'var')
            logBuffer{end+1} = sprintf('PIPELINE ERROR: %s', ME.message);
            if exist('rawMeanFolder', 'var')
                errorLogFile = fullfile(fileparts(rawMeanFolder), 'error_log_v50.txt');
                modules.io.saveLog(logBuffer, errorLogFile);
                fprintf('Error log saved to: %s\n', errorLogFile);
            end
        end
        
        rethrow(ME);
    end
end

function [hasParallelToolbox, hasGPU, gpuInfo, poolObj] = setupSystemCapabilities(config)
    % Setup and detect system capabilities
    
    % Check MATLAB version
    matlab_version = version('-release');
    fprintf('MATLAB Version: %s\n', matlab_version);
    
    useReadMatrix = ~verLessThan('matlab', '9.6'); % R2019a+
    if ~useReadMatrix
        warning('This pipeline is optimized for MATLAB R2019a or later');
    end
    
    % Detect system capabilities
    hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox');
    hasGPU = false;
    gpuInfo = struct('name', 'None', 'memory', 0, 'deviceCount', 0);
    
    % GPU detection
    if hasParallelToolbox
        try
            gpuDevice(); % Test GPU availability
            gpu = gpuDevice();
            hasGPU = true;
            gpuInfo.name = gpu.Name;
            gpuInfo.memory = gpu.AvailableMemory / 1e9; % GB
            gpuInfo.deviceCount = gpuDeviceCount();
            
            fprintf('GPU detected: %s (%.1f GB available)\n', gpuInfo.name, gpuInfo.memory);
        catch
            fprintf('No compatible GPU found\n');
        end
    end
    
    % Setup parallel pool
    poolObj = [];
    if hasParallelToolbox
        poolObj = setupParallelPool(hasGPU, gpuInfo);
    end
end

function poolObj = setupParallelPool(hasGPU, gpuInfo)
    % Setup parallel processing pool
    
    poolObj = gcp('nocreate');
    if ~isempty(poolObj)
        fprintf('Using existing parallel pool with %d workers\n', poolObj.NumWorkers);
        return;
    end
    
    % Determine optimal worker count
    workers = min(6, feature('numcores') - 1);
    
    try
        poolObj = parpool('Processes', workers);
        poolObj.IdleTimeout = 60;
        
        fprintf('Started parallel pool with %d workers\n', poolObj.NumWorkers);
        
        % Configure GPU on workers if available
        if hasGPU
            try
                spmd
                    if gpuDeviceCount > 0
                        gpuDevice(1);
                    end
                end
                fprintf('GPU configuration completed on all workers\n');
            catch ME
                fprintf('GPU configuration on workers failed: %s\n', ME.message);
            end
        end
        
    catch ME
        fprintf('Could not start parallel pool: %s\n', ME.message);
        poolObj = [];
    end
end

function [rawMeanFolder, outputFolders, excelFiles] = setupFileSystem(io)
    % Setup file system and validate inputs
    
    % Default directory (can be customized)
    defaultDir = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\';
    
    % Select input folder
    rawMeanFolder = uigetdir(defaultDir, 'Select the "5_raw_mean" subfolder in GPU_Processed_Images');
    
    if isequal(rawMeanFolder, 0)
        error('No folder selected. Pipeline cancelled.');
    end
    
    % Create output folders
    processedImagesFolder = fileparts(rawMeanFolder);
    outputFolders = struct();
    outputFolders.main = fullfile(processedImagesFolder, '6_v50_modular_dF_F');
    outputFolders.individual = fullfile(processedImagesFolder, '6_v50_modular_plots_trials');
    outputFolders.averaged = fullfile(processedImagesFolder, '6_v50_modular_plots_averaged');
    
    % Create directories
    io.createDirectories({outputFolders.main, outputFolders.individual, outputFolders.averaged});
    
    % Get and validate Excel files
    excelFiles = io.getExcelFiles(rawMeanFolder);
    
    if isempty(excelFiles)
        error('No valid Excel files found in: %s', rawMeanFolder);
    end
    
    fprintf('Input folder: %s\n', rawMeanFolder);
    fprintf('Output folder: %s\n', outputFolders.main);
end

function [groupResults, groupTimes] = processAllGroups(groupedFiles, groupKeys, rawMeanFolder, ...
                                                      outputFolders, hasParallelToolbox, hasGPU, gpuInfo, modules)
    % Process all groups with optimal parallelization
    
    numGroups = length(groupKeys);
    groupResults = cell(numGroups, 1);
    groupTimes = zeros(numGroups, 1);
    
    cfg = modules.config;
    
    % Determine processing strategy
    useParallel = hasParallelToolbox && numGroups > 1;
    
    if useParallel
        fprintf('Processing %d groups in parallel\n', numGroups);
        
        % Parallel processing with proper data passing
        parfor groupIdx = 1:numGroups
            [groupResults{groupIdx}, groupTimes(groupIdx)] = processGroup(...
                groupIdx, groupKeys{groupIdx}, groupedFiles{groupIdx}, ...
                rawMeanFolder, outputFolders, hasGPU, gpuInfo);
        end
        
    else
        fprintf('Processing %d groups sequentially\n', numGroups);
        
        % Sequential processing
        for groupIdx = 1:numGroups
            [groupResults{groupIdx}, groupTimes(groupIdx)] = processGroup(...
                groupIdx, groupKeys{groupIdx}, groupedFiles{groupIdx}, ...
                rawMeanFolder, outputFolders, hasGPU, gpuInfo);
        end
    end
    
    % Summary
    successCount = sum(cellfun(@(x) strcmp(x.status, 'success'), groupResults));
    fprintf('Group processing complete: %d/%d successful\n', successCount, numGroups);
end

function [result, processingTime] = processGroup(groupIdx, groupKey, filesInGroup, ...
                                               rawMeanFolder, outputFolders, hasGPU, gpuInfo)
    % Process a single group of files
    
    groupTimer = tic;
    result = struct('status', 'processing', 'groupKey', groupKey, 'numFiles', length(filesInGroup));
    
    fprintf('Processing Group %d: %s (%d files)\n', groupIdx, groupKey, length(filesInGroup));
    
    try
        % Load modules (required for parfor)
        modules = module_loader();
        
        % Process all files in the group
        [groupData, groupMetadata] = processGroupFiles(filesInGroup, rawMeanFolder, modules);
        
        if isempty(groupData)
            result.status = 'warning';
            result.message = 'No valid data found in group';
            processingTime = toc(groupTimer);
            return;
        end
        
        % Organize data
        [organizedData, averagedData, roiInfo] = modules.organize.organizeGroupData(groupData, groupMetadata, groupKey);
        
        % Save results
        saveGroupResults(organizedData, averagedData, roiInfo, groupKey, outputFolders, modules);
        
        % Generate plots
        modules.plot.generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, ...
                                       outputFolders.individual, outputFolders.averaged);
        
        % Prepare result summary
        result = prepareGroupResult(groupData, groupMetadata, roiInfo, 'success');
        result.groupKey = groupKey;
        
    catch ME
        fprintf('  ERROR processing group %s: %s\n', groupKey, ME.message);
        result.status = 'error';
        result.message = ME.message;
        result.stackTrace = ME.stack;
    end
    
    processingTime = toc(groupTimer);
    fprintf('  Group %s completed in %.3f seconds [%s]\n', groupKey, processingTime, result.status);
end

function [groupData, groupMetadata] = processGroupFiles(filesInGroup, rawMeanFolder, modules)
    % Process all files in a group
    
    numFiles = length(filesInGroup);
    groupData = cell(numFiles, 1);
    groupMetadata = cell(numFiles, 1);
    
    validCount = 0;
    useReadMatrix = ~verLessThan('matlab', '9.6');
    
    for fileIdx = 1:numFiles
        try
            hasGPU = gpuDeviceCount > 0;
            gpuInfo = struct('memory', 4); % Default 4GB for parfor
            
            [data, metadata] = modules.analysis.processSingleFile(...
                filesInGroup(fileIdx), rawMeanFolder, useReadMatrix, hasGPU, gpuInfo);
            
            if ~isempty(data)
                validCount = validCount + 1;
                groupData{validCount} = data;
                groupMetadata{validCount} = metadata;
            end
            
        catch ME
            fprintf('    WARNING: Error processing %s: %s\n', filesInGroup(fileIdx).name, ME.message);
        end
    end
    
    % Trim to actual size
    groupData = groupData(1:validCount);
    groupMetadata = groupMetadata(1:validCount);
    
    if validCount < numFiles
        fprintf('    WARNING: %d/%d files processed successfully\n', validCount, numFiles);
    end
end

function saveGroupResults(organizedData, averagedData, roiInfo, groupKey, outputFolders, modules)
    % Save all group results (Excel + metadata)
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    filename = [cleanGroupKey '_grouped_v50_modular.xlsx'];
    filepath = fullfile(outputFolders.main, filename);
    
    % Delete existing file
    if exist(filepath, 'file')
        delete(filepath);
    end
    
    try
        % Save organized data sheets
        if strcmp(roiInfo.experimentType, 'PPF')
            savePPFResults(organizedData, averagedData, roiInfo, filepath, modules);
        else
            save1APResults(organizedData, averagedData, roiInfo, filepath, modules);
        end
        
        % Generate and save metadata
        modules.analysis.generateMetadata(organizedData, roiInfo, filepath);
        
        fprintf('    Saved Excel file: %s\n', filename);
        
    catch ME
        fprintf('    ERROR saving results for %s: %s\n', groupKey, ME.message);
        rethrow(ME);
    end
end

function savePPFResults(organizedData, averagedData, roiInfo, filepath, modules)
    % Save PPF-specific results
    
    % All data sheet
    writeTableWithHeaders(organizedData, filepath, 'All_Data', modules.io, roiInfo, true);
    
    % Averaged data sheet
    writeTableWithHeaders(averagedData, filepath, 'Averaged', modules.io, roiInfo, false);
end

function save1APResults(organizedData, averagedData, roiInfo, filepath, modules)
    % Save 1AP-specific results with noise-based sheets
    
    % Separate by noise level
    [lowNoiseData, highNoiseData] = separateByNoiseLevel(organizedData, roiInfo);
    
    % Write noise-based sheets
    if width(lowNoiseData) > 1
        writeTableWithHeaders(lowNoiseData, filepath, 'Low_noise', modules.io, roiInfo, true);
    end
    
    if width(highNoiseData) > 1
        writeTableWithHeaders(highNoiseData, filepath, 'High_noise', modules.io, roiInfo, true);
    end
    
    % Write averaged sheets
    writeTableWithHeaders(averagedData.roi, filepath, 'ROI_Average', modules.io, roiInfo, false);
    writeTableWithHeaders(averagedData.total, filepath, 'Total_Average', modules.io, roiInfo, false);
end

function [lowNoiseData, highNoiseData] = separateByNoiseLevel(organizedData, roiInfo)
    % Separate data by noise level for 1AP experiments
    
    varNames = organizedData.Properties.VariableNames;
    lowNoiseCols = {'Frame'};
    highNoiseCols = {'Frame'};
    
    for i = 2:length(varNames)
        colName = varNames{i};
        roiMatch = regexp(colName, 'ROI(\d+)_T', 'tokens');
        
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            
            if isKey(roiInfo.roiNoiseMap, roiNum)
                noiseLevel = roiInfo.roiNoiseMap(roiNum);
                
                if strcmp(noiseLevel, 'low')
                    lowNoiseCols{end+1} = colName;
                elseif strcmp(noiseLevel, 'high')
                    highNoiseCols{end+1} = colName;
                end
            end
        end
    end
    
    lowNoiseData = organizedData(:, lowNoiseCols);
    highNoiseData = organizedData(:, highNoiseCols);
end

function writeTableWithHeaders(dataTable, filepath, sheetName, io, roiInfo, isTrialData)
    % Write table with appropriate headers based on experiment type
    
    if width(dataTable) <= 1 % Only Frame column
        return;
    end
    
    if strcmp(roiInfo.experimentType, 'PPF')
        [row1, row2] = createPPFHeaders(dataTable, roiInfo, isTrialData);
    else
        [row1, row2] = create1APHeaders(dataTable, roiInfo, isTrialData);
    end
    
    io.writeExcelWithHeaders(dataTable, filepath, sheetName, row1, row2);
end

function [row1, row2] = createPPFHeaders(dataTable, roiInfo, isTrialData)
    % Create headers for PPF data
    
    varNames = dataTable.Properties.VariableNames;
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    % First column
    row1{1} = sprintf('%dms', roiInfo.timepoint);
    row2{1} = 'Time (ms)';
    
    % Process other columns
    for i = 2:length(varNames)
        varName = varNames{i};
        
        if isTrialData
            % Format: Cs1-c2_ROI3
            roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
            if ~isempty(roiMatch)
                row1{i} = roiMatch{1}{1};  % Cs1-c2
                row2{i} = sprintf('ROI %s', roiMatch{1}{2});  % ROI 3
            end
        else
            % Format: Cs1-c2_n24
            roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
            if ~isempty(roiMatch)
                row1{i} = roiMatch{1}{2};  % 24
                row2{i} = roiMatch{1}{1};  % Cs1-c2
            end
        end
    end
end

function [row1, row2] = create1APHeaders(dataTable, roiInfo, isTrialData)
    % Create headers for 1AP data
    
    varNames = dataTable.Properties.VariableNames;
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    % First column
    if isTrialData
        row1{1} = 'Trial';
        row2{1} = 'Time (ms)';
    else
        row1{1} = 'n';
        row2{1} = 'Time (ms)';
    end
    
    % Process other columns
    for i = 2:length(varNames)
        varName = varNames{i};
        
        if isTrialData
            % Format: ROI123_T5
            roiMatch = regexp(varName, 'ROI(\d+)_T(\d+)', 'tokens');
            if ~isempty(roiMatch)
                row1{i} = roiMatch{1}{2};  % Trial number
                row2{i} = sprintf('ROI %s', roiMatch{1}{1});  % ROI number
            end
        else
            % Format: ROI123_n5 or Low_Noise_n15
            if contains(varName, 'ROI')
                roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    row1{i} = roiMatch{1}{2};  % n count
                    row2{i} = sprintf('ROI %s', roiMatch{1}{1});  % ROI number
                end
            else
                % Total averages
                nMatch = regexp(varName, 'n(\d+)', 'tokens');
                if ~isempty(nMatch)
                    row1{i} = nMatch{1}{1};  % n count
                    if contains(varName, 'Low_Noise')
                        row2{i} = 'Low Noise';
                    elseif contains(varName, 'High_Noise')
                        row2{i} = 'High Noise';
                    else
                        row2{i} = 'All';
                    end
                end
            end
        end
    end
end

function result = prepareGroupResult(groupData, groupMetadata, roiInfo, status)
    % Prepare group result summary
    
    result = struct();
    result.status = status;
    result.experimentType = roiInfo.experimentType;
    result.numFiles = length(groupData);
    result.dataType = roiInfo.dataType;
    
    if strcmp(roiInfo.experimentType, 'PPF')
        if isfield(roiInfo, 'timepoint')
            result.timepoint = roiInfo.timepoint;
        end
        if isfield(roiInfo, 'coverslipFiles')
            result.numCoverslipFiles = length(roiInfo.coverslipFiles);
            totalROIs = 0;
            for i = 1:length(roiInfo.coverslipFiles)
                totalROIs = totalROIs + length(roiInfo.coverslipFiles(i).roiNumbers);
            end
            result.numROIs = totalROIs;
        end
    else
        if isfield(roiInfo, 'roiNumbers')
            result.numROIs = length(roiInfo.roiNumbers);
        end
        if isfield(roiInfo, 'numTrials')
            result.numTrials = roiInfo.numTrials;
        end
    end
    
    % Check GPU usage
    gpuUsed = false;
    for i = 1:length(groupData)
        if ~isempty(groupData{i}) && isfield(groupData{i}, 'gpuUsed') && groupData{i}.gpuUsed
            gpuUsed = true;
            break;
        end
    end
    result.gpuUsed = gpuUsed;
end

function logEntries = logSystemInfo(hasParallelToolbox, hasGPU, gpuInfo)
    % Create system info log entries
    
    logEntries = {};
    logEntries{end+1} = 'System Capabilities:';
    
    if hasParallelToolbox
        logEntries{end+1} = '  CPU Parallel Processing: Available';
    else
        logEntries{end+1} = '  CPU Parallel Processing: Not Available';
    end
    
    if hasGPU
        logEntries{end+1} = sprintf('  GPU Acceleration: Available (%s, %.1fGB)', gpuInfo.name, gpuInfo.memory);
    else
        logEntries{end+1} = '  GPU Acceleration: Not Available';
    end
end