function version_info = PipelineVersion()
    % PIPELINEVERSION - Central version management for GluSnFR pipeline
    % 
    % Returns version information for the entire pipeline
    
    version_info = struct();
    version_info.version = '55.1.0';  % Semantic versioning: MAJOR.MINOR.PATCH
    version_info.build_date = '2025-07-31';
    version_info.matlab_version_required = 'R2019a';
    version_info.version_name = 'Modular Release';
    
    % Legacy version number for compatibility
    version_info.legacy_version = '55-1';
end