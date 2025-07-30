function utils = string_utils(config)
    % STRING_UTILS - Optimized string processing utilities
    % 
    % This module centralizes and optimizes all string processing
    % operations used throughout the pipeline, with cached regex
    % patterns for better performance.
    %
    % INPUT:
    %   config - Configuration structure (to avoid circular dependencies)
    
    % Store config for use in internal functions
    if nargin < 1
        % Fallback: load config if not provided (for standalone usage)
        config = GluSnFRConfig();
    end
    
    % Return function handles for all utilities with config closure
    utils.extractGroupKey = @(filename) extractGroupKey(filename, config);
    utils.extractROINumbers = @(roiNames) extractROINumbers(roiNames, config);
    utils.extractTrialInfo = @(filename) extractTrialInfo(filename, config);
    utils.extractTrialOrPPI = @extractTrialOrPPI;  % Standalone function
    utils.extractGenotype = @extractGenotype;
    utils.parseFilename = @(filename) parseFilename(filename, config);
end

function groupKey = extractGroupKey(filename, config)
    % Extract group key with cached patterns from config
    
    groupKey = '';
    
    try
        [~, name, ~] = fileparts(filename);
        
        % Early exit for invalid format
        if ~contains(name, 'CP_')
            return;
        end
        
        if contains(name, 'PPF')
            % PPF logic
            ppfMatch = regexp(name, config.patterns.PPF_TIMEPOINT, 'tokens', 'once');
            if ~isempty(ppfMatch)
                timepoint = ppfMatch{1};
                baseMatch = regexp(name, config.patterns.DOC2B, 'match', 'once');
                if ~isempty(baseMatch)
                    groupKey = sprintf('PPF_%sms%s', timepoint, baseMatch);
                end
            end
        else
            % 1AP logic with cached patterns
            doc2bMatch = regexp(name, config.patterns.DOC2B, 'match', 'once');
            csMatch = regexp(name, config.patterns.COVERSLIP, 'match', 'once');
            expMatch = regexp(name, config.patterns.EXPERIMENT, 'match', 'once');
            
            if ~isempty(doc2bMatch) && ~isempty(csMatch) && ~isempty(expMatch)
                cpIndex = strfind(name, 'CP_');
                csEnd = strfind(name, csMatch) + length(csMatch) - 1;
                baseKey = name(cpIndex:csEnd);
                expType = expMatch(2:end); % Remove underscore
                
                if strcmp(expType, '1AP')
                    groupKey = [baseKey '_1AP'];
                end
            end
        end
        
    catch ME
        warning('Error extracting group key from %s: %s', filename, ME.message);
    end
end

function roiNumbers = extractROINumbers(roiNames, config)
    % FIXED: Extract ROI numbers with robust fallback (matching monolithic version)
    
    numROIs = length(roiNames);
    roiNumbers = NaN(numROIs, 1); % Preallocate for worst case
    validCount = 0;
    
    for i = 1:numROIs
        try
            roiName = char(roiNames{i});
            
            % Primary pattern: ROI with optional separators (case insensitive)
            roiMatch = regexp(roiName, 'roi[_\s]*(\d+)', 'tokens', 'ignorecase');
            if ~isempty(roiMatch)
                roiNum = str2double(roiMatch{1}{1});
                if isfinite(roiNum) && roiNum > 0 && roiNum <= 65535
                    validCount = validCount + 1;
                    roiNumbers(validCount) = roiNum;
                    continue;
                end
            end
            
            % Fallback: find any number in the string (like monolithic version)
            numMatch = regexp(roiName, '(\d+)', 'tokens');
            if ~isempty(numMatch)
                roiNum = str2double(numMatch{end}{1}); % Use last number found
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

function [trialNum, expType, ppiValue, coverslipCell] = extractTrialInfo(filename, config)
    % Extract trial/PPI information with cached patterns
    
    trialNum = NaN;
    expType = '';
    ppiValue = NaN;
    coverslipCell = '';
    
    try
        % Extract coverslip-cell info
        csMatch = regexp(filename, config.patterns.COVERSLIP, 'tokens', 'once');
        if ~isempty(csMatch)
            coverslipCell = sprintf('Cs%s-c%s', csMatch{1}, csMatch{2});
        end
        
        % Determine experiment type and extract trial info
        if contains(filename, '1AP')
            expType = '1AP';
            % Pattern for 1AP trials
            trialPatterns = {'1AP-(\d+)', '1AP_(\d+)', '1AP(\d+)'};
            
            for i = 1:length(trialPatterns)
                trialMatch = regexp(filename, trialPatterns{i}, 'tokens', 'once');
                if ~isempty(trialMatch)
                    trialNum = str2double(trialMatch{1});
                    break;
                end
            end
            
        elseif contains(filename, 'PPF')
            expType = 'PPF';
            % Pattern for PPF trials
            ppfPattern = 'PPF-(\d+)ms-(\d+)';
            ppfMatch = regexp(filename, ppfPattern, 'tokens', 'once');
            
            if ~isempty(ppfMatch)
                ppiValue = str2double(ppfMatch{1});
                trialNum = str2double(ppfMatch{2});
            end
        end
        
        % Validate results
        if ~isfinite(trialNum) || trialNum <= 0
            trialNum = NaN;
        end
        
    catch ME
        warning('Error extracting trial info from %s: %s', filename, ME.message);
    end
end

function [trialNum, expType, ppiValue, coverslipCell] = extractTrialOrPPI(filename)
    % Comprehensive trial/PPI extraction (original implementation from backup)
    % This is standalone to avoid circular dependencies
    
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
            % Pattern matching for 1AP
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
            % Pattern matching for PPF
            ppfPattern = 'PPF-(\d+)ms-(\d+)';
            ppfMatch = regexp(filename, ppfPattern, 'tokens');
            
            if ~isempty(ppfMatch)
                ppiValue = str2double(ppfMatch{1}{1});
                trialNum = str2double(ppfMatch{1}{2});
            end
        end
        
        % Fallback patterns if main extraction fails
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

function genotype = extractGenotype(groupKey)
    % Extract genotype from group key
    
    if contains(groupKey, 'R213W')
        genotype = 'R213W';
    elseif contains(groupKey, 'WT')
        genotype = 'WT';
    else
        genotype = 'Unknown';
    end
end

function info = parseFilename(filename, config)
    % Comprehensive filename parsing
    
    info = struct();
    info.filename = filename;
    info.groupKey = extractGroupKey(filename, config);
    info.genotype = extractGenotype(info.groupKey);
    
    % Use the internal function with config
    [info.trialNum, info.expType, info.ppiValue, info.coverslipCell] = ...
        extractTrialInfo(filename, config);
    
    info.isValid = ~isempty(info.groupKey) && ~isempty(info.expType);
end