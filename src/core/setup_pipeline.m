function setup_pipeline()
    % SETUP_PIPELINE - Setup GluSnFR analysis pipeline
    %
    % This function sets up the MATLAB path and verifies that the 
    % modular GluSnFR analysis pipeline is ready to use.
    
    fprintf('\n');
    fprintf('===============================================\n');
    fprintf('  GluSnFR Analysis Pipeline Setup v50\n');
    fprintf('===============================================\n');
    
    % Get the current directory (where this script is located)
    pipelineDir = fileparts(mfilename('fullpath'));
    
    % Add all subdirectories to MATLAB path
    fprintf('Setting up MATLAB path...\n');
    addpath(genpath(pipelineDir));
    
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
        verify_modules();
        
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
        fprintf('  • Verify setup: verify_modules\n');
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
        fprintf('\n');
    end
end