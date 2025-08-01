% Run this to benchmark current vs optimized performance
function benchmark_pipeline_performance()
    % Test with standardized datasets
    datasets = {'small', 'medium', 'large'};
    
    for i = 1:length(datasets)
        fprintf('Testing %s dataset...\n', datasets{i});
        
        % Current implementation
        tic; 
        result_current = run_current_pipeline(datasets{i}); 
        time_current = toc;
        
        % Optimized implementation  
        tic; 
        result_optimized = run_optimized_pipeline(datasets{i}); 
        time_optimized = toc;
        
        % Validate identical results
        assert(validate_identical_results(result_current, result_optimized));
        
        speedup = time_current / time_optimized;
        fprintf('%s: %.1fx speedup (%.1fs → %.1fs)\n', ...
                datasets{i}, speedup, time_current, time_optimized);
    end
end