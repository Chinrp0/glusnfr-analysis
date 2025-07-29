%% ========================================================================  
%% MODULE 3: src/processing/memory_manager.m
%% ========================================================================

function manager = memory_manager()
    % MEMORY_MANAGER - Optimized memory management utilities
    %
    % This module provides better memory allocation and management
    % for large datasets, preventing out-of-memory errors.
    
    manager.preallocateResults = @preallocateResults;
    manager.estimateMemoryUsage = @estimateMemoryUsage;
    manager.optimizeAllocation = @optimizeAllocation;
    manager.validateMemoryAvailable = @validateMemoryAvailable;
end

function results = preallocateResults(estimatedROIs, estimatedFrames, estimatedTrials, dataType)
    % Pre-allocate result structures with optimal data types
    
    if nargin < 4
        dataType = 'single';
    end
    
    % Safety factor for allocation
    safetyFactor = 1.2;
    maxROIs = ceil(estimatedROIs * safetyFactor);
    
    % Pre-allocate main data arrays
    results = struct();
    results.timeData = NaN(estimatedFrames, 1, dataType);
    results.dFData = NaN(estimatedFrames, maxROIs, dataType);
    results.thresholds = NaN(maxROIs, 1, dataType);
    results.roiNames = cell(maxROIs, 1);
    
    % Pre-allocate metadata arrays
    if nargin >= 3 && ~isempty(estimatedTrials)
        results.trialData = NaN(estimatedFrames, maxROIs, estimatedTrials, dataType);
        results.trialMetadata = repmat(struct('roi', NaN, 'trial', NaN, 'threshold', NaN), maxROIs * estimatedTrials, 1);
    end
    
    % Track allocation info
    results.allocated = struct();
    results.allocated.maxROIs = maxROIs;
    results.allocated.frames = estimatedFrames;
    results.allocated.dataType = dataType;
    results.allocated.estimatedMemoryMB = estimateMemoryUsage(maxROIs, estimatedFrames, estimatedTrials, dataType);
    
    fprintf('    Pre-allocated memory for %d ROIs × %d frames (%.1f MB)\n', ...
            maxROIs, estimatedFrames, results.allocated.estimatedMemoryMB);
end

function memoryMB = estimateMemoryUsage(numROIs, numFrames, numTrials, dataType)
    % Estimate memory usage in MB
    
    switch dataType
        case 'single'
            bytesPerElement = 4;
        case 'double'
            bytesPerElement = 8;
        otherwise
            bytesPerElement = 8; % Default to double
    end
    
    % Calculate memory for main arrays
    mainDataBytes = numROIs * numFrames * bytesPerElement;
    
    % Add memory for trial data if applicable
    if nargin >= 3 && ~isempty(numTrials)
        trialDataBytes = numROIs * numFrames * numTrials * bytesPerElement;
    else
        trialDataBytes = 0;
    end
    
    % Add overhead for metadata and other structures (20% estimate)
    totalBytes = (mainDataBytes + trialDataBytes) * 1.2;
    
    memoryMB = totalBytes / (1024^2);
end

function isAvailable = validateMemoryAvailable(requiredMB)
    % Check if sufficient memory is available
    
    try
        % Get system memory info (Windows-specific)
        [~, systemview] = memory;
        availableMB = systemview.PhysicalMemory.Available / (1024^2);
        
        isAvailable = availableMB > (requiredMB * 1.5); % 50% safety margin
        
        if ~isAvailable
            warning('Insufficient memory: need %.1f MB, have %.1f MB available', ...
                    requiredMB, availableMB);
        end
        
    catch
        % Fallback: assume memory is available
        warning('Could not check memory availability');
        isAvailable = true;
    end
end

function optimizedParams = optimizeAllocation(totalROIs, totalFrames, availableMemoryMB)
    % Optimize allocation parameters based on available memory
    
    % Estimate memory per ROI
    memoryPerROI = estimateMemoryUsage(1, totalFrames, 1, 'single');
    
    % Calculate optimal chunk size
    maxROIsPerChunk = floor(availableMemoryMB / (memoryPerROI * 2)); % 50% safety
    maxROIsPerChunk = max(maxROIsPerChunk, 10); % Minimum chunk size
    maxROIsPerChunk = min(maxROIsPerChunk, totalROIs); % Don't exceed total
    
    optimizedParams = struct();
    optimizedParams.chunkSize = maxROIsPerChunk;
    optimizedParams.numChunks = ceil(totalROIs / maxROIsPerChunk);
    optimizedParams.useChunking = optimizedParams.numChunks > 1;
    optimizedParams.estimatedMemoryPerChunk = memoryPerROI * maxROIsPerChunk;
    
    if optimizedParams.useChunking
        fprintf('    Memory optimization: processing in %d chunks of %d ROIs each\n', ...
                optimizedParams.numChunks, optimizedParams.chunkSize);
    end
end