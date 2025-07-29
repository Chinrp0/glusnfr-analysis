function main_glusnfr_pipeline()
    % MAIN_GLUSNFR_PIPELINE - Entry point for GluSnFR analysis pipeline
    % 
    % This is the main function that users call to run the complete
    % GluSnFR analysis pipeline with the new modular architecture.
    %
    % Usage:
    %   main_glusnfr_pipeline()
    %
    % The function will:
    % 1. Load all required modules
    % 2. Setup system capabilities (GPU, parallel processing)
    % 3. Guide user through folder selection
    % 4. Process all groups automatically
    % 5. Generate Excel outputs and plots
    % 6. Provide comprehensive summary
    
    % Display banner
    fprintf('\n');
    fprintf('========================================================\n');
    fprintf('    GluSnFR Analysis Pipeline v50 - Modular Edition    \n');
    fprintf('========================================================\n');
    fprintf('High-performance analysis for glutamate imaging data\n');
    fprintf('Processing Date: %s\n', char(datetime('now')));
    fprintf('\n');
    
    try
        % Load the pipeline controller and run
        controller = pipeline_controller();
        controller.runMainPipeline();
        
    catch ME
        fprintf('\n=== PIPELINE ERROR ===\n');
        fprintf('Error: %s\n', ME.message);
        fprintf('\nFor help, check the documentation or run:\n');
        fprintf('  help main_glusnfr_pipeline\n');
        fprintf('  test_processing_comprehensive\n');
        
        % Save error details
        errorFile = fullfile(pwd, 'pipeline_error.txt');
        fid = fopen(errorFile, 'w');
        if fid ~= -1
            fprintf(fid, 'GluSnFR Pipeline Error Report\n');
            fprintf(fid, 'Time: %s\n', char(datetime('now')));
            fprintf(fid, 'Error: %s\n', ME.message);
            fprintf(fid, '\nStack Trace:\n');
            for i = 1:length(ME.stack)
                fprintf(fid, '  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
            end
            fclose(fid);
            fprintf('Error details saved to: %s\n', errorFile);
        end
        
        rethrow(ME);
    end
end