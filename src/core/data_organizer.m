function organizer = data_organizer()
    % DATA_ORGANIZER - Data organization and averaging module
    % 
    % Updated with cleaner, less verbose output for better user experience
    
    organizer.organizeFilesByGroup = @organizeFilesByGroup;
    organizer.organizeGroupData = @organizeGroupData;
    organizer.createTrialMapping = @createTrialMapping;
    organizer.extractValidHeaders = @extractValidHeaders;
end

function [groupedFiles, groupKeys] = organizeFilesByGroup(excelFiles, rawMeanFolder)
    % Organize files into groups based on experimental parameters
    
    fprintf('Organizing %d files by experimental groups...\n', length(excelFiles));
    
    groupMap = containers.Map();
    cfg = GluSnFRConfig();
    utils = string_utils(cfg);
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
    % UPDATED: Include filtering statistics in roiInfo for plotting
    
    cfg = GluSnFRConfig();
    
    % Determine experiment type
    isPPF = contains(groupKey, 'PPF_');
    
    if isPPF
        [organizedData, averagedData, roiInfo] = organizeGroupDataPPF(groupData, groupMetadata, groupKey, cfg);
    else
        [organizedData, averagedData, roiInfo] = organizeGroupData1AP(groupData, groupMetadata, cfg);
    end
    
    % ENHANCEMENT: Collect filtering statistics from all files for plotting
    roiInfo.filteringStats = collectFilteringStats(groupData);
end

function filteringStats = collectFilteringStats(groupData)
    % UPDATED: Collect filtering statistics with standard deviations instead of basic thresholds
    % Ensures all required filtering data is available for ROI cache creation
    
    filteringStats = struct();
    filteringStats.available = false;
    filteringStats.method = 'unknown';
    
    cfg = GluSnFRConfig();
    utils = string_utils(cfg);
    
    % Initialize containers for collecting data from all files
    allNoiseMap = containers.Map('KeyType', 'int32', 'ValueType', 'char');
    allUpperThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    allLowerThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
    allStandardDeviations = containers.Map('KeyType', 'int32', 'ValueType', 'double');  % CHANGED: from basic thresholds
    
    foundSchmittData = false;
    
    for i = 1:length(groupData)
        if ~isempty(groupData{i}) && isfield(groupData{i}, 'filterStats')
            stats = groupData{i}.filterStats;
            
            % CRITICAL: Check for Schmitt trigger results
            if isfield(stats, 'schmitt_info') && isstruct(stats.schmitt_info)
                schmittInfo = stats.schmitt_info;
                
                % UPDATED: Verify all required Schmitt fields are present (with standard_deviations)
                if isfield(schmittInfo, 'noise_classification') && ...
                   isfield(schmittInfo, 'upper_thresholds') && ...
                   isfield(schmittInfo, 'lower_thresholds') && ...
                   isfield(schmittInfo, 'standard_deviations') && ...  % CHANGED: from basic_thresholds
                   ~isempty(schmittInfo.noise_classification) && ...
                   ~isempty(schmittInfo.upper_thresholds) && ...
                   ~isempty(schmittInfo.lower_thresholds) && ...
                   ~isempty(schmittInfo.standard_deviations)      % CHANGED: from basic_thresholds
                    
                    foundSchmittData = true;
                    
                    % Get ROI information for this file
                    if isfield(groupData{i}, 'roiNames') && ~isempty(groupData{i}.roiNames)
                        roiNames = groupData{i}.roiNames;
                        roiNumbers = utils.extractROINumbers(roiNames);
                        
                        % Get Schmitt data
                        noiseClassification = schmittInfo.noise_classification;
                        upperThresholds = schmittInfo.upper_thresholds;
                        lowerThresholds = schmittInfo.lower_thresholds;
                        standardDeviations = schmittInfo.standard_deviations;  % CHANGED: from basic_thresholds
                        
                        % UPDATED: Store data using ROI numbers as keys (handle all array types)
                        numROIsToProcess = length(roiNumbers);
                        
                        for j = 1:numROIsToProcess
                            roiNum = roiNumbers(j);
                            
                            % Store noise classification
                            if j <= length(noiseClassification)
                                if iscell(noiseClassification)
                                    noiseLevel = noiseClassification{j};
                                else
                                    noiseLevel = char(noiseClassification(j));
                                end
                                allNoiseMap(roiNum) = noiseLevel;
                            end
                            
                            % Store upper threshold
                            if j <= length(upperThresholds)
                                if iscell(upperThresholds)
                                    upperThresh = upperThresholds{j};
                                else
                                    upperThresh = upperThresholds(j);
                                end
                                if isnumeric(upperThresh) && isfinite(upperThresh)
                                    allUpperThresholds(roiNum) = double(upperThresh);
                                end
                            end
                            
                            % Store lower threshold
                            if j <= length(lowerThresholds)
                                if iscell(lowerThresholds)
                                    lowerThresh = lowerThresholds{j};
                                else
                                    lowerThresh = lowerThresholds(j);
                                end
                                if isnumeric(lowerThresh) && isfinite(lowerThresh)
                                    allLowerThresholds(roiNum) = double(lowerThresh);
                                end
                            end
                            
                            % CHANGED: Store standard deviation instead of basic threshold
                            if j <= length(standardDeviations)
                                if iscell(standardDeviations)
                                    stdDev = standardDeviations{j};
                                else
                                    stdDev = standardDeviations(j);
                                end
                                if isnumeric(stdDev) && isfinite(stdDev)
                                    allStandardDeviations(roiNum) = double(stdDev);
                                end
                            end
                        end
                        
                        if cfg.debug.ENABLE_PLOT_DEBUG
                            fprintf('    Collected Schmitt data for %d ROIs from file %d\n', numROIsToProcess, i);
                        end
                    end
                else
                    if cfg.debug.ENABLE_PLOT_DEBUG
                        fprintf('    File %d: Incomplete Schmitt info structure\n', i);
                        if isfield(schmittInfo, 'noise_classification')
                            fprintf('      noise_classification: %s\n', class(schmittInfo.noise_classification));
                        end
                        if isfield(schmittInfo, 'upper_thresholds')
                            fprintf('      upper_thresholds: %s\n', class(schmittInfo.upper_thresholds));
                        end
                    end
                end
            else
                if cfg.debug.ENABLE_PLOT_DEBUG
                    fprintf('    File %d: No schmitt_info found in filterStats\n', i);
                    if isfield(stats, 'method')
                        fprintf('      Filter method: %s\n', stats.method);
                    end
                end
            end
        else
            if cfg.debug.ENABLE_PLOT_DEBUG
                fprintf('    File %d: No filterStats found\n', i);
            end
        end
    end
    
    % UPDATED: Package the collected data if Schmitt data was found
    if foundSchmittData && ~isempty(allNoiseMap)
        filteringStats.available = true;
        filteringStats.method = 'schmitt_trigger';
        filteringStats.roiNoiseMap = allNoiseMap;
        filteringStats.roiUpperThresholds = allUpperThresholds;
        filteringStats.roiLowerThresholds = allLowerThresholds;
        filteringStats.roiStandardDeviations = allStandardDeviations;  % CHANGED: from roiBasicThresholds
        
        if cfg.debug.ENABLE_PLOT_DEBUG
            fprintf('    Successfully collected Schmitt filtering statistics:\n');
            fprintf('      ROIs with noise classification: %d\n', length(allNoiseMap));
            fprintf('      ROIs with upper thresholds: %d\n', length(allUpperThresholds));
            fprintf('      ROIs with lower thresholds: %d\n', length(allLowerThresholds));
            fprintf('      ROIs with standard deviations: %d\n', length(allStandardDeviations));  % CHANGED: from basic thresholds
        end
    else
        if cfg.debug.ENABLE_PLOT_DEBUG
            if foundSchmittData
                fprintf('    Found Schmitt data but no ROIs were processed successfully\n');
            else
                fprintf('    No Schmitt trigger data found in any group files\n');
            end
        end
        
        % Set to unavailable rather than creating fallback
        filteringStats.available = false;
        filteringStats.method = 'schmitt_unavailable';
        
        if cfg.filtering.USE_SCHMITT_TRIGGER
            warning('Schmitt trigger is enabled but no complete Schmitt data found!');
            fprintf('This suggests the roi_filter is not properly storing schmitt_info.\n');
        end
    end
end

function [organizedData, averagedData, roiInfo] = organizeGroupDataPPF(groupData, groupMetadata, groupKey, cfg)
    % UPDATED: PPF-specific data organization with minimal output
    
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
                                  'dF_values', [], 'thresholds', [], 'timeData_ms', [], ...
                                  'peakResponses', []), maxFiles, 1);
    fileCount = 0;
    
    utils = string_utils(cfg);
    
    for i = 1:length(groupData)
        if ~isempty(groupData{i}) && isfield(groupData{i}, 'roiNames') && ~isempty(groupData{i}.roiNames)
            
            % Extract coverslip-cell info
            csCell = 'Unknown';
            if ~isempty(groupMetadata{i}) && isfield(groupMetadata{i}, 'coverslipCell')
                csCell = groupMetadata{i}.coverslipCell;
            else
                csCell = sprintf('File%d', i);
            end
            
            roiNums = utils.extractROINumbers(groupData{i}.roiNames);
            
            fileCount = fileCount + 1;
            coverslipFiles(fileCount).coverslipCell = csCell;
            coverslipFiles(fileCount).roiNumbers = roiNums;
            coverslipFiles(fileCount).dF_values = groupData{i}.dF_values;
            coverslipFiles(fileCount).thresholds = groupData{i}.thresholds;
            coverslipFiles(fileCount).timeData_ms = groupData{i}.timeData_ms;
            
            % Store peak response information if available (with fallback)
            if isfield(groupData{i}, 'filterStats') && ...
               isfield(groupData{i}.filterStats, 'peakResponses') && ...
               ~isempty(groupData{i}.filterStats.peakResponses)
                coverslipFiles(fileCount).peakResponses = groupData{i}.filterStats.peakResponses;
            else
                % Fallback: create default peak response classification
                numROIs = length(roiNums);
                coverslipFiles(fileCount).peakResponses = struct();
                coverslipFiles(fileCount).peakResponses.filteredBothPeaks = false(numROIs, 1);
                coverslipFiles(fileCount).peakResponses.filteredPeak1Only = false(numROIs, 1);
                coverslipFiles(fileCount).peakResponses.filteredPeak2Only = false(numROIs, 1);
                % Default: assume all ROIs are "single peak" if no classification available
                coverslipFiles(fileCount).peakResponses.filteredPeak1Only(1:numROIs) = true;
            end
        end
    end
    
    % Trim to actual size
    coverslipFiles = coverslipFiles(1:fileCount);
    
    if isempty(coverslipFiles)
        error('No valid PPF data found');
    end
    
    % Create organized data - start with original approach as baseline
    timeData_ms = coverslipFiles(1).timeData_ms;
    
    % Create all data table first (this is the baseline that should always work)
    allDataTable = table();
    allDataTable.Frame = timeData_ms;
    
    % Create separation tables
    bothPeaksTable = table();
    bothPeaksTable.Frame = timeData_ms;
    
    singlePeakTable = table();
    singlePeakTable.Frame = timeData_ms;
    
    % Add all ROIs to tables with peak response classification
    for fileIdx = 1:length(coverslipFiles)
        fileData = coverslipFiles(fileIdx);
        csCell = fileData.coverslipCell;
        
        [sortedROIs, sortOrder] = sort(fileData.roiNumbers);
        
        for roiIdx = 1:length(sortedROIs)
            roiNum = sortedROIs(roiIdx);
            originalIdx = sortOrder(roiIdx);
            
            colName = sprintf('%s_ROI%d', csCell, roiNum);
            
            % Make sure we have valid data for this ROI
            if originalIdx <= size(fileData.dF_values, 2)
                roiData = fileData.dF_values(:, originalIdx);
                
                % Always add to all data table
                allDataTable.(colName) = roiData;
                
                % Classify and add to appropriate separation table
                if ~isempty(fileData.peakResponses)
                    % Check bounds before accessing arrays
                    isBothPeaks = originalIdx <= length(fileData.peakResponses.filteredBothPeaks) && ...
                                  fileData.peakResponses.filteredBothPeaks(originalIdx);
                    isPeak1Only = originalIdx <= length(fileData.peakResponses.filteredPeak1Only) && ...
                                  fileData.peakResponses.filteredPeak1Only(originalIdx);
                    isPeak2Only = originalIdx <= length(fileData.peakResponses.filteredPeak2Only) && ...
                                  fileData.peakResponses.filteredPeak2Only(originalIdx);
                    
                    if isBothPeaks
                        bothPeaksTable.(colName) = roiData;
                    elseif isPeak1Only || isPeak2Only
                        singlePeakTable.(colName) = roiData;
                    else
                        % Default: add to single peak if not classified as both
                        singlePeakTable.(colName) = roiData;
                    end
                else
                    % Fallback: if no peak info, add to single peak table
                    singlePeakTable.(colName) = roiData;
                end
            end
        end
    end
    
    % Package organized data (ensure allData is always available)
    organizedData = struct();
    organizedData.allData = allDataTable;
    
    % Only add separated tables if they have data beyond Frame column
    if width(bothPeaksTable) > 1
        organizedData.bothPeaks = bothPeaksTable;
    end
    
    if width(singlePeakTable) > 1
        organizedData.singlePeak = singlePeakTable;
    end
    
    % Create averaged data for each available category
    averagedData = struct();
    averagedData.allData = createPPFAveragedData(allDataTable, coverslipFiles);
    
    if isfield(organizedData, 'bothPeaks')
        averagedData.bothPeaks = createPPFAveragedData(bothPeaksTable, coverslipFiles);
    end
    
    if isfield(organizedData, 'singlePeak')
        averagedData.singlePeak = createPPFAveragedData(singlePeakTable, coverslipFiles);
    end
    
    % Create ROI info
    roiInfo = struct();
    roiInfo.coverslipFiles = coverslipFiles;
    roiInfo.timepoint = timepoint;
    roiInfo.experimentType = 'PPF';
    roiInfo.dataType = 'separated';
    
    % MINIMAL OUTPUT: Single line summary
    % (will be shown in group processing summary)
end

function averagedTable = createPPFAveragedData(dataTable, coverslipFiles)
    % Create averaged data for PPF with coverslip grouping
    
    if width(dataTable) <= 1
        averagedTable = table();
        if width(dataTable) == 1
            averagedTable.Frame = dataTable.Frame;
        end
        return;
    end
    
    timeData_ms = dataTable.Frame;
    averagedTable = table();
    averagedTable.Frame = timeData_ms;
    
    % Get unique coverslip cells
    coverslipCells = unique({coverslipFiles.coverslipCell});
    
    for csIdx = 1:length(coverslipCells)
        csCell = coverslipCells{csIdx};
        
        % Find columns for this coverslip
        allColNames = dataTable.Properties.VariableNames;
        csPattern = sprintf('%s_ROI', csCell);
        csCols = contains(allColNames, csPattern);
        
        if any(csCols)
            csColNames = allColNames(csCols);
            csData = dataTable(:, csColNames);
            csDataMatrix = table2array(csData);
            meanData = mean(csDataMatrix, 2, 'omitnan');
            nROIs = size(csDataMatrix, 2);
            
            avgColName = sprintf('%s_n%d', csCell, nROIs);
            averagedTable.(avgColName) = meanData;
        end
    end
end


function [organizedData, averagedData, roiInfo] = organizeGroupData1AP(groupData, groupMetadata, cfg)
    % UPDATED: 1AP-specific data organization - FIXED legacy parameter references
    
    % Extract trial numbers
    [originalTrialNumbers, trialMapping] = createTrialMapping(groupMetadata);
    
    if isempty(originalTrialNumbers)
        error('No valid trial numbers found in metadata');
    end
    
    % UPDATED: Collect ROI information without legacy parameter references
    utils = string_utils(cfg);
    allROIData = [];
    
    for fileIdx = 1:length(groupData)
        fileData = groupData{fileIdx};
        
        if isempty(fileData) || ~isfield(fileData, 'roiNames') || isempty(fileData.roiNames)
            continue;
        end
        
        roiNums = utils.extractROINumbers(fileData.roiNames);
        
        if isempty(roiNums)
            continue;
        end
        
        % Store ROI data for this file
        fileROIData = struct();
        fileROIData.roiNumbers = roiNums;
        fileROIData.dF_values = fileData.dF_values;
        fileROIData.thresholds = fileData.thresholds;  % These are now upper thresholds
        fileROIData.roiNames = fileData.roiNames;
        fileROIData.fileIndex = fileIdx;
        
        % CRITICAL: Store original standard deviations if available
        if isfield(fileData, 'originalStandardDeviations')
            fileROIData.standardDeviations = fileData.originalStandardDeviations;
        elseif isfield(fileData, 'filterStats') && isfield(fileData.filterStats, 'schmitt_info') && ...
               isfield(fileData.filterStats.schmitt_info, 'standard_deviations')
            fileROIData.standardDeviations = fileData.filterStats.schmitt_info.standard_deviations;
        end
        
        allROIData = [allROIData; fileROIData];
    end
    
    if isempty(allROIData)
        error('No ROIs found in any files for group');
    end
    
    % Get all unique ROI numbers
    allUniqueROIs = [];
    for i = 1:length(allROIData)
        allUniqueROIs = [allUniqueROIs; allROIData(i).roiNumbers];
    end
    
    uniqueROIs = unique(allUniqueROIs);
    uniqueROIs = sort(uniqueROIs);
    
    % FIXED: Create noise classification map using standard deviations instead of LOW_NOISE_CUTOFF
    roiNoiseMap = containers.Map('KeyType', 'double', 'ValueType', 'char');
    
    for roiNum = uniqueROIs'
        % Find all instances of this ROI across files
        lowNoiseCount = 0;
        highNoiseCount = 0;
        
        for fileIdx = 1:length(allROIData)
            fileData = allROIData(fileIdx);
            roiPos = find(fileData.roiNumbers == roiNum, 1);
            
            if ~isempty(roiPos) && roiPos <= length(fileData.standardDeviations)
                standardDeviation = fileData.standardDeviations(roiPos);
                if isfinite(standardDeviation)
                    % FIXED: Use SD_NOISE_CUTOFF instead of LOW_NOISE_CUTOFF
                    if standardDeviation <= cfg.thresholds.SD_NOISE_CUTOFF
                        lowNoiseCount = lowNoiseCount + 1;
                    else
                        highNoiseCount = highNoiseCount + 1;
                    end
                end
            end
        end
        
        % Majority vote
        if lowNoiseCount >= highNoiseCount
            roiNoiseMap(roiNum) = 'low';
        else
            roiNoiseMap(roiNum) = 'high';
        end
    end
    
    % Organize data into table format (rest unchanged)
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
                found = false;
                for fileIdx = 1:length(allROIData)
                    fileData = allROIData(fileIdx);
                    if fileData.fileIndex == trialIdx % Match trial index
                        roiPos = find(fileData.roiNumbers == roiNum, 1);
                        
                        if ~isempty(roiPos) && roiPos <= size(fileData.dF_values, 2)
                            organizedTable.(colName) = fileData.dF_values(:, roiPos);
                            if roiPos <= length(fileData.thresholds)
                                allThresholds(roiIdx, trialIdx) = fileData.thresholds(roiPos);
                            end
                            found = true;
                            break;
                        end
                    end
                end
                
                if ~found
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
    
    % MINIMAL OUTPUT: No detailed organization logging
    % (will be shown in group processing summary)
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
                % Return NaN for any conversion error
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

function roiAveragedData = createROIAveragedData1AP(organizedData, roiInfo, timeData_ms)
    % Create ROI-averaged data for 1AP experiments
    
    averagedTable = table();
    averagedTable.Frame = timeData_ms;
    
    for i = 1:length(roiInfo.roiNumbers)
        roiNum = roiInfo.roiNumbers(i);
        
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
    % FIXED: Create total averaged data by noise level - no legacy parameter references
    
    totalAveragedTable = table();
    totalAveragedTable.Frame = timeData_ms;
    
    % Get all data columns (skip Frame)
    dataVarNames = organizedData.Properties.VariableNames(2:end);
    
    if isempty(dataVarNames)
        totalAveragedData = totalAveragedTable;
        return;
    end
    
    % Separate data by noise level using the roiNoiseMap (no threshold calculations needed)
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
                
                % FIXED: Use pre-computed noise level from roiNoiseMap
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
    
    % Calculate averages (unchanged)
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