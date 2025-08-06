function analyzer = experiment_analyzer()
    % EXPERIMENT_ANALYZER - Experiment-specific analysis module
    % 
    % This module handles analysis specific to different experiment types:
    % - 1AP (single action potential) analysis
    % - PPF (paired-pulse facilitation) analysis
    % - Statistics and summary generation
    % - Results validation and quality control
    


    analyzer.validateResults = @validateExperimentResults;
    analyzer.calculateStatistics = @calculateExperimentStatistics;
    analyzer.createSummary = @createResultsSummary;
end


function isValid = validateExperimentResults(groupResults)
    % Validate experiment results for quality control
    
    isValid = true;
    issues = {};
    
    for i = 1:length(groupResults)
        result = groupResults{i};
        
        % Check for critical errors
        if strcmp(result.status, 'error')
            isValid = false;
            issues{end+1} = sprintf('Group %d failed with error', i);
        end
        
        % Check for reasonable ROI counts
        if isfield(result, 'numROIs') && result.numROIs == 0
            issues{end+1} = sprintf('Group %d has no valid ROIs', i);
        end
        
        % Check for reasonable filter rates
        if isfield(result, 'numROIs') && isfield(result, 'numOriginalROIs')
            filterRate = result.numROIs / result.numOriginalROIs;
            if filterRate < 0.1 % Less than 10% passed filtering
                issues{end+1} = sprintf('Group %d has very low filter rate (%.1f%%)', i, filterRate*100);
            end
        end
    end
    
    % Report issues
    if ~isempty(issues)
        fprintf('\n=== Quality Control Issues ===\n');
        for i = 1:length(issues)
            fprintf('  WARNING: %s\n', issues{i});
        end
    end
    
    if isValid
        fprintf('All experiment results passed validation\n');
    else
        fprintf('Some experiment results failed validation\n');
    end
end

function stats = calculateExperimentStatistics(groupResults)
    % Calculate comprehensive statistics across all groups
    
    stats = struct();
    stats.totalGroups = length(groupResults);
    stats.successfulGroups = 0;
    stats.totalROIs = 0;
    stats.totalOriginalROIs = 0;
    stats.gpuUsage = 0;
    stats.experimentTypes = {};
    
    % Collect statistics
    for i = 1:length(groupResults)
        result = groupResults{i};
        
        if strcmp(result.status, 'success')
            stats.successfulGroups = stats.successfulGroups + 1;
        end
        
        if isfield(result, 'numROIs')
            stats.totalROIs = stats.totalROIs + result.numROIs;
        end
        
        if isfield(result, 'numOriginalROIs')
            stats.totalOriginalROIs = stats.totalOriginalROIs + result.numOriginalROIs;
        end
        
        if isfield(result, 'gpuUsed') && result.gpuUsed
            stats.gpuUsage = stats.gpuUsage + 1;
        end
        
        if isfield(result, 'experimentType')
            if ~ismember(result.experimentType, stats.experimentTypes)
                stats.experimentTypes{end+1} = result.experimentType;
            end
        end
    end
    
    % Calculate derived statistics
    stats.successRate = stats.successfulGroups / stats.totalGroups;
    if stats.totalOriginalROIs > 0
        stats.overallFilterRate = stats.totalROIs / stats.totalOriginalROIs;
    else
        stats.overallFilterRate = 0;
    end
    stats.gpuUsageRate = stats.gpuUsage / stats.totalGroups;
    
    % Performance categories
    if stats.successRate >= 0.95
        stats.performanceCategory = 'Excellent';
    elseif stats.successRate >= 0.80
        stats.performanceCategory = 'Good';
    elseif stats.successRate >= 0.60
        stats.performanceCategory = 'Fair';
    else
        stats.performanceCategory = 'Poor';
    end
end

function summary = createResultsSummary(groupResults, processingTimes, totalTime)
    % Create comprehensive results summary
    
    stats = calculateExperimentStatistics(groupResults);
    
    summary = struct();
    summary.statistics = stats;
    summary.timing = struct();
    summary.timing.totalTime = totalTime;
    summary.timing.averageTimePerGroup = totalTime / stats.totalGroups;
    summary.timing.groupTimes = processingTimes;
    
    % Create text summary
    summaryText = {};
    summaryText{end+1} = '=== GluSnFR Analysis Summary ===';
    summaryText{end+1} = sprintf('Total groups processed: %d', stats.totalGroups);
    summaryText{end+1} = sprintf('Successful groups: %d (%.1f%%)', stats.successfulGroups, stats.successRate*100);
    summaryText{end+1} = sprintf('Experiment types: %s', strjoin(stats.experimentTypes, ', '));
    summaryText{end+1} = sprintf('Total ROIs: %d (from %d original)', stats.totalROIs, stats.totalOriginalROIs);
    summaryText{end+1} = sprintf('Overall filter rate: %.1f%%', stats.overallFilterRate*100);
    summaryText{end+1} = sprintf('GPU usage: %d/%d groups (%.1f%%)', stats.gpuUsage, stats.totalGroups, stats.gpuUsageRate*100);
    summaryText{end+1} = sprintf('Total processing time: %.2f seconds', totalTime);
    summaryText{end+1} = sprintf('Average time per group: %.2f seconds', summary.timing.averageTimePerGroup);
    summaryText{end+1} = sprintf('Performance category: %s', stats.performanceCategory);
    
    summary.textSummary = summaryText;
    
    % Display summary
    fprintf('\n');
    for i = 1:length(summaryText)
        fprintf('%s\n', summaryText{i});
    end
end