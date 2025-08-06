function calculator = df_calculator()
    % DF_CALCULATOR - SIMPLIFIED: Returns standard deviations only
    % 
    % MAJOR CHANGE: No longer calculates "basicThresholds" (3×SD)
    % Returns raw standard deviations for roi_filter.m to use directly
    
    calculator = df_calculator_enhanced();
end

function calculator = df_calculator_enhanced()
    % DF_CALCULATOR_ENHANCED - Optimized GPU utilization with SD-only output
    
    calculator.calculate = @calculateDFOptimizedEnhanced;
    calculator.calculateBatch = @calculateBatchGPU;
    calculator.shouldUseGPU = @shouldUseGPUEnhanced;
    calculator.optimizeGPUMemory = @optimizeGPUMemoryUsage;
end

function [dF_values, standardDeviations, gpuUsed] = calculateDFOptimizedEnhanced(traces, hasGPU, gpuInfo)
    % UPDATED: Calculate dF/F values and return standard deviations (not thresholds)
    
    cfg = GluSnFRConfig();
    [n_frames, n_rois] = size(traces);
    dataSize = numel(traces);
    
    % Enhanced GPU decision
    useGPU = shouldUseGPUEnhanced(dataSize, hasGPU, gpuInfo, cfg);
    
    if useGPU
        try
            % Try GPU with enhanced optimizations
            [dF_values, standardDeviations] = calculateGPUEnhanced(traces, cfg, gpuInfo);
            gpuUsed = true;
            
        catch ME
            try
                [dF_values, standardDeviations] = calculateGPUOptimized(traces, cfg);
                gpuUsed = true;
            catch
                [dF_values, standardDeviations] = calculateCPUOptimized(traces, cfg);
                gpuUsed = false;
            end
        end
    else
        [dF_values, standardDeviations] = calculateCPUOptimized(traces, cfg);
        gpuUsed = false;
    end
end

function [dF_values, standardDeviations] = calculateGPUEnhanced(traces, cfg, gpuInfo)
    % ENHANCED: GPU calculation returning standard deviations only
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    % Check if we can fit everything in GPU memory
    memoryRequired = numel(traces) * 4 * 3; % Input + intermediate + output
    availableMemory = gpuInfo.memory * 0.8 * 1e9;
    
    if memoryRequired <= availableMemory
        % Single transfer approach
        [dF_values, standardDeviations] = calculateGPUSingleTransfer(traces, baseline_window, cfg);
    else
        % Chunked processing for large datasets
        [dF_values, standardDeviations] = calculateGPUChunked(traces, baseline_window, cfg, gpuInfo);
    end
end

function [dF_values, standardDeviations] = calculateGPUSingleTransfer(traces, baseline_window, cfg)
    % UPDATED: Single transfer GPU calculation returning SD only
    
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
    
    % UPDATED: Calculate standard deviations only (no threshold multiplier)
    baseline_dF_F = dF_values_gpu(baseline_window, :);
    standardDeviations_gpu = std(baseline_dF_F, 1, 'omitnan');
    %standardDeviations_gpu(isnan(standardDeviations_gpu)) =
    %cfg.thresholds.DEFAULT_THRESHOLD / cfg.thresholds.SD_MULTIPLIER; %What
    %is this? 
    
    % Single transfer back to CPU
    dF_values = gather(dF_values_gpu);
    standardDeviations = gather(standardDeviations_gpu);
end

function [dF_values, standardDeviations] = calculateGPUChunked(traces, baseline_window, cfg, gpuInfo)
    % UPDATED: Chunked GPU processing returning SD only
    
    [n_frames, n_rois] = size(traces);
    
    % Calculate optimal chunk size based on available GPU memory
    bytesPerROI = n_frames * 4 * 3; % Single precision * operations
    maxROIsPerChunk = floor(gpuInfo.memory * 0.6 * 1e9 / bytesPerROI);
    maxROIsPerChunk = max(maxROIsPerChunk, 1);
    
    % Preallocate output
    dF_values = zeros(n_frames, n_rois, 'single');
    standardDeviations = zeros(1, n_rois, 'single');
    
    % Process in chunks
    for startROI = 1:maxROIsPerChunk:n_rois
        endROI = min(startROI + maxROIsPerChunk - 1, n_rois);
        roiIndices = startROI:endROI;
        
        % Process chunk
        chunkTraces = traces(:, roiIndices);
        [chunkDF, chunkSD] = calculateGPUSingleTransfer(chunkTraces, baseline_window, cfg);
        
        % Store results
        dF_values(:, roiIndices) = chunkDF;
        standardDeviations(roiIndices) = chunkSD;
    end
end

function [dF_values, standardDeviations] = calculateGPUOptimized(traces, cfg)
    % UPDATED: Standard GPU implementation returning SD only
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    gpuData = gpuArray(traces);
    baseline_data = gpuData(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    F0(F0 <= 0) = single(cfg.thresholds.MIN_F0);
    
    dF_values = (gpuData - F0) ./ F0;
    dF_values(~isfinite(dF_values)) = 0;
    
    % UPDATED: Return standard deviations only
    baseline_dF_F = dF_values(baseline_window, :);
    standardDeviations = std(baseline_dF_F, 1, 'omitnan');
    standardDeviations(isnan(standardDeviations)) = cfg.thresholds.DEFAULT_THRESHOLD / cfg.thresholds.SD_MULTIPLIER;
    
    dF_values = gather(dF_values);
    standardDeviations = gather(standardDeviations);
end

function [dF_values, standardDeviations] = calculateCPUOptimized(traces, cfg)
    % UPDATED: CPU implementation returning SD only
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    baseline_data = traces(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    F0(F0 <= 0) = single(cfg.thresholds.MIN_F0);
    
    dF_values = (traces - F0) ./ F0;
    dF_values(~isfinite(dF_values)) = 0;
    
    % UPDATED: Return standard deviations only  
    baseline_dF_F = dF_values(baseline_window, :);
    standardDeviations = std(baseline_dF_F, 1, 'omitnan');
    standardDeviations(isnan(standardDeviations)) = cfg.thresholds.DEFAULT_THRESHOLD / cfg.thresholds.SD_MULTIPLIER;
end

% UNCHANGED: Other functions remain the same
function useGPU = shouldUseGPUEnhanced(dataSize, hasGPU, gpuInfo, cfg)
    % Unchanged - same GPU decision logic
    useGPU = false;
    
    if ~hasGPU
        return;
    end
    
    transferTime = estimateTransferTime(dataSize, gpuInfo);
    computeTime = estimateComputeTime(dataSize, true);
    cpuComputeTime = estimateComputeTime(dataSize, false);
    
    totalGPUTime = transferTime + computeTime;
    
    if totalGPUTime < cpuComputeTime * 0.8
        useGPU = true;
    end
    
    if dataSize > 500000
        useGPU = true;
    end
    
    memoryRequired = dataSize * 4 * 3;
    availableMemory = gpuInfo.memory * 0.9 * 1e9;
    
    if memoryRequired > availableMemory
        useGPU = false;
    end
end

function transferTime = estimateTransferTime(dataSize, gpuInfo)
    dataSizeGB = dataSize * 4 / 1e9;
    pcieBandwidth = 12;
    transferTime = (dataSizeGB * 2) / pcieBandwidth;
end

function computeTime = estimateComputeTime(dataSize, useGPU)
    if useGPU
        computeTime = dataSize * 1e-8;
    else
        computeTime = dataSize * 1e-7;
    end
end

function optimizeGPUMemoryUsage()
    % Unchanged
    try
        if gpuDeviceCount > 0
            reset(gpuDevice());
            dummy = gpuArray.zeros(1000, 1000, 'single');
            clear dummy;
        end
    catch
    end
end