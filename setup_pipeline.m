function setup_pipeline()
    % SETUP_PIPELINE - Setup GluSnFR analysis pipeline
    %
    % This function sets up the MATLAB path and verifies that the 
    % modular GluSnFR analysis pipeline is ready to use.
    %
    % Run this FIRST before using the pipeline.
    
    fprintf('\n');
    fprintf('===============================================\n');
    fprintf('  GluSnFR Analysis Pipeline Setup v50\n');
    fprintf('===============================================\n');
    
    % Get the directory where this script is located (should be project root)
    scriptDir = fileparts(mfilename('fullpath'));
    
    % Add all subdirectories to MATLAB path
    fprintf('Setting up MATLAB path from: %s\n', scriptDir);
    
    % Critical directories that must exist
    criticalDirs = {
        fullfile(scriptDir, 'config'),
        fullfile(scriptDir, 'src', 'core'),
        fullfile(scriptDir, 'src', 'processing'),
        fullfile(scriptDir, 'src', 'io'),
        fullfile(scriptDir, 'src', 'plotting'),
        fullfile(scriptDir, 'src', 'utils'),
        fullfile(scriptDir, 'tests')
    };
    
    % Check and add critical directories
    allPathsGood = true;
    for i = 1:length(criticalDirs)
        if exist(criticalDirs{i}, 'dir')
            addpath(criticalDirs{i});
            fprintf('  ✓ Added: %s\n', criticalDirs{i});
        else
            fprintf('  ✗ Missing: %s\n', criticalDirs{i});
            allPathsGood = false;
        end
    end
    
    if ~allPathsGood
        error('Some critical directories are missing. Please check your installation.');
    end
    
    % Add all subdirectories to path (for any additional modules)
    addpath(genpath(scriptDir));
    
    % Save path permanently (optional)
    try
        savepath;
        fprintf('✓ Path saved permanently\n');
    catch
        fprintf('⚠ Could not save path permanently (run as administrator if needed)\n');
        fprintf('  You may need to run setup_pipeline() each MATLAB session\n');
    end
    
    % Verify installation
    fprintf('\nVerifying installation...\n');
    try
        % Test that we can load the config
        fprintf('  Testing configuration loading...\n');
        config = GluSnFRConfig();
        fprintf('  ✓ Configuration loaded (version %s)\n', config.version);
        
        % Test module loading
        fprintf('  Testing module loading...\n');
        modules = module_loader();
        fprintf('  ✓ All modules loaded successfully\n');
        
        % Basic functionality test
        fprintf('  Testing basic functionality...\n');
        testFilename = 'CP_Ms_DIV13_Doc2b-WT1_Cs1-c1_1AP-1_bg_mean.xlsx';
        groupKey = modules.utils.extractGroupKey(testFilename);
        assert(~isempty(groupKey), 'String extraction test failed');
        fprintf('  ✓ Basic functionality working\n');
        
        fprintf('\n===============================================\n');
        fprintf('            SETUP COMPLETE!                   \n');
        fprintf('===============================================\n');
        fprintf('\nQuick Start:\n');
        fprintf('  1. Run: main_glusnfr_pipeline\n');
        fprintf('  2. Select your "5_raw_mean" folder\n');
        fprintf('  3. Processing runs automatically\n');
        fprintf('\nFor help:\n');
        fprintf('  • Documentation: README.md\n');
        fprintf('  • Run tests: test_processing_comprehensive\n');
        fprintf('  • Integration test: test_modular_integration\n');
        fprintf('\n');
        
    catch ME
        fprintf('\n===============================================\n');
        fprintf('            SETUP FAILED!                     \n');
        fprintf('===============================================\n');
        fprintf('Error: %s\n', ME.message);
        fprintf('\nTroubleshooting:\n');
        fprintf('  1. Ensure all files are in the correct folders\n');
        fprintf('  2. Check that you have MATLAB R2019a or later\n');
        fprintf('  3. Verify folder structure matches README.md\n');
        fprintf('  4. Try running from the project root directory\n');
        fprintf('\nStack trace:\n');
        for i = 1:min(3, length(ME.stack))
            fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
        end
        fprintf('\n');
    end
end