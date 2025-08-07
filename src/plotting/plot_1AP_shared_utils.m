function sharedUtils = plot_1AP_shared_utils()
    % PLOT_1AP_SHARED_UTILS - Shared utilities for 1AP plotting modules
    % 
    % SHARED RESPONSIBILITIES:
    % - Common validation functions
    % - Text formatting utilities
    % - Cache management helpers
    
    sharedUtils.validateTaskAndCache = @validateTaskAndCache;
    sharedUtils.createNoiseLevelDisplayText = @createNoiseLevelDisplayText;
    sharedUtils.titleCase = @title_case;
    sharedUtils.calculateNoiseSummary = @calculateNoiseSummary;
end

function isValid = validateTaskAndCache(task, config)
    % Centralized task and cache validation
    
    isValid = false;
    
    if ~isstruct(task) || ~isfield(task, 'type') || ~isfield(task, 'roiCache')
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Invalid task structure\n');
        end
        return;
    end
    
    if isempty(task.roiCache) || ~task.roiCache.valid
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    Invalid or missing ROI cache\n');
        end
        return;
    end
    
    isValid = true;
end

function noiseLevelText = createNoiseLevelDisplayText(roiNoiseLevel)
    % Create meaningful noise level display text
    
    switch lower(roiNoiseLevel)
        case 'low'
            noiseLevelText = ' (Low)';
        case 'high'
            noiseLevelText = ' (High)';
        case 'unknown'
            noiseLevelText = ' (?)';
        otherwise
            noiseLevelText = ' (?)';
    end
end

function titleStr = title_case(str)
    % Convert string to title case
    
    words = strsplit(str, '_');
    titleStr = strjoin(cellfun(@(x) [upper(x(1)), lower(x(2:end))], words, 'UniformOutput', false), ' ');
end

function noiseSummary = calculateNoiseSummary(roiCache)
    % Calculate descriptive noise level summary for title
    
    noiseSummary = '';
    
    try
        cache_manager = roi_cache();
        
        if cache_manager.hasFilteringStats(roiCache)
            roiNumbers = cache_manager.getROINumbers(roiCache);
            lowCount = 0;
            highCount = 0;
            
            for i = 1:length(roiNumbers)
                [roiNoiseLevel, ~, ~, ~, ~] = cache_manager.retrieve(roiCache, roiNumbers(i));
                if strcmp(roiNoiseLevel, 'low')
                    lowCount = lowCount + 1;
                elseif strcmp(roiNoiseLevel, 'high')
                    highCount = highCount + 1;
                end
            end
            
            if lowCount > 0 && highCount > 0
                noiseSummary = sprintf(' (%dL, %dH)', lowCount, highCount);
            elseif lowCount > 0
                noiseSummary = sprintf(' (%d Low)', lowCount);
            elseif highCount > 0
                noiseSummary = sprintf(' (%d High)', highCount);
            end
        end
        
    catch
        % Silent failure - just don't add noise summary
    end
end