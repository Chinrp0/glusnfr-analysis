function startup()
    % Automatically add project folders to MATLAB path
    
    % Get current user's project directory
    projectDir = fullfile(userpath, 'glusnfr-analysis');
    
    if exist(projectDir, 'dir')
        % Add all subdirectories to path
        addpath(genpath(projectDir));
        fprintf('Added GluSnFR analysis project to MATLAB path\n');
    end
end