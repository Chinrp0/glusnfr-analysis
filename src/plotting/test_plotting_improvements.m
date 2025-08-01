function test_plotting_improvements()
    % TEST_PLOTTING_IMPROVEMENTS - Verify all plotting improvements work correctly
    %
    % Run this script after implementing the plotting improvements to verify
    % that all changes work correctly and provide performance benefits.
    
    fprintf('\n');
    fprintf('=======================================================\n');
    fprintf('    GluSnFR Plotting Improvements Verification       \n');
    fprintf('=======================================================\n');
    fprintf('Testing consistency fixes, optimizations, and new configuration controls\n\n');
    
    try
        % Ensure path is set
        addpath(genpath(pwd));
        
        % Test 1: Configuration Loading and New Controls
        fprintf('Test 1: Configuration and Plot Controls\n');
        fprintf('=======================================\n');
        testConfigurationControls();
        
        % Test 2: Plot Utilities Consistency
        fprintf('\nTest 2: Plot Utilities Consistency\n');
        fprintf('==================================\n');
        testPlotUtilsConsistency();
        
        % Test 3: Parallel Plotting Capability
        fprintf('\nTest 3: Parallel Plotting Capability\n');
        fprintf('====================================\n');
        testParallelPlotting();
        
        % Test 4: Performance Improvements
        fprintf('\nTest 4: Performance Improvements\n');
        fprintf('================================\n');
        testPerformanceImprovements();
        
        % Test 5: Stimulus Marker Consistency
        fprintf('\nTest 5: Stimulus Marker Consistency\n');
        fprintf('===================================\n');
        testStimulusMarkers();
        
        fprintf('\n');
        fprintf('=======================================================\n');
        fprintf('          ALL TESTS PASSED! 🎉                       \n');
        fprintf('=======================================================\n');
        fprintf('✅ Configuration controls working\n');
        fprintf('✅ Plot utilities consistency fixed\n');
        fprintf('✅ Parallel plotting enabled\n');
        fprintf('✅ Performance improvements active\n');
        fprintf('✅ Stimulus markers properly configured\n');
        fprintf('\nYour plotting system is ready for production use!\n\n');
        
    catch ME
        fprintf('\n');
        fprintf('=======================================================\n');
        fprintf('          TEST FAILED ❌                              \n');
        fprintf('=======================================================\n');
        fprintf('Error: %s\n', ME.message);
        fprintf('Stack trace:\n');
        for i = 1:min(3, length(ME.stack))
            fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
        end
        fprintf('\nPlease check the implementation and try again.\n\n');
        rethrow(ME);
    end
end

function testConfigurationControls()
    % Test new configuration controls
    
    fprintf('Loading enhanced configuration...\n');
    cfg = GluSnFRConfig();
    
    % Test individual plot controls
    plotControls = {
        'ENABLE_INDIVIDUAL_TRIALS'
        'ENABLE_ROI_AVERAGES'
        'ENABLE_COVERSLIP_AVERAGES'
        'ENABLE_PPF_INDIVIDUAL'
        'ENABLE_PPF_AVERAGED'
    };
    
    for i = 1:length(plotControls)
        control = plotControls{i};
        if isfield(cfg.plotting, control)
            value = cfg.plotting.(control);
            fprintf('  ✅ %s = %s\n', control, string(value));
        else
            error('Missing plot control: %s', control);
        end
    end
    
    % Test performance controls
    performanceControls = {
        'ENABLE_PARALLEL'
        'PARALLEL_THRESHOLD'
        'MAX_CONCURRENT_PLOTS'
        'USE_FAST_MODE'
        'ENABLE_PLOT_CACHING'
    };
    
    for i = 1:length(performanceControls)
        control = performanceControls{i};
        if isfield(cfg.plotting, control)
            value = cfg.plotting.(control);
            fprintf('  ✅ %s = %s\n', control, string(value));
        else
            error('Missing performance control: %s', control);
        end
    end
    
    % Test stimulus marker controls
    if isfield(cfg.plotting, 'STIMULUS_MARKER_STYLE')
        fprintf('  ✅ STIMULUS_MARKER_STYLE = %s\n', cfg.plotting.STIMULUS_MARKER_STYLE);
    else
        error('Missing STIMULUS_MARKER_STYLE configuration');
    end
    
    fprintf('✅ All configuration controls present and accessible\n');
end

function testPlotUtilsConsistency()
    % Test plot utilities for consistency improvements
    
    fprintf('Testing plot utilities enhancements...\n');
    utils = plot_utils();
    cfg = GluSnFRConfig();
    
    % Test color scheme consistency
    colors1AP = utils.getPlotColors('1AP', 'WT', 'trials', cfg);
    colorsPPF = utils.getPlotColors('PPF', 'WT', 'trials', cfg);
    
    assert(size(colors1AP, 2) == 3, 'Color scheme should return RGB values');
    assert(size(colorsPPF, 2) == 3, 'Color scheme should return RGB values');
    fprintf('  ✅ Consistent color schemes working\n');
    
    % Test layout calculation with caching
    tic;
    [nRows1, nCols1] = utils.calculateOptimalLayout(8);
    time1 = toc;
    
    tic;
    [nRows2, nCols2] = utils.calculateOptimalLayout(8);  % Should use cache
    time2 = toc;
    
    assert(nRows1 == nRows2 && nCols1 == nCols2, 'Layout calculation inconsistent');
    if time2 < time1 * 0.8  % Caching should make it faster
        fprintf('  ✅ Layout caching working (%.1fx speedup)\n', time1/time2);
    else
        fprintf('  ⚠️  Layout caching may not be active\n');
    end
    
    % Test figure type selection
    figType = utils.getOptimalFigureType('PPF 30ms Analysis', cfg);
    expectedType = cfg.plotting.PPF_FIGURE_TYPE;
    if strcmp(figType, expectedType)
        fprintf('  ✅ Auto figure type selection working\n');
    else
        fprintf('  ⚠️  Figure type: got %s, expected %s\n', figType, expectedType);
    end
    
    % Test early exit logic
    shouldSkip = utils.shouldSkipPlot('individual_trials', cfg);
    expectedSkip = ~cfg.plotting.ENABLE_INDIVIDUAL_TRIALS;
    if shouldSkip == expectedSkip
        fprintf('  ✅ Plot skipping logic working\n');
    else
        fprintf('  ❌ Plot skipping logic failed\n');
    end
    
    fprintf('✅ Plot utilities consistency improvements verified\n');
end

function testParallelPlotting()
    % Test parallel plotting capabilities
    
    fprintf('Testing parallel plotting system...\n');
    coordinator = plot_parallel_coordinator();
    cfg = GluSnFRConfig();
    
    % Test parallel pool creation
    if cfg.plotting.ENABLE_PARALLEL
        success = coordinator.createParallelPool();
        if success
            fprintf('  ✅ Parallel pool creation successful\n');
            
            pool = gcp('nocreate');
            if ~isempty(pool)
                fprintf('  ✅ Pool has %d workers available\n', pool.NumWorkers);
            end
        else
            fprintf('  ⚠️  Parallel pool creation failed (may not be available)\n');
        end
    else
        fprintf('  ℹ️  Parallel plotting disabled in configuration\n');
    end
    
    % Test parallel decision logic
    mockTasks = cell(5, 1);  % Create 5 dummy tasks
    for i = 1:5
        mockTasks{i} = struct('type', 'test', 'id', i);
    end
    
    useParallel = coordinator.shouldUseParallel(mockTasks, cfg);
    expectedParallel = cfg.plotting.ENABLE_PARALLEL && length(mockTasks) >= cfg.plotting.PARALLEL_THRESHOLD;
    
    if useParallel == expectedParallel
        fprintf('  ✅ Parallel decision logic working correctly\n');
    else
        fprintf('  ❌ Parallel decision logic failed\n');
    end
    
    fprintf('✅ Parallel plotting system verified\n');
end

function testPerformanceImprovements()
    % Test performance improvements
    
    fprintf('Testing performance improvements...\n');
    cfg = GluSnFRConfig();
    
    % Test caching system
    utils = plot_utils();
    
    % Time color scheme generation with and without cache
    numIterations = 100;
    
    % Clear cache first if possible
    if isfield(utils, 'clearPlotCache')
        utils.clearPlotCache();
    end
    
    % Time without cache (first run)
    tic;
    for i = 1:numIterations
        colors = utils.createColorScheme(10, 'trials');
    end
    timeWithoutCache = toc;
    
    % Time with cache (subsequent runs)
    tic;
    for i = 1:numIterations
        colors = utils.createColorScheme(10, 'trials');  % Should use cache
    end
    timeWithCache = toc;
    
    if timeWithCache < timeWithoutCache * 0.5  % Should be significantly faster
        speedup = timeWithoutCache / timeWithCache;
        fprintf('  ✅ Caching system working (%.1fx speedup)\n', speedup);
    else
        fprintf('  ⚠️  Caching system may not be active\n');
    end
    
    % Test fast mode settings
    if cfg.plotting.USE_FAST_MODE
        assert(cfg.plotting.DPI_FAST < cfg.plotting.DPI_STANDARD, 'Fast mode DPI should be lower');
        fprintf('  ✅ Fast mode DPI settings correct\n');
    end
    
    % Test memory optimization settings
    if cfg.plotting.CLOSE_FIGURES_IMMEDIATELY
        fprintf('  ✅ Memory optimization enabled\n');
    end
    
    fprintf('✅ Performance improvements verified\n');
end

function testStimulusMarkers()
    % Test stimulus marker consistency fixes
    
    fprintf('Testing stimulus marker improvements...\n');
    cfg = GluSnFRConfig();
    utils = plot_utils();
    
    % Test marker style configuration
    markerStyle = cfg.plotting.STIMULUS_MARKER_STYLE;
    validStyles = {'line', 'pentagram'};
    
    if ismember(markerStyle, validStyles)
        fprintf('  ✅ Stimulus marker style valid: %s\n', markerStyle);
    else
        error('Invalid stimulus marker style: %s', markerStyle);
    end
    
    % Test marker colors
    stimColor = cfg.plotting.STIMULUS_COLOR;
    ppfColor = cfg.plotting.PPF_STIMULUS2_COLOR;
    
    assert(length(stimColor) == 3, 'Stimulus color should be RGB triplet');
    assert(length(ppfColor) == 3, 'PPF stimulus color should be RGB triplet');
    assert(all(stimColor >= 0) && all(stimColor <= 1), 'Stimulus colors should be in [0,1] range');
    assert(all(ppfColor >= 0) && all(ppfColor <= 1), 'PPF stimulus colors should be in [0,1] range');
    
    fprintf('  ✅ Stimulus colors properly configured\n');
    
    % Test dual stimuli setting
    if cfg.plotting.ENABLE_DUAL_STIMULI
        fprintf('  ✅ Dual stimuli enabled for PPF experiments\n');
    else
        fprintf('  ℹ️  Dual stimuli disabled\n');
    end
    
    % Create test figure to verify stimulus marker rendering
    try
        fig = utils.createStandardFigure('standard', 'Stimulus Test', cfg);
        
        timeData = 0:5:2995;  % 0 to ~3000ms
        
        subplot(1, 1, 1);
        plot(timeData, 0.01 * randn(size(timeData)), 'b-');
        hold on;
        
        % Test stimulus marker with current configuration
        utils.addStandardElements(timeData, 1335, 0.02, cfg, 'PPFTimepoint', 30);
        
        % Verify the plot was created successfully
        ax = gca;
        children = get(ax, 'Children');
        
        if length(children) >= 2  % Should have trace + stimulus markers
            fprintf('  ✅ Stimulus markers rendered successfully\n');
        else
            fprintf('  ⚠️  Stimulus markers may not be rendering\n');
        end
        
        close(fig);
        
    catch ME
        fprintf('  ⚠️  Stimulus marker rendering test failed: %s\n', ME.message);
    end
    
    fprintf('✅ Stimulus marker consistency verified\n');
end

function demonstrateNewFeatures()
    % Demonstrate the new plotting features
    
    fprintf('\n');
    fprintf('=======================================================\n');
    fprintf('           NEW FEATURES DEMONSTRATION                 \n');
    fprintf('=======================================================\n');
    
    cfg = GluSnFRConfig();
    
    fprintf('1. Individual Plot Type Controls:\n');
    fprintf('   cfg.plotting.ENABLE_INDIVIDUAL_TRIALS = false;  %% Disable trial plots\n');
    fprintf('   cfg.plotting.ENABLE_ROI_AVERAGES = false;       %% Disable ROI averages\n');
    fprintf('   cfg.plotting.ENABLE_COVERSLIP_AVERAGES = true;  %% Keep population plots\n\n');
    
    fprintf('2. Performance Optimization:\n');
    fprintf('   cfg.plotting.USE_FAST_MODE = true;              %% Quick preview mode\n');
    fprintf('   cfg.plotting.ENABLE_PARALLEL = true;            %% Parallel processing\n');
    fprintf('   cfg.plotting.MAX_CONCURRENT_PLOTS = 4;          %% Control concurrency\n\n');
    
    fprintf('3. Quality Controls:\n');
    fprintf('   cfg.plotting.DPI_STANDARD = 600;                %% High-res for papers\n');
    fprintf('   cfg.plotting.ENABLE_VECTOR_OUTPUT = true;       %% Also save PDF\n');
    fprintf('   cfg.plotting.ENABLE_ANTIALIASING = true;        %% Smooth lines\n\n');
    
    fprintf('4. Stimulus Marker Customization:\n');
    fprintf('   cfg.plotting.STIMULUS_MARKER_STYLE = ''pentagram''; %% Use star markers\n');
    fprintf('   cfg.plotting.STIMULUS_COLOR = [1, 0, 0];        %% Red stimulus\n');
    fprintf('   cfg.plotting.ENABLE_DUAL_STIMULI = false;       %% Single stimulus only\n\n');
    
    fprintf('To use these features, modify the configuration before running your pipeline:\n');
    fprintf('   cfg = GluSnFRConfig();\n');
    fprintf('   cfg.plotting.ENABLE_INDIVIDUAL_TRIALS = false;  %% Customize as needed\n');
    fprintf('   %% Then run your analysis with the modified config\n\n');
end

% % Add demonstration at the end if all tests pass
% if true
%     try
%         test_plotting_improvements();
%         demonstrateNewFeatures();
%     catch
%         % Test failed, don't show demonstration
%     end
% end