function calculator = df_calculator()
    % DF_CALCULATOR - Optimized dF/F calculation module
    % 
    % This module provides GPU-accelerated and CPU-optimized dF/F
    % calculations with proper memory management and error handling.
    
    calculator.calculate = @calculateDFOptimized;
    calculator.calculateCPU = @calculateCPUOptimized;
    calculator.calculateGPU = @calculateGPUOptimized;
    calculator.validateInputs = @validateCalculationInputs;
    calculator.shouldUseGPU = @shouldUseGPU;  % NEW: Expose GPU decision logic
end

function [dF_values, thresholds, gpuUsed] = calculateDFOptimized(traces, hasGPU, gpuInfo)
    % Main optimized dF/F calculation with automatic GPU/CPU selection
    
    cfg = GluSnFRConfig();
    
    % Validate inputs
    if ~validateCalculationInputs(traces)
        error('Invalid input data for dF/F calculation');
    end
    
    % Convert to single precision for memory efficiency
    traces = single(traces);
    [n_frames, n_rois] = size(traces);
    
    % Use the new shouldUseGPU function for decision making
    useGPU = shouldUseGPU(numel(traces), hasGPU, gpuInfo, cfg);
    
    fprintf('    Processing %d ROIs × %d frames (%s)\n', n_rois, n_frames, ...
            ternary(useGPU, 'GPU', 'CPU'));
    
    if useGPU
        try
            [dF_values, thresholds] = calculateGPUOptimized(traces, cfg);
            gpuUsed = true;
            
        catch ME
            fprintf('    GPU calculation failed (%s), falling back to CPU\n', ME.message);
            [dF_values, thresholds] = calculateCPUOptimized(traces, cfg);
            gpuUsed = false;
        end
    else
        [dF_values, thresholds] = calculateCPUOptimized(traces, cfg);
        gpuUsed = false;
    end
    
    fprintf('    Calculated dF/F for %d ROIs (GPU: %s)\n', n_rois, string(gpuUsed));
end

function useGPU = shouldUseGPU(dataSize, hasGPU, gpuInfo, cfg)
    % Determine whether to use GPU based on data size and available memory
    %
    % INPUTS:
    %   dataSize - Number of elements in the data array
    %   hasGPU   - Boolean indicating if GPU is available
    %   gpuInfo  - Structure with GPU information (including .memory field in GB)
    %   cfg      - Configuration structure with processing parameters
    %
    % OUTPUTS:
    %   useGPU   - Boolean indicating whether GPU should be used
    %
    % LOGIC:
    %   - GPU must be available
    %   - Data size must exceed minimum threshold
    %   - Required memory must fit in available GPU memory (with safety margin)
    
    useGPU = false;
    
    % Check basic availability
    if ~hasGPU
        return;
    end
    
    % Check data size threshold
    if dataSize < cfg.processing.GPU_MIN_DATA_SIZE
        return;
    end
    
    % Check memory requirements
    memoryRequired = dataSize * 4; % bytes for single precision
    availableMemory = gpuInfo.memory * cfg.processing.GPU_MEMORY_FRACTION * 1e9; % GB to bytes
    
    if memoryRequired > availableMemory
        return;
    end
    
    % All checks passed
    useGPU = true;
end

function [dF_values, thresholds] = calculateGPUOptimized(traces, cfg)
    % GPU-optimized dF/F calculation
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    % Transfer to GPU
    gpuData = gpuArray(traces);
    
    % Vectorized baseline calculation on GPU
    baseline_data = gpuData(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    
    % Protect against zero/negative baselines
    F0(F0 <= 0) = single(cfg.thresholds.MIN_F0);
    
    % Vectorized dF/F calculation using implicit expansion (MATLAB R2016b+)
    dF_values = (gpuData - F0) ./ F0;
    
    % Handle edge cases
    dF_values(~isfinite(dF_values)) = 0;
    
    % Calculate thresholds (3×SD of baseline dF/F)
    baseline_dF_F = dF_values(baseline_window, :);
    thresholds = cfg.thresholds.SD_MULTIPLIER * std(baseline_dF_F, 1, 'omitnan');
    thresholds(isnan(thresholds)) = cfg.thresholds.DEFAULT_THRESHOLD;
    
    % Transfer back to CPU
    dF_values = gather(dF_values);
    thresholds = gather(thresholds);
end

function [dF_values, thresholds] = calculateCPUOptimized(traces, cfg)
    % CPU-optimized dF/F calculation with vectorization
    
    baseline_window = cfg.timing.BASELINE_FRAMES;
    
    % Vectorized operations on CPU
    baseline_data = traces(baseline_window, :);
    F0 = mean(baseline_data, 1, 'omitnan');
    F0(F0 <= 0) = single(cfg.thresholds.MIN_F0);
    
    % Efficient dF/F calculation using implicit expansion
    dF_values = (traces - F0) ./ F0;
    dF_values(~isfinite(dF_values)) = 0;
    
    % Vectorized threshold calculation
    baseline_dF_F = dF_values(baseline_window, :);
    thresholds = cfg.thresholds.SD_MULTIPLIER * std(baseline_dF_F, 1, 'omitnan');
    thresholds(isnan(thresholds)) = cfg.thresholds.DEFAULT_THRESHOLD;
end

function isValid = validateCalculationInputs(traces)
    % Validate inputs for dF/F calculation
    
    isValid = false;
    
    if isempty(traces)
        warning('Empty traces provided');
        return;
    end
    
    if ~isnumeric(traces)
        warning('Non-numeric traces provided');
        return;
    end
    
    if size(traces, 1) < 300  % Minimum frames
        warning('Insufficient frames for analysis (need at least 300)');
        return;
    end
    
    if any(all(isnan(traces), 1))
        warning('Some ROIs contain only NaN values');
    end
    
    isValid = true;
end

function result = ternary(condition, trueVal, falseVal)
    % Utility function for ternary operator
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end