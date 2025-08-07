function plot1AP = plot_1ap()
    % PLOT_1AP - Main 1AP plotting module that delegates to specialized modules
    % 
    % UPDATED ARCHITECTURE:
    % - Delegates trials plotting to plot_1AP_trials module
    % - Delegates average plotting to plot_1AP_average module
    % - Maintains same interface for compatibility
    
    plot1AP.execute = @executePlotTask;
end

function success = executePlotTask(task, config, varargin)
    % Main task dispatcher - delegates to specialized modules
    
    success = false;
    
    % Validate task and cache
    sharedUtils = plot_1AP_shared_utils();
    if ~sharedUtils.validateTaskAndCache(task, config)
        return;
    end
    
    % Get appropriate module and execute
    try
        switch task.type
            case 'trials'
                % Delegate to trials module
                trialsModule = plot_1AP_trials();
                success = trialsModule.execute(task, config, varargin{:});
                    
            case 'averages'
                % Delegate to average module
                averageModule = plot_1AP_average();
                success = averageModule.execute(task, config, varargin{:});
                    
            case 'coverslip'
                % Delegate to average module
                averageModule = plot_1AP_average();
                success = averageModule.execute(task, config, varargin{:});
                    
            otherwise
                if config.debug.ENABLE_PLOT_DEBUG
                    fprintf('    Unknown 1AP plot task type: %s\n', task.type);
                end
        end
        
    catch ME
        if config.debug.ENABLE_PLOT_DEBUG
            fprintf('    1AP plot task failed: %s\n', ME.message);
        end
        success = false;
    end
end

% Uses plot_1AP_shared_utils() for validation and formatting