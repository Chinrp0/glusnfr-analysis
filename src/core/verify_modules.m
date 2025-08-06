function verify_modules()
    % VERIFY_MODULES - Quick verification that all modules load correctly
    %
    % This script performs a quick check to ensure all modules are properly
    % organized and can be loaded without errors.
    
    fprintf('=== GluSnFR Module Verification ===\n');
    
    % Add current directory and subdirectories to path
    currentDir = fileparts(mfilename('fullpath'));
    addpath(genpath(currentDir));
    
    try
        % Test 1: Load configuration
        fprintf('1. Testing configuration module...\n');
        cfg = GluSnFRConfig();
        assert(isfield(cfg, 'version'), 'Config missing version field');
        version_info = PipelineVersion();
        fprintf('   ✓ Configuration loaded (v%s)\n', version_info.version);
        
        % Test 2: Load all modules
        fprintf('2. Testing module loader...\n');
        modules = module_loader();
        fprintf('   ✓ All modules loaded successfully\n');
        
        % Test 3: Test string utilities
        fprintf('3. Testing string utilities...\n');
        testFilename = 'CP_Ms_DIV13_Doc2b-WT1_Cs1-c1_1AP-1_bg_mean.xlsx';
        groupKey = modules.utils.extractGroupKey(testFilename);
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
        
        % Test 6: Basic dF/F calculation test
        fprintf('6. Testing dF/F calculation...\n');
        testData = 100 + 10*randn(600, 10, 'single'); % Simple test data
        [dF, thresh, gpuUsed] = modules.calc.calculate(testData, hasGPU, gpuInfo);
        assert(size(dF, 1) == 600, 'dF/F calculation size mismatch');
        fprintf('   ✓ dF/F calculation working (GPU: %s)\n', string(gpuUsed));
        
        % Test 7: Test Schmitt trigger filtering
        fprintf('7. Testing Schmitt trigger ROI filtering...\n');
        testSchmittFiltering(modules, dF, thresh);
        
        % Success message
        fprintf('\n=== ALL MODULES VERIFIED SUCCESSFULLY ===\n');
        fprintf('The simplified Schmitt trigger pipeline is ready to use!\n\n');
        fprintf('To run the full pipeline:\n');
        fprintf('  >> main_glusnfr_pipeline\n\n');
        fprintf('To run comprehensive tests:\n');
        fprintf('  >> test_processing_comprehensive\n\n');
        
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

function testSchmittFiltering(modules, testData, testThresholds)
    % Test the Schmitt trigger filtering functionality
    
    try
        % Create test headers
        testHeaders = cell(1, size(testData, 2));
        for i = 1:length(testHeaders)
            testHeaders{i} = sprintf('ROI_%d', i);
        end
        
        % Test 1AP filtering
        [filteredData1AP, filteredHeaders1AP, filteredThresh1AP, stats1AP] = ...
            modules.filter.filterROIs(testData, testHeaders, testThresholds, '1AP');
        
        assert(~isempty(stats1AP), 'Schmitt filtering stats not generated for 1AP');
        assert(strcmp(stats1AP.method, 'Schmitt Trigger'), 'Wrong filtering method reported');
        assert(isfield(stats1AP, 'schmitt_info'), 'Missing Schmitt info in stats');
        
        fprintf('   ✓ 1AP Schmitt filtering: %d/%d ROIs passed\n', ...
                stats1AP.passedROIs, stats1AP.totalROIs);
        
        % Test PPF filtering with 50ms interval
        [filteredDataPPF, filteredHeadersPPF, filteredThreshPPF, statsPPF] = ...
            modules.filter.filterROIs(testData, testHeaders, testThresholds, 'PPF', 50);
        
        assert(~isempty(statsPPF), 'Schmitt filtering stats not generated for PPF');
        assert(strcmp(statsPPF.method, 'Schmitt Trigger'), 'Wrong filtering method reported for PPF');
        assert(isfield(statsPPF, 'schmitt_info'), 'Missing Schmitt info in PPF stats');
        
        fprintf('   ✓ PPF Schmitt filtering: %d/%d ROIs passed\n', ...
                statsPPF.passedROIs, statsPPF.totalROIs);
        
        % Test Schmitt threshold calculation
        cfg = modules.config;
        [noiseClass, upperThresh, lowerThresh] = ...
            modules.filter.calculateSchmittThresholds(testThresholds, cfg);
        
        assert(length(noiseClass) == length(testThresholds), 'Noise classification size mismatch');
        assert(length(upperThresh) == length(testThresholds), 'Upper thresholds size mismatch');
        assert(length(lowerThresh) == length(testThresholds), 'Lower thresholds size mismatch');
        assert(all(upperThresh > lowerThresh), 'Upper thresholds should be greater than lower thresholds');
        
        fprintf('   ✓ Schmitt thresholds: %d low noise, %d high noise ROIs\n', ...
                sum(strcmp(noiseClass, 'low')), sum(strcmp(noiseClass, 'high')));
        
    catch ME
        error('Schmitt trigger filtering test failed: %s', ME.message);
    end
end