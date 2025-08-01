function utils = plot_utils()
    % PLOT_UTILS - Plotting utilities and helpers
    
    utils.calculateOptimalLayout = @calculateOptimalLayout;
    utils.extractGenotypeFromGroupKey = @extractGenotypeFromGroupKey;
    utils.createColorScheme = @createColorScheme;
    utils.setupFigureDefaults = @setupFigureDefaults;
    utils.savePlotWithFormat = @savePlotWithFormat;
end

function [nRows, nCols] = calculateOptimalLayout(nSubplots)
    % Calculate optimal subplot layout
    if nSubplots <= 2
        nRows = 2; nCols = 1;
    elseif nSubplots <= 4
        nRows = 2; nCols = 2;
    elseif nSubplots <= 6
        nRows = 2; nCols = 3;
    elseif nSubplots <= 9
        nRows = 3; nCols = 3;
    else
        nRows = 3; nCols = 4;
    end
end

function genotype = extractGenotypeFromGroupKey(groupKey)
    % Extract genotype from group key
    if contains(groupKey, 'R213W')
        genotype = 'R213W';
    elseif contains(groupKey, 'WT')
        genotype = 'WT';
    else
        genotype = 'Unknown';
    end
end

function colors = createColorScheme(numColors, scheme)
    % Create color schemes for plotting
    if nargin < 2, scheme = 'default'; end
    
    switch scheme
        case 'trials'
            colors = [
                0.0 0.0 0.0;      % Black
                0.8 0.2 0.2;      % Red  
                0.2 0.6 0.8;      % Blue
                0.2 0.8 0.2;      % Green
                0.8 0.5 0.2;      % Orange
                0.6 0.2 0.8;      % Purple
                0.8 0.8 0.2;      % Yellow
                0.4 0.4 0.4;      % Gray
                0.0 0.8 0.8;      % Cyan
                0.8 0.0 0.8;      % Magenta
            ];
        case 'genotype'
            colors = [0, 0, 0; 1, 0, 1];  % WT=black, R213W=magenta
        otherwise
            colors = lines(numColors);
    end
    
    % Repeat if more colors needed
    if size(colors, 1) < numColors
        colors = repmat(colors, ceil(numColors/size(colors,1)), 1);
    end
    colors = colors(1:numColors, :);
end

function setupFigureDefaults()
    % Set optimal figure defaults for publication
    set(groot, 'DefaultFigureVisible', 'off');
    set(groot, 'DefaultFigureRenderer', 'vector');
    set(groot, 'DefaultFigureColor', 'white');
    set(groot, 'DefaultAxesFontSize', 10);
    set(groot, 'DefaultLineLineWidth', 1.0);
end

function success = savePlotWithFormat(fig, filepath, format, dpi)
    % Save plot with specified format and DPI
    if nargin < 3, format = 'png'; end
    if nargin < 4, dpi = 300; end
    
    try
        switch lower(format)
            case 'png'
                print(fig, filepath, '-dpng', sprintf('-r%d', dpi), '-vector');
            case 'pdf'
                print(fig, filepath, '-dpdf', '-vector');
            case 'eps'
                print(fig, filepath, '-depsc', '-vector');
            otherwise
                error('Unsupported format: %s', format);
        end
        success = true;
    catch
        success = false;
    end
end