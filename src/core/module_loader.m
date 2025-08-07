function modules = module_loader()
    % MODULE_LOADER - Central module loading system with ROI cache support
    
    fprintf('Loading GluSnFR Analysis Pipeline modules...\n');
    
    try
        % Step 1: Load configuration FIRST (no dependencies)
        fprintf('  Loading configuration...\n');
        modules.config = GluSnFRConfig();
        
        % Step 2: Load utility modules (pass config to avoid circular dependencies)
        fprintf('  Loading utilities...\n');
        modules.utils = string_utils(modules.config);
        modules.memory = memory_manager();
        modules.cache = roi_cache();  % NEW: Add ROI cache module
        
        % Step 3: Load core processing modules
        fprintf('  Loading processing modules...\n');
        modules.calc = df_calculator();
        modules.filter = roi_filter(); 
        modules.gpu = gpu_processor();
        
        % Step 4: Load I/O modules
        fprintf('  Loading I/O modules...\n');
        modules.io.reader = excel_reader();
        modules.io.writer = excel_writer();
        modules.organize = data_organizer();
        modules.plot = plot_controller();
        
        % Step 5: Load analysis and controller
        fprintf('  Loading analysis modules...\n');
        modules.analysis = experiment_analyzer();
        modules.controller = pipeline_controller();
        
        % Step 6: Validate all modules loaded correctly
        validateAllModules(modules);
        
        version_info = PipelineVersion();
        fprintf('✓ All modules loaded successfully (v%s)\n', version_info.version);
        
    catch ME
        error('Module loading failed: %s\nStack: %s', ME.message, ME.stack(1).name);
    end
end

function validateAllModules(modules)
    % Updated validation to include ROI cache module
    
    requiredModules = {'config', 'calc', 'filter', 'memory', 'utils', ...
                      'io', 'organize', 'plot', 'analysis', 'controller', 'gpu', 'cache'};  % Added 'cache'
    
    % Check all modules exist
    for i = 1:length(requiredModules)
        moduleName = requiredModules{i};
        if ~isfield(modules, moduleName) || isempty(modules.(moduleName))
            error('Required module missing: %s', moduleName);
        end
    end
    
    % Test critical functions with updated signatures
    testResults = runModuleTestsUpdated(modules);
    
    if all(testResults)
        fprintf('✓ Module validation passed\n');
    else
        failedTests = find(~testResults);
        error('Module validation failed: %d/%d tests failed (tests %s)', ...
              sum(~testResults), length(testResults), mat2str(failedTests));
    end
end

function testResults = runModuleTestsUpdated(modules)
    % UPDATED: Run tests with correct function signatures after refactoring
    
    testResults = false(9, 1);  
    
    try
        % Test 1: Configuration
        assert(isfield(modules.config, 'version'), 'Config missing version');
        % UPDATED: Test new threshold parameters
        assert(isfield(modules.config.thresholds, 'LOW_NOISE_SIGMA'), 'Missing LOW_NOISE_SIGMA');
        assert(isfield(modules.config.thresholds, 'HIGH_NOISE_SIGMA'), 'Missing HIGH_NOISE_SIGMA');
        assert(isfield(modules.config.thresholds, 'SD_NOISE_CUTOFF'), 'Missing SD_NOISE_CUTOFF');
        testResults(1) = true;
        
        % Test 2: String utilities 
        testFilename = 'CP_Ms_DIV13_Doc2b-WT1_Cs1-c1_1AP-1_bg_mean.xlsx';
        groupKey = modules.utils.extractGroupKey(testFilename);  % Config already bound in closure
        assert(~isempty(groupKey), 'Group key extraction failed');
        testResults(2) = true;
        
        % Test 3: Memory manager 
        memUsage = modules.memory.estimateMemoryUsage(100, 600, 5, 'single');
        assert(memUsage > 0, 'Memory estimation failed');
        testResults(3) = true;
        
        % Test 4: dF/F calculator 
        hasGPU = false;  % For testing
        gpuInfo = struct('memory', 4, 'name', 'Test');
        useGPU = modules.calc.shouldUseGPU(50000, hasGPU, gpuInfo);  % Updated signature
        testResults(4) = true;  % Function exists and runs
        
        % Test 5: ROI filter 
        assert(isfield(modules.filter, 'filterROIs'), 'Filter missing main function');
        assert(isfield(modules.filter, 'applySchmittTrigger'), 'Filter missing Schmitt trigger function');
        assert(isfield(modules.filter, 'calculateSchmittThresholds'), 'Filter missing threshold calculation');
        testResults(5) = true;
        
        % Test 6: I/O operations
        assert(isfield(modules.io, 'reader'), 'IO missing reader module');
        assert(isfield(modules.io, 'writer'), 'IO missing writer module');
        assert(isfield(modules.io.reader, 'readFile'), 'Reader missing readFile function');
        assert(isfield(modules.io.writer, 'writeResults'), 'Writer missing writeResults function');
        testResults(6) = true;

        % Test 7: Plot controller
        assert(isfield(modules.plot, 'generateGroupPlots'), 'Plot controller missing main function');
        assert(isfield(modules.plot, 'shouldUseParallel'), 'Plot controller missing parallel function');
        testResults(7) = true;
        
        % Test 8: GPU processor
        assert(isfield(modules.gpu, 'calculate'), 'GPU processor missing calculate function');
        assert(isfield(modules.gpu, 'shouldUseGPU'), 'GPU processor missing shouldUseGPU function');
        assert(isfield(modules.gpu, 'getCapabilities'), 'GPU processor missing getCapabilities function');
        testResults(8) = true;

        % Test 9: ROI cache module (NEW)
        assert(isfield(modules.cache, 'create'), 'Cache missing create function');
        assert(isfield(modules.cache, 'validate'), 'Cache missing validate function');
        assert(isfield(modules.cache, 'retrieve'), 'Cache missing retrieve function');
        testResults(9) = true;
        
    catch ME
        fprintf('Module test failed: %s\n', ME.message);
        % Find which test failed based on current test results
        failedTestNum = find(~testResults, 1);
        if isempty(failedTestNum)
            failedTestNum = length(testResults);
        end
        fprintf('Failed on test %d\n', failedTestNum);
    end
end