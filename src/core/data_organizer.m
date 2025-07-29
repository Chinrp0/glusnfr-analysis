function organizer = data_organizer()
    % DATA_ORGANIZER - Data organization and averaging module
    % 
    % This module handles the complex data organization logic:
    % - Grouping files by experiment parameters
    % - Organizing individual trial data
    % - Creating averaged data structures
    % - Handling both 1AP and PPF experiments
    
    organizer.organizeFilesByGroup = @organizeFilesByGroup;
    organizer.organizeGroupData = @organizeGroupData;
    organizer.createTrialMapping = @createTrialMapping;
    organizer.extractValidHeaders = @extractValidHeaders;
    organizer.createROINoiseMap = @createROINoiseMap;
end

function [groupedFiles, groupKeys] = organizeFilesByGroup(excelFiles, rawMeanFolder)
    % Organize files into groups based on experimental parameters
    
    fprintf('Organizing %d files by experimental groups...\n', length(excelFiles));
    
    groupMap = containers.Map();
    utils = string_utils();
    successCount = 0;
    
    % Process each file
    for i = 1:length(excelFiles)
        try
            filename = excelFiles(i).name;
            groupKey = utils.extractGroupKey(filename);
            
            if ~isempty(groupKey)
                % Add to group
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
    
    % Convert to output format
    groupKeys = keys(groupMap);
    numGroups = length(groupKeys);
    groupedFiles = cell(numGroups, 1);
    
    for i = 1:numGroups
        indices = groupMap(groupKeys{i});
        groupedFiles{i} = excelFiles(indices);
    end
    
    fprintf('Successfully organized %d/%d files into %d groups\n', ...
            successCount, length(excelFiles), numGroups);
    
    % Display groups
    for i = 1:numGroups
        fprintf('  Group %d: %s (%d files)\n', i, groupKeys{i}, length(groupedFiles{i}));
    end
end

function [organizedData, averagedData, roiInfo] = organizeGroupData(groupData, groupMetadata, groupKey)
    % Organize group data based on experiment type
    
    cfg = GluSnFRConfig();
    
    % Determine experiment type
    isPPF = contains(groupKey, 'PPF_');
    
    if isPPF
        fprintf('    Organizing PPF experiment data\n');
        [organizedData, averagedData, roiInfo] = organizeGroupDataPPF(groupData, groupMetadata, groupKey, cfg);
    else
        fprintf('    Organizing 1AP experiment data\n');
        [organizedData, averagedData, roiInfo] = organizeGroupData1AP(groupData, groupMetadata, cfg);
    end
end

function [organizedData, averagedData, roiInfo] = organizeGroupDataPPF(groupData, groupMetadata, groupKey, cfg)
    % PPF-specific data organization
    
    % Extract timepoint from group key
    timepointMatch = regexp(groupKey, 'PPF_(\d+)ms', 'tokens');
    if ~isempty(timepointMatch)
        timepoint = str2double(timepointMatch{1}{1});
    else
        error('Could not extract timepoint from PPF group key: %s', groupKey);
    end
    
    % Process coverslip files
    maxFiles = length(groupData);
    coverslipFiles = repmat(struct('coverslipCell', '', 'roiNumbers', [], ...
                                  'dF_values', [], 'thresholds', [], 'timeData_ms', []), maxFiles, 1);
    fileCount = 0;
    
    for i = 1:length(groupData)
        if ~isempty(groupData{i}) && isfield(groupData{i}, 'roiNames') && ~isempty(groupData{i}.roiNames)
            
            % Extract coverslip-cell info
            csCell = 'Unknown';
            if ~isempty(groupMetadata{i}) && isfield(groupMetadata{i}, 'coverslipCell')
                csCell = groupMetadata{i}.coverslipCell;
            else
                csCell = sprintf('File%d', i);
            end
            
            utils = string_utils();
            roiNums = utils.extractROINumbers(groupData{i}.roiNames);
            
            fileCount = fileCount + 1;
            coverslipFiles(fileCount).coverslipCell = csCell;
            coverslipFiles(fileCount).roiNumbers = roiNums;
            coverslipFiles(fileCount).dF_values = groupData{i}.dF_values;
            coverslipFiles(fileCount).thresholds = groupData{i}.thresholds;
            coverslipFiles(fileCount).timeData_ms = groupData{i}.timeData_ms;
        end
    end
    
    % Trim to actual size
    coverslipFiles = coverslipFiles(1:fileCount);
    
    if isempty(coverslipFiles)
        error('No valid PPF data found');
    end
    
    % Create organized table
    timeData_ms = coverslipFiles(1).timeData_ms;
    organizedTable = table();
    organizedTable.Frame = timeData_ms;
    
    % Add all ROIs from all coverslip files
    for fileIdx = 1:length(coverslipFiles)
        fileData = coverslipFiles(fileIdx);
        csCell = fileData.coverslipCell;
        
        [sortedROIs, sortOrder] = sort(fileData.roiNumbers);
        
        for roiIdx = 1:length(sortedROIs)
            roiNum = sortedROIs(roiIdx);
            originalIdx = sortOrder(roiIdx);
            
            colName = sprintf('%s_ROI%d', csCell, roiNum);
            organizedTable.(colName) = fileData.dF_values(:, originalIdx);
        end
    end
    
    organizedData = organizedTable;
    
    % Create averaged data
    averagedTable = table();
    averagedTable.Frame = timeData_ms;
    
    for fileIdx = 1:length(coverslipFiles)
        fileData = coverslipFiles(fileIdx);
        csCell = fileData.coverslipCell;
        
        % Average all ROIs in this coverslip
        allColNames = organizedData.Properties.VariableNames;
        csPattern = sprintf('%s_ROI', csCell);
        csCols = contains(allColNames, csPattern);
        
        if any(csCols)
            csColNames = allColNames(csCols);
            csData = organizedData(:, csColNames);
            csDataMatrix = table2array(csData);
            meanData = mean(csDataMatrix, 2, 'omitnan');
            nROIs = size(csDataMatrix, 2);
            
            avgColName = sprintf('%s_n%d', csCell, nROIs);
            averagedTable.(avgColName) = meanData;
        end
    end
    
    averagedData = averagedTable;
    
    % Create ROI info
    roiInfo = struct();
    roiInfo.coverslipFiles = coverslipFiles;
    roiInfo.timepoint = timepoint;
    roiInfo.experimentType = 'PPF';
    roiInfo.dataType = 'single';
end

function [organizedData, averagedData, roiInfo] = organizeGroupData1AP(groupData, groupMetadata, cfg)
    % 1AP-specific data organization with noise level tracking
    
    % Extract trial numbers
    [originalTrialNumbers, trialMapping] = createTrialMapping(groupMetadata);
    
    if isempty(originalTrialNumbers)
        error('No valid trial numbers found in metadata');
    end
    
    % Collect ROI information with noise classification
    utils = string_utils();
    allROINums = [];
    allNoiseTypes = {};
    
    for fileIdx = 1:length(groupData)
        if ~isempty(groupData{fileIdx}) && isfield(groupData{fileIdx}, 'roiNames')
            roiNums = utils.extractROINumbers(groupData{fileIdx}.roiNames);
            thresholds = groupData{fileIdx}.thresholds;
            
            for roiIdx = 1:length(roiNums)
                allROINums(end+1) = roiNums(roiIdx);
                
                % Classify noise level
                if roiIdx <= length(thresholds) && isfinite(thresholds(roiIdx))
                    if thresholds(roiIdx) <= cfg.thresholds.LOW_NOISE_CUTOFF
                        allNoiseTypes{end+1} = 'low';
                    else
                        allNoiseTypes{end+1} = 'high';
                    end
                else
                    allNoiseTypes{end+1} = 'unknown';
                end
            end
        end
    end
    
    uniqueROIs = unique(allROINums);
    uniqueROIs = sort(uniqueROIs);
    
    % Create ROI noise classification map
    roiNoiseMap = createROINoiseMap(uniqueROIs, allROINums, allNoiseTypes);
    
    % Organize data into table format
    timeData_ms = groupData{1}.timeData_ms;
    numTrials = length(originalTrialNumbers);
    
    organizedTable = table();
    organizedTable.Frame = timeData_ms;
    
    % Create data columns
    allThresholds = NaN(length(uniqueROIs), numTrials);
    
    for roiIdx = 1:length(uniqueROIs)
        roiNum = uniqueROIs(roiIdx);
        
        for trialIdx = 1:numTrials
            originalTrialNum = originalTrialNumbers(trialIdx);
            
            if isfinite(originalTrialNum)
                colName = sprintf('ROI%d_T%g', roiNum, originalTrialNum);
                
                % Find data for this ROI in this trial
                data = groupData{trialIdx};
                if ~isempty(data) && isfield(data, 'dF_values') && isfield(data, 'roiNames')
                    roiNums = utils.extractROINumbers(data.roiNames);
                    roiPos = find(roiNums == roiNum, 1);
                    
                    if ~isempty(roiPos) && roiPos <= size(data.dF_values, 2)
                        organizedTable.(colName) = data.dF_values(:, roiPos);
                        if isfield(data, 'thresholds') && roiPos <= length(data.thresholds)
                            allThresholds(roiIdx, trialIdx) = data.thresholds(roiPos);
                        end
                    else
                        organizedTable.(colName) = NaN(length(timeData_ms), 1, 'single');
                    end
                else
                    organizedTable.(colName) = NaN(length(timeData_ms), 1, 'single');
                end
            end
        end
    end
    
    organizedData = organizedTable;
    
    % Create ROI info
    roiInfo = struct();
    roiInfo.roiNumbers = uniqueROIs;
    roiInfo.roiNoiseMap = roiNoiseMap;
    roiInfo.numTrials = numTrials;
    roiInfo.originalTrialNumbers = originalTrialNumbers;
    roiInfo.trialMapping = trialMapping;
    roiInfo.experimentType = '1AP';
    roiInfo.thresholds = allThresholds;
    roiInfo.dataType = 'single';
    
    % Create averaged data
    roiAveragedData = createROIAveragedData1AP(organizedData, roiInfo, timeData_ms);
    totalAveragedData = createTotalAveragedData1AP(organizedData, roiInfo, timeData_ms);
    
    averagedData = struct();
    averagedData.roi = roiAveragedData;
    averagedData.total = totalAveragedData;
end

function [originalTrialNumbers, trialMapping] = createTrialMapping(groupMetadata)
    % Create mapping between original and sequential trial numbers
    
    numFiles = length(groupMetadata);
    originalTrialNumbers = NaN(numFiles, 1);
    validCount = 0;
    
    for i = 1:numFiles
        if ~isempty(groupMetadata{i}) && isfield(groupMetadata{i}, 'trialNumber')
            trialNum = groupMetadata{i}.trialNumber;
            
            % Convert to valid number
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
                % Keep as NaN
            end
            
            if isfinite(validNum)
                validCount = validCount + 1;
                originalTrialNumbers(validCount) = validNum;
            end
        end
    end
    
    % Trim to actual size
    originalTrialNumbers = originalTrialNumbers(1:validCount);
    
    % Create bidirectional mapping
    uniqueTrials = unique(originalTrialNumbers);
    numUnique = length(uniqueTrials);
    
    trialMapping = struct();
    trialMapping.original_to_sequential = containers.Map(num2cell(uniqueTrials), num2cell(1:numUnique));
    trialMapping.sequential_to_original = containers.Map(num2cell(1:numUnique), num2cell(uniqueTrials));
end

function [validHeaders, validColumns] = extractValidHeaders(headers)
    % Extract valid headers from raw header row
    
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
end

function roiNoiseMap = createROINoiseMap(uniqueROIs, allROINums, allNoiseTypes)
    % Create noise classification map for ROIs
    
    roiNoiseMap = containers.Map('KeyType', 'double', 'ValueType', 'char');
    
    for roiNum = uniqueROIs'
        roiOccurrences = allROINums == roiNum;
        roiNoiseTypes = allNoiseTypes(roiOccurrences);
        
        % Majority vote for noise level
        lowCount = sum(strcmp(roiNoiseTypes, 'low'));
        highCount = sum(strcmp(roiNoiseTypes, 'high'));
        
        if lowCount >= highCount
            roiNoiseMap(roiNum) = 'low';
        else
            roiNoiseMap(roiNum) = 'high';
        end
    end
end

function roiAveragedData = createROIAveragedData1AP(organizedData, roiInfo, timeData_ms)
    % Create ROI-averaged data for 1AP experiments
    
    numROIs = length(roiInfo.roiNumbers);
    
    averagedTable = table();
    averagedTable.Frame = timeData_ms;
    
    for roiIdx = 1:numROIs
        roiNum = roiInfo.roiNumbers(roiIdx);
        
        % Find all trials for this ROI
        validTrialData = [];
        validTrialCount = 0;
        
        for trialIdx = 1:roiInfo.numTrials
            originalTrialNum = roiInfo.originalTrialNumbers(trialIdx);
            if isfinite(originalTrialNum)
                colName = sprintf('ROI%d_T%g', roiNum, originalTrialNum);
                
                if ismember(colName, organizedData.Properties.VariableNames)
                    trialData = organizedData.(colName);
                    if ~all(isnan(trialData))
                        validTrialCount = validTrialCount + 1;
                        if isempty(validTrialData)
                            validTrialData = trialData;
                        else
                            validTrialData = [validTrialData, trialData];
                        end
                    end
                end
            end
        end
        
        % Calculate average if data exists
        if validTrialCount > 0
            meanData = mean(validTrialData, 2, 'omitnan');
            avgColName = sprintf('ROI%d_n%d', roiNum, validTrialCount);
            averagedTable.(avgColName) = meanData;
        end
    end
    
    roiAveragedData = averagedTable;
end

function totalAveragedData = createTotalAveragedData1AP(organizedData, roiInfo, timeData_ms)
    % Create total averaged data by noise level for 1AP experiments
    
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
    
    lowNoiseCount = 0;
    highNoiseCount = 0;
    
    for colIdx = 1:length(dataVarNames)
        colName = dataVarNames{colIdx};
        colData = organizedData.(colName);
        
        % Skip columns with all NaN
        if all(isnan(colData))
            continue;
        end
        
        % Extract ROI number
        roiMatch = regexp(colName, 'ROI(\d+)_T', 'tokens');
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            
            if isKey(roiInfo.roiNoiseMap, roiNum)
                noiseLevel = roiInfo.roiNoiseMap(roiNum);
                
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
        totalAveragedTable.(sprintf('All_n%d', size(allValidData, 2))) = allAvg;
    end
    
    totalAveragedData = totalAveragedTable;
end