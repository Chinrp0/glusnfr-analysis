function modules = module_loader()
    % MODULE_LOADER - Optimized central module loading system
    % 
    % OPTIMIZED: Reduced redundancy and improved error handling
    
    fprintf('Loading GluSnFR Analysis Pipeline modules...\n');
    
    try
        % Load configuration first (required by other modules)
        modules.config = GluSnFRConfig();
        
        % Load core processing modules (GPU/CPU optimized)
        modules.calc = df_calculator();
        modules.filter = roi_filter(); 
        modules.memory = memory_manager();
        
        % Load I/O and organization (consolidated)
        modules.io = io_manager();  % Now handles ALL file operations
        modules.organize = data_organizer();
        modules.plot = plot_generator();  % Fixed plotting module
        
        % Load utility modules
        modules.utils = string_utils();
        
        % Load analysis and controller
        modules.analysis = experiment_analyzer();
        modules.controller = pipeline_controller();
        
        % OPTIMIZED: Single validation pass
        validateAllModules(modules);
        
        fprintf('✓ All modules loaded successfully (v%s)\n', modules.config.version);
        
    catch ME
        error('Module loading failed: %s\nStack: %s', ME.message, ME.stack(1).name);
    end
end

function validateAllModules(modules)
    % OPTIMIZED: Comprehensive module validation in one pass
    
    % Required module fields
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
    % Run quick functionality tests for each module
    
    testResults = false(6, 1);
    
    try
        % Test 1: Configuration
        assert(isfield(modules.config, 'version'), 'Config missing version');
        testResults(1) = true;
        
        % Test 2: String utilities
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
        
        % Test 6: I/O operations
        assert(isfield(modules.io, 'writeExperimentResults'), 'IO missing consolidated function');
        testResults(6) = true;
        
    catch ME
        fprintf('Module test failed: %s', ME.message);
    end
end