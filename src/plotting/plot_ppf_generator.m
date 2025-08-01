function plotPPF = plot_ppf_generator()
    % PLOT_PPF_GENERATOR - Specialized PPF plotting
    
    plotPPF.generateSequential = @generatePPFSequential;
    plotPPF.generateIndividualPlots = @generatePPFIndividualPlots;
    plotPPF.generateAveragedPlots = @generatePPFAveragedPlots;
end