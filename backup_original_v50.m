%%  dF/F Analysis Script for Glutamate Imaging - Fixed PPF Version v4.1
%   Split script into key helper functions
%       Plotting
%       group keys
%       Threshold function
%   Add complete average per genotype & condition


%% INTEGRATION WITH NEW MODULAR FUNCTIONS
% Add all project modules to path
projectRoot = fileparts(mfilename('fullpath'));
addpath(genpath(projectRoot));

% Load configuration and modules
cfg = GluSnFRConfig();
utils = string_utils();
calc = df_calculator();
filter = roi_filter();
memMgr = memory_manager();

fprintf('Loaded modular functions (v%s)\n', cfg.version);

%% Initialize and validate system capabilities with  configuration
scriptName = 's6_SnFR_mean_dF_filter_group_plot_v50.m';
fprintf('=== OPTIMIZED dF/F GROUPED ANALYSIS v50 (1AP and PPF!) ===\n');
fprintf('Script: %s\n', scriptName);
fprintf('Data Type: Evoked glutamate release with iGlu3Fast\n');
fprintf('Sampling: 200Hz (5ms per frame)\n');

% Initialize  logging
logBuffer = {};
logBuffer{end+1} = sprintf('=== OPTIMIZED dF/F GROUPED ANALYSIS v50 (1AP and PPF!) ===\n');
logBuffer{end+1} = sprintf('Script: %s', scriptName);
logBuffer{end+1} = sprintf('Data Type: Evoked glutamate release with iGlu3Fast\n');
logBuffer{end+1} = sprintf('Sampling: 200Hz (5ms per frame)');
logBuffer{end+1} = sprintf('Processing Date: %s', char(datetime('now')));


% Check MATLAB version and capabilities
matlab_version = version('-release');
fprintf('MATLAB Version: %s\n', matlab_version);
logBuffer{end+1} = sprintf('MATLAB Version: %s', matlab_version);

if verLessThan('matlab', '9.6') % R2019a
    warning('This script is optimized for MATLAB R2019a or later. Some features may not work properly.');
    useReadMatrix = false;
else
    useReadMatrix = true;
end

%  system detection
[hasParallelToolbox, hasGPU, gpuInfo] = detectSystemCapabilities();

% Display system information
fprintf('System Capabilities:\n');
if hasParallelToolbox
    fprintf('  CPU Parallel Processing: Available\n');
else
    fprintf('  CPU Parallel Processing: Not Available\n');
end

if hasGPU
    fprintf('  GPU Acceleration: Available (%s, %.1fGB)\n', gpuInfo.name, gpuInfo.memory);
else
    fprintf('  GPU Acceleration: Not Available\n');
end

logBuffer{end+1} = 'System Capabilities:';
if hasParallelToolbox
    logBuffer{end+1} = '  CPU Parallel Processing: Available';
else
    logBuffer{end+1} = '  CPU Parallel Processing: Not Available';
end

if hasGPU
    logBuffer{end+1} = sprintf('  GPU Acceleration: Available (%s, %.1fGB)', gpuInfo.name, gpuInfo.memory);
else
    logBuffer{end+1} = '  GPU Acceleration: Not Available';
end

%%  parallel pool configuration
if hasParallelToolbox
    [optimalPoolSize, poolObj] = setupParallelPool(hasParallelToolbox, hasGPU, gpuInfo);
    
    % Configure GPU on each worker using SPMD
    if hasGPU && ~isempty(poolObj)
        try
            spmd
                if gpuDeviceCount > 0
                    gpuDevice(1); % Use first GPU
                end
            end
            fprintf('GPU configuration completed on all workers\n');
            logBuffer{end+1} = 'GPU configuration completed on all workers';
        catch ME
            fprintf('Warning: GPU configuration on workers failed: %s\n', ME.message);
            logBuffer{end+1} = sprintf('Warning: GPU configuration on workers failed: %s', ME.message);
        end
    end
end

%% File selection and setup with validation
defaultTargetDirectory = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\';

% Select the "raw mean" folder
rawMeanFolder = uigetdir(defaultTargetDirectory, 'Select the "5_raw_mean" subfolder in GPU_Processed_Images');

if isequal(rawMeanFolder, 0)
    disp('No folder selected. Exiting...');
    return;
end

% Create output folders (xlsx files in main folder, plots in subfolders)
processedImagesFolder = fileparts(rawMeanFolder);
dF_grouped_folder = fullfile(processedImagesFolder, '6_v50_dF_F');
plotsIndividualFolder = fullfile(processedImagesFolder, '6_v50_dF_plots_trials');
plotsAveragedFolder = fullfile(processedImagesFolder, '6_v50_dF_plots_averaged');
createDirectoriesIfNeeded({dF_grouped_folder, plotsIndividualFolder, plotsAveragedFolder});

% Get all Excel files with validation
excelFiles = dir(fullfile(rawMeanFolder, '*.xlsx'));

if isempty(excelFiles)
    error('No Excel files found in the selected folder: %s', rawMeanFolder);
end

fprintf('\nFound %d Excel files to process\n', length(excelFiles));
fprintf('Input folder: %s\n', rawMeanFolder);
fprintf('Output folder: %s\n', dF_grouped_folder);

logBuffer{end+1} = '';
logBuffer{end+1} = sprintf('Found %d Excel files to process', length(excelFiles));
logBuffer{end+1} = sprintf('Input folder: %s', rawMeanFolder);
logBuffer{end+1} = sprintf('Output folder: %s', dF_grouped_folder);

%% Initialize  logging and timing
logFileName = fullfile(processedImagesFolder, '6_grouped_processing_log_v50.txt');
globalTimer = tic;

%% Step 1: File organization with  validation
fprintf('\n--- STEP 1: Organizing files by groups ---\n');
logBuffer{end+1} = '';
logBuffer{end+1} = '--- STEP 1: Organizing files by groups ---';

step1Timer = tic;

try
    [groupedFiles, groupKeys] = organizeFilesByGroup(excelFiles, rawMeanFolder);
    step1Time = toc(step1Timer);
    
    fprintf('Successfully organized %d files into %d groups in %.3f seconds\n', ...
           length(excelFiles), length(groupKeys), step1Time);
    logBuffer{end+1} = sprintf('Successfully organized %d files into %d groups in %.3f seconds', ...
                              length(excelFiles), length(groupKeys), step1Time);
    
    for i = 1:length(groupKeys)
        msg = sprintf('  Group %d: %s (%d files)', i, groupKeys{i}, length(groupedFiles{i}));
        fprintf('%s\n', msg);
        logBuffer{end+1} = msg;
    end
    
catch ME
    fprintf('ERROR in file organization: %s\n', ME.message);
    logBuffer{end+1} = sprintf('ERROR in file organization: %s', ME.message);
    return;
end

%% Step 2:  group processing with  optimizations
fprintf('\n--- STEP 2: Processing groups with optimizations ---\n');
logBuffer{end+1} = '';
logBuffer{end+1} = '--- STEP 2: Processing groups with optimizations ---';

step2Timer = tic;

% Preallocate with optimal data types
numGroups = length(groupKeys);
groupProcessingTimes = zeros(numGroups, 1, 'single');
groupResults = cell(numGroups, 1);

%  processing with  parallel optimization
if hasParallelToolbox && optimalPoolSize > 1 && numGroups > 1
    fprintf('Using parallel processing with %d workers\n', optimalPoolSize);
    logBuffer{end+1} = sprintf('Using parallel processing with %d workers', optimalPoolSize);
    
    % Use parallel.pool.Constant for efficient data sharing
    filesConstant = parallel.pool.Constant({groupedFiles, groupKeys});
    
    parfor groupIdx = 1:numGroups
        [groupResults{groupIdx}, groupProcessingTimes(groupIdx)] = ...
            processGroup(groupIdx, filesConstant.Value{2}{groupIdx}, ...
                               filesConstant.Value{1}{groupIdx}, rawMeanFolder, useReadMatrix, ...
                               dF_grouped_folder, plotsIndividualFolder, plotsAveragedFolder, hasGPU, gpuInfo);
    end
else
    fprintf('Using sequential processing with optimizations\n');
    logBuffer{end+1} = 'Using sequential processing with optimizations';
    
    for groupIdx = 1:numGroups
        [groupResults{groupIdx}, groupProcessingTimes(groupIdx)] = ...
            processGroup(groupIdx, groupKeys{groupIdx}, groupedFiles{groupIdx}, ...
                               rawMeanFolder, useReadMatrix, dF_grouped_folder, ...
                               plotsIndividualFolder, plotsAveragedFolder, hasGPU, gpuInfo);
    end
end

step2Time = toc(step2Timer);

%% Step 3: Comprehensive analysis
fprintf('\n--- STEP 3: Generating comprehensive summary ---\n');
logBuffer{end+1} = '';
logBuffer{end+1} = '--- STEP 3: Generating comprehensive summary ---';

step3Timer = tic;

[successCount, warningCount, errorCount] = analyzeProcessingResults(groupResults);
totalTime = toc(globalTimer);

% Display results
fprintf('\n=== PROCESSING COMPLETE ===\n');
fprintf('Total groups: %d\n', numGroups);
fprintf('Successfully processed: %d\n', successCount);
fprintf('Warnings: %d\n', warningCount);
fprintf('Errors: %d\n', errorCount);
fprintf('Total processing time: %.2f seconds\n', totalTime);

step3Time = toc(step3Timer);

%  logging
logBuffer{end+1} = '';
logBuffer{end+1} = '=== PROCESSING COMPLETE ===';
logBuffer{end+1} = sprintf('Total groups: %d', numGroups);
logBuffer{end+1} = sprintf('Successfully processed: %d', successCount);
logBuffer{end+1} = sprintf('Warnings: %d', warningCount);
logBuffer{end+1} = sprintf('Errors: %d', errorCount);
logBuffer{end+1} = sprintf('Total processing time: %.2f seconds', totalTime);

% Save comprehensive log
saveLogWithBuffer(logFileName, logBuffer);

fprintf('\nTiming Breakdown:\n');
fprintf('  File organization: %.3f seconds\n', step1Time);
fprintf('  Group processing: %.3f seconds\n', step2Time);
fprintf('  Analysis & reporting: %.3f seconds\n', step3Time);
fprintf('\nProcessing log saved to: %s\n', logFileName);

%% ALL SUPPORTING FUNCTIONS BELOW THIS LINE

function [hasParallelToolbox, hasGPU, gpuInfo] = detectSystemCapabilities()
    %  system capability detection
    
    hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox');
    hasGPU = false;
    gpuInfo = struct('name', 'None', 'memory', 0, 'deviceCount', 0, 'computeCapability', 0);
    
    if hasParallelToolbox
        try
            gpuDevice; % Test GPU availability
            gpu = gpuDevice();
            hasGPU = true;
            gpuInfo.name = gpu.Name;
            gpuInfo.memory = gpu.AvailableMemory / 1e9; % GB
            gpuInfo.deviceCount = gpuDeviceCount();
            gpuInfo.computeCapability = gpu.ComputeCapability;
            
            fprintf('GPU detected: %s (%.1f GB available, Compute %.1f)\n', ...
                   gpuInfo.name, gpuInfo.memory, gpuInfo.computeCapability);
        catch
            fprintf('No compatible GPU found\n');
        end
    end
end

function [poolSize, poolObj] = setupParallelPool(hasParallelToolbox, hasGPU, gpuInfo)
    % Renamed from setupParallelPool
    % (Function content remains the same - just renamed)
    
    poolSize = 1;
    poolObj = [];
    
    if ~hasParallelToolbox
        fprintf('No Parallel Computing Toolbox - using sequential processing\n');
        return;
    end
    
    % Check existing pool
    poolObj = gcp('nocreate');
    if ~isempty(poolObj)
        poolSize = poolObj.NumWorkers;
        fprintf('Using existing parallel pool with %d workers\n', poolSize);
        return;
    end
    
    % Configuration
    workers = min(6, feature('numcores') - 1);
    
    try
        poolObj = parpool('Processes', workers);
        poolObj.IdleTimeout = 60;
        poolSize = poolObj.NumWorkers;
        
        fprintf('Started parallel pool with %d workers\n', poolSize);
    catch ME
        fprintf('WARNING: Could not start parallel pool: %s\n', ME.message);
        poolSize = 1;
    end
end

function [groupedFiles, groupKeys] = organizeFilesByGroup(excelFiles, rawMeanFolder)
    % Organize files by group with simplified return
    
    groupMap = containers.Map();
    
    % Process files efficiently
    numFiles = length(excelFiles);
    successCount = 0;
    
    for i = 1:numFiles
        try
            filename = excelFiles(i).name;
            groupKey = utils.extractGroupKey(filename);
            
            if ~isempty(groupKey)
                if isKey(groupMap, groupKey)
                    groupMap(groupKey) = [groupMap(groupKey), i];
                else
                    groupMap(groupKey) = i;
                end
                successCount = successCount + 1;
            else
                fprintf('WARNING: Could not extract group key from %s\n', filename);
            end
            
        catch ME
            fprintf('ERROR processing filename %s: %s\n', filename, ME.message);
        end
    end
    
    % Build output structures
    groupKeys = keys(groupMap);
    numGroups = length(groupKeys);
    groupedFiles = cell(numGroups, 1);
    
    for i = 1:numGroups
        indices = groupMap(groupKeys{i});
        groupedFiles{i} = excelFiles(indices);
    end
    
    fprintf('Successfully organized %d/%d files into %d groups\n', successCount, numFiles, numGroups);
end

function groupKey = extractGroupKey(filename)
    % Simplified group key extraction
    
    groupKey = '';
    
    try
        % Remove extension efficiently
        [~, name, ~] = fileparts(filename);
        
        % Enhanced pattern matching
        if ~contains(name, 'CP_')
            return;
        end
        
        % Check if this is a PPF file
        if contains(name, 'PPF')
            % For PPF: Group by timepoint instead of coverslip
            ppfPattern = 'PPF-(\d+)ms';
            ppfMatch = regexp(name, ppfPattern, 'tokens');
            
            if ~isempty(ppfMatch)
                timepoint = ppfMatch{1}{1};
                
                % Extract base group info
                basePattern = '_Doc2b-[A-Z0-9]+';
                baseMatch = regexp(name, basePattern, 'match');
                
                if ~isempty(baseMatch)
                    baseKey = baseMatch{1};
                    groupKey = sprintf('PPF_%sms%s', timepoint, baseKey);
                end
            end
        else
            % Original 1AP logic
            patterns = {
                '_Doc2b-[A-Z0-9]+',  ... Doc2b pattern
                '_Cs\d+-c\d+',       ... Coverslip pattern  
                '_(1AP|PPF)'         ... Experiment type
            };
            
            matches = cell(length(patterns), 1);
            for i = 1:length(patterns)
                matches{i} = regexp(name, patterns{i}, 'match');
                if isempty(matches{i})
                    return; % Early exit if any pattern fails
                end
            end
            
            % Build robust group key
            cpIndex = strfind(name, 'CP_');
            csEnd = strfind(name, matches{2}{1}) + length(matches{2}{1}) - 1;
            baseKey = name(cpIndex:csEnd);
            expType = matches{3}{1}(2:end); % Remove underscore
            
            % Optimize group key generation
            if strcmp(expType, '1AP')
                groupKey = [baseKey '_1AP'];
            end
        end
        
    catch ME
        fprintf('WARNING: Error extracting group key from %s: %s\n', filename, ME.message);
    end
end


function [result, processingTime] = processGroup(groupIdx, groupKey, filesInGroup, ...
                                                       rawMeanFolder, useReadMatrix, ...
                                                       dF_grouped_folder, plotsIndividualFolder, plotsAveragedFolder, ...
                                                       hasGPU, gpuInfo)
    %  version that collects metadata for Script 1
    
    groupTimer = tic;
    result = struct('status', 'processing', 'groupKey', groupKey, 'numFiles', length(filesInGroup));
    
    fprintf('Processing Group %d: %s (%d files)\n', groupIdx, groupKey, length(filesInGroup));
    
    try
        %  file processing
        [groupData, groupMetadata] = processGroupFiles(filesInGroup, rawMeanFolder, ...
                                                             useReadMatrix, hasGPU, gpuInfo);
        
        if isempty(groupData)
            result.status = 'warning';
            result.message = 'No valid data found in group';
            processingTime = toc(groupTimer);
            return;
        end
        
        % Data organization
        [organizedData, averagedData, roiInfo] = organizeGroupData(groupData, groupMetadata, groupKey);
        
        % Save results with metadata (metadata now generated from actual organized data)
        saveGroupResults(organizedData, averagedData, roiInfo, groupKey, ...
                        dF_grouped_folder, plotsIndividualFolder, plotsAveragedFolder);        
                result = prepareGroupResult(groupData, groupMetadata, roiInfo, 'success');
        
    catch ME
        fprintf('  ERROR processing group %s: %s\n', groupKey, ME.message);
        result.status = 'error';
        result.message = ME.message;
        result.stackTrace = ME.stack;
    end
    
    processingTime = toc(groupTimer);
    fprintf('  Group %s completed in %.3f seconds [%s]\n', groupKey, processingTime, result.status);
end



function saveGroupResults(organizedData, averagedData, roiInfo, groupKey, ...
                                 dF_grouped_folder, plotsIndividualFolder, plotsAveragedFolder)
    %  saving with metadata - FIXED to generate metadata from actual data
    
    try
        % Save Excel with metadata - NOW GENERATES metadata from organizedData
        saveGroupedExcel(organizedData, averagedData, roiInfo, groupKey, dF_grouped_folder);
        
        % Generate plots (unchanged)
        generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, plotsIndividualFolder, plotsAveragedFolder);
        
    catch ME
        fprintf('    ERROR saving results for %s: %s\n', groupKey, ME.message);
        rethrow(ME);
    end
end

function [groupData, groupMetadata] = processGroupFiles(filesInGroup, rawMeanFolder, ...
                                                              useReadMatrix, hasGPU, gpuInfo)
    %  file processing with optimizations
    
    numFiles = length(filesInGroup);
    groupData = cell(numFiles, 1);
    groupMetadata = cell(numFiles, 1);
    
    % Process files with  error handling
    validCount = 0;
    
    for fileIdx = 1:numFiles
        try
            [data, metadata] = processSingleFile(filesInGroup(fileIdx), rawMeanFolder, ...
                                                        useReadMatrix, hasGPU, gpuInfo);
            if ~isempty(data)
                validCount = validCount + 1;
                groupData{validCount} = data;
                groupMetadata{validCount} = metadata;
            end
            
        catch ME
            fprintf('    WARNING: Error processing %s: %s\n', filesInGroup(fileIdx).name, ME.message);
        end
    end
    
    % Trim arrays to actual size
    groupData = groupData(1:validCount);
    groupMetadata = groupMetadata(1:validCount);
    
    if validCount < numFiles
        fprintf('    WARNING: %d/%d files failed processing\n', numFiles - validCount, numFiles);
    end
end

function [data, metadata] = processSingleFile(fileInfo, rawMeanFolder, useReadMatrix, hasGPU, gpuInfo)
    %  single file processing with optimizations
    
    fullFilePath = fullfile(fileInfo.folder, fileInfo.name);
    
    fprintf('    Processing: %s\n', fileInfo.name);
    
    %  data import with multiple fallback methods
    try
        if useReadMatrix
            try
                % Method 1: readcell with optimization
                raw = readcell(fullFilePath, 'NumHeaderLines', 0);
                if isempty(raw) || size(raw, 1) < 3
                    error('Insufficient data rows');
                end
            catch
                % Method 2: readtable fallback
                try
                    tempTable = readtable(fullFilePath, 'ReadVariableNames', false);
                    raw = table2cell(tempTable);
                catch
                    % Method 3: xlsread as last resort
                    fprintf('      Using xlsread fallback for %s\n', fileInfo.name);
                    [~, ~, raw] = xlsread(fullFilePath); %#ok<XLSRD>
                end
            end
        else
            [~, ~, raw] = xlsread(fullFilePath); %#ok<XLSRD>
        end
        
    catch ME
        error('Failed to read file %s: %s', fileInfo.name, ME.message);
    end
    
    %  data validation
    if isempty(raw) || size(raw, 1) < 3
        error('File %s has insufficient data (need at least 3 rows)', fileInfo.name);
    end
    
    %  header and data extraction
    headers = raw(2, :);
    dataRows = raw(3:end, :);
    
    % Optimized numeric conversion with single precision
    numericData = convertToNumeric(dataRows);
    
    %  header validation
    [validHeaders, validColumns] = extractValidHeaders(headers);
    
    if isempty(validHeaders)
        error('No valid ROI headers found in %s', fileInfo.name);
    end
    
    % Keep only valid columns and convert to single precision
    numericData = single(numericData(:, validColumns));
    
    
    % Add Frame column
    timeData_ms = single((0:(size(numericData, 1)-1))' * 5); % Convert to time (ms): 5ms per frame
    
    % OPTIMIZED dF/F calculations with INDIVIDUAL thresholds 
    [dF_values, thresholds, gpuUsed] = calc.calculate(numericData, hasGPU, gpuInfo);
    
    % APPLY FILTERING - keep only ROIs that pass individual thresholds
    % Determine if this is PPF data and use appropriate filtering
    isPPF = contains(fileInfo.name, 'PPF');
    
    if isPPF
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, 'PPF', timepoint_ms);
    else
        [finalDFValues, finalHeaders, finalThresholds, filterStats] = ...
            filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
    end
    fprintf('    %s\n', filterStats.summary);
    
    % Prepare output structures with single precision
    data = struct();
    data.timeData_ms = timeData_ms;
    data.dF_values = finalDFValues;
    data.roiNames = finalHeaders;
    data.thresholds = finalThresholds;
    data.stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS; % 267 frames × 5ms = 1335ms
    data.gpuUsed = gpuUsed;
    
    metadata = struct();
    metadata.filename = fileInfo.name;
    metadata.numFrames = size(numericData, 1);
    metadata.numROIs = length(finalHeaders);
    metadata.gpuUsed = gpuUsed;
    metadata.dataType = 'single';
    
    %  trial/PPI extraction - MODIFIED FOR PPF
    [metadata.trialNumber, metadata.experimentType, metadata.ppiValue, metadata.coverslipCell] = ...
        extractTrialOrPPI(fileInfo.name);
    
    if strcmp(metadata.experimentType, 'PPF')
        fprintf('      Final result: %d ROIs for %s PPI=%dms trial=%g\n', metadata.numROIs, metadata.experimentType, metadata.ppiValue, metadata.trialNumber);
    else
        fprintf('      Final result: %d ROIs for %s trial=%g\n', metadata.numROIs, metadata.experimentType, metadata.trialNumber);
    end
end

function numericData = convertToNumeric(dataRows)
    % Optimized cell array to numeric conversion with single precision
    
    [numRows, numCols] = size(dataRows);
    numericData = NaN(numRows, numCols, 'single');
    conversionIssues = 0;
    
    % Vectorized conversion with optimized loops
    for col = 1:numCols
        try
            colData = dataRows(:, col);
            
            % Fast path for already numeric columns
            if all(cellfun(@isnumeric, colData(~cellfun(@isempty, colData))))
                validRows = ~cellfun(@isempty, colData);
                if any(validRows)
                    numericData(validRows, col) = single(cell2mat(colData(validRows)));
                end
            else
                % Mixed type column - optimized element by element conversion
                for row = 1:numRows
                    cellValue = colData{row};
                    
                    if isnumeric(cellValue) && isscalar(cellValue) && isfinite(cellValue)
                        numericData(row, col) = single(cellValue);
                    elseif ischar(cellValue) || isstring(cellValue)
                        numValue = str2double(cellValue);
                        if isfinite(numValue)
                            numericData(row, col) = single(numValue);
                        end
                    end
                end
            end
            
        catch ME
            conversionIssues = conversionIssues + 1;
            if conversionIssues <= 3
                fprintf('    WARNING: Column %d conversion issue: %s\n', col, ME.message);
            end
        end
    end
    
    if conversionIssues > 3
        fprintf('    WARNING: %d additional conversion issues encountered\n', conversionIssues - 3);
    end
end

function [validHeaders, validColumns] = extractValidHeaders(headers)
    %  header extraction with comprehensive validation
    
    numHeaders = length(headers);
    validHeaders = cell(numHeaders, 1);
    validColumns = zeros(numHeaders, 1);
    validCount = 0;
    
    for i = 1:numHeaders
        header = headers{i};
        if ~isempty(header) && (ischar(header) || isstring(header))
            cleanHeader = strtrim(char(header));
            if ~isempty(cleanHeader)
                validCount = validCount + 1;
                validHeaders{validCount} = cleanHeader;
                validColumns(validCount) = i;
            end
        end
    end
    
    % Trim to actual size
    validHeaders = validHeaders(1:validCount);
    validColumns = validColumns(1:validCount);
    
    fprintf('      Extracted %d valid headers from %d total columns\n', validCount, numHeaders);
end

function [dF_values, thresholds, gpuUsed] = calculate_dF_F(traces, hasGPU, gpuInfo)
    % Renamed from calculate_dF_F
    % (Function content remains the same - just renamed)
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    [n_frames, n_rois] = size(traces);
    gpuUsed = false;
    
    % Pre-allocate output arrays
    dF_values = zeros(n_frames, n_rois, 'single');
    F0 = zeros(1, n_rois, 'single');
    thresholds = zeros(1, n_rois, 'single');
    
    dataSize = numel(traces);
    memoryRequired = dataSize * 4; % Single precision
    useGPU = hasGPU && dataSize > 50000 && memoryRequired < (gpuInfo.memory * 0.8 * 1e9);
    
    if useGPU
        try
            % Transfer to GPU with single precision
            gpuData = gpuArray(traces);
            
            % Vectorized baseline calculation on GPU
            baseline_data = gpuData(baseline_window, :);
            F0 = mean(baseline_data, 1, 'omitnan');
            
            % Protect against zero/negative baselines
            F0(F0 <= 0) = single(1e-6);
            
            % Vectorized %dF/F calculation on GPU
            F0_matrix = repmat(F0, n_frames, 1);
            dF_values = (gpuData - F0_matrix) ./ F0_matrix;
            
            % Handle potential division by zero/infinity
            dF_values(isinf(dF_values) | isnan(dF_values)) = 0;
            
            % Calculate individual thresholds per ROI (3×SD of baseline %dF/F)
            baseline_dF_F = dF_values(baseline_window, :);
            thresholds = 3 * std(baseline_dF_F, 1, 'omitnan');
            thresholds(isnan(thresholds)) = 0;
            
            % Transfer results back to CPU
            dF_values = gather(dF_values);
            thresholds = gather(thresholds);
            
            gpuUsed = true;
            
        catch ME
            fprintf('    GPU calculation failed (%s), using CPU\n', ME.message);
            useGPU = false;
        end
    end
    
    if ~useGPU
        % CPU calculation
        baseline_data = traces(baseline_window, :);
        F0 = mean(baseline_data, 1, 'omitnan');
        F0(F0 <= 0) = single(1e-6);
        
        % Vectorized operations
        F0_matrix = repmat(F0, n_frames, 1);
        dF_values = (traces - F0_matrix) ./ F0_matrix;
        
        % Handle potential division by zero/infinity
        dF_values(isinf(dF_values) | isnan(dF_values)) = 0;
        
        % Calculate individual thresholds per ROI (3×SD of baseline %dF/F)
        baseline_dF_F = dF_values(baseline_window, :);
        thresholds = 3 * std(baseline_dF_F, 1, 'omitnan');
        thresholds(isnan(thresholds)) = 0;
    end
end

function [organizedData, averagedData, roiInfo] = organizeGroupData(groupData, groupMetadata, groupKey)
    % Updated data organization with noise level tracking
    
    % Determine experiment type by checking group key first
    isPPF = contains(groupKey, 'PPF_');
    
    if isPPF
        fprintf('    DETECTED PPF EXPERIMENT - Using PPF-specific organization\n');
        [organizedData, averagedData, roiInfo] = organizeGroupDataPPFOnly(groupData, groupMetadata, groupKey);
    else
        fprintf('    DETECTED 1AP EXPERIMENT - Using 1AP-specific organization with noise tracking\n');
        [organizedData, averagedData, roiInfo] = organizeGroupData1AP(groupData, groupMetadata);
    end
end


function [organizedData, averagedData, roiInfo] = organizeGroupDataPPFOnly(groupData, groupMetadata, groupKey)
    % PPF-ONLY data organization with FIXED preallocation
    
    fprintf('    Starting PPF-only organization\n');
    
    % Extract timepoint from group key
    timepoint = NaN;
    timepointMatch = regexp(groupKey, 'PPF_(\d+)ms', 'tokens');
    if ~isempty(timepointMatch)
        timepoint = str2double(timepointMatch{1}{1});
    end
    
    if isnan(timepoint)
        error('Could not extract timepoint from PPF group key: %s', groupKey);
    end
    
    fprintf('    PPF timepoint: %d ms\n', timepoint);
    
    % FIXED: Preallocate coverslip files BEFORE the loop
    maxFiles = length(groupData);
    coverslipFiles = repmat(struct('coverslipCell', '', 'roiNumbers', [], 'dF_values', [], 'thresholds', [], 'timeData_ms', []), maxFiles, 1);
    fileCount = 0;
    
    % Process each file as a separate Cs#-C#
    for i = 1:length(groupData)
        if ~isempty(groupData{i}) && isfield(groupData{i}, 'roiNames') && ~isempty(groupData{i}.roiNames)
            
            % Extract coverslip-cell info
            csCell = 'Unknown';
            if ~isempty(groupMetadata{i}) && isfield(groupMetadata{i}, 'coverslipCell') && ~isempty(groupMetadata{i}.coverslipCell)
                csCell = groupMetadata{i}.coverslipCell;
            else
                csCell = sprintf('File%d', i);
            end
            
            % Get ROI data for this coverslip-cell
            roiNums = extractROINumbers(groupData{i}.roiNames);
            
            % Store in preallocated array
            fileCount = fileCount + 1;
            coverslipFiles(fileCount).coverslipCell = csCell;
            coverslipFiles(fileCount).roiNumbers = roiNums;
            coverslipFiles(fileCount).dF_values = groupData{i}.dF_values;
            coverslipFiles(fileCount).thresholds = groupData{i}.thresholds;
            coverslipFiles(fileCount).timeData_ms = groupData{i}.timeData_ms;
            
            fprintf('    PPF file %d - %s: %d ROIs\n', i, csCell, length(roiNums));
        end
    end
    
    % Trim to actual size
    coverslipFiles = coverslipFiles(1:fileCount);
    
    if isempty(coverslipFiles)
        error('No valid PPF data found');
    end
    
    % Rest of the function remains the same...
    timeData_ms = coverslipFiles(1).timeData_ms;
    organizedTable = table();
    organizedTable.Frame = timeData_ms;
    
    fprintf('    Creating PPF organized table with %d coverslip files\n', length(coverslipFiles));
    
    % Add all ROIs from all coverslip files
    for fileIdx = 1:length(coverslipFiles)
        fileData = coverslipFiles(fileIdx);
        csCell = fileData.coverslipCell;
        
        % Sort ROIs for consistent ordering
        [sortedROIs, sortOrder] = sort(fileData.roiNumbers);
        
        for roiIdx = 1:length(sortedROIs)
            roiNum = sortedROIs(roiIdx);
            originalIdx = sortOrder(roiIdx);
            
            % Column name format: Cs1-c2_ROI3
            colName = sprintf('%s_ROI%d', csCell, roiNum);
            organizedTable.(colName) = fileData.dF_values(:, originalIdx);
        end
    end
    
    organizedData = organizedTable;
    
    % Create averaged data - one average per Cs#-C#
    averagedTable = table();
    averagedTable.Frame = timeData_ms;    
    
    for fileIdx = 1:length(coverslipFiles)
        fileData = coverslipFiles(fileIdx);
        csCell = fileData.coverslipCell;
        
        % Find all columns for this Cs#-C#
        allColNames = organizedData.Properties.VariableNames;
        csPattern = sprintf('%s_ROI', csCell);
        csCols = contains(allColNames, csPattern);
        
        if any(csCols)
            csColNames = allColNames(csCols);
            csData = organizedData(:, csColNames);
            
            % Average all ROIs in this Cs#-C#
            csDataMatrix = table2array(csData);
            meanData = mean(csDataMatrix, 2, 'omitnan');
            nROIs = size(csDataMatrix, 2);
            
            % Column name format: Cs1-c2_n24
            avgColName = sprintf('%s_n%d', csCell, nROIs);
            averagedTable.(avgColName) = meanData;
        end
    end
    
    averagedData = averagedTable;
    
    % Create PPF-specific ROI info
    roiInfo = struct();
    roiInfo.coverslipFiles = coverslipFiles;
    roiInfo.timepoint = timepoint;
    roiInfo.experimentType = 'PPF';
    roiInfo.dataType = 'single';
    
    fprintf('    PPF organization complete: %d individual columns, %d averaged columns\n', ...
            width(organizedData)-1, width(averagedData)-1);
end

function [organizedData, averagedData, roiInfo] = organizeGroupData1AP(groupData, groupMetadata)
    % 1AP data organization with noise level tracking
    
    % Extract and validate trial numbers
    [originalTrialNumbers, trialMapping] = createTrialMapping(groupMetadata);
    
    if isempty(originalTrialNumbers)
        error('No valid trial numbers found in metadata');
    end
    
    % Collect all ROI numbers and their noise levels
    numFiles = length(groupData);
    maxROIs = 0;
    
    % First pass: calculate total ROI count
    for fileIdx = 1:numFiles
        if ~isempty(groupData{fileIdx}) && isfield(groupData{fileIdx}, 'roiNames')
            maxROIs = maxROIs + length(groupData{fileIdx}.roiNames);
        end
    end
    
    % Preallocate arrays for ROI tracking
    allROINums = NaN(maxROIs, 1);
    allNoiseTypes = cell(maxROIs, 1);  % Track noise type for each ROI occurrence
    roiCount = 0;
    
    % Second pass: collect ROI numbers with noise classification
    for fileIdx = 1:numFiles
        if ~isempty(groupData{fileIdx}) && isfield(groupData{fileIdx}, 'roiNames') && ~isempty(groupData{fileIdx}.roiNames)
            roiNums = extractROINumbers(groupData{fileIdx}.roiNames);
            thresholds = groupData{fileIdx}.thresholds;
            
            fprintf('    File %d: %d ROIs passed threshold\n', fileIdx, length(roiNums));
            
            % Classify noise level for each ROI
            for roiIdx = 1:length(roiNums)
                roiCount = roiCount + 1;
                allROINums(roiCount) = roiNums(roiIdx);
                
                % Determine noise level (threshold ≤ 0.02 = low noise)
                if roiIdx <= length(thresholds) && isfinite(thresholds(roiIdx))
                    if thresholds(roiIdx) <= 0.02
                        allNoiseTypes{roiCount} = 'low';
                    else
                        allNoiseTypes{roiCount} = 'high';
                    end
                else
                    allNoiseTypes{roiCount} = 'unknown';
                end
            end
        else
            fprintf('    File %d: No valid ROI data found\n', fileIdx);
        end
    end
    
    % Trim to actual size
    allROINums = allROINums(1:roiCount);
    allNoiseTypes = allNoiseTypes(1:roiCount);
    
    uniqueROIs = unique(allROINums);
    uniqueROIs = sort(uniqueROIs);
    
    fprintf('    Total unique ROIs found: %d\n', length(uniqueROIs));
    
    if isempty(uniqueROIs)
        error('No valid ROIs found in group data');
    end
    
    % Create ROI noise classification map (majority vote for each ROI)
    roiNoiseMap = containers.Map('KeyType', 'double', 'ValueType', 'char');
    for roiNum = uniqueROIs'
        roiOccurrences = allROINums == roiNum;
        roiNoiseTypes = allNoiseTypes(roiOccurrences);
        
        % Count occurrences of each noise type
        lowCount = sum(strcmp(roiNoiseTypes, 'low'));
        highCount = sum(strcmp(roiNoiseTypes, 'high'));
        
        if lowCount >= highCount
            roiNoiseMap(roiNum) = 'low';
        else
            roiNoiseMap(roiNum) = 'high';
        end
    end
    
    % Rest of organization remains the same
    timeData_ms = groupData{1}.timeData_ms;
    numFrames = length(timeData_ms);
    numTrials = length(originalTrialNumbers);
    numROIs = length(uniqueROIs);
    
    % Create organized table with preallocation
    organizedTable = table();
    organizedTable.Frame = timeData_ms;
    
    % Preallocate threshold storage
    allThresholds = NaN(numROIs, numTrials);
    
    % Organize data with optimizations
    fprintf('    Organizing %d ROIs across %d trials with noise tracking\n', numROIs, numTrials);
    
    for roiIdx = 1:numROIs
        roiNum = uniqueROIs(roiIdx);
        
        for trialIdx = 1:numTrials
            originalTrialNum = originalTrialNumbers(trialIdx);
            
            if isfinite(originalTrialNum)
                colName = sprintf('ROI%d_T%g', roiNum, originalTrialNum);
                
                % Find ROI data in this trial
                data = groupData{trialIdx};
                
                if ~isempty(data) && isfield(data, 'dF_values') && isfield(data, 'roiNames')
                    roiNums = extractROINumbers(data.roiNames);
                    roiPos = find(roiNums == roiNum, 1);
                    
                    if ~isempty(roiPos) && roiPos <= size(data.dF_values, 2)
                        % ROI exists - extract data
                        roiData = data.dF_values(:, roiPos);
                        
                        % Ensure correct length
                        if length(roiData) == numFrames
                            organizedTable.(colName) = roiData;
                            if isfield(data, 'thresholds') && roiPos <= length(data.thresholds)
                                allThresholds(roiIdx, trialIdx) = data.thresholds(roiPos);
                            end
                        else
                            organizedTable.(colName) = NaN(numFrames, 1, 'single');
                        end
                    else
                        % ROI doesn't exist in this trial
                        organizedTable.(colName) = NaN(numFrames, 1, 'single');
                    end
                else
                    % No valid data for this trial
                    organizedTable.(colName) = NaN(numFrames, 1, 'single');
                end
            end
        end
    end
    
    organizedData = organizedTable;
    
    % Create ROI info structure with noise classification
    roiInfo = struct();
    roiInfo.roiNumbers = uniqueROIs;
    roiInfo.roiNoiseMap = roiNoiseMap;  % Add noise classification
    roiInfo.numTrials = numTrials;
    roiInfo.originalTrialNumbers = originalTrialNumbers;
    roiInfo.trialMapping = trialMapping;
    roiInfo.experimentType = '1AP';
    roiInfo.thresholds = allThresholds;
    roiInfo.dataType = 'single';
    
    % Create ROI averaged data (unchanged)
    roiAveragedData = createAveragedData1AP(organizedData, roiInfo, timeData_ms);
    
    % Create total averaged data (NEW)
    totalAveragedData = createTotalAveragedData1AP(organizedData, roiInfo, timeData_ms);
    
    % Return both types of averaged data
    averagedData = struct();
    averagedData.roi = roiAveragedData;
    averagedData.total = totalAveragedData;
end

function totalAveragedData = createTotalAveragedData1AP(organizedData, roiInfo, timeData_ms)
    % Create total averaged data across all ROIs by noise level
    
    numFrames = length(timeData_ms);
    
    % Initialize output table
    totalAveragedTable = table();
    totalAveragedTable.Frame = timeData_ms;
    
    % Get all data columns (skip Frame)
    dataVarNames = organizedData.Properties.VariableNames(2:end);
    
    if isempty(dataVarNames)
        totalAveragedData = totalAveragedTable;
        return;
    end
    
    % Separate data by noise level
    lowNoiseData = [];
    highNoiseData = [];
    allValidData = [];
    
    validColumnCount = 0;
    lowNoiseCount = 0;
    highNoiseCount = 0;
    
    for colIdx = 1:length(dataVarNames)
        colName = dataVarNames{colIdx};
        colData = organizedData.(colName);
        
        % Skip columns with all NaN
        if all(isnan(colData))
            continue;
        end
        
        % Extract ROI number from column name
        roiMatch = regexp(colName, 'ROI(\d+)_T', 'tokens');
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            
            % Check noise level
            if isKey(roiInfo.roiNoiseMap, roiNum)
                noiseLevel = roiInfo.roiNoiseMap(roiNum);
                
                validColumnCount = validColumnCount + 1;
                if isempty(allValidData)
                    allValidData = colData;
                else
                    allValidData = [allValidData, colData];
                end
                
                if strcmp(noiseLevel, 'low')
                    lowNoiseCount = lowNoiseCount + 1;
                    if isempty(lowNoiseData)
                        lowNoiseData = colData;
                    else
                        lowNoiseData = [lowNoiseData, colData];
                    end
                elseif strcmp(noiseLevel, 'high')
                    highNoiseCount = highNoiseCount + 1;
                    if isempty(highNoiseData)
                        highNoiseData = colData;
                    else
                        highNoiseData = [highNoiseData, colData];
                    end
                end
            end
        end
    end
    
    % Calculate averages
    if ~isempty(lowNoiseData)
        lowNoiseAvg = mean(lowNoiseData, 2, 'omitnan');
        totalAveragedTable.(sprintf('Low_Noise_n%d', lowNoiseCount)) = lowNoiseAvg;
    end
    
    if ~isempty(highNoiseData)
        highNoiseAvg = mean(highNoiseData, 2, 'omitnan');
        totalAveragedTable.(sprintf('High_Noise_n%d', highNoiseCount)) = highNoiseAvg;
    end
    
    if ~isempty(allValidData)
        allAvg = mean(allValidData, 2, 'omitnan');
        totalAveragedTable.(sprintf('All_n%d', validColumnCount)) = allAvg;
    end
    
    totalAveragedData = totalAveragedTable;
    
    fprintf('    Total averages: Low noise n=%d, High noise n=%d, All n=%d\n', ...
            lowNoiseCount, highNoiseCount, validColumnCount);
end

function [trialNum, expType, ppiValue, coverslipCell] = extractTrialOrPPI(filename)
    %  1AP trial or PPI extraction
    
    trialNum = NaN;
    expType = '';
    ppiValue = NaN;
    coverslipCell = '';
    
    try
        % Extract coverslip-cell info first
        csPattern = '_Cs(\d+)-c(\d+)_';
        csMatch = regexp(filename, csPattern, 'tokens');
        if ~isempty(csMatch)
            coverslipCell = sprintf('Cs%s-c%s', csMatch{1}{1}, csMatch{1}{2});
        end
        
        % Determine experiment type first
        if contains(filename, '1AP')
            expType = '1AP';
            %  pattern matching for 1AP
            patterns = {'1AP-(\d+)', '1AP_(\d+)', '1AP(\d+)'};
            
            for i = 1:length(patterns)
                trialMatch = regexp(filename, patterns{i}, 'tokens');
                if ~isempty(trialMatch)
                    trialNum = str2double(trialMatch{1}{1});
                    break;
                end
            end
            
        elseif contains(filename, 'PPF')
            expType = 'PPF';
            %  pattern matching for PPF
            ppfPattern = 'PPF-(\d+)ms-(\d+)';
            ppfMatch = regexp(filename, ppfPattern, 'tokens');
            
            if ~isempty(ppfMatch)
                ppiValue = str2double(ppfMatch{1}{1});
                trialNum = str2double(ppfMatch{1}{2});
            end
        end
        
        %  fallback patterns
        if isnan(trialNum)
            fallbackPatterns = {'(\d+)_bg', '(\d+)_mean', '-(\d+)_', '_(\d+)\.'};
            
            for i = 1:length(fallbackPatterns)
                fallbackMatch = regexp(filename, fallbackPatterns{i}, 'tokens');
                if ~isempty(fallbackMatch)
                    trialNum = str2double(fallbackMatch{1}{1});
                    break;
                end
            end
        end
        
        % Validation
        if ~isnumeric(trialNum) || ~isscalar(trialNum) || ~isfinite(trialNum)
            trialNum = NaN;
        end
        
    catch ME
        fprintf('    WARNING: Trial extraction error for %s: %s\n', filename, ME.message);
        trialNum = NaN;
        expType = '';
        ppiValue = NaN;
        coverslipCell = '';
    end
end

function [originalTrialNumbers, trialMapping] = createTrialMapping(groupMetadata)
    % Simplified trial mapping with both outputs
    
    numFiles = length(groupMetadata);
    originalTrialNumbers = NaN(numFiles, 1);
    validCount = 0;
    
    for i = 1:numFiles
        if ~isempty(groupMetadata{i}) && isfield(groupMetadata{i}, 'trialNumber')
            trialNum = groupMetadata{i}.trialNumber;
            
            % Inline the conversion logic (replacing convertToValidTrialNumber)
            validNum = NaN;
            try
                if isnumeric(trialNum) && isscalar(trialNum) && isfinite(trialNum)
                    validNum = double(trialNum);
                elseif iscell(trialNum) && ~isempty(trialNum)
                    cellVal = trialNum{1};
                    if isnumeric(cellVal) && isscalar(cellVal) && isfinite(cellVal)
                        validNum = double(cellVal);
                    end
                elseif ischar(trialNum) || isstring(trialNum)
                    numVal = str2double(trialNum);
                    if isfinite(numVal)
                        validNum = double(numVal);
                    end
                end
            catch
                % Return NaN for any conversion error
            end
            
            if isfinite(validNum)
                validCount = validCount + 1;
                originalTrialNumbers(validCount) = validNum;
            end
        end
    end
    
    % Trim to actual size
    originalTrialNumbers = originalTrialNumbers(1:validCount);
    
    % Create efficient bidirectional mapping
    uniqueTrials = unique(originalTrialNumbers);
    numUnique = length(uniqueTrials);
    
    trialMapping = struct();
    trialMapping.original_to_sequential = containers.Map(num2cell(uniqueTrials), ...
                                                        num2cell(1:numUnique));
    trialMapping.sequential_to_original = containers.Map(num2cell(1:numUnique), ...
                                                        num2cell(uniqueTrials));
end

function [finalDFValues, finalHeaders, finalThresholds] = filterValidROIsAdaptive(dF_values, validHeaders, thresholds, varargin)
    % Unified ROI filtering with adaptive thresholds for both 1AP and PPF experiments
    % 
    % INPUTS:
    %   dF_values    - dF/F data matrix (frames x ROIs)
    %   validHeaders - cell array of ROI names
    %   thresholds   - threshold values for each ROI (3×std baseline)
    %   varargin     - optional: 'PPF', timepoint_ms for PPF experiments
    %
    % USAGE:
    %   [data, headers, thresh] = filterValidROIsAdaptive(dF, headers, thresh);  % 1AP
    %   [data, headers, thresh] = filterValidROIsAdaptive(dF, headers, thresh, 'PPF', 30);  % PPF 30ms
    
    % Parse inputs
    isPPF = false;
    timepoint_ms = 0;
    
    if nargin >= 4 && ischar(varargin{1}) && strcmp(varargin{1}, 'PPF')
        isPPF = true;
        if nargin >= 5
            timepoint_ms = varargin{2};
        else
            error('PPF mode requires timepoint_ms parameter');
        end
    end
    
    % Common setup
    stimulusFrame1 = 267;  % First stimulus at 1335ms
    postStimulusWindow = 50; % 250ms window to check for response
    
    % Remove empty/NaN columns efficiently
    nonEmptyColumns = ~all(isnan(dF_values), 1);
    dF_values = dF_values(:, nonEmptyColumns);
    validHeaders = validHeaders(nonEmptyColumns);
    thresholds = thresholds(nonEmptyColumns);
    
    fprintf('    After removing empty columns: %d ROIs remain\n', length(validHeaders));
    
    %  duplicate detection
    if size(dF_values, 2) > 1
        tolerance = single(1e-10);
        [~, uniqueIdx] = uniquetol(dF_values', tolerance, 'ByRows', true, 'DataScale', 1);
        if length(uniqueIdx) < size(dF_values, 2)
            fprintf('    Removed %d duplicate columns\n', size(dF_values, 2) - length(uniqueIdx));
            dF_values = dF_values(:, uniqueIdx);
            validHeaders = validHeaders(uniqueIdx);
            thresholds = thresholds(uniqueIdx);
        end
    end
    
    % Calculate adaptive thresholds
    adaptiveThresholds = calculateAdaptiveThresholds(thresholds);
    
    % Get stimulus responses
    if isPPF
        fprintf('    PPF filtering: checking responses within 250ms after both stimuli\n');
        stimulusFrame2 = stimulusFrame1 + round(timepoint_ms / 5);
        fprintf('    Stimulus 1: %dms (frame %d), Stimulus 2: %dms (frame %d)\n', ...
                stimulusFrame1*5, stimulusFrame1, stimulusFrame2*5, stimulusFrame2);
        
        maxResponses1 = getStimulusResponse(dF_values, stimulusFrame1, postStimulusWindow);
        maxResponses2 = getStimulusResponse(dF_values, stimulusFrame2, postStimulusWindow);
        
        % PPF: pass if EITHER stimulus meets criteria
        response1Filter = maxResponses1 >= adaptiveThresholds & isfinite(maxResponses1);
        response2Filter = maxResponses2 >= adaptiveThresholds & isfinite(maxResponses2);
        responseFilter = response1Filter | response2Filter;
        
        fprintf('    ROIs passing threshold for stimulus 1: %d/%d\n', sum(response1Filter), length(response1Filter));
        fprintf('    ROIs passing threshold for stimulus 2: %d/%d\n', sum(response2Filter), length(response2Filter));
        fprintf('    ROIs passing either stimulus (final): %d/%d\n', sum(responseFilter), length(responseFilter));
        
    else
        % 1AP: single stimulus check
        fprintf('    1AP filtering: checking response within 250ms after stimulus\n');
        maxResponses = getStimulusResponse(dF_values, stimulusFrame1, postStimulusWindow);
        responseFilter = maxResponses >= adaptiveThresholds & isfinite(maxResponses);
        
        fprintf('    ROIs passing adaptive threshold within 250ms: %d/%d\n', sum(responseFilter), length(responseFilter));
    end
    
    % Apply filter and return results
    finalDFValues = dF_values(:, responseFilter);
    finalHeaders = validHeaders(responseFilter);
    finalThresholds = thresholds(responseFilter);
    
    fprintf('    Final ROI count after adaptive filtering: %d\n', length(finalHeaders));
end

% Helper function: Calculate adaptive thresholds
function adaptiveThresholds = calculateAdaptiveThresholds(thresholds)
    % Calculate adaptive thresholds based on noise level
    % Low noise (threshold ≤ 0.02): use original threshold
    % High noise (threshold > 0.02): use 1.5× original threshold
    
    lowNoiseROIs = thresholds <= 0.02;
    highNoiseROIs = thresholds > 0.02;
    
    adaptiveThresholds = zeros(size(thresholds));
    adaptiveThresholds(lowNoiseROIs) = thresholds(lowNoiseROIs);  % original
    adaptiveThresholds(highNoiseROIs) = 1.5 * thresholds(highNoiseROIs);  % stricter
    
    fprintf('    ROIs with low noise (threshold ≤ 0.02): %d (using original threshold)\n', sum(lowNoiseROIs));
    fprintf('    ROIs with high noise (threshold > 0.02): %d (using 1.5×threshold)\n', sum(highNoiseROIs));
end

% Helper function: Get stimulus response
function maxResponse = getStimulusResponse(dF_values, stimulusFrame, postStimulusWindow)
    % Get maximum response in post-stimulus window
    
    if size(dF_values, 1) > stimulusFrame
        responseStart = stimulusFrame + 1;
        responseEnd = min(stimulusFrame + postStimulusWindow, size(dF_values, 1));
        responseWindow = responseStart:responseEnd;
        postStimulusData = dF_values(responseWindow, :);
        maxResponse = max(postStimulusData, [], 1, 'omitnan');
    else
        maxResponse = zeros(1, size(dF_values, 2));
    end
end


function roiNumbers = extractROINumbers(roiNames)
    % Extract ROI numbers with proper preallocation
    
    numROIs = length(roiNames);
    roiNumbers = NaN(numROIs, 1); % Preallocate for worst case
    validCount = 0;
    
    for i = 1:numROIs
        try
            roiName = char(roiNames{i});
            
            % Primary pattern: vectorized regex
            roiMatch = regexp(roiName, 'roi[_\s]*(\d+)', 'tokens', 'ignorecase');
            if ~isempty(roiMatch)
                roiNum = str2double(roiMatch{1}{1});
                if isfinite(roiNum) && roiNum > 0 && roiNum <= 65535
                    validCount = validCount + 1;
                    roiNumbers(validCount) = roiNum;
                    continue;
                end
            end
            
            % Fallback: find any number
            numMatch = regexp(roiName, '(\d+)', 'tokens');
            if ~isempty(numMatch)
                roiNum = str2double(numMatch{end}{1});
                if isfinite(roiNum) && roiNum > 0 && roiNum <= 65535
                    validCount = validCount + 1;
                    roiNumbers(validCount) = roiNum;
                end
            end
            
        catch
            % Skip problematic entries
        end
    end
    
    % Trim to actual size
    roiNumbers = roiNumbers(1:validCount);
end

function averagedData = createAveragedData1AP(organizedData, roiInfo, timeData_ms)
    % Create averaged data with proper preallocation
    
    numROIs = length(roiInfo.roiNumbers);
    numFrames = length(timeData_ms);
    
    % Preallocate averaged table
    averagedTable = table();
    averagedTable.Frame = timeData_ms;
    
    % Preallocate threshold array
    roiInfo.avgThresholds = NaN(numROIs, 1);
    
    for roiIdx = 1:numROIs
        roiNum = roiInfo.roiNumbers(roiIdx);
        
        % Preallocate for maximum possible trials
        maxTrials = roiInfo.numTrials;
        trialDataMatrix = NaN(numFrames, maxTrials, 'single');
        validThresholds = NaN(maxTrials, 1, 'single');
        
        validTrialCount = 0;
        validThresholdCount = 0;
        
        for trialIdx = 1:roiInfo.numTrials
            originalTrialNum = roiInfo.originalTrialNumbers(trialIdx);
            if isfinite(originalTrialNum)
                colName = sprintf('ROI%d_T%g', roiNum, originalTrialNum);
                
                if ismember(colName, organizedData.Properties.VariableNames)
                    trialData = organizedData.(colName);
                    if ~all(isnan(trialData))
                        validTrialCount = validTrialCount + 1;
                        trialDataMatrix(:, validTrialCount) = trialData;
                        
                        % Collect threshold efficiently
                        if roiIdx <= size(roiInfo.thresholds, 1) && trialIdx <= size(roiInfo.thresholds, 2)
                            thresh = roiInfo.thresholds(roiIdx, trialIdx);
                            if isfinite(thresh)
                                validThresholdCount = validThresholdCount + 1;
                                validThresholds(validThresholdCount) = thresh;
                            end
                        end
                    end
                end
            end
        end
        
        % Calculate average if data exists
        if validTrialCount > 0
            validTrialData = trialDataMatrix(:, 1:validTrialCount);
            meanData = mean(validTrialData, 2, 'omitnan');
            avgColName = sprintf('ROI%d_n%d', roiNum, validTrialCount);
            averagedTable.(avgColName) = meanData;
            
            if validThresholdCount > 0
                validThresholdData = validThresholds(1:validThresholdCount);
                roiInfo.avgThresholds(roiIdx) = mean(validThresholdData);
            end
        end
    end
    
    averagedData = averagedTable;
end


function saveGroupedExcel(organizedData, averagedData, roiInfo, groupKey, outputFolder)
    % Updated Excel saving with noise-based sheets and total averages
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    filename = [cleanGroupKey '_grouped_v50.xlsx'];
    filepath = fullfile(outputFolder, filename);
    
    % Delete existing file
    if exist(filepath, 'file')
        delete(filepath);
    end
    
    try
        if strcmp(roiInfo.experimentType, 'PPF')
            % PPF: Keep existing structure (no changes needed)
            writeTrialsSheet(organizedData, roiInfo, filepath);
            writeAveragedSheet(averagedData, roiInfo, filepath);
        else
            % 1AP: New structure with noise-based sheets
            writeNoiseBasedTrialsSheets(organizedData, roiInfo, filepath);
            writeROIAveragedSheet(averagedData.roi, roiInfo, filepath);
            writeTotalAveragedSheet(averagedData.total, roiInfo, filepath);
        end
        
        % Write metadata sheet with noise level info
        writeMetadataSheetForScript1([], roiInfo, filepath, organizedData);
        
    catch ME
        fprintf('    ERROR saving Excel file %s: %s\n', filename, ME.message);
        rethrow(ME);
    end
end

function writeMetadataSheetForScript1(metadataCollection, roiInfo, filepath, organizedData)
    % Create metadata sheet specifically for Script 1 to import
    % This eliminates the need for Script 1 to recalculate baseline stats and thresholds
    % FIXED: Only include ROI-trial combinations that actually have data
    
    fprintf('    Writing metadata sheet for Script 1 optimization...\n');
    
    try
        if strcmp(roiInfo.experimentType, 'PPF')
            writeMetadataSheetPPF(metadataCollection, roiInfo, filepath, organizedData);
        else
            writeMetadataSheet1APFixed(metadataCollection, roiInfo, filepath, organizedData);
        end
        
        fprintf('    Metadata sheet written successfully\n');
        
    catch ME
        fprintf('    ERROR writing metadata sheet: %s\n', ME.message);
        rethrow(ME);
    end
end

function writeNoiseBasedTrialsSheets(organizedData, roiInfo, filepath)
    % Write separate Low_noise and High_noise sheets for 1AP data
    
    varNames = organizedData.Properties.VariableNames;
    timeData_ms = organizedData.Frame;
    numFrames = length(timeData_ms);
    
    % Separate columns by noise level
    lowNoiseColumns = {'Frame'};  % Always include Frame
    highNoiseColumns = {'Frame'};
    
    for i = 2:length(varNames)  % Skip Frame column
        colName = varNames{i};
        
        % Extract ROI number
        roiMatch = regexp(colName, 'ROI(\d+)_T', 'tokens');
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            
            if isKey(roiInfo.roiNoiseMap, roiNum)
                noiseLevel = roiInfo.roiNoiseMap(roiNum);
                
                if strcmp(noiseLevel, 'low')
                    lowNoiseColumns{end+1} = colName;
                elseif strcmp(noiseLevel, 'high')
                    highNoiseColumns{end+1} = colName;
                end
            end
        end
    end
    
    % Write Low_noise sheet
    if length(lowNoiseColumns) > 1  % More than just Frame
        lowNoiseData = organizedData(:, lowNoiseColumns);
        writeSingleTrialsSheet(lowNoiseData, roiInfo, filepath, 'Low_noise');
    end
    
    % Write High_noise sheet
    if length(highNoiseColumns) > 1  % More than just Frame
        highNoiseData = organizedData(:, highNoiseColumns);
        writeSingleTrialsSheet(highNoiseData, roiInfo, filepath, 'High_noise');
    end
    
    fprintf('    Written noise-based sheets: Low_noise (%d cols), High_noise (%d cols)\n', ...
            length(lowNoiseColumns)-1, length(highNoiseColumns)-1);
end

function writeSingleTrialsSheet(dataTable, roiInfo, filepath, sheetName)
    % Write a single trials sheet with custom headers
    
    varNames = dataTable.Properties.VariableNames;
    timeData_ms = dataTable.Frame;
    numFrames = length(timeData_ms);
    
    % Prepare header rows
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    % First column
    row1{1} = 'Trial';
    row2{1} = 'Time (ms)';
    
    % Process each variable
    for i = 2:length(varNames)
        varName = varNames{i};
        
        roiMatch = regexp(varName, 'ROI(\d+)_T(\d+)', 'tokens');
        if ~isempty(roiMatch)
            roiNum = roiMatch{1}{1};
            trialNum = roiMatch{1}{2};
            
            row1{i} = trialNum;
            row2{i} = ['ROI ' roiNum];
        else
            row1{i} = '';
            row2{i} = varName;
        end
    end
    
    % Prepare data matrix
    try
        dataMatrix = [timeData_ms, dataTable{:, 2:end}];
        
        % Create cell array for writing
        cellData = cell(numFrames + 2, length(varNames));
        
        % Add headers
        cellData(1, :) = row1;
        cellData(2, :) = row2;
        
        % Add data
        for i = 1:numFrames
            for j = 1:size(dataMatrix, 2)
                cellData{i+2, j} = dataMatrix(i, j);
            end
        end
        
        % Write to Excel
        writecell(cellData, filepath, 'Sheet', sheetName);
        
    catch ME
        fprintf('    WARNING: Custom header writing failed for %s (%s), using standard format\n', sheetName, ME.message);
        writetable(dataTable, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
    end
end

function writeROIAveragedSheet(averagedData, roiInfo, filepath)
    % Write ROI_Average sheet (renamed from "Averaged")
    
    varNames = averagedData.Properties.VariableNames;
    timeData_ms = averagedData.Frame;
    numFrames = length(timeData_ms);
    
    % Prepare header rows
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    % First column
    row1{1} = 'n';
    row2{1} = 'Time (ms)';
    
    % Process each variable
    for i = 2:length(varNames)
        varName = varNames{i};
        
        roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
        if ~isempty(roiMatch)
            roiNum = roiMatch{1}{1};
            nTrials = roiMatch{1}{2};
            
            row1{i} = nTrials;
            row2{i} = ['ROI ' roiNum];
        else
            row1{i} = '';
            row2{i} = varName;
        end
    end
    
    % Write to Excel
    try
        dataMatrix = [timeData_ms, averagedData{:, 2:end}];
        cellData = cell(numFrames + 2, length(varNames));
        
        cellData(1, :) = row1;
        cellData(2, :) = row2;
        
        for i = 1:numFrames
            for j = 1:size(dataMatrix, 2)
                cellData{i+2, j} = dataMatrix(i, j);
            end
        end
        
        writecell(cellData, filepath, 'Sheet', 'ROI_Average');
        
    catch ME
        fprintf('    WARNING: ROI averaged sheet writing failed (%s), using standard format\n', ME.message);
        writetable(averagedData, filepath, 'Sheet', 'ROI_Average', 'WriteVariableNames', true);
    end
end

function writeTotalAveragedSheet(totalAveragedData, roiInfo, filepath)
    % Write Total_Average sheet for 1AP experiments
    
    if width(totalAveragedData) <= 1  % Only Frame column
        fprintf('    No total averaged data to write\n');
        return;
    end
    
    varNames = totalAveragedData.Properties.VariableNames;
    timeData_ms = totalAveragedData.Frame;
    numFrames = length(timeData_ms);
    
    % Create simple headers
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    row1{1} = 'Average Type';
    row2{1} = 'Time (ms)';
    
    for i = 2:length(varNames)
        varName = varNames{i};
        
        % Parse column names like "Low_Noise_n15", "High_Noise_n8", "All_n23"
        if contains(varName, 'Low_Noise')
            nMatch = regexp(varName, 'n(\d+)', 'tokens');
            if ~isempty(nMatch)
                row1{i} = nMatch{1}{1};
                row2{i} = 'Low Noise';
            else
                row1{i} = '';
                row2{i} = 'Low Noise';
            end
        elseif contains(varName, 'High_Noise')
            nMatch = regexp(varName, 'n(\d+)', 'tokens');
            if ~isempty(nMatch)
                row1{i} = nMatch{1}{1};
                row2{i} = 'High Noise';
            else
                row1{i} = '';
                row2{i} = 'High Noise';
            end
        elseif contains(varName, 'All_')
            nMatch = regexp(varName, 'n(\d+)', 'tokens');
            if ~isempty(nMatch)
                row1{i} = nMatch{1}{1};
                row2{i} = 'All';
            else
                row1{i} = '';
                row2{i} = 'All';
            end
        else
            row1{i} = '';
            row2{i} = varName;
        end
    end
    
    % Write to Excel
    try
        dataMatrix = [timeData_ms, totalAveragedData{:, 2:end}];
        cellData = cell(numFrames + 2, length(varNames));
        
        cellData(1, :) = row1;
        cellData(2, :) = row2;
        
        for i = 1:numFrames
            for j = 1:size(dataMatrix, 2)
                cellData{i+2, j} = dataMatrix(i, j);
            end
        end
        
        writecell(cellData, filepath, 'Sheet', 'Total_Average');
        fprintf('    Total_Average sheet written with %d columns\n', length(varNames)-1);
        
    catch ME
        fprintf('    WARNING: Total averaged sheet writing failed (%s), using standard format\n', ME.message);
        writetable(totalAveragedData, filepath, 'Sheet', 'Total_Average', 'WriteVariableNames', true);
    end
end

function writeMetadataSheet1APFixed(metadataCollection, roiInfo, filepath, organizedData)
    % 1AP metadata sheet with noise level column
    
    maxEntries = length(roiInfo.roiNumbers) * roiInfo.numTrials;
    
    if maxEntries == 0
        fprintf('    WARNING: No ROI-trial combinations to process\n');
        return;
    end
    
    % Preallocate struct array with noise level
    allMetadata = repmat(struct(...
        'ROI_Number', NaN, ...
        'Trial_Number', NaN, ...
        'Column_Name', '', ...
        'Noise_Level', '', ...
        'Threshold_dF_F', NaN, ...
        'Baseline_SD', NaN, ...
        'Baseline_Mean', NaN, ...
        'Experiment_Type', '', ...
        'Stimulus_Time_ms', NaN), maxEntries, 1);
    
    entryCount = 0;
    skippedCount = 0;
    
    for roiIdx = 1:length(roiInfo.roiNumbers)
        roiNum = roiInfo.roiNumbers(roiIdx);
        
        % Get noise level for this ROI
        noiseLevel = 'unknown';
        if isKey(roiInfo.roiNoiseMap, roiNum)
            noiseLevel = roiInfo.roiNoiseMap(roiNum);
        end
        
        for trialIdx = 1:roiInfo.numTrials
            trialNum = roiInfo.originalTrialNumbers(trialIdx);
            
            if isfinite(trialNum)
                columnName = sprintf('ROI%d_T%g', roiNum, trialNum);
                
                if ismember(columnName, organizedData.Properties.VariableNames)
                    columnData = organizedData.(columnName);
                    
                    if ~all(isnan(columnData))
                        entryCount = entryCount + 1;
                        allMetadata(entryCount).ROI_Number = roiNum;
                        allMetadata(entryCount).Trial_Number = trialNum;
                        allMetadata(entryCount).Column_Name = columnName;
                        allMetadata(entryCount).Noise_Level = noiseLevel;  % NEW COLUMN
                        
                        % Extract threshold and baseline stats
                        if roiIdx <= size(roiInfo.thresholds, 1) && trialIdx <= size(roiInfo.thresholds, 2)
                            threshold = roiInfo.thresholds(roiIdx, trialIdx);
                            allMetadata(entryCount).Threshold_dF_F = threshold;
                            allMetadata(entryCount).Baseline_SD = threshold / 3;
                        else
                            allMetadata(entryCount).Threshold_dF_F = NaN;
                            allMetadata(entryCount).Baseline_SD = NaN;
                        end
                        
                        allMetadata(entryCount).Baseline_Mean = 0;
                        allMetadata(entryCount).Experiment_Type = '1AP';
                        allMetadata(entryCount).Stimulus_Time_ms = 1335;
                    else
                        skippedCount = skippedCount + 1;
                    end
                else
                    skippedCount = skippedCount + 1;
                end
            end
        end
    end
    
    if entryCount > 0
        allMetadata = allMetadata(1:entryCount);
        metadataTable = struct2table(allMetadata);
        writetable(metadataTable, filepath, 'Sheet', 'ROI_Metadata');
        fprintf('    1AP metadata with noise levels: %d valid entries, %d skipped\n', entryCount, skippedCount);
    else
        fprintf('    WARNING: No valid 1AP ROI metadata found\n');
    end
end

function writeMetadataSheetPPF(metadataCollection, roiInfo, filepath, organizedData)
    % PPF metadata sheet format with OPTIMIZED preallocation
    
    % STEP 1: Calculate maximum possible entries for preallocation
    maxEntries = 0;
    for fileIdx = 1:length(roiInfo.coverslipFiles)
        maxEntries = maxEntries + length(roiInfo.coverslipFiles(fileIdx).roiNumbers);
    end
    
    if maxEntries == 0
        fprintf('    WARNING: No ROIs found in coverslip files\n');
        return;
    end
    
    % STEP 2: Preallocate struct array
    allMetadata = repmat(struct(...
        'CoverslipCell', '', ...
        'ROI_Number', NaN, ...
        'Column_Name', '', ...
        'Threshold_dF_F', NaN, ...
        'Baseline_SD', NaN, ...
        'Baseline_Mean', NaN, ...
        'Experiment_Type', '', ...
        'Timepoint_ms', NaN, ...
        'Stimulus1_Time_ms', NaN, ...
        'Stimulus2_Time_ms', NaN), maxEntries, 1);
    
    % STEP 3: Fill preallocated array efficiently
    entryCount = 0;
    
    for fileIdx = 1:length(roiInfo.coverslipFiles)
        fileData = roiInfo.coverslipFiles(fileIdx);
        csCell = fileData.coverslipCell;
        
        for roiIdx = 1:length(fileData.roiNumbers)
            roiNum = fileData.roiNumbers(roiIdx);
            
            % Check if this ROI actually has a column in organizedData
            columnName = sprintf('%s_ROI%d', csCell, roiNum);
            if ~ismember(columnName, organizedData.Properties.VariableNames)
                continue; % Skip if column doesn't exist
            end
            
            % Check if column has actual data (not all NaN)
            columnData = organizedData.(columnName);
            if all(isnan(columnData))
                continue; % Skip if column is all NaN
            end
            
            % Add to preallocated array
            entryCount = entryCount + 1;
            allMetadata(entryCount).CoverslipCell = csCell;
            allMetadata(entryCount).ROI_Number = roiNum;
            allMetadata(entryCount).Column_Name = columnName;
            
            % Extract baseline statistics and threshold
            if roiIdx <= length(fileData.thresholds)
                threshold = fileData.thresholds(roiIdx);
                allMetadata(entryCount).Threshold_dF_F = threshold;
                allMetadata(entryCount).Baseline_SD = threshold / 3; % Back-calculate baseline SD
                
                % Calculate baseline mean from dF/F data (should be ~0)
                if ~isempty(fileData.dF_values)
                    baselineWindow = 1:min(250, size(fileData.dF_values, 1));
                    baselineData = fileData.dF_values(baselineWindow, roiIdx);
                    allMetadata(entryCount).Baseline_Mean = mean(baselineData, 'omitnan');
                else
                    allMetadata(entryCount).Baseline_Mean = 0;
                end
            else
                allMetadata(entryCount).Threshold_dF_F = NaN;
                allMetadata(entryCount).Baseline_SD = NaN;
                allMetadata(entryCount).Baseline_Mean = NaN;
            end
            
            % Add experiment-specific info
            allMetadata(entryCount).Experiment_Type = 'PPF';
            allMetadata(entryCount).Timepoint_ms = roiInfo.timepoint;
            allMetadata(entryCount).Stimulus1_Time_ms = 1335;
            allMetadata(entryCount).Stimulus2_Time_ms = 1335 + roiInfo.timepoint;
        end
    end
    
    % STEP 4: Trim to actual size and convert to table
    if entryCount > 0
        allMetadata = allMetadata(1:entryCount); % Trim unused entries
        metadataTable = struct2table(allMetadata);
        writetable(metadataTable, filepath, 'Sheet', 'ROI_Metadata');
        fprintf('    PPF metadata: %d valid ROI entries (preallocated %d)\n', entryCount, maxEntries);
    else
        fprintf('    WARNING: No valid PPF ROI metadata found\n');
    end
end


function writeTrialsSheet(organizedData, roiInfo, filepath)
    % Fixed Excel writing for 1AP vs PPF
    
    if strcmp(roiInfo.experimentType, 'PPF')
        writeTrialsSheetPPFOnly(organizedData, roiInfo, filepath);
    else
        % For 1AP, use the noise-based approach instead
        writeNoiseBasedTrialsSheets(organizedData, roiInfo, filepath);
    end
end

function writeAveragedSheet(averagedData, roiInfo, filepath)
    % Fixed Excel writing for averaged data
    
    if strcmp(roiInfo.experimentType, 'PPF')
        writeAveragedSheetPPFOnly(averagedData, roiInfo, filepath);
    else
        % For 1AP, write the ROI averages only (total averages handled separately)
        writeROIAveragedSheet(averagedData, roiInfo, filepath);
    end
end

function writeTrialsSheetPPFOnly(organizedData, roiInfo, filepath)
    % PPF-ONLY trials sheet writing with proper two-row headers
    
    varNames = organizedData.Properties.VariableNames;
    timeData_ms = organizedData.Frame;
    numFrames = length(timeData_ms);
    
    fprintf('    Writing PPF trials sheet with %d columns\n', length(varNames));
    
    % Prepare two-row headers
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    % First column
    row1{1} = sprintf('%dms', roiInfo.timepoint);
    row2{1} = 'Time (ms)';
    
    % Process each variable (skip Frame column)
    for i = 2:length(varNames)
        varName = varNames{i};
        
        % PPF format: Cs1-c2_ROI3
        roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            csCell = roiMatch{1}{1};      % Cs1-c2
            roiNum = roiMatch{1}{2};      % 3
            
            row1{i} = csCell;             % Top row: Cs1-c2
            row2{i} = ['ROI ' roiNum];    % Second row: ROI 3
                    
        else
            fprintf('      WARNING: Could not parse PPF column name: %s\n', varName);
            row1{i} = '';
            row2{i} = varName;
        end
    end
    
    % Prepare data matrix
    try
        dataMatrix = [timeData_ms, organizedData{:, 2:end}];
        fprintf('    Data matrix size: %d x %d\n', size(dataMatrix, 1), size(dataMatrix, 2));
    catch ME
        fprintf('    ERROR creating PPF data matrix: %s\n', ME.message);
        rethrow(ME);
    end
    
    % Write to Excel with custom headers
    try
        cellData = cell(numFrames + 2, length(varNames));
        
        % Add headers
        cellData(1, :) = row1;
        cellData(2, :) = row2;
        
        % Add data
        for i = 1:numFrames
            for j = 1:size(dataMatrix, 2)
                cellData{i+2, j} = dataMatrix(i, j);
            end
        end
        
        % Write to Excel
        writecell(cellData, filepath, 'Sheet', 'All_Data');
        fprintf('    PPF trials sheet written successfully\n');
        
    catch ME
        fprintf('    WARNING: PPF custom header writing failed (%s), using fallback\n', ME.message);
        writetable(organizedData, filepath, 'Sheet', 'All_Data', 'WriteVariableNames', true);
    end
end

function writeAveragedSheetPPFOnly(averagedData, roiInfo, filepath)
    % PPF-ONLY averaged sheet writing with proper two-row headers
    
    varNames = averagedData.Properties.VariableNames;
    timeData_ms = averagedData.Frame;
    numFrames = length(timeData_ms);
    
    fprintf('    Writing PPF averaged sheet with %d columns\n', length(varNames));
    
    % Prepare two-row headers
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    % First column
    row1{1} = sprintf('%dms', roiInfo.timepoint);
    row2{1} = 'Time (ms)';
    
    % Process each variable (skip Frame column)
    for i = 2:length(varNames)
        varName = varNames{i};
        
        % PPF averaged format: Cs1-c2_n24
        roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
        if ~isempty(roiMatch)
            csCell = roiMatch{1}{1};      % Cs1-c2
            nROIs = roiMatch{1}{2};       % 24
            
            row1{i} = nROIs;              % Top row: 24
            row2{i} = csCell;             % Second row: Cs1-c2
            
        else
            fprintf('      WARNING: Could not parse PPF averaged column name: %s\n', varName);
            row1{i} = '';
            row2{i} = varName;
        end
    end
    
    % Prepare data matrix
    try
        dataMatrix = [timeData_ms, averagedData{:, 2:end}];

    catch ME
        fprintf('    ERROR creating PPF averaged data matrix: %s\n', ME.message);
        rethrow(ME);
    end
    
    % Write to Excel with custom headers
    try
        cellData = cell(numFrames + 2, length(varNames));
        
        % Add headers
        cellData(1, :) = row1;
        cellData(2, :) = row2;
        
        % Add data
        for i = 1:numFrames
            for j = 1:size(dataMatrix, 2)
                cellData{i+2, j} = dataMatrix(i, j);
            end
        end
        
        % Write to Excel
        writecell(cellData, filepath, 'Sheet', 'Averaged');
        fprintf('    PPF averaged sheet written successfully\n');
        
    catch ME
        fprintf('    WARNING: PPF averaged custom header writing failed (%s), using fallback\n', ME.message);
        writetable(averagedData, filepath, 'Sheet', 'Averaged', 'WriteVariableNames', true);
    end
end


% Updated plotting function to handle total averages
function generateGroupPlots(organizedData, averagedData, roiInfo, groupKey, plotsIndividualFolder, plotsAveragedFolder)
    % Updated plotting with reorganized folder structure
    
    if strcmp(roiInfo.experimentType, 'PPF')
        generateGroupPlotsPPFOnly(organizedData, averagedData, roiInfo, groupKey, plotsIndividualFolder, plotsAveragedFolder);
    else
        % Create subfolders for better organization
        roiPlotsFolder = fullfile(plotsAveragedFolder, 'ROI_Averages');
        totalPlotsFolder = fullfile(plotsAveragedFolder, 'Total_Averages');
        
        if ~exist(roiPlotsFolder, 'dir'), mkdir(roiPlotsFolder); end
        if ~exist(totalPlotsFolder, 'dir'), mkdir(totalPlotsFolder); end
        
        generateGroupPlots1AP(organizedData, averagedData.roi, roiInfo, groupKey, plotsIndividualFolder, roiPlotsFolder);
        generateTotalAveragePlots1AP(averagedData.total, roiInfo, groupKey, totalPlotsFolder);
    end
end

function generateGroupPlotsPPFOnly(organizedData, averagedData, roiInfo, groupKey, plotsIndividualFolder, plotsAveragedFolder)
    % PPF-ONLY plotting - MODIFIED for genotype titles and Cs-specific files
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    timeData_ms = organizedData.Frame;
    stimulusTime_ms1 = 1335; % First stimulus
    
    % Calculate second stimulus frame
    stimulusTime_ms2 = stimulusTime_ms1 + roiInfo.timepoint;  % timepoint is already in ms
    
    % Extract genotype from groupKey
    genotype = extractGenotypeFromGroupKey(groupKey);
    
    fprintf('    PPF plotting: %dms, genotype=%s, stim1=%d, stim2=%d\n', roiInfo.timepoint, genotype, stimulusTime_ms1, stimulusTime_ms2);
    
    % Generate individual plots - SEPARATE BY Cs#-C#
    generatePPFIndividualPlots(organizedData, roiInfo, genotype, plotsIndividualFolder, timeData_ms, stimulusTime_ms1, stimulusTime_ms2);
    
    % Generate averaged plots with genotype color coding
    numAvgFigures = generatePPFAveragedPlotsOnlyModified(averagedData, roiInfo, cleanGroupKey, genotype, plotsAveragedFolder, timeData_ms, stimulusTime_ms1, stimulusTime_ms2);
    
    fprintf('    PPF plots complete: individual plots by coverslip, %d averaged\n', numAvgFigures);
end

function genotype = extractGenotypeFromGroupKey(groupKey)
    % Extract genotype from group key (WT or R213W)
    
    if contains(groupKey, 'R213W')
        genotype = 'R213W';
    elseif contains(groupKey, 'WT')
        genotype = 'WT';
    else
        genotype = 'Unknown';
    end
end

function generatePPFIndividualPlots(organizedData, roiInfo, genotype, plotsFolder, timeData_ms, stimulusTime_ms1, stimulusTime_ms2)
    % Generate PPF individual plots with proper preallocation
    
    dataVarNames = organizedData.Properties.VariableNames(2:end); % Skip Frame
    
    if isempty(dataVarNames)
        fprintf('    No PPF data to plot\n');
        return;
    end
    
    % Preallocate coverslip collection
    maxCoverslips = length(dataVarNames); % Overestimate
    coverslipCells = cell(maxCoverslips, 1);
    coverslipCount = 0;
    
    % Extract unique Cs#-C# combinations efficiently
    for i = 1:length(dataVarNames)
        varName = dataVarNames{i};
        roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            csCell = roiMatch{1}{1};
            
            % Check if already found (using logical indexing for speed)
            if coverslipCount == 0 || ~any(strcmp(csCell, coverslipCells(1:coverslipCount)))
                coverslipCount = coverslipCount + 1;
                coverslipCells{coverslipCount} = csCell;
            end
        end
    end
    
    % Trim to actual size
    coverslipCells = coverslipCells(1:coverslipCount);
    
    fprintf('    Creating individual plots for %d coverslip-cell combinations\n', coverslipCount);
    
    % Create separate plot for each Cs#-C#
    for csIdx = 1:coverslipCount
        csCell = coverslipCells{csIdx};
        
        % Preallocate ROI collection for this coverslip
        maxROIsPerCs = length(dataVarNames); % Overestimate
        csROIs = cell(maxROIsPerCs, 1);
        csROICount = 0;
        
        % Find all ROIs for this Cs#-C#
        csPattern = [csCell '_ROI'];
        for i = 1:length(dataVarNames)
            varName = dataVarNames{i};
            if contains(varName, csPattern)
                csROICount = csROICount + 1;
                csROIs{csROICount} = varName;
            end
        end
        
        if csROICount == 0
            continue;
        end
        
        % Trim to actual size
        csROIs = csROIs(1:csROICount);
        
        try
            % Calculate subplot layout
            maxPlotsPerFigure = 12;
            numFigures = ceil(csROICount / maxPlotsPerFigure);
            
            for figNum = 1:numFigures
                fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
                
                startROI = (figNum - 1) * maxPlotsPerFigure + 1;
                endROI = min(figNum * maxPlotsPerFigure, csROICount);
                numPlotsThisFig = endROI - startROI + 1;
                
                [nRows, nCols] = calculateLayout(numPlotsThisFig);
                
                for roiIdx = startROI:endROI
                    subplotIdx = roiIdx - startROI + 1;
                    varName = csROIs{roiIdx};
                    traceData = organizedData.(varName);
                    
                    subplot(nRows, nCols, subplotIdx);
                    hold on;
                    
                    % Plot in BLACK
                    if ~all(isnan(traceData))
                        plot(timeData_ms, traceData, 'k-', 'LineWidth', 1.0);
                        
                        % Add GREEN threshold line
                        threshold = getPPFROIThreshold(varName, roiInfo);
                        if isfinite(threshold)
                            plot([timeData_ms(1), timeData_ms(100)], [threshold, threshold], 'g--', 'LineWidth', 1.5);
                        end
                    end
                    
                    % Set y-limits
                    yLims = ylim;
                    ylim([-0.02, max(yLims(2), 0.1)]);
                    
                    % GREEN first stimulus
                    plot([stimulusTime_ms1, stimulusTime_ms1], [-0.02, -0.02], ':gpentagram', 'LineWidth', 1);
                    
                    % CYAN second stimulus
                    plot([stimulusTime_ms2, stimulusTime_ms2], [-0.02, -0.02], ':cpentagram', 'LineWidth', 1);
                    
                    % ROI title
                    roiMatch = regexp(varName, '.*_ROI(\d+)', 'tokens');
                    if ~isempty(roiMatch)
                        title(sprintf('ROI %s', roiMatch{1}{1}), 'FontSize', 10, 'FontWeight', 'bold');
                    else
                        title(varName, 'FontSize', 10, 'FontWeight', 'bold');
                    end
                    
                    xlabel('Time (ms)', 'FontSize', 8);
                    ylabel('ΔF/F', 'FontSize', 8);
                    grid on; box on;
                    hold off;
                end
                
                % Figure title
                if numFigures > 1
                    titleText = sprintf('PPI %dms %s %s (Part %d/%d)', roiInfo.timepoint, genotype, csCell, figNum, numFigures);
                    plotFile = sprintf('PPF_%dms_%s_%s_individual_part%d.png', roiInfo.timepoint, genotype, csCell, figNum);
                else
                    titleText = sprintf('PPI %dms %s %s', roiInfo.timepoint, genotype, csCell);
                    plotFile = sprintf('PPF_%dms_%s_%s_individual.png', roiInfo.timepoint, genotype, csCell);
                end
                
                sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold');
                print(fig, fullfile(plotsFolder, plotFile), '-dpng', '-r300');
                close(fig);
            end
            
        catch ME
            fprintf('    ERROR in PPF individual plot for %s: %s\n', csCell, ME.message);
            if exist('fig', 'var')
                close(fig);
            end
        end
    end
end

function generateTotalAveragePlots1AP(totalAveragedData, roiInfo, groupKey, plotsFolder)
    % Generate plots for total averages
    
    if width(totalAveragedData) <= 1
        fprintf('    No total averaged data to plot\n');
        return;
    end
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    timeData_ms = totalAveragedData.Frame;
    stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    
    % Get column names (skip Frame)
    varNames = totalAveragedData.Properties.VariableNames(2:end);
    
    try
        fig = figure('Position', [100, 100, 1200, 400], 'Visible', 'off', 'Color', 'white');
        
        hold on;
        legendHandles = [];
        legendLabels = {};
        
        for i = 1:length(varNames)
            varName = varNames{i};
            data = totalAveragedData.(varName);
            
            if contains(varName, 'Low_Noise')
                color = [0.2, 0.6, 0.2];  % Green for low noise
                lineStyle = '-';
                displayName = 'Low Noise';
            elseif contains(varName, 'High_Noise')
                color = [0.8, 0.2, 0.2];  % Red for high noise
                lineStyle = '-';
                displayName = 'High Noise';
            elseif contains(varName, 'All_')
                color = [0.2, 0.2, 0.8];  % Blue for all
                lineStyle = '-';
                displayName = 'All ROIs';
            else
                color = [0.5, 0.5, 0.5];  % Gray for unknown
                lineStyle = '-';
                displayName = varName;
            end
            
            % Extract n count for display
            nMatch = regexp(varName, 'n(\d+)', 'tokens');
            if ~isempty(nMatch)
                displayName = sprintf('%s (n=%s)', displayName, nMatch{1}{1});
            end
            
            h = plot(timeData_ms, data, 'Color', color, 'LineWidth', 2, 'LineStyle', lineStyle);
            legendHandles(end+1) = h;
            legendLabels{end+1} = displayName;
        end
        
        % Add stimulus line
        yLims = ylim;
        ylim([-0.02, max(yLims(2), 0.05)]);
        hStim = plot([stimulusTime_ms, stimulusTime_ms], [-0.02, -0.02], ':gpentagram', 'LineWidth', 1.0);
        legendHandles(end+1) = hStim;
        legendLabels{end+1} = 'Stimulus';
        
        title(sprintf('%s - Total Averages by Noise Level', cleanGroupKey), 'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
        xlabel('Time (ms)', 'FontSize', 12);
        ylabel('ΔF/F', 'FontSize', 12);
        grid on; box on;
        
        % Add legend
        legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 10);
        
        hold off;
        
        % Save plot
        plotFile = sprintf('%s_total_averages.png', cleanGroupKey);
        print(fig, fullfile(plotsFolder, plotFile), '-dpng', '-r300');
        close(fig);
        
        fprintf('    Generated total averages plot: %s\n', plotFile);
        
    catch ME
        fprintf('    ERROR creating total averages plot: %s\n', ME.message);
        if exist('fig', 'var')
            close(fig);
        end
    end
end

function threshold = getPPFROIThreshold(varName, roiInfo)
    % Get threshold for PPF ROI
    threshold = NaN;
    
    try
        roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
        if ~isempty(roiMatch)
            csCell = roiMatch{1}{1};
            roiNum = str2double(roiMatch{1}{2});
            
            for fileIdx = 1:length(roiInfo.coverslipFiles)
                fileData = roiInfo.coverslipFiles(fileIdx);
                if strcmp(fileData.coverslipCell, csCell)
                    roiIdx = find(fileData.roiNumbers == roiNum, 1);
                    if ~isempty(roiIdx) && roiIdx <= length(fileData.thresholds)
                        threshold = fileData.thresholds(roiIdx);
                        return;
                    end
                end
            end
        end
    catch
        threshold = NaN;
    end
end

% PPF-only averaged plots 
function numAvgFigures = generatePPFAveragedPlotsOnlyModified(averagedData, roiInfo, cleanGroupKey, genotype, plotsFolder, timeData_ms, stimulusTime_ms1, stimulusTime_ms2)
    
    if width(averagedData) <= 1
        numAvgFigures = 0;
        return;
    end
    
    avgVarNames = averagedData.Properties.VariableNames(2:end);
    numAvgPlots = length(avgVarNames);
    
    fprintf('    PPF averaged traces: %d for genotype %s\n', numAvgPlots, genotype);
    
    maxPlotsPerFigure = 12;
    numAvgFigures = ceil(numAvgPlots / maxPlotsPerFigure);
    
    % Determine trace color based on genotype
    if strcmp(genotype, 'WT')
        traceColor = 'k'; % Black for WT
    elseif strcmp(genotype, 'R213W')
        traceColor = 'm'; % Magenta for R213W mutant
    else
        traceColor = 'b'; % Blue for unknown
    end
    
    for figNum = 1:numAvgFigures
        try
            figAvg = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', 'Color', 'white');
            
            startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
            endPlot = min(figNum * maxPlotsPerFigure, numAvgPlots);
            numPlotsThisFig = endPlot - startPlot + 1;
            
            [nRowsAvg, nColsAvg] = calculateLayout(numPlotsThisFig);
            
            for plotIdx = startPlot:endPlot
                subplotIdx = plotIdx - startPlot + 1;
                
                subplot(nRowsAvg, nColsAvg, subplotIdx);
                hold on;
                
                varName = avgVarNames{plotIdx};
                avgData = averagedData.(varName); % ALREADY IN %dF/F
                
                % Plot in genotype-specific color 
                plot(timeData_ms, avgData, traceColor, 'LineWidth', 1.0);
                
                % Add GREEN threshold line 
                avgThreshold = calculatePPFAveragedThreshold(avgData);
                if isfinite(avgThreshold)
                    plot([timeData_ms(1), timeData_ms(100)], [avgThreshold, avgThreshold], 'g--', 'LineWidth', 1.5);
                end
                
                % Title with GENOTYPE included
                roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    csCell = roiMatch{1}{1};
                    nROIs = str2double(roiMatch{1}{2});
                    title(sprintf('%s %s, n=%d', genotype, csCell, nROIs), 'FontSize', 10, 'FontWeight', 'bold');
                else
                    title([genotype ' ' varName], 'FontSize', 10);
                end
                
                % Set y-limits
                yLims = ylim;
                ylim([-0.005, 0.05]);
                
                % GREEN first stimulus
                plot([stimulusTime_ms1, stimulusTime_ms1], [-0.005, -0.005], ':gpentagram', 'LineWidth', 1.0);
                
                % CYAN second stimulus
                plot([stimulusTime_ms2, stimulusTime_ms2], [-0.005, -0.005], ':cpentagram', 'LineWidth', 1.0);
                
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % FIXED: Include genotype in filename to prevent overwriting
            if numAvgFigures > 1
                titleText = sprintf('PPI %dms %s - Averaged Traces (Part %d/%d)', roiInfo.timepoint, genotype, figNum, numAvgFigures);
                avgPlotFile = sprintf('PPF_%dms_%s_FoV_averaged_part%d.png', roiInfo.timepoint, genotype, figNum);
            else
                titleText = sprintf('PPI %dms %s - Averaged Traces', roiInfo.timepoint, genotype);
                avgPlotFile = sprintf('PPF_%dms_%s_FoV_averaged.png', roiInfo.timepoint, genotype);
            end
            
            sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold');
            print(figAvg, fullfile(plotsFolder, avgPlotFile), '-dpng', '-r300');
            close(figAvg);
            
            fprintf('      Created PPF averaged plot: %s\n', avgPlotFile);
            
        catch ME
            fprintf('    ERROR in PPF averaged plot %d: %s\n', figNum, ME.message);
            if exist('figAvg', 'var'), close(figAvg); end
        end
    end
end

function avgThreshold = calculateProperAveragedThreshold(avgData, baselineWindow)
    % Calculate proper averaged threshold from averaged trace baseline
    if nargin < 2
        baselineWindow = 1:250;  % Default baseline window
    end
    
    % Calculate threshold as 3×SD of baseline portion of averaged trace
    if length(avgData) >= max(baselineWindow)
        baselineData = avgData(baselineWindow);
        avgThreshold = 3 * std(baselineData, 'omitnan');
    else
        avgThreshold = NaN;
    end
    
    if ~isfinite(avgThreshold)
        avgThreshold = 0.01;  % Default threshold if calculation fails
    end
end

% FIX 5: Add missing function for PPF averaged threshold calculation
function avgThreshold = calculatePPFAveragedThreshold(avgData)
    % Calculate threshold for PPF averaged data
    baselineWindow = 1:250;
    
    if length(avgData) >= max(baselineWindow)
        baselineData = avgData(baselineWindow);
        avgThreshold = 3 * std(baselineData, 'omitnan');
    else
        avgThreshold = NaN;
    end
    
    if ~isfinite(avgThreshold)
        avgThreshold = 0.01;
    end
end

function generateGroupPlots1AP(organizedData, averagedData, roiInfo, groupKey, plotsIndividualFolder, plotsAveragedFolder)
    %  1AP plotting with Green stimulus lines and averaged thresholds
    % MODIFIED: No longer converts to percentage since data is already %dF/F
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    timeData_ms = organizedData.Frame;
    stimulusTime_ms = cfg.timing.STIMULUS_TIME_MS;
    
    %  color schemes for trials (consistent mapping)
    trialColors = [
        0.0 0.0 0.0;      % Black - Trial 1
        0.8 0.2 0.2;      % Red - Trial 2
        0.2 0.6 0.8;      % Blue - Trial 3
        0.2 0.8 0.2;      % Green - Trial 4
        0.8 0.5 0.2;      % Orange - Trial 5
        0.6 0.2 0.8;      % Purple - Trial 6
        0.8 0.8 0.2;      % Green-Green - Trial 7
        0.4 0.4 0.4;      % Dark Gray - Trial 8
        0.0 0.8 0.8;      % Cyan - Trial 9
        0.8 0.0 0.8;      % Magenta - Trial 10
    ];
    
    maxPlotsPerFigure = 12;
    numROIs = length(roiInfo.roiNumbers);
    alphaValue = 0.7; % Transparency for individual traces
    
    if numROIs == 0
        fprintf('    No ROIs to plot for group %s\n', groupKey);
        return;
    end
    
    % Create consistent trial number mapping
    uniqueTrials = unique(roiInfo.originalTrialNumbers);
    uniqueTrials = uniqueTrials(isfinite(uniqueTrials));
    uniqueTrials = sort(uniqueTrials);
    
    % Generate individual trials plots
    numTrialsFigures = ceil(numROIs / maxPlotsPerFigure);
    
    for figNum = 1:numTrialsFigures
        try
            fig = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', ...
                        'Color', 'white');
            
            startROI = (figNum - 1) * maxPlotsPerFigure + 1;
            endROI = min(figNum * maxPlotsPerFigure, numROIs);
            numPlotsThisFig = endROI - startROI + 1;
            
            [nRows, nCols] = calculateLayout(numPlotsThisFig);
            
            % Track legend handles
            legendHandles = [];
            legendLabels = {};
            
            for roiIdx = startROI:endROI
                subplotIdx = roiIdx - startROI + 1;
                roiNum = roiInfo.roiNumbers(roiIdx);
                
                subplot(nRows, nCols, subplotIdx);
                hold on;
                
                % Plot trials for this ROI with consistent coloring
                trialCount = 0;
                validThresholds = [];
                hasThresholdInLegend = false; % Track if we've added threshold to legend
                
                for i = 1:length(uniqueTrials)
                    trialNum = uniqueTrials(i);
                    colName = sprintf('ROI%d_T%g', roiNum, trialNum);
                    
                    if ismember(colName, organizedData.Properties.VariableNames)
                        trialData = organizedData.(colName); % ALREADY IN %dF/F
                        if ~all(isnan(trialData))
                            trialCount = trialCount + 1;
                            
                            % Use consistent color (REMOVED: percentage conversion)
                            colorIdx = mod(i-1, size(trialColors, 1)) + 1;
                            
                            h_line = plot(timeData_ms, trialData, 'Color', trialColors(colorIdx, :), ...
                                     'LineWidth', 1.0);
                            
                            % Set transparency
                            h_line.Color(4) = alphaValue;
                            
                            % Store handle for legend (only from first subplot)
                            if subplotIdx == 1
                                if ~ismember(sprintf('Trial %g', trialNum), legendLabels)
                                    legendHandles(end+1) = h_line;
                                    legendLabels{end+1} = sprintf('Trial %g', trialNum);
                                end
                            end
                            
                            % Add individual threshold line (REMOVED: percentage conversion)
                            trialIdx = find(roiInfo.originalTrialNumbers == trialNum, 1);
                            if ~isempty(trialIdx) && roiIdx <= size(roiInfo.thresholds, 1) && ...
                               trialIdx <= size(roiInfo.thresholds, 2) && ...
                               isfinite(roiInfo.thresholds(roiIdx, trialIdx))
                                threshold = roiInfo.thresholds(roiIdx, trialIdx); % ALREADY IN %dF/F
                                h_thresh_line = plot([timeData_ms(1), timeData_ms(100)], [threshold, threshold], ...
                                     ':', 'Color', trialColors(colorIdx, :), 'LineWidth', 1.5, ...
                                     'HandleVisibility', 'off');
                                validThresholds(end+1) = roiInfo.thresholds(roiIdx, trialIdx);
                                
                                % Add threshold to legend only once per figure
                                if subplotIdx == 1 && ~hasThresholdInLegend
                                    h_thresh_line.HandleVisibility = 'on'; % Make this one visible for legend
                                    legendHandles(end+1) = h_thresh_line;
                                    legendLabels{end+1} = 'Individual Thresholds';
                                    hasThresholdInLegend = true;
                                end
                            end
                        end
                    end
                end
                
                % Set y-limits with y-min = -0.02
                yLims = ylim;
                ylim([-0.02, max(yLims(2), 0.1)]);
                
                % Add Green stimulus star (at y=-1)
                hStim = plot([stimulusTime_ms, stimulusTime_ms], [-0.02, -0.02], ':gpentagram', 'LineWidth', 1.0, ...
                     'HandleVisibility', 'off');
                
                % Add to legend only once
                if subplotIdx == 1 && ~ismember('Stimulus', legendLabels)
                    hStim.HandleVisibility = 'on'; % Make visible for legend
                    legendHandles(end+1) = hStim;
                    legendLabels{end+1} = 'Stimulus';
                end
                
                title(sprintf('ROI %d (n=%d)', roiNum, trialCount), 'FontSize', 10, 'FontWeight', 'bold');
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Add figure-level legend
            if ~isempty(legendHandles)
                try
                    legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 8);
                catch ME
                    fprintf('    WARNING: Could not create legend: %s\n', ME.message);
                end
            end
            
            % Add title
            if numTrialsFigures > 1
                titleText = sprintf('%s - Individual Trials (Part %d/%d)', cleanGroupKey, figNum, numTrialsFigures);
                plotFile = sprintf('%s_trials_part%d.png', cleanGroupKey, figNum);
            else
                titleText = sprintf('%s - Individual Trials', cleanGroupKey);
                plotFile = sprintf('%s_trials.png', cleanGroupKey);
            end
            
            sgtitle(titleText, 'FontSize', 14, 'Interpreter', 'none', 'FontWeight', 'bold');
            
            print(fig, fullfile(plotsIndividualFolder, plotFile), '-dpng', '-r300');
            close(fig);
            
        catch ME
            fprintf('    ERROR creating trials plot %d: %s\n', figNum, ME.message);
            if exist('fig', 'var')
                close(fig);
            end
        end
    end
    
    % Generate  averaged plots with Green stimulus and averaged thresholds
    numAvgFigures = generateAveragedPlotsFixed(averagedData, roiInfo, cleanGroupKey, plotsAveragedFolder, timeData_ms, stimulusTime_ms);    
    fprintf('    Generated %d trials plot file(s) and %d averaged plot file(s)\n', numTrialsFigures, numAvgFigures);
end

function numAvgFigures = generateAveragedPlotsFixed(averagedData, roiInfo, cleanGroupKey, plotsFolder, timeData_ms, stimulusTime_ms)
    % Generate  averaged plots with Green stimulus and averaged thresholds
    
    if width(averagedData) <= 1 % Only Frame column
        numAvgFigures = 0;
        return;
    end
    
    avgVarNames = averagedData.Properties.VariableNames(2:end); % Skip Frame
    numAvgPlots = length(avgVarNames);
    maxPlotsPerFigure = 12;
    numAvgFigures = ceil(numAvgPlots / maxPlotsPerFigure);
    
    for figNum = 1:numAvgFigures
        try
            figAvg = figure('Position', [50, 100, 1900, 1000], 'Visible', 'off', ...
                           'Color', 'white');
            
            % Calculate which plots go in this figure
            startPlot = (figNum - 1) * maxPlotsPerFigure + 1;
            endPlot = min(figNum * maxPlotsPerFigure, numAvgPlots);
            numPlotsThisFig = endPlot - startPlot + 1;
            
            [nRowsAvg, nColsAvg] = calculateLayout(numPlotsThisFig);
            
            % Legend preparation
            legendHandles = [];
            legendLabels = {};
            
            for plotIdx = startPlot:endPlot
                subplotIdx = plotIdx - startPlot + 1;
                
                subplot(nRowsAvg, nColsAvg, subplotIdx);
                hold on;
                
                varName = avgVarNames{plotIdx};
                avgData = averagedData.(varName); % ALREADY IN %dF/F
                
                % Plot average trace 
                h_line = plot(timeData_ms, avgData, 'k-', 'LineWidth', 1.0);
                
                % Collect for legend (first subplot only)
                if subplotIdx == 1
                    legendHandles(end+1) = h_line;
                    legendLabels{end+1} = 'Average Trace';
                end
                
                % Add averaged threshold line (REMOVED: percentage conversion)
                roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    roiNum = str2double(roiMatch{1}{1});
                    nTrials = str2double(roiMatch{1}{2});
                    
                    % Calculate threshold for this averaged trace
                    avgThreshold = calculateProperAveragedThreshold(avgData, 1:250);
                    if isfinite(avgThreshold)
                        hThresh = plot([timeData_ms(1), timeData_ms(100)], [avgThreshold, avgThreshold], ...
                             'g--', 'LineWidth', 2, 'HandleVisibility', 'off'); 
                        
                        % Collect for legend (first subplot only)
                        if subplotIdx == 1
                            legendHandles(end+1) = hThresh;
                            legendLabels{end+1} = 'Avg Threshold';
                        end
                    end
                    
                    title(sprintf('ROI %d (n=%d)', roiNum, nTrials), 'FontSize', 10, 'FontWeight', 'bold');
                else
                    title(varName, 'FontSize', 10);
                end
                
                % Set y-limits with y-min = -0.02
                yLims = ylim;
                ylim([-0.02, max(yLims(2), 0.1)]);
                
                % Add Green stimulus star (at y=-1)
                hStim = plot([stimulusTime_ms, stimulusTime_ms], [-0.02, -0.02], ':gpentagram', 'LineWidth', 1.0, ...
                            'HandleVisibility', 'off');
                
                % Collect for legend (first subplot only)
                if subplotIdx == 1
                    legendHandles(end+1) = hStim;
                    legendLabels{end+1} = 'Stimulus';
                end
                
                xlabel('Time (ms)', 'FontSize', 8);
                ylabel('ΔF/F', 'FontSize', 8);
                grid on; box on;
                hold off;
            end
            
            % Add figure-level legend
            if ~isempty(legendHandles)
                try
                    legend(legendHandles, legendLabels, 'Location', 'northeast', 'FontSize', 8);
                catch ME
                    fprintf('    WARNING: Could not create averaged legend: %s\n', ME.message);
                end
            end
            
            % Add title
            if numAvgFigures > 1
                titleText = sprintf('%s - Averaged Traces (Part %d/%d)', cleanGroupKey, figNum, numAvgFigures);
                avgPlotFile = sprintf('%s_averaged_part%d.png', cleanGroupKey, figNum);
            else
                titleText = sprintf('%s - Averaged Traces', cleanGroupKey);
                avgPlotFile = sprintf('%s_averaged.png', cleanGroupKey);
            end
            
            sgtitle(titleText, 'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
            
            % Save averaged plot
            print(figAvg, fullfile(plotsFolder, avgPlotFile), '-dpng', '-r300');
            close(figAvg);
            
        catch ME
            fprintf('    ERROR creating averaged figure %d: %s\n', figNum, ME.message);
            if exist('figAvg', 'var')
                close(figAvg);
            end
        end
    end
end

function [nRows, nCols] = calculateLayout(nSubplots)
    % Calculate optimal subplot layout
    
    if nSubplots <= 2
    nRows = 2; nCols = 1;
    elseif nSubplots <= 4
        nRows = 2; nCols = 2;
    elseif nSubplots <= 6
        nRows = 2; nCols = 3;
    elseif nSubplots <= 9
        nRows = 3; nCols = 3;
    else
        nRows = 3; nCols = 4;
    end
end

function result = prepareGroupResult(groupData, groupMetadata, roiInfo, status)
    
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
            
            % Calculate total ROIs across all coverslip files
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
        if isfield(roiInfo, 'originalTrialNumbers')
            result.actualTrialNumbers = roiInfo.originalTrialNumbers;
        end
    end
    
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

function [successCount, warningCount, errorCount] = analyzeProcessingResults(groupResults)
    successCount = sum(cellfun(@(x) strcmp(x.status, 'success'), groupResults));
    warningCount = sum(cellfun(@(x) strcmp(x.status, 'warning'), groupResults));
    errorCount = sum(cellfun(@(x) strcmp(x.status, 'error'), groupResults));
end

function saveLogWithBuffer(logFileName, logBuffer)
    % Save log with buffer
    
    try
        fid = fopen(logFileName, 'w');
        if fid == -1
            warning('Could not create log file: %s', logFileName);
            return;
        end
        
        % Write buffered output
        for i = 1:length(logBuffer)
            fprintf(fid, '%s\n', logBuffer{i});
        end
        
        fclose(fid);
        
    catch ME
        fprintf(2, 'Error writing log file: %s\n', ME.message); % Option 1: fprintf to stderr
        
        if exist('fid', 'var') && fid ~= -1
            fclose(fid);
        end
    end
end

function createDirectoriesIfNeeded(directories)
    for i = 1:length(directories)
        if ~exist(directories{i}, 'dir')
            mkdir(directories{i});
        end
    end
end
