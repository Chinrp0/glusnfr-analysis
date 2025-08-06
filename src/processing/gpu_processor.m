function processor = gpu_processor()
    % GPU_PROCESSOR - High-performance GPU processing for dF/F calculation and ROI filtering
    % 
    % This module handles all GPU operations for the pipeline, including:
    % - dF/F calculation
    % - Standard deviation calculation for thresholds
    % - Potential ROI filtering operations
    
    processor.calculate = @calculateDFOnGPU;
    processor.calculateBatch = @calculateBatchOnGPU;
    processor.shouldUseGPU = @shouldUseGPU;
    processor.optimizeMemory = @optimizeGPUMemory;
    processor.getCapabilities = @getGPUCapabilities;
end

function [dF_values, standardDeviations, gpuUsed] = calculateDFOnGPU(traces, hasGPU, gpuInfo, cfg)
    % Main GPU calculation function - returns both dF/F and standard deviations
    
    dataSize = numel(traces);
    useGPU = shouldUseGPU(dataSize, hasGPU, gpuInfo, cfg);
    
    if useGPU
        try
            [dF_values, standardDeviations] = calculateGPUOptimized(traces, cfg, gpuInfo);
            gpuUsed = true;
        catch ME
            if cfg.debug.ENABLE_PLOT_DEBUG
                fprintf('    GPU calculation failed, falling back to CPU: %s\n', ME.message);
            end
            [dF_values, standardDeviations] = calculateCPU(traces, cfg);
            gpuUsed = false;
        end
    else
        [dF_values, standardDeviations] = calculateCPU(traces, cfg);
        gpuUsed = false;
    end
end

function [batchResults, processingTimes] = calculateBatchOnGPU(tracesCell, hasGPU, gpuInfo, cfg)
    % Batch processing multiple datasets on GPU
    
    numGroups = length(tracesCell);
    batchResults = cell(numGroups, 1);
    processingTimes = zeros(numGroups, 1);
    
    % Initialize GPU context once if using GPU
    if hasGPU && shouldUseBatchGPU(tracesCell, gpuInfo, cfg)
        try
            gpuDevice();
            
            % Process each group
            for i = 1:numGroups
                tic;
                [batchResults{i}.dF_values, batchResults{i}.standardDeviations, batchResults{i}.gpuUsed] = ...
                    calculateDFOnGPU(tracesCell{i}, hasGPU, gpuInfo, cfg);
                processingTimes(i) = toc;
            end
            
        catch ME
            % Fallback to individual CPU processing
            if cfg.debug.ENABLE_PLOT_DEBUG
                fprintf('    Batch GPU processing failed, using CPU: %s\n', ME.message);
            end
            for i = 1:numGroups
                tic;
                [batchResults{i}.dF_values, batchResults{i}.standardDeviations, batchResults{i}.gpuUsed] = ...
                    calculateDFOnGPU(tracesCell{i}, false, gpuInfo, cfg);
                processingTimes(i) = toc;
            end
        end
    else
        % Process individually
        for i = 1:numGroups
            tic;
            [batchResults{i}.dF_values, batchResults{i}.standardDeviations, batchResults{i}.gpuUsed] = ...
                calculateDFOnGPU(tracesCell{i}, hasGPU, gpuInfo, cfg);
            processingTimes(i) = toc;
        end
    end
end

function useGPU = shouldUseGPU(dataSize, hasGPU, gpuInfo, cfg)
    % Enhanced GPU decision logic
    
    useGPU = false;
    
    if ~hasGPU || ~cfg.gpu.ENABLED
        return;
    end
    
    % Check minimum data size threshold
    if dataSize < cfg.gpu.MIN_DATA_SIZE
        return;
    end
    
    % Check memory requirements
    memoryRequired = dataSize * 4 * 3; % Input + intermediate + output (single precision)
    availableMemory = gpuInfo.memory * cfg.gpu.MEMORY_FRACTION * 1e9;
    
    if memoryRequired > availableMemory
        return;
    end
    
    % Estimate performance benefit
    transferTime = estimateTransferTime(dataSize, gpuInfo);
    gpuComputeTime = estimateComputeTime(dataSize, true);
    cpuComputeTime = estimateComputeTime(dataSize, false);
    
    totalGPUTime = transferTime + gpuComputeTime;
    
    % Use GPU if total time is at least 20% better
    if totalGPUTime < cpuComputeTime * 0.8
        useGPU = true;
    end
    
    % Always use GPU for very large datasets
    if dataSize > 500000
        useGPU = true;
    end
end

function useBatchGPU = shouldUseBatchGPU(tracesCell, gpuInfo, cfg)
    % Determine if batch GPU processing is beneficial
    
    useBatchGPU = false;
    
    if length(tracesCell) < 2
        return;
    end
    
    % Calculate total data size
    totalElements = 0;
    for i = 1:length(tracesCell)
        totalElements = totalElements + numel(tracesCell{i});
    end
    
    % Check if total data justifies batch processing
    if totalElements > cfg.gpu.MIN_DATA_SIZE * 3
        useBatchGPU = true;
    end
end

function [dF_values, standardDeviations] = calculateGPUOptimized(traces, cfg, gpuInfo)
    % Optimized GPU calculation
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    % Check if we can fit everything in GPU memory
    memoryRequired = numel(traces) * 4 * 3;
    availableMemory = gpuInfo.memory * cfg.gpu.MEMORY_FRACTION * 1e9;
    
    if memoryRequired <= availableMemory
        % Single transfer approach
        [dF_values, standardDeviations] = calculateGPUSingleTransfer(traces, baseline_window, cfg);
    else
        % Chunked processing for large datasets
        [dF_values, standardDeviations] = calculateGPUChunked(traces, baseline_window, cfg, gpuInfo);
    end
end

function [dF_values, standardDeviations] = calculateGPUSingleTransfer(traces, baseline_window, cfg)
    % Single transfer GPU calculation
    
    % Transfer to GPU once
    gpuTraces = gpuArray(single(traces));
    
    % Calculate baseline statistics
    baseline_data = gpuTraces(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    
    % Protect against zero/negative baselines
    F0 = max(F0, single(1e-6));
    
    % Vectorized dF/F calculation
    dF_values_gpu = (gpuTraces - F0) ./ F0;
    dF_values_gpu(~isfinite(dF_values_gpu)) = 0;
    
    % Calculate standard deviations from baseline dF/F
    baseline_dF_F = dF_values_gpu(baseline_window, :);
    standardDeviations_gpu = std(baseline_dF_F, 1, 'omitnan');
    standardDeviations_gpu(isnan(standardDeviations_gpu)) = single(cfg.thresholds.SD_NOISE_CUTOFF);
    
    % Transfer back to CPU
    dF_values = gather(dF_values_gpu);
    standardDeviations = gather(standardDeviations_gpu);
end

function [dF_values, standardDeviations] = calculateGPUChunked(traces, baseline_window, cfg, gpuInfo)
    % Chunked GPU processing for large datasets
    
    [n_frames, n_rois] = size(traces);
    
    % Calculate optimal chunk size
    bytesPerROI = n_frames * 4 * 3; % Single precision * operations
    maxROIsPerChunk = floor(gpuInfo.memory * cfg.gpu.MEMORY_FRACTION * 1e9 / bytesPerROI);
    maxROIsPerChunk = max(maxROIsPerChunk, 1);
    
    % Preallocate output
    dF_values = zeros(n_frames, n_rois, 'single');
    standardDeviations = zeros(1, n_rois, 'single');
    
    % Process in chunks
    for startROI = 1:maxROIsPerChunk:n_rois
        endROI = min(startROI + maxROIsPerChunk - 1, n_rois);
        roiIndices = startROI:endROI;
        
        chunkTraces = traces(:, roiIndices);
        [chunkDF, chunkSD] = calculateGPUSingleTransfer(chunkTraces, baseline_window, cfg);
        
        dF_values(:, roiIndices) = chunkDF;
        standardDeviations(roiIndices) = chunkSD;
    end
end

function [dF_values, standardDeviations] = calculateCPU(traces, cfg)
    % CPU fallback calculation
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    % Calculate baseline statistics
    baseline_data = traces(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    
    % Protect against zero/negative baselines
    F0(F0 <= 0) = single(1e-6);
    
    % Calculate dF/F
    dF_values = (traces - F0) ./ F0;
    dF_values(~isfinite(dF_values)) = 0;
    
    % Calculate standard deviations from baseline dF/F
    baseline_dF_F = dF_values(baseline_window, :);
    standardDeviations = std(baseline_dF_F, 1, 'omitnan');
    standardDeviations(isnan(standardDeviations)) = single(cfg.thresholds.SD_NOISE_CUTOFF);
end

function transferTime = estimateTransferTime(dataSize, gpuInfo)
    % Estimate GPU transfer time
    
    dataSizeGB = dataSize * 4 / 1e9; % Single precision
    pcieBandwidth = 12; % GB/s (conservative estimate)
    
    % Round trip: CPU->GPU + GPU->CPU
    transferTime = (dataSizeGB * 2) / pcieBandwidth;
end

function computeTime = estimateComputeTime(dataSize, useGPU)
    % Estimate compute time
    
    if useGPU
        % GPU compute time
        computeTime = dataSize * 1e-8; % ~100M operations/second
    else
        % CPU compute time  
        computeTime = dataSize * 1e-7; % ~10M operations/second
    end
end

function optimizeGPUMemory()
    % Clean up GPU memory
    
    try
        if gpuDeviceCount > 0
            reset(gpuDevice());
            
            % Pre-allocate memory pool
            dummy = gpuArray.zeros(1000, 1000, 'single');
            clear dummy;
        end
    catch
        % GPU optimization failed, continue without
    end
end

function capabilities = getGPUCapabilities()
    % Get GPU capabilities for optimization
    
    capabilities = struct();
    capabilities.available = false;
    capabilities.deviceCount = 0;
    capabilities.memory = 0;
    capabilities.name = 'None';
    
    try
        deviceCount = gpuDeviceCount();
        if deviceCount > 0
            gpu = gpuDevice();
            capabilities.available = true;
            capabilities.deviceCount = deviceCount;
            capabilities.memory = gpu.AvailableMemory / 1e9; % GB
            capabilities.name = gpu.Name;
            capabilities.computeCapability = gpu.ComputeCapability;
        end
    catch
        % No GPU available or error occurred
    end
end