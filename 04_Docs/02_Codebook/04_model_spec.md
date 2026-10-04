# Model Specification

> **Last updated**: 2026-09-04

## Reading This Document

**Section numbering.** Top-level numbers are stable identifiers, not a sequence: `2)` and `4)` are reserved and intentionally absent. They belong to a pre-repository numbering scheme that predates the first commit in this repository (2026-05-14) and correspond to no active model. The numbers are not reused, because the matching `M*` model ids are referenced by `04_model_spec.csv`, `99_spec_to_code_map.csv`, and the QC layer; renumbering would break those references for no gain.

**Parameter ownership.** This document is the authoritative source for model parameter values. Where [research_plan.md](../01_Design/research_plan.md) or [research_procedure.md](../01_Design/research_procedure.md) discuss the same parameters, they carry the rationale and the execution context, and they defer to the tables here for the values themselves. A parameter value changed here must be changed in `config.R` and recorded in [decision_log.md](../03_Log/decision_log.md); it must not be restated as a literal in the design documents.

## 0) Canonical vs Supplementary Surface

- The active canonical model surface is [02_run_esda.R](../../02_Code/02_esda/02_run_esda.R) -> [03_run_exploratory_diagnostics.R](../../02_Code/02_esda/03_run_exploratory_diagnostics.R) -> [01_run_twfe_main.R](../../02_Code/03_models/01_run_twfe_main.R) -> [02_run_spdm_main.R](../../02_Code/03_models/02_run_spdm_main.R) -> [01_run_spdm_w_robustness.R](../../02_Code/04_robustness/01_run_spdm_w_robustness.R) -> [02_run_robustness.R](../../02_Code/04_robustness/02_run_robustness.R) -> [03_run_influence_robustness.R](../../02_Code/04_robustness/03_run_influence_robustness.R) -> [04_run_identification_diagnostics.R](../../02_Code/04_robustness/04_run_identification_diagnostics.R) -> [01_make_tables_figures.R](../../02_Code/05_reporting/01_make_tables_figures.R).
- All active canonical models and reporting use the `2019Q4~2025Q4` analysis sample. `2019Q1~2019Q3` is maintained only as a rolling/lag warm-up period for panel construction.
- TWFE, SPDM, GTWR, and optional preprocessing scripts under `80_optional/**` are part of a manual direct-run surface that is excluded from the default run and required test plans. Executing these files directly will perform the actual tasks without needing a separate `RUN_*` execution flag.
- The TWFE channel, interaction, age-mix, sector-share, selection, and family-comparison, SPDM channel path, and GTWR local appendix series are treated as supplementary/manual or appendix sidecars. The SPDM channel path is executed directly via [07_run_spdm_channel_path.R](../../02_Code/80_optional/spdm/07_run_spdm_channel_path.R).

## 1) ESDA

- Objective: Identify the presence of spatial dependence.
- Inputs: `panel_main.parquet`, `W_*.rds`
- Outputs:
  - `global_morans_i.csv`
  - `global_morans_i_by_w.csv`
  - `global_morans_i_by_yq.csv`
  - `global_morans_i_within.csv`
  - `global_bivariate_morans_i.csv`
  - `univariate_lisa_summary.csv`
  - `univariate_lisa_local.csv`
  - `bivariate_lisa_summary.csv`
  - `bivariate_lisa_local.csv`
  - `emerging_hotspot_summary.csv`
  - `emerging_hotspot_local.csv`
  - `distribution_map__*.png`
  - `univariate_lisa_map__*.png`
  - `bivariate_lisa_map__*.png`
  - `emerging_hotspot_map__*.png`
- Implementation Principles:
  - Distribution maps for `age60_floating_share`, `age60_resident_share`, `vitality_index_base`, and `vitality_sub_*` from the latest quarter cross-section are saved first.
  - Scale of each output. Global Moran's I is computed for **every quarter** of the active window, in two forms: on the levels, and on the two-way within transform. LISA, bivariate LISA, global bivariate Moran, and the maps are computed on the **latest-quarter cross-section only**; EHSA uses the full quarterly sequence by construction. All are reproducible under deterministic permutation seeds.
  - **Levels versus within.** `global_morans_i_within.csv` reports both scales side by side with `retained_share`, because the estimators identify from within-dong, within-quarter deviations rather than from levels. Autocorrelation confined to the cross-sectional levels is removed by the fixed effects before estimation and cannot on its own justify a spatial specification. Measured over all 25 quarters, the level scale is significant in 175 of 175 variable-quarters while the within scale is significant in 92; the exposures retain their structure (`age60_resident_share` significant in 92% of quarters within, `age60_floating_share` 96%) whereas the outcomes largely do not (`vitality_sub_economic` 52%, `vitality_sub_temporal` 40%, `vitality_sub_social` 36%, `vitality_sub_stability` 0%). This asymmetry, spatial structure surviving in `X` but not in `y`, is the empirical reason the significant SPDM spillovers arrive through `W X` rather than through `W y`.
  - Multiplicity. LISA runs one local test per dong, so roughly `alpha * n` rejections are expected under the null by construction. Both the uncorrected `p_value` and the Benjamini-Hochberg `p_value_fdr` are stored, with `significant`/`cluster` and `significant_fdr`/`cluster_fdr` alongside, and `n_expected_by_chance` in the summary. Any cluster count presented as a finding must be the corrected one.
  - Permutation counts are contracted in `config.R` (`cfg$esda_global_moran_nsim`, `cfg$esda_lisa_nsim`, `cfg$esda_bivariate_nsim`, `cfg$esda_ehsa_nsim`) rather than hard-coded. LISA and bivariate use 9,999: at the previous 499 the two-sided p-value floor was 0.004, which made a Bonferroni threshold of `0.05/425` unreachable by construction and left Benjamini-Hochberg almost no resolution.
  - **EHSA keeps 199 and is deliberately not raised.** It computes one Gi* series per dong across the whole quarterly sequence rather than a single cross-section, so a permutation costs 25 times what a LISA permutation costs on this panel. Measured on the 2026-09-04 run, raising it to 999 took the EHSA stage from roughly an hour to 6h00m and the whole ESDA step to 6h15m, against about 14 minutes for the global Moran, within-Moran, univariate LISA, and bivariate LISA stages combined. EHSA is a descriptive hot-spot classification rather than a multiplicity-corrected inference surface, so it does not need the resolution that justifies 9,999 for LISA.
  - Stage costs at the contracted settings, for planning a rerun: global and within Moran about 1 minute, univariate LISA about 1 minute, bivariate LISA about 12 minutes, EHSA about 1 hour.
  - The p-values for Global Moran's I are calculated using a permutation approach with a deterministic seed.
  - LISA quadrants are classified based on the signs of `z(x)` and `W z(x)` for univariate, and `z(x)` and `W z(y)` for bivariate analyses.
  - Bivariate LISA maps save all combinations of calculated aging variables and vitality indicators.
  - EHSA uses `queen_include_self` weights (queen contiguity including self-neighbors), following the Gi* convention of `sfdep::emerging_hotspot_analysis()`.
  - The core variables are `age60_resident_share`, `age60_floating_share`, `vitality_sub_*`, and `vitality_index_base`.

## 1A) Exploratory Diagnostics

- Objective: The two exploratory questions the spatial ESDA does not address.
- Execution condition: Part of `cfg$canonical_pipeline_scripts`, running after [02_run_esda.R](../../02_Code/02_esda/02_run_esda.R).
- Inputs: `panel_main.parquet`
- Outputs:
  - `exposure_response_bins.csv`
  - `exposure_linearity_tests.csv`
  - `outcome_quarterly_trend.csv`
  - `outcome_quarterly_trend.png`
- Implementation Principles:
  - **Functional form.** Every active model enters `lag4_age60_resident_share` linearly, over an exposure that ranges from roughly 0.11 to 0.49, and until now that assumption was never inspected. The binned exposure-response table uses equal-count bins on the two-way within transform, because a binned plot of raw levels would trace the cross-sectional gradient the fixed effects remove. `exposure_linearity_tests.csv` reports two checks against the linear specification: a quadratic term test, and a nonparametric comparison of the linear fit against bin dummies, which does not assume the departure is quadratic.
  - **Temporal shape.** `outcome_quarterly_trend.csv` reports the cross-sectional mean, median, p10, p90, and standard deviation of each outcome by quarter, with the `covid_period` flag attached. Reported on untransformed outcomes, because the point is to see the common time pattern the quarter fixed effects later absorb.
  - Diagnostic only: nothing here changes a specification. A rejected linearity test is an input to a modelling decision, recorded in [decision_log.md](../03_Log/decision_log.md), not an automatic respecification.

### 1A.1) Reading Requirement

The first run rejects linearity for four of the five outcomes:

| Outcome | Quadratic `p` | Lack-of-fit `p` (df 19) | Linearity |
| --- | --- | --- | --- |
| `vitality_sub_stability` | `0.006` | `5.5e-08` | rejected |
| `vitality_sub_temporal` | `0.953` | `1.2e-07` | rejected |
| `vitality_sub_social` | `0.302` | `2.4e-07` | rejected |
| `vitality_index_base` | `0.119` | `0.027` | rejected |
| `vitality_sub_economic` | `0.095` | `0.056` | not rejected |

Two readings follow. First, the quadratic test alone would have caught only one of the four: the departures are real but not quadratic in shape, which is why the nonparametric lack-of-fit comparison is the operative test and a RESET-style check would have been misleading here. Second, the outcome with the strongest evidence of non-linearity, `vitality_sub_social`, is also the only outcome that survives the influence diagnostic in section 6A.1. The one effect the design can currently defend is therefore also the one whose linear coefficient is the weakest summary of its own relationship, and a reported slope for it should be accompanied by the binned response in `exposure_response_bins.csv`.

## 3) TWFE Main Models

- Inputs: `panel_main.parquet`, `W_queen.rds`
- Base equation: `y_it ~ lag4_age60_resident_share + lag4_controls_it | adm_cd + yq`
- Standard error: `cluster = ~ adm_cd`
- Dependent variables:
  - Primary: `vitality_sub_economic`, `vitality_sub_social`, `vitality_sub_temporal`, `vitality_sub_stability`
  - Supplementary: `vitality_index_base`
- Outputs:
  - `twfe_main_models.csv`
  - `twfe_main_models.html`
  - `twfe_main_controls_used.csv`
  - `twfe_main_diagnostics.csv`
  - `twfe_main_residual_moran.csv`
  - `twfe_main_residual_moran_by_yq.csv`
  - `twfe_main_residual_moran_summary.csv`
  - `twfe_main_coefplot.png`
  - `twfe_main_coefplot_supplementary.png`
- Implementation Principles:
  - TWFE serves as the baseline / spatial diagnostic layer.
  - Since `ln_floating_pop` is included in the social vitality component and the composite vitality index, it is excluded from the main control variables.
  - Residual Moran output is a mandatory deliverable, and p-values are saved using a deterministic seed permutation approach (`permutation_two_sided_abs`) by default.
  - `twfe_main_residual_moran_by_yq.csv` is one test per quarter per model, 125 in all, so it carries `p_value_fdr`, `significant_fdr`, `fdr_method`, and `n_expected_by_chance` beside the uncorrected columns, and the summary carries `n_significant_fdr` and `share_significant_fdr`. Benjamini-Hochberg is applied within each model, matching the LISA treatment in section 1, because the 25 quarters of one model are the family a reader interprets together. Added 2026-09-12; before that the table reported only `share_p_lt_0_05`, which cannot be read without knowing that 1.25 rejections per model are expected by chance. Measured on the current run: 31 of 125 reject uncorrected, 24 survive the correction, against 6.25 expected. The corrected count is the one to quote.
  - `twfe_main_diagnostics.csv` carries `max_vif_within` and the per-term `vif_within_terms`. Multicollinearity had previously been reported only as a GTWR local diagnostic, leaving the global design without one. The VIF is computed on the two-way within transform, which is the design the estimator actually inverts; raw correlations among levels would overstate the collinearity a fixed-effects model faces.

## 3A) TWFE Channel Models

- Appendix TWFE channel family
- Inputs: `panel_main.parquet`, `twfe_main_controls_used.csv`
- Outputs:
  - `twfe_channel_models.csv`
  - `twfe_channel_controls_used.csv`
- Implementation Principles:
  - This is a quarterly appendix contract that includes both `lag4_age60_resident_share` and `lag2_age60_floating_share`.
  - `x_to_m` and `y_with_channels` are saved separately within the same quarterly panel contract.
  - `y_with_channels` inherits the main TWFE control contract by outcome, while `x_to_m` inherits the control set commonly selected across all main outcomes from `twfe_main_controls_used.csv`.

## 3B) TWFE Interaction Models

- Appendix resident FE COVID interaction family
- Inputs: `panel_main.parquet`, `twfe_main_controls_used.csv`
- Period flag: `covid_period = 1` represents the `2020Q1~2022Q2` quarterly sample.
- Equation structure:
  - `M4`: `Y_it ~ lag4_age60_resident_share + lag4_age60_resident_share:covid_period + controls | adm_cd + yq`

## 3C) TWFE Age-Mix Experiment

- Appendix TWFE age-mix family
- Execution condition: Run [03_run_twfe_age_mix_experiment.R](../../02_Code/80_optional/twfe/03_run_twfe_age_mix_experiment.R) directly.
- Inputs: `panel_main.parquet`, `registered_resident_population.parquet`
- Outputs:
  - `twfe_age_mix_experiment_models.csv`
  - `twfe_age_mix_experiment_controls_used.csv`
  - `twfe_age_mix_experiment_diagnostics.csv`
- Implementation Principles:
  - Using the quarterly average registered resident population by age group from the Ministry of the Interior and Safety, we group them into youth (20s-30s), middle-aged (40s-50s), and elderly (60+). They are log1p-transformed into `ln_young_resident_pop`, `ln_middle_resident_pop`, and `ln_old_resident_pop` and all set as exposures.
  - Because this is not a compositional model, the elderly group is not omitted as a reference category.
  - Controls inherit the current main TWFE control contract from `twfe_main_controls_used.csv`, and the lagged resident scale control, `lag4_ln_resident_pop`, is maintained.
  - **Timing departs from the main contract.** The three exposures are contemporaneous while every control is a 4-quarter lag. The main design lags the exposure to avoid simultaneous response, and this family does not, so its coefficients are not comparable in timing to the main TWFE result and carry no protection against reverse response. This is a property of the family as specified; it is stated here rather than inferred from the variable names.
  - `max_vif_within` and `vif_within_terms` are recorded in the diagnostics. They matter more here than anywhere else in the project: the three log age-group populations move together within a dong, giving within VIFs of `9.08`, `17.75` and `10.37` against `1.17` for the main TWFE design, which inflates the middle-age standard error by roughly `4.2` times relative to an orthogonal design. The same-domain total control is not the cause — dropping `lag4_ln_resident_pop` moves the largest VIF only from `17.75` to `17.55`.

## 3D) TWFE Vitality Component Models

- Appendix TWFE vitality components family
- Execution condition: Run [04_run_twfe_vitality_component_models.R](../../02_Code/80_optional/twfe/04_run_twfe_vitality_component_models.R) directly.
- Inputs: `panel_main.parquet`
- Outputs:
  - `twfe_vitality_component_models.csv`
  - `twfe_vitality_component_controls_used.csv`
  - `twfe_vitality_component_diagnostics.csv`
- Implementation Principles:
  - An appendix TWFE sidecar using individual vitality component variables (e.g. underlying components of commercial vitality such as sales counts, survival rates, continuity months, time-of-day entropy, etc.) as outcomes.
  - The exposure variable is fixed as `lag4_age60_resident_share`.
  - Controls inherit the main TWFE control candidates (`lag4_ln_resident_pop`, `lag4_ln_land_price_adjusted`, `lag4_transit_accessibility`, `lag4_ln_workplace_worker_pop`) and undergo the same outcome-specific screening.

## 5) SPDM

- Objective: Estimate direct, indirect, and total effects.
- Inputs: `panel_main.parquet`, `W_queen.rds`
- Main exposure variable: `lag4_age60_resident_share`
- Outputs:
  - `spdm_main_models.csv`
  - `spdm_impacts.csv`
  - `spdm_controls_used.csv`
  - `spdm_main_diagnostics.csv`
- Implementation Principles:
  - The main SPDM aligns with the TWFE main specification as a resident-only exposure.
  - The active main specification is a true SDM: `y_it = rho W y_it + X_it beta + W X_it theta + adm_cd FE + yq FE + e_it`.
  - The `W X` term generates the spatial lags of `lag4_age60_resident_share` and outcome-specific selected controls directly in the quarterly panel.
  - Interpretation of results focuses on direct, indirect, and total effects.
  - Impacts are calculated using the matrix expressions `S = (I - rho W)^(-1)` and `S(beta I + theta W)`.
  - **Inference is a dong-level wild bootstrap through the reduced form (since 2026-10-04).** `run_spdm_impact_bootstrap()` flips the sign of all within-scale structural residuals of a dong together, one Rademacher weight per dong, regenerates the outcome through `y* = (I - rho W)^-1 (Z gamma + e*)` with `build_spdm_reduced_form_resampler()`, refits the same `spml()` specification, and recomputes the matrix impacts, so `rho`, `beta` and `theta` are re-estimated jointly in every draw. The primary `*_se`, `*_z`, `*_p` and `*_ci_*` columns of `spdm_impacts.csv`, and `std.error`, `statistic` and `p.value` of `spdm_main_models.csv`, hold the bootstrap: the standard error is the standard deviation of the draws, the p-value its normal reading, the interval the 2.5 and 97.5 percentiles. The model-based values stay beside them as `direct_se_model`, `direct_p_model` and their indirect and total equivalents, and as `std.error_model` and `p.value_model`; `impact_se_method` and `se_method` read `adm_cd_wild_reduced_form_bootstrap`. Defaults are `SPDM_MAIN_BOOTSTRAP_R=1000`, `SPDM_MAIN_BOOTSTRAP_CORES=4` and `SPDM_MAIN_BOOTSTRAP_SEED` equal to the analysis seed, offset by the spec number for each outcome. A bootstrap with fewer than 90% valid draws reports no inference at all and is labelled `adm_cd_wild_reduced_form_bootstrap_failed`, rather than falling back to the model-based values. `spdm_main_diagnostics.csv` carries `boot_R`, `boot_valid_draws`, `boot_seed`, and the two resampler guard values `boot_roundtrip_max_deviation` and `boot_max_design_residual_cor`. QC check `S04` fails, and the evidence synthesis stops, on a main table without this inference. Dependence between dongs beyond what `rho W y` absorbs is not resampled, which is the limit of a one-way cluster scheme.
  - **Why the model-based standard errors are not reported.** They treat the errors of a dong as independent across quarters. The TWFE residuals on the same panel have an AR(1) coefficient of `0.61` to `0.81`, and the exposure is close to a dong-specific trend, the combination under which that assumption understates a standard error most. The 2026-10-04 run of the main bootstrap, 1,000 valid draws of 1,000 for every outcome, measures the understatement directly: the bootstrap impact standard errors are `1.96` to `4.64` times the model-based ones, for example `vitality_sub_economic` direct `0.637` against `0.137` and `vitality_sub_social` direct `0.456` against `0.102`, and the standard error of `rho` is `2.0` to `2.9` times its model-based value. They sit close to the TWFE dong-clustered errors, as they should. The point estimates are unchanged to `1e-7`.
  - **What survives (2026-10-04).** Of the 15 impacts, 13 were significant at 5% on the model-based errors and 3 are on the bootstrap: `vitality_sub_social` direct (`-2.083`, p < .001) and total (`-2.561`, p < .001), and `vitality_index_base` total (`-2.198`, p = .006). **No indirect effect is significant**: `vitality_sub_social` `-0.477` (p = .468, was .018), `vitality_sub_stability` `-2.145` (p = .071, was 7.5e-7), `vitality_index_base` `-1.203` (p = .208, was .0006), and the economic and temporal ones were never significant. `vitality_index_base` direct is `-0.995` (p = .070) and `vitality_sub_stability` direct `+0.570` (p = .439). `rho` remains significant for `vitality_sub_economic`, `vitality_sub_temporal` and `vitality_index_base` (`0.13` to `0.17`, p < .001), is marginal for `vitality_sub_social` (`0.082`, p = .068), and is not significant for `vitality_sub_stability`. The spillover reading of H2 is therefore not supported at 5% for any outcome under this inference; a spillover statement may be made only as a point estimate with its interval. The 2026-09-12 channel-path bootstrap of the same specification had already shown the same pattern for its four outcomes. A 2026-09-04 note that a 150-draw dong-level bootstrap returned `0.92` times the model-based standard error for `vitality_sub_social` is withdrawn: its code is not in the repository, the 1,000-draw runs contradict it, and a weight drawn per row instead of per dong would produce exactly that result. The specification itself still models no dependence in the time dimension; the bootstrap makes the inference robust to it rather than modelling it.
  - **The model-based impact simulation also drops a covariance.** `splm` 1.6-5's `spfeml()` inverts the full information matrix of `sigma^2`, `rho` and the coefficients, but returns `vcov` assembled block-diagonally, with the covariance between `rho` and every coefficient set to zero. The `*_model` impact columns therefore draw `rho` independently of `beta` and `theta`. The bootstrap does not use that matrix.
  - **Lee-Yu bias correction is available but not applied.** `spml()` passes `LeeYu = TRUE` through `...` to `spfeml()`; an earlier statement here that no such argument exists had been checked against the visible signature of `spml()` only, and was wrong. Lee and Yu (2010) show that the quasi-ML estimator of a spatial panel with fixed effects carries a bias of order `1/T` from the individual effects and `1/N` from the time effects, concentrated in `rho` and `sigma^2`. With `T = 25` and `N` of 423 to 424 both terms are small beside the inference problem above. The main fit does not apply the correction; `rho` is small (`0.02` to `0.17`), and no reported direction hinges on it.
  - **Panel and weights alignment is asserted at the estimator.** `splm` sorts the panel by the time index and then by the codes of the individual index factor, which `plm` keeps as given for a factor and sets alphabetically for a character column, and maps the sorted rows to the weights matrix by position without verifying the mapping. A row order inconsistent with the `listw` is accepted silently and returns plausible but wrong estimates. On this panel the `region.id` order differs from alphabetical order for 393 of the 425 dongs, and sorting alphabetically instead moves `rho` by 21% and `theta` by a factor of 2.3 with no error and no warning. `assert_spdm_panel_alignment()` checks the row order of every period against `region.id` immediately before each `spml()` handoff, in addition to the existing guard inside `W X` construction. It checks rows, not factor levels; every call site builds `adm_cd` as `factor(adm_cd, levels = keep_ids)` in `region.id` order, so the two coincide, but a character `adm_cd` would pass the assertion and still be sorted alphabetically inside `splm`.
  - **`lambda` is the spatial lag parameter, not a spatial error parameter.** `splm` exports the autoregressive parameter of a lag model under the name `lambda`, the opposite of the convention in which `lambda` denotes the error parameter. The term keeps `splm`'s name so the exported table matches `coef()` on the fitted object; the `spatial_param_role` column states what each row actually holds, taking the value `rho_spatial_lag` for that row in the `sar`, `sdm`, `gns`, and `sarar_sac` families.
  - The `splm` covariance matrix arrives without dimnames, so `spdm_get_vcov_matrix()` restores them from the coefficient vector before any name-based indexing.
  - `ln_floating_pop` is a component of the dependent variable, so it is excluded from the main SPDM control contract.
  - Sample rule: each outcome-control specification is reduced to complete cases on the outcome, the exposure, and the trial controls, and only administrative dongs observed in **every** remaining quarter are kept, so the estimation panel is strictly balanced. A specification is accepted only if it retains at least 20 dongs and at least `SPDM_MIN_PERIODS` quarters; the default of 20 is therefore a floor on the length of the balanced panel, not a per-dong observation threshold. Because a dong missing any single quarter is dropped in full, `n_units` in `spdm_impacts.csv` varies across outcomes (423 to 424 as of the 2026-09-12 rerun, 423 to 425 before it) rather than always equalling the 425 dongs of the panel. No outcome reaches 425 any more: `항동` now lacks the social sub-index and every composite for all 25 quarters, because its external inflow publishes as `NA` rather than a fabricated zero. The realized `n_units`, `n_periods`, and `n_obs` are recorded per outcome in `spdm_main_models.csv` and `spdm_impacts.csv`.
  - The control ladder in `choose_spdm_controls_for_spec()` adds candidate controls one at a time and keeps a control only if the specification still satisfies the balanced-sample gate, so the retained set is outcome-specific and is logged in `spdm_controls_used.csv`.
  - **The dropped dongs are not a random sample.** Missingness in the active window is small, 0.08% to 0.30% depending on the outcome, but it is confined to two administrative dongs: `둔촌1동` (Gangdong-gu, missing 24 of 25 quarters) and `항동` (Guro-gu, missing 8). Both are redevelopment sites, and they are far smaller commercially than the rest of the panel, with a median quarterly sales of 0.20 billion KRW against 32.2 billion and a median store count of 160 against 1,037. The balanced-panel rule therefore removes the two smallest, most disrupted districts rather than a random pair, and this is the concrete reason `n_units` falls to 423 or 424 for some outcomes. The direction of the resulting selection is that the estimation sample under-represents districts undergoing physical redevelopment; it should be stated in the sample description rather than left to be inferred from the varying `n_units`.

## 5A) SPDM Optional Channel Path Sidecar

- Optional/manual SPDM path family
- Execution condition: Run [07_run_spdm_channel_path.R](../../02_Code/80_optional/spdm/07_run_spdm_channel_path.R) directly.
- Inputs: `panel_main.parquet`, `W_queen.rds`
- Outputs:
  - `spdm_channel_models.csv`
  - `spdm_channel_impacts.csv`
  - `spdm_channel_controls_used.csv`
  - `spdm_channel_path_effects.csv`
  - `spdm_channel_bootstrap_draws.csv`
  - `spdm_channel_diagnostics.csv`
- Implementation Principles:
  - Fixed as `X = lag4_age60_resident_share` and `M = lag2_age60_floating_share`.
  - Since `lag2_age60_floating_share` lacks a 2018 floating source, `2019Q1~2019Q2` are missing warm-ups. The active channel path complete-case sample is formed from the analysis sample after `2019Q4`.
  - The total-effect equation estimates `Y ~ X + controls + W X + W controls` and the spatially lagged outcome via a quarterly Queen SDM.
  - The mediator equation estimates `M ~ X + controls + W X + W controls` and the spatially lagged mediator via a quarterly Queen SDM.
  - The outcome equation estimates `Y ~ X + M + controls + W X + W M + W controls` and the spatially lagged outcome via a quarterly Queen SDM.
  - Channel outcomes are `vitality_sub_economic`, `vitality_sub_temporal`, `vitality_sub_stability`, and `vitality_index_base`.
  - `vitality_sub_social` directly overlaps with the floating population source, so it is excluded as a standalone channel path outcome. However, to maintain the meaning of the composite vitality index encompassing the four sub-dimensions, `vitality_index_base` (which includes social vitality) is used, and a mediator source overlap caveat is recorded.
  - Records direct, indirect, and total effects for `c`, `a`, `b`, and `c_prime`, along with the `a*b` product indirect effect and the `c - c_prime` direct attenuation diagnostic.
  - Default `a*b` inference uses a dong-level wild bootstrap **through the reduced form**: `y* = (I - rho W)^-1 (Z gamma + e*)`, with the systematic part rebuilt from the coefficients rather than read from the fitted object. A resample that adds a perturbed residual to a fitted vector holds `W y` at its original value and discards the spatial multiplier the model exists to estimate, so it is not available here.
  - The draw is sequential, matching the mediation structure: the mediator is drawn first, then the outcome is drawn from the equation containing it with the **resampled** mediator substituted into the design. Both the total-effect equation and the outcome equation are then fitted to the same drawn outcome, because `c` and `c_prime` are two readings of one system rather than two data-generating processes.
  - Two guards run before any draw. The round trip checks that unit weights return the observed outcome, which catches period-slice, weights-dimension and unit-ordering errors; it cannot catch a wrong coefficient, because the structural residual absorbs whatever `gamma` leaves behind. Orthogonality of that residual to the design does catch it: on this panel a converged fit gives a maximum absolute correlation of `0.0000`, while inflating one coefficient by half raises it to `0.030`, so the threshold is set at `0.01`.
  - Only the `a*b` product is inferred from the bootstrap. The path-level p-values of `a`, `b`, `c` and `c'` in `spdm_channel_impacts.csv` and `spdm_channel_path_effects.csv` are model-based and understated in the same way as the pre-2026-10-04 main table (section 5), so they are not quoted as tests; the `c` path is the main specification, whose inference is in `spdm_impacts.csv`.
  - If the bootstrap is disabled or yields insufficient valid draws, `delta_independent_approx` is used as a fallback, but the result is interpreted as a mediation-oriented channel inference rather than an automatic full mediation judgment.
  - `mediated_share_vs_cprime` is accompanied by `mediation_pattern`, because a share outside `[0, 1]` is not a proportion mediated. A negative value means the channel offsets the direct path rather than transmitting it, and both patterns are routinely read as "x% of the effect runs through the mediator".

### 5A.1) Status of the Published Channel Path Table (re-run 2026-09-12)

**The bootstrap columns are now usable.** [07_run_spdm_channel_path.R](../../02_Code/80_optional/spdm/07_run_spdm_channel_path.R) was re-run on the rebuilt panel under the corrected reduced-form scheme `y* = (I - rho W)^-1 (Z gamma + e*)`, taking 1h56m at `SPDM_CHANNEL_BOOTSTRAP_R=1000`. All 12 rows return 1,000 valid draws of 1,000 and `bootstrap_method` reads `adm_cd_wild_residual`. The withdrawn version had used `fitted + residual * weight` on `splm` objects, which defines no `fitted` method; its bootstrap standard errors ran 5 to 56 times *smaller* than the delta-method approximation and 9 of 12 rows reported `bootstrap_p = 0.000`. Under the corrected scheme the ratio to the delta method runs `0.38` to `3.24` and 3 of 12 rows report `bootstrap_p = 0.000`.

**The correction reverses the delta-method reading of the indirect effect.** On the `indirect` scale the delta method, which assumes `a` and `b` are independent, understates the standard error by `2.35` to `3.24` times, and every indirect effect it calls significant becomes non-significant: `vitality_sub_economic` moves from `p = .020` to `p = .392`, `vitality_sub_temporal` from `.024` to `.294`, `vitality_index_base` from `.003` to `.194`, and the `vitality_sub_temporal` total from `.025` to `.266`. No mediation through `lag2_age60_floating_share` is established on the indirect scale for any outcome, and no mediation claim may be made from the delta columns. The `direct`-scale rows behave differently and the bootstrap is the tighter of the two there (`0.38` to `0.87` times the delta standard error), which is a reminder that the delta approximation is not uniformly conservative.

**Read `mediation_pattern` before `mediated_share_vs_cprime`.** Seven of the 12 rows are `inconsistent_mediation_opposite_sign` with a negative share, which means the channel offsets the direct path rather than transmitting it. A negative share is not a proportion mediated and must not be reported as one.

**The two pre-draw guards passed but are not published.** The round trip at unit weights and the orthogonality of the structural residual to the design both `stop()` on failure, so 12 fits completing with full draws establishes that both passed for all of them. Their realized values are not written to `spdm_channel_diagnostics.csv`, so a reader confirms them by the run completing rather than by reading a number. Recording them would cost a further two-hour re-run and was not done.

  - Runtime defaults are `RUN_SPDM_CHANNEL_BOOTSTRAP=TRUE`, `SPDM_CHANNEL_BOOTSTRAP_R=1000`, `SPDM_CHANNEL_BOOTSTRAP_CORES=4`, `SPDM_CHANNEL_IMPACT_SIM_R=1000`, and `SPDM_CHANNEL_IMPACT_CORES=4`. It uses parallel execution on macOS/Linux/GCP and sequential fallback on Windows.

## 5B) SPDM Interaction Models

- Appendix resident SDM COVID interaction family
- Inputs: `panel_main.parquet`, `W_queen.rds`, `spdm_main_controls_used.csv`
- Period flag: `covid_period = 1` represents the `2020Q1~2022Q2` quarterly sample.
- Equation structure:
  - `M4`: `Y_it ~ lag4_age60_resident_share + lag4_age60_resident_share:covid_period + controls`

## 5C) SPDM Age-Mix Experiment

- Appendix SPDM age-mix family
- Execution condition: Run [02_run_spdm_age_mix_experiment.R](../../02_Code/80_optional/spdm/02_run_spdm_age_mix_experiment.R) directly.
- Outputs:
  - `spdm_age_mix_experiment_models.csv`
  - `spdm_age_mix_experiment_impacts.csv`
  - `spdm_age_mix_experiment_controls_used.csv`
  - `spdm_age_mix_experiment_diagnostics.csv`
- Implementation Principles:
  - Using the quarterly average registered resident population by age group from the Ministry of the Interior and Safety, we group them into youth (20s-30s), middle-aged (40s-50s), and elderly (60+). They are log1p-transformed into `ln_young_resident_pop`, `ln_middle_resident_pop`, and `ln_old_resident_pop` and all set as exposures.
  - Because this is not a compositional model, the elderly group is not omitted as a reference category.
  - Controls inherit the current SPDM main control candidates, and the lagged resident scale control, `lag4_ln_resident_pop`, is maintained.
  - The age-mix appendix also uses a quarterly impact schema with `sample_min_yq` and `sample_max_yq`.
  - **Timing departs from the main contract** in the same way as section 3C: the three exposures are contemporaneous while the controls are 4-quarter lags.
  - `max_vif_within` and `vif_within_terms` are recorded in the diagnostics, for the reason given in section 3C.

## 5D) SPDM Sector-Share Experiment

- Appendix SPDM sector-share family
- Execution condition: Run [03_run_spdm_sector_share_experiment.R](../../02_Code/80_optional/spdm/03_run_spdm_sector_share_experiment.R) directly.
- Outputs:
  - `spdm_sector_share_experiment_models.csv`
  - `spdm_sector_share_experiment_impacts.csv`
  - `spdm_sector_share_experiment_controls_used.csv`
  - `spdm_sector_share_experiment_diagnostics.csv`
  - `spdm_sector_share_experiment_exposure_relations.csv`
- Implementation Principles:
  - Resident-only and floating-only exposure families are compared in a contemporaneous quarterly contract.
  - Whether the same-domain total control is retained is recorded in the diagnostics.

## 5E) SPDM W Robustness

- Objective: Check W-matrix sensitivity by re-estimating the same resident-only quarterly SDM contract across `queen`, `rook`, `knn6`, and `knn8`.
- The standard error contract does **not** match the main SPDM since 2026-10-04. Coefficients and spatial parameters are reported with model-based asymptotic ML SEs and impacts with model-based `vcov` simulation SEs, which understate the impact standard errors by a factor of two to five on this panel (section 5); only the main Queen table and the component sidecar carry the dong-level bootstrap. The W check is read for the spread of the point estimates across matrices, and its p-values are not quoted. The presentation tables built from it carry no p-value column for that reason.
- Outputs:
  - `spdm_w_robustness_models.csv`
  - `spdm_w_robustness_impacts.csv`
  - `spdm_w_robustness_controls_used.csv`
  - `spdm_w_robustness_diagnostics.csv`

### 5E.1) What the W Check Establishes (2026-09-12)

**The direct effect is W-robust; the indirect effect is not, and the two must be reported with different confidence.** Across `queen`, `rook`, `knn6` and `knn8` the direct effect keeps its sign for all five outcomes, and for the outcome the project actually reports, `vitality_sub_social`, it is tight: `-2.031` to `-2.083`, a spread of `3%` of the queen value. The other direct effects spread by `17%` (`vitality_sub_economic`), `31%` (`vitality_sub_temporal`), `34%` (`vitality_index_base`) and `84%` (`vitality_sub_stability`) of their queen value.

The indirect effects are a different matter. Their spread across the four matrices is `42%` of the queen value for `vitality_sub_social`, `69%` for `vitality_sub_stability`, `95%` for `vitality_index_base`, `344%` for `vitality_sub_economic`, and `2647%` for `vitality_sub_temporal`, where the sign also flips: `-0.053` under queen against `+1.357` under `knn8`. Four of five keep their sign, `vitality_sub_temporal` does not.

Two consequences for reporting. A spillover magnitude quoted from the queen matrix alone is quoting one draw from a range that the choice of neighbourhood definition moves by tens of percent at best. And no directional spillover claim may be made for `vitality_sub_temporal` at all, which is consistent with its indirect effect being insignificant under queen to begin with (`p = .93`) and with the outcome being `not_supported` in the evidence synthesis.

## 5F) SPDM Selection Sidecar

- Appendix selection family
- Outputs:
  - `spdm_selection_tests.csv`
  - `spdm_selection_family_comparison.csv`
- Implementation Principles:
  - Compares SEM, SAR, and SDM selection diagnostics within the same quarterly control contract as the main queen sample.
  - The family comparison table also stores `sample_min_yq` and `sample_max_yq`.

## 5G) SPDM Family Comparison Sidecar

- A manual sidecar for the appendix that does not replace the main SPDM. Its purpose is to compare spatial panel family selection sensitivity using the same quarterly Queen sample and control contract.
- Inputs:
  - `panel_main.parquet`
  - `W_queen.rds`
  - `spdm_main_diagnostics.csv`
  - `spdm_controls_used.csv`
- Comparison families:
  - `twfe_common`: A common-sample TWFE baseline re-fitted on the main SPDM sample.
  - `slx`: Two-way FE panel including `W X`, where direct=`beta`, indirect=`theta`, and total=`beta + theta`.
  - `sar`: Spatial lag panel.
  - `sdm`: A manual `W X` true SDM implementation identical to the main SPDM.
  - `sem`: Spatial error panel, where direct/indirect/total impacts are `not_applicable`.
  - `sdem`: Spatial error panel with manual `W X`, where direct=`beta`, indirect=`theta`, and total=`beta + theta`.
  - `sarar_sac`: Spatial lag + spatial error panel.
  - `gns`: A GNS/SAC-Durbin family encompassing `W y`, manual `W X`, and spatial error.
- Implementation Principles:
  - Only models where the `outcome x exposure` run succeeded in the main SPDM are targeted.
  - If the selected control contract between `spdm_main_diagnostics.csv` and `spdm_controls_used.csv` mismatches, the specification is recorded as a failure and not re-estimated.
  - All families are estimated by exactly reconstructing the balanced quarterly sample and the `2019Q4~2025Q4` active analysis horizon from the main SPDM.
  - For `SAR`, `SDM`, and `SARAR/SAC` where impacts are theoretically interpretable, direct/indirect/total impacts are recorded when available.
  - Since `SLX` and `SDEM` reflect `W X` effects without an endogenous `W y` feedback multiplier, they are interpreted distinctly from the feedback-inclusive matrix impacts of `SDM`.
  - Although `GNS` includes a spatial error, its average effects are recorded with the same `S = (I - rho W)^(-1)`, `S(beta I + theta W)` matrix impacts as `SDM`.
  - Since `SEM` is a spatial error model, focal coefficients and error parameters are compared, but spatial spillover impacts are not indicated.
  - **The comparison is of point estimates (added 2026-10-04).** The `splm` families report model-based ML standard errors, which understate uncertainty by a factor of two to five on this panel (section 5), while `slx` and `twfe_common` are clustered by dong. Their p-values therefore sit on different footings and are not compared across families; the `sdm` row reproduces the main point estimates but not the main inference, which is in `spdm_impacts.csv`.
  - **Information criteria are scoped, not missing by accident (added 2026-09-12).** `AIC` and `BIC` are populated only for `slx` and `twfe_common`, which are `fixest` fits. `splm` returns a log-likelihood for `sar`, `sdm`, `sem` and `sdem` and none for `sarar_sac` or `gns`, and it does not compute the lag-model and error-model likelihoods on a common basis: on `vitality_sub_social`, the same 10,600 observations give `+8,506` for `sar` and `+8,513` for `sdm` against `-25,581` for `sem` and `-25,569` for `sdem`, a gap of about 34,000 units that is a change of scale rather than a difference in fit. An information criterion built from these is valid inside `{sar, sdm}` or inside `{sem, sdem}`, never across the two and never against the `fixest` rows. The `ic_comparability` column states the scope on every row, because blank cells alone invited computing the number by hand and reading the scale gap as model selection. Within the comparable subsets the `W X` term earns its place: `sdm` beats `sar` and `sdem` beats `sem` for all five outcomes.

### 5G.1) What the Comparison Establishes on the Rebuilt Panel (2026-09-12)

The focal estimate is stable across all eight families, which is the reassurance the sidecar exists to provide: `vitality_sub_social` runs `-1.810` to `-2.190`, `vitality_index_base` `-0.969` to `-1.421`, `vitality_sub_economic` `-0.828` to `-0.982`, and `vitality_sub_temporal` `-1.014` to `-1.276`.

Two readings matter beyond that. First, the robust LM tests of the selection sidecar reject no spatial error dependence for four of five outcomes, and the main specification sets `spatial.error = "none"`, so the natural question is whether the unmodelled error term moves the reported impacts. It does not: adding it leaves the direct effect essentially unchanged and barely moves the indirect one. For `vitality_sub_social`, `sdm` gives direct `-2.083` and indirect `-0.477` against `sdem` at `-2.092` and `-0.432`; for `vitality_index_base`, `-0.995` and `-1.203` against `-0.992` and `-1.200`; for `vitality_sub_stability`, `0.570` and `-2.145` against `0.570` and `-2.135`. The exception is `sarar_sac`, which carries a spatial error but no `W X` and therefore forces the spillover through `rho`, giving a materially larger indirect effect for `vitality_sub_social` (`-1.167`) and `vitality_sub_temporal` (`-0.895`).

Second, `vitality_sub_stability` is the one outcome whose result depends on the family. Every family carrying `W X` (`sdm`, `sdem`, `gns`, `slx`) reports a focal estimate near `+0.57` with an indirect effect near `-2.14`, while every family without it (`sar`, `sem`, `sarar_sac`) reports a focal estimate between `-0.16` and `-0.09` with an indirect effect near zero. On this outcome `rho` is not significant and ESDA finds no within-scale spatial autocorrelation in any of the 25 quarters, so the entire spatial result rests on the `W X` term. It should be reported with that dependence stated.
- Outputs:
  - `spdm_family_models.csv`
  - `spdm_family_comparison.csv`
  - `spatial_family_main_table.csv` (Condensed table for reporting when running [01_make_tables_figures.R](../../02_Code/05_reporting/01_make_tables_figures.R))

## 5H) SPDM Vitality Component Models

- Appendix SPDM vitality components family
- Execution condition: Run [06_run_spdm_vitality_component_models.R](../../02_Code/80_optional/spdm/06_run_spdm_vitality_component_models.R) directly.
- Inputs: `panel_main.parquet`, `W_queen.rds`
- Outputs:
  - `spdm_vitality_component_models.csv`
  - `spdm_vitality_component_impacts.csv`
  - `spdm_vitality_component_controls_used.csv`
  - `spdm_vitality_component_diagnostics.csv`
- Implementation Principles:
  - An appendix Queen-based true SDM/SPDM sidecar using individual vitality component variables as outcomes.
  - The main exposure variable is fixed as `lag4_age60_resident_share` (along with its spatial lag `W lag4_age60_resident_share`).
  - Estimates direct, indirect, and total impacts of resident aging on each underlying vitality component.
  - Controls inherit the main SPDM control pool and its outcomes-specific selected control configurations.
  - **Inference follows the main contract (since 2026-10-04).** The component impacts are reported beside the main ones in the paper's SPDM table, so they carry the same dong-level reduced-form bootstrap in the primary columns, with the model-based values kept as `*_model` and the same `SPDM_MAIN_BOOTSTRAP_*` settings. On the 2026-10-04 run, with 1,000 valid draws of 1,000 for all 11 components, 5 of the 11 direct effects, 1 of the 11 indirect effects and 5 of the 11 total effects are significant at 5%, against 8, 6 and 9 on the model-based errors; the one indirect effect is `operating_months_rel_seoul` at p = .049. The point estimates are unchanged.

## 6) Robustness

- Objective: Check sensitivity to outcome definitions, sample windows, and W-Moran specifications.
- Outputs:
  - `robustness_summary.csv`
  - `robustness_compare.png`
- Implementation Principles:
  - The canonical shared panel retains only contemporaneous source variables and registered model lag variables.
  - Unregistered lag/lead families are not created.
  - Sample windows compare the `full` (`2019Q4~2025Q4`) and `pre2025` quarterly windows.

## 6A) Influence Robustness

- Objective: Measure how much of the reported aging effect rests on individual administrative dongs.
- Execution condition: Part of `cfg$canonical_pipeline_scripts`, running after [02_run_robustness.R](../../02_Code/04_robustness/02_run_robustness.R). Under the 2026-09-04 decision to report the full sample as the main specification, this diagnostic is a required companion to every main-text effect rather than an optional check, so it must not fall out of the default run.
- Inputs: `panel_main.parquet`, `adm_region_lookup.parquet`
- Outputs:
  - `influence_dfbeta.csv`
  - `influence_outlier_dongs.csv`
  - `influence_robustness_summary.csv`
- Implementation Principles:
  - Re-estimates the TWFE baseline rather than the SPDM main, because the diagnostic needs several hundred fits per outcome. TWFE shares the main exposure and control contract and is the project's declared diagnostic layer, so an effect that does not survive here is not one to defend under SPDM.
  - The primary measure is threshold-free. `dfbeta` is the change in the exposure coefficient when a single dong is dropped from the estimation sample, reported per dong per outcome, together with `dfbeta_in_se` (the change in units of the baseline standard error) and `pct_change`. This asks which dongs move the estimate rather than which observations look unusual.
  - A secondary outcome-tail diagnostic reports the dongs whose outcome values exceed `INFLUENCE_TAIL_Z` (default 5) in pooled z units, and the percentage by which those dongs inflate the pooled standard deviation. This matters because coefficients are reported per standard deviation of a distribution the tail itself helped set.
  - Three exclusion variants are re-estimated per outcome: `tail` drops that outcome's tail dongs, `top_k` drops the `INFLUENCE_TOP_K` (default 10) most influential dongs by `|dfbeta|`, and `union_tail` drops every dong flagged in the tail of any outcome. Each records `sign_flip`, `loses_5pct_significance`, and `gains_5pct_significance`.
  - The script diagnoses; it does not alter the vitality index, trim observations, or change any active contract. The full sample remains the main specification, and this output is what accompanies it.

### 6A.1) Reading Requirement

The first run established that the dependence on individual dongs is not uniform across outcomes, so the diagnostic is not a formality:

| Outcome | Full sample | Tail excluded | Reading |
| --- | --- | --- | --- |
| `vitality_sub_social` | `-2.190` (p < 0.001) | `-1.924` (p < 0.001) | robust in every variant |
| `vitality_sub_economic` | `-0.961` (p = 0.063) | `-0.343` (p = 0.416) | materially attenuated |
| `vitality_index_base` | `-1.421` (p = 0.003) | `-1.139` (p = 0.022) | loses 5% significance only in the union-tail variant (`-0.922`, p = .062) |
| `vitality_sub_stability` | `-0.257` (p = 0.655) | `-0.126` (p = 0.849) | not significant either way |
| `vitality_sub_temporal` | `-1.297` (p = 0.112) | `+0.039` (p = 0.959) | **sign flips in all three variants** |

For `vitality_sub_temporal` a single dong, `반포본동`, accounts for `+1.222` of the coefficient, which is `1.50` baseline standard errors and `94.3%` of the estimate; removing it alone takes the effect from `-1.297` to `-0.074`. For `vitality_sub_economic`, `개포1동` alone accounts for `40.5%`.

Any main-text statement about a `vitality_sub_temporal` effect, and any magnitude claim for `vitality_sub_economic` or `vitality_index_base`, must be reported together with the corresponding row of `influence_robustness_summary.csv`. A directional claim for `vitality_sub_temporal` is not supported by the current evidence and should not be made on the full-sample coefficient alone.

## 6B) Identification Diagnostics

- Objective: Test whether the lagged-exposure TWFE design separates an aging effect from dong-specific time trends.
- Execution condition: Part of `cfg$canonical_pipeline_scripts`, running after [03_run_influence_robustness.R](../../02_Code/04_robustness/03_run_influence_robustness.R).
- Inputs: `panel_main.parquet`
- Outputs:
  - `identification_placebo_lead.csv`
  - `identification_trend_spec.csv`
  - `identification_exposure_persistence.csv`
- Implementation Principles:
  - The design justifies its 4-quarter lag as avoiding simultaneous response. A lag imposes temporal ordering, but ordering is not identification. If the exposure is close to a dong-specific linear trend, a lag, a contemporaneous value, and a lead are all positions on the same line, and any dong-level outcome trend correlated with the aging trend reproduces the coefficient.
  - The diagnostic `lead4` is constructed in-script and never written back to `panel_main`, because the shared-panel contract admits registered lag variables only.
  - The dong-trend specification adds `adm_cd[quarter_index]`, a separate linear trend per dong, which absorbs exactly the differential-trend variation the baseline relies on. It is a demanding test: since the exposure is itself close to a trend, little identifying variation survives and standard errors inflate by a factor of 1.5 to 6.5. A coefficient that vanishes here is not proven absent, but neither is it separable from a trend.
  - Diagnostic only. No specification is changed by this step.

### 6B.1) Reading Requirement

The exposure is close to a deterministic within-dong trend: the median absolute correlation between `age60_resident_share` and `quarter_index` within a dong is `0.993`, exceeding `0.9` in `85.4%` of dongs and `0.95` in `80.7%`, over a median within-dong range of only `5.76` percentage points.

| Outcome | Lag `beta` (p) | **Lead `beta` (p)** | Lag in horse race (p) | Under dong trends (p) |
| --- | --- | --- | --- | --- |
| `vitality_sub_economic` | `-0.961` (.063) | **`-1.042` (.032)** | `-0.212` (.639) | `-2.271` (.070) |
| `vitality_sub_social` | `-2.190` (<.001) | **`-1.553` (.010)** | `-0.672` (.239) | `-0.551` (.342) |
| `vitality_index_base` | `-1.421` (.003) | `-0.886` (.090) | `-1.531` (.064) | `-3.874` (.043) |
| `vitality_sub_temporal` | `-1.297` (.112) | `+1.458` (.349) | `-2.823` (.083) | `-7.059` (.069) |
| `vitality_sub_stability` | `-0.257` (.655) | `-0.109` (.935) | `-2.017` (.250) | `-3.668` (.327) |

Three readings follow, and they constrain what may be claimed.

First, the placebo fails for `vitality_sub_economic` and `vitality_sub_social`: future aging predicts current vitality at least as well as past aging does, and for `vitality_sub_economic` the lag collapses to `-0.212` (p = .639) once both are entered. This is not a collinearity artefact. After two-way demeaning the lag and the lead correlate at `0.674`, a variance inflation factor of `1.8`, so the horse race is informative rather than degenerate.

Second, only `vitality_index_base` survives dong-specific linear trends. `vitality_sub_social`, the one outcome that survives the influence diagnostic of section 6A.1, falls from `-2.190` (p < .001) to `-0.551` (p = .342): that effect was the differential trend.

Third, taken together these mean the 4-quarter lag provides no identifying leverage against a shared dong-level trend. Reported associations remain valid as descriptions of a conditional relationship; a causal reading of the aging coefficient is not supported by this design, and the language of the results must reflect that.

## 6C) Evidence Synthesis

- Objective: Cross-tabulate every diagnostic the project runs against every reported outcome, so that what survives all of them at once is a computed result rather than a recollection of separate audits.
- Execution condition: Part of `cfg$canonical_pipeline_scripts`, running last among the robustness steps, after [04_run_identification_diagnostics.R](../../02_Code/04_robustness/04_run_identification_diagnostics.R) and before QC.
- Inputs: `twfe_main_models.csv`, `spdm_impacts.csv`, `influence_robustness_summary.csv`, `identification_placebo_lead.csv`, `identification_trend_spec.csv`, `exposure_linearity_tests.csv`
- Outputs:
  - `evidence_synthesis_gates.csv`
  - `evidence_synthesis.csv`
  - `evidence_synthesis_matrix.png`
- Implementation Principles:
  - The step exists because each diagnostic, read alone, reports a survivable result: two or three of the five outcomes come through every time. The outcomes that come through are not the same ones each time, so the per-audit pass counts overstate what is jointly defensible. A paper defends one result against every diagnostic simultaneously, which makes the intersection the relevant quantity.
  - It estimates nothing. Every cell traces to a named column of a named upstream table, recorded per gate in `evidence_synthesis_gates.csv`, so a disputed verdict is checked against its source rather than against this script.
  - The modification time of every source table is carried into `evidence_synthesis.csv`, because a synthesis computed over stale diagnostics is worse than none.
  - Nine gates span the five audits. Each carries a `role` tag — `prerequisite`, `stability`, `identification`, `supporting` — which is the judgement this script makes and is written to the output so a reader who weighs the evidence differently can re-tier the same matrix without re-deriving it.
  - A gate that no outcome passes is reported as a `design_level_failure` rather than an outcome-level one, because such a limitation cannot be answered by choosing a different outcome.
  - The influence tolerance (`SYNTHESIS_INFLUENCE_PCT_TOL`, default 50) is a stated convention, not an inferential rule. It exists because a coefficient that moves by more than half of itself when a small set of dongs is dropped is not reportable as a magnitude even when it never crosses a significance threshold. The underlying `pct_change` values travel with the output so the choice can be inspected instead of trusted.
  - Diagnostic only. No specification, contract, or observation is changed by this step.
  - **`model_family_agreement` reads the bootstrap p-value (since 2026-10-04).** The gate compares the 5% verdicts of TWFE m2, clustered by dong, and the SPDM direct effect, so it is only as sound as the SPDM standard error. The script stops when `spdm_impacts.csv` carries model-based impact inference, naming the re-run it needs, and records `impact_se_method` in the gate's `statistic`. A row whose bootstrap failed leaves only that outcome's gate unevaluated.

### 6C.1) Reading Requirement

> **Re-run 2026-10-04.** The table and readings below are from the synthesis re-run on the dong-level bootstrap inference of section 5. Against the 2026-09-12 run, only `model_family_agreement` moved: `vitality_sub_economic` and `vitality_sub_temporal` now pass it and `vitality_index_base` now fails it. No tier changed.

The intersection is empty. No outcome passes all nine gates; the best passes six (`vitality_index_base`), then `vitality_sub_social` with five, `vitality_sub_temporal` with three, and `vitality_sub_economic` and `vitality_sub_stability` with two.

| Outcome | base | ctrl | fam | infl | plac | race | trnd | lin | se2w | Passed | Tier |
| --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- |
| `vitality_index_base` | O | O | **X** | **X** | O | **X** | O | O | O | 6/9 | `descriptive_only` |
| `vitality_sub_social` | O | O | O | O | **X** | **X** | **X** | **X** | O | 5/9 | `conditional_association` |
| `vitality_sub_temporal` | X | X | O | X | O | X | X | O | X | 3/9 | `not_supported` |
| `vitality_sub_economic` | X | X | O | X | X | X | X | O | X | 2/9 | `not_supported` |
| `vitality_sub_stability` | X | X | X | X | O | X | X | O | X | 2/9 | `not_supported` |

Columns, in the order of `GATE_META`: `base` = `baseline_significant`, `ctrl` = `control_set_consistency`, `fam` = `model_family_agreement`, `infl` = `influence_stable`, `plac` = `placebo_lead_null`, `race` = `lag_beats_lead`, `trnd` = `dong_trend_survival`, `lin` = `linearity_not_rejected`, `se2w` = `se_twoway_significant`.

Four readings follow, and they govern the language of the results.

First, `lag_beats_lead` fails for every outcome, which makes it a property of the design rather than of any outcome. Entered alongside the 4-quarter lead, the 4-quarter lag is not significant for a single outcome (p = .639, .206, .083, .250, .061). This is not a collinearity artefact: after two-way demeaning the two correlate at `0.674`, a variance inflation factor of `1.8`. The lag is separable from the lead and still does not win. No choice of outcome answers this, and no outcome may carry a causal directional claim.

Second, the tier names a *kind* of claim, not a quality ranking, because the failures are not commensurable. `vitality_index_base` passes more gates but fails `influence_stable`: dropping the nine union-tail dongs, `2.1%` of the sample, takes it from `-1.421` (p = .003) to `-0.922` (p = .062). Its magnitude is therefore not reportable, and it is the only outcome that survives dong-specific trends. `vitality_sub_social` has a stable magnitude but fails all three identification gates. These license different sentences, and neither is the stronger result in a single ordering.

Third, `n_gates_passed` is not comparable across outcomes, because some gates are conditional on the baseline. `vitality_sub_temporal` and `vitality_sub_stability` each pass `placebo_lead_null`, but a placebo test has nothing to falsify when the baseline effect is itself null; and `vitality_sub_economic` and `vitality_sub_temporal` pass `model_family_agreement` only because TWFE and SPDM agree that neither effect is significant. Those are vacuous passes, and the 2/9 and 3/9 rows should be read as "no reportable effect" rather than as a graded score.

Fourth, `model_family_agreement` fails for two outcomes, for different reasons. For `vitality_sub_stability` the sign differs, `-0.257` (p = .655) for TWFE against `+0.570` (p = .439) for the SPDM direct effect, neither significant; the SPDM figure moves positive only once `W X` enters (section 5G.1). For `vitality_index_base` the verdict differs: TWFE `-1.421` (p = .003) against SPDM `-0.995` (p = .070). Until 2026-10-04 the gate failed for three outcomes and the disagreement ran one way, SPDM calling all five direct effects significant against TWFE's two; that was the model-based SPDM standard error, `0.137` against `0.515` for TWFE clustered on dong for `vitality_sub_economic`, and the bootstrap gives `0.637`. On the bootstrap the two models' standard errors are of the same order and their verdicts differ only where an estimate sits near the threshold.

Because these gates were applied as forty-five outcome-by-gate tests, the reporting should say so. The failures at issue are not marginal — a lack-of-fit p of `1.1e-7`, sign reversals under a 2% sample change — so multiplicity does not explain them, but the count belongs in the text.

## 6D) Published Test Inventory

- Objective: Count every exposure-side hypothesis test the project publishes and report how many survive a multiplicity adjustment, so the size of the search is a number in the record rather than an impression.
- Execution condition: Run [04_build_test_inventory.R](../../02_Code/06_qc/04_build_test_inventory.R) directly. It reads published tables only and estimates nothing.
- Inputs: every `03_Output/01_Tables/(twfe|spdm)_*_{models,impacts,path_effects}.csv`
- Outputs:
  - `model_test_inventory.csv`
  - `model_test_inventory_adjusted.csv`
- Implementation Principles:
  - Control terms and spatial nuisance parameters are excluded; counting them would inflate the search with quantities nobody claims anything about.
  - Benjamini-Hochberg is applied both within each table and across the whole published surface. The families share a panel, an exposure and a control contract, so this is a conservative summary of search size rather than an exact error rate, and it does not replace the unadjusted p-values the tables carry.
  - The inventory separates the main-text surface from the appendix, because the two carry very different weight.

### 6D.1) Reading Requirement

| Scope | Tables | Tests | Significant, unadjusted | Significant under BH | Expected false positives at 0.05 |
| --- | ---: | ---: | ---: | ---: | ---: |
| All published | 21 | 405 | 250 | 235 | 20.3 |
| Main text | 2 | 15 | 7 | 7 | 0.8 |
| Appendix | 19 | 390 | 243 | 228 | 19.5 |

Re-run 2026-10-04, after the main SPDM and the component sidecar moved to the dong-level bootstrap. The main-text count fell from 11 to 7 because the SPDM direct effects went from 5 significant to 1.

Two readings, and the second is the more useful one.

The search is large: the main text rests on 15 tests while the published tables carry 405, spread across appendix families that are searches by construction — age-mix, sector-share, vitality components, COVID interactions, spatial model families, W variants. Any appendix result quoted in support of a claim is selected from that surface, and the reporting should say so.

The adjustment nevertheless changes very little: 250 unadjusted rejections become 235 under BH across all 405 tests, and the main-text count is unchanged at 7. Multiplicity is not what threatens these results. Serial dependence is: about 280 of the 390 appendix tests come from SPDM sidecar tables that still carry model-based ML standard errors, which understate uncertainty by a factor of two to five on this panel (section 5), so the appendix count is an upper bound and those rejections are not evidence on their own. The other honest concerns about these families remain the ones in sections 3C and 5A.1 — timing, collinearity, and an invalid resample.

## 7) GTWR Main Optional Sidecar

### 7.0) Authoritative Parameter Contract

This table is the single source of truth for GTWR specification parameters. Every value is set in [config.R](../../02_Code/00_setup/config.R) and overridable by the named environment variable. All are required reporting items wherever GTWR results are presented.

| Parameter | Env var | Contracted default | `config.R` field |
| --- | --- | --- | --- |
| Bandwidth | `GTWR_ST_BW` | `60` | `cfg$gtwr_st_bw` |
| Adaptive | `GTWR_ADAPTIVE` | `true` (60 = 60 spatiotemporal neighbours, not a metric radius) | `cfg$gtwr_adaptive` |
| Kernel | `GTWR_KERNEL` | `bisquare` | `cfg$gtwr_kernel` |
| Spatiotemporal mix | `GTWR_LAMDA` | `0.5` (dimensionless; see 7.2) | `cfg$gtwr_lamda` |
| Angle parameter | `GTWR_KSI` | `0` | `cfg$gtwr_ksi` |
| Control set | `GTWR_CONTROL_SET` | `lean` | `cfg$gtwr_control_set` |
| Local VIF warn threshold | `GTWR_LOCAL_VIF_WARN_THRESHOLD` | `10` | `cfg$gtwr_local_vif_warn_threshold` |

### 7.1) Status of the Published Outputs

> **Both bundles were re-estimated on 2026-09-13 and both now match this contract.** `lean` took 10h52m and `extended` 10h46m, run back to back because each forks five workers at about 3.45 GB and the machine holds 19 GB. The table below is kept as the record of what the gap was before that run; every `extended` cell that reads as a deviation was closed on 2026-09-13 and the current state is in 7.1b.

| | Contracted (7.0) | `lean` (2026-09-06) | `extended` (2026-06-27) |
| --- | --- | --- | --- |
| `st_bw` | `60` | `60` | **`90`** (run-time override; see [decision_log.md](../03_Log/decision_log.md), 2026-09-04 entry) |
| `lamda` | `0.5` dimensionless | `0.5`, stamped `dimensionless_span_normalized` | **`0.05` raw-unit**, unstamped (retired convention; roughly 76:1 in favour of space) |
| Time distance | symmetric `abs(t_i - t_j)` | symmetric | legacy `GWmodel::ti.distv()` string comparison |
| Collinearity schema | `local_vif_max`, `local_cn_centered`, `local_cn_gtwr` | all three | `local_cn_gtwr` only |
| Local inference | `estimate_se`, `estimate_t`, `estimate_p`, BH-FDR flag | present (`local_inference_status = gwmodel_sdf`) | **absent** |

#### 7.1b) Both control sets after the 2026-09-13 re-estimation

`extended` now carries the contracted `st_bw = 60`, `lamda = 0.5` stamped `dimensionless_span_normalized`, the symmetric time distance, the full three-measure collinearity schema and local inference, so the three deviations this section previously recorded for it are closed and no `extended` statement is blocked on a pending rerun any more.

**The multicollinearity concern that motivated the `lean` default is real in direction but does not breach the contract.** The `extended` control set roughly doubles the median local VIF and pushes the maximum close to the threshold, without any dong crossing it:

| | `lean` | `extended` | contracted threshold |
| --- | ---: | ---: | ---: |
| `local_vif_max` median | `1.376` | `2.485` | — |
| `local_vif_max` maximum | `5.918` | `9.181` | `10` |
| share of dongs above the threshold | `0.00%` | `0.00%` | — |
| `local_cn_centered` maximum | `5.94` | `8.71` | reported without a threshold |
| `local_cn_gtwr` maximum | `301.6` | `363.0` | reported without a threshold |

`collinearity_warn_share` is therefore `0` for all five outcomes in **both** control sets. The `0.998`-`1.0` warn share the old `extended` bundle reported was the retired uncentered flag and is now superseded by a VIF result rather than merely cautioned against.

**The control set changes the local surface materially, which is a reason to report which one produced a figure.** Adding the transit composite and the workplace worker population raises the mean local coefficient for `vitality_sub_economic` from `1.297` to `2.158` and for `vitality_sub_social` from `0.199` to `0.704`, lowers the dispersion for those two and for the composite (`sd_beta` `3.830` to `2.973`, `3.703` to `2.923`, `2.464` to `1.834`), and raises the FDR-significant share for `vitality_sub_economic` from `23.8%` to `38.1%` and for `vitality_sub_stability` from `38.8%` to `49.2%`. `vitality_sub_temporal` is unmoved and near zero in both (`0.168` against `-0.006`, significant in `9.2%` and `9.4%` of dongs). The two sets are not interchangeable, and `lean` remains the reported default per [research_plan.md section 6.3](../01_Design/research_plan.md); whether the VIF evidence above still justifies that preference is a design question this table does not settle.

What the `lean` rerun settles, measured on its own outputs:

- `collinearity_warn_share` is `0` for all five outcomes. The median `local_vif_max_latest` is `1.435` and the maximum `2.786` against a warning threshold of `10`; the maximum weighted centered condition number is `3.40` and the maximum uncentered `330.68`. The near-`1.0` warn share that `extended` still reports (`0.998`-`1.0`) was written under the retired flag, which keyed off the **uncentered** condition number, and is not evidence of pervasive collinearity under the current criterion.
- `gtwr_local_coefficients_lean.csv` carries all three collinearity measures directly, so 7Y is no longer the source for them on `lean`. For `extended` the two predictor-space measures are available **nowhere**: its local coefficient table predates the schema and 7Y has never been run for that control set, so `gtwr_collin_diag_backfill_extended.csv` does not exist. 7Y can produce it without refitting.
- **Local standard errors are present for `lean` and absent for `extended`.** All 52,985 rows of `gtwr_local_beta_panel_lean.csv` carry `estimate_se`, `estimate_t` and `estimate_p`, and `gtwr_local_coefficients_lean.csv` carries the latest-quarter values with `latest_estimate_p_fdr` and `latest_significant_fdr`. `sd_beta` and `share_positive` are therefore no longer the only description of the `lean` local surface, subject to the standing caution of 7.2 that these errors are a screen rather than exact inference. For `extended`, no statement of the form "the effect is positive in region X" is supported by the published tables.

#### 7.1a) The 2026-09-13 `lean` re-estimation on the rebuilt panel

`lean` was re-estimated on the panel corrected by the 2026-09-12 living-population fix, taking 10h52m at the section 7.0 contract, and the result separates cleanly into what the fix touched and what it did not.

| Outcome | dongs | FDR-significant | share positive among them | changed by the fix |
| --- | ---: | ---: | ---: | --- |
| `vitality_sub_temporal` | 425 | `9.2%` (was `9.2%`) | `0.436` (was `0.436`) | no |
| `vitality_sub_economic` | 425 | `23.8%` (was `23.8%`) | `0.752` (was `0.752`) | no |
| `vitality_sub_stability` | 425 | `38.8%` (was `38.8%`) | `0.933` (was `0.933`) | no |
| `vitality_index_base` | 424 | **`34.0%`** (was `21.6%`) | `0.840` (was `0.870`) | yes |
| `vitality_sub_social` | 424 | **`37.7%`** (was `24.9%`) | `0.594` (was `0.557`) | yes |

The three outcomes the fix does not touch reproduce the 2026-09-06 run exactly, to the significant share and to three decimals on the share positive, across two independent eleven-hour runs on different dates with unrelated code changes in between. That is the only reproducibility evidence this layer has, and it is strong.

The two outcomes the fix does touch gain about half again in the share of dongs separable from zero. The direction is the expected one: the seven fabricated zeros carried an outcome roughly eight log points below the truth, which inflated local residual variance and widened local standard errors throughout their neighbourhoods, so removing them sharpens the surface rather than merely shifting it.

**The artifact that occupied both tails of the social surface is gone.** Before the fix all seven dongs were FDR-significant, `수유2동` held the Seoul minimum at `-9.096` and `항동` the Seoul maximum at `+11.706` (`p_fdr` = 2.3e-19). After it, `항동` leaves the sample entirely because its social sub-index is now `NA` (`n` = 424), and the six Gangbuk-gu dongs sit at the 79th to 87th percentile with local betas of `+3.6` to `+4.7`, four of the six FDR-significant against a Seoul-wide rate of `37.7%`. Their sign reversed, which is what a fabricated floor on the outcome would produce. Neither the Seoul minimum (`-8.627`) nor the maximum (`+9.738`) is now held by one of them. Any H3 reading of the social surface published before 2026-09-13 rests on that artifact.

Still outstanding:

- The `extended` main bundle, and with it every `extended` sidecar derived from it.
- ~~The 7E, 7F and 7G bundles.~~ **Closed 2026-09-29.** Both the 7F bandwidth-sensitivity and 7G lamda-sensitivity tables are now re-run and baselined on the contracted `60` / `0.5` surface for **both** control sets, with their numbers in 7H.1 and 7G.1; every baseline row self-checks at correlation `1.0000` with a `0.0%` sign-flip share. The 7E full-panel bandwidth selection remains unavailable and is intractable at this panel size (7E.1a); the anchor-quarter variant is published. [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R) and [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R) halt rather than baseline on a main surface fitted off contract (7F), so each run produces a table that agrees with 7.0 by construction.

QC checks `G02` and `G03` run whenever the GTWR outputs exist, not only under the opt-in flag: GTWR is optional to produce, but not optional to be correct once published. `G03` reports the full diagnostic schema for `lean`; the pending-rerun path remains for `extended`, whose local coefficient table carries `local_cn_gtwr_latest` and `collinearity_warn_flag` alone.

### 7.2) Specification

- Objective: Explain resident-only local heterogeneity.
- Inputs: `panel_main.parquet`, `2020 Seoul administrative boundary`
- Execution condition: Run [03_run_gtwr_main.R](../../02_Code/03_models/03_run_gtwr_main.R) directly.
- Outputs:
  - `gtwr_main_models_<control_set>.csv`
  - `gtwr_local_beta_panel_<control_set>.csv`
  - `gtwr_local_coefficients_<control_set>.csv`
  - `gtwr_controls_used_<control_set>.csv`
  - `gtwr_main_frozen_spec_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/main/*.rds`
- Downstream tables, **not written by this script**: `gtwr_latest_summary_table_<control_set>.csv`, `gtwr_latest_rankings_table_<control_set>.csv`, `gtwr_delta_summary_table_<control_set>.csv`, and `gtwr_delta_rankings_table_<control_set>.csv` are derived by [01_make_tables_figures.R](../../02_Code/05_reporting/01_make_tables_figures.R) from the outputs above, behind the optional-appendix gate of section 8.1. They are absent from `03_Output/01_Tables/` whenever that gate is off, which is the default; their absence is not a GTWR failure.
- Implementation Principles:
  - Executed based on a quarterly sample.
  - `GTWR_CONTROL_SET=lean` is used as the default control specification.
  - The lean control pool consists solely of `lag4_ln_resident_pop` and `lag4_ln_land_price_adjusted`.
  - `GTWR_CONTROL_SET=extended` adds `lag4_transit_accessibility` and `lag4_ln_workplace_worker_pop` to the lean controls.
  - In GTWR extended, the number of bus stops and subway stations are not input as separate controls but as a `lag4_transit_accessibility` composite, and workplace population size is controlled via `lag4_ln_workplace_worker_pop`.
  - Records three local collinearity diagnostics based on GTWR spatiotemporal weights: `local_vif_max` (largest weighted variance inflation factor), `local_cn_centered` (condition number of the weighted centered design), and `local_cn_gtwr` (uncentered condition number).
  - `local_cn_gtwr` applies the local_CN calculation convention of `GWmodel::gwr.collin.diagno()` adapted to GTWR's `gw.weight` spatiotemporal weights. Following Belsley (1984), it is computed without centering and therefore conditions on the local intercept as well as the predictors; it is reported for comparability with the GWR literature.
  - The collinearity warning flag is raised when `local_vif_max >= GTWR_LOCAL_VIF_WARN_THRESHOLD` (default 10). `local_cn_centered` and `local_cn_gtwr` carry no threshold, because Belsley's cut-off of 30 is defined for the uncentered construction and no comparable convention exists for a centered one.
  - The spatiotemporal distance matrix is built by `build_gtwr_st_dmat()` with the symmetric temporal distance `|t_i - t_j|` and passed to `bw.gtwr()` and `gtwr()` as `st.dMat`, bypassing `GWmodel::st.dist()`/`ti.distm()` whose string time comparison mislabels past quarters as future for integer period ids.
  - `lamda` is dimensionless: spatial and temporal distances are divided by their own observed spans before combining, so `0.5` weights space and time equally and the default is `GTWR_LAMDA=0.5`. The previous raw-unit `lamda=0.05` corresponds to roughly `0.987` under this convention; values from the two conventions are not comparable.
  - The weighting kernel is `GTWR_KERNEL=bisquare` by default, applied to the combined spatiotemporal distance. `gaussian`, `exponential`, `tricube`, and `boxcar` are accepted alternatives; any other value falls back to `bisquare`. The kernel is a required reporting item for the specification and must be stated wherever GTWR results are presented.
  - `GTWR_KSI` is the angle parameter of the Huang et al. (2010) spatiotemporal distance `lamda * d_S + (1 - lamda) * d_T + 2 * sqrt(lamda * (1 - lamda) * d_S * d_T) * cos(ksi)` and defaults to `0`, which makes the interaction term enter at full weight. It is held at the default in every specification that is actually estimated. [05_run_gtwr_experiment.R](../../02_Code/80_optional/gtwr/05_run_gtwr_experiment.R) records varying values of it but estimates nothing (section 7X), so the only working sensitivity on the angle is the geometric sweep of section 7Z, which reports what the kernel averages over at each angle without refitting.
  - The default bandwidth is uniformly fixed at `GTWR_ST_BW=60`.
  - Under `GTWR_ADAPTIVE=true` (the default), a bandwidth of 60 means 60 spatiotemporal neighbors around each estimation point rather than a fixed metric radius.
  - [03_run_gtwr_main.R](../../02_Code/03_models/03_run_gtwr_main.R) does not run `bw.gtwr()` even if `GTWR_BANDWIDTH_STRATEGY` is not fixed.
  - `bw.gtwr()` full-panel/anchor-quarter search, fixed bandwidth grid sensitivity, and lambda grid sensitivity are only executed in [06_select_gtwr_bandwidth.R](../../02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R), [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R), and [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R), respectively.
  - The default fixed bandwidth grid for [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R) is `30, 60, 90, 120, 180`, with a baseline of `GTWR_ST_BW=60`.
  - Local inference is extracted alongside the coefficient. `GWmodel::gtwr()` returns `<var>_SE` and `<var>_TV` per estimation point; `extract_gtwr_local_inference()` reads both and derives a two-sided p-value on GWmodel's own effective residual degrees of freedom, `n - 2*tr(S) + tr(S'S)`. The beta panel carries `estimate_se`, `estimate_t`, `estimate_p`, and `estimate_inference_source`; the local coefficient table carries the latest-quarter values plus `latest_estimate_p_fdr` and `latest_significant_fdr`.
  - These local standard errors are conditional on the bandwidth, treat it as known, and come from overlapping windows, so neighbouring t-values are strongly dependent and do not carry exact nominal coverage (Wheeler and Tiefelsdorf 2005; Paez, Farber and Wheeler 2011). They are the weakest defensible screen, not exact inference. Benjamini-Hochberg is therefore applied across dongs within a specification, matching the ESDA convention for local indicators, and the summary counts the adjusted flag rather than the raw p-value.
  - `share_positive` is reported beside `share_positive_among_significant`, because the local estimates that are not separable from zero split near 50/50 by construction and would otherwise read as sign heterogeneity.
  - The main summary and local coefficient tables save the latest-quarter local beta with `estimate_type=latest`.
  - Latest-quarter coefficient coverage is recorded via `latest_missing_n` and `latest_coverage_share`.
  - Earliest-to-latest changes are derived solely as `gtwr_delta_*` auxiliary reporting tables.
  - Spec-specific caches by outcome-exposure are saved first, and the final raw GTWR bundle and control traces are generated by aggregating the entire cache.
  - `GTWR_PARALLEL_SPECS` limits the number of parallel workers, and completed spec caches are reused when `GTWR_RESUME_SPECS=TRUE`.
  - Downstream delta tables for reporting are derived only when horizon-aligned raw outputs exist.

## 7A) GTWR Floating-Only Appendix

- Manual quarterly GTWR appendix sidecar
- Execution condition: Run [01_run_gtwr_floating_only.R](../../02_Code/80_optional/gtwr/01_run_gtwr_floating_only.R) directly.
- Outputs:
  - `gtwr_floating_models_<control_set>.csv`
  - `gtwr_floating_local_beta_panel_<control_set>.csv`
  - `gtwr_floating_local_coefficients_<control_set>.csv`
  - `gtwr_floating_controls_used_<control_set>.csv`
  - `gtwr_floating_frozen_spec_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/floating/*.rds`
- Implementation Principles:
  - Actual estimation is performed using `GWmodel::gtwr()`. The realized `focal_var` is `lag2_age60_floating_share`, the registered 2-quarter channel mediator, not the contemporaneous `age60_floating_share` this line previously named.
  - The control pool follows the same `GTWR_CONTROL_SET` contract as the main GTWR.
  - Because it is excluded from the default `run_all.R` and required test plans, the absence of raw output is not considered a failure.

### 7A.1) Two reading requirements (added 2026-09-18)

**This is not a minor variant of the main surface. It reverses the sign for three of five outcomes.** Measured on the 2026-09-18 `lean` run (10h48m, exit 0, `collinearity_warn_share` 0 throughout), the mean local coefficient under the floating exposure is `-3.555` for `vitality_sub_economic` against `+1.297` under the resident exposure, `-5.575` against `+0.199` for `vitality_sub_social`, and `-1.289` against `+1.395` for `vitality_index_base`; only `vitality_sub_temporal` and `vitality_sub_stability` agree in sign. The floating surface is also the better identified one for two outcomes, at `|mean| / sd` of `1.029` for `vitality_sub_social` and `1.054` for `vitality_sub_stability` against `0.054` and `0.844` under the resident exposure. A GTWR statement therefore has to name its exposure; the two families do not describe the same local relationship.

**`vitality_sub_social` under this exposure shares a source with its own outcome and must not be read as an independent result.** `lag2_age60_floating_share` is `age60_floating_pop / floating_pop`, and `vitality_sub_social` is the mean of pooled-z `ln_floating_pop` and `ln_external_inflow_pop`, so the exposure's denominator is the source of half the outcome. This is the same overlap for which [section 5A](#5a-spdm-optional-channel-path-sidecar) excludes `vitality_sub_social` as a standalone channel-path outcome, and it is unflagged here even though this is where it produces the largest effect in the bundle. Measured on the active window the exposure correlates `-0.568` with `ln_external_inflow_pop`, `-0.155` with `ln_floating_pop` and `-0.438` with the sub-index itself, against `-0.270` for the resident exposure. The correlation is not a mechanical identity, since the exposure is a composition and the outcome a log level, but the shared source is real and the `-5.575` local mean must carry the caveat wherever it is reported.

## 7B) GTWR Age-Band Appendix

- Manual quarterly GTWR appendix sidecar
- Execution condition: Run [02_run_gtwr_age_band.R](../../02_Code/80_optional/gtwr/02_run_gtwr_age_band.R) directly.
- Outputs:
  - `gtwr_age_band_models_<control_set>.csv`
  - `gtwr_age_band_local_beta_panel_<control_set>.csv`
  - `gtwr_age_band_local_coefficients_<control_set>.csv`
  - `gtwr_age_band_controls_used_<control_set>.csv`
  - `gtwr_age_band_frozen_spec_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/age_band/*.rds`
- Implementation Principles:
  - Actual estimation is performed using `GWmodel::gtwr()` on age20~age50 exposure families by resident/floating domains and main outcomes.
  - The output saves `domain`, `age_band`, and `same_domain_total_control` together.
  - The control pool follows the same `GTWR_CONTROL_SET` contract as the main GTWR.
  - Downstream delta summaries/rankings are derived only when raw appendix outputs exist.

## 7C) GTWR Sector-Share Appendix

- Manual quarterly GTWR appendix sidecar
- Execution condition: Run [03_run_gtwr_sector_share.R](../../02_Code/80_optional/gtwr/03_run_gtwr_sector_share.R) directly.
- Outputs:
  - `gtwr_sector_share_models_<control_set>.csv`
  - `gtwr_sector_share_local_beta_panel_<control_set>.csv`
  - `gtwr_sector_share_local_coefficients_<control_set>.csv`
  - `gtwr_sector_share_controls_used_<control_set>.csv`
  - `gtwr_sector_share_frozen_spec_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/sector_share/*.rds`
- Implementation Principles:
  - Actual estimation is performed using `GWmodel::gtwr()` on resident-only/floating-only exposure families against sector-share outcomes.
  - The output saves `exposure_family` and `same_domain_total_control` together.
  - The control pool follows the same `GTWR_CONTROL_SET` contract as the main GTWR.


### 7C.1) The sidecar published empty tables on every run to 2026-09-13

**It never invoked `GWmodel::gtwr()`, despite [research_plan.md section 7.4](../01_Design/research_plan.md) stating that it does.** The script read the `"gtwr"` panel view with the six sector-share outcomes added as `extra_cols`, but its exposure registry is built on the *contemporaneous* `age60_resident_share` and `age60_floating_share`, and its resident family needs `ln_resident_pop` as the same-domain total control. The view projects the lagged forms the main GTWR uses (`lag4_age60_resident_share`, `lag2_age60_floating_share`) and none of those three, so the registry filtered to zero rows, the script took its skip branch, and it wrote five empty tables and one line to `model_run_log.md` in about nine seconds with exit 0.

Two things made this hard to notice. The empty summary table carries no `status` and no `message` column at all, unlike the deferred sidecars of 7D and 7X which write explicit `not_estimated` rows, so the output offered no reason for its own emptiness. And the control-selection line is `intersect(unique(c(required_controls, optional_controls)), names(panel))`, which silently drops a required control that is absent from the projection rather than failing on it.

**The sidecar was broken twice over, and the first fix exposed the second fault.** Adding the two exposures to `extra_cols` resolved the registry, and the run then halted on its own guard: `assert_gtwr_control_vector_current()` refused `ln_resident_pop`, the contemporaneous same-domain total control the registry declared, because the current GTWR contract carries `lag4_ln_resident_pop`. That contract violation had been present all along and was invisible for the same reason the registry was empty — the `intersect(..., names(panel))` in the control-selection line dropped a required control that the projection did not carry, so the guard never received it. Widening the projection handed the guard the stale name and it halted correctly. The registry entry is now `lag4_ln_resident_pop`, which the `"gtwr"` view already projects, so only the two exposures need requesting as extras.

With both faults fixed the registry resolves to 2 families against 6 outcomes, so the sidecar fits **12 specifications** where the main GTWR fits 5, and should be budgeted at roughly twice the main's wall time per control set. Any statement about sector-share local heterogeneity made before 2026-10-02 rests on tables that were either empty or never written.

## 7D) GWR Delta Appendix

- Execution condition: Run [04_run_gwr_delta.R](../../02_Code/80_optional/gtwr/04_run_gwr_delta.R) directly.
- Manual quarterly appendix sidecar
- Outputs:
  - `gwr_delta_main_models.csv`
  - `gwr_delta_local_coefficients.csv`
  - `gwr_delta_floating_models.csv`
  - `gwr_delta_floating_local_coefficients.csv`
  - `gwr_delta_controls_used.csv`
- **This sidecar estimates nothing. It is a metadata-only emitter by construction, not a run that failed or is waiting on a flag.** Verified 2026-09-12: the script contains no call to `GWmodel::gwr.basic()` or any other fitting function; the single textual occurrence of that name is a string literal in a `method` column recording what the estimator *would* be. Both of its branches write `status = "not_estimated"`, one with `quarterly_gwr_delta_deferred: insufficient active-horizon support for early-late local comparison` and the other with `quarterly_gwr_delta_deferred: appendix local delta estimation is not activated; active-horizon metadata preserved`, and there is no environment variable that activates estimation. Consequences a reader should expect rather than discover: `gwr_delta_local_coefficients.csv` and `gwr_delta_floating_local_coefficients.csv` are always **0 rows**, `gwr_delta_main_models.csv` and `gwr_delta_floating_models.csv` carry five metadata rows each with `bandwidth`, `mean_beta`, `sd_beta` and `share_positive` all `NA`, and the run takes about 11 seconds. The reporting layer propagates this honestly: `gwr_delta_summary_table.csv` carries the `not_estimated` rows with the deferral message and `gwr_delta_rankings_table.csv` is empty, so nothing downstream fabricates a local surface. No GWR-delta claim of any kind is supported by the published tables.
- Implementation Principles:
  - Delta window metadata is derived from the active analysis horizon, `2019Q4~2025Q4`.
  - The early window is recorded as the first 3 calendar years of the active horizon (`2019Q4~2021Q4`), and the late window as the last 3 calendar years (`2023Q1~2025Q4`).
  - The raw output schema logs `sample_min_yq`, `sample_max_yq`, `early_*_yq`, `late_*_yq`, `early_n_quarter`, and `late_n_quarter`, while `early_*_year`, `late_*_year`, and `window_n_year` are retained for legacy compatibility.

## 7E) GTWR Bandwidth Selection Diagnostic

- Manual quarterly diagnostic
- Execution condition: `GTWR_BANDWIDTH_STRATEGY=full_panel_bw_gtwr` or `anchor_quarter_bw_gtwr`
- Outputs:
  - `gtwr_bandwidth_selection_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_bandwidth_cache/<control_set>/main/*.rds`
- Implementation Principles:
  - Only the `bw.gtwr()` search results for resident-only main GTWR specs are saved.
  - The selection results are not automatically applied to the main GTWR; they must be explicitly applied via `GTWR_ST_BW` if needed.

### 7E.1) Status of the Published Selection and Sensitivity Bundle

> **The published outputs of 7E, 7F and 7G are on the retired raw-unit `lamda` convention and cannot be read against the current contract.**

| Output | Run | Recorded `lamda` | Convention |
| --- | --- | --- | --- |
| `gtwr_bandwidth_selection_<cs>.csv` | 2026-06-16 | `0.05` | **raw-unit (retired)** |
| `gtwr_bandwidth_sensitivity_<cs>.csv` | 2026-06-23 | `0.05`, baseline `st_bw` `90` | **raw-unit (retired)** |
| `gtwr_lamda_sensitivity_<cs>.csv` | 2026-06-23 | `0.025, 0.05, 0.1, 0.2` (baseline `0.05`) | **raw-unit (retired)** |
| `gtwr_lamda_bw_cv_search_<cs>.csv` | 2026-09-02 | `0.1` to `0.995` | dimensionless (current) |

The consequence is specific to 7G. The lamda sensitivity is the project's evidence that the spatiotemporal mix does not drive the local surface, and its grid of `0.025` to `0.2` spans roughly 76:1 to 2000:1 in favour of space under the convention it was run on. The grid never varied the mix in any meaningful sense, in either convention's terms, so **there is currently no evidence that the local coefficients are insensitive to `lamda`**. Runs from 2026-09-04 stamp `lamda_convention` into `gtwr_main_frozen_spec_<cs>.csv`; an output with no stamp is on the retired convention.


### 7E.1a) `full_panel_bw_gtwr` is intractable on this panel (measured 2026-09-18)

**Do not queue the full-panel strategy behind anything.** A `lean` run was started on 2026-09-13 21:57 and killed on 2026-09-18 00:22 after **98.4 hours** on five workers at 99.9% CPU each, having written no output and offering no progress signal beyond `GWmodel`'s own "it will take a few minutes" notice. It was not deadlocked; it was still computing.

The cost is structural rather than incidental. `bw.gtwr()` runs a golden-section search over bandwidths, and each candidate requires a leave-one-out cross-validation across every point of the spatiotemporal panel. At 425 dongs by 25 quarters that is 10,625 points, so one candidate costs on the order of 10,625² ≈ 113 million distance-and-weight evaluations, repeated for as many candidates as the optimiser needs. The `anchor_quarter_bw_gtwr` strategy, which evaluates one 425-point cross-section instead, completes in **30 seconds** on the same machine.

Two practical rules follow. Use `anchor_quarter_bw_gtwr` for the routine diagnostic. If a full-panel figure is genuinely wanted, run it alone, last, with nothing queued behind it, and expect days rather than hours — the 98 hours above did not finish and is a lower bound, not an estimate.

## 7F) GTWR Bandwidth Sensitivity Diagnostic

- Manual quarterly diagnostic
- Execution condition: Run [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R) directly.
- Outputs:
  - `gtwr_bandwidth_sensitivity_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_bandwidth_sensitivity_cache/<control_set>/main/*.rds`
- Implementation Principles:
  - Requires baseline `gtwr_main_models_<control_set>.csv` and `gtwr_local_coefficients_<control_set>.csv` first.
  - The contracted bandwidth is not re-estimated: its row is reused from the baseline outputs, and every other bandwidth is scored against that surface. `assert_gtwr_sensitivity_baseline_contract()` therefore reads the realized `st_bw` from `gtwr_main_models_<control_set>.csv` and the realized `lamda`, `lamda_convention`, `kernel` and `ksi` from `gtwr_main_frozen_spec_<control_set>.csv`, and **halts** unless they match section 7.0. A frozen spec with no `lamda_convention` stamp is on the retired raw-unit convention and is refused. Without the gate a baseline fitted at other parameters would be republished under the contracted ones, which is how the published bundle came to carry `st_bw = 90` against a documented `60` (7.1).
  - The fixed bandwidth grid is re-estimated by spec, and the sensitivity regarding correlation, absolute difference, sign flip, and local collinearity diagnostics relative to the baseline latest-quarter beta is saved.

## 7G) GTWR Lamda Sensitivity Diagnostic

- Manual quarterly diagnostic
- Execution condition: Run [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R) directly.
- Outputs:
  - `gtwr_lamda_sensitivity_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_lamda_sensitivity_cache/<control_set>/main/*.rds`
- Implementation Principles:
  - Requires baseline `gtwr_main_models_<control_set>.csv` and `gtwr_local_coefficients_<control_set>.csv` first.
  - The contracted lamda is not re-estimated: its row is reused from the baseline outputs, and every other lamda is scored against that surface at the contracted bandwidth. The same `assert_gtwr_sensitivity_baseline_contract()` gate described in 7F applies here and halts on any mismatch with section 7.0, including a frozen spec carrying no `lamda_convention` stamp.
  - The lamda grid is re-estimated by spec using the fixed main bandwidth, and sensitivity regarding correlation, absolute difference, sign flip, and local collinearity diagnostics relative to the baseline latest-quarter beta is saved.
  - The cache signature of both sensitivity sidecars carries `lamda_convention`, so a payload written under the retired raw-unit convention can never be reused for a dimensionless value that happens to share its number.

### 7G.1) The response is strongly asymmetric (measured 2026-09-25, `lean`)

The first lamda sensitivity table baselined on the contracted surface (44.7 hours, 25 rows, all `success`, baseline `lamda = 0.5` self-checking at `beta_corr = 1.0000`) answers a question the earlier documentation could only flag as open. The surface is **nearly invariant below the contracted value and changes sharply above it**:

| `lamda` | `beta_corr` with the reported surface | dongs flipping sign |
| ---: | ---: | ---: |
| `0.10` | `0.971` - `0.981` | `2.1%` - `8.0%` |
| `0.25` | `0.977` - `0.987` | `1.9%` - `6.8%` |
| `0.50` | baseline | baseline |
| `0.75` | `0.907` - `0.944` | `6.6%` - `13.6%` |
| `0.90` | **`0.566` - `0.691`** | **`20.0%` - `28.2%`** |

Ranges are across the five outcomes. Shifting weight toward time barely moves the local coefficients; shifting it toward space moves them a great deal, and by `0.90` the correlation with the reported surface has fallen below `0.7` with a quarter of dongs reversing sign.

**Two consequences follow, and both are uncomfortable.** First, the cross-validated optimum sits in the sensitive region: 7H.1 reports CV-preferred values of `0.75` to `0.9867` for the five outcomes, so the prediction-optimal specification and the reported one are substantially different local surfaces, not neighbouring ones. Second, the retired raw-unit `lamda = 0.05` corresponds to roughly `0.987` dimensionless, which is above the top of this grid; every GTWR result published before the 2026-09 re-estimation therefore sat in that same sensitive region, and at `0.90` the surface already differs from the contracted one by `0.57`-`0.69` correlation. The old and new bundles are not two readings of one surface.

Reporting `lamda` alongside any local coefficient is therefore not a formality. It is the difference between surfaces that correlate at `0.98` and surfaces that correlate at `0.57`.

**`extended` reproduces the asymmetry and is slightly worse in the sensitive region** (re-run 2026-09-29, 45.0 hours, 25 rows, all `success`): `0.972`-`0.988` correlation with `0.7%`-`5.2%` flips at `0.10`, `0.978`-`0.991` with `0.7%`-`4.2%` at `0.25`, `0.897`-`0.957` with `5.2%`-`13.2%` at `0.75`, and `0.507`-`0.766` with `22.4%`-`28.5%` at `0.90`. Below the contracted value it is marginally more stable than `lean` and above it marginally less, but the shape is the same, so the asymmetry is a property of the spatiotemporal kernel on this panel rather than of either control set.

## 7H) GTWR Lamda / Bandwidth CV Search Diagnostic

- Manual quarterly diagnostic (`M07H`)
- Execution condition: Run [10_search_gtwr_lamda_bw_cv.R](../../02_Code/80_optional/gtwr/10_search_gtwr_lamda_bw_cv.R) directly.
- Outputs:
  - `gtwr_lamda_bw_cv_search_<control_set>.csv`
- Implementation Principles:
  - Locates the lamda / bandwidth region by leave-one-out cross validation **without fitting GTWR**. The CV score `bw.gtwr()` minimizes is the leave-one-out residual sum of squares over local weighted least squares fits, which requires neither the coefficient surface nor the hat-matrix traces that `gtwr()` also computes, so the score is assembled from the same distance-and-weight machinery as the collinearity diagnostics.
  - The distance column for a focal point depends on `lamda` but not on the bandwidth, and an adaptive kernel needs only the `bw`-th smallest distance, so one sort serves the whole bandwidth grid. Weights do not depend on the response, so one weight vector serves every outcome on a single common complete-case sample. Cost scales with (number of lamda values) x (focal sample size), not with the size of the full grid.
  - Defaults: `GTWR_CV_SEARCH_LAMDA_GRID=0.1,0.25,0.5,0.75,0.9,0.9867`, `GTWR_CV_SEARCH_BW_GRID=30,60,90,120,180`, `GTWR_CV_SEARCH_FOCAL_N=300`, `GTWR_CV_SEARCH_SEED=20260902`. The kernel and control set follow the active GTWR contract.
  - `lamda_on_grid_edge` and `st_bw_on_grid_edge` record whether the minimizing value sits on a grid boundary, that is, whether the optimum was bracketed or merely pinned.
  - This is a search tool, not a reporting one. CV optimizes prediction rather than inference, the focal subsample estimates the CV surface rather than reproducing `bw.gtwr()`'s exact value, and the active bandwidth contract weighs outcome comparability and local coefficient stability alongside fit. Reported bandwidths come from [06_select_gtwr_bandwidth.R](../../02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R) and the robustness tables of 7F and 7G, never from this search.

### 7H.1) Reading Requirement

The search does not support either contracted value, and the gap is not small. Re-run on the rebuilt panel on 2026-09-12 (`n_obs_common = 10,576`, 302 seconds), it reproduces the earlier conclusion and now carries the cost directly rather than by reference.

| Outcome | CV-best `lamda` | CV-best `st_bw` | On a grid edge | CV RMSE at best | at contracted `(0.5, 60)` |
| --- | ---: | ---: | --- | ---: | ---: |
| `vitality_sub_temporal` | `0.750` | **`30`** | bandwidth | `0.2229` | `0.3076` (**+38%**) |
| `vitality_sub_stability` | `0.900` | **`30`** | bandwidth | `0.2086` | `0.4082` (**+96%**) |
| `vitality_index_base` | `0.900` | **`30`** | bandwidth | `0.1485` | `0.3165` (**+113%**) |
| `vitality_sub_social` | `0.9867` | **`30`** | lamda and bandwidth | `0.1034` | `0.4048` (**+292%**) |
| `vitality_sub_economic` | `0.9867` | **`30`** | lamda and bandwidth | `0.1161` | `0.5041` (**+334%**) |

The contracted `lamda = 0.5` is preferred for **none** of the five outcomes and the contracted `st_bw = 60` for none either. `st_bw = 30` wins for all five and sits at the bottom of the grid, so that optimum is pinned rather than bracketed and CV would go lower still. Every outcome prefers a strongly space-weighted mix, `0.75` or above, which is the direction the retired raw-unit default happened to sit in; for two outcomes the preferred `lamda` is also pinned at the top of the grid.

Two notes on reading the table. The percentages are CV RMSE penalties at the contracted point against each outcome's own optimum, and CV optimises prediction while the bandwidth contract weighs outcome comparability and local coefficient stability, so a gap is not by itself an error. But a factor of two to four in predictive RMSE is a large price, and it has to be reported as the price of a choice rather than left implicit. The earlier version of this table recorded `0.995` for `vitality_sub_economic` and `vitality_sub_social`; that value is not on the search grid and was a transcription error for the grid maximum `0.9867`. `vitality_sub_stability` also moves from `0.750` to `0.900` between the two runs, which is expected: the focal subsample is drawn from the common complete-case sample across all five outcomes, and that sample changed when `항동` lost the social sub-index and the composite in the 2026-09-12 preprocessing fix.

What the bandwidth choice costs in coefficient terms is now measurable directly. The `lean` bandwidth sensitivity was re-run on 2026-09-23 against the contracted surface, the first such table baselined on `st_bw = 60` with the dimensionless `lamda` (42.6 hours, 25 rows, all `success`, and the baseline row self-checks at `beta_corr = 1.0000` with `0.0%` sign flips):

| `st_bw` | `beta_corr` with the reported surface | dongs flipping sign |
| ---: | ---: | ---: |
| `30` | `0.791` - `0.861` | `10.1%` - `20.0%` |
| `60` | baseline | baseline |
| `90` | `0.952` - `0.970` | `2.4%` - `9.7%` |
| `120` | `0.887` - `0.938` | `4.9%` - `14.4%` |
| `180` | `0.791` - `0.893` | `11.5%` - `22.4%` |

Ranges are across the five outcomes. Moving to the CV-preferred `30` flips the sign of the local coefficient for between one dong in ten and one in five, and correlation with the reported surface falls to `0.79`-`0.86`. The surface is therefore materially a function of the bandwidth, and a local coefficient quoted without its bandwidth is not reproducible.

**This is a property of the specification rather than of the control set.** The `extended` table, re-run on 2026-09-27 in 43.4 hours against the same contracted baseline, reproduces the pattern almost exactly: `0.759`-`0.890` correlation with `11.3%`-`20.5%` flips at `30`, `0.941`-`0.968` with `1.9%`-`8.2%` at `90`, `0.862`-`0.936` with `4.0%`-`15.5%` at `120`, and `0.743`-`0.902` with `10.4%`-`24.0%` at `180`. Adding the transit composite and the workplace worker population leaves the bandwidth response unchanged in shape and very slightly amplified at the extremes, which is what a larger local design matrix would be expected to do. The finding generalises across both control sets. The superseded figures from the retired-convention table baselined at `st_bw = 90`, `0.554` correlation and `21.9%` flips at `30`, were more alarming than the corrected measurement but pointed the same way.

## 7X) GTWR Experiment Appendix

- Manual quarterly appendix sidecar
- Outputs:
  - `gtwr_experiment_main_models_<control_set>.csv`
  - `gtwr_experiment_local_beta_panel_<control_set>.csv`
  - `gtwr_experiment_local_coefficients_<control_set>.csv`
  - `gtwr_experiment_controls_used_<control_set>.csv`
  - `gtwr_experiment_controls_used_state_<control_set>.csv`
  - `gtwr_experiment_registry_<control_set>.csv`
  - `gtwr_experiment_ranked_candidates_<control_set>.csv`
- Implementation Principles:
  - This is a manual appendix that organizes bandwidth/control strategy grids within a quarterly local contract.
  - The canonical pipeline does not automatically run this appendix.
  - **It plans specifications; it does not estimate any.** Every row it writes carries `status = not_estimated` and `frozen_spec_reason = manual_appendix_not_estimated`, and the script contains no call to `GWmodel::gtwr()`. The parameter columns, `ksi` among them, record what a specification *would* use, not what any fit used.
  - It therefore provides no sensitivity of any kind, and in particular no `ksi` sensitivity. Section 7.2 previously stated that this appendix was the one place the angle parameter varied; that was true of the registry and false of the estimates. The working `ksi` sweep is the geometric one in section 7Z.
  - `GTWR_EXPERIMENT_LAMDA_GRID` defaulted to `0.05` until 2026-09-04, a raw-unit value the dimensionless normalization did not reach. It now defaults to `0.25,0.5,0.75`.

## 7Y) GTWR Local Collinearity Diagnostic Backfill

- Manual quarterly diagnostic over already-estimated `M07` specs
- Execution condition: Run [09_backfill_gtwr_collin_diag.R](../../02_Code/80_optional/gtwr/09_backfill_gtwr_collin_diag.R) directly.
- Outputs:
  - `gtwr_collin_diag_backfill_<control_set>.csv`
- Implementation Principles:
  - Recomputes `local_cn_uncentered`, `local_cn_centered`, and `local_vif_max` for already-estimated specs **without refitting** the GTWR.
  - Each metric is reported twice, once under the legacy `GWmodel::ti.distv()` string-comparison time distance and once under the symmetric `|t_i - t_j|` distance, so the reach of the corrected time comparison can be measured.
  - Gates on reproducing the stored `local_cn_gtwr_latest` to prove the estimation sample was reconstructed exactly as the original run saw it. The 2026-09-06 `lean` run passed across all 2,125 dong-outcome rows at a maximum relative difference of `2.181e-16`.
  - Reports the earliest and latest focal quarter separately, because the legacy time comparison distorted the two endpoints to different degrees. On the reran `lean` specs the two time bases agree exactly at the latest focal quarter and differ at the earliest for 2,119 of 2,125 rows, by up to `0.63` in relative terms for `local_vif_max`, `0.43` for `local_cn_centered` and `0.16` for `local_cn_uncentered`. The reported quarter is the latest one, so the defect did not reach the published diagnostics; the earliest-quarter columns of any pre-rerun output are the ones it touched.
  - Its role for `lean` is now historical: `gtwr_local_coefficients_lean.csv` carries all three measures directly (7.1). It has never been run for `extended`, which is therefore the one control set with no `local_vif_max` or `local_cn_centered` on record anywhere.

## 7Z) GTWR Estimand and Kernel Geometry Diagnostic

- Objective: Establish what the GTWR local surface is an estimate *of*, and what its spatiotemporal kernel actually averages over, without refitting the model.
- Execution condition: Run [11_diagnose_gtwr_estimand.R](../../02_Code/80_optional/gtwr/11_diagnose_gtwr_estimand.R) directly. It reads distances and the already-published beta panel, so it costs minutes rather than the twelve hours a rerun costs.
- Inputs: `panel_main.parquet`, 2020 Seoul administrative boundary, `gtwr_main_models_<control_set>.csv`, `gtwr_local_beta_panel_<control_set>.csv`
- Outputs:
  - `gtwr_estimand_comparison_<control_set>.csv`
  - `gtwr_kernel_geometry_<control_set>.csv`
  - `gtwr_temporal_edge_<control_set>.csv`
- Implementation Principles:
  - Diagnostic only. It fits no GTWR, changes no contract, and rewrites no published estimate.
  - The estimand comparison runs the same specification under a levels OLS and the two-way within estimator on the same complete-case sample, and places the published local mean beside both. Whichever the local mean tracks is the estimand its variation decomposes.
  - The kernel geometry classifies each point of the bandwidth-nearest window as same-quarter, same-dong, or genuinely both-different, at the contracted angle and at the right angle where the interaction term drops out. The contrast is the point: recording `ksi = 0` states the parameter, not its consequence.
  - The temporal-edge table reports the kernel's own-dong support at every focal quarter and, separately, whether the reported quarter's published local mean is typical of the other quarters. The two are independent readings of the same concern.

### 7Z.1) Reading Requirement

**The local surface is a levels estimate, and the global models are not.** GTWR is fitted with no fixed effects; TWFE and SPDM are within estimators. On the same sample and specification:

| Outcome | Levels OLS | Within (TWFE) | Published GTWR mean (`lean`, 2026-09-06) |
| --- | ---: | ---: | ---: |
| `vitality_sub_economic` | `+1.487` | `-0.960` | `+1.297` |
| `vitality_sub_social` | `-0.514` | `-1.885` | `-0.090` |
| `vitality_sub_temporal` | `+0.798` | `-1.295` | `+0.168` |
| `vitality_sub_stability` | `+1.435` | `-0.163` | `+2.379` |
| `vitality_index_base` | `+1.156` | `-1.355` | `+1.451` |

The published local mean matches the **levels** sign for 5 of 5 outcomes and the **within** sign for 1 (`vitality_sub_social`, the one outcome whose two global estimands share a sign). The rerun at the contracted `st_bw = 60` and `lamda = 0.5` moved every local mean but changed neither count. The sign disagreement between GTWR and the global models is therefore not a local phenomenon; it is the levels-versus-within gap, which the ESDA layer already documents for this panel (section 1A). GTWR results must not be narrated as the global effect varying by place, because it is not that effect. Either the interpretation states the levels estimand explicitly, or the panel is two-way demeaned before fitting so the local coefficients become local versions of the within estimate. The first is the current choice; the second is recorded as the alternative and would require a rerun.

**At the contracted angle the kernel is a cross, not an ellipse.** With `ksi = 0` the Huang et al. (2010) distance collapses to `(sqrt(lamda*d_S) + sqrt((1-lamda)*d_T))^2`, which penalises a neighbour distant in both dimensions far more than one distant in either alone. Measured over the bandwidth-nearest window:

| `ksi` | `st_bw` | Same quarter, other dong | Same dong, other quarter | Genuinely spatiotemporal |
| --- | ---: | ---: | ---: | ---: |
| `0` (contracted) | `60` (published) | 82.3% | 9.3% | **6.7%** |
| `pi/4` | `60` | 76.8% | 8.8% | 12.7% |
| `pi/2` | `60` | 50.6% | 6.7% | 41.0% |
| `3pi/4` | `60` | 8.9% | 2.6% | 86.8% |
| `pi` | `60` | 0.0% | 0.0% | **98.3%** |
| `0` (contracted) | `90` | 77.9% | 7.6% | 13.3% |
| `pi/2` | `90` | 44.3% | 5.2% | 49.4% |

This sweep is the project's only working sensitivity on the angle parameter, because the appendix that section 7.2 credited with that role never estimates anything (section 7X). It is geometric rather than estimate-based, which is what makes it cheap enough to run without a refit.

At the contracted setting the model is close to a stack of per-quarter GWRs — a median of 51 distinct dongs at the focal quarter — with a thin own-dong temporal thread of about seven points. This is a legitimate specification, but it is not what "spatiotemporal weighting" conveys on its own, and it must be stated wherever GTWR results are presented, alongside the kernel and the angle parameter that section 7.0 already requires.

**The dispersion that H3 reads as heterogeneity is largely a bandwidth choice.** Across the published bandwidth sensitivity grid, `sd_beta` for `vitality_index_base` falls monotonically as the bandwidth widens: `7.79` at 30, `4.97` at 60, `4.62` at 90, `4.37` at 120, `3.87` at 180. That grid is the `lean` 7F bundle, which is on the retired raw-unit `lamda` (7E.1), so its levels are not comparable with the current run: the same outcome reports `sd_beta = 2.58` in the 2026-09-06 `lean` rerun at the same bandwidth of 60. What survives the convention change is the monotone direction, not the values. The spread of the local coefficient field is therefore not a fixed property of the data, and any statement about how much the effect varies across Seoul is a statement conditional on a bandwidth that section 7H.1 shows was not chosen by cross-validation.

**The reported quarter is the temporal edge.** Every reported coefficient comes from the last quarter, where the kernel has no future side:

| Focal quarter | Own-dong points in window | Past | Future |
| --- | ---: | ---: | ---: |
| `2019Q4` (first) | 3.5 | 0.0 | 2.5 |
| `2022Q4` (middle) | 5.9 | 2.5 | 2.5 |
| `2025Q4` (**reported**) | 3.5 | 2.5 | 0.0 |

The support falls by about 40% and becomes entirely backward-looking. This is a property of the kernel and the panel, so it is unchanged by the rerun. Its consequence for the published betas is not. Before the rerun the reported quarter's mean local coefficient lay outside the range spanned by the other 24 quarters for three of five outcomes; on the 2026-09-06 `lean` bundle it lies **inside** that range for all five:

| Outcome | `2025Q4` mean | Other 24 quarters | Other-quarter mean | latest/other `sd` |
| --- | ---: | ---: | ---: | ---: |
| `vitality_index_base` | `+1.451` | `+1.036` to `+2.394` | `+1.769` | `0.89` |
| `vitality_sub_economic` | `+1.297` | `+1.060` to `+3.703` | `+2.451` | `0.68` |
| `vitality_sub_social` | `-0.090` | `-0.356` to `+1.455` | `+0.565` | `0.92` |
| `vitality_sub_stability` | `+2.379` | `+1.966` to `+3.136` | `+2.277` | `0.93` |
| `vitality_sub_temporal` | `+0.168` | `-1.538` to `+0.656` | `-0.140` | `0.71` |

The reported quarter is no longer an outlier in level, but it still sits below the other-quarter mean for three of five outcomes and its dispersion is narrower than theirs for all five (`sd` ratio `0.68`-`0.93`). A latest-quarter reading is defensible only if the edge is stated; a claim that the latest quarter shows a change over the panel is still not supported, because the earliest quarter sits at the mirror-image edge.

## 8) Reporting and Presentation

- [01_make_tables_figures.R](../../02_Code/05_reporting/01_make_tables_figures.R)
  - Always-on descriptive/reporting outputs plus optional appendix tables.
  - `descriptive_statistics.csv` is created as an expanded descriptive statistics table by variable. It reports valid observations, missing values, mean, standard deviation, minimum, p25, median, p75, maximum, valid quarter range, and the number of dongs for aging exposures, vitality outcomes, robustness composites, vitality components, and main controls.
  - `main_variable_correlation_matrix.csv` and `main_variable_correlation_pairs.csv` calculate the Pearson correlation for main analysis variables (SPDM/GTWR) based on active analysis observations from `2019Q4~2025Q4`. The scope includes main exposures, channel mediators, supporting aging exposures, primary/supplementary outcomes, and TWFE/SPDM/GTWR control pools.
  - GTWR reporting uses the latest summary/rankings as the main surface, while delta summary/rankings are used solely as appendix diagnostics.
- [02_build_presentation_artifacts.R](../../02_Code/05_reporting/02_build_presentation_artifacts.R)
  - A presentation-only sidecar that derives slide-ready artifacts from canonical outputs.
  - Publishes `presentation_spdm_channel_path_diagram.csv` and `presentation_spdm_channel_path_diagram.png` as a slide-left visual when the optional `lag4_age60_resident_share -> lag2_age60_floating_share -> commercial vitality` channel path outputs exist.
- [03_build_gtwr_level_artifacts.R](../../02_Code/05_reporting/03_build_gtwr_level_artifacts.R)
  - Optional quarterly GTWR level reporting sidecar.
  - Reads existing `gtwr_local_beta_panel_<control_set>.csv` and related GTWR tables without rerunning GTWR.
  - Builds artifacts for both available `extended` and `lean` GTWR source families by default; `GTWR_LEVEL_CONTROL_SET=lean` or `extended` can force one family.
  - Writes reporting artifacts with strict `lean` or `extended` suffixes only; legacy mode tags are not accepted.
  - Publishes early/latest/delta triptych maps, quarterly local-beta trajectories, living-area/gu regional summaries, sign-transition tables, representative district trajectories, and earliest-to-latest delta diagnostics.

Reporting selectively attaches only those optional appendix artifacts that have source inputs, and their absence itself is not interpreted as a failure.

### 8.1 Optional Appendix Tables Are Gated, Not Automatic

The following tables from [01_make_tables_figures.R](../../02_Code/05_reporting/01_make_tables_figures.R) are written **only** when `BUILD_OPTIONAL_APPENDIX_TABLES` is true, which it is not by default, **and** the source input exists. A default pipeline run therefore does not produce them, and their absence from `03_Output/01_Tables/` is the expected state rather than a defect:

- `spatial_family_main_table.csv` (requires `spdm_family_comparison.csv`)
- `gtwr_latest_summary_table_<control_set>.csv`, `gtwr_latest_rankings_table_<control_set>.csv` (requires `gtwr_main_models_<control_set>.csv`)
- `gtwr_delta_summary_table_<control_set>.csv`, `gtwr_delta_rankings_table_<control_set>.csv` (requires horizon-aligned raw local coefficients)
- `gwr_delta_summary_table.csv` (requires `gwr_delta_main_models.csv`)

To regenerate them, run `BUILD_OPTIONAL_APPENDIX_TABLES=true Rscript 02_Code/05_reporting/01_make_tables_figures.R` after the source sidecars have been executed. The script unlinks these paths at the start of every run, so a default run also clears any copies left by an earlier gated run.
