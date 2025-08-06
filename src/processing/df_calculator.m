function calculator = df_calculator()
    % DF_CALCULATOR - Simplified entry point that delegates to GPU processor
    % 
    % This module now focuses on the interface while GPU processing is handled
    % by the dedicated gpu_processor module
    
    calculator.calculate = @calculateDF;
    calculator.calculateBatch = @calculateBatchDF;
    calculator.shouldUseGPU = @shouldUseGPU;
end

function [dF_values, standardDeviations, gpuUsed] = calculateDF(traces, hasGPU, gpuInfo)
    % Main dF/F calculation interface
    % 
    % OUTPUTS:
    %   dF_values - dF/F traces [frames x ROIs]
    %   standardDeviations - baseline standard deviations for each ROI (for thresholding)
    %   gpuUsed - boolean indicating if GPU was used
    
    cfg = GluSnFRConfig();
    
    % Delegate to GPU processor
    gpu_proc = gpu_processor();
    [dF_values, standardDeviations, gpuUsed] = gpu_proc.calculate(traces, hasGPU, gpuInfo, cfg);
end

function [batchResults, processingTimes] = calculateBatchDF(tracesCell, hasGPU, gpuInfo)
    % Batch dF/F calculation interface
    
    cfg = GluSnFRConfig();
    
    % Delegate to GPU processor
    gpu_proc = gpu_processor();
    [batchResults, processingTimes] = gpu_proc.calculateBatch(tracesCell, hasGPU, gpuInfo, cfg);
end

function useGPU = shouldUseGPU(dataSize, hasGPU, gpuInfo)
    % GPU decision interface
    
    cfg = GluSnFRConfig();
    
    % Delegate to GPU processor
    gpu_proc = gpu_processor();
    useGPU = gpu_proc.shouldUseGPU(dataSize, hasGPU, gpuInfo, cfg);
end