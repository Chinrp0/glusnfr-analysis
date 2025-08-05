function results = compare_roi_filters(filepath)
    % COMPARE_ROI_FILTERS - Compare current vs Schmitt trigger filtering
    %
    % This function compares the existing ROI filtering method with a new
    % Schmitt trigger-based approach on a single input file.
    %
    % Usage:
    %   results = compare_roi_filters(filepath)
    %   results = compare_roi_filters()  % Opens file dialog with default path
    %
    % Returns:
    %   results - Structure containing comparison data and statistics
    
    if nargin < 1 || isempty(filepath)
        % Set your default path here
        default_path = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\1AP\GPU_Processed_Images_1AP\5_raw_mean\';
        
        % Check if default path exists, if not fall back to current directory
        if ~exist(default_path, 'dir')
            warning('Default path does not exist: %s\nUsing current directory instead.', default_path);
            default_path = pwd;
        end
        
        [filename, pathname] = uigetfile('*.xlsx', 'Select Excel file for ROI filter comparison', default_path);
        if isequal(filename, 0)
            fprintf('No file selected, exiting...\n');
            results = [];
            return;
        end
        filepath = fullfile(pathname, filename);
    end
    
    fprintf('\n=== ROI Filter Comparison ===\n');
    fprintf('File: %s\n', filepath);
    
    % Add path and load modules
    addpath(genpath(pwd));
    modules = module_loader();
    
    % Read and process file
    fprintf('Reading file...\n');
    [rawData, headers, success] = modules.io.reader.readFile(filepath, true);
    if ~success || isempty(rawData)
        error('Failed to read file: %s', filepath);
    end
    
    % Extract valid data
    [validHeaders, validColumns] = modules.io.reader.extractHeaders(headers);
    if isempty(validHeaders)
        error('No valid headers found');
    end
    
    % Calculate dF/F
    fprintf('Calculating dF/F...\n');
    numericData = single(rawData(:, validColumns));
    hasGPU = gpuDeviceCount > 0;
    gpuInfo = struct('memory', 4);
    [dF_values, thresholds, gpuUsed] = modules.calc.calculate(numericData, hasGPU, gpuInfo);
    
    % Determine experiment type
    [~, filename, ~] = fileparts(filepath);
    if contains(filename, 'PPF')
        experimentType = 'PPF';
        ppfMatch = regexp(filename, 'PPF-(\d+)ms', 'tokens');
        ppfTimepoint = ternary(~isempty(ppfMatch), str2double(ppfMatch{1}{1}), 30);
    else
        experimentType = '1AP';
        ppfTimepoint = [];
    end
    
    fprintf('Experiment type: %s\n', experimentType);
    
    % Run current filtering method
    fprintf('Running current filtering method...\n');
    if strcmp(experimentType, 'PPF')
        [currentData, currentHeaders, currentThresh, currentStats] = ...
            modules.filter.filterROIs(dF_values, validHeaders, thresholds, 'PPF', ppfTimepoint);
    else
        [currentData, currentHeaders, currentThresh, currentStats] = ...
            modules.filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
    end
    
    % Run Schmitt trigger filtering method
    fprintf('Running Schmitt trigger filtering method...\n');
    schmitt_filter = schmitt_trigger_filter();
    if strcmp(experimentType, 'PPF')
        [schmittData, schmittHeaders, schmittThresh, schmittStats] = ...
            schmitt_filter.filterROIs(dF_values, validHeaders, thresholds, 'PPF', ppfTimepoint);
    else
        [schmittData, schmittHeaders, schmittThresh, schmittStats] = ...
            schmitt_filter.filterROIs(dF_values, validHeaders, thresholds, '1AP');
    end
    
    % Extract ROI numbers for comparison
    currentROIs = extractROINumbers(currentHeaders);
    schmittROIs = extractROINumbers(schmittHeaders);
    allROIs = extractROINumbers(validHeaders);
    
    % Compare results
    bothPassed = intersect(currentROIs, schmittROIs);
    currentOnly = setdiff(currentROIs, schmittROIs);
    schmittOnly = setdiff(schmittROIs, currentROIs);
    bothFailed = setdiff(allROIs, union(currentROIs, schmittROIs));
    
    % Compile results
    results = struct();
    results.filepath = filepath;
    results.experimentType = experimentType;
    results.totalROIs = length(allROIs);
    
    % Method results
    results.current = struct();
    results.current.count = length(currentROIs);
    results.current.rois = currentROIs;
    results.current.stats = currentStats;
    
    results.schmitt = struct();
    results.schmitt.count = length(schmittROIs);
    results.schmitt.rois = schmittROIs;
    results.schmitt.stats = schmittStats;
    
    % Comparison results
    results.comparison = struct();
    results.comparison.both_passed = bothPassed;
    results.comparison.current_only = currentOnly;
    results.comparison.schmitt_only = schmittOnly;
    results.comparison.both_failed = bothFailed;
    
    % Performance metrics
    results.metrics = struct();
    results.metrics.current_pass_rate = length(currentROIs) / length(allROIs);
    results.metrics.schmitt_pass_rate = length(schmittROIs) / length(allROIs);
    results.metrics.agreement_rate = length(bothPassed) / length(allROIs);
    results.metrics.net_change = length(schmittROIs) - length(currentROIs);
    results.metrics.net_change_percent = results.metrics.net_change / length(currentROIs) * 100;
    
    % Store data for plotting
    results.data = struct();
    results.data.dF_values = dF_values;
    results.data.headers = validHeaders;
    results.data.thresholds = thresholds;
    results.data.timeData_ms = (0:(size(dF_values,1)-1))' * 5; % 5ms per frame
    
    % Display summary
    displayComparisonSummary(results);
    
    % Generate plots
    plot_filter_comparison(results);
    
    fprintf('\nComparison complete!\n');
end

function roiNumbers = extractROINumbers(headers)
    % Extract ROI numbers from headers
    roiNumbers = [];
    for i = 1:length(headers)
        matches = regexp(headers{i}, 'ROI[_\s]*(\d+)', 'tokens', 'ignorecase');
        if ~isempty(matches)
            roiNumbers(end+1) = str2double(matches{1}{1});
        end
    end
    roiNumbers = sort(roiNumbers);
end

function displayComparisonSummary(results)
    % Display comparison summary
    fprintf('\n=== COMPARISON SUMMARY ===\n');
    fprintf('Total ROIs: %d\n', results.totalROIs);
    fprintf('Current method: %d ROIs passed (%.1f%%)\n', ...
            results.current.count, results.metrics.current_pass_rate * 100);
    fprintf('Schmitt trigger: %d ROIs passed (%.1f%%)\n', ...
            results.schmitt.count, results.metrics.schmitt_pass_rate * 100);
    fprintf('Agreement: %d ROIs (%.1f%%)\n', ...
            length(results.comparison.both_passed), results.metrics.agreement_rate * 100);
    fprintf('Net change: %+d ROIs (%+.1f%%)\n', ...
            results.metrics.net_change, results.metrics.net_change_percent);
    
    if ~isempty(results.comparison.current_only)
        fprintf('\nROIs removed by Schmitt trigger (n=%d):\n', length(results.comparison.current_only));
        fprintf('  %s\n', sprintf('%d ', results.comparison.current_only(1:min(10, end))));
        if length(results.comparison.current_only) > 10
            fprintf('  ... and %d more\n', length(results.comparison.current_only) - 10);
        end
    end
    
    if ~isempty(results.comparison.schmitt_only)
        fprintf('\nROIs added by Schmitt trigger (n=%d):\n', length(results.comparison.schmitt_only));
        fprintf('  %s\n', sprintf('%d ', results.comparison.schmitt_only(1:min(10, end))));
        if length(results.comparison.schmitt_only) > 10
            fprintf('  ... and %d more\n', length(results.comparison.schmitt_only) - 10);
        end
    end
end

function result = ternary(condition, trueVal, falseVal)
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end