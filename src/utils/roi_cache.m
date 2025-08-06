function cache_manager = roi_cache()
    % ROI_CACHE - Dedicated ROI cache management module
    % 
    % This module handles all ROI cache creation, validation, and data retrieval
    % Separates cache concerns from plotting logic for better modularity
    
    cache_manager.create = @createROICache;
    cache_manager.validate = @validateROICache;
    cache_manager.retrieve = @retrieveROIData;
    cache_manager.isEmpty = @isCacheEmpty;
    cache_manager.getROINumbers = @getROINumbers;
    cache_manager.hasFilteringStats = @hasFilteringStats;
end

function roiCache = createROICache(roiInfo, organizedData, experimentType, varargin)
    % CREATE_ROI_CACHE - Main cache creation function
    % 
    % INPUTS:
    %   roiInfo - ROI information structure with filtering statistics
    %   organizedData - Organized data table/structure
    %   experimentType - '1AP' or 'PPF'
    %   varargin - Optional parameters
    
    if nargin < 3
        experimentType = roiInfo.experimentType;
    end
    
    cfg = GluSnFRConfig();
    
    % Initialize cache structure
    roiCache = initializeCache(experimentType);
    
    try
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    Creating ROI cache for %s experiment...\n', experimentType);
        end
        
        % STEP 1: Extract ROI numbers from organized data
        roiNumbers = extractROINumbersFromData(organizedData, experimentType, cfg);
        
        if isempty(roiNumbers)
            if cfg.debug.ENABLE_PLOT_DEBUG
                fprintf('    ERROR: No ROI numbers found in organized data\n');
            end
            return;
        end
        
        % STEP 2: Set up basic cache structure
        roiCache = setupBasicCache(roiCache, roiNumbers);
        
        % STEP 3: Load filtering statistics if available
        if isfield(roiInfo, 'filteringStats') && ...
           isstruct(roiInfo.filteringStats) && ...
           isfield(roiInfo.filteringStats, 'available') && ...
           roiInfo.filteringStats.available
            
            roiCache = loadFilteringStatistics(roiCache, roiInfo.filteringStats, cfg);
        else
            if cfg.debug.ENABLE_PLOT_DEBUG
                fprintf('    No filtering statistics available\n');
            end
        end
        
        % STEP 4: Validate cache completeness
        roiCache.valid = validateROICache(roiCache);
        
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    ROI cache: %d ROIs, filtering stats = %s, valid = %s\n', ...
                    length(roiCache.numbers), string(roiCache.hasFilteringStats), string(roiCache.valid));
        end
        
    catch ME
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    Cache creation failed: %s\n', ME.message);
        end
        roiCache.valid = false;
        roiCache.errorMessage = ME.message;
    end
end
% UPDATED: Use ROI cache module for cache creation
function roiCache = createROICacheFixed(roiInfo, organizedData, averagedData)
    % UPDATED: Use dedicated ROI cache module for cache management
    
    cfg = GluSnFRConfig();
    
    if cfg.debug.ENABLE_PLOT_DEBUG
        fprintf('    Creating ROI cache using dedicated cache module...\n');
    end
    
    try
        % Use the dedicated ROI cache module
        cache_manager = roi_cache();
        roiCache = cache_manager.create(roiInfo, organizedData, roiInfo.experimentType);
        
        if cfg.debug.ENABLE_PLOT_DEBUG
            if roiCache.valid
                fprintf('    ROI cache created successfully: %d ROIs, filtering stats = %s\n', ...
                        length(cache_manager.getROINumbers(roiCache)), ...
                        string(cache_manager.hasFilteringStats(roiCache)));
            else
                fprintf('    ROI cache creation failed: %s\n', roiCache.errorMessage);
            end
        end
        
    catch ME
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    ROI cache module error: %s\n', ME.message);
        end
        
        % Create empty cache as fallback
        roiCache = struct();
        roiCache.valid = false;
        roiCache.experimentType = roiInfo.experimentType;
        roiCache.hasFilteringStats = false;
        roiCache.numbers = [];
        roiCache.errorMessage = ME.message;
    end
end
function roiCache = initializeCache(experimentType)
    % Initialize empty cache structure
    
    roiCache = struct();
    roiCache.valid = false;
    roiCache.experimentType = experimentType;
    roiCache.hasFilteringStats = false;
    roiCache.numbers = [];
    roiCache.numberToIndex = [];
    roiCache.createdAt = datetime('now');
    roiCache.errorMessage = '';
    
    % Initialize filtering statistics containers
    roiCache.noiseMap = [];
    roiCache.upperThresholds = [];
    roiCache.lowerThresholds = [];
    roiCache.basicThresholds = [];
    roiCache.standardDeviations = []; % NEW: For SD-based processing
end

function roiNumbers = extractROINumbersFromData(organizedData, experimentType, cfg)
    % Extract ROI numbers from organized data based on experiment type
    
    utils = string_utils(cfg);
    roiNumbers = [];
    
    if strcmp(experimentType, '1AP')
        % 1AP: Extract from table column names
        if istable(organizedData) && width(organizedData) > 1
            varNames = organizedData.Properties.VariableNames(2:end); % Skip Frame column
            
            for i = 1:length(varNames)
                roiMatch = regexp(varNames{i}, 'ROI(\d+)_T', 'tokens');
                if ~isempty(roiMatch)
                    roiNumbers(end+1) = str2double(roiMatch{1}{1});
                end
            end
        end
        
    elseif strcmp(experimentType, 'PPF')
        % PPF: Extract from structured data
        if isstruct(organizedData)
            % Try different data fields in order of preference
            dataFields = {'allData', 'bothPeaks', 'singlePeak'};
            
            for fieldIdx = 1:length(dataFields)
                if isfield(organizedData, dataFields{fieldIdx}) && ...
                   istable(organizedData.(dataFields{fieldIdx})) && ...
                   width(organizedData.(dataFields{fieldIdx})) > 1
                    
                    varNames = organizedData.(dataFields{fieldIdx}).Properties.VariableNames(2:end);
                    
                    for i = 1:length(varNames)
                        roiMatch = regexp(varNames{i}, 'ROI(\d+)', 'tokens');
                        if ~isempty(roiMatch)
                            roiNumbers(end+1) = str2double(roiMatch{1}{1});
                        end
                    end
                    
                    if ~isempty(roiNumbers)
                        break; % Use first available data field
                    end
                end
            end
        end
    end
    
    % Remove duplicates and sort
    if ~isempty(roiNumbers)
        roiNumbers = unique(roiNumbers);
        roiNumbers = sort(roiNumbers);
    end
end

function roiCache = setupBasicCache(roiCache, roiNumbers)
    % Set up basic cache structure with ROI numbers
    
    roiCache.numbers = roiNumbers;
    
    % Create number-to-index mapping
    roiCache.numberToIndex = containers.Map('KeyType', 'int32', 'ValueType', 'int32');
    for i = 1:length(roiNumbers)
        roiCache.numberToIndex(roiNumbers(i)) = i;
    end
end

function roiCache = loadFilteringStatistics(roiCache, filteringStats, cfg)
    % Load filtering statistics into cache
    
    if cfg.debug.ENABLE_PLOT_DEBUG
        fprintf('    Loading filtering statistics...\n');
    end
    
    % Check that all required maps are present
    requiredMaps = {'roiNoiseMap', 'roiUpperThresholds', 'roiLowerThresholds', 'roiBasicThresholds'};
    allMapsPresent = true;
    
    for i = 1:length(requiredMaps)
        mapName = requiredMaps{i};
        if ~isfield(filteringStats, mapName) || ...
           ~isa(filteringStats.(mapName), 'containers.Map') || ...
           isempty(filteringStats.(mapName))
            
            if cfg.debug.ENABLE_PLOT_DEBUG
                fprintf('    ERROR: %s missing or invalid\n', mapName);
            end
            allMapsPresent = false;
            break;
        end
    end
    
    if allMapsPresent
        % Store the maps directly
        roiCache.hasFilteringStats = true;
        roiCache.noiseMap = filteringStats.roiNoiseMap;
        roiCache.upperThresholds = filteringStats.roiUpperThresholds;
        roiCache.lowerThresholds = filteringStats.roiLowerThresholds;
        roiCache.basicThresholds = filteringStats.roiBasicThresholds;
        
        % NEW: Load standard deviations if available
        if isfield(filteringStats, 'roiStandardDeviations') && ...
           isa(filteringStats.roiStandardDeviations, 'containers.Map')
            roiCache.standardDeviations = filteringStats.roiStandardDeviations;
        end
        
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    Successfully loaded filtering statistics:\n');
            fprintf('      Noise classifications: %d ROIs\n', length(roiCache.noiseMap));
            fprintf('      Upper thresholds: %d ROIs\n', length(roiCache.upperThresholds));
            fprintf('      Lower thresholds: %d ROIs\n', length(roiCache.lowerThresholds));
            fprintf('      Basic thresholds: %d ROIs\n', length(roiCache.basicThresholds));
            
            if ~isempty(roiCache.standardDeviations)
                fprintf('      Standard deviations: %d ROIs\n', length(roiCache.standardDeviations));
            end
            
            % Sample a few entries for debugging
            roiKeys = keys(roiCache.noiseMap);
            for i = 1:min(3, length(roiKeys))
                roiNum = roiKeys{i};
                noise = roiCache.noiseMap(roiNum);
                upper = roiCache.upperThresholds(roiNum);
                basic = roiCache.basicThresholds(roiNum);
                
                sdText = '';
                if ~isempty(roiCache.standardDeviations) && isKey(roiCache.standardDeviations, roiNum)
                    sd = roiCache.standardDeviations(roiNum);
                    sdText = sprintf(', SD=%.4f', sd);
                end
                
                fprintf('        ROI %d: %s noise, upper=%.4f, basic=%.4f%s\n', ...
                        roiNum, noise, upper, basic, sdText);
            end
        end
    else
        roiCache.hasFilteringStats = false;
        roiCache.errorMessage = 'Incomplete filtering statistics';
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    Cannot load filtering statistics - incomplete data\n');
        end
    end
end

function isValid = validateROICache(roiCache)
    % Validate that ROI cache contains all required data
    
    isValid = false;
    
    try
        % Basic structure validation
        if ~isstruct(roiCache) || isempty(roiCache.numbers)
            return;
        end
        
        % Check number-to-index mapping
        if ~isa(roiCache.numberToIndex, 'containers.Map') || ...
           length(roiCache.numberToIndex) ~= length(roiCache.numbers)
            return;
        end
        
        % If filtering statistics are claimed to be available, validate them
        if roiCache.hasFilteringStats
            requiredMaps = {'noiseMap', 'upperThresholds', 'lowerThresholds', 'basicThresholds'};
            
            for i = 1:length(requiredMaps)
                mapName = requiredMaps{i};
                if ~isfield(roiCache, mapName) || ...
                   ~isa(roiCache.(mapName), 'containers.Map') || ...
                   isempty(roiCache.(mapName))
                    return;
                end
            end
            
            % Verify that we have data for at least some ROIs
            if length(roiCache.noiseMap) == 0
                return;
            end
            
            % Check for reasonable overlap between cache ROIs and filtering data
            roiKeysInNoise = cell2mat(keys(roiCache.noiseMap));
            commonROIs = intersect(roiCache.numbers, roiKeysInNoise);
            if isempty(commonROIs)
                return;
            end
        end
        
        isValid = true;
        
    catch ME
        % Validation error
        roiCache.errorMessage = sprintf('Validation error: %s', ME.message);
        isValid = false;
    end
end

function [roiNoiseLevel, upperThreshold, lowerThreshold, basicThreshold, standardDeviation] = retrieveROIData(roiCache, roiNum)
    % RETRIEVE_ROI_DATA - Get all data for a specific ROI from cache
    % 
    % INPUTS:
    %   roiCache - Validated ROI cache structure
    %   roiNum - ROI number to retrieve
    %
    % OUTPUTS:
    %   roiNoiseLevel - 'low', 'high', or 'unknown'
    %   upperThreshold - Schmitt upper threshold (NaN if not available)
    %   lowerThreshold - Schmitt lower threshold (NaN if not available) 
    %   basicThreshold - Display threshold for plots (NaN if not available)
    %   standardDeviation - Original SD (NaN if not available)
    
    % Initialize defaults
    roiNoiseLevel = 'unknown';
    upperThreshold = NaN;
    lowerThreshold = NaN;
    basicThreshold = NaN;
    standardDeviation = NaN;
    
    % ONLY use cache data - NO CALCULATIONS OR FALLBACKS
    if roiCache.valid && roiCache.hasFilteringStats
        try
            % Retrieve noise classification
            if isKey(roiCache.noiseMap, roiNum)
                roiNoiseLevel = roiCache.noiseMap(roiNum);
            end
            
            % Retrieve upper threshold
            if isKey(roiCache.upperThresholds, roiNum)
                upperThreshold = roiCache.upperThresholds(roiNum);
            end
            
            % Retrieve lower threshold
            if isKey(roiCache.lowerThresholds, roiNum)
                lowerThreshold = roiCache.lowerThresholds(roiNum);
            end
            
            % Retrieve basic threshold (for display)
            if isKey(roiCache.basicThresholds, roiNum)
                basicThreshold = roiCache.basicThresholds(roiNum);
            end
            
            % NEW: Retrieve standard deviation if available
            if ~isempty(roiCache.standardDeviations) && ...
               isKey(roiCache.standardDeviations, roiNum)
                standardDeviation = roiCache.standardDeviations(roiNum);
            end
            
        catch ME
            % Cache lookup failed - return defaults
            cfg = GluSnFRConfig();
            if cfg.debug.ENABLE_PLOT_DEBUG
                fprintf('    Cache lookup failed for ROI %d: %s\n', roiNum, ME.message);
            end
        end
    end
end

function isEmpty = isCacheEmpty(roiCache)
    % Check if cache is empty or invalid
    
    isEmpty = ~roiCache.valid || isempty(roiCache.numbers) || ~roiCache.hasFilteringStats;
end

function roiNumbers = getROINumbers(roiCache)
    % Get all ROI numbers in the cache
    
    if roiCache.valid
        roiNumbers = roiCache.numbers;
    else
        roiNumbers = [];
    end
end

function hasStats = hasFilteringStats(roiCache)
    % Check if cache has filtering statistics
    
    hasStats = roiCache.valid && roiCache.hasFilteringStats;
end