function modules = module_loader()
    % MODULE_LOADER - Central module loading system
    % 
    % This function loads and returns all pipeline modules,
    % providing a single entry point for the entire system.
    
    fprintf('Loading GluSnFR Analysis Pipeline modules...\n');
    
    % Load configuration
    modules.config = GluSnFRConfig();
    
    % Load core processing modules
    modules.calc = df_calculator();
    modules.filter = roi_filter();
    modules.memory = memory_manager();
    
    % Load utility modules
    modules.utils = string_utils();
    modules.io = io_manager();
    modules.organize = data_organizer();
    modules.plot = plot_generator();
    
    % Load analysis modules
    modules.analysis = experiment_analyzer();
    
    % Load main controller
    modules.controller = pipeline_controller();
    
    % Validate all modules loaded
    validateModules(modules);
    
    fprintf('All modules loaded successfully (v%s)\n', modules.config.version);
end

function validateModules(modules)
    % Validate that all required modules are present and functional
    
    required_fields = {'config', 'calc', 'filter', 'memory', 'utils', ...
                      'io', 'organize', 'plot', 'analysis', 'controller'};
    
    for i = 1:length(required_fields)
        field = required_fields{i};
        if ~isfield(modules, field) || isempty(modules.(field))
            error('Module validation failed: %s module not loaded', field);
        end
    end
    
    % Test basic functionality
    try
        % Test config
        assert(isfield(modules.config, 'version'), 'Config missing version');
        
        % Test utils
        testKey = modules.utils.extractGroupKey('CP_Ms_DIV13_Doc2b-WT1_Cs1-c1_1AP-1_bg_mean.xlsx');
        assert(~isempty(testKey), 'String utils not working');
        
        fprintf('Module validation passed\n');
        
    catch ME
        error('Module validation failed: %s', ME.message);
    end
end