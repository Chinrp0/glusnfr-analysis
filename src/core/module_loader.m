function modules = module_loader()
    % MODULE_LOADER - Central module loading system
    % 
    % Loads all pipeline modules in the correct order to avoid circular dependencies
    
    fprintf('Loading GluSnFR Analysis Pipeline modules...\n');
    
    try
        % Step 1: Load configuration FIRST (no dependencies)
        fprintf('  Loading configuration...\n');
        modules.config = GluSnFRConfig();
        
        % Step 2: Load utility modules (pass config to avoid circular dependencies)
        fprintf('  Loading utilities...\n');
        modules.utils = string_utils(modules.config);  % Pass config to avoid circular dependency
        modules.memory = memory_manager();
        
        % Step 3: Load core processing modules
        fprintf('  Loading processing modules...\n');
        modules.calc = df_calculator();
        modules.filter = roi_filter(); 
        
        % Step 4: Load I/O modules (UPDATED for split reader/writer)
        fprintf('  Loading I/O modules...\n');
        modules.io.reader = excel_reader();
        modules.io.writer = excel_writer();
        modules.organize = data_organizer();
        modules.plot = plot_generator();
        
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
    % Validate that all required modules are loaded
    
    requiredModules = {'config', 'calc', 'filter', 'memory', 'utils', ...
                      'io', 'organize', 'plot', 'analysis', 'controller'};
    
    % Check all modules exist
    for i = 1:length(requiredModules)
        moduleName = requiredModules{i};
        if ~isfield(modules, moduleName) || isempty(modules.(moduleName))
            error('Required module missing: %s', moduleName);
        end
    end
    
    % Test critical functions
    testResults = runModuleTests(modules);
    
    if all(testResults)
        fprintf('✓ Module validation passed\n');
    else
        error('Module validation failed: %d/%d tests failed', sum(~testResults), length(testResults));
    end
end

function testResults = runModuleTests(modules)
    % Run quick functionality tests for each module (UPDATED for split IO)
    
    testResults = false(6, 1);
    
    try
        % Test 1: Configuration
        assert(isfield(modules.config, 'version'), 'Config missing version');
        testResults(1) = true;
        
        % Test 2: String utilities (with config)
        testKey = modules.utils.extractGroupKey('CP_Ms_DIV13_Doc2b-WT1_Cs1-c1_1AP-1_bg_mean.xlsx');
        assert(~isempty(testKey), 'String extraction failed');
        testResults(2) = true;
        
        % Test 3: Memory manager
        memUsage = modules.memory.estimateMemoryUsage(100, 600, 5, 'single');
        assert(memUsage > 0, 'Memory estimation failed');
        testResults(3) = true;
        
        % Test 4: dF/F calculator decision logic
        useGPU = modules.calc.shouldUseGPU(50000, false, struct('memory', 4), modules.config);
        testResults(4) = true;  % Function exists and runs
        
        % Test 5: ROI filter
        assert(isfield(modules.filter, 'filterROIs'), 'Filter missing main function');
        testResults(5) = true;
        
        % Test 6: I/O operations (UPDATED for split reader/writer)
        assert(isfield(modules.io, 'reader'), 'IO missing reader module');
        assert(isfield(modules.io, 'writer'), 'IO missing writer module');
        assert(isfield(modules.io.reader, 'readFile'), 'Reader missing readFile function');
        assert(isfield(modules.io.writer, 'writeResults'), 'Writer missing writeResults function');
        testResults(6) = true;
        
    catch ME
        fprintf('Module test failed: %s', ME.message);
    end
end