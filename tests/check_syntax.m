function check_syntax()
    % CHECK_SYNTAX - Verify that all module files have valid MATLAB syntax
    %
    % This script will try to load each module file to catch any syntax errors
    % before running the full pipeline.
    
    fprintf('=== MATLAB Syntax Verification ===\n');
    
    % Add paths
    addpath(genpath(pwd));
    
    % List of critical files to check
    criticalFiles = {
        'config/GluSnFRConfig.m'
        'src/core/module_loader.m'
        'src/core/pipeline_controller.m'
        'src/io/io_manager.m'
        'src/processing/df_calculator.m'
        'src/processing/roi_filter.m'
        'src/processing/memory_manager.m'
        'src/utils/string_utils.m'
        'src/core/data_organizer.m'
        'src/core/experiment_analyzer.m'
        'src/plotting/plot_generator.m'
    };
    
    allPassed = true;
    
    for i = 1:length(criticalFiles)
        filename = criticalFiles{i};
        fprintf('Checking %s... ', filename);
        
        if ~exist(filename, 'file')
            fprintf('❌ FILE NOT FOUND\n');
            allPassed = false;
            continue;
        end
        
        try
            % Try to parse the file by getting function info
            [~, funcName, ~] = fileparts(filename);
            
            % For files in subdirectories, use just the filename
            if contains(funcName, '/')
                parts = split(funcName, '/');
                funcName = parts{end};
            end
            
            % Special handling for different file types
            if strcmp(funcName, 'GluSnFRConfig')
                % Test config loading
                cfg = GluSnFRConfig();
                assert(isstruct(cfg), 'Config should return struct');
                
            elseif endsWith(filename, '_manager.m') || endsWith(filename, '_calculator.m') || ...
                   endsWith(filename, '_filter.m') || endsWith(filename, '_utils.m') || ...
                   endsWith(filename, '_organizer.m') || endsWith(filename, '_analyzer.m') || ...
                   endsWith(filename, '_generator.m')
                % Test module loading
                eval(sprintf('%s();', funcName));
                
            elseif strcmp(funcName, 'module_loader')
                % Special test for module loader
                modules = module_loader();
                assert(isstruct(modules), 'Module loader should return struct');
                
            elseif strcmp(funcName, 'pipeline_controller')
                % Test pipeline controller
                controller = pipeline_controller();
                assert(isstruct(controller), 'Controller should return struct');
                
            else
                % For other files, just try to get function info
                try
                    help(funcName);
                catch
                    % If help fails, file might have syntax issues
                    warning('Could not get help for %s', funcName);
                end
            end
            
            fprintf('✅ OK\n');
            
        catch ME
            fprintf('❌ SYNTAX ERROR\n');
            fprintf('   Error: %s\n', ME.message);
            if ~isempty(ME.stack)
                fprintf('   Line: %d\n', ME.stack(1).line);
            end
            allPassed = false;
        end
    end
    
    fprintf('\n');
    if allPassed
        fprintf('🎉 ALL SYNTAX CHECKS PASSED!\n');
        fprintf('✅ All module files have valid MATLAB syntax\n');
        fprintf('\nNext steps:\n');
        fprintf('• Run: verify_pipeline() - for comprehensive testing\n');
        fprintf('• Run: main_glusnfr_pipeline() - to process your data\n');
    else
        fprintf('❌ SYNTAX ERRORS FOUND!\n');
        fprintf('🔧 Please fix the syntax errors shown above before proceeding.\n');
        fprintf('\nCommon issues:\n');
        fprintf('• Python-style "if condition else value" syntax\n');
        fprintf('• Missing "end" statements\n');
        fprintf('• Incorrect function declarations\n');
    end
    
    fprintf('\n');
end