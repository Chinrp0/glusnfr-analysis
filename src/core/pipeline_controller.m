function controller = pipeline_controller()
    % PIPELINE_CONTROLLER - Main pipeline orchestration with comprehensive logging
    
    controller.runMainPipeline = @runMainPipeline;
    controller.setupSystem = @setupSystemCapabilities;
    controller.processSingleFile = @processSingleFile;
    controller.processAllGroups = @processAllGroups;
    controller.detectSystemCapabilities = @detectSystemCapabilities;
    controller.validateProcessingResults = @validateProcessingResults;
end

function runMainPipeline()
    % Main pipeline entry point with comprehensive logging
    
    scriptName = 'GluSnFR-Analysis_';
    version_info = PipelineVersion();
    
    % Initialize comprehensive logging
    logBuffer = {};
    logBuffer{end+1} = sprintf('========================================================');
    logBuffer{end+1} = sprintf('    %s v%s - %s    ', scriptName, version_info.version, version_info.version_name);
    logBuffer{end+1} = sprintf('========================================================');
    logBuffer{end+1} = sprintf('High-performance analysis for glutamate imaging data');
    logBuffer{end+1} = sprintf('Processing Date: %s', char(datetime('now')));
    logBuffer{end+1} = sprintf('');
    
    fprintf('\n');
    fprintf('========================================================\n');
    fprintf('    %s v%s - %s    \n', scriptName, version_info.version, version_info.version_name);
    fprintf('========================================================\n');
    fprintf('High-performance analysis for glutamate imaging data\n');
    fprintf('Processing Date: %s\n', char(datetime('now')));
    fprintf('\n');
    
    globalTimer = tic;
    
    try
        % Load all modules with detailed logging
        fprintf('Setting up MATLAB paths...\n');
        logBuffer{end+1} = 'Setting up MATLAB paths...';
        pathsAdded = setupPipelinePaths();
        logBuffer = [logBuffer, pathsAdded];
        
        fprintf('Loading pipeline modules...\n');
        logBuffer{end+1} = 'Loading pipeline modules...';
        modules = module_loader();
        logBuffer{end+1} = sprintf('✓ All modules loaded successfully (v%s)', version_info.version);
        
        % Step 1: System setup with detailed logging
        fprintf('\n--- STEP 1: System Setup ---\n');
        logBuffer{end+1} = '';
        logBuffer{end+1} = '--- STEP 1: System Setup ---';
        [hasParallelToolbox, hasGPU, gpuInfo, poolObj] = setupSystemCapabilities(modules.config);
        systemLogEntries = logSystemInfo(hasParallelToolbox, hasGPU, gpuInfo);
        logBuffer = [logBuffer, systemLogEntries];
        
        % Step 2: File selection with detailed logging
        fprintf('\n--- STEP 2: File Selection ---\n');
        logBuffer{end+1} = '';
        logBuffer{end+1} = '--- STEP 2: File Selection ---';
        [rawMeanFolder, outputFolders, excelFiles, fileSystemLog] = setupFileSystem(modules.io);
        logBuffer = [logBuffer, fileSystemLog];
        
        % Step 3: File organization with detailed logging
        fprintf('\n--- STEP 3: File Organization ---\n');
        logBuffer{end+1} = '';
        logBuffer{end+1} = '--- STEP 3: File Organization ---';
        step3Timer = tic;
        [groupedFiles, groupKeys, organizationLog] = organizeFilesByGroup(excelFiles, rawMeanFolder, modules);
        step3Time = toc(step3Timer);
        logBuffer = [logBuffer, organizationLog];
        logBuffer{end+1} = sprintf('File organization completed in %.3f seconds', step3Time);
        
        % Step 4: Group processing with detailed logging
        fprintf('\n--- STEP 4: Group Processing ---\n');
        logBuffer{end+1} = '';
        logBuffer{end+1} = '--- STEP 4: Group Processing ---';
        step4Timer = tic;
        [groupResults, groupTimes, processingLog] = processAllGroups(groupedFiles, groupKeys, rawMeanFolder, ...
                                                     outputFolders, hasParallelToolbox, hasGPU, gpuInfo, modules);
        step4Time = toc(step4Timer);
        logBuffer = [logBuffer, processingLog];
        logBuffer{end+1} = sprintf('Group processing completed in %.3f seconds', step4Time);
        
        % Step 5: Validate results
        validateProcessingResults(groupResults);
        logBuffer{end+1} = '✓ Completed processing: All groups successful';
        
        % Step 6: Results analysis with detailed logging
        fprintf('\n--- STEP 5: Results Analysis ---\n');
        logBuffer{end+1} = '';
        logBuffer{end+1} = '--- STEP 5: Results Analysis ---';
        step5Timer = tic;
        summary = modules.analysis.createSummary(groupResults, groupTimes, toc(globalTimer));
        modules.analysis.validateResults(groupResults);
        step5Time = toc(step5Timer);
        logBuffer = [logBuffer, summary.textSummary];
        logBuffer{end+1} = sprintf('Results analysis completed in %.3f seconds', step5Time);
        
        % Save comprehensive log
        totalTime = toc(globalTimer);
        logFileName = fullfile(fileparts(rawMeanFolder), sprintf('modular_pipeline_log_v%s.txt', version_info.version));
        modules.io.writer.writeLog(logBuffer, logFileName);
        
        fprintf('\n=== PIPELINE COMPLETE ===\n');
        fprintf('Total processing time: %.2f seconds\n', totalTime);
        fprintf('Performance: %s\n', summary.statistics.performanceCategory);
        fprintf('Log saved to: %s\n', logFileName);
        
    catch ME
        fprintf('\n=== PIPELINE ERROR ===\n');
        fprintf('Error: %s\n', ME.message);
        
        % Add error to log
        logBuffer{end+1} = '';
        logBuffer{end+1} = '=== PIPELINE ERROR ===';
        logBuffer{end+1} = sprintf('Error: %s', ME.message);
        logBuffer{end+1} = 'Stack trace:';
        for i = 1:length(ME.stack)
            logBuffer{end+1} = sprintf('  %s at line %d', ME.stack(i).name, ME.stack(i).line);
        end
        
        % Save error log (FIXED: Use new split IO structure)
        if exist('rawMeanFolder', 'var') && exist('modules', 'var')
            errorLogFile = fullfile(fileparts(rawMeanFolder), sprintf('error_log_v%s.txt', version_info.version));
            modules.io.writer.writeLog(logBuffer, errorLogFile);
            fprintf('Error log saved to: %s\n', errorLogFile);
        end
        
        rethrow(ME);
    end
end

function pathsAdded = setupPipelinePaths()
    % Setup paths with detailed logging
    
    % Get the directory where this script is located
    [scriptDir, ~, ~] = fileparts(mfilename('fullpath'));
    
    % Navigate to project root (assuming this script is in src/core/)
    projectRoot = fileparts(fileparts(scriptDir));
    
    % Add all necessary directories to path
    pathsToAdd = {
        fullfile(projectRoot, 'config'),
        fullfile(projectRoot, 'src', 'core'),
        fullfile(projectRoot, 'src', 'processing'), 
        fullfile(projectRoot, 'src', 'io'),
        fullfile(projectRoot, 'src', 'plotting'),
        fullfile(projectRoot, 'src', 'utils'),
        fullfile(projectRoot, 'src', 'analysis'),
        fullfile(projectRoot, 'tests')
    };
    
    pathsAdded = {};
    
    % Add each path if it exists
    for i = 1:length(pathsToAdd)
        if exist(pathsToAdd{i}, 'dir')
            addpath(pathsToAdd{i});
            pathEntry = sprintf('  Added: %s', pathsToAdd{i});
            fprintf('%s\n', pathEntry);
            pathsAdded{end+1} = pathEntry;
        else
            warning('Directory not found: %s', pathsToAdd{i});
        end
    end
    
    pathsAdded{end+1} = '✓ All paths configured';
    fprintf('✓ All paths configured\n');
end

function [hasParallelToolbox, hasGPU, gpuInfo, poolObj] = setupSystemCapabilities(config)
    % Setup and detect system capabilities with detailed logging
    
    % Check MATLAB version
    matlab_version = version('-release');
    fprintf('MATLAB Version: %s\n', matlab_version);
    
    % Detect system capabilities
    hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox');
    hasGPU = false;
    gpuInfo = struct('name', 'None', 'memory', 0, 'deviceCount', 0);
    
    % GPU detection with detailed info
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
    
    % Setup parallel pool with logging
    poolObj = [];
    if hasParallelToolbox
        poolObj = setupParallelPool(hasGPU, gpuInfo);
        
        % Configure GPU on workers if available
        configureGPUOnWorkers(hasGPU, gpuInfo);
    end
end

function poolObj = setupParallelPool(hasGPU, gpuInfo)
    % Setup parallel processing pool with logging
    
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
        
    catch ME
        fprintf('Could not start parallel pool: %s\n', ME.message);
        poolObj = [];
    end
end

function [rawMeanFolder, outputFolders, excelFiles, fileSystemLog] = setupFileSystem(io)
    % Setup file system with comprehensive logging (FIXED: Use new IO structure)
    
    fileSystemLog = {};
    fileSystemLog{end+1} = 'Setting up file system...';
    fprintf('Setting up file system...\n');
    
    version_info = PipelineVersion();
    VERSION = version_info.legacy_version;
    
    % Default directory (can be customized)
    defaultDir = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\';
    
    % Select input folder with logging
    if exist(defaultDir, 'dir')
        fileSystemLog{end+1} = sprintf('Default directory found: %s', defaultDir);
        fprintf('Default directory found: %s\n', defaultDir);
        rawMeanFolder = uigetdir(defaultDir, 'Select the "5_raw_mean" subfolder in GPU_Processed_Images');
    else
        fileSystemLog{end+1} = 'Default directory not found, please select manually';
        fprintf('Default directory not found, please select manually\n');
        rawMeanFolder = uigetdir(pwd, 'Select folder containing Excel files');
    end
    
    if isequal(rawMeanFolder, 0)
        error('No folder selected. Pipeline cancelled.');
    end
    
    fileSystemLog{end+1} = sprintf('Selected input folder: %s', rawMeanFolder);
    fprintf('Selected input folder: %s\n', rawMeanFolder);
    
    % Create output folders with logging
    processedImagesFolder = fileparts(rawMeanFolder);
    outputFolders = struct();
    outputFolders.main = fullfile(processedImagesFolder, sprintf('6_v%s_dF_F', VERSION));
    
    plotsMainFolder = fullfile(processedImagesFolder, sprintf('6_v%s_dF_plots', VERSION));
    outputFolders.plots_main = plotsMainFolder;
    outputFolders.roi_trials = fullfile(plotsMainFolder, 'ROI_trials');
    outputFolders.roi_averages = fullfile(plotsMainFolder, 'ROI_Averages');
    outputFolders.coverslip_averages = fullfile(plotsMainFolder, 'Coverslip_Averages');
    
    fileSystemLog{end+1} = 'Creating output directories...';
    fprintf('Creating output directories...\n');
    
    % FIXED: Complete the directories array properly
    directories = {outputFolders.main, outputFolders.plots_main, outputFolders.roi_trials, ...
                   outputFolders.roi_averages, outputFolders.coverslip_averages};
    
    % Create directories
    for i = 1:length(directories)
        if ~exist(directories{i}, 'dir')
            mkdir(directories{i});
            dirEntry = sprintf('Created directory: %s', directories{i});
            fileSystemLog{end+1} = dirEntry;
            fprintf('%s\n', dirEntry);
        end
    end
    
    % Get and validate Excel files with logging (FIXED: Use new reader)
    fileSystemLog{end+1} = 'Scanning for Excel files...';
    fprintf('Scanning for Excel files...\n');
    
    try
        excelFiles = io.reader.getFiles(rawMeanFolder);
        
        fileSystemLog{end+1} = sprintf('Found %d valid Excel files (out of %d total)', length(excelFiles), length(excelFiles));
        fileSystemLog{end+1} = sprintf('Successfully found %d valid Excel files', length(excelFiles));
        
        % Show first few files for confirmation
        numToShow = min(3, length(excelFiles));
        fileSystemLog{end+1} = sprintf('First %d files:', numToShow);
        fprintf('First %d files:\n', numToShow);
        for i = 1:numToShow
            fileEntry = sprintf('  %d. %s', i, excelFiles(i).name);
            fileSystemLog{end+1} = fileEntry;
            fprintf('%s\n', fileEntry);
        end
        
    catch ME
        error('ERROR getting Excel files: %s', ME.message);
    end
    
    % Final summary
    fileSystemLog{end+1} = 'File system setup complete!';
    fileSystemLog{end+1} = sprintf('Input: %s (%d files)', rawMeanFolder, length(excelFiles));
    fileSystemLog{end+1} = sprintf('Output: %s', outputFolders.main);
    fileSystemLog{end+1} = sprintf('Plots: %s', outputFolders.plots_main);
    
    fprintf('File system setup complete!\n');
    fprintf('Input: %s (%d files)\n', rawMeanFolder, length(excelFiles));
    fprintf('Output: %s\n', outputFolders.main);
    fprintf('Plots: %s\n', outputFolders.plots_main);
end

function [groupedFiles, groupKeys, organizationLog] = organizeFilesByGroup(excelFiles, rawMeanFolder, modules)
    % Organize files by group with detailed logging
    
    organizationLog = {};
    organizationLog{end+1} = sprintf('Organizing %d files by experimental groups...', length(excelFiles));
    fprintf('Organizing %d files by experimental groups...\n', length(excelFiles));
    
    [groupedFiles, groupKeys] = modules.organize.organizeFilesByGroup(excelFiles, rawMeanFolder);
    
    organizationLog{end+1} = sprintf('Successfully organized %d/%d files into %d groups', length(excelFiles), length(excelFiles), length(groupKeys));
    
    % Log each group
    for i = 1:length(groupKeys)
        groupEntry = sprintf('  Group %d: %s (%d files)', i, groupKeys{i}, length(groupedFiles{i}));
        organizationLog{end+1} = groupEntry;
        fprintf('%s\n', groupEntry);
    end
end

function [groupResults, groupTimes, processingLog] = processAllGroups(groupedFiles, groupKeys, rawMeanFolder, ...
                                                      outputFolders, hasParallelToolbox, hasGPU, gpuInfo, modules)
    % Process all groups with detailed logging
    
    processingLog = {};
    numGroups = length(groupKeys);
    groupResults = cell(numGroups, 1);
    groupTimes = zeros(numGroups, 1);
    
    % Determine processing approach
    useParallel = shouldUseGroupParallel(numGroups, hasParallelToolbox);
    
    if useParallel
        processingLog{end+1} = sprintf('  → Group-level parallel: %d groups, %d cores', numGroups, feature('numcores'));
        fprintf('  → Group-level parallel: %d groups, %d cores\n', numGroups, feature('numcores'));
        processingLog{end+1} = sprintf('Processing %d groups in parallel', numGroups);
        fprintf('Processing %d groups in parallel\n', numGroups);
        
        % Pass modules as constant to avoid reloading in parfor
        modulesConstant = parallel.pool.Constant(modules);
        
        parfor groupIdx = 1:numGroups
            [groupResults{groupIdx}, groupTimes(groupIdx)] = processGroup(...
                groupIdx, groupKeys{groupIdx}, groupedFiles{groupIdx}, ...
                rawMeanFolder, outputFolders, hasGPU, gpuInfo, modulesConstant.Value);
        end
        
    else
        if ~hasParallelToolbox
            processingLog{end+1} = '  → Sequential: No parallel toolbox';
            fprintf('  → Sequential: No parallel toolbox\n');
        elseif numGroups < 3
            processingLog{end+1} = sprintf('  → Sequential: Only %d groups', numGroups);
            fprintf('  → Sequential: Only %d groups\n', numGroups);
        else
            processingLog{end+1} = sprintf('  → Sequential: Limited cores');
            fprintf('  → Sequential: Limited cores\n');
        end
        
        processingLog{end+1} = sprintf('Processing %d groups sequentially', numGroups);
        fprintf('Processing %d groups sequentially\n', numGroups);
        
        for groupIdx = 1:numGroups
            [groupResults{groupIdx}, groupTimes(groupIdx)] = processGroup(...
                groupIdx, groupKeys{groupIdx}, groupedFiles{groupIdx}, ...
                rawMeanFolder, outputFolders, hasGPU, gpuInfo, modules);
        end
    end
    
    % Performance summary
    totalTime = sum(groupTimes);
    avgTime = totalTime / numGroups;
    summaryEntry = sprintf('Group processing complete: %.2fs total, %.2fs/group', totalTime, avgTime);
    processingLog{end+1} = summaryEntry;
    fprintf('%s\n', summaryEntry);
end

function useParallel = shouldUseGroupParallel(numGroups, hasParallelToolbox)
    % Decide if group-level parallel processing is beneficial
    
    numCores = feature('numcores');
    hasEnoughGroups = numGroups >= 3;
    hasEnoughCores = numCores >= 4;
    
    useParallel = hasParallelToolbox && hasEnoughGroups && hasEnoughCores;
end

function [result, processingTime] = processGroup(groupIdx, groupKey, filesInGroup, ...
                                               rawMeanFolder, outputFolders, hasGPU, gpuInfo, modules)
    % Process a single group with logging
    
    groupTimer = tic;
    result = struct('status', 'processing', 'groupKey', groupKey, 'numFiles', length(filesInGroup));
    
    fprintf('Processing Group %d: %s\n', groupIdx, groupKey);
    
    try
        % Process group files
        [groupData, groupMetadata] = processGroupFiles(filesInGroup, rawMeanFolder, modules, hasGPU, gpuInfo);
        
        if isempty(groupData)
            result.status = 'warning';
            result.message = 'No valid data found in group';
            processingTime = toc(groupTimer);
            fprintf('  ⚠️  No valid data found\n');
            return;
        end
        
        % Organize data
        [organizedData, averagedData, roiInfo] = modules.organize.organizeGroupData(groupData, groupMetadata, groupKey);
        
        % Count total ROIs and files processed
        totalROIs = 0;
        totalOriginalROIs = 0;
        validFiles = 0;
        for i = 1:length(groupMetadata)
            if ~isempty(groupMetadata{i})
                validFiles = validFiles + 1;
                totalROIs = totalROIs + groupMetadata{i}.numROIs;
                totalOriginalROIs = totalOriginalROIs + groupMetadata{i}.numOriginalROIs;
            end
        end
        
        % Save results (FIXED: Use new writer)
        cfg = modules.config;
        modules.io.writer.writeResults(organizedData, averagedData, roiInfo, groupKey, outputFolders.main, cfg);
        
        % Generate plots
        plotFolders = struct();
        plotFolders.roi_trials = outputFolders.roi_trials;
        plotFolders.roi_averages = outputFolders.roi_averages;
        plotFolders.coverslip_averages = outputFolders.coverslip_averages;
        
        modules.plot.generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, plotFolders);
        
        result = prepareGroupResult(groupData, groupMetadata, roiInfo, 'success');
        result.groupKey = groupKey;
        
        % Summary with metrics
        if totalOriginalROIs > 0
            filterRate = (totalROIs / totalOriginalROIs) * 100;
        else
            filterRate = 0;
        end
        
        processingTime = toc(groupTimer);
        fprintf('  ✅ %d files → %d ROIs (%.1f%% passed) → Excel + plots (%.2fs)\n', ...
                validFiles, totalROIs, filterRate, processingTime);
        
    catch ME
        processingTime = toc(groupTimer);
        fprintf('  ❌ ERROR: %s (%.2fs)\n', ME.message, processingTime);
        result.status = 'error';
        result.message = ME.message;
        result.stackTrace = ME.stack;
    end
end

function [groupData, groupMetadata] = processGroupFiles(filesInGroup, rawMeanFolder, modules, hasGPU, gpuInfo)
    % Process group files
    
    numFiles = length(filesInGroup);
    groupData = cell(numFiles, 1);
    groupMetadata = cell(numFiles, 1);
    
    % Process each file in the group
    for fileIdx = 1:numFiles
        try
            [groupData{fileIdx}, groupMetadata{fileIdx}] = processSingleFile(...
                filesInGroup(fileIdx), rawMeanFolder, true, hasGPU, gpuInfo);
        catch ME
            fprintf('    ⚠️  File %s failed\n', filesInGroup(fileIdx).name);
            groupData{fileIdx} = [];
            groupMetadata{fileIdx} = [];
        end
    end
    
    % Remove empty entries
    validEntries = ~cellfun(@isempty, groupData);
    groupData = groupData(validEntries);
    groupMetadata = groupMetadata(validEntries);
end

function [data, metadata] = processSingleFile(fileInfo, rawMeanFolder, useReadMatrix, hasGPU, gpuInfo)
    % UPDATED: Store filtering statistics for plotting
    
    fullFilePath = fullfile(fileInfo.folder, fileInfo.name);
    
    % Load configuration and modules
    cfg = GluSnFRConfig();
    reader = excel_reader();
    calc = df_calculator();
    filter = roi_filter();
    utils = string_utils(cfg);
    
    % Read file
    [rawData, headers, readSuccess] = reader.readFile(fullFilePath, useReadMatrix);
    
    if ~readSuccess || isempty(rawData)
        error('Failed to read file: %s', fileInfo.name);
    end
    
    % Extract valid data
    [validHeaders, validColumns] = reader.extractHeaders(headers);
    
    if isempty(validHeaders)
        error('No valid ROI headers found in %s', fileInfo.name);
    end
    
    % Extract data and calculate dF/F
    numericData = single(rawData(:, validColumns));
    timeData_ms = single((0:(size(numericData, 1)-1))' * cfg.timing.MS_PER_FRAME);
    [dF_values, thresholds, gpuUsed] = calc.calculate(numericData, hasGPU, gpuInfo);
    
    % Extract experiment info
    [trialNum, expType, ppiValue, coverslipCell] = utils.extractTrialOrPPI(fileInfo.name);
    
    % Apply filtering (THIS IS WHERE SCHMITT RESULTS ARE GENERATED)
    if strcmp(expType, 'PPF') && isfinite(ppiValue)
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, 'PPF', ppiValue);
    else
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
    end
    
    % Prepare output - ENHANCED: Include full filtering statistics
    data = struct();
    data.timeData_ms = timeData_ms;
    data.dF_values = finalDFValues;
    data.roiNames = finalHeaders;
    data.thresholds = finalThresholds;
    data.stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    data.gpuUsed = gpuUsed;
    data.filterStats = filterStats;  % CRITICAL: Include full filter stats
    
    % ENHANCEMENT: If Schmitt trigger was used, also store original headers mapping
    if isfield(filterStats, 'schmitt_info')
        data.originalHeaders = validHeaders;  % For mapping back to original ROI names
        data.originalThresholds = thresholds; % Original thresholds before filtering
    end
    
    metadata = struct();
    metadata.filename = fileInfo.name;
    metadata.numFrames = size(numericData, 1);
    metadata.numROIs = length(finalHeaders);
    metadata.numOriginalROIs = length(validHeaders);
    metadata.filterRate = metadata.numROIs / metadata.numOriginalROIs;
    metadata.gpuUsed = gpuUsed;
    metadata.dataType = 'single';
    metadata.trialNumber = trialNum;
    metadata.experimentType = expType;
    metadata.ppiValue = ppiValue;
    metadata.coverslipCell = coverslipCell;
    metadata.filteringMethod = filterStats.method;  % Track which filtering method was used
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
    
    % Calculate total original ROIs
    totalOriginalROIs = 0;
    for i = 1:length(groupMetadata)
        if isfield(groupMetadata{i}, 'numOriginalROIs')
            totalOriginalROIs = totalOriginalROIs + groupMetadata{i}.numOriginalROIs;
        end
    end
    result.numOriginalROIs = totalOriginalROIs;
    
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
    % Create detailed system info log entries
    
    logEntries = {};
    logEntries{end+1} = sprintf('MATLAB Version: %s', version('-release'));
    
    if hasGPU
        logEntries{end+1} = sprintf('GPU detected: %s (%.1f GB available)', gpuInfo.name, gpuInfo.memory);
    else
        logEntries{end+1} = 'No compatible GPU found';
    end
    
    if hasParallelToolbox
        poolObj = gcp('nocreate');
        if ~isempty(poolObj)
            logEntries{end+1} = sprintf('Using existing parallel pool with %d workers', poolObj.NumWorkers);
        end
        logEntries{end+1} = 'GPU configuration completed on all workers';
    end
end

function [hasParallelToolbox, hasGPU, gpuInfo] = detectSystemCapabilities()
    % Detect system capabilities for optimal processing
    
    hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox');
    
    hasGPU = false;
    gpuInfo = struct('name', 'None', 'memory', 0, 'deviceCount', 0, 'computeCapability', 0);
    
    if hasParallelToolbox
        try
            gpuDevice();
            gpu = gpuDevice();
            hasGPU = true;
            gpuInfo.name = gpu.Name;
            gpuInfo.memory = gpu.AvailableMemory / 1e9;
            gpuInfo.deviceCount = gpuDeviceCount();
            gpuInfo.computeCapability = gpu.ComputeCapability;
        catch
            % No GPU available
        end
    end
end

function validateProcessingResults(groupResults)
    % Validate that processing was successful
    
    successCount = 0;
    errorCount = 0;
    warningCount = 0;
    
    for i = 1:length(groupResults)
        if isfield(groupResults{i}, 'status')
            if strcmp(groupResults{i}.status, 'success')
                successCount = successCount + 1;
            elseif strcmp(groupResults{i}.status, 'error')
                errorCount = errorCount + 1;
            elseif strcmp(groupResults{i}.status, 'warning')
                warningCount = warningCount + 1;
            end
        end
    end
    
    fprintf('✓ Completed processing: %d/%d groups successful\n', successCount, length(groupResults));
    
    if successCount == 0
        error('No groups processed successfully');
    end
end

function configureGPUOnWorkers(hasGPU, gpuInfo)
    % CONFIGUREGPUONWORKERS - Properly configure GPU on parallel workers
    % 
    % REPLACES configureGPUOnWorkers in pipeline_controller.m (lines 775-830)
    % Fixes the "Unknown parallel pool type" warning
    
    if ~hasGPU
        return; % No GPU to configure
    end
    
    pool = gcp('nocreate');
    if isempty(pool)
        return; % No pool to configure
    end
    
    % Get pool type - handle different MATLAB versions
    try
        if isprop(pool, 'Cluster')
            poolType = pool.Cluster.Type;
        elseif isprop(pool, 'Type')
            poolType = pool.Type;
        else
            poolType = 'unknown';
        end
    catch
        poolType = 'unknown';
    end
    
    % Convert to lowercase for consistent checking
    poolTypeLower = lower(poolType);
    
    % Determine pool type and configure accordingly
    if contains(poolTypeLower, 'process')
        % Process-based pool - use parfeval
        fprintf('Configuring GPU on process-based parallel pool...\n');
        
        numWorkers = pool.NumWorkers;
        futures = parallel.FevalFuture.empty(numWorkers, 0);
        
        for w = 1:numWorkers
            futures(w) = parfeval(@setupWorkerGPU, 1);
        end
        
        % Wait for all workers with timeout
        try
            results = fetchOutputs(futures, 'UniformOutput', false);
            successCount = sum(cellfun(@(x) x, results));
            
            if successCount > 0
                fprintf('GPU configured on %d/%d workers\n', successCount, numWorkers);
            else
                fprintf('Warning: GPU configuration failed on all workers\n');
            end
        catch ME
            fprintf('Warning: GPU configuration timeout or error: %s\n', ME.message);
        end
        
    elseif contains(poolTypeLower, 'thread')
        % Thread-based pool - can use spmd (but may not support GPU)
        fprintf('Thread-based pool detected - GPU may not be supported\n');
        
        % Try to configure but don't fail if it doesn't work
        try
            spmd
                if gpuDeviceCount > 0
                    gpuDevice(1);
                end
            end
            fprintf('GPU configuration attempted on thread-based pool\n');
        catch ME
            % This is expected for thread pools - they don't support GPU
            fprintf('Note: Thread-based pools typically do not support GPU operations\n');
        end
        
    elseif contains(poolTypeLower, 'local')
        % Local pool - try parfeval approach
        fprintf('Configuring GPU on local parallel pool...\n');
        
        try
            numWorkers = pool.NumWorkers;
            futures = parallel.FevalFuture.empty(numWorkers, 0);
            
            for w = 1:numWorkers
                futures(w) = parfeval(@setupWorkerGPU, 1);
            end
            
            results = fetchOutputs(futures, 'UniformOutput', false);
            successCount = sum(cellfun(@(x) x, results));
            
            if successCount > 0
                fprintf('GPU configured on %d/%d workers\n', successCount, numWorkers);
            end
        catch ME
            fprintf('Warning: GPU configuration failed: %s\n', ME.message);
        end
        
    else
        % Unknown pool type - try parfeval as safest option
        fprintf('Pool type "%s" - attempting GPU configuration...\n', poolType);
        
        try
            numWorkers = pool.NumWorkers;
            futures = parallel.FevalFuture.empty(numWorkers, 0);
            
            for w = 1:numWorkers
                futures(w) = parfeval(@setupWorkerGPU, 1);
            end
            
            % Use shorter timeout for unknown pool types
            results = fetchOutputs(futures, 'UniformOutput', false);
            successCount = sum(cellfun(@(x) x, results));
            
            if successCount > 0
                fprintf('GPU configured on %d/%d workers\n', successCount, numWorkers);
            else
                % This is not an error - GPU might not be needed for this pool type
                fprintf('Note: GPU configuration not available for this pool type\n');
            end
            
        catch ME
            % Not a critical error - processing can continue without GPU on workers
            fprintf('Note: GPU configuration not supported for pool type "%s"\n', poolType);
        end
    end
end

function success = setupWorkerGPU()
    % SETUPWORKERGPU - Configure GPU on a single worker
    % Helper function for parfeval-based GPU setup
    
    success = false;
    try
        if gpuDeviceCount > 0
            gpu = gpuDevice(1);
            % Warm up the GPU with a small operation
            dummy = gpuArray(ones(100, 'single'));
            clear dummy;
            success = true;
        end
    catch
        success = false;
    end
end