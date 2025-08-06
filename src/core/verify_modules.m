function verify_modules()
    % VERIFY_MODULES - Quick verification that all modules load correctly
    %
    % UPDATED: Fixed for new function signatures after refactoring
    
    fprintf('=== GluSnFR Module Verification ===\n');
    
    % Add current directory and subdirectories to path
    currentDir = fileparts(mfilename('fullpath'));
    addpath(genpath(currentDir));
    
    try
        % Test 1: Load configuration
        fprintf('1. Testing configuration module...\n');
        cfg = GluSnFRConfig();
        assert(isfield(cfg, 'version'), 'Config missing version field');
        
        % UPDATED: Test new threshold parameters
        assert(isfield(cfg.thresholds, 'LOW_NOISE_SIGMA'), 'Missing LOW_NOISE_SIGMA');
        assert(isfield(cfg.thresholds, 'HIGH_NOISE_SIGMA'), 'Missing HIGH_NOISE_SIGMA');
        assert(isfield(cfg.thresholds, 'SD_NOISE_CUTOFF'), 'Missing SD_NOISE_CUTOFF');
        
        version_info = PipelineVersion();
        fprintf('   ✓ Configuration loaded (v%s) with new threshold parameters\n', version_info.version);
        
        % Test 2: Load all modules
        fprintf('2. Testing module loader...\n');
        modules = module_loader();
        fprintf('   ✓ All modules loaded successfully\n');
        
        % Test 3: Test string utilities
        fprintf('3. Testing string utilities...\n');
        testFilename = 'CP_Ms_DIV13_Doc2b-WT1_Cs1-c1_1AP-1_bg_mean.xlsx';
        groupKey = modules.utils.extractGroupKey(testFilename);  % Config already bound
        assert(~isempty(groupKey), 'Group key extraction failed');
        fprintf('   ✓ String utilities working: "%s" → "%s"\n', testFilename, groupKey);
        
        % Test 4: Test system capabilities
        fprintf('4. Testing system detection...\n');
        [hasParallel, hasGPU, gpuInfo] = modules.controller.detectSystemCapabilities();
        fprintf('   ✓ System detection complete (Parallel: %s, GPU: %s)\n', ...
                string(hasParallel), string(hasGPU));
        
        % Test 5: Test memory manager
        fprintf('5. Testing memory management...\n');
        memUsage = modules.memory.estimateMemoryUsage(100, 600, 5, 'single');
        fprintf('   ✓ Memory estimation working: %.1f MB for test dataset\n', memUsage);
        
        % Test 6: UPDATED dF/F calculation test with new signature
        fprintf('6. Testing dF/F calculation...\n');
        testData = 100 + 10*randn(600, 10, 'single'); % Simple test data
        [dF, standardDeviations, gpuUsed] = modules.calc.calculate(testData, hasGPU, gpuInfo);  % UPDATED: New return values
        assert(size(dF, 1) == 600, 'dF/F calculation size mismatch');
        assert(length(standardDeviations) == 10, 'Standard deviations size mismatch');  % NEW: Test standard deviations
        fprintf('   ✓ dF/F calculation working (GPU: %s), returns dF/F + standard deviations\n', string(gpuUsed));
        
        % Test 7: UPDATED Schmitt trigger filtering with new signature
        fprintf('7. Testing Schmitt trigger ROI filtering...\n');
        testSchmittFilteringUpdated(modules, dF, standardDeviations);  % UPDATED: Pass standard deviations
        
        % Test 8: NEW GPU processor test
        fprintf('8. Testing GPU processor...\n');
        [dF_gpu, sd_gpu, gpuUsed_gpu] = modules.gpu.calculate(testData, hasGPU, gpuInfo, cfg);
        assert(size(dF_gpu, 1) == 600, 'GPU dF/F calculation size mismatch');
        assert(length(sd_gpu) == 10, 'GPU standard deviations size mismatch');
        fprintf('   ✓ GPU processor working (GPU: %s)\n', string(gpuUsed_gpu));
        
        % Success message
        fprintf('\n=== ALL MODULES VERIFIED SUCCESSFULLY ===\n');
        fprintf('The refactored pipeline with GPU optimization is ready to use!\n\n');
        fprintf('Key changes verified:\n');
        fprintf('  • Simplified threshold configuration (direct sigma values)\n');
        fprintf('  • GPU processor module operational\n');
        fprintf('  • dF/F calculator returns standard deviations\n');
        fprintf('  • ROI filter uses standard deviations instead of old thresholds\n\n');
        
        fprintf('To run the full pipeline:\n');
        fprintf('  >> main_glusnfr_pipeline\n\n');
        fprintf('To run comprehensive tests:\n');
        fprintf('  >> test_processing_comprehensive\n\n');
        fprintf('To validate data integrity:\n');
        fprintf('  >> validate_pipeline_integrity\n\n');
        
    catch ME
        fprintf('\n=== MODULE VERIFICATION FAILED ===\n');
        fprintf('Error: %s\n', ME.message);
        fprintf('Stack trace:\n');
        for i = 1:length(ME.stack)
            fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
        end
        fprintf('\nPlease check the module organization and try again.\n');
        rethrow(ME);
    end
end

function testSchmittFilteringUpdated(modules, testData, testStandardDeviations)
    % UPDATED: Test the Schmitt trigger filtering functionality with new signature
    
    try
        % Create test headers
        testHeaders = cell(1, size(testData, 2));
        for i = 1:length(testHeaders)
            testHeaders{i} = sprintf('ROI_%d', i);
        end
        
        % UPDATED: Test 1AP filtering with standard deviations instead of thresholds
        [filteredData1AP, filteredHeaders1AP, filteredThresh1AP, stats1AP] = ...
            modules.filter.filterROIs(testData, testHeaders, testStandardDeviations, '1AP');  % UPDATED: Use standard deviations
        
        assert(~isempty(stats1AP), 'Schmitt filtering stats not generated for 1AP');
        assert(strcmp(stats1AP.method, 'Schmitt Trigger'), 'Wrong filtering method reported');
        assert(isfield(stats1AP, 'schmitt_info'), 'Missing Schmitt info in stats');
        
        fprintf('   ✓ 1AP Schmitt filtering: %d/%d ROIs passed\n', ...
                stats1AP.passedROIs, stats1AP.totalROIs);
        
        % UPDATED: Test PPF filtering with 50ms interval using standard deviations
        [filteredDataPPF, filteredHeadersPPF, filteredThreshPPF, statsPPF] = ...
            modules.filter.filterROIs(testData, testHeaders, testStandardDeviations, 'PPF', 50);  % UPDATED: Use standard deviations
        
        assert(~isempty(statsPPF), 'Schmitt filtering stats not generated for PPF');
        assert(strcmp(statsPPF.method, 'Schmitt Trigger'), 'Wrong filtering method reported for PPF');
        assert(isfield(statsPPF, 'schmitt_info'), 'Missing Schmitt info in PPF stats');
        
        fprintf('   ✓ PPF Schmitt filtering: %d/%d ROIs passed\n', ...
                statsPPF.passedROIs, statsPPF.totalROIs);
        
        % UPDATED: Test Schmitt threshold calculation with new config
        cfg = modules.config;
        [noiseClass, upperThresh, lowerThresh] = ...
            modules.filter.calculateSchmittThresholds(testStandardDeviations, cfg);  % UPDATED: Use standard deviations
        
        assert(length(noiseClass) == length(testStandardDeviations), 'Noise classification size mismatch');
        assert(length(upperThresh) == length(testStandardDeviations), 'Upper thresholds size mismatch');
        assert(length(lowerThresh) == length(testStandardDeviations), 'Lower thresholds size mismatch');
        assert(all(upperThresh > lowerThresh), 'Upper thresholds should be greater than lower thresholds');
        
        % UPDATED: Check that thresholds are calculated correctly with new config
        expectedLowNoiseUpper = cfg.thresholds.LOW_NOISE_SIGMA * testStandardDeviations;
        expectedHighNoiseUpper = cfg.thresholds.HIGH_NOISE_SIGMA * testStandardDeviations;
        expectedLower = cfg.thresholds.LOWER_SIGMA * testStandardDeviations;
        
        % Verify at least some thresholds match expected calculations
        lowNoiseROIs = strcmp(noiseClass, 'low');
        highNoiseROIs = strcmp(noiseClass, 'high');
        
        if any(lowNoiseROIs)
            assert(all(abs(upperThresh(lowNoiseROIs) - expectedLowNoiseUpper(lowNoiseROIs)) < 1e-10), ...
                   'Low noise upper thresholds incorrectly calculated');
        end
        
        if any(highNoiseROIs)
            assert(all(abs(upperThresh(highNoiseROIs) - expectedHighNoiseUpper(highNoiseROIs)) < 1e-10), ...
                   'High noise upper thresholds incorrectly calculated');
        end
        
        assert(all(abs(lowerThresh - expectedLower) < 1e-10), 'Lower thresholds incorrectly calculated');
        
        fprintf('   ✓ Schmitt thresholds: %d low noise, %d high noise ROIs (calculations verified)\n', ...
                sum(strcmp(noiseClass, 'low')), sum(strcmp(noiseClass, 'high')));
        
    catch ME
        error('Schmitt trigger filtering test failed: %s', ME.message);
    end
end