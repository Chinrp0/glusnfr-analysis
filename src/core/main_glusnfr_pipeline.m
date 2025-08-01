function main_glusnfr_pipeline()
    % MAIN_GLUSNFR_PIPELINE - Entry point for GluSnFR analysis pipeline
    % 
    % This is the main function that users call to run the complete
    % GluSnFR analysis pipeline with the new modular architecture.
    %
    % Usage:
    %   main_glusnfr_pipeline()
    
    % Display banner
    fprintf('\n');
    fprintf('========================================================\n');
    version_info = PipelineVersion();
    fprintf('    GluSnFR Analysis Pipeline v%s - %s    \n', version_info.version, version_info.version_name);
    fprintf('========================================================\n');
    fprintf('High-performance analysis for glutamate imaging data\n');
    fprintf('Processing Date: %s\n', char(datetime('now')));
    fprintf('\n');
    
    try
        % CRITICAL: Setup paths FIRST before loading any modules
        fprintf('Setting up MATLAB paths...\n');
        setupPipelinePaths();
        
        % Now load the pipeline controller and run
        fprintf('Loading pipeline modules...\n');
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

function setupPipelinePaths()
    % Setup all necessary paths for the modular pipeline
    
    % Get the directory where this script is located
    [scriptDir, ~, ~] = fileparts(mfilename('fullpath'));
    
    % Navigate to project root (assuming this script is in src/core/)
    projectRoot = fileparts(fileparts(scriptDir));
    
    % Add all necessary directories to path
    pathsToAdd = {
        fullfile(projectRoot, 'config'),
        fullfile(projectRoot, 'src', 'core'),
        fullfile(projectRoot, 'src', 'processing'), 
        fullfile(projectRoot, 'src', 'io'),
        fullfile(projectRoot, 'src', 'plotting'),
        fullfile(projectRoot, 'src', 'utils'),
        fullfile(projectRoot, 'src', 'analysis'),
        fullfile(projectRoot, 'tests')
    };
    
    % Add each path if it exists
    for i = 1:length(pathsToAdd)
        if exist(pathsToAdd{i}, 'dir')
            addpath(pathsToAdd{i});
            fprintf('  Added: %s\n', pathsToAdd{i});
        else
            warning('Directory not found: %s', pathsToAdd{i});
        end
    end
    
    fprintf('✓ All paths configured\n');
end