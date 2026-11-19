# MATLAB absorption fitting within experimental uncertainty limits

This update allows measured thickness, airflow resistivity and open porosity to vary within limits you supply. It preserves a measured-input reference, fits each model independently within its permitted input intervals, and exports both results.

## Run

1. Extract the package, keeping `fit_absorption_models.m`, `absorption_data.csv` and `sample_properties.csv` together.
2. Open the script in **MATLAB R2018b or newer** and run the **whole script**. Only base MATLAB is required.
3. For every sample, enter its measured thickness in **mm**, airflow resistivity in **Pa s/m²**, and **open porosity as a fraction**.
4. After each measured value, enter the allowed **relative ± deviation in percent**. Enter **0** to keep that measured property fixed.
5. The completed measured values and interval endpoints are saved in `sample_properties.csv` for reuse. Results go into a new time-stamped subfolder of `absorption_results` alongside the source data.

The illustrative prompt defaults are ±5% for thickness, ±10% for resistivity and ±5% for porosity. **They are not measured uncertainties, recommended universal tolerances, or automatically established confidence intervals.** Replace them with the limits justified by your experiment. Every missing interval requires a prompt; the defaults are accepted only if you press Enter.

Example of relative percentage limits: a measured porosity of 0.88 with ±5% gives [0.836, 0.924], not [0.83, 0.93]. A measured thickness of 20 mm with ±5% gives [19, 21] mm. A measured resistivity of 90000 Pa s/m² with ±10% gives [81000, 99000] Pa s/m². These are examples only; no such sample values are prefilled.

Use **open porosity**, not automatically total gravimetric porosity. Enter resistivity, not flow resistance: divide area-specific flow resistance in Pa s/m by the layer thickness in metres to obtain resistivity in Pa s/m². Multiply values in kPa s/m² by 1000. Interactive prompts accept decimal points or decimal commas; CSV files use decimal points.

## Explicit/asymmetric bounds and saved inputs

Set `cfg.boundInputMode = 'endpoints'` to enter lower and upper endpoints instead of relative percentages. You can also fill the bounds directly in the properties CSV:

| Measured value column | Lower endpoint column | Upper endpoint column |
|---|---|---|
| `Thickness_mm` | `ThicknessLower_mm` | `ThicknessUpper_mm` |
| `Resistivity_Pa_s_m2` | `ResistivityLower_Pa_s_m2` | `ResistivityUpper_Pa_s_m2` |
| `Porosity` | `PorosityLower` | `PorosityUpper` |

All endpoints must be positive, each interval must contain its measured value, and porosity must not exceed 1. Equal lower and upper endpoints freeze the input. For percentage input, a porosity upper bound above 1 is capped at 1 and the actual interval is printed. This can make the interval asymmetric.

An old properties CSV with only the original four columns is accepted: the script adds the six endpoint columns and asks for the missing limits. Existing valid endpoints are reused without a prompt when `cfg.promptEveryRun = false`. Set it to `true` to review every nominal value and interval. Choose `'endpoints'` when reviewing bounds if you wish to retain asymmetric intervals; `'percent'` rebuilds them from the entered relative deviation. Properties for unselected samples are retained.

To process a single sample, set `cfg.selectedSamples = "A"`. For a subset use `["A";"AP"]`; leave it empty for all samples. Set `cfg.fitFrequencyRange_Hz` to restrict the frequency band.

## What is fitted?

| Model | Measured-input reference | Fit within experimental input limits |
|---|---|---|
| Delany–Bazley | Thickness and resistivity fixed; no free parameters | Thickness and resistivity may vary within their limits |
| Miki | Thickness and resistivity fixed; no free parameters | Thickness and resistivity may vary within their limits |
| Komatsu | Thickness and resistivity fixed; no free parameters | Thickness and resistivity may vary within their limits |
| JCA | Thickness, resistivity and porosity fixed; tortuosity and both characteristic lengths fitted | Thickness, resistivity and porosity may vary within their limits; tortuosity and both characteristic lengths also fitted |

The published empirical model coefficients remain fixed. Porosity is not an input to the first three models and is never fitted by them. Depending on zero-width intervals, the bounded empirical fits have **0–2** free parameters, and bounded JCA has **up to 6**. A model requires more distinct observed frequencies than its number of free parameters; at least four are required for the overall workflow.

Each model has its own optimum within the same user-supplied measured-input limits. Consequently its fitted thickness or resistivity can differ from those of another model. The script does not impose a single jointly optimized set shared by all models. The original measured values are retained separately; fitted values are model-conditioned estimates and do not replace the measurements.

JCA microstructural search bounds are set by `cfg.jcaLower` and `cfg.jcaUpper`:

| Parameter | Default lower | Default upper |
|---|---:|---:|
| Tortuosity | 1 | 10 |
| Viscous characteristic length | 1 µm | 5000 µm |
| Thermal characteristic length | 1 µm | 5000 µm |

The two characteristic lengths are bounded independently. These broad bounds are computational choices, not specimen-specific uncertainty estimates. They can be narrowed using independent information; equal endpoints freeze a JCA microparameter too.

## Optimization and checks

The objective is the **unweighted sum of squared absorption residuals**, with one equal weight per supplied observation. No offset, scale factor or empirical coefficient is calibrated. The search uses base MATLAB `fminsearch` from reproducible multiple starting points: 16 for each bounded empirical fit and 48 for each JCA scenario by default. A finite-difference damped least-squares refinement then polishes the best multistart result, also using only base MATLAB. Its iteration limit is `cfg.refinementIterations` (default 200). All positive parameters are scaled logarithmically. A bounded decoding function enforces the physical endpoints, including exact boundary values, and the objective penalizes overshoot in normalized coordinates. Exact coordinate endpoints are also checked after the multistart search; an improving boundary candidate is retained and identified separately.

The measured-input reference solution is always included as a feasible candidate for the corresponding bounded fit. The retained bounded SSE is therefore no greater than the reference SSE, subject to numerical tolerance. The script checks this. Including more freedom can improve agreement without improving predictive validity; improvement is not evidence that the adjusted properties are more accurate measurements.

The selected solution, all starting-point results, convergence flags and bound proximity are exported. Multistart does not certify a global optimum. The default run can take several minutes depending on the MATLAB installation and the data; edit the start counts to control the search effort. Increase them for an additional convergence assessment if parameter sets or SSE vary between searches.

## CSV and image outputs

Each sample gets its own output subfolder. No source-data splitting is required. The provided data contain eight samples and 292 observations, approximately 200–1800 Hz overall. Missing frequencies are not filled before fitting.

| File for sample A | Contents |
|---|---|
| `A_fitted_values.csv` | Experimental absorption, the four bounded best-fit predictions at the observed frequencies, and four measured-input reference predictions |
| `A_R2.csv` | Eight rows: four models × two scenarios, including R², RMSE, MAE, SSE, number of free parameters and diagnostics |
| `A_parameters.csv` | Eight rows with estimates, lower/upper bounds, nominal measured values and percentage changes in measured inputs |
| `A_smooth_curves.csv` | Both sets of model curves on 500 logarithmically spaced frequencies within the fitted band |
| `A_<model>_<scenario>_multistart.csv` | Reference (`Start=0`), optimization starts, least-squares refinement and endpoint checks; `CandidateType` identifies the candidate and `IsSelected` marks the retained result |
| `A_input.csv` | All valid original observations for the sample, before optional frequency filtering |
| `A_comparison.png` | Two panels comparing measured-input reference curves and fits within experimental limits, with R²; 300 dpi |

In the prediction files, `Alpha_Delany_Bazley`, `Alpha_Miki`, `Alpha_Komatsu` and `Alpha_JCA` contain **bounded-fit predictions**. Columns ending in `_Measured` contain the corresponding reference predictions. For JCA, that reference already includes regression of its microstructural parameters with measured experimental inputs held fixed.

The metric/parameter `Scenario` column is `Measured_inputs` or `Within_input_bounds`. For empirical models, unused porosity and microstructural parameter fields are NaN. Parameter fields ending in `_Lower` and `_Upper` identify each scenario's permitted values. The full measured-input intervals are also saved once per sample in `sample_properties_used.csv`. Change percentages describe deviations from the measured values.

Combined exports are `ALL_samples_R2.csv` (one sample per row, eight model/scenario columns), `ALL_samples_parameters.csv` and `ALL_samples_fit_metrics.csv`. Combined metric and parameter files are checkpointed after each sample. `run_settings.mat` saves the actual configuration, air properties and inputs. Every run uses a new results folder.

## Statistics and confidence terminology

`R2 = 1 - sum((observed-predicted).^2)/sum((observed-mean(observed)).^2)`

`RMSE = sqrt(SSE/N)` and `MAE = mean(abs(observed-predicted))`.

R² can be negative and is NaN for effectively constant observed absorption. It is not squared correlation. All models/scenarios for a sample use the same frequency rows, with no interpolation in the objective. Duplicate frequencies remain repeated observations with equal row weights. The curves in the smooth export are evaluations of the models, not interpolated observations.

The search intervals can be based on your experimentally established confidence intervals, expanded uncertainties, standard deviations or justified tolerances, but these meanings are **not interchangeable**. The script does not assign them a probability level, convert SD to a 95% interval, or compute confidence intervals for the inferred parameters. Independent rectangular intervals also do not encode correlations between measured properties or establish joint 95% coverage. If you have correlated experimental uncertainties, an appropriate joint constraint would require a further extension.

**Specific JCA identifiability limitation:** with thickness, resistivity, porosity and tortuosity all free, the equations admit the transformation `d -> a*d`, `sigma -> sigma/a`, `phi -> phi/a`, `tortuosity -> tortuosity/a^2`, with both characteristic lengths unchanged. Whenever the transformed values remain within the allowed bounds, the characteristic impedance and rigid-backed absorption are unchanged. This follows algebraically from the implemented equations and was checked numerically. Thus an excellent six-parameter fit need not select unique material properties. Fixing an independently well-established input (for example thickness, by entering 0% uncertainty) removes this particular scaling freedom. The script reports agreement and sensitivity diagnostics rather than claiming unique physical identification.

All reported agreement scores are **in-sample**. JCA can now have six adjustable parameters over a relatively narrow absorption band, so parameter nonuniqueness deserves particular attention. Distinct solutions with similar SSE should be reported as weak identification, not unique material constants. Complex impedance measurements and/or additional specimen thicknesses can provide more information. If the source curves were digitized, their digitization uncertainty also remains.


## Physics and conventions

The calculation assumes a homogeneous, air-saturated, rigid-frame layer measured at normal incidence against a rigid, impervious backing, **with no air gap**. It does not represent a transmitting OSB sandwich or a diffuse-field chamber measurement. Enter the specimen thickness and through-thickness open porosity/resistivity corresponding to the actual acoustic measurement.

Air defaults to 20 °C and 101325 Pa. The script derives density and sound speed consistently from an ideal-gas approximation with gamma = 1.4, estimates viscosity using Sutherland's law, and uses Pr = 0.71. Edit the temperature and pressure settings to match the experiment. The time convention is `exp(+i*omega*t)`.

For every model the rigid-backed surface impedance is

`Zs = -i*Zc*cot(kc*d)`

and `alpha = 1 - abs((Zs-Z0)/(Zs+Z0))^2`, with `Z0 = rho0*c0`. The script evaluates the algebraically equivalent sine/cosine reflection expression to avoid the cotangent poles. Predictions are never clipped into [0,1]; nonphysical predictions are flagged and remain visible in the plot and exported results.

**Delany–Bazley:** the common density-scaled formulation uses `X = rho0*f/sigma`:

`Zc/Z0 = 1 + 0.0571*X^(-0.754) - i*0.0870*X^(-0.732)`

`kc/k0 = 1 + 0.0978*X^(-0.700) - i*0.1890*X^(-0.595)`

**Miki:** the original convention implemented here uses `X = 1000*f/sigma`:

`Zc/Z0 = 1 + 5.50*X^(-0.632) - i*8.43*X^(-0.632)`

`kc/k0 = 1 + 7.81*X^(-0.618) - i*11.41*X^(-0.618)`

**Komatsu:** use the common logarithm `X = 2-log10(f/sigma)`, with f in Hz and sigma in Pa s/m²:

`Zc/Z0 = 1 + 0.00027*X^6.2 - i*0.0047*X^4.1`

`kc/k0 = 1 + 0.0004*X^6.2 - i*0.0069*X^4.1`

The Komatsu wavenumber coefficients above follow Eqs. (17)–(18) in the original paper: the phase correction uses 0.0004 and the attenuation correction uses 0.0069. They must not be interchanged. The expression requires `2-log10(f/sigma)>0`; the script stops with an explicit message if an entered resistivity violates that mathematical domain at any evaluated frequency. This is not a complete empirical validity criterion.

**JCA:** the implementation uses bulk effective density and bulk modulus, both including the porosity factor. It calculates `Zc = sqrt(rho_eff*K_eff)` and `kc = omega*sqrt(rho_eff/K_eff)` without an additional porosity division. Dynamic density follows Johnson–Koplik–Dashen and bulk modulus follows Champoux–Allard; the exact equations are commented in the MATLAB function and documented in the sources below.


## Diagnostics

- `NearBound` and `BoundParameters` flag estimates within 1% of an active logarithmic interval edge. Frozen parameters do not trigger a bound warning. A boundary optimum can indicate limited identifiability, imperfect model assumptions, or that the interval is restrictive; do not widen an experimentally justified interval simply to increase R².
- `JacobianCondition` describes local sensitivity to logarithmic free parameters. Above 1e6 the script records an ill-conditioning note; this is a diagnostic, not a confidence interval.
- `OptimizerExitFlag > 0` indicates local numerical convergence for the selected optimized start. A flag <=0 is reported. NaN with `SelectedSource=Reference_candidate` means no optimized result improved the retained feasible reference; it is not an optimizer convergence claim. NaN with `SelectedSource=Boundary_check` identifies an improving exact endpoint candidate and does not claim optimizer convergence for that candidate. NaN with `No_free_parameters` means no optimization was needed.
- The DB and Miki conventional range fractions use their explicitly different frequency/resistivity conventions. Their out-of-range observations remain in the comparison. Komatsu/JCA have NaN in this field because no universal applicability interval is asserted here.
- Nonphysical absorption predictions are not clipped; they remain in exports and are visible in plots. The Komatsu mathematical domain is checked using the entire allowed resistivity interval, before fitting.
- Missing/nonfinite rows are removed with a warning. Absorption outside [0,1] is rejected for review. No numerical fit results are supplied in this package because measured properties and their uncertainty limits have not been provided.

## Validation

MATLAB is unavailable in the creation environment, so this revised `.m` script has not been executed in MATLAB. The equations and revised bounded-search strategy were independently checked with Python/SciPy, including synthetic empirical-parameter recovery, an exact-bound optimum, zero-width/fixed inputs, damped least-squares refinement of six-variable JCA fitting, physical porosity limits, and retention of a feasible measured-input reference. These checks do not replace an execution check in MATLAB.

## Sources

1. Delany, M. E.; Bazley, E. N. (1970). Acoustical properties of fibrous absorbent materials. *Applied Acoustics*, 3, 105–116. https://doi.org/10.1016/0003-682X(70)90031-9
2. Allard, J.-F.; Champoux, Y. (1992). New empirical equations for sound propagation in rigid frame fibrous materials. *JASA*, 91, 3346–3353. https://doi.org/10.1121/1.402824 — the common density-scaled DB form used here is documented at https://matelys.com/apmr/PropagationModels/MotionlessSkeleton/DelanyBazleyModel.html
3. Miki, Y. (1990). Acoustical properties of porous materials—Modifications of Delany–Bazley models. *J. Acoust. Soc. Jpn. (E)*, 11, 19–24. https://doi.org/10.1250/ast.11.19 — coefficient convention: https://matelys.com/apmr/PropagationModels/MotionlessSkeleton/DelanyBazleyMikiModel.html
4. Komatsu, T. (2008). Improvement of the Delany–Bazley and Miki models for fibrous sound-absorbing materials. *Acoustical Science and Technology*, 29, 121–129. https://doi.org/10.1250/ast.29.121
5. Johnson, D. L.; Koplik, J.; Dashen, R. (1987). Theory of dynamic permeability and tortuosity in fluid-saturated porous media. *Journal of Fluid Mechanics*, 176, 379–402. https://doi.org/10.1017/S0022112087000727
6. Champoux, Y.; Allard, J.-F. (1991). Dynamic tortuosity and bulk modulus in air-saturated porous media. *Journal of Applied Physics*, 70, 1975–1979. https://doi.org/10.1063/1.349482 — equations: https://matelys.fr/apmr/PropagationModels/MotionlessSkeleton/JohnsonChampouxAllardModel.html

