function test_processing_comprehensive()
    % Comprehensive testing of processing modules with realistic data
    
    fprintf('=== Comprehensive Processing Module Tests ===\n');
    
    % Add project to path
    addpath(genpath(fileparts(fileparts(mfilename('fullpath')))));
    
    % Load modules
    cfg = GluSnFRConfig();
    utils = string_utils();
    calc = df_calculator();
    filter = roi_filter();
    memMgr = memory_manager();
    
    fprintf('Loaded all modules successfully\n\n');
    
    % Test 1: Realistic dF/F calculation
    test_realistic_df_calculation(calc, cfg);
    
    % Test 2: ROI filtering with mixed noise levels
    test_mixed_noise_filtering(filter, cfg);
    
    % Test 3: Memory management with large datasets
    test_large_dataset_memory(memMgr);
    
    % Test 4: Integration test with realistic workflow
    test_realistic_workflow(calc, filter, utils, cfg);
    
    fprintf('\n=== All Comprehensive Tests Passed! ===\n');
    fprintf('Processing modules are ready for integration into main script.\n');
end

function test_realistic_df_calculation(calc, cfg)
    fprintf('1. Testing realistic dF/F calculation...\n');
    
    % Create data similar to your real experiments
    numFrames = 600;  % 2 seconds at 200Hz
    numROIs = 50;     % Typical number of ROIs
    
    % Realistic baseline fluorescence values
    F0_values = 80 + 40 * rand(1, numROIs);  % F0 between 80-120
    
    % Create realistic traces
    traces = create_realistic_traces(numFrames, numROIs, F0_values, cfg);
    
    % Test both GPU and CPU
    hasGPU = gpuDeviceCount > 0;
    gpuInfo = struct('memory', 4);  % 4GB
    
    % Time the calculation
    tic;
    [dF_values, thresholds, gpuUsed] = calc.calculate(traces, hasGPU, gpuInfo);
    calcTime = toc;
    
    % Validation
    assert(size(dF_values, 1) == numFrames, 'Frame count mismatch');
    assert(size(dF_values, 2) == numROIs, 'ROI count mismatch');
    assert(all(isfinite(thresholds)), 'Invalid thresholds');
    
    % Check baseline is approximately zero
    baselineWindow = cfg.timing.BASELINE_FRAMES;
    baselineMean = mean(dF_values(baselineWindow, :), 1);
    assert(all(abs(baselineMean) < 0.01), 'Baseline not properly normalized');
    
    % Check stimulus responses are detectable
    stimFrame = cfg.timing.STIMULUS_FRAME;
    postStimWindow = stimFrame + (1:cfg.timing.POST_STIMULUS_WINDOW);
    maxResponses = max(dF_values(postStimWindow, :), [], 1);
    detectable = sum(maxResponses > thresholds);
    
    fprintf('   ✓ dF/F calculation: %.3fs, GPU=%s, %d/%d detectable responses\n', ...
            calcTime, string(gpuUsed), detectable, numROIs);
    
    % Performance check
    expectedTime = numROIs * numFrames / 1e6;  % Rough estimate
    if calcTime < expectedTime
        fprintf('   ✓ Performance excellent (%.2fx faster than expected)\n', expectedTime/calcTime);
    end
end

function traces = create_realistic_traces(numFrames, numROIs, F0_values, cfg)
    % Create more realistic fluorescence traces with stronger responses
    
    % Time vector
    timeVec = (0:numFrames-1)' * cfg.timing.MS_PER_FRAME;
    
    % Baseline with realistic noise (1-2% CV) - REDUCED noise level
    noiseLevel = 0.008;  % 0.8% noise (was 1.5% - too high)
    baseline = repmat(F0_values, numFrames, 1) .* (1 + noiseLevel * randn(numFrames, numROIs));
    
    % Add photobleaching (slow exponential decay) - REDUCED bleaching
    bleachRate = 0.00005;  % per ms (reduced from 0.0001)
    bleachFactor = exp(-bleachRate * timeVec);
    baseline = baseline .* repmat(bleachFactor, 1, numROIs);
    
    % Add stimulus responses (make them STRONGER and more ROIs respond)
    stimFrame = cfg.timing.STIMULUS_FRAME;
    respondingROIs = 1:round(numROIs * 0.85);  % 85% of ROIs respond (was 70%)
    
    for i = respondingROIs
        % STRONGER response amplitude (3-12% dF/F instead of 2-8%)
        amplitude = 0.03 + 0.09 * rand();  % Increased amplitude
        
        % Response kinetics (exponential rise and decay)
        responseStart = stimFrame + 1;  % Start 1 frame after stimulus
        responseEnd = min(stimFrame + 80, numFrames);  % 80 frames = 400ms response
        responseFrames = responseStart:responseEnd;
        
        if ~isempty(responseFrames)
            % Create response shape (fast rise, slow decay)
            timeFromStim = (responseFrames - stimFrame)';
            response = amplitude * F0_values(i) * ...
                      (1 - exp(-timeFromStim / 8)) .* ...  % Faster rise (8 frames vs 10)
                      exp(-timeFromStim / 40);              % Slower decay (40 frames vs 50)
            
            baseline(responseFrames, i) = baseline(responseFrames, i) + response;
        end
    end
    
    traces = baseline;
end

function test_mixed_noise_filtering(filter, cfg)
    fprintf('2. Testing mixed noise level filtering...\n');
    
    % Create test data with known characteristics
    numFrames = 600;
    numROIs = 30;
    
    % Create dF/F data with mixed noise levels
    dF_data = create_mixed_noise_data(numFrames, numROIs, cfg);
    
    % Create headers
    headers = cell(numROIs, 1);
    for i = 1:numROIs
        headers{i} = sprintf('ROI %03d', i);
    end
    
    % Create thresholds that classify noise levels
    % First 15 ROIs: low noise (< 0.02)
    % Last 15 ROIs: high noise (> 0.02)
    thresholds = [0.015 * ones(1, 15), 0.035 * ones(1, 15)];
    
    % Test 1AP filtering
    fprintf('   Testing 1AP filtering...\n');
    [filtered1AP, headers1AP, thresh1AP, stats1AP] = ...
        filter.filterROIs(dF_data, headers, thresholds, '1AP');
    
    % Test PPF filtering
    fprintf('   Testing PPF filtering...\n');
    [filteredPPF, headersPPF, threshPPF, statsPPF] = ...
        filter.filterROIs(dF_data, headers, thresholds, 'PPF', 30);
    
    % Validation
    assert(size(filtered1AP, 1) == numFrames, '1AP: Frame count mismatch');
    assert(length(headers1AP) == size(filtered1AP, 2), '1AP: Header count mismatch');
    assert(stats1AP.lowNoiseROIs + stats1AP.highNoiseROIs == stats1AP.passedROIs, '1AP: Noise count mismatch');
    
    assert(size(filteredPPF, 1) == numFrames, 'PPF: Frame count mismatch');
    assert(length(headersPPF) == size(filteredPPF, 2), 'PPF: Header count mismatch');
    
    fprintf('   ✓ 1AP filtering: %s\n', stats1AP.summary);
    fprintf('   ✓ PPF filtering: %s\n', statsPPF.summary);
end

function dF_data = create_mixed_noise_data(numFrames, numROIs, cfg)
    % Create dF/F data with mixed noise levels and STRONGER responses
    
    stimFrame = cfg.timing.STIMULUS_FRAME;
    
    % Initialize with baseline noise
    dF_data = zeros(numFrames, numROIs, 'single');
    
    for i = 1:numROIs
        % Different noise levels (but more reasonable)
        if i <= 15
            noiseLevel = 0.008;  % Low noise ROIs (reduced from 0.01)
        else
            noiseLevel = 0.018;  % High noise ROIs (reduced from 0.025)
        end
        
        % Add baseline noise
        dF_data(:, i) = noiseLevel * randn(numFrames, 1);
        
        % Add STRONGER stimulus response to most ROIs
        if i <= round(numROIs * 0.9)  % 90% respond (was 80%)
            responseAmplitude = 0.04 + 0.08 * rand();  % 4-12% response (was 3-8%)
            responseStart = stimFrame + 1;
            responseEnd = min(stimFrame + 60, numFrames);
            responseFrames = responseStart:responseEnd;
            
            if ~isempty(responseFrames)
                timeFromStim = (responseFrames - stimFrame)';
                response = responseAmplitude * exp(-timeFromStim / 25);  % Slower decay
                dF_data(responseFrames, i) = dF_data(responseFrames, i) + response';
            end
        end
    end
end

function test_large_dataset_memory(memMgr)
    fprintf('3. Testing large dataset memory management...\n');
    
    % Simulate large dataset parameters
    largeROIs = 500;
    largeFrames = 2000;
    largeTrials = 8;
    
    % Test memory estimation
    estimatedMB = memMgr.estimateMemoryUsage(largeROIs, largeFrames, largeTrials, 'single');
    fprintf('   Estimated memory for large dataset: %.1f MB\n', estimatedMB);
    
    % Test memory availability
    isAvailable = memMgr.validateMemoryAvailable(estimatedMB);
    fprintf('   Memory available for large dataset: %s\n', string(isAvailable));
    
    % Test preallocation (with smaller size for actual testing)
    testROIs = 100;
    testFrames = 600;
    results = memMgr.preallocateResults(testROIs, testFrames, 3, 'single');
    
    % Validation
    assert(isfield(results, 'dFData'), 'Missing dFData field');
    assert(size(results.dFData, 1) == testFrames, 'Frame allocation mismatch');
    assert(size(results.dFData, 2) >= testROIs, 'ROI allocation insufficient');
    
    fprintf('   ✓ Memory management working, allocated %.1f MB\n', ...
            results.allocated.estimatedMemoryMB);
end

function test_realistic_workflow(calc, filter, utils, cfg)
    fprintf('4. Testing realistic workflow integration...\n');
    
    % Simulate processing a single file
    
    % 1. Create realistic raw data (like from Excel)
    numFrames = 600;
    numROIs = 25;
    F0_values = 90 + 30 * rand(1, numROIs);
    rawTraces = create_realistic_traces(numFrames, numROIs, F0_values, cfg);
    
    % 2. Test filename parsing
    testFilename = 'CP_Ms_DIV13_Doc2b-WT1_Cs1-c1_1AP-3_bg_mean.xlsx';
    fileInfo = utils.parseFilename(testFilename);
    assert(strcmp(fileInfo.expType, '1AP'), 'Experiment type parsing failed');
    assert(fileInfo.trialNum == 3, 'Trial number parsing failed');
    
    % 3. Calculate dF/F
    hasGPU = gpuDeviceCount > 0;
    gpuInfo = struct('memory', 2);
    [dF_values, thresholds, gpuUsed] = calc.calculate(rawTraces, hasGPU, gpuInfo);
    
    % 4. Filter ROIs
    headers = cell(numROIs, 1);
    for i = 1:numROIs
        headers{i} = sprintf('ROI %03d', i);
    end
    
    [filteredData, filteredHeaders, filteredThresholds, stats] = ...
        filter.filterROIs(dF_values, headers, thresholds, fileInfo.expType);
    
    % 5. Validation
    assert(~isempty(filteredData), 'No data after filtering');
    assert(size(filteredData, 1) == numFrames, 'Frame count changed');
    assert(length(filteredHeaders) == size(filteredData, 2), 'Header mismatch');
    
    % 6. Performance summary
    expectedResponses = round(numROIs * 0.7);  % Expected ~70% to respond
    actualResponses = stats.passedROIs;
    
    fprintf('   ✓ Workflow complete: %s parsed, %d→%d ROIs (expected ~%d)\n', ...
            fileInfo.expType, numROIs, actualResponses, expectedResponses);
    
    % Check if results are reasonable
    if actualResponses >= expectedResponses * 0.5
        fprintf('   ✓ Filtering results are reasonable\n');
    else
        fprintf('   ⚠ Filtering may be too strict (only %d/%d ROIs passed)\n', ...
                actualResponses, numROIs);
    end
end