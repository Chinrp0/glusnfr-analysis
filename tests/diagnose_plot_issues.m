function diagnose_plot_issues()
    % DIAGNOSE_PLOT_ISSUES - Comprehensive diagnostic for plot generation problems
    %
    % Run this after your main pipeline to diagnose why plots aren't being generated
    % Usage: diagnose_plot_issues()
    
    fprintf('\n=== PLOT GENERATION DIAGNOSTIC ===\n');
    
    % Step 1: Check configuration
    fprintf('\n1. Checking Configuration:\n');
    cfg = GluSnFRConfig();
    
    fprintf('   ENABLE_INDIVIDUAL_TRIALS: %s\n', mat2str(cfg.plotting.ENABLE_INDIVIDUAL_TRIALS));
    fprintf('   ENABLE_ROI_AVERAGES: %s\n', mat2str(cfg.plotting.ENABLE_ROI_AVERAGES));
    fprintf('   ENABLE_COVERSLIP_AVERAGES: %s\n', mat2str(cfg.plotting.ENABLE_COVERSLIP_AVERAGES));
    fprintf('   DEBUG mode: %s\n', mat2str(cfg.debug.ENABLE_PLOT_DEBUG));
    
    % Step 2: Check for output directories
    fprintf('\n2. Checking Output Directories:\n');
    
    % Try to find the most recent output directory
    baseDir = 'D:\Data\GluSnFR\Ms\2025-06-17_Ms-Hipp_DIV13_Doc2b_pilot_resave\iglu3fast_NGR\1AP\GPU_Processed_Images_1AP\';
    if exist(baseDir, 'dir')
        plotDir = fullfile(baseDir, sprintf('6_v%s_dF_plots', cfg.version(1:2)));
        
        if exist(plotDir, 'dir')
            fprintf('   Plot directory exists: %s\n', plotDir);
            
            subDirs = {'ROI_trials', 'ROI_Averages', 'Coverslip_Averages'};
            for i = 1:length(subDirs)
                subPath = fullfile(plotDir, subDirs{i});
                if exist(subPath, 'dir')
                    files = dir(fullfile(subPath, '*.png'));
                    fprintf('   %s: %d files\n', subDirs{i}, length(files));
                else
                    fprintf('   %s: MISSING!\n', subDirs{i});
                end
            end
        else
            fprintf('   Plot directory NOT FOUND: %s\n', plotDir);
        end
    else
        fprintf('   Base directory not accessible\n');
    end
    
    % Step 3: Test plot generation with sample data
    fprintf('\n3. Testing Plot Generation:\n');
    test_plot_generation();
    
    % Step 4: Check module loading
    fprintf('\n4. Checking Module Loading:\n');
    try
        modules = module_loader();
        fprintf('   Module loader: OK\n');
        
        if isfield(modules, 'plot')
            fprintf('   Plot controller loaded: OK\n');
        else
            fprintf('   Plot controller: MISSING!\n');
        end
        
        % Check if plot functions exist
        plot1AP = plot_1ap();
        fprintf('   plot_1ap loaded: OK\n');
        
        plotPPF = plot_ppf();
        fprintf('   plot_ppf loaded: OK\n');
        
    catch ME
        fprintf('   Module loading FAILED: %s\n', ME.message);
    end
    
    % Step 5: Check filtering statistics availability
    fprintf('\n5. Checking Filtering Statistics:\n');
    check_filtering_stats();
    
    fprintf('\n=== DIAGNOSTIC COMPLETE ===\n');
end

function test_plot_generation()
    % Test basic plot generation with minimal data
    
    try
        % Create minimal test data
        n_frames = 600;
        n_rois = 3;
        n_trials = 2;
        
        % Create test organized data
        timeData_ms = (0:n_frames-1)' * 5;
        organizedData = table();
        organizedData.Frame = timeData_ms;
        
        % Add some ROI data
        for roi = 1:n_rois
            for trial = 1:n_trials
                colName = sprintf('ROI%d_T%d', roi, trial);
                % Create synthetic data with a response
                data = 0.01 * randn(n_frames, 1);
                data(267:280) = data(267:280) + 0.05; % Add response
                organizedData.(colName) = single(data);
            end
        end
        
        % Create minimal roiInfo
        roiInfo = struct();
        roiInfo.roiNumbers = (1:n_rois)';
        roiInfo.originalTrialNumbers = (1:n_trials)';
        roiInfo.experimentType = '1AP';
        roiInfo.numTrials = n_trials;
        roiInfo.thresholds = 0.02 * ones(n_rois, n_trials);
        
        % Create noise map
        roiInfo.roiNoiseMap = containers.Map('KeyType', 'double', 'ValueType', 'char');
        for roi = 1:n_rois
            if roi <= 2
                roiInfo.roiNoiseMap(roi) = 'low';
            else
                roiInfo.roiNoiseMap(roi) = 'high';
            end
        end
        
        % Create filtering stats
        roiInfo.filteringStats = struct();
        roiInfo.filteringStats.available = true;
        roiInfo.filteringStats.roiNoiseMap = roiInfo.roiNoiseMap;
        roiInfo.filteringStats.roiUpperThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
        roiInfo.filteringStats.roiLowerThresholds = containers.Map('KeyType', 'int32', 'ValueType', 'double');
        
        for roi = 1:n_rois
            roiInfo.filteringStats.roiUpperThresholds(roi) = 0.02;
            roiInfo.filteringStats.roiLowerThresholds(roi) = 0.007;
        end
        
        fprintf('   Test data created: %d ROIs, %d trials\n', n_rois, n_trials);
        
        % Try to create a plot
        config = GluSnFRConfig();
        utils = plot_utilities();
        plotConfig = utils.getPlotConfig(config);
        
        % Test figure creation
        fig = utils.createFigure('standard');
        if ishandle(fig)
            fprintf('   Figure creation: OK\n');
            close(fig);
        else
            fprintf('   Figure creation: FAILED\n');
        end
        
        % Test plot task creation
        plot1AP = plot_1ap();
        task = struct('type', 'trials', 'experimentType', '1AP', ...
                     'data', organizedData, 'roiInfo', roiInfo, ...
                     'groupKey', 'TEST_GROUP', 'outputFolder', tempdir);
        
        success = plot1AP.execute(task, config);
        if success
            fprintf('   Test plot generation: OK\n');
            
            % Check if file was created
            testFile = fullfile(tempdir, 'TEST_GROUP_trials.png');
            if exist(testFile, 'file')
                fprintf('   Test plot saved: OK\n');
                delete(testFile); % Clean up
            else
                fprintf('   Test plot save: FAILED\n');
            end
        else
            fprintf('   Test plot generation: FAILED\n');
        end
        
    catch ME
        fprintf('   Test FAILED: %s\n', ME.message);
        fprintf('   Stack: %s at line %d\n', ME.stack(1).name, ME.stack(1).line);
    end
end

function check_filtering_stats()
    % Check if filtering statistics are being properly generated
    
    try
        % Create test data
        n_frames = 600;
        n_rois = 10;
        dF_values = 0.01 * randn(n_frames, n_rois, 'single');
        headers = arrayfun(@(x) sprintf('ROI %03d', x), 1:n_rois, 'UniformOutput', false);
        thresholds = 0.02 * ones(1, n_rois);
        
        % Apply filter
        filter = roi_filter();
        [filteredData, filteredHeaders, filteredThresholds, stats] = ...
            filter.filterROIs(dF_values, headers, thresholds, '1AP');
        
        fprintf('   Filter applied: %d/%d ROIs passed\n', length(filteredHeaders), n_rois);
        
        % Check if Schmitt info is present
        if isfield(stats, 'schmitt_info')
            fprintf('   Schmitt trigger info: PRESENT\n');
            
            if isfield(stats.schmitt_info, 'upper_thresholds')
                fprintf('   Upper thresholds: %d values\n', length(stats.schmitt_info.upper_thresholds));
            else
                fprintf('   Upper thresholds: MISSING!\n');
            end
            
            if isfield(stats.schmitt_info, 'noise_classification')
                fprintf('   Noise classification: %d values\n', length(stats.schmitt_info.noise_classification));
            else
                fprintf('   Noise classification: MISSING!\n');
            end
        else
            fprintf('   Schmitt trigger info: MISSING!\n');
            fprintf('   Filter method used: %s\n', stats.method);
        end
        
    catch ME
        fprintf('   Filtering test FAILED: %s\n', ME.message);
    end
end
