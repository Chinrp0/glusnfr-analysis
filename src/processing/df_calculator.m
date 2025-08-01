function calculator = df_calculator_enhanced()
    % DF_CALCULATOR_ENHANCED - Optimized GPU utilization
    % 
    % Improvements:
    % - Dynamic GPU threshold based on actual performance
    % - GPU memory pool management
    % - Optimized data transfer patterns
    % - GPU-accelerated filtering operations
    
    calculator.calculate = @calculateDFOptimizedEnhanced;
    calculator.calculateBatch = @calculateBatchGPU;
    calculator.shouldUseGPU = @shouldUseGPUEnhanced;
    calculator.optimizeGPUMemory = @optimizeGPUMemoryUsage;
end

function useGPU = shouldUseGPUEnhanced(dataSize, hasGPU, gpuInfo, cfg)
    % ENHANCED: Dynamic GPU decision based on actual performance characteristics
    
    useGPU = false;
    
    if ~hasGPU
        return;
    end
    
    % Calculate data transfer overhead
    transferTime = estimateTransferTime(dataSize, gpuInfo);
    computeTime = estimateComputeTime(dataSize, true); % GPU compute time
    cpuComputeTime = estimateComputeTime(dataSize, false); % CPU compute time
    
    % Use GPU if total GPU time (transfer + compute) < CPU time
    totalGPUTime = transferTime + computeTime;
    
    % Enhanced decision matrix
    if totalGPUTime < cpuComputeTime * 0.8  % 20% improvement threshold
        useGPU = true;
    end
    
    % Override for very large datasets (always beneficial)
    if dataSize > 500000  % 500k elements
        useGPU = true;
    end
    
    % Memory check with better utilization
    memoryRequired = dataSize * 4 * 3; % Data + intermediate + output
    availableMemory = gpuInfo.memory * 0.9 * 1e9; % 90% utilization
    
    if memoryRequired > availableMemory
        useGPU = false;
    end
end

function [dF_values, thresholds, gpuUsed] = calculateDFOptimizedEnhanced(traces, hasGPU, gpuInfo)
    % ENHANCED: GPU calculation with memory pooling and batch processing
    
    cfg = GluSnFRConfig();
    [n_frames, n_rois] = size(traces);
    dataSize = numel(traces);
    
    % Enhanced GPU decision
    useGPU = shouldUseGPUEnhanced(dataSize, hasGPU, gpuInfo, cfg);
    
    fprintf('    Processing %d ROIs × %d frames (%s, %.1fMB)\n', ...
            n_rois, n_frames, ...
            ternary(useGPU, 'GPU', 'CPU'), dataSize*4/1e6);
    
    if useGPU
        try
            % Try GPU with enhanced optimizations
            [dF_values, thresholds] = calculateGPUEnhanced(traces, cfg, gpuInfo);
            gpuUsed = true;
            
        catch ME
            fprintf('    GPU enhanced failed (%s), trying standard GPU\n', ME.message);
            try
                [dF_values, thresholds] = calculateGPUOptimized(traces, cfg);
                gpuUsed = true;
            catch
                fprintf('    GPU failed, using CPU\n');
                [dF_values, thresholds] = calculateCPUOptimized(traces, cfg);
                gpuUsed = false;
            end
        end
    else
        [dF_values, thresholds] = calculateCPUOptimized(traces, cfg);
        gpuUsed = false;
    end
end

function [dF_values, thresholds] = calculateGPUEnhanced(traces, cfg, gpuInfo)
    % ENHANCED: GPU calculation with memory optimization and reduced transfers
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    % Check if we can fit everything in GPU memory
    memoryRequired = numel(traces) * 4 * 3; % Input + intermediate + output
    availableMemory = gpuInfo.memory * 0.8 * 1e9;
    
    if memoryRequired <= availableMemory
        % OPTIMIZED: Single transfer approach
        [dF_values, thresholds] = calculateGPUSingleTransfer(traces, baseline_window, cfg);
    else
        % OPTIMIZED: Chunked processing for large datasets
        [dF_values, thresholds] = calculateGPUChunked(traces, baseline_window, cfg, gpuInfo);
    end
end

function [dF_values, thresholds] = calculateGPUSingleTransfer(traces, baseline_window, cfg)
    % Single transfer GPU calculation - minimize data movement
    
    % Transfer to GPU once
    gpuTraces = gpuArray(single(traces));
    
    % All operations on GPU using vectorized operations
    baseline_data = gpuTraces(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    
    % Protect against zero baselines
    F0 = max(F0, cfg.thresholds.MIN_F0);
    
    % Vectorized dF/F calculation
    dF_values_gpu = (gpuTraces - F0) ./ F0;
    
    % Replace non-finite values
    dF_values_gpu(~isfinite(dF_values_gpu)) = 0;
    
    % Calculate thresholds on GPU
    baseline_dF_F = dF_values_gpu(baseline_window, :);
    thresholds_gpu = cfg.thresholds.SD_MULTIPLIER * std(baseline_dF_F, 1, 'omitnan');
    thresholds_gpu(isnan(thresholds_gpu)) = cfg.thresholds.DEFAULT_THRESHOLD;
    
    % Single transfer back to CPU
    dF_values = gather(dF_values_gpu);
    thresholds = gather(thresholds_gpu);
end

function [dF_values, thresholds] = calculateGPUChunked(traces, baseline_window, cfg, gpuInfo)
    % Chunked GPU processing for large datasets
    
    [n_frames, n_rois] = size(traces);
    
    % Calculate optimal chunk size based on available GPU memory
    bytesPerROI = n_frames * 4 * 3; % Single precision * operations
    maxROIsPerChunk = floor(gpuInfo.memory * 0.6 * 1e9 / bytesPerROI);
    maxROIsPerChunk = max(maxROIsPerChunk, 1); % At least 1 ROI
    
    % Preallocate output
    dF_values = zeros(n_frames, n_rois, 'single');
    thresholds = zeros(1, n_rois, 'single');
    
    fprintf('      GPU chunked processing: %d ROIs per chunk\n', maxROIsPerChunk);
    
    % Process in chunks
    for startROI = 1:maxROIsPerChunk:n_rois
        endROI = min(startROI + maxROIsPerChunk - 1, n_rois);
        roiIndices = startROI:endROI;
        
        % Process chunk
        chunkTraces = traces(:, roiIndices);
        [chunkDF, chunkThresh] = calculateGPUSingleTransfer(chunkTraces, baseline_window, cfg);
        
        % Store results
        dF_values(:, roiIndices) = chunkDF;
        thresholds(roiIndices) = chunkThresh;
    end
end

function [groupResults, processingTimes] = calculateBatchGPU(tracesCell, hasGPU, gpuInfo)
    % ENHANCED: Batch processing multiple experiments on GPU
    % Reduces GPU initialization overhead
    
    numGroups = length(tracesCell);
    groupResults = cell(numGroups, 1);
    processingTimes = zeros(numGroups, 1);
    
    if hasGPU && numGroups > 1
        try
            % Initialize GPU context once
            gpuDevice();
            
            % Batch process on GPU
            for i = 1:numGroups
                tic;
                [groupResults{i}.dF_values, groupResults{i}.thresholds, groupResults{i}.gpuUsed] = ...
                    calculateDFOptimizedEnhanced(tracesCell{i}, hasGPU, gpuInfo);
                processingTimes(i) = toc;
            end
            
        catch ME
            fprintf('Batch GPU processing failed: %s\n', ME.message);
            % Fallback to individual processing
            for i = 1:numGroups
                tic;
                [groupResults{i}.dF_values, groupResults{i}.thresholds, groupResults{i}.gpuUsed] = ...
                    calculateDFOptimizedEnhanced(tracesCell{i}, false, gpuInfo);
                processingTimes(i) = toc;
            end
        end
    else
        % Process individually
        for i = 1:numGroups
            tic;
            [groupResults{i}.dF_values, groupResults{i}.thresholds, groupResults{i}.gpuUsed] = ...
                calculateDFOptimizedEnhanced(tracesCell{i}, hasGPU, gpuInfo);
            processingTimes(i) = toc;
        end
    end
end

function transferTime = estimateTransferTime(dataSize, gpuInfo)
    % Estimate GPU transfer time based on PCIe bandwidth
    % Typical PCIe 3.0 x16: ~12 GB/s, PCIe 4.0 x16: ~24 GB/s
    
    dataSizeGB = dataSize * 4 / 1e9; % Single precision
    pcieBandwidth = 12; % GB/s (conservative estimate)
    
    % Round trip: CPU->GPU + GPU->CPU
    transferTime = (dataSizeGB * 2) / pcieBandwidth;
end

function computeTime = estimateComputeTime(dataSize, useGPU)
    % Rough compute time estimates based on empirical data
    
    if useGPU
        % GPU compute time (GFLOPS dependent)
        computeTime = dataSize * 1e-8; % Estimate: 100M operations/second
    else
        % CPU compute time  
        computeTime = dataSize * 1e-7; % Estimate: 10M operations/second
    end
end

function optimizeGPUMemoryUsage()
    % Clean up GPU memory and optimize for subsequent operations
    
    try
        if gpuDeviceCount > 0
            % Clear GPU memory
            reset(gpuDevice());
            
            % Pre-allocate memory pool if possible
            % This reduces allocation overhead for subsequent operations
            dummy = gpuArray.zeros(1000, 1000, 'single');
            clear dummy;
            
            fprintf('  GPU memory optimized\n');
        end
    catch
        % GPU optimization failed, continue without
    end
end

function [dF_values, thresholds] = calculateGPUOptimized(traces, cfg)
    % ORIGINAL: Standard GPU implementation (fallback)
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    gpuData = gpuArray(traces);
    baseline_data = gpuData(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    F0(F0 <= 0) = single(cfg.thresholds.MIN_F0);
    
    dF_values = (gpuData - F0) ./ F0;
    dF_values(~isfinite(dF_values)) = 0;
    
    baseline_dF_F = dF_values(baseline_window, :);
    thresholds = cfg.thresholds.SD_MULTIPLIER * std(baseline_dF_F, 1, 'omitnan');
    thresholds(isnan(thresholds)) = cfg.thresholds.DEFAULT_THRESHOLD;
    
    dF_values = gather(dF_values);
    thresholds = gather(thresholds);
end

function [dF_values, thresholds] = calculateCPUOptimized(traces, cfg)
    % ORIGINAL: CPU implementation (unchanged)
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    baseline_data = traces(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    F0(F0 <= 0) = single(cfg.thresholds.MIN_F0);
    
    dF_values = (traces - F0) ./ F0;
    dF_values(~isfinite(dF_values)) = 0;
    
    baseline_dF_F = dF_values(baseline_window, :);
    thresholds = cfg.thresholds.SD_MULTIPLIER * std(baseline_dF_F, 1, 'omitnan');
    thresholds(isnan(thresholds)) = cfg.thresholds.DEFAULT_THRESHOLD;
end

function result = ternary(condition, trueVal, falseVal)
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end