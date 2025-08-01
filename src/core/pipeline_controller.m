function controller = pipeline_controller()
    % PIPELINE_CONTROLLER - Main pipeline orchestration module
    % 
    % Updated with cleaner, more concise output for better user experience
    
    controller.runMainPipeline = @runMainPipeline;
    controller.setupSystem = @setupSystemCapabilities;
    controller.processSingleFile = @processSingleFile;
    controller.processAllGroups = @processAllGroups;
    controller.saveAllResults = @saveAllResults;
    controller.generateAllPlots = @generateAllPlots;
    controller.detectSystemCapabilities = @detectSystemCapabilities;
    controller.validateProcessingResults = @validateProcessingResults;
end

function runMainPipeline()
    % Main pipeline entry point with cleaner output
    
    scriptName = 'GluSnFR-Analysis_';
    version_info = PipelineVersion();
    fprintf('=== %s v%s ===\n', scriptName, version_info.version);
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
        
        % Step 4: Group processing (CLEANED UP OUTPUT)
        fprintf('\n--- STEP 4: Group Processing ---\n');
        step4Timer = tic;
        [groupResults, groupTimes] = processAllGroups(groupedFiles, groupKeys, rawMeanFolder, ...
                                                     outputFolders, hasParallelToolbox, hasGPU, gpuInfo, modules);
        step4Time = toc(step4Timer);
        logBuffer{end+1} = sprintf('Group processing completed in %.3f seconds', step4Time);
        
        % Step 5: Validate results
        validateProcessingResults(groupResults);
        
        % Step 6: Results analysis and summary
        fprintf('\n--- STEP 5: Results Analysis ---\n');
        step5Timer = tic;
        summary = modules.analysis.createSummary(groupResults, groupTimes, toc(globalTimer));
        modules.analysis.validateResults(groupResults);
        step5Time = toc(step5Timer);
        
        % Add summary to log
        logBuffer = [logBuffer, summary.textSummary];
        logBuffer{end+1} = sprintf('Results analysis completed in %.3f seconds', step5Time);
        
        % Save comprehensive log with version info
        totalTime = toc(globalTimer);
        logFileName = fullfile(fileparts(rawMeanFolder), sprintf('modular_pipeline_log_v%s.txt', version_info.version));
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
        
        % Save error log with version info
        if exist('logBuffer', 'var')
            logBuffer{end+1} = sprintf('PIPELINE ERROR: %s', ME.message);
            if exist('rawMeanFolder', 'var') && exist('modules', 'var')
                version_info = PipelineVersion();
                errorLogFile = fullfile(fileparts(rawMeanFolder), sprintf('error_log_v%s.txt', version_info.version));
                modules.io.saveLog(logBuffer, errorLogFile);
                fprintf('Log saved to: %s\n', errorLogFile);
            end
        end
        
        rethrow(ME);
    end
end

function [rawMeanFolder, outputFolders, excelFiles] = setupFileSystem(io)
    % Setup output folder structure
    
    fprintf('Setting up file system...\n');
    
    % ==================== VERSION CONTROL ====================
    version_info = PipelineVersion();
    VERSION = version_info.legacy_version;  % For folder naming compatibility
    SEMANTIC_VERSION = version_info.version; % For display/logging
    % ==========================================================
    
    % Default directory (can be customized)
    defaultDir = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\';
    
    % Select input folder
    if exist(defaultDir, 'dir')
        fprintf('Default directory found: %s\n', defaultDir);
        rawMeanFolder = uigetdir(defaultDir, 'Select the "5_raw_mean" subfolder in GPU_Processed_Images');
    else
        fprintf('Default directory not found, please select manually\n');
        rawMeanFolder = uigetdir(pwd, 'Select folder containing Excel files');
    end
    
    if isequal(rawMeanFolder, 0)
        error('No folder selected. Pipeline cancelled.');
    end
    
    fprintf('Selected input folder: %s\n', rawMeanFolder);
    
    % Create output folders with new structure
    processedImagesFolder = fileparts(rawMeanFolder);
    outputFolders = struct();
    outputFolders.main = fullfile(processedImagesFolder, sprintf('6_v%s_dF_F', VERSION));
    
    % NEW: Single plot folder with 3 subfolders
    plotsMainFolder = fullfile(processedImagesFolder, sprintf('6_v%s_dF_plots', VERSION));
    outputFolders.plots_main = plotsMainFolder;
    outputFolders.roi_trials = fullfile(plotsMainFolder, 'ROI_trials');
    outputFolders.roi_averages = fullfile(plotsMainFolder, 'ROI_Averages');
    outputFolders.coverslip_averages = fullfile(plotsMainFolder, 'Coverslip_Averages');
    
    % Create directories using the io manager
    fprintf('Creating output directories...\n');
    io.createDirectories({
        outputFolders.main, 
        outputFolders.plots_main,
        outputFolders.roi_trials, 
        outputFolders.roi_averages, 
        outputFolders.coverslip_averages
    });
    
    % Get and validate Excel files with improved error handling
    fprintf('Scanning for Excel files...\n');
    try
        excelFiles = io.getExcelFiles(rawMeanFolder);
        
        if isempty(excelFiles)
            error('No valid Excel files found in: %s', rawMeanFolder);
        end
        
        fprintf('Successfully found %d valid Excel files\n', length(excelFiles));
        
        % Show first few files for confirmation
        numToShow = min(3, length(excelFiles));
        fprintf('First %d files:\n', numToShow);
        for i = 1:numToShow
            fprintf('  %d. %s\n', i, excelFiles(i).name);
        end
        
    catch ME
        fprintf('ERROR getting Excel files: %s\n', ME.message);
        fprintf('Folder contents:\n');
        allFiles = dir(rawMeanFolder);
        for i = 1:min(10, length(allFiles))
            if ~allFiles(i).isdir
                fprintf('  %s\n', allFiles(i).name);
            end
        end
        rethrow(ME);
    end
    
    % Final confirmation
    fprintf('File system setup complete!\n');
    fprintf('Input: %s (%d files)\n', rawMeanFolder, length(excelFiles));
    fprintf('Output: %s\n', outputFolders.main);
    fprintf('Plots: %s\n', outputFolders.plots_main);
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
        
        % Configure GPU on workers if available
        if hasGPU && ~isempty(poolObj)
            try
                spmd
                    if gpuDeviceCount > 0
                        gpuDevice(1); % Use first GPU
                    end
                end
                fprintf('GPU configuration completed on all workers\n');
            catch ME
                fprintf('Warning: GPU configuration on workers failed: %s\n', ME.message);
            end
        end
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
        
    catch ME
        fprintf('Could not start parallel pool: %s\n', ME.message);
        poolObj = [];
    end
end

function [data, metadata] = processSingleFile(fileInfo, rawMeanFolder, useReadMatrix, hasGPU, gpuInfo)
    % UPDATED: Process a single file with minimal output
    
    fullFilePath = fullfile(fileInfo.folder, fileInfo.name);
    
    % Load configuration first
    cfg = GluSnFRConfig();
    
    % Create individual module instances (avoid loading full module system)
    io = io_manager();
    calc = df_calculator();
    filter = roi_filter();
    utils = string_utils(cfg);
    
    % Read file (suppress detailed output)
    [rawData, headers, readSuccess] = io.readExcelFile(fullFilePath, useReadMatrix);
    
    if ~readSuccess || isempty(rawData)
        error('Failed to read file: %s', fileInfo.name);
    end
    
    % Extract valid headers and data (suppress detailed output)
    [validHeaders, validColumns] = io.extractValidHeaders(headers);
    
    if isempty(validHeaders)
        error('No valid ROI headers found in %s', fileInfo.name);
    end
    
    % Extract valid data columns
    numericData = single(rawData(:, validColumns));
    
    % Create time data
    timeData_ms = single((0:(size(numericData, 1)-1))' * cfg.timing.MS_PER_FRAME);
    
    % Calculate dF/F (suppress detailed output)
    [dF_values, thresholds, gpuUsed] = calc.calculate(numericData, hasGPU, gpuInfo);
    
    % Extract experiment info
    [trialNum, expType, ppiValue, coverslipCell] = utils.extractTrialOrPPI(fileInfo.name);
    
    % Apply filtering (suppress detailed output)
    if strcmp(expType, 'PPF') && isfinite(ppiValue)
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, 'PPF', ppiValue);
    else
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
    end
    
    % Prepare output structures
    data = struct();
    data.timeData_ms = timeData_ms;
    data.dF_values = finalDFValues;
    data.roiNames = finalHeaders;
    data.thresholds = finalThresholds;
    data.stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    data.gpuUsed = gpuUsed;
    data.filterStats = filterStats;
    
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
    
    % CONCISE OUTPUT: Single line summary per file
    if strcmp(expType, 'PPF')
        % No output during individual file processing - will be summarized at group level
    else
        % No output during individual file processing - will be summarized at group level
    end
end

function [groupResults, groupTimes] = processAllGroups(groupedFiles, groupKeys, rawMeanFolder, ...
                                                      outputFolders, hasParallelToolbox, hasGPU, gpuInfo, modules)
    % Process all groups with group-level parallelization (not plot-level)
    
    numGroups = length(groupKeys);
    groupResults = cell(numGroups, 1);
    groupTimes = zeros(numGroups, 1);
    
    % Determine if group-level parallel processing is beneficial
    useParallel = shouldUseGroupParallel(numGroups, hasParallelToolbox);
    
    if useParallel
        fprintf('Processing %d groups in parallel\n', numGroups);
        
        % Pass modules as constant to avoid reloading in parfor
        modulesConstant = parallel.pool.Constant(modules);
        
        parfor groupIdx = 1:numGroups
            [groupResults{groupIdx}, groupTimes(groupIdx)] = processGroup(...
                groupIdx, groupKeys{groupIdx}, groupedFiles{groupIdx}, ...
                rawMeanFolder, outputFolders, hasGPU, gpuInfo, modulesConstant.Value);
        end
        
    else
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
    fprintf('Group processing complete: %.2fs total, %.2fs/group\n', totalTime, avgTime);
end

function useParallel = shouldUseGroupParallel(numGroups, hasParallelToolbox)
    % Decide if group-level parallel processing is beneficial
    
    numCores = feature('numcores');
    hasEnoughGroups = numGroups >= 3;  % Need at least 3 groups
    hasEnoughCores = numCores >= 4;    % Need at least 4 cores
    
    useParallel = hasParallelToolbox && hasEnoughGroups && hasEnoughCores;
    
    if useParallel
        fprintf('  → Group-level parallel: %d groups, %d cores\n', numGroups, numCores);
    else
        if ~hasParallelToolbox
            fprintf('  → Sequential: No parallel toolbox\n');
        elseif ~hasEnoughGroups
            fprintf('  → Sequential: Only %d groups\n', numGroups);
        else
            fprintf('  → Sequential: Only %d cores\n', numCores);
        end
    end
end

function [result, processingTime] = processGroup(groupIdx, groupKey, filesInGroup, ...
                                               rawMeanFolder, outputFolders, hasGPU, gpuInfo, modules)
    % UPDATED: Process a single group with cleaner output
    
    groupTimer = tic;
    result = struct('status', 'processing', 'groupKey', groupKey, 'numFiles', length(filesInGroup));
    
    fprintf('Processing Group %d: %s\n', groupIdx, groupKey);
    
    try
        % Process group files (suppress individual file details)
        [groupData, groupMetadata] = processGroupFiles(filesInGroup, rawMeanFolder, modules, hasGPU, gpuInfo);
        
        if isempty(groupData)
            result.status = 'warning';
            result.message = 'No valid data found in group';
            processingTime = toc(groupTimer);
            fprintf('  ⚠️  No valid data found\n');
            return;
        end
        
        % Organize data (suppress detailed output)
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
        
        % Save results (suppress detailed Excel output)
        modules.io.writeExperimentResults(organizedData, averagedData, roiInfo, groupKey, outputFolders.main);
        
        % Generate plots (suppress detailed plotting output)
        plotFolders = struct();
        plotFolders.roi_trials = outputFolders.roi_trials;
        plotFolders.roi_averages = outputFolders.roi_averages;
        plotFolders.coverslip_averages = outputFolders.coverslip_averages;
        
        modules.plot.generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, plotFolders);
        
        result = prepareGroupResult(groupData, groupMetadata, roiInfo, 'success');
        result.groupKey = groupKey;
        
        % CONCISE SUMMARY: Single line per group with key metrics
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

function [groupData, groupMetadata] = processGroupFilesOptimized(filesInGroup, rawMeanFolder, modules, hasGPU, gpuInfo)
    % OPTIMIZED: Parallel file processing within groups
    % Expected speedup: 2-4x depending on file count and I/O speed
    
    numFiles = length(filesInGroup);
    groupData = cell(numFiles, 1);
    groupMetadata = cell(numFiles, 1);
    
    % Check if parallel processing is beneficial
    % Rule: Use parallel if >2 files and sufficient workers
    useParallel = numFiles > 2 && ~isempty(gcp('nocreate'));
    
    if useParallel
        fprintf('    Processing %d files in parallel\n', numFiles);
        
        % Pre-distribute common data to workers
        rawMeanFolderConstant = parallel.pool.Constant(rawMeanFolder);
        configConstant = parallel.pool.Constant(modules.config);
        
        % Parallel file processing
        parfor fileIdx = 1:numFiles
            try
                % Create minimal module instances on each worker
                io = io_manager();
                calc = df_calculator();
                filter = roi_filter();
                utils = string_utils(configConstant.Value);
                
                fullFilePath = fullfile(filesInGroup(fileIdx).folder, filesInGroup(fileIdx).name);
                
                % Use optimized reading method
                [rawData, headers, readSuccess] = readExcelFileOptimized(fullFilePath, io);
                
                if readSuccess && ~isempty(rawData)
                    % Process file data
                    [groupData{fileIdx}, groupMetadata{fileIdx}] = processFileData(...
                        rawData, headers, filesInGroup(fileIdx), calc, filter, utils, hasGPU, gpuInfo);
                end
                
            catch ME
                fprintf('    WARNING: Error in parallel processing file %s: %s\n', ...
                        filesInGroup(fileIdx).name, ME.message);
                groupData{fileIdx} = [];
                groupMetadata{fileIdx} = [];
            end
        end
        
    else
        % Sequential processing for small file counts
        fprintf('    Processing %d files sequentially\n', numFiles);
        for fileIdx = 1:numFiles
            try
                [groupData{fileIdx}, groupMetadata{fileIdx}] = processSingleFile(...
                    filesInGroup(fileIdx), rawMeanFolder, true, hasGPU, gpuInfo);
            catch ME
                fprintf('    WARNING: Error processing %s: %s\n', ...
                        filesInGroup(fileIdx).name, ME.message);
                groupData{fileIdx} = [];
                groupMetadata{fileIdx} = [];
            end
        end
    end
    
    % Remove empty entries
    validEntries = ~cellfun(@isempty, groupData);
    groupData = groupData(validEntries);
    groupMetadata = groupMetadata(validEntries);
end

function result = prepareGroupResult(groupData, groupMetadata, roiInfo, status)
    % Prepare group result summary with comprehensive information
    
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
    
    % Calculate total original ROIs (before filtering)
    totalOriginalROIs = 0;
    for i = 1:length(groupMetadata)
        if isfield(groupMetadata{i}, 'numOriginalROIs')
            totalOriginalROIs = totalOriginalROIs + groupMetadata{i}.numOriginalROIs;
        end
    end
    result.numOriginalROIs = totalOriginalROIs;
    
    % Check GPU usage across files
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

function [hasParallelToolbox, hasGPU, gpuInfo] = detectSystemCapabilities()
    % Detect system capabilities for optimal processing
    
    % Check for Parallel Computing Toolbox
    hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox');
    
    % Initialize GPU info
    hasGPU = false;
    gpuInfo = struct('name', 'None', 'memory', 0, 'deviceCount', 0, 'computeCapability', 0);
    
    % GPU detection
    if hasParallelToolbox
        try
            gpuDevice(); % Test GPU availability
            gpu = gpuDevice();
            hasGPU = true;
            gpuInfo.name = gpu.Name;
            gpuInfo.memory = gpu.AvailableMemory / 1e9; % Convert to GB
            gpuInfo.deviceCount = gpuDeviceCount();
            gpuInfo.computeCapability = gpu.ComputeCapability;
            
            fprintf('GPU detected: %s (%.1f GB available, Compute %.1f)\n', ...
                   gpuInfo.name, gpuInfo.memory, gpuInfo.computeCapability);
        catch
            fprintf('No compatible GPU found\n');
        end
    else
        fprintf('Parallel Computing Toolbox not available\n');
    end
end

function validateProcessingResults(groupResults)
    % FIXED: Validate that at least some groups were processed successfully
    
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

% Placeholder functions for missing functionality
function saveAllResults(varargin)
    warning('saveAllResults not yet implemented');
end

function generateAllPlots(varargin)
    warning('generateAllPlots not yet implemented');
end

function [groupData, groupMetadata] = processGroupFiles(filesInGroup, rawMeanFolder, modules, hasGPU, gpuInfo)
    % UPDATED: Process group files with minimal output
    
    numFiles = length(filesInGroup);
    groupData = cell(numFiles, 1);
    groupMetadata = cell(numFiles, 1);
    
    % Process each file in the group (suppress individual file output)
    for fileIdx = 1:numFiles
        try
            [groupData{fileIdx}, groupMetadata{fileIdx}] = processSingleFile(...
                filesInGroup(fileIdx), rawMeanFolder, true, hasGPU, gpuInfo);
        catch ME
            % Only show warning for failed files, not detailed error
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
