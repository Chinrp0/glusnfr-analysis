function plot_filter_comparison(results)
    % PLOT_FILTER_COMPARISON - Plot differences between filtering methods
    %
    % This function creates comprehensive plots showing the differences
    % between current and Schmitt trigger filtering methods.
    %
    % Input:
    %   results - Structure from compare_roi_filters function
    
    if isempty(results) || ~isfield(results, 'data')
        error('Invalid results structure - run compare_roi_filters first');
    end
    
    % Extract data for plotting
    dF_values = results.data.dF_values;
    headers = results.data.headers;
    thresholds = results.data.thresholds;
    timeData_ms = results.data.timeData_ms;
    
    cfg = GluSnFRConfig();
    stimTime_ms = cfg.timing.STIMULUS_TIME_MS;
    
    fprintf('Generating comparison plots...\n');
    
    % Plot 1: Summary comparison
    plot_summary_comparison(results);
    
    % Plot 2: ROIs removed by Schmitt trigger (false positives from current method)
    if ~isempty(results.comparison.current_only)
        plot_removed_rois(results, dF_values, headers, timeData_ms, stimTime_ms, thresholds);
    end
    
    % Plot 3: ROIs added by Schmitt trigger (missed by current method)
    if ~isempty(results.comparison.schmitt_only)
        plot_added_rois(results, dF_values, headers, timeData_ms, stimTime_ms, thresholds);
    end
    
    % Plot 4: Example traces showing Schmitt trigger logic
    plot_schmitt_trigger_examples(results, dF_values, headers, timeData_ms, stimTime_ms, thresholds);
    
    fprintf('All comparison plots generated.\n');
end

function plot_summary_comparison(results)
    % Plot summary comparison between methods
    
    figure('Position', [100, 100, 1000, 600], 'Name', 'Filter Method Comparison Summary');
    
    % Subplot 1: Pass rates
    subplot(2, 3, 1);
    methods = {'Current', 'Schmitt'};
    pass_rates = [results.metrics.current_pass_rate, results.metrics.schmitt_pass_rate] * 100;
    
    bar(pass_rates, 'FaceColor', [0.3, 0.6, 0.8]);
    set(gca, 'XTickLabel', methods);
    ylabel('Pass Rate (%)');
    title('ROI Pass Rates');
    ylim([0, max(pass_rates) * 1.2]);
    
    % Add text labels
    for i = 1:length(pass_rates)
        text(i, pass_rates(i) + max(pass_rates)*0.02, sprintf('%.1f%%', pass_rates(i)), ...
             'HorizontalAlignment', 'center');
    end
    
    % Subplot 2: ROI counts
    subplot(2, 3, 2);
    counts = [results.current.count, results.schmitt.count];
    bar(counts, 'FaceColor', [0.8, 0.4, 0.3]);
    set(gca, 'XTickLabel', methods);
    ylabel('ROI Count');
    title('ROIs Passed');
    ylim([0, max(counts) * 1.2]);
    
    % Add text labels
    for i = 1:length(counts)
        text(i, counts(i) + max(counts)*0.02, sprintf('%d', counts(i)), ...
             'HorizontalAlignment', 'center');
    end
    
    % Subplot 3: Venn diagram-style comparison
    subplot(2, 3, 3);
    both = length(results.comparison.both_passed);
    current_only = length(results.comparison.current_only);
    schmitt_only = length(results.comparison.schmitt_only);
    
    categories = {'Both Methods', 'Current Only', 'Schmitt Only'};
    values = [both, current_only, schmitt_only];
    colors = [0.4, 0.8, 0.4; 0.8, 0.4, 0.4; 0.4, 0.4, 0.8];
    
    bar(values, 'FaceColor', 'flat', 'CData', colors);
    set(gca, 'XTickLabel', categories, 'XTickLabelRotation', 45);
    ylabel('ROI Count');
    title('Method Agreement');
    
    % Add text labels
    for i = 1:length(values)
        if values(i) > 0
            text(i, values(i) + max(values)*0.02, sprintf('%d', values(i)), ...
                 'HorizontalAlignment', 'center');
        end
    end
    
    % Subplot 4: Performance metrics text
    subplot(2, 3, [4, 5, 6]);
    axis off;
    
    summary_text = {
        'COMPARISON SUMMARY';
        '';
        sprintf('Total ROIs: %d', results.totalROIs);
        sprintf('Current method: %d ROIs (%.1f%%)', results.current.count, results.metrics.current_pass_rate * 100);
        sprintf('Schmitt trigger: %d ROIs (%.1f%%)', results.schmitt.count, results.metrics.schmitt_pass_rate * 100);
        sprintf('Agreement: %d ROIs (%.1f%%)', both, results.metrics.agreement_rate * 100);
        sprintf('Net change: %+d ROIs (%+.1f%%)', results.metrics.net_change, results.metrics.net_change_percent);
        '';
        'METHOD DIFFERENCES:';
        sprintf('• ROIs removed by Schmitt: %d', current_only);
        sprintf('• ROIs added by Schmitt: %d', schmitt_only);
        '';
        sprintf('File: %s', results.filepath);
        sprintf('Experiment: %s', results.experimentType);
    };
    
    text(0.05, 0.95, summary_text, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
         'FontSize', 11, 'FontName', 'FixedWidth');
    
    sgtitle('ROI Filtering Method Comparison', 'FontSize', 14, 'FontWeight', 'bold');
end

function plot_removed_rois(results, dF_values, headers, timeData_ms, stimTime_ms, thresholds)
    % Plot ROIs that were removed by Schmitt trigger with enhanced visualization
    
    removed_rois = results.comparison.current_only;
    num_to_plot = min(12, length(removed_rois));
    
    if num_to_plot == 0
        return;
    end
    
    figure('Position', [150, 150, 1400, 900], 'Name', 'ROIs Removed by Schmitt Trigger');
    
    [nRows, nCols] = calculate_subplot_layout(num_to_plot);
    
    for i = 1:num_to_plot
        roi_num = removed_rois(i);
        roi_idx = find_roi_index(headers, roi_num);
        
        if isempty(roi_idx)
            continue;
        end
        
        subplot(nRows, nCols, i);
        
        trace = dF_values(:, roi_idx);
        threshold = thresholds(roi_idx);
        
        % Standardized y-axis limits
        ylim([-0.02, 0.04]);
        
        % Plot trace
        plot(timeData_ms, trace, 'b-', 'LineWidth', 1.5);
        hold on;
        
        % Plot stimulus line with max at y=0.05
        plot([stimTime_ms, stimTime_ms], [-0.04, 0.05], 'g--', 'LineWidth', 1, 'DisplayName', 'Stimulus');
        
        % Plot current method threshold (3σ)
        plot(xlim, [threshold, threshold], 'r--', 'LineWidth', 1, 'DisplayName', 'Current (3σ)');
        
        % Calculate and plot Schmitt thresholds
        cfg = GluSnFRConfig();
        if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
            upper_thresh = threshold;        % 3σ for low noise
            lower_thresh = threshold * 0.5;  % 1.5σ
            noise_label = 'Low';
        else
            upper_thresh = threshold * 1.5;  % 4.5σ for high noise
            lower_thresh = threshold * 0.5;  % 1.5σ
            noise_label = 'High';
        end
        
        plot(xlim, [upper_thresh, upper_thresh], 'm--', 'LineWidth', 1, 'DisplayName', 'Schmitt Upper');
        plot(xlim, [lower_thresh, lower_thresh], 'c--', 'LineWidth', 1, 'DisplayName', 'Schmitt Lower');
        
        % Analyze why this ROI was removed with enhanced details
        schmitt_filter = schmitt_trigger_filter();
        [passes, details] = schmitt_filter.applySchmittTrigger(trace, upper_thresh, lower_thresh, ...
                                                             results.experimentType, [], cfg);
        
        reason = '';
        if ~details.triggered
            reason = 'No trigger';
        elseif details.valid_signals == 0
            if details.invalid_signals > 0
                reason = sprintf('%d brief signals (<%dms)', details.invalid_signals, 2*5); % 2 frames * 5ms
            else
                reason = 'No valid signals';
            end
        end
        
        % Add max response info for debugging
        stimFrame = cfg.timing.STIMULUS_FRAME;
        postStimWindow = stimFrame + (1:30);
        postStimWindow = postStimWindow(postStimWindow <= length(trace));
        if ~isempty(postStimWindow)
            maxResp = max(trace(postStimWindow));
            reason = sprintf('%s (max=%.3f)', reason, maxResp);
        end
        
        title(sprintf('ROI %d - REMOVED (%s noise)\n%s', roi_num, noise_label, reason), ...
              'FontSize', 10, 'Color', 'red');
        xlabel('Time (ms)');
        ylabel('ΔF/F');
        
        if i == 1
            legend('Location', 'northeast', 'FontSize', 8);
        end
        
        grid on;
        hold off;
    end
    
    sgtitle('ROIs Removed by Schmitt Trigger (Potential False Positives)', ...
            'FontSize', 14, 'FontWeight', 'bold', 'Color', 'red');
end

function plot_added_rois(results, dF_values, headers, timeData_ms, stimTime_ms, thresholds)
    % Plot ROIs that were added by Schmitt trigger with enhanced visualization
    
    added_rois = results.comparison.schmitt_only;
    num_to_plot = min(12, length(added_rois));
    
    if num_to_plot == 0
        return;
    end
    
    figure('Position', [200, 200, 1400, 900], 'Name', 'ROIs Added by Schmitt Trigger');
    
    [nRows, nCols] = calculate_subplot_layout(num_to_plot);
    
    for i = 1:num_to_plot
        roi_num = added_rois(i);
        roi_idx = find_roi_index(headers, roi_num);
        
        if isempty(roi_idx)
            continue;
        end
        
        subplot(nRows, nCols, i);
        
        trace = dF_values(:, roi_idx);
        threshold = thresholds(roi_idx);
        
        % Standardized y-axis limits
        ylim([-0.02, 0.04]);
        
        % Plot trace
        plot(timeData_ms, trace, 'b-', 'LineWidth', 1.5);
        hold on;
        
        % Plot stimulus line with max at y=0
        plot([stimTime_ms, stimTime_ms], [-0.02, 0], 'g--', 'LineWidth', 1, 'DisplayName', 'Stimulus');
        
        % Plot current method threshold (3σ)
        plot(xlim, [threshold, threshold], 'r--', 'LineWidth', 1, 'DisplayName', 'Current (3σ)');
        
        % Calculate and plot Schmitt thresholds
        cfg = GluSnFRConfig();
        if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
            upper_thresh = threshold;        % 3σ for low noise
            lower_thresh = threshold * 0.5;  % 1.5σ
            noise_label = 'Low';
        else
            upper_thresh = threshold * 1.5;  % 4.5σ for high noise
            lower_thresh = threshold * 0.5;  % 1.5σ
            noise_label = 'High';
        end
        
        plot(xlim, [upper_thresh, upper_thresh], 'm--', 'LineWidth', 1, 'DisplayName', 'Schmitt Upper');
        plot(xlim, [lower_thresh, lower_thresh], 'c--', 'LineWidth', 1, 'DisplayName', 'Schmitt Lower');
        
        % Analyze why this ROI was added
        cfg = GluSnFRConfig();
        stimFrame = cfg.timing.STIMULUS_FRAME;
        postStimWindow = stimFrame + (1:30);
        postStimWindow = postStimWindow(postStimWindow <= length(trace));
        if ~isempty(postStimWindow)
            max_response = max(trace(postStimWindow));
        else
            max_response = 0;
        end
        current_passes = max_response > threshold;
        
        reason = '';
        if ~current_passes
            reason = sprintf('Below 3σ (%.3f < %.3f)', max_response, threshold);
        end
        
        title(sprintf('ROI %d - ADDED (%s noise)\n%s', roi_num, noise_label, reason), ...
              'FontSize', 10, 'Color', 'blue');
        xlabel('Time (ms)');
        ylabel('ΔF/F');
        
        if i == 1
            legend('Location', 'northeast', 'FontSize', 8);
        end
        
        grid on;
        hold off;
    end
    
    sgtitle('ROIs Added by Schmitt Trigger (Missed by Current Method)', ...
            'FontSize', 14, 'FontWeight', 'bold', 'Color', 'blue');
end


function plot_schmitt_trigger_examples(results, dF_values, headers, timeData_ms, stimTime_ms, thresholds)
    % Plot examples showing Schmitt trigger logic in action with enhanced visualization
    
    % Find good examples: some that pass, some that fail
    all_rois = 1:min(50, size(dF_values, 2)); % Look at first 50 ROIs
    examples = [];
    example_labels = {};
    
    cfg = GluSnFRConfig();
    schmitt_filter = schmitt_trigger_filter();
    
    % Find examples of different behaviors
    for roi_idx = all_rois
        trace = dF_values(:, roi_idx);
        threshold = thresholds(roi_idx);
        
        if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
            upper_thresh = threshold;
            lower_thresh = threshold * 0.5;
        else
            upper_thresh = threshold * 1.5;
            lower_thresh = threshold * 0.5;
        end
        
        [passes, details] = schmitt_filter.applySchmittTrigger(trace, upper_thresh, lower_thresh, ...
                                                             results.experimentType, [], cfg);
        
        % Categorize this ROI
        if passes && details.valid_signals > 0
            if length(examples) < 2 || ~any(strcmp(example_labels, 'Valid Signal'))
                examples(end+1) = roi_idx;
                example_labels{end+1} = 'Valid Signal';
            end
        elseif details.triggered && details.invalid_signals > 0 && details.valid_signals == 0
            if length(examples) < 4 || ~any(strcmp(example_labels, 'Invalid Signal'))
                examples(end+1) = roi_idx;
                example_labels{end+1} = 'Invalid Signal';
            end
        elseif ~details.triggered
            if length(examples) < 6 || ~any(strcmp(example_labels, 'No Trigger'))
                examples(end+1) = roi_idx;
                example_labels{end+1} = 'No Trigger';
            end
        end
        
        if length(examples) >= 6
            break;
        end
    end
    
    if isempty(examples)
        return;
    end
    
    figure('Position', [250, 250, 1400, 900], 'Name', 'Schmitt Trigger Logic Examples');
    
    [nRows, nCols] = calculate_subplot_layout(length(examples));
    
    for i = 1:length(examples)
        roi_idx = examples(i);
        roi_num = extract_roi_number_from_header(headers{roi_idx});
        
        subplot(nRows, nCols, i);
        
        trace = dF_values(:, roi_idx);
        threshold = thresholds(roi_idx);
        
        % Standardized y-axis limits
        ylim([-0.02, 0.04]);
        
        % Calculate Schmitt thresholds
        if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
            upper_thresh = threshold;
            lower_thresh = threshold * 0.5;
            noise_label = 'Low';
        else
            upper_thresh = threshold * 1.5;
            lower_thresh = threshold * 0.5;
            noise_label = 'High';
        end
        
        % Plot trace
        plot(timeData_ms, trace, 'b-', 'LineWidth', 2);
        hold on;
        
        % Plot thresholds
        plot(xlim, [upper_thresh, upper_thresh], 'm--', 'LineWidth', 2, 'DisplayName', 'Upper (Trigger)');
        plot(xlim, [lower_thresh, lower_thresh], 'c--', 'LineWidth', 2, 'DisplayName', 'Lower (Reset)');
        
        % Plot stimulus line with max at y=0
        plot([stimTime_ms, stimTime_ms], [-0.02, 0], 'g--', 'LineWidth', 1.5, 'DisplayName', 'Stimulus');
        
        % Analyze and highlight trigger points
        [passes, details] = schmitt_filter.applySchmittTrigger(trace, upper_thresh, lower_thresh, ...
                                                             results.experimentType, [], cfg);
        
        % Highlight trigger regions
        stim_frame = cfg.timing.STIMULUS_FRAME;
        search_start = max(1, stim_frame + 1);
        search_end = min(length(trace), stim_frame + 50);
        
        above_upper = trace > upper_thresh;
        trigger_points = find(above_upper(search_start:search_end));
        
        if ~isempty(trigger_points)
            trigger_frames = search_start + trigger_points - 1;
            scatter(timeData_ms(trigger_frames), trace(trigger_frames), 60, 'm', 'filled', ...
                   'DisplayName', 'Triggers');
        end
        
        title_color = 'black';
        if strcmp(example_labels{i}, 'Valid Signal')
            title_color = 'green';
        elseif strcmp(example_labels{i}, 'Invalid Signal')
            title_color = 'red';
        end
        
        title(sprintf('ROI %d - %s (%s noise)\nValid: %d, Invalid: %d', ...
              roi_num, example_labels{i}, noise_label, details.valid_signals, details.invalid_signals), ...
              'FontSize', 10, 'Color', title_color);
        
        xlabel('Time (ms)');
        ylabel('ΔF/F');
        
        if i == 1
            legend('Location', 'northeast', 'FontSize', 8);
        end
        
        grid on;
        hold off;
    end
    
    sgtitle('Schmitt Trigger Logic Examples', 'FontSize', 14, 'FontWeight', 'bold');
end

function inspect_specific_rois(results, roi_numbers, dF_values, headers, timeData_ms, stimTime_ms, thresholds)
    % NEW FUNCTION: Inspect specific ROIs of interest
    % Usage: inspect_specific_rois(results, [5, 18, 19], dF_values, headers, timeData_ms, stimTime_ms, thresholds)
    
    if isempty(roi_numbers)
        fprintf('No ROIs specified for inspection.\n');
        return;
    end
    
    cfg = GluSnFRConfig();
    schmitt_filter = schmitt_trigger_filter();
    
    % Check which ROIs were removed vs kept
    current_rois = extractROINumbers(results.current.rois);
    schmitt_rois = extractROINumbers(results.schmitt.rois);
    
    figure('Position', [100, 100, 1600, 1000], 'Name', 'Specific ROI Inspection');
    
    num_rois = length(roi_numbers);
    [nRows, nCols] = calculate_subplot_layout(num_rois);
    
    for i = 1:num_rois
        roi_num = roi_numbers(i);
        roi_idx = find_roi_index(headers, roi_num);
        
        if isempty(roi_idx)
            fprintf('ROI %d not found in headers.\n', roi_num);
            continue;
        end
        
        subplot(nRows, nCols, i);
        
        trace = dF_values(:, roi_idx);
        threshold = thresholds(roi_idx);
        
        % Standardized y-axis limits
        ylim([-0.02, 0.04]);
        
        % Plot trace
        plot(timeData_ms, trace, 'b-', 'LineWidth', 2);
        hold on;
        
        % Plot stimulus line with max at y=0
        plot([stimTime_ms, stimTime_ms], [-0.02, 0], 'g--', 'LineWidth', 1.5, 'DisplayName', 'Stimulus');
        
        % Calculate thresholds
        if threshold <= cfg.thresholds.LOW_NOISE_CUTOFF
            upper_thresh = threshold;
            lower_thresh = threshold * 0.5;
            noise_label = 'Low';
        else
            upper_thresh = threshold * 1.5;
            lower_thresh = threshold * 0.5;
            noise_label = 'High';
        end
        
        % Plot thresholds
        plot(xlim, [threshold, threshold], 'r--', 'LineWidth', 1.5, 'DisplayName', 'Current (3σ)');
        plot(xlim, [upper_thresh, upper_thresh], 'm--', 'LineWidth', 1.5, 'DisplayName', 'Schmitt Upper');
        plot(xlim, [lower_thresh, lower_thresh], 'c--', 'LineWidth', 1.5, 'DisplayName', 'Schmitt Lower');
        
        % Analyze both methods
        % Current method
        stimFrame = cfg.timing.STIMULUS_FRAME;
        postStimWindow = stimFrame + (1:30);
        postStimWindow = postStimWindow(postStimWindow <= length(trace));
        if ~isempty(postStimWindow)
            max_response = max(trace(postStimWindow));
        else
            max_response = 0;
        end
        current_passes = max_response > threshold;
        
        % Schmitt method
        [schmitt_passes, details] = schmitt_filter.applySchmittTrigger(trace, upper_thresh, lower_thresh, ...
                                                                     results.experimentType, [], cfg);
        
        % Determine status
        in_current = ismember(roi_num, current_rois);
        in_schmitt = ismember(roi_num, schmitt_rois);
        
        if in_current && in_schmitt
            status = 'BOTH PASS';
            color = 'green';
        elseif in_current && ~in_schmitt
            status = 'REMOVED by Schmitt';
            color = 'red';
        elseif ~in_current && in_schmitt
            status = 'ADDED by Schmitt';
            color = 'blue';
        else
            status = 'BOTH FAIL';
            color = 'black';
        end
        
        % Add detailed analysis
        analysis = sprintf('Max resp: %.3f | Triggered: %s | Valid: %d | Invalid: %d', ...
                          max_response, logical2str(details.triggered), ...
                          details.valid_signals, details.invalid_signals);
        
        title(sprintf('ROI %d - %s (%s noise)\n%s', roi_num, status, noise_label, analysis), ...
              'FontSize', 10, 'Color', color);
        xlabel('Time (ms)');
        ylabel('ΔF/F');
        
        if i == 1
            legend('Location', 'northeast', 'FontSize', 8);
        end
        
        grid on;
        hold off;
    end
    
    sgtitle('Specific ROI Inspection', 'FontSize', 14, 'FontWeight', 'bold');
end

function str = logical2str(val)
    if val
        str = 'YES';
    else
        str = 'NO';
    end
end

function roi_numbers = extractROINumbers(rois)
    % Helper function to extract ROI numbers from various formats
    if iscell(rois)
        roi_numbers = [];
        for i = 1:length(rois)
            matches = regexp(rois{i}, 'ROI[_\s]*(\d+)', 'tokens', 'ignorecase');
            if ~isempty(matches)
                roi_numbers(end+1) = str2double(matches{1}{1});
            end
        end
    else
        roi_numbers = rois; % Assume already numeric
    end
    roi_numbers = sort(roi_numbers);
end

function [nRows, nCols] = calculate_subplot_layout(n)
    % Calculate optimal subplot layout
    if n <= 1
        nRows = 1; nCols = 1;
    elseif n <= 2
        nRows = 1; nCols = 2;
    elseif n <= 4
        nRows = 2; nCols = 2;
    elseif n <= 6
        nRows = 2; nCols = 3;
    elseif n <= 9
        nRows = 3; nCols = 3;
    elseif n <= 12
        nRows = 3; nCols = 4;
    else
        nRows = 4; nCols = 4;
    end
end

function roi_idx = find_roi_index(headers, roi_num)
    % Find index of ROI in headers array
    roi_idx = [];
    for i = 1:length(headers)
        if contains(headers{i}, sprintf('ROI %d', roi_num)) || ...
           contains(headers{i}, sprintf('ROI%d', roi_num)) || ...
           contains(headers{i}, sprintf('ROI %03d', roi_num))
            roi_idx = i;
            return;
        end
    end
end

function roi_num = extract_roi_number_from_header(header)
    % Extract ROI number from header string
    matches = regexp(header, 'ROI[_\s]*(\d+)', 'tokens', 'ignorecase');
    if ~isempty(matches)
        roi_num = str2double(matches{1}{1});
    else
        roi_num = 0;
    end
end