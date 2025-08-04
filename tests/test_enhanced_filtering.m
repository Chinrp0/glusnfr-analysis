function test_enhanced_filtering()
    % TEST_ENHANCED_FILTERING - Compare original vs enhanced filtering
    %
    % This script tests the new iGlu3Fast-optimized filtering against
    % your current filtering method and shows detailed comparisons.
    
    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('   Enhanced Filtering Test for iGlu3Fast (Ultrafast)      \n');
    fprintf('============================================================\n');
    fprintf('Testing enhanced temporal and kinetic validation optimized\n');
    fprintf('for iGlu3Fast ultrafast glutamate sensor characteristics.\n\n');
    
    try
        % Load modules
        addpath(genpath(pwd));
        modules = module_loader();
        fprintf('✓ Pipeline modules loaded\n');
        
        % Load enhanced filtering
        enhanced_filter = enhanced_filtering_system();
        fprintf('✓ Enhanced filtering module loaded\n');
        
    catch ME
        fprintf('✗ Error loading modules: %s\n', ME.message);
        fprintf('Make sure enhanced_filtering_system.m is in your path\n');
        return;
    end
    
    % Select test file
    fprintf('\nStep 1: Select test file\n');
    [filename, pathname] = uigetfile('*.xlsx', 'Select Excel file for filtering comparison');
    
    if isequal(filename, 0)
        fprintf('No file selected, exiting...\n');
        return;
    end
    
    filepath = fullfile(pathname, filename);
    fprintf('Selected: %s\n', filename);
    
    % Read and process data
    fprintf('\nStep 2: Reading and processing data...\n');
    try
        [rawData, headers, success] = modules.io.readExcelFile(filepath, true);
        if ~success || isempty(rawData)
            error('Failed to read file');
        end
        
        % Extract data
        traces = single(rawData(:, 2:end));
        validHeaders = headers(2:end);
        [n_frames, n_rois] = size(traces);
        
        fprintf('✓ Read %d frames × %d ROIs\n', n_frames, n_rois);
        
        % Calculate dF/F using your current method
        [dF_values, thresholds, gpuUsed] = modules.calc.calculate(traces, true, struct('memory', 4));
        fprintf('✓ Calculated dF/F (%s)\n', ternary(gpuUsed, 'GPU', 'CPU'));
        
    catch ME
        fprintf('✗ Error processing file: %s\n', ME.message);
        return;
    end
    
    % Determine experiment type
    experimentType = '1AP';  % Default
    if contains(filename, 'PPF')
        experimentType = 'PPF';
        % Extract PPF timepoint if present
        ppfMatch = regexp(filename, 'PPF-(\d+)ms', 'tokens');
        if ~isempty(ppfMatch)
            ppfTimepoint = str2double(ppfMatch{1}{1});
        else
            ppfTimepoint = 30; % Default
        end
    else
        ppfTimepoint = [];
    end
    
    fprintf('✓ Detected experiment type: %s\n', experimentType);
    
    % Optional: Ask for known responding ROIs
    fprintf('\nStep 3: Known responding ROIs (optional)\n');
    fprintf('If you know which ROIs should respond (e.g., ROI 235), enter them.\n');
    fprintf('This helps evaluate filter performance.\n');
    knownResponders = input('Enter known ROI numbers [235, 150, ...] or press Enter to skip: ');
    
    if isempty(knownResponders)
        fprintf('No known responders specified - will compare methods only\n');
    else
        fprintf('Will analyze detection of %d known responders\n', length(knownResponders));
    end
    
    % Run comprehensive comparison
    fprintf('\nStep 4: Running filtering comparison...\n');
    fprintf('This compares your current filtering vs enhanced iGlu3Fast filtering\n');
    
    tic;
    if isempty(knownResponders)
        comparison = enhanced_filter.compareFilteringMethods(dF_values, validHeaders, thresholds, experimentType, ...
            'PlotResults', true, 'SaveResults', true, 'PPFTimepoint', ppfTimepoint);
    else
        comparison = enhanced_filter.compareFilteringMethods(dF_values, validHeaders, thresholds, experimentType, ...
            'PlotResults', true, 'SaveResults', true, 'PPFTimepoint', ppfTimepoint, ...
            'AnalyzeKnownResponders', knownResponders);
    end
    
    comparisonTime = toc;
    fprintf('✓ Comparison completed in %.2f seconds\n', comparisonTime);
    
    % Detailed analysis
    fprintf('\nStep 5: Detailed Analysis\n');
    fprintf('========================\n');
    
    % Show which ROIs were affected by enhanced filtering
    if ~isempty(comparison.original_only)
        fprintf('\nROIs removed by enhanced filtering:\n');
        fprintf('(These may be false positives)\n');
        for i = 1:min(10, length(comparison.original_only))  % Show first 10
            fprintf('  ROI %d\n', comparison.original_only(i));
        end
        if length(comparison.original_only) > 10
            fprintf('  ... and %d more\n', length(comparison.original_only) - 10);
        end
    end
    
    if ~isempty(comparison.enhanced_only)
        fprintf('\nROIs added by enhanced filtering:\n');
        fprintf('(These passed enhanced criteria but not original)\n');
        for i = 1:min(5, length(comparison.enhanced_only))
            fprintf('  ROI %d\n', comparison.enhanced_only(i));
        end
    end
    
    % Performance analysis
    fprintf('\nPerformance Summary:\n');
    fprintf('  Original method: %d ROIs passed\n', comparison.original.count);
    fprintf('  Enhanced method: %d ROIs passed\n', comparison.enhanced.count);
    fprintf('  Net change: %+d ROIs (%.1f%% change)\n', ...
            comparison.enhanced.count - comparison.original.count, ...
            (comparison.enhanced.count - comparison.original.count) / comparison.original.count * 100);
    
    % Enhanced filtering stages breakdown
    if isfield(comparison.enhanced.stats, 'filtering_stages')
        stages = comparison.enhanced.stats.filtering_stages;
        fprintf('\nEnhanced Filtering Breakdown:\n');
        if isfield(stages, 'basic_pass')
            fprintf('  After basic filtering: %d ROIs\n', stages.basic_pass);
        end
        if isfield(stages, 'enhanced_pass')
            fprintf('  After enhanced filtering: %d ROIs\n', stages.enhanced_pass);
        end
        if isfield(stages, 'additional_filtering')
            fprintf('  Additional ROIs removed: %d\n', stages.additional_filtering);
        end
    end
    
    % Temporal validation results
    if isfield(comparison.enhanced.stats, 'temporal_validation')
        tv = comparison.enhanced.stats.temporal_validation;
        fprintf('\nTemporal Validation Results:\n');
        fprintf('  ROIs passing temporal validation: %d/%d (%.1f%%)\n', ...
                tv.passed_temporal, tv.total_rois, tv.temporal_pass_rate * 100);
    end
    
    % Kinetic analysis results
    if isfield(comparison.enhanced.stats, 'kinetic_analysis')
        ka = comparison.enhanced.stats.kinetic_analysis;
        fprintf('\nKinetic Analysis Results:\n');
        fprintf('  ROIs passing kinetic validation: %d/%d (%.1f%%)\n', ...
                ka.passed_kinetic, ka.total_rois, ka.kinetic_pass_rate * 100);
    end
    
    % Known responders analysis
    if ~isempty(knownResponders) && isfield(comparison, 'known_responders')
        kr = comparison.known_responders;
        fprintf('\nKnown Responders Analysis:\n');
        fprintf('  Known responders provided: %d ROIs\n', length(knownResponders));
        fprintf('  Original method detected: %d/%d (%.1f%%)\n', ...
                kr.original_detected, length(knownResponders), kr.original_detection_rate * 100);
        fprintf('  Enhanced method detected: %d/%d (%.1f%%)\n', ...
                kr.enhanced_detected, length(knownResponders), kr.enhanced_detection_rate * 100);
        
        if ~isempty(kr.missed_by_enhanced) && isempty(kr.missed_by_original)
            fprintf('  ⚠ Enhanced method misses some known responders: ROI %s\n', ...
                    sprintf('%d ', kr.missed_by_enhanced));
        elseif length(kr.missed_by_enhanced) < length(kr.missed_by_original)
            fprintf('  ✓ Enhanced method detects more known responders\n');
        end
    end
    
    % Generate recommendation and next steps
    fprintf('\nStep 6: Recommendations\n');
    fprintf('======================\n');
    
    selectivity_improvement = comparison.metrics.selectivity_improvement;
    
    if selectivity_improvement > 0.05
        fprintf('🟢 ENHANCED FILTERING RECOMMENDED\n');
        fprintf('\nWhy enhanced filtering is better for your data:\n');
        fprintf('  ✓ Removes %.1f%% more false positives\n', selectivity_improvement * 100);
        fprintf('  ✓ Uses iGlu3Fast ultrafast kinetics (%.1fms decay vs %.1fms)\n', 3.3, 14.1);
        fprintf('  ✓ Temporal validation (%.1f-%.1fms rise time)\n', 2.0, 25.0);
        fprintf('  ✓ Advanced kinetic analysis\n');
        
        fprintf('\nTo implement enhanced filtering:\n');
        fprintf('1. Add to your GluSnFRConfig.m:\n');
        fprintf('   config.filtering.ENABLE_ENHANCED_FILTERING = true;\n');
        fprintf('   config.filtering.ENABLE_TEMPORAL_VALIDATION = true;\n');
        fprintf('   config.filtering.ENABLE_KINETIC_ANALYSIS = true;\n\n');
        
        fprintf('2. Update your roi_filter calls to use enhanced mode:\n');
        fprintf('   [filtered, headers, thresh, stats] = enhanced_filter.filterROIsEnhanced(...\n');
        fprintf('       dF_values, headers, thresholds, experimentType);\n\n');
        
    elseif selectivity_improvement > 0
        fprintf('🟡 MODERATE IMPROVEMENT\n');
        fprintf('Enhanced filtering removes %.1f%% more ROIs\n', selectivity_improvement * 100);
        fprintf('Consider implementing if false positives are a concern\n');
        
    elseif selectivity_improvement < -0.05
        fprintf('🔴 ENHANCED FILTERING TOO AGGRESSIVE\n');
        fprintf('Enhanced filtering may be removing valid responses\n');
        fprintf('Your current filtering appears well-tuned for your data\n');
        
    else
        fprintf('🔵 BOTH METHODS SIMILAR\n');
        fprintf('Minimal difference between methods\n');
        fprintf('Your current filtering is working well\n');
    end
    
    % File outputs
    fprintf('\nGenerated Files:\n');
    if exist('filtering_comparison_results.mat', 'file')
        fprintf('  ✓ filtering_comparison_results.mat - Detailed comparison data\n');
    end
    fprintf('  ✓ Comparison plots displayed\n');
    
    fprintf('\nTest completed! Review the plots and recommendations above.\n');
end

function testSingleROI()
    % TESTSINGLEORI - Quick test of enhanced filtering on single ROI
    %
    % Use this for debugging specific ROI behavior
    
    fprintf('=== Single ROI Enhanced Filtering Test ===\n');
    
    % Get test parameters
    roiNumber = input('Enter ROI number to test: ');
    if isempty(roiNumber)
        roiNumber = 235;  % Default to a known responder
    end
    
    % Load data (reuse from main test)
    try
        modules = module_loader();
        enhanced_filter = enhanced_filtering_system();
        
        [filename, pathname] = uigetfile('*.xlsx', 'Select Excel file');
        filepath = fullfile(pathname, filename);
        
        [rawData, headers, ~] = modules.io.readExcelFile(filepath, true);
        traces = single(rawData(:, 2:end));
        validHeaders = headers(2:end);
        
        [dF_values, thresholds, ~] = modules.calc.calculate(traces, false, struct('memory', 4));
        
        % Find ROI
        roiIdx = [];
        for i = 1:length(validHeaders)
            if contains(validHeaders{i}, sprintf('ROI %d', roiNumber)) || ...
               contains(validHeaders{i}, sprintf('ROI%d', roiNumber))
                roiIdx = i;
                break;
            end
        end
        
        if isempty(roiIdx)
            fprintf('ROI %d not found in data\n', roiNumber);
            return;
        end
        
        fprintf('Testing ROI %d (index %d)\n', roiNumber, roiIdx);
        
        % Test individual components
        cfg = getEnhancedConfig();
        dF_trace = dF_values(:, roiIdx);
        
        % Basic threshold test
        basicPass = max(dF_trace(cfg.timing.STIMULUS_FRAME+1:cfg.timing.STIMULUS_FRAME+30)) > thresholds(roiIdx);
        fprintf('Basic threshold test: %s (peak=%.4f, threshold=%.4f)\n', ...
                ternary(basicPass, 'PASS', 'FAIL'), max(dF_trace), thresholds(roiIdx));
        
        % Temporal validation
        temporalPass = enhanced_filter.validateTemporalCharacteristics(dF_trace, cfg, '1AP', []);
        fprintf('Temporal validation: %s\n', ternary(temporalPass, 'PASS', 'FAIL'));
        
        % Kinetic analysis
        kineticPass = analyzeROIKinetics(dF_trace, cfg);
        fprintf('Kinetic analysis: %s\n', ternary(kineticPass, 'PASS', 'FAIL'));
        
        % Plot ROI
        figure('Position', [200, 200, 800, 400]);
        time_ms = (0:length(dF_trace)-1) * 5;
        plot(time_ms, dF_trace, 'b-', 'LineWidth', 2);
        hold on;
        plot([cfg.timing.STIMULUS_TIME_MS, cfg.timing.STIMULUS_TIME_MS], ylim, 'g--', 'LineWidth', 2);
        plot(xlim, [thresholds(roiIdx), thresholds(roiIdx)], 'r--', 'LineWidth', 1);
        
        title(sprintf('ROI %d - Enhanced Filtering Analysis', roiNumber));
        xlabel('Time (ms)'); ylabel('ΔF/F');
        legend('ΔF/F trace', 'Stimulus', 'Threshold', 'Location', 'best');
        grid on;
        
        fprintf('Single ROI test completed\n');
        
    catch ME
        fprintf('Error in single ROI test: %s\n', ME.message);
    end
end

function result = ternary(condition, trueVal, falseVal)
    % Utility function for ternary operator
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end