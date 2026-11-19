%% SOUND ABSORPTION: FIT WITHIN EXPERIMENTAL UNCERTAINTY BOUNDS
% MATLAB R2018b+. Base MATLAB only. Run the WHOLE script.
% Input: Sample, Frequency_Hz, Alpha in absorption_data.csv.
% Each sample: nominal thickness [mm], resistivity [Pa*s/m^2], open porosity.
% Enter relative +/- limits or explicit endpoints. Zero width = fixed input.
% Limits are user-supplied uncertainty intervals, NOT computed confidence CIs.
% Every model is evaluated at measured inputs AND fitted within input bounds.
% JCA also fits tortuosity and the viscous/thermal characteristic lengths.
% Geometry: normal incidence, rigid backing, no air gap, rigid porous frame.

%% 1. User settings
cfg = struct;
cfg.dataFile = 'absorption_data.csv';
cfg.propertiesFile = 'sample_properties.csv';
cfg.selectedSamples = strings(0,1); % [] = all; e.g. ["A";"AP"]
cfg.promptEveryRun = false;         % true = review nominal inputs AND limits
cfg.boundInputMode = 'percent';     % 'percent' or 'endpoints'
% Illustrative prompt defaults ONLY; enter your actual experimental limits.
cfg.defaultUncertaintyPercent = [5,10,5]; % thickness, resistivity, porosity
cfg.fitFrequencyRange_Hz = [0 Inf];
cfg.airTemperature_C = 20;
cfg.atmosphericPressure_Pa = 101325;
cfg.prandtlNumber = 0.71;
cfg.jcaLower = [1,1,5];            % tortuosity, viscous um, thermal um
cfg.jcaUpper = [10,30,1500];
cfg.jcaInitial = [1.3,100,200];
cfg.jcaStarts = 48;               % each JCA scenario (3 to 6 free parameters)
cfg.empiricalStarts = 16;         % each bounded DB/Miki/Komatsu fit
cfg.randomSeed = 42;
cfg.maxIterations = 4000;
cfg.maxFunctionEvaluations = 20000;
cfg.refinementIterations = 200;   % bounded damped least-squares polishing
cfg.boundWarningFraction = 0.01;  % fraction of logarithmic search interval
cfg.curvePoints = 500;
cfg.makePlots = true;
cfg.showPlots = true;

%% 2. Data and settings validation
scriptFolder = fileparts(mfilename('fullpath'));
if isempty(scriptFolder), scriptFolder = pwd; end
dataPath = fullfile(scriptFolder,cfg.dataFile);
if ~isfile(dataPath)
    [fn,fp] = uigetfile('*.csv','Select absorption data CSV');
    if isequal(fn,0), error('No absorption data file selected.'); end
    dataPath = fullfile(fp,fn);
end
propertiesPath = fullfile(fileparts(dataPath),cfg.propertiesFile);
validateattributes(cfg.jcaLower,{'numeric'},{'vector','numel',3,'positive','finite'});
validateattributes(cfg.jcaUpper,{'numeric'},{'vector','numel',3,'positive','finite'});
assert(all(cfg.jcaUpper>=cfg.jcaLower) && cfg.jcaLower(1)>=1, ...
    'Invalid JCA bounds: upper >= lower and tortuosity >= 1 required.');
validateattributes(cfg.jcaInitial,{'numeric'},{'vector','numel',3,'positive','finite'});
validateattributes(cfg.jcaStarts,{'numeric'},{'scalar','integer','>=',1});
validateattributes(cfg.empiricalStarts,{'numeric'},{'scalar','integer','>=',1});
validateattributes(cfg.defaultUncertaintyPercent,{'numeric'}, ...
    {'vector','numel',3,'nonnegative','finite','<',100});
validateattributes(cfg.curvePoints,{'numeric'},{'scalar','integer','>=',2});
assert(any(strcmp(cfg.boundInputMode,{'percent','endpoints'})), ...
    'boundInputMode must be percent or endpoints.');
assert(numel(cfg.fitFrequencyRange_Hz)==2 && cfg.fitFrequencyRange_Hz(1)>=0 ...
    && cfg.fitFrequencyRange_Hz(2)>cfg.fitFrequencyRange_Hz(1), ...
    'Specify an increasing nonnegative frequency interval.');
validateattributes(cfg.airTemperature_C,{'numeric'},{'scalar','finite','>',-273.15});
validateattributes(cfg.atmosphericPressure_Pa,{'numeric'},{'scalar','positive','finite'});
validateattributes(cfg.prandtlNumber,{'numeric'},{'scalar','positive','finite'});
T = readtable(dataPath);
required = {'Sample','Frequency_Hz','Alpha'};
assert(all(ismember(required,T.Properties.VariableNames)), ...
    'Data CSV needs Sample, Frequency_Hz, Alpha.');
assert(isnumeric(T.Frequency_Hz) && isnumeric(T.Alpha),'Frequency and Alpha must be numeric.');
T.Sample = strtrim(string(T.Sample));
valid = ~ismissing(T.Sample) & strlength(T.Sample)>0 & ...
    isfinite(T.Frequency_Hz) & T.Frequency_Hz>0 & isfinite(T.Alpha);
if any(~valid)
    warning('Absorption:InvalidRows','Removing %d missing/invalid rows.',sum(~valid));
end
T = T(valid,required);
assert(~isempty(T),'No valid absorption data remain.');
assert(all(T.Alpha>=0 & T.Alpha<=1),'Alpha must be a fraction in [0,1]; values are not clipped.');
samples = unique(T.Sample,'stable');
if ~isempty(cfg.selectedSamples)
    requested = string(cfg.selectedSamples(:));
    assert(all(ismember(requested,samples)),'A selected sample is absent.');
    samples = samples(ismember(samples,requested));
end
fprintf('\nSamples: %s\n',strjoin(cellstr(samples),', '));
fprintf('Measured-input reference + fitting within user-supplied input limits.\n');
fprintf('These limits are not automatically computed statistical confidence intervals.\n');

%% 3. Nominal measured properties and uncertainty limits
nominalFields = {'Thickness_mm','Resistivity_Pa_s_m2','Porosity'};
lowerFields = {'ThicknessLower_mm','ResistivityLower_Pa_s_m2','PorosityLower'};
upperFields = {'ThicknessUpper_mm','ResistivityUpper_Pa_s_m2','PorosityUpper'};
fields = [nominalFields,lowerFields,upperFields];
P = [table(samples,'VariableNames',{'Sample'}), ...
    array2table(nan(numel(samples),numel(fields)),'VariableNames',fields)];
oldP = P([],:);
if isfile(propertiesPath)
    oldP = readtable(propertiesPath);
    assert(all(ismember([{'Sample'},nominalFields],oldP.Properties.VariableNames)), ...
        'Properties CSV needs Sample, Thickness_mm, Resistivity_Pa_s_m2, Porosity.');
    oldP.Sample = strtrim(string(oldP.Sample));
    assert(numel(unique(oldP.Sample))==height(oldP),'Duplicate sample identifiers in properties CSV.');
    % Automatically migrate a properties CSV from the original script.
    for j = 1:numel(fields)
        if ~ismember(fields{j},oldP.Properties.VariableNames)
            oldP.(fields{j}) = nan(height(oldP),1);
        end
        assert(isnumeric(oldP.(fields{j})),'Properties and endpoints must be numeric.');
    end
    [found,loc] = ismember(samples,oldP.Sample);
    P{found,fields} = oldP{loc(found),fields};
end
labels = {'Thickness [mm]','Airflow resistivity [Pa*s/m^2]','Open porosity [fraction]'};
for s = 1:height(P)
    fprintf('\nSample %s\n',char(P.Sample(s)));
    for j = 1:3
        if j==3, validator = @(x) x>0 && x<=1;
        else, validator = @(x) x>0; end
        P{s,nominalFields(j)} = askValue(labels{j},P{s,nominalFields(j)},validator,cfg.promptEveryRun);
        v = P{s,nominalFields(j)};
        low = P{s,lowerFields(j)}; high = P{s,upperFields(j)};
        validBounds = isfinite(low) && isfinite(high) && low>0 && ...
            low<=v && high>=v && (j~=3 || high<=1);
        if validBounds && ~cfg.promptEveryRun
            fprintf('  Reusing interval: [%.8g, %.8g]\n',low,high);
        elseif strcmp(cfg.boundInputMode,'percent')
            pct = cfg.defaultUncertaintyPercent(j);
            if validBounds, pct = 100*max(v-low,high-v)/v; end
            pct = askValue('Allowed +/- relative deviation [%]; 0 = fixed', ...
                pct,@(x) x>=0 && x<100,true);
            low = v*(1-pct/100); high = v*(1+pct/100);
            if j==3, high = min(1,high); end
        else
            if ~validBounds
                low = v*(1-cfg.defaultUncertaintyPercent(j)/100);
                high = v*(1+cfg.defaultUncertaintyPercent(j)/100);
                if j==3, high = min(1,high); end
            end
            low = askValue('Lower endpoint',low,@(x) x>0 && x<=v,true);
            high = askValue('Upper endpoint',high,@(x) x>=v && (j~=3 || x<=1),true);
        end
        P{s,lowerFields(j)} = low;
        P{s,upperFields(j)} = high;
        fprintf('  Search interval: [%.8g, %.8g]\n',low,high);
    end
end
remaining = oldP(~ismember(oldP.Sample,P.Sample),P.Properties.VariableNames);
writetable([remaining;P],propertiesPath);

%% 4. Air properties and output folder
air.P0 = cfg.atmosphericPressure_Pa;
air.gamma = 1.4; air.Pr = cfg.prandtlNumber;
temperatureK = cfg.airTemperature_C+273.15;
air.rho0 = air.P0/(287.05*temperatureK);
air.c0 = sqrt(air.gamma*air.P0/air.rho0);
air.eta = 1.716e-5*(temperatureK/273.15)^1.5*(273.15+111)/(temperatureK+111);
air.Z0 = air.rho0*air.c0;
outRoot = fullfile(fileparts(dataPath),'absorption_results');
if ~isfolder(outRoot), mkdir(outRoot); end
runFolder = fullfile(outRoot,datestr(now,'yyyymmdd_HHMMSS'));
baseFolder = runFolder; counter = 1;
while isfolder(runFolder)
    runFolder = sprintf('%s_%02d',baseFolder,counter); counter = counter+1;
end
mkdir(runFolder);
writetable(P,fullfile(runFolder,'sample_properties_used.csv'));
save(fullfile(runFolder,'run_settings.mat'),'cfg','air','dataPath','P');
modelNames = ["Delany_Bazley";"Miki";"Komatsu";"JCA"];
scenarios = ["Measured_inputs";"Within_input_bounds"];
allMetrics = table; allParameters = table;
r2Matrix = nan(numel(samples),8);
parameterLabels = [nominalFields,{'Tortuosity','ViscousLength_um','ThermalLength_um'}];

%% 5. Independent bounded regression for each sample and each model
for s = 1:numel(samples)
    sample = samples(s);
    original = sortrows(T(T.Sample==sample,:),'Frequency_Hz');
    inBand = original.Frequency_Hz>=cfg.fitFrequencyRange_Hz(1) & ...
        original.Frequency_Hz<=cfg.fitFrequencyRange_Hz(2);
    S = original(inBand,:); f = S.Frequency_Hz; y = S.Alpha;
    assert(numel(unique(f))>=4,'Sample %s needs at least four distinct frequencies.',char(sample));
    if numel(unique(f))<numel(f)
        warning('Absorption:RepeatedFrequency','Repeated frequencies retained with equal row weights.');
    end
    nominal = P{s,nominalFields};
    inputLow = P{s,lowerFields}; inputHigh = P{s,upperFields};
    assert(2-log10(max(f)/inputLow(2))>0, ...
        'Sample %s: Komatsu requires resistivity lower bound > max(f)/100.',char(sample));
    safeName = regexprep(char(sample),'[^a-zA-Z0-9_-]','_');
    if isempty(safeName), safeName = 'Sample'; end
    sampleFolder = fullfile(runFolder,sprintf('%02d_%s',s,safeName)); mkdir(sampleFolder);
    writetable(original,fullfile(sampleFolder,[safeName '_input.csv']));
    fprintf('\n[%d/%d] %s, %d observations\n',s,numel(samples),char(sample),numel(f));
    curveF = logspace(log10(min(f)),log10(max(f)),cfg.curvePoints).';
    predicted = nan(numel(f),4,2); curves = nan(numel(curveF),4,2);
    metrics = table; parameters = table;
    for m = 1:4
        name = modelNames(m);
        micro0 = max(cfg.jcaLower,min(cfg.jcaUpper,cfg.jcaInitial));
        seed = [nominal,micro0];
        for scenario = 1:2
            if scenario==1, low = [nominal,cfg.jcaLower]; high = [nominal,cfg.jcaUpper];
            else, low = [inputLow,cfg.jcaLower]; high = [inputHigh,cfg.jcaUpper]; end
            if m~=4
                % Empirical models do not depend on porosity or JCA parameters.
                low(3:6) = seed(3:6); high(3:6) = seed(3:6);
            end
            [fit,runs] = boundedFit(name,f,y,seed,low,high,air,cfg, ...
                cfg.randomSeed+100*s+10*m+scenario);
            predicted(:,m,scenario) = modelPrediction(name,f,fit.p,air);
            curves(:,m,scenario) = modelPrediction(name,curveF,fit.p,air);
            if scenario==1
                % A feasible reference candidate guarantees the bounded result
                % is never worse in SSE than the measured-input reference.
                reference = fit; seed = fit.p;
            else
                assert(fit.SSE<=reference.SSE+1e-10*max(1,reference.SSE), ...
                    'Internal error: bounded result worse than its feasible reference.');
            end
            if fit.nFree>0
                runs.Sample = repmat(sample,height(runs),1);
                runs.Model = repmat(name,height(runs),1);
                runs.Scenario = repmat(scenarios(scenario),height(runs),1);
                writetable(runs,fullfile(sampleFolder,sprintf('%s_%s_%s_multistart.csv', ...
                    safeName,char(name),char(scenarios(scenario)))));
            end
            metric = makeMetrics(sample,name,scenarios(scenario),f,y, ...
                predicted(:,m,scenario),curves(:,m,scenario),fit,air);
            param = table(sample,name,scenarios(scenario),fit.nFree, ...
                'VariableNames',{'Sample','Model','Scenario','NFreeParameters'});
            for j = 1:6
                value = fit.p(j); lv = low(j); uv = high(j);
                if m~=4 && j>=3, value = NaN; lv = NaN; uv = NaN; end
                param.(parameterLabels{j}) = value;
                param.([parameterLabels{j} '_Lower']) = lv;
                param.([parameterLabels{j} '_Upper']) = uv;
            end
            param.MeasuredThickness_mm = nominal(1);
            param.MeasuredResistivity_Pa_s_m2 = nominal(2);
            param.MeasuredPorosity = nominal(3);
            param.ThicknessChange_pct = 100*(fit.p(1)/nominal(1)-1);
            param.ResistivityChange_pct = 100*(fit.p(2)/nominal(2)-1);
            if m==4, param.PorosityChange_pct = 100*(fit.p(3)/nominal(3)-1);
            else, param.PorosityChange_pct = NaN; end
            if isempty(metrics), metrics = metric; parameters = param;
            else, metrics = [metrics;metric]; parameters = [parameters;param]; end %#ok<AGROW>
            r2Matrix(s,m+(scenario-1)*4) = metric.R2;
            fprintf('  %-14s %-20s R2=% .5f RMSE=%.5f (%d free)\n', ...
                char(name),char(scenarios(scenario)),metric.R2,metric.RMSE,fit.nFree);
            if strlength(metric.Notes)>0, fprintf('    %s\n',char(metric.Notes)); end
        end
    end
    values = table(repmat(sample,numel(f),1),f,y,'VariableNames', ...
        {'Sample','Frequency_Hz','Alpha_Experimental'});
    smooth = table(curveF,'VariableNames',{'Frequency_Hz'});
    for m = 1:4
        col = ['Alpha_' char(modelNames(m))];
        values.(col) = predicted(:,m,2); smooth.(col) = curves(:,m,2);
        values.([col '_Measured']) = predicted(:,m,1);
        smooth.([col '_Measured']) = curves(:,m,1);
    end
    writetable(values,fullfile(sampleFolder,[safeName '_fitted_values.csv']));
    writetable(smooth,fullfile(sampleFolder,[safeName '_smooth_curves.csv']));
    writetable(metrics,fullfile(sampleFolder,[safeName '_R2.csv']));
    writetable(parameters,fullfile(sampleFolder,[safeName '_parameters.csv']));
    if isempty(allMetrics), allMetrics = metrics; allParameters = parameters;
    else, allMetrics = [allMetrics;metrics]; allParameters = [allParameters;parameters]; end %#ok<AGROW>
    if cfg.makePlots
        try
            saveBoundedPlot(sample,f,y,curveF,curves,metrics,sampleFolder,safeName,cfg);
        catch plotError
            warning('Absorption:PlotFailed','CSVs saved; plot failed: %s',plotError.message);
        end
    end
    writetable(allMetrics,fullfile(runFolder,'ALL_samples_fit_metrics.csv'));
    writetable(allParameters,fullfile(runFolder,'ALL_samples_parameters.csv'));
end
summaryNames = [modelNames+"_Measured";modelNames+"_Bounded"];
R2summary = [table(samples,'VariableNames',{'Sample'}), ...
    array2table(r2Matrix,'VariableNames',cellstr(summaryNames))];
writetable(R2summary,fullfile(runFolder,'ALL_samples_R2.csv'));
fprintf('\nDone. Results:\n%s\n',runFolder); disp(R2summary);

%% Local functions

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


function a = modelPrediction(name,f,p,air)
    a = absorptionModel(name,f,p(1)/1000,p(2),p(3),p(4:6),air);
end

function [best,runs] = boundedFit(name,f,y,seed,low,high,air,cfg,randomSeed)
    assert(all(low>0 & low<=high) && all(seed>=low & seed<=high),'Invalid bounds or initial candidate.');
    free = find(high>low);
    best.nFree = numel(free);
    assert(numel(unique(f))>best.nFree, ...
        'Model %s needs more distinct frequencies than its %d free parameters.',char(name),best.nFree);
    best.p = seed;
    best.SSE = sum((modelPrediction(name,f,seed,air)-y).^2);
    best.exitflag = NaN; best.selection = "Reference_candidate";
    if name=="JCA", count = cfg.jcaStarts; else, count = cfg.empiricalStarts; end
    if isempty(free), count = 0; best.selection = "No_free_parameters"; end
    params = nan(count+1,6); scores = inf(count+1,1);
    flags = nan(count+1,1); iterations = zeros(count+1,1); evals = zeros(count+1,1);
    candidateTypes = repmat("Optimized_start",count+1,1);
    candidateTypes(1) = best.selection;
    params(1,:) = seed; scores(1) = best.SSE; selected = 1;
    if ~isempty(free)
        logLow = log10(low(free)); logSpan = log10(high(free))-logLow;
        decode = @(z) decodeBounded(z,seed,free,low,high,logLow,logSpan);
        objective = @(z) boundedLoss(z,decode,name,f,y,air);
        stream = RandStream('mt19937ar','Seed',randomSeed);
        starts = rand(stream,count,numel(free));
        starts(1,:) = (log10(seed(free))-logLow)./logSpan;
        if name=="JCA" && count>=2
            alternative = seed;
            alternative(4:6) = max(low(4:6),min(high(4:6),cfg.jcaInitial));
            starts(2,:) = (log10(alternative(free))-logLow)./logSpan;
        end
        options = optimset('Display','off','MaxIter',cfg.maxIterations, ...
            'MaxFunEvals',cfg.maxFunctionEvaluations,'TolX',1e-8,'TolFun',1e-12);
        for start = 1:count
            [z,~,flag,out] = fminsearch(objective,starts(start,:),options);
            candidate = decode(z);
            try
                score = sum((modelPrediction(name,f,candidate,air)-y).^2);
            catch
                score = Inf;
            end
            k = start+1;
            params(k,:) = candidate; scores(k) = score; flags(k) = flag;
            iterations(k) = out.iterations; evals(k) = out.funcCount;
            if score<best.SSE || (score<=best.SSE && flag>0 && isnan(best.exitflag))
                best.p = candidate; best.SSE = score; best.exitflag = flag;
                best.selection = "Optimized_start"; selected = k;
            end
        end
    end
    % Refine the best multistart result with bounded damped least squares.
    if ~isempty(free)
        z0 = (log10(best.p(free))-logLow)./logSpan;
        residualFunction = @(z) modelPrediction(name,f,decode(z),air)-y;
        [z,score,flag,niter,neval] = refineLeastSquares(residualFunction,z0,cfg.refinementIterations);
        k = size(params,1)+1;
        params(k,:) = decode(z); scores(k,1) = score; flags(k,1) = flag;
        iterations(k,1) = niter; evals(k,1) = neval;
        candidateTypes(k,1) = "Least_squares_refinement";
        if score<best.SSE
            best.p = params(k,:); best.SSE = score; best.exitflag = flag;
            best.selection = "Least_squares_refinement"; selected = k;
        end
    end
    % Check exact coordinate endpoints as well as optimizer candidates.
    % This catches a boundary optimum that stopped just inside the interval.
    for j = free
        for endpoint = [low(j),high(j)]
            candidate = best.p; candidate(j) = endpoint;
            try
                score = sum((modelPrediction(name,f,candidate,air)-y).^2);
            catch
                score = Inf;
            end
            k = size(params,1)+1;
            params(k,:) = candidate; scores(k,1) = score; flags(k,1) = NaN;
            iterations(k,1) = 0; evals(k,1) = 1;
            candidateTypes(k,1) = "Boundary_check";
            if score<best.SSE
                best.p = candidate; best.SSE = score; best.exitflag = NaN;
                best.selection = "Boundary_check"; selected = k;
            end
        end
    end
    best.nearBound = false; best.boundParameters = ""; best.jacCondition = NaN;
    if ~isempty(free)
        u = (log10(best.p(free))-log10(low(free)))./(log10(high(free))-log10(low(free)));
        hit = u<=cfg.boundWarningFraction | u>=1-cfg.boundWarningFraction;
        names = ["Thickness_mm","Resistivity_Pa_s_m2","Porosity", ...
            "Tortuosity","ViscousLength_um","ThermalLength_um"];
        best.nearBound = any(hit);
        best.boundParameters = strjoin(names(free(hit)),"; ");
        J = zeros(numel(f),numel(free));
        for k = 1:numel(free)
            j = free(k); up = best.p; down = best.p;
            up(j) = min(high(j),up(j)*10^1e-4);
            down(j) = max(low(j),down(j)/10^1e-4);
            J(:,k) = (modelPrediction(name,f,up,air)-modelPrediction(name,f,down,air)) ...
                /log10(up(j)/down(j));
        end
        sv = svd(J,0); best.jacCondition = Inf;
        if sv(end)>0, best.jacCondition = sv(1)/sv(end); end
    end
    runs = array2table([(0:size(params,1)-1).',params,scores,flags,iterations,evals], ...
        'VariableNames',{'Start','Thickness_mm','Resistivity_Pa_s_m2','Porosity', ...
        'Tortuosity','ViscousLength_um','ThermalLength_um','SSE','ExitFlag','Iterations','FunctionEvaluations'});
    runs.CandidateType = candidateTypes;
    runs.IsSelected = false(height(runs),1); runs.IsSelected(selected) = true;
    if name~="JCA"
        runs{:,{'Porosity','Tortuosity','ViscousLength_um','ThermalLength_um'}} = nan(height(runs),4);
    end
end

function p = decodeBounded(z,seed,free,low,high,logLow,logSpan)
    p = seed;
    % Clamping permits exact boundary values. Objective penalizes overshoot.
    p(free) = max(low(free),min(high(free), ...
        10.^(logLow+logSpan.*max(0,min(1,z)))));
end

function score = boundedLoss(z,decode,name,f,y,air)
    clipped = max(0,min(1,z));
    penalty = 1e4*sum((z-clipped).^2);
    try
        residual = modelPrediction(name,f,decode(z),air)-y;
        score = sum(residual.^2)+penalty;
        if ~isfinite(score), score = 1e30; end
    catch
        score = 1e30+penalty; % unusable numerical candidate; keep searching
    end
end

function [z,SSE,flag,iteration,evaluations] = refineLeastSquares(residualFunction,z,maxIterations)
    % Finite-difference damped Gauss-Newton; no Optimization Toolbox needed.
    z = max(0,min(1,z)); r = residualFunction(z); SSE = sum(r.^2);
    evaluations = 1; flag = 0; damping = 1e-3; iteration = 0;
    for iteration = 1:maxIterations
        J = zeros(numel(r),numel(z));
        for j = 1:numel(z)
            plus = z; minus = z;
            plus(j) = min(1,z(j)+1e-5); minus(j) = max(0,z(j)-1e-5);
            J(:,j) = (residualFunction(plus)-residualFunction(minus))/(plus(j)-minus(j));
            evaluations = evaluations+2;
        end
        gradient = J.'*r;
        % First-order projected gradient accounts for active endpoints.
        active = (z(:)<=1e-12 & gradient>0) | (z(:)>=1-1e-12 & gradient<0);
        projected = gradient; projected(active) = 0;
        if norm(projected,Inf)<1e-11, flag = 1; break; end
        H = J.'*J;
        D = diag(max(diag(H),1e-10));
        moving = ~active; step = zeros(size(gradient));
        step(moving) = -(H(moving,moving)+damping*D(moving,moving))\gradient(moving);
        accepted = false;
        for lineSearch = 0:12
            candidate = max(0,min(1,z+(0.5^lineSearch)*step.'));
            try
                nextR = residualFunction(candidate); nextSSE = sum(nextR.^2);
            catch
                nextSSE = Inf;
            end
            evaluations = evaluations+1;
            if nextSSE<SSE
                move = norm(candidate-z,Inf); previous = SSE;
                z = candidate; r = nextR; SSE = nextSSE;
                damping = max(1e-12,damping/3); accepted = true;
                if move<1e-10 && previous-SSE<1e-10*max(previous,eps), flag = 1; end
                break
            end
        end
        if flag==1, break; end
        if ~accepted
            damping = damping*10;
            if damping>1e12, break; end
        end
    end
end

function metric = makeMetrics(sample,name,scenario,f,y,predicted,curve,fit,air)
    SSE = sum((predicted-y).^2); SST = sum((y-mean(y)).^2);
    R2 = NaN;
    if SST>eps(max(1,sum(y.^2))), R2 = 1-SSE/SST; end
    RMSE = sqrt(SSE/numel(y)); MAE = mean(abs(predicted-y));
    outside = NaN; notes = "";
    if name=="Delany_Bazley"
        X = air.rho0*f/fit.p(2); outside = mean(X<0.01 | X>1);
    elseif name=="Miki"
        X = f/fit.p(2); outside = mean(X<0.01 | X>1);
    end
    if outside>0, notes = notes+"Some points outside conventional empirical range; "; end
    if fit.nearBound, notes = notes+"Near search bound: "+fit.boundParameters+"; "; end
    if fit.jacCondition>1e6, notes = notes+"Ill-conditioned local parameter sensitivity; "; end
    if fit.exitflag<=0, notes = notes+"Selected optimizer run did not converge; "; end
    if fit.selection=="Boundary_check"
        notes = notes+"Exact boundary candidate retained; no convergence claim for this candidate; ";
    elseif fit.nFree>0 && isnan(fit.exitflag)
        notes = notes+"Reference candidate retained; no optimized start improved SSE; ";
    end
    nonphysical = any(predicted<-1e-8 | predicted>1+1e-8) || any(curve<-1e-8 | curve>1+1e-8);
    if nonphysical, notes = notes+"Unclipped prediction outside [0,1]; "; end
    metric = table(sample,name,scenario,fit.nFree,numel(y),min(f),max(f), ...
        R2,RMSE,MAE,SSE,fit.exitflag,fit.selection,fit.nearBound,fit.boundParameters, ...
        fit.jacCondition,outside,nonphysical,notes,'VariableNames', ...
        {'Sample','Model','Scenario','NFreeParameters','NPoints','MinFrequency_Hz', ...
        'MaxFrequency_Hz','R2','RMSE','MAE','SSE','OptimizerExitFlag','SelectedSource', ...
        'NearBound','BoundParameters','JacobianCondition','OutsideConventionalRangeFraction', ...
        'NonphysicalPrediction','Notes'});
end

function saveBoundedPlot(sample,f,y,curveF,curves,metrics,folder,safeName,cfg)
    visibility = 'off'; if cfg.showPlots, visibility = 'on'; end
    fig = figure('Color','w','Visible',visibility,'Name',char(sample), ...
        'Position',[100,100,1250,520]);
    colors = [0 .34 .58; .85 .33 .10; .20 .55 .32; .49 .25 .62];
    styles = {'-','--','-.','-'};
    names = {'Delany-Bazley','Miki','Komatsu','JCA'};
    titles = {'Measured inputs','Best fit within experimental input limits'};
    scenarios = ["Measured_inputs","Within_input_bounds"];
    for scenario = 1:2
        ax = subplot(1,2,scenario,'Parent',fig); hold(ax,'on');
        semilogx(ax,f,y,'ko','MarkerFaceColor','w','MarkerSize',4,'LineWidth',1);
        labels = {'Experimental'};
        for m = 1:4
            semilogx(ax,curveF,curves(:,m,scenario),'Color',colors(m,:), ...
                'LineStyle',styles{m},'LineWidth',1.7);
            subset = metrics(metrics.Scenario==scenarios(scenario),:);
            labels{end+1} = sprintf('%s (R^2=%.3f)',names{m},subset.R2(m)); %#ok<AGROW>
        end
        set(ax,'XScale','log','FontName','Arial','FontSize',11,'LineWidth',1,'TickDir','out','Box','on');
        grid(ax,'on'); xlim(ax,[min(curveF),max(curveF)]);
        ylim(ax,[min(0,min(curves(:)))-.02,max(1,max(curves(:)))+.02]);
        xlabel(ax,'Frequency (Hz)'); ylabel(ax,'Absorption coefficient, \alpha');
        title(ax,sprintf('%s | %s',char(sample),titles{scenario}),'Interpreter','none');
        legend(ax,labels,'Location','best','FontSize',9);
    end
    drawnow; print(fig,fullfile(folder,[safeName '_comparison.png']),'-dpng','-r300');
    if ~cfg.showPlots, close(fig); end
end
