# Sound absorption modelling of porous layers in MATLAB

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.24365069.svg)](https://doi.org/10.5281/zenodo.24365069)

Compare measured normal-incidence sound absorption with four equivalent-fluid models: **Delany–Bazley (DB), Miki, Komatsu, and Johnson–Champoux–Allard (JCA)**. The scripts model a homogeneous porous layer with a rigid frame, an impervious rigid backing, and zero backing air gap. The supplied dataset includes samples A, AP, B, BP, C, CP, D, and DP.

## Choose a workflow

| | Fixed measured inputs | Bounded input sensitivity |
| --- | --- | --- |
| Thickness and static airflow resistivity | Fixed at measured values in all four models | May vary independently within the supplied limits for each model |
| Open porosity | Fixed at its measured value in JCA | May vary within the supplied limits in JCA |
| DB, Miki and Komatsu | Forward predictions using published coefficients | Measured-input predictions and fits with up to two free inputs |
| JCA | Fits high-frequency tortuosity and the viscous and thermal characteristic lengths | Fits the same three JCA parameters in both scenarios. Up to three measured inputs may also vary in the bounded scenario |
| Best suited to | Benchmarking the four models at measured specimen properties | Evaluating how sensitive fit quality and estimated parameters are to the permitted input ranges |

The bounded workflow exports both `Measured_inputs` and `Within_input_bounds` for each model. Use these two scenarios from the **same bounded run** to assess the effect of releasing measured inputs. The two scripts ship with different optimization settings and different JCA bounds. In particular, the viscous characteristic length has an upper bound of **300 µm** in the fixed workflow and **30 µm** in the bounded workflow. Both use **1 µm** as the lower bound. For comparisons across scripts, record and align the JCA bounds and account for differences in the optimizer.

## Repository layout

Both scripts expect `absorption_data.csv` and `sample_properties.csv` by default. Use the following layout to keep saved inputs and generated results independent.

| Supplied file | Path in the repository |
| --- | --- |
| This README | `README.md` |
| `fixed input: fit_absorption_models` | `fixed_inputs/fit_absorption_models.m` |
| `fixed input: absorption_data` | `fixed_inputs/absorption_data.csv` |
| `fixed_input: sample_properties` | `fixed_inputs/sample_properties.csv` |
| `bounded_input: fit_absorption_models` | `bounded_inputs/fit_absorption_models.m` |
| `bounded_input: absorption_data` | `bounded_inputs/absorption_data.csv` |
| `bounded_input: sample_properties` | `bounded_inputs/sample_properties.csv` |

The two supplied absorption CSVs are identical. The existing variant-specific READMEs can also be kept as `fixed_inputs/README.md` and `bounded_inputs/README.md`.

## Quick start

**Requires MATLAB R2018b or newer.** Both workflows use base MATLAB.

1. Arrange the files as shown above, then open `fit_absorption_models.m` in the chosen folder.
2. In the settings section, optionally select samples with `cfg.selectedSamples` and specify the frequency band with `cfg.fitFrequencyRange_Hz`.
3. Click **Run** to execute the whole script. Provide missing sample properties when prompted. Completed inputs are saved to the local `sample_properties.csv` and reused in later runs. Set `cfg.promptEveryRun = true` to review them interactively.
4. Open the latest timestamped folder under `absorption_results/` beside the input CSV. Start with `ALL_samples_R2.csv` and the per-sample comparison plots.

### Input files

| File | Required columns or fields |
| --- | --- |
| `absorption_data.csv` | `Sample`, `Frequency_Hz`, `Alpha`. Use positive frequencies in Hz and absorption as a fraction from 0 to 1. Use one row per observation and at least four distinct frequencies per fitted sample. |
| `sample_properties.csv` | `Sample`, `Thickness_mm`, `Resistivity_Pa_s_m2`, `Porosity`. Use thickness in mm, static airflow resistivity in Pa·s/m², and open porosity as a fraction greater than 0 and at most 1. |

The supplied property templates contain `NaN` placeholders. Fill them with measured values or enter the values at the MATLAB prompts. Use decimal points in CSV files.

### Specify the bounded search

- Set `cfg.boundInputMode = 'percent'` for relative limits. Enter **0** for any property to hold it fixed. For example, ±10% around a measured resistivity of 90,000 Pa·s/m² gives a range of 81,000 to 99,000 Pa·s/m².
- Set `cfg.boundInputMode = 'endpoints'` to specify explicit limits, including asymmetric intervals. The bounded property template includes the corresponding lower and upper columns. Each interval must contain the measured value.
- The interactive defaults are ±5% for thickness, ±10% for resistivity and ±5% for open porosity. Use bounds justified by the experiment. For a sensitivity study limited to ±10% in resistivity and porosity, enter 0% for thickness and 10% for each of the other two inputs. The percentage mode caps the porosity upper endpoint at 1.

## Outputs

| Output | Contents |
| --- | --- |
| `ALL_samples_R2.csv` | R² by sample, with four model columns for the fixed workflow and eight model–scenario columns for the bounded workflow |
| `ALL_samples_fit_metrics.csv` | R², RMSE, MAE, SSE, number of free parameters and fit diagnostics across samples |
| `ALL_samples_parameters.csv` | Model inputs and fitted parameters across samples, with nominal values and search limits in the bounded workflow |
| `sample_properties_used.csv` and `run_settings.mat` | Inputs and settings recorded for the run |
| `<sample>_input.csv` and `<sample>_fitted_values.csv` | Input observations and predictions at the retained measurement frequencies |
| `<sample>_smooth_curves.csv` and `<sample>_comparison.png` | Curves evaluated within the retained frequency band and a visual comparison with the measurements when plotting is enabled |
| `<sample>_R2.csv` and `<sample>_parameters.csv` | Detailed metrics and parameters for one specimen |
| `*_multistart.csv` | Optimization candidates and the selected solution for fits with free parameters |

## Interpret the results

Both workflows compare predictions at the same retained frequencies within each sample. Fitting minimizes the sum of squared absorption residuals, which gives the same optimum as minimizing RMSE for a fixed set of observations. The bounded workflow includes its measured-input reference among the feasible candidates, so releasing inputs can only maintain or reduce the reported SSE, up to numerical tolerance. This shows how much the fit can improve within the chosen ranges. Treat those ranges as search limits and the resulting metrics as in-sample measures of agreement.

Review parameters close to their bounds and inspect the multistart results. Similar residual errors across markedly different parameter sets indicate that the absorption data weakly constrain those parameters. Report the frequency band, search intervals, JCA parameter bounds and number of free parameters when comparing fits.

## Model references

- Delany and Bazley (1970), *Acoustical properties of fibrous absorbent materials*. [DOI](https://doi.org/10.1016/0003-682X(70)90031-9)
- Miki (1990), *Acoustical properties of porous materials: Modifications of Delany–Bazley models*. [DOI](https://doi.org/10.1250/ast.11.19)
- Komatsu (2008), *Improvement of the Delany–Bazley and Miki models for fibrous sound-absorbing materials*. [DOI](https://doi.org/10.1250/ast.29.121)
- Johnson, Koplik and Dashen (1987), *Theory of dynamic permeability and tortuosity in fluid-saturated porous media*. [DOI](https://doi.org/10.1017/S0022112087000727)
- Champoux and Allard (1991), *Dynamic tortuosity and bulk modulus in air-saturated porous media*. [DOI](https://doi.org/10.1063/1.349482)
