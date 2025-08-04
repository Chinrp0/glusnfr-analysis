function writer = excel_writer()
    % EXCEL_WRITER - Specialized Excel file writing operations
    
    writer.writeResults = @writeExperimentResults;
    writer.writeSheet = @writeDataSheet;
    writer.writeLog = @saveLogToFile;
    writer.createDirectories = @createDirectoriesIfNeeded;
end

function writeExperimentResults(organizedData, averagedData, roiInfo, groupKey, outputFolder, cfg)
    % WRITEEXPERIMENTRESULTS - Main results writing with parallel sheet creation
    
    if nargin < 6
        cfg = GluSnFRConfig();
    end
    
    % Check if Excel output is enabled
    if ~cfg.output.ENABLE_EXCEL_OUTPUT
        return;
    end
    
    cleanGroupKey = regexprep(groupKey, '[^\w-]', '_');
    filename = [cleanGroupKey '_grouped.xlsx'];
    filepath = fullfile(outputFolder, filename);
    
    % Delete existing file
    if exist(filepath, 'file')
        delete(filepath);
    end
    
    try
        hasValidData = validateDataForWriting(organizedData, roiInfo);
        
        if ~hasValidData
            if cfg.output.ENABLE_VERBOSE_OUTPUT
                warning('No data to write for group %s', groupKey);
            end
            return;
        end
        
        % Create write tasks for parallel processing
        writeTasks = createWriteTasks(organizedData, averagedData, roiInfo, filepath, cfg);
        
        % Execute write tasks (parallel if beneficial)
        if length(writeTasks) > 3 && license('test', 'Distrib_Computing_Toolbox')
            executeWriteTasksParallel(writeTasks);
        else
            executeWriteTasksSequential(writeTasks);
        end
        
    catch ME
        if cfg.output.ENABLE_VERBOSE_OUTPUT
            fprintf('ERROR saving Excel file %s: %s\n', filename, ME.message);
        end
        rethrow(ME);
    end
end

function isValid = validateDataForWriting(organizedData, roiInfo)
    % VALIDATEDATAFORWRITING - Check if data structure has content
    
    if strcmp(roiInfo.experimentType, 'PPF')
        if isstruct(organizedData)
            isValid = (isfield(organizedData, 'allData') && width(organizedData.allData) > 1) || ...
                     (isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1) || ...
                     (isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1);
        end
    else
        isValid = istable(organizedData) && width(organizedData) > 1;
    end
end

function writeTasks = createWriteTasks(organizedData, averagedData, roiInfo, filepath, cfg)
    % CREATEWRITETASKS - Create independent write tasks for parallel execution
    
    writeTasks = {};
    
    if strcmp(roiInfo.experimentType, 'PPF')
        writeTasks = createPPFWriteTasks(organizedData, averagedData, roiInfo, filepath, cfg);
    else
        writeTasks = create1APWriteTasks(organizedData, averagedData, roiInfo, filepath, cfg);
    end
    
    % Add metadata task if enabled
    if cfg.output.ENABLE_METADATA_SHEET
        writeTasks{end+1} = struct('type', 'metadata', 'data', organizedData, ...
                                  'roiInfo', roiInfo, 'filepath', filepath);
    end
end

function tasks = createPPFWriteTasks(organizedData, averagedData, roiInfo, filepath, cfg)
    % CREATEPPFWRITETASKS - Create PPF-specific write tasks
    
    tasks = {};
    
    % Individual data sheets
    if cfg.output.ENABLE_INDIVIDUAL_SHEETS
        if isfield(organizedData, 'allData') && width(organizedData.allData) > 1
            tasks{end+1} = struct('type', 'sheet', 'data', organizedData.allData, ...
                                 'sheetName', 'All_Data', 'headerType', 'PPF', ...
                                 'filepath', filepath, 'roiInfo', roiInfo);
        end
        
        if isfield(organizedData, 'bothPeaks') && width(organizedData.bothPeaks) > 1
            tasks{end+1} = struct('type', 'sheet', 'data', organizedData.bothPeaks, ...
                                 'sheetName', 'Both_Peaks', 'headerType', 'PPF', ...
                                 'filepath', filepath, 'roiInfo', roiInfo);
        end
        
        if isfield(organizedData, 'singlePeak') && width(organizedData.singlePeak) > 1
            tasks{end+1} = struct('type', 'sheet', 'data', organizedData.singlePeak, ...
                                 'sheetName', 'Single_Peak', 'headerType', 'PPF', ...
                                 'filepath', filepath, 'roiInfo', roiInfo);
        end
    end
    
    % Averaged sheets
    if cfg.output.ENABLE_AVERAGED_SHEETS && isstruct(averagedData)
        avgFields = {'allData', 'bothPeaks', 'singlePeak'};
        avgSheetNames = {'All_Data_Avg', 'Both_Peaks_Avg', 'Single_Peak_Avg'};
        
        for i = 1:length(avgFields)
            if isfield(averagedData, avgFields{i}) && width(averagedData.(avgFields{i})) > 1
                tasks{end+1} = struct('type', 'sheet', 'data', averagedData.(avgFields{i}), ...
                                     'sheetName', avgSheetNames{i}, 'headerType', 'PPF', ...
                                     'filepath', filepath, 'roiInfo', roiInfo);
            end
        end
    end
end

function tasks = create1APWriteTasks(organizedData, averagedData, roiInfo, filepath, cfg)
    % CREATE1APWRITETASKS - Create 1AP-specific write tasks
    
    tasks = {};
    
    % Noise-separated sheets
    if cfg.output.ENABLE_NOISE_SEPARATED_SHEETS
        [lowNoiseData, highNoiseData] = separateDataByNoise(organizedData, roiInfo);
        
        if ~isempty(lowNoiseData)
            tasks{end+1} = struct('type', 'sheet', 'data', lowNoiseData, ...
                                 'sheetName', 'Low_noise', 'headerType', '1AP', ...
                                 'filepath', filepath, 'roiInfo', []);
        end
        
        if ~isempty(highNoiseData)
            tasks{end+1} = struct('type', 'sheet', 'data', highNoiseData, ...
                                 'sheetName', 'High_noise', 'headerType', '1AP', ...
                                 'filepath', filepath, 'roiInfo', []);
        end
    end
    
    % ROI and total averages
    if cfg.output.ENABLE_ROI_AVERAGE_SHEET && isfield(averagedData, 'roi') && width(averagedData.roi) > 1
        tasks{end+1} = struct('type', 'sheet', 'data', averagedData.roi, ...
                             'sheetName', 'ROI_Average', 'headerType', '1AP', ...
                             'filepath', filepath, 'roiInfo', roiInfo);
    end
    
    if cfg.output.ENABLE_TOTAL_AVERAGE_SHEET && isfield(averagedData, 'total') && width(averagedData.total) > 1
        tasks{end+1} = struct('type', 'sheet', 'data', averagedData.total, ...
                             'sheetName', 'Total_Average', 'headerType', '1AP', ...
                             'filepath', filepath, 'roiInfo', []);
    end
end

function [lowNoiseData, highNoiseData] = separateDataByNoise(organizedData, roiInfo)
    % SEPARATEDATABYNOISE - Separate 1AP data by noise level
    
    varNames = organizedData.Properties.VariableNames;
    lowNoiseColumns = {'Frame'};
    highNoiseColumns = {'Frame'};
    
    % Separate columns by noise level
    for i = 2:length(varNames)
        colName = varNames{i};
        roiMatch = regexp(colName, 'ROI(\d+)_T', 'tokens');
        if ~isempty(roiMatch)
            roiNum = str2double(roiMatch{1}{1});
            if isKey(roiInfo.roiNoiseMap, roiNum)
                noiseLevel = roiInfo.roiNoiseMap(roiNum);
                if strcmp(noiseLevel, 'low')
                    lowNoiseColumns{end+1} = colName;
                elseif strcmp(noiseLevel, 'high')
                    highNoiseColumns{end+1} = colName;
                end
            end
        end
    end
    
    % Create tables
    if length(lowNoiseColumns) > 1
        lowNoiseData = organizedData(:, lowNoiseColumns);
    else
        lowNoiseData = [];
    end
    
    if length(highNoiseColumns) > 1
        highNoiseData = organizedData(:, highNoiseColumns);
    else
        highNoiseData = [];
    end
end

function executeWriteTasksParallel(writeTasks)
    % EXECUTEWRITETASKSPARALLEL - Execute write tasks in parallel
    
    parfor i = 1:length(writeTasks)
        executeWriteTask(writeTasks{i});
    end
end

function executeWriteTasksSequential(writeTasks)
    % EXECUTEWRITETASKSSEQUENTIAL - Execute write tasks sequentially
    
    for i = 1:length(writeTasks)
        executeWriteTask(writeTasks{i});
    end
end

function executeWriteTask(task)
    % EXECUTEWRITETASK - Execute a single write task
    
    try
        switch task.type
            case 'sheet'
                writeDataSheet(task.data, task.filepath, task.sheetName, task.headerType, task.roiInfo);
            case 'metadata'
                writeMetadataSheet(task.data, task.roiInfo, task.filepath);
        end
    catch ME
        % Silent failure for individual tasks to avoid blocking other writes
        warning('Write task failed for sheet %s: %s', task.sheetName, ME.message);
    end
end

function writeDataSheet(dataTable, filepath, sheetName, headerType, roiInfo)
    % Keep the two-header functionality you had before
    
    try
        if strcmp(headerType, 'standard') || isempty(roiInfo)
            writetable(dataTable, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
        else
            writeSheetWithCustomHeaders(dataTable, filepath, sheetName, headerType, roiInfo);
        end
        
    catch ME
        error('Failed to write sheet %s: %s', sheetName, ME.message);
    end
end

function writeSheetWithCustomHeaders(dataTable, filepath, sheetName, expType, roiInfo)
    % WRITESHEETWITHCUSTOMHEADERS - Write Excel sheet with two-row headers
    
    varNames = dataTable.Properties.VariableNames;
    numFrames = height(dataTable);
    
    % Create header rows
    row1 = cell(1, length(varNames));
    row2 = cell(1, length(varNames));
    
    % First column (always Frame/Time)
    if strcmp(expType, 'PPF') && ~isempty(roiInfo)
        row1{1} = sprintf('%dms', roiInfo.timepoint);
    else
        row1{1} = 'Trial/n';
    end
    row2{1} = 'Time (ms)';
    
    % Process remaining columns
    for i = 2:length(varNames)
        varName = varNames{i};
        
        if strcmp(expType, 'PPF')
            % PPF format parsing
            if contains(sheetName, 'Avg')
                roiMatch = regexp(varName, '(Cs\d+-c\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    row1{i} = roiMatch{1}{2};  % n count
                    row2{i} = roiMatch{1}{1};  % Cs-c
                else
                    row1{i} = '';
                    row2{i} = varName;
                end
            else
                roiMatch = regexp(varName, '(Cs\d+-c\d+)_ROI(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    row1{i} = roiMatch{1}{1};  % Cs-c
                    row2{i} = sprintf('ROI %s', roiMatch{1}{2});
                else
                    row1{i} = '';
                    row2{i} = varName;
                end
            end
        else
            % 1AP format parsing
            if contains(varName, '_n')
                roiMatch = regexp(varName, 'ROI(\d+)_n(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    row1{i} = roiMatch{1}{2};  % n count
                    row2{i} = sprintf('ROI %s', roiMatch{1}{1});
                else
                    row1{i} = '';
                    row2{i} = varName;
                end
            else
                roiMatch = regexp(varName, 'ROI(\d+)_T(\d+)', 'tokens');
                if ~isempty(roiMatch)
                    row1{i} = roiMatch{1}{2};  % Trial number
                    row2{i} = sprintf('ROI %s', roiMatch{1}{1});
                else
                    row1{i} = '';
                    row2{i} = varName;
                end
            end
        end
    end
    
    % Write to Excel with custom headers
    try
        % Create data matrix
        timeData = dataTable.Frame;
        dataMatrix = [timeData, table2array(dataTable(:, 2:end))];
        
        % Create cell array for writing
        cellData = cell(numFrames + 2, length(varNames));
        cellData(1, :) = row1;
        cellData(2, :) = row2;
        
        % Add data
        for i = 1:numFrames
            for j = 1:size(dataMatrix, 2)
                cellData{i+2, j} = dataMatrix(i, j);
            end
        end
        
        % Write to Excel
        writecell(cellData, filepath, 'Sheet', sheetName);
        
    catch ME
        % Fallback to standard format
        writetable(dataTable, filepath, 'Sheet', sheetName, 'WriteVariableNames', true);
    end
end

function writeMetadataSheet(organizedData, roiInfo, filepath)
    % WRITEMETADATASHEET - Write metadata information
    
    try
        analyzer = experiment_analyzer();
        metadataTable = analyzer.generateMetadata(organizedData, roiInfo, filepath);
    catch
        % Silent failure for metadata
    end
end

function createDirectoriesIfNeeded(directories)
    % CREATEDIRECTORIESIFNEEDED - Create directories if they don't exist
    
    for i = 1:length(directories)
        dir_path = directories{i};
        if ~exist(dir_path, 'dir')
            try
                mkdir(dir_path);
            catch ME
                warning('Failed to create directory %s: %s', dir_path, ME.message);
            end
        end
    end
end

function saveLogToFile(logBuffer, logFileName)
    % SAVELOGTOFILE - Save log buffer to file
    
    try
        fid = fopen(logFileName, 'w');
        if fid == -1
            warning('Could not create log file: %s', logFileName);
            return;
        end
        
        for i = 1:length(logBuffer)
            fprintf(fid, '%s\n', logBuffer{i});
        end
        
        fclose(fid);
        
    catch ME
        fprintf(2, 'Error writing log file: %s\n', ME.message);
        if exist('fid', 'var') && fid ~= -1
            fclose(fid);
        end
    end
end