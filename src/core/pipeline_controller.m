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
    controller.processSingleFile = @processSingleFile;
    controller.processAllGroups = @processAllGroups;
    controller.saveAllResults = @saveAllResults;
    controller.generateAllPlots = @generateAllPlots;
    controller.detectSystemCapabilities = @detectSystemCapabilities; 
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
            if exist('rawMeanFolder', 'var') && exist('modules', 'var')
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

function [rawMeanFolder, outputFolders, excelFiles] = setupFileSystem(io)
    % Setup file system with proper versioning and return values
    % FIXED: Now properly returns all 3 outputs as expected
    
    % ==================== VERSION CONTROL ====================
    % CHANGE THIS NUMBER TO UPDATE ALL FOLDER NAMES
    VERSION = '50';  % <-- CHANGE THIS NUMBER HERE
    % ==========================================================
    
    % Default directory (can be customized)
    defaultDir = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\';
    
    % Select input folder
    rawMeanFolder = uigetdir(defaultDir, 'Select the "5_raw_mean" subfolder in GPU_Processed_Images');
    
    if isequal(rawMeanFolder, 0)
        error('No folder selected. Pipeline cancelled.');
    end
    
    % Create output folders with version variable
    processedImagesFolder = fileparts(rawMeanFolder);
    outputFolders = struct();
    outputFolders.main = fullfile(processedImagesFolder, sprintf('6_v%s_modular_dF_F', VERSION));
    outputFolders.individual = fullfile(processedImagesFolder, sprintf('6_v%s_modular_plots_trials', VERSION));
    outputFolders.averaged = fullfile(processedImagesFolder, sprintf('6_v%s_modular_plots_averaged', VERSION));
    
    % Create directories
    io.createDirectories({outputFolders.main, outputFolders.individual, outputFolders.averaged});
    
    % Get and validate Excel files  
    excelFiles = io.getExcelFiles(rawMeanFolder);
    
    if isempty(excelFiles)
        error('No valid Excel files found in: %s', rawMeanFolder);
    end
    
    fprintf('Using version: v%s\n', VERSION);
    fprintf('Input folder: %s\n', rawMeanFolder);
    fprintf('Output folder: %s\n', outputFolders.main);
    
    % FIXED: Function now properly returns all expected outputs
end

function [data, metadata] = processSingleFile(fileInfo, rawMeanFolder, useReadMatrix, hasGPU, gpuInfo)
    % Process a single file with modular components
    % FIXED: Load modules locally to avoid dependency issues
    
    fullFilePath = fullfile(fileInfo.folder, fileInfo.name);
    fprintf('    Processing: %s\n', fileInfo.name);
    
    % Load configuration first
    cfg = GluSnFRConfig();
    
    % Create individual module instances (avoid loading full module system)
    io = io_manager();
    calc = df_calculator();
    filter = roi_filter();
    utils = string_utils(cfg);  % Pass config to avoid circular dependency
    
    % Read file
    [rawData, headers, readSuccess] = io.readExcelFile(fullFilePath, useReadMatrix);
    
    if ~readSuccess || isempty(rawData)
        error('Failed to read file: %s', fileInfo.name);
    end
    
    % Extract valid headers and data
    [validHeaders, validColumns] = io.extractValidHeaders(headers);
    
    if isempty(validHeaders)
        error('No valid ROI headers found in %s', fileInfo.name);
    end
    
    % Extract valid data columns
    numericData = single(rawData(:, validColumns));
    
    % Create time data
    timeData_ms = single((0:(size(numericData, 1)-1))' * cfg.timing.MS_PER_FRAME);
    
    % Calculate dF/F
    [dF_values, thresholds, gpuUsed] = calc.calculate(numericData, hasGPU, gpuInfo);
    
    % Extract experiment info
    [trialNum, expType, ppiValue, coverslipCell] = utils.extractTrialOrPPI(fileInfo.name);
    
    % Apply filtering
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
    
    % Log results
    if strcmp(expType, 'PPF')
        fprintf('      Final result: %d ROIs for %s PPI=%dms trial=%g (%.1f%% passed filter)\n', ...
                metadata.numROIs, expType, ppiValue, trialNum, metadata.filterRate*100);
    else
        fprintf('      Final result: %d ROIs for %s trial=%g (%.1f%% passed filter)\n', ...
                metadata.numROIs, expType, trialNum, metadata.filterRate*100);
    end
end

function [groupResults, groupTimes] = processAllGroups(groupedFiles, groupKeys, rawMeanFolder, ...
                                                      outputFolders, hasParallelToolbox, hasGPU, gpuInfo, modules)
    % Process all groups with optimal parallelization
    
    numGroups = length(groupKeys);
    groupResults = cell(numGroups, 1);
    groupTimes = zeros(numGroups, 1);
    
    % Determine processing strategy
    useParallel = hasParallelToolbox && numGroups > 1;
    
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
end

function [result, processingTime] = processGroup(groupIdx, groupKey, filesInGroup, ...
                                               rawMeanFolder, outputFolders, hasGPU, gpuInfo, modules)
    % Process a single group
    
    groupTimer = tic;
    result = struct('status', 'processing', 'groupKey', groupKey, 'numFiles', length(filesInGroup));
    
    fprintf('Processing Group %d: %s (%d files)\n', groupIdx, groupKey, length(filesInGroup));
    
    try
        % Process group files
        [groupData, groupMetadata] = processGroupFiles(filesInGroup, rawMeanFolder, modules, hasGPU, gpuInfo);
        
        if isempty(groupData)
            result.status = 'warning';
            result.message = 'No valid data found in group';
            processingTime = toc(groupTimer);
            return;
        end
        
        % Organize data
        [organizedData, averagedData, roiInfo] = modules.organize.organizeGroupData(groupData, groupMetadata, groupKey);
        
        % Save results using consolidated io manager
        modules.io.writeExperimentResults(organizedData, averagedData, roiInfo, groupKey, outputFolders.main);
        
        % Generate plots
        modules.plot.generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, ...
                                       outputFolders.individual, outputFolders.averaged);
        
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

function [groupData, groupMetadata] = processGroupFiles(filesInGroup, rawMeanFolder, modules, hasGPU, gpuInfo)
    % Process all files in a group with proper module usage
    
    numFiles = length(filesInGroup);
    groupData = cell(numFiles, 1);
    groupMetadata = cell(numFiles, 1);
    
    validCount = 0;
    useReadMatrix = ~verLessThan('matlab', '9.6');
    
    for fileIdx = 1:numFiles
        try
            [data, metadata] = processSingleFile(...
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

% Placeholder functions for missing functionality
function saveAllResults(varargin)
    warning('saveAllResults not yet implemented');
end

function generateAllPlots(varargin)
    warning('generateAllPlots not yet implemented');
end