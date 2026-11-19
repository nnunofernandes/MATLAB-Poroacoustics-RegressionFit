# Sound absorption: MATLAB prediction and JCA regression

## Run

1. Extract this folder and open `fit_absorption_models.m` in MATLAB R2018b or newer.
2. Keep `absorption_data.csv` and `sample_properties.csv` alongside the script.
3. Click **Run** to execute the whole script. No add-on toolboxes are required.
4. At the Command Window prompts, enter **thickness in mm**, **airflow resistivity in Pa s/m²**, and **open porosity as a fraction** for each sample. For example, 90% porosity is entered as `0.90`. These are your measured properties; no sample values have been assumed.
5. The completed properties CSV is saved for reuse. Set `cfg.promptEveryRun = true` to review/edit every value interactively, or edit the CSV before running again.

You can fill the blank properties CSV first to avoid interactive entry. Use decimal points in CSV files. Interactive prompts accept either a decimal point or a decimal comma. Enter **resistivity**, not flow resistance: if area-specific flow resistance is measured in Pa s/m, divide by layer thickness in metres to obtain resistivity in Pa s/m². A value reported in kPa s/m² must be multiplied by 1000.

The attached data already have the correct long format, with columns `Sample,Frequency_Hz,Alpha`. The script finds sample identifiers automatically and processes **A, AP, B, BP, C, CP, D, DP** independently. Separate source files are unnecessary. B and D have fewer rows than some other samples; no observations are fabricated or interpolated before fitting. The file contains 292 observations, spanning approximately 200–1800 Hz overall.

To process only one sample, change `cfg.selectedSamples` to `"A"`. To process a subset, use `["A";"AP"]`. Leave it empty for all samples. Set `cfg.fitFrequencyRange_Hz` to restrict the analysis; the same retained observations are used for every model for that sample. The saved input CSV contains all valid original rows, whereas prediction and metric files contain the selected frequency band.

## What is predicted and what is fitted?

| Model | Fixed user inputs | Parameters estimated from absorption |
|---|---|---|
| Delany–Bazley | Thickness, airflow resistivity | None; published coefficients remain fixed |
| Miki | Thickness, airflow resistivity | None; published coefficients remain fixed |
| Komatsu | Thickness, airflow resistivity | None; published coefficients remain fixed |
| JCA | Thickness, airflow resistivity, open porosity | High-frequency tortuosity, viscous characteristic length, thermal characteristic length |

Porosity is entered once for each sample and is used only by JCA. Resistivity is **fixed to the same measured input in every model**. Thickness is also fixed. The first three models therefore provide forward predictions, with goodness of agreement evaluated against the data. Changing their published coefficients would constitute a separate recalibration, which this script does not perform.

JCA minimizes the sum of squared absorption residuals with **32 reproducible starting points** using base MATLAB `fminsearch`. A logistic transformation in logarithmic parameter space enforces the bounds. No artificial offset, amplitude multiplier, or adjustable thickness is included.

Default JCA bounds, adjustable in the settings section:

| Fitted parameter | Lower bound | Upper bound |
|---|---:|---:|
| Tortuosity | 1 | 10 |
| Viscous characteristic length | 1 µm | 5000 µm |
| Thermal characteristic length | 1 µm | 5000 µm |

The two lengths are bounded independently; the script does not impose a universal ordering on them. These deliberately broad search bounds are computational choices and should be narrowed if independent measurements justify it. Multistart reduces sensitivity to initial guesses; it does not prove a global optimum or unique physical identification.

## Outputs

Each run creates a new time-stamped folder inside `absorption_results`, alongside the absorption data. Each sample has its own folder.

| File for sample A | Contents |
|---|---|
| `A_fitted_values.csv` | Frequency, experimental absorption, and predicted absorption for all four models at exactly the retained experimental frequencies |
| `A_R2.csv` | One row per model: R², RMSE, MAE, SSE, number of free parameters, frequency band, and diagnostics |
| `A_parameters.csv` | One row per model: fixed thickness and resistivity, plus JCA porosity and the three fitted JCA parameters; unused fields are NaN |
| `A_smooth_curves.csv` | All four model curves evaluated on 500 logarithmically spaced frequencies within the retained band, without extrapolation |
| `A_JCA_multistart.csv` | JCA parameter estimates, SSE, convergence flag and iteration/evaluation counts for every start; `IsSelected` marks the retained run |
| `A_input.csv` | Valid original absorption rows for the sample |
| `A_comparison.png` | Experimental points and the four model curves, with their R² values; 300 dpi |

Combined files are `ALL_samples_R2.csv` (samples as rows, four model columns), `ALL_samples_parameters.csv`, and `ALL_samples_fit_metrics.csv`. Completed inputs are preserved as `sample_properties_used.csv`; `run_settings.mat` preserves settings, air properties, and starting points. Combined metric and parameter files are checkpointed after each completed sample.

The supplied package contains **no fitted numerical results**, because your measured thickness, resistivity, and porosity have not yet been entered.

## Goodness of agreement

For each model on the same observed frequencies:

`SSE = sum((alpha_experimental - alpha_predicted).^2)`

`R2 = 1 - SSE / sum((alpha_experimental - mean(alpha_experimental)).^2)`

`RMSE = sqrt(SSE/N)`

`MAE = mean(abs(alpha_experimental - alpha_predicted))`

R² is not computed as squared correlation and is allowed to be negative. Negative R² means the prediction has a larger SSE than the experimental mean. Constant absorption data have undefined R², recorded as NaN. Each supplied observation has equal weight. Duplicate frequencies are retained as repeated observations and reported in the Command Window.

These are **in-sample agreement statistics**, not cross-validated predictive performance. JCA estimates three parameters from the same observations; the other models estimate none. A higher JCA R² alone does not establish better generalization. R² does not provide a confidence interval or validate the physical uniqueness of the inferred parameters. Where source curves were digitized from a graph, the numerical results also inherit that digitization uncertainty.

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

## Diagnostics and interpretation

- For DB, the fraction of points outside the commonly used `0.01 <= rho0*f/sigma <= 1` interval is reported. For Miki, the conservative original `0.01 <= f/sigma <= 1` interval is reported. These source-dependent conventions are explicitly distinguished. The points are still evaluated, so model statistics share the same observed frequencies. These diagnostics do not establish applicability to the sample material.
- No general validated frequency range is asserted for Komatsu or JCA. Their range fraction is NaN, not zero. DB, Miki and Komatsu were developed for fibrous materials; applying them to other structures requires experimental assessment.
- A JCA optimizer exit flag >0 means the selected local run met its numerical convergence criterion. A flag <=0 is reported without claiming convergence.
- `NearJcaBound` indicates an estimate within 1% of a logarithmic search interval boundary. Inspect the bounds, the model assumptions and the data before interpreting such an estimate.
- `JcaJacobianCondition` is the local sensitivity matrix condition number with respect to logarithmic physical parameters. Values above 1e6 trigger an ill-conditioning note. This is a local diagnostic, not a formal uncertainty analysis.
- Inspect `JCA_multistart.csv`: very different parameter sets with almost equal SSE indicate weak identification. Absorption magnitude alone may constrain parameters poorly, especially over a short frequency band. Complex surface impedance and/or additional thicknesses would provide additional information.
- Nonfinite/missing rows are removed with a warning. Absorption outside [0,1] is rejected for review rather than silently corrected. At least four distinct frequencies are required for each selected sample.

## Sources

1. Delany, M. E.; Bazley, E. N. (1970). Acoustical properties of fibrous absorbent materials. *Applied Acoustics*, 3, 105–116. https://doi.org/10.1016/0003-682X(70)90031-9
2. Allard, J.-F.; Champoux, Y. (1992). New empirical equations for sound propagation in rigid frame fibrous materials. *JASA*, 91, 3346–3353. https://doi.org/10.1121/1.402824 — the common density-scaled DB form used here is documented at https://matelys.com/apmr/PropagationModels/MotionlessSkeleton/DelanyBazleyModel.html
3. Miki, Y. (1990). Acoustical properties of porous materials—Modifications of Delany–Bazley models. *J. Acoust. Soc. Jpn. (E)*, 11, 19–24. https://doi.org/10.1250/ast.11.19 — coefficient convention: https://matelys.com/apmr/PropagationModels/MotionlessSkeleton/DelanyBazleyMikiModel.html
4. Komatsu, T. (2008). Improvement of the Delany–Bazley and Miki models for fibrous sound-absorbing materials. *Acoustical Science and Technology*, 29, 121–129. https://doi.org/10.1250/ast.29.121
5. Johnson, D. L.; Koplik, J.; Dashen, R. (1987). Theory of dynamic permeability and tortuosity in fluid-saturated porous media. *Journal of Fluid Mechanics*, 176, 379–402. https://doi.org/10.1017/S0022112087000727
6. Champoux, Y.; Allard, J.-F. (1991). Dynamic tortuosity and bulk modulus in air-saturated porous media. *Journal of Applied Physics*, 70, 1975–1979. https://doi.org/10.1063/1.349482 — equations: https://matelys.fr/apmr/PropagationModels/MotionlessSkeleton/JohnsonChampouxAllardModel.html

## Validation note

MATLAB is not installed in the creation environment. The MATLAB script could not be executed here. The forward equations and optimization strategy were independently checked numerically with Python/SciPy, including comparison of the two equivalent reflection formulas, the equivalent JCA thermal expression, fixed-input predictions for every supplied sample, and recovery of a synthetic JCA absorption curve. This does not substitute for an execution check in your MATLAB installation.
