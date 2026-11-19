%% SOUND ABSORPTION: DB, MIKI, KOMATSU AND JCA
% Run this script with absorption_data.csv in the same folder.
% MATLAB R2018b or newer. Base MATLAB only; no add-on toolboxes.
%
% INPUT: long-format CSV with Sample, Frequency_Hz, Alpha columns.
% For EACH sample enter: thickness [mm], airflow resistivity [Pa*s/m^2],
% and OPEN porosity [0 < phi <= 1]. Measured resistivity is fixed in ALL
% models. Measured thickness is fixed in ALL models. Porosity is used by JCA.
%
% DB/Miki/Komatsu: predictions using published coefficients, zero fitted
% parameters. JCA: fit alpha_infinity, Lambda and Lambda_prime by bounded,
% multistart nonlinear least squares. Sigma and phi are NEVER optimized.
%
% Assumptions: normal incidence, homogeneous rigid-frame porous layer,
% rigid impervious backing, zero backing air gap, exp(+1i*omega*t).
% See README.md for formulas, sources, bounds, diagnostics and limitations.

%% 1. Settings (edit these if needed)
cfg = struct;
cfg.dataFile = 'absorption_data.csv';
cfg.propertiesFile = 'sample_properties.csv';
cfg.selectedSamples = strings(0,1);  % e.g. ["A";"AP"]; empty = all
cfg.promptEveryRun = false;          % true = review every saved input
cfg.fitFrequencyRange_Hz = [0 Inf];  % inclusive; same points for all models
cfg.airTemperature_C = 20;
cfg.atmosphericPressure_Pa = 101325;
cfg.prandtlNumber = 0.71;
cfg.jcaLower = [1, 1, 5];           % [tortuosity, Lambda_um, LambdaPrime_um]
cfg.jcaUpper = [10, 300, 1500];
cfg.jcaStarts = 32;
cfg.randomSeed = 42;
cfg.maxIterations = 2500;
cfg.maxFunctionEvaluations = 12000;
cfg.boundWarningFraction = 0.01;     % fraction of LOG parameter interval
cfg.curvePoints = 500;
cfg.makePlots = true;
cfg.showPlots = true;

%% 2. Locate input data and validate settings
scriptFolder = fileparts(mfilename('fullpath'));
if isempty(scriptFolder), scriptFolder = pwd; end
dataPath = fullfile(scriptFolder, cfg.dataFile);
if ~isfile(dataPath)
    [fn, fp] = uigetfile('*.csv', 'Select absorption data CSV');
    if isequal(fn,0), error('No absorption data file selected.'); end
    dataPath = fullfile(fp, fn);
end
propertiesPath = fullfile(fileparts(dataPath), cfg.propertiesFile);
validateattributes(cfg.jcaLower, {'numeric'}, {'vector','numel',3,'positive','finite'});
validateattributes(cfg.jcaUpper, {'numeric'}, {'vector','numel',3,'positive','finite'});
assert(all(cfg.jcaUpper > cfg.jcaLower), 'Upper bounds must exceed lower bounds.');
assert(cfg.jcaLower(1) >= 1, 'Tortuosity lower bound must be >= 1.');
validateattributes(cfg.jcaStarts, {'numeric'}, {'scalar','integer','>=',2});
validateattributes(cfg.curvePoints, {'numeric'}, {'scalar','integer','>=',2});
assert(numel(cfg.fitFrequencyRange_Hz)==2 && ...
    cfg.fitFrequencyRange_Hz(1)>=0 && ...
    cfg.fitFrequencyRange_Hz(2)>cfg.fitFrequencyRange_Hz(1), ...
    'Specify an increasing, nonnegative frequency interval.');
validateattributes(cfg.airTemperature_C, {'numeric'}, {'scalar','finite','>',-273.15});
validateattributes(cfg.atmosphericPressure_Pa, {'numeric'}, {'scalar','positive','finite'});
validateattributes(cfg.prandtlNumber, {'numeric'}, {'scalar','positive','finite'});
T = readtable(dataPath);
required = {'Sample','Frequency_Hz','Alpha'};
assert(all(ismember(required,T.Properties.VariableNames)), ...
    'Input must contain Sample, Frequency_Hz and Alpha columns.');
assert(isnumeric(T.Frequency_Hz) && isnumeric(T.Alpha), ...
    'Frequency_Hz and Alpha must be numeric columns.');
T.Sample = strtrim(string(T.Sample));
valid = ~ismissing(T.Sample) & strlength(T.Sample)>0 & ...
    isfinite(T.Frequency_Hz) & T.Frequency_Hz>0 & isfinite(T.Alpha);
if any(~valid)
    warning('Absorption:InvalidRows', 'Removing %d missing/invalid rows.', sum(~valid));
end
T = T(valid,required);
assert(~isempty(T), 'No valid absorption data remain.');
assert(all(T.Alpha>=0 & T.Alpha<=1), ...
    ['Alpha must be a fraction in [0,1]. Values are not clipped. ' ...
     'Check percentages or investigate out-of-range measurements.']);
samples = unique(T.Sample,'stable');
if ~isempty(cfg.selectedSamples)
    requested = string(cfg.selectedSamples(:));
    assert(all(ismember(requested,samples)), 'A selected sample is absent from the data.');
    samples = samples(ismember(samples,requested));
end
fprintf('\nDetected %d samples: %s\n', numel(samples), strjoin(cellstr(samples), ', '));
fprintf('Fixed measured resistivity is used in ALL four models.\n');
fprintf('JCA alone fits three parameters; all models use the same frequency rows.\n');

%% 3. Read or prompt for measured sample properties
P = table(samples, nan(numel(samples),1), nan(numel(samples),1), ...
    nan(numel(samples),1), 'VariableNames', ...
    {'Sample','Thickness_mm','Resistivity_Pa_s_m2','Porosity'});
if isfile(propertiesPath)
    oldP = readtable(propertiesPath);
    assert(all(ismember(P.Properties.VariableNames, oldP.Properties.VariableNames)), ...
        'Properties CSV needs Sample, Thickness_mm, Resistivity_Pa_s_m2, Porosity.');
    oldP.Sample = strtrim(string(oldP.Sample));
    assert(numel(unique(oldP.Sample))==height(oldP), ...
        'Properties CSV contains duplicate sample identifiers.');
    fields = P.Properties.VariableNames(2:end);
    for j = 1:numel(fields)
        assert(isnumeric(oldP.(fields{j})), 'Properties columns must be numeric.');
    end
    [found,loc] = ismember(samples, oldP.Sample);
    for j = 1:numel(fields)
        P{found,fields(j)} = oldP{loc(found),fields(j)};
    end
else
    oldP = P([],:);
end
for s = 1:height(P)
    fprintf('\nSample %s\n', char(P.Sample(s)));
    P.Thickness_mm(s) = askValue('Thickness [mm]', P.Thickness_mm(s), ...
        @(x) x>0, cfg.promptEveryRun);
    P.Resistivity_Pa_s_m2(s) = askValue('Airflow resistivity [Pa*s/m^2]', ...
        P.Resistivity_Pa_s_m2(s), @(x) x>0, cfg.promptEveryRun);
    P.Porosity(s) = askValue('Open porosity [fraction, >0 and <=1]', ...
        P.Porosity(s), @(x) x>0 && x<=1, cfg.promptEveryRun);
end
% Preserve other samples when only a subset is processed.
remaining = oldP(~ismember(oldP.Sample,P.Sample),P.Properties.VariableNames);
writetable([remaining; P], propertiesPath);

%% 4. Air properties and reproducible optimization
air.P0 = cfg.atmosphericPressure_Pa;
air.gamma = 1.4;
air.Pr = cfg.prandtlNumber;
temperatureK = cfg.airTemperature_C + 273.15;
air.rho0 = air.P0/(287.05*temperatureK);
air.c0 = sqrt(air.gamma*air.P0/air.rho0);
air.eta = 1.716e-5*(temperatureK/273.15)^1.5 * ...
    (273.15+111)/(temperatureK+111);  % Sutherland approximation [Pa*s]
air.Z0 = air.rho0*air.c0;
previousRng = rng;
rng(cfg.randomSeed,'twister');
% Generate once: each sample receives the same reproducible starting set.
starts = 0.03 + 0.94*rand(cfg.jcaStarts,3);
initialPhysical = [1.3, 100, 200];
initialPhysical = max(cfg.jcaLower, min(cfg.jcaUpper, initialPhysical));
starts(1,:) = (log10(initialPhysical)-log10(cfg.jcaLower)) ./ ...
    (log10(cfg.jcaUpper)-log10(cfg.jcaLower));
starts(1,:) = max(0.001,min(0.999,starts(1,:)));
rng(previousRng);

%% 5. Output folder and sample-by-sample estimation
outRoot = fullfile(fileparts(dataPath),'absorption_results');
if ~isfolder(outRoot), mkdir(outRoot); end
runFolder = fullfile(outRoot,datestr(now,'yyyymmdd_HHMMSS'));
baseFolder = runFolder;
counter = 1;
while isfolder(runFolder)
    runFolder = sprintf('%s_%02d',baseFolder,counter);
    counter = counter+1;
end
mkdir(runFolder);
writetable(P,fullfile(runFolder,'sample_properties_used.csv'));
save(fullfile(runFolder,'run_settings.mat'),'cfg','air','dataPath','P','starts');
modelNames = ["Delany_Bazley";"Miki";"Komatsu";"JCA"];
allMetrics = table;
allParameters = table;
r2Matrix = nan(numel(samples),4);

for s = 1:numel(samples)
    sample = samples(s);
    rows = T.Sample==sample;
    allSampleData = sortrows(T(rows,:), 'Frequency_Hz');
    inBand = allSampleData.Frequency_Hz>=cfg.fitFrequencyRange_Hz(1) & ...
        allSampleData.Frequency_Hz<=cfg.fitFrequencyRange_Hz(2);
    S = allSampleData(inBand,:);
    assert(height(S)>3 && numel(unique(S.Frequency_Hz))>3, ...
        'Sample %s requires at least four distinct frequencies in the selected band.',char(sample));
    if numel(unique(S.Frequency_Hz))<height(S)
        warning('Absorption:DuplicateFrequency', ...
            'Sample %s: duplicate frequencies retained as equally weighted observations.',char(sample));
    end
    f = S.Frequency_Hz;
    y = S.Alpha;
    d = P.Thickness_mm(s)/1000;
    sigma = P.Resistivity_Pa_s_m2(s);
    phi = P.Porosity(s);
    assert(2-log10(max(f)/sigma)>0, ...
        ['Sample %s: the entered resistivity is outside the real-valued ' ...
         'Komatsu domain over this frequency band (need sigma > max(f)/100).'],char(sample));
    % Index prefix prevents folder collisions from sanitized sample names.
    safeName = regexprep(char(sample),'[^a-zA-Z0-9_-]','_');
    if isempty(safeName), safeName = 'Sample'; end
    sampleFolder = fullfile(runFolder,sprintf('%02d_%s',s,safeName));
    mkdir(sampleFolder);
    writetable(allSampleData,fullfile(sampleFolder,[safeName '_input.csv']));
    fprintf('\n[%d/%d] %s: %d points, %.1f-%.1f Hz\n',s,numel(samples),char(sample),numel(f),min(f),max(f));

    [best, multiStart] = fitJCA(f,y,d,sigma,phi,air,cfg,starts);
    multiStart.Sample = repmat(sample,height(multiStart),1);
    writetable(multiStart,fullfile(sampleFolder,[safeName '_JCA_multistart.csv']));
    predicted = nan(numel(f),4);
    curveF = logspace(log10(min(f)),log10(max(f)),cfg.curvePoints).';
    curveY = nan(numel(curveF),4);
    sampleMetrics = table;
    sampleParameters = table;

    for m = 1:4
        name = modelNames(m);
        predicted(:,m) = absorptionModel(name,f,d,sigma,phi,best.p,air);
        curveY(:,m) = absorptionModel(name,curveF,d,sigma,phi,best.p,air);
        residual = y-predicted(:,m);
        SSE = sum(residual.^2);
        SST = sum((y-mean(y)).^2);
        R2 = NaN;
        if SST>eps(max(1,sum(y.^2)))
            R2 = 1-SSE/SST;  % Can be negative; never square corrcoef.
        end
        RMSE = sqrt(mean(residual.^2));
        MAE = mean(abs(residual));
        nFree = 0;
        method = "Fixed_input_prediction";
        exitFlag = NaN;
        nearBound = false;
        jacCondition = NaN;
        tau = NaN; Lv = NaN; Lt = NaN; porosityUsed = NaN;
        notes = "";
        if m==4
            nFree = 3;
            method = "Nonlinear_least_squares";
            exitFlag = best.exitflag;
            nearBound = best.nearBound;
            jacCondition = best.jacCondition;
            tau = best.p(1); Lv = best.p(2); Lt = best.p(3);
            porosityUsed = phi;
            if exitFlag<=0, notes = notes+"Optimizer did not converge; "; end
            if nearBound, notes = notes+"JCA estimate near search bound; "; end
            if jacCondition>1e6
                notes = notes+"Ill-conditioned local sensitivity; ";
            end
        end
        % Range diagnostics are ADVISORY, not fitted-point exclusions.
        outsideRange = NaN;
        if m==1
            X = air.rho0*f/sigma;
            outsideRange = mean(X<0.01 | X>1);
        elseif m==2
            X = f/sigma;
            outsideRange = mean(X<0.01 | X>1);
        end
        if outsideRange>0
            notes = notes+"Some points outside conventional empirical range; ";
        end
        nonphysical = any(predicted(:,m)<-1e-8 | predicted(:,m)>1+1e-8) || ...
            any(curveY(:,m)<-1e-8 | curveY(:,m)>1+1e-8);
        if nonphysical, notes = notes+"Unclipped prediction outside [0,1]; "; end
        metric = table(sample,name,method,nFree,numel(f),min(f),max(f), ...
            R2,RMSE,MAE,SSE,exitFlag,nearBound,jacCondition,outsideRange,nonphysical,notes, ...
            'VariableNames',{'Sample','Model','Method','NFreeParameters','NPoints', ...
            'MinFrequency_Hz','MaxFrequency_Hz','R2','RMSE','MAE','SSE', ...
            'OptimizerExitFlag','NearJcaBound','JcaJacobianCondition', ...
            'OutsideConventionalRangeFraction','NonphysicalPrediction','Notes'});
        parameter = table(sample,name,P.Thickness_mm(s),sigma,porosityUsed,tau,Lv,Lt,nFree, ...
            'VariableNames',{'Sample','Model','Thickness_mm','Resistivity_Pa_s_m2', ...
            'PorosityUsed','Tortuosity','ViscousLength_um','ThermalLength_um','NFreeParameters'});
        if isempty(sampleMetrics)
            sampleMetrics = metric;
            sampleParameters = parameter;
        else
            sampleMetrics = [sampleMetrics; metric]; %#ok<AGROW>
            sampleParameters = [sampleParameters; parameter]; %#ok<AGROW>
        end
        r2Matrix(s,m) = R2;
        fprintf('  %-15s R2 = % .5f   RMSE = %.5f\n',char(name),R2,RMSE);
        if strlength(notes)>0
            fprintf('    Note: %s\n',char(notes));
        end
    end
    fittedValues = table(repmat(sample,numel(f),1),f,y,predicted(:,1), ...
        predicted(:,2),predicted(:,3),predicted(:,4), 'VariableNames', ...
        {'Sample','Frequency_Hz','Alpha_Experimental','Alpha_Delany_Bazley', ...
        'Alpha_Miki','Alpha_Komatsu','Alpha_JCA'});
    smoothCurves = array2table([curveF,curveY], 'VariableNames', ...
        {'Frequency_Hz','Alpha_Delany_Bazley','Alpha_Miki','Alpha_Komatsu','Alpha_JCA'});
    writetable(fittedValues,fullfile(sampleFolder,[safeName '_fitted_values.csv']));
    writetable(sampleMetrics,fullfile(sampleFolder,[safeName '_R2.csv']));
    writetable(sampleParameters,fullfile(sampleFolder,[safeName '_parameters.csv']));
    writetable(smoothCurves,fullfile(sampleFolder,[safeName '_smooth_curves.csv']));
    if isempty(allMetrics)
        allMetrics = sampleMetrics;
        allParameters = sampleParameters;
    else
        allMetrics = [allMetrics; sampleMetrics]; %#ok<AGROW>
        allParameters = [allParameters; sampleParameters]; %#ok<AGROW>
    end
    if cfg.makePlots
        try
            saveSamplePlot(sample,f,y,curveF,curveY,sampleMetrics,sampleFolder,safeName,cfg);
        catch plotError
            warning('Absorption:PlotFailed','CSV outputs saved; plot failed: %s',plotError.message);
        end
    end
    % Save combined results after each sample as a progress checkpoint.
    writetable(allMetrics,fullfile(runFolder,'ALL_samples_fit_metrics.csv'));
    writetable(allParameters,fullfile(runFolder,'ALL_samples_parameters.csv'));
end
R2summary = array2table(r2Matrix,'VariableNames',cellstr(modelNames));
R2summary = [table(samples,'VariableNames',{'Sample'}),R2summary];
writetable(R2summary,fullfile(runFolder,'ALL_samples_R2.csv'));
fprintf('\nDone. Results saved in:\n%s\n',runFolder);
disp(R2summary);

%% Local functions (keep these below the script)
function value = askValue(label, saved, validator, promptEveryRun)
    goodSaved = isnumeric(saved) && isscalar(saved) && isfinite(saved) && validator(saved);
    if goodSaved && ~promptEveryRun
        value = saved;
        fprintf('  %s = %.8g (from properties CSV)\n',label,value);
        return
    end
    while true
        if goodSaved
            txt = input(sprintf('  %s [Enter = %.8g]: ',label,saved),'s');
            if isempty(strtrim(txt)), value = saved; return; end
        else
            txt = input(sprintf('  %s: ',label),'s');
        end
        value = str2double(strrep(strtrim(txt),',','.'));
        if isscalar(value) && isfinite(value) && validator(value), return; end
        fprintf('  Invalid value. Enter one number in the stated units/range.\n');
    end
end

function alpha = absorptionModel(model,f,d,sigma,phi,p,air)
    f = f(:);
    w = 2*pi*f;
    k0 = w/air.c0;
    switch char(model)
        case 'Delany_Bazley'
            % Common density-scaled DB formulation; X = rho0*f/sigma.
            X = air.rho0*f/sigma;
            Zc = air.Z0*(1+0.0571*X.^(-0.754)-1i*0.0870*X.^(-0.732));
            kc = k0.*(1+0.0978*X.^(-0.700)-1i*0.1890*X.^(-0.595));
        case 'Miki'
            % Original Miki convention: X = 1000*f/sigma, NOT rho0*f/sigma.
            X = 1000*f/sigma;
            Zc = air.Z0*(1+5.50*X.^(-0.632)-1i*8.43*X.^(-0.632));
            kc = k0.*(1+7.81*X.^(-0.618)-1i*11.41*X.^(-0.618));
        case 'Komatsu'
            % Komatsu (2008), Eqs. 15-18. Common logarithm, SI resistivity.
            X = 2-log10(f/sigma);
            assert(all(X>0), ...
                'Komatsu requires 2-log10(f/sigma)>0 over the evaluation band.');
            Zc = air.Z0*(1+0.00027*X.^6.2-1i*0.0047*X.^4.1);
            % Re(kc): 0.0004*X^6.2; attenuation: 0.0069*X^4.1.
            kc = k0.*(1+0.0004*X.^6.2-1i*0.0069*X.^4.1);
        case 'JCA'
            tau = p(1); Lv = p(2)*1e-6; Lt = p(3)*1e-6;
            rho = (air.rho0*tau/phi).*(1 + sigma*phi./(1i*w*air.rho0*tau).* ...
                sqrt(1+1i*4*tau^2*air.eta*air.rho0*w/(sigma^2*Lv^2*phi^2)));
            thermal = 1 + 8*air.eta./(1i*w*air.Pr*air.rho0*Lt^2).* ...
                sqrt(1+1i*w*air.Pr*air.rho0*Lt^2/(16*air.eta));
            K = (air.gamma*air.P0/phi)./(air.gamma-(air.gamma-1)./thermal);
            % Bulk effective rho and K already include 1/phi. No extra
            % division of Zc by phi is appropriate with this convention.
            Zc = sqrt(rho.*K);
            kc = w.*sqrt(rho./K);
        otherwise
            error('Unknown model: %s',char(model));
    end
    % Algebraically equivalent to Zs=-1i*Zc*cot(kc*d), but avoids its poles.
    numerator = -1i*Zc.*cos(kc*d)-air.Z0*sin(kc*d);
    denominator = -1i*Zc.*cos(kc*d)+air.Z0*sin(kc*d);
    reflection = numerator./denominator;
    alpha = real(1-abs(reflection).^2);  % Deliberately NOT clipped to [0,1].
    assert(all(isfinite(alpha)), 'Nonfinite absorption prediction.');
end

function [best, runs] = fitJCA(f,y,d,sigma,phi,air,cfg,starts)
    % Logistic transform bounds a LOG parameter space; fminsearch is base MATLAB.
    lo = log10(cfg.jcaLower);
    span = log10(cfg.jcaUpper)-lo;
    decode = @(z) 10.^(lo+span.*(1./(1+exp(-max(-36,min(36,z))))));
    loss = @(z) jcaLoss(decode(z),f,y,d,sigma,phi,air);
    options = optimset('Display','off','MaxIter',cfg.maxIterations, ...
        'MaxFunEvals',cfg.maxFunctionEvaluations,'TolX',1e-8,'TolFun',1e-12);
    par = nan(cfg.jcaStarts,3);
    scores = inf(cfg.jcaStarts,1);
    flags = zeros(cfg.jcaStarts,1);
    iterations = zeros(cfg.jcaStarts,1);
    evals = zeros(cfg.jcaStarts,1);
    for j = 1:cfg.jcaStarts
        z0 = log(starts(j,:)./(1-starts(j,:)));
        [z,scores(j),flags(j),output] = fminsearch(loss,z0,options);
        par(j,:) = decode(z);
        iterations(j) = output.iterations;
        evals(j) = output.funcCount;
    end
    [~,idx] = min(scores);
    assert(isfinite(scores(idx)) && scores(idx)<1e25, 'JCA optimization failed.');
    best.p = par(idx,:);
    best.exitflag = flags(idx);
    normalized = (log10(best.p)-lo)./span;
    best.nearBound = any(normalized<cfg.boundWarningFraction | ...
        normalized>1-cfg.boundWarningFraction);
    % Sensitivities with respect to log10(physical parameter), for scale balance.
    h = 1e-4;
    J = zeros(numel(f),3);
    for j = 1:3
        high = best.p; low = best.p;
        high(j) = min(cfg.jcaUpper(j),high(j)*10^h);
        low(j) = max(cfg.jcaLower(j),low(j)/10^h);
        J(:,j) = (absorptionModel("JCA",f,d,sigma,phi,high,air)- ...
            absorptionModel("JCA",f,d,sigma,phi,low,air))/log10(high(j)/low(j));
    end
    singularValues = svd(J,0);
    best.jacCondition = Inf;
    if singularValues(end)>0
        best.jacCondition = singularValues(1)/singularValues(end);
    end
    runs = table((1:cfg.jcaStarts).',par(:,1),par(:,2),par(:,3),scores,flags, ...
        iterations,evals,'VariableNames',{'Start','Tortuosity','ViscousLength_um', ...
        'ThermalLength_um','SSE','ExitFlag','Iterations','FunctionEvaluations'});
    runs.IsSelected = false(height(runs),1);
    runs.IsSelected(idx) = true;
end

function SSE = jcaLoss(p,f,y,d,sigma,phi,air)
    prediction = absorptionModel("JCA",f,d,sigma,phi,p,air);
    SSE = sum((prediction-y).^2);  % Equal weight for every supplied row.
    if ~isfinite(SSE), SSE = 1e30; end
end

function saveSamplePlot(sample,f,y,curveF,curveY,metrics,folder,safeName,cfg)
    visibility = 'off';
    if cfg.showPlots, visibility = 'on'; end
    fig = figure('Color','w','Visible',visibility,'Name',char(sample), ...
        'Position',[100,100,900,600]);
    ax = axes('Parent',fig);
    hold(ax,'on');
    semilogx(ax,f,y,'ko','MarkerFaceColor','w','MarkerSize',5,'LineWidth',1.1);
    colors = [0.00 0.34 0.58; 0.85 0.33 0.10; 0.20 0.55 0.32; 0.49 0.25 0.62];
    styles = {'-','--','-.','-'};
    labels = {'Experimental'};
    displayNames = {'Delany-Bazley','Miki','Komatsu','JCA'};
    for m = 1:4
        semilogx(ax,curveF,curveY(:,m),'LineStyle',styles{m}, ...
            'Color',colors(m,:),'LineWidth',1.8);
        labels{end+1} = sprintf('%s (R^2 = %.3f)',displayNames{m},metrics.R2(m)); %#ok<AGROW>
    end
    set(ax,'XScale','log','FontName','Arial','FontSize',12,'LineWidth',1, ...
        'Box','on','TickDir','out');
    grid(ax,'on');
    xlabel(ax,'Frequency (Hz)');
    ylabel(ax,'Normal-incidence absorption coefficient, \alpha');
    title(ax,sprintf('Sample %s',char(sample)),'Interpreter','none');
    xlim(ax,[min(curveF),max(curveF)]);
    % Expand instead of hiding nonphysical predictions outside [0,1].
    ylim(ax,[min(0,min(curveY(:)))-0.02,max(1,max(curveY(:)))+0.02]);
    legend(ax,labels,'Location','best','FontSize',10);
    drawnow;
    print(fig,fullfile(folder,[safeName '_comparison.png']),'-dpng','-r300');
    if ~cfg.showPlots, close(fig); end
end
