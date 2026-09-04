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
  - **Levels versus within.** `global_morans_i_within.csv` reports both scales side by side with `retained_share`, because the estimators identify from within-dong, within-quarter deviations rather than from levels. Autocorrelation confined to the cross-sectional levels is removed by the fixed effects before estimation and cannot on its own justify a spatial specification. Measured over all 25 quarters, the level scale is significant in 175 of 175 variable-quarters while the within scale is significant in 102; the exposures retain their structure (`age60_resident_share` significant in 92% of quarters within, `age60_floating_share` 96%) whereas the outcomes largely do not (`vitality_sub_economic` 64%, `vitality_sub_social` 44%, `vitality_sub_stability` 8%). This asymmetry, spatial structure surviving in `X` but not in `y`, is the empirical reason the significant SPDM spillovers arrive through `W X` rather than through `W y`.
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
  - Impacts are calculated using the matrix expressions `S = (I - rho W)^(-1)` and `S(beta I + theta W)`, saving simulation-based standard errors and confidence intervals.
  - Standard errors for coefficients and spatial parameters come from the model-based asymptotic ML `vcov` of the `splm::spml()` fitted object. Impact SEs/CIs are simulation-based inferences using the same `vcov`, and are not referred to as robust SEs in active SPDM outputs.
  - **The model-based SE is not understated, but it is conditional on the error structure the model assumes.** A dong-level wild bootstrap that regenerates the outcome through the reduced form `y* = S(Z gamma + e*)` rather than holding `W y` fixed returns a standard error of `0.0769` for `vitality_sub_social` against the model-based `0.0838`, a ratio of `0.92`, over 150 valid draws. An earlier diagnosis that the SPDM standard errors were understated by a factor of 2.2 to 4.3, inferred from their gap against the TWFE dong-clustered errors, is therefore withdrawn. What the bootstrap establishes is narrower than it looks: it resamples residuals under the covariance structure `spml` itself estimated, so it confirms the standard error is correct given the model rather than that the model is correct. The open question is the one below.
  - **Serial correlation is not modelled.** `rho W y` is a cross-sectional dependence term; nothing in the specification represents dependence in the time dimension. The TWFE residuals on the same panel have an AR(1) coefficient of `0.61` to `0.81` with p-values below `1e-170`, so that dependence is present and substantial. In the SDM it is absorbed into `sigma^2` rather than modelled, which is the reason the model-based SE sits far below the TWFE dong-clustered SE (`0.084` against `0.359` for `vitality_sub_social`) even though both are internally valid under their own assumptions. This is a specification limitation to state, not a computational error to fix.
  - **No Lee-Yu bias correction is available.** `splm::spml()` exposes no bias-correction argument, verified against its signature. Lee and Yu (2010) show that the quasi-ML estimator of a spatial panel with fixed effects carries a bias of order `1/T` from the individual effects and `1/N` from the time effects, concentrated in `rho` and `sigma^2`. With `N = 425` the time-effect term is negligible; with `T = 25` the individual-effect term is not, and no correction is applied. Estimates of `rho` should be read with that in mind, and the direction of the reported impacts does not hinge on it here because `rho` is small (`0.02` to `0.17`).
  - **Panel and weights alignment is asserted at the estimator.** `splm` maps panel rows to the weights matrix by position within each period and does not verify that mapping, so a row order inconsistent with the `listw` is accepted silently and returns plausible but wrong estimates. On this panel the `region.id` order differs from alphabetical order for 393 of the 425 dongs, and sorting alphabetically instead moves `rho` by 21% and `theta` by a factor of 2.3 with no error and no warning. `assert_spdm_panel_alignment()` now checks the order of every period against `region.id` immediately before each `spml()` handoff, in addition to the existing guard inside `W X` construction.
  - **`lambda` is the spatial lag parameter, not a spatial error parameter.** `splm` exports the autoregressive parameter of a lag model under the name `lambda`, the opposite of the convention in which `lambda` denotes the error parameter. The term keeps `splm`'s name so the exported table matches `coef()` on the fitted object; the `spatial_param_role` column states what each row actually holds, taking the value `rho_spatial_lag` for that row in the `sar`, `sdm`, `gns`, and `sarar_sac` families.
  - The `splm` covariance matrix arrives without dimnames, so `spdm_get_vcov_matrix()` restores them from the coefficient vector before any name-based indexing.
  - `ln_floating_pop` is a component of the dependent variable, so it is excluded from the main SPDM control contract.
  - Sample rule: each outcome-control specification is reduced to complete cases on the outcome, the exposure, and the trial controls, and only administrative dongs observed in **every** remaining quarter are kept, so the estimation panel is strictly balanced. A specification is accepted only if it retains at least 20 dongs and at least `SPDM_MIN_PERIODS` quarters; the default of 20 is therefore a floor on the length of the balanced panel, not a per-dong observation threshold. Because a dong missing any single quarter is dropped in full, `n_units` in `spdm_impacts.csv` varies across outcomes (423 to 425) rather than always equalling the 425 dongs of the panel. The realized `n_units`, `n_periods`, and `n_obs` are recorded per outcome in `spdm_main_models.csv` and `spdm_impacts.csv`.
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
  - If the bootstrap is disabled or yields insufficient valid draws, `delta_independent_approx` is used as a fallback, but the result is interpreted as a mediation-oriented channel inference rather than an automatic full mediation judgment.
  - `mediated_share_vs_cprime` is accompanied by `mediation_pattern`, because a share outside `[0, 1]` is not a proportion mediated. A negative value means the channel offsets the direct path rather than transmitting it, and both patterns are routinely read as "x% of the effect runs through the mediator".

### 5A.1) Status of the Published Channel Path Table

> **The bootstrap columns of the published `spdm_channel_path_effects.csv` are not usable.** They were produced by a resample of the form `fitted + residual * weight` on `splm` objects. `splm` defines no `fitted` method, so `stats::fitted()` returned a slot that is not a fitted value of the outcome in any scale: on this panel it correlates `0.010` with the raw outcome, `-0.007` with its two-way within transform, and `-0.005` with `rho*W*y`, and `fitted + residuals` reproduces neither the outcome (`max |diff| = 5.16`) nor its within transform (`5.08`). The substitution raised no error.

The published consequence is visible without re-running anything. Bootstrap standard errors run 5 to 56 times smaller than the delta-method approximation in the same table, and 9 of 12 rows report `bootstrap_p = 0.000`; for one `vitality_sub_temporal` row the delta method gives `p = 0.786` against a bootstrap `p = 0.000`.

A 40-draw pilot of the corrected reduced-form scheme on the full balanced panel, against the same specification, gives an `a*b` standard deviation of `0.553` where the shipped scheme gives `0.043` — **13.0 times larger** — with the draw mean (`0.104`) centred on the point estimate (`0.107`) rather than displaced from it (`0.139`).

Until [07_run_spdm_channel_path.R](../../02_Code/80_optional/spdm/07_run_spdm_channel_path.R) is re-run, `bootstrap_se`, `bootstrap_p`, `bootstrap_ci_low`, `bootstrap_ci_high` and `indirect_p` in the published table must not be quoted, and no mediation claim may rest on them. The point estimates `a`, `b`, `c_total`, `c_prime` and `a*b` are unaffected: they come from the fits, not from the resample. A full re-run is roughly 2 to 3 hours at `SPDM_CHANNEL_BOOTSTRAP_R=1000` on 4 cores, measured at 2.8 seconds per `spml` fit.
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
- The standard error contract matches the main SPDM. Coefficients and spatial parameters are reported with model-based asymptotic ML SEs, while impacts are reported with model-based `vcov` simulation SEs.
- Outputs:
  - `spdm_w_robustness_models.csv`
  - `spdm_w_robustness_impacts.csv`
  - `spdm_w_robustness_controls_used.csv`
  - `spdm_w_robustness_diagnostics.csv`

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
| `vitality_sub_social` | `-1.840` (p < 0.001) | `-1.593` (p < 0.001) | robust in every variant |
| `vitality_sub_economic` | `-0.961` (p = 0.063) | `-0.343` (p = 0.416) | materially attenuated |
| `vitality_index_base` | `-1.363` (p = 0.004) | `-0.847` (p = 0.083) | loses 5% significance |
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
| `vitality_sub_social` | `-1.840` (<.001) | **`-1.304` (.011)** | `-0.613` (.206) | `-0.607` (.248) |
| `vitality_index_base` | `-1.363` (.004) | `-0.822` (.118) | `-1.543` (.061) | `-3.878` (.042) |
| `vitality_sub_temporal` | `-1.297` (.112) | `+1.458` (.349) | `-2.823` (.083) | `-7.059` (.069) |
| `vitality_sub_stability` | `-0.257` (.655) | `-0.109` (.935) | `-2.017` (.250) | `-3.668` (.327) |

Three readings follow, and they constrain what may be claimed.

First, the placebo fails for `vitality_sub_economic` and `vitality_sub_social`: future aging predicts current vitality at least as well as past aging does, and for `vitality_sub_economic` the lag collapses to `-0.212` (p = .639) once both are entered. This is not a collinearity artefact. After two-way demeaning the lag and the lead correlate at `0.674`, a variance inflation factor of `1.8`, so the horse race is informative rather than degenerate.

Second, only `vitality_index_base` survives dong-specific linear trends. `vitality_sub_social`, the one outcome that survives the influence diagnostic of section 6A.1, falls from `-1.840` (p < .001) to `-0.607` (p = .248): that effect was the differential trend.

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

### 6C.1) Reading Requirement

The first run confirmed that the intersection is empty. No outcome passes all nine gates; the best passes six.

| Outcome | base | ctrl | fam | infl | plac | race | trnd | lin | se2w | Passed | Tier |
| --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- |
| `vitality_index_base` | O | O | O | **X** | O | **X** | O | **X** | O | 6/9 | `descriptive_only` |
| `vitality_sub_social` | O | O | O | O | **X** | **X** | **X** | **X** | O | 5/9 | `conditional_association` |
| `vitality_sub_economic` | X | X | X | X | X | X | X | O | X | 1/9 | `not_supported` |
| `vitality_sub_temporal` | X | X | X | X | O | X | X | X | X | 1/9 | `not_supported` |
| `vitality_sub_stability` | X | X | X | X | O | X | X | X | X | 1/9 | `not_supported` |

Columns, in the order of `GATE_META`: `base` = `baseline_significant`, `ctrl` = `control_set_consistency`, `fam` = `model_family_agreement`, `infl` = `influence_stable`, `plac` = `placebo_lead_null`, `race` = `lag_beats_lead`, `trnd` = `dong_trend_survival`, `lin` = `linearity_not_rejected`, `se2w` = `se_twoway_significant`.

Four readings follow, and they govern the language of the results.

First, `lag_beats_lead` fails for every outcome, which makes it a property of the design rather than of any outcome. Entered alongside the 4-quarter lead, the 4-quarter lag is not significant for a single outcome (p = .639, .206, .083, .250, .061). This is not a collinearity artefact: after two-way demeaning the two correlate at `0.674`, a variance inflation factor of `1.8`. The lag is separable from the lead and still does not win. No choice of outcome answers this, and no outcome may carry a causal directional claim.

Second, the tier names a *kind* of claim, not a quality ranking, because the failures are not commensurable. `vitality_index_base` passes more gates but fails `influence_stable`: dropping the nine union-tail dongs, `2.1%` of the sample, takes it from `-1.363` (p = .004) to `-0.847` (p = .083). Its magnitude is therefore not reportable, and it is the only outcome that survives dong-specific trends. `vitality_sub_social` has a stable magnitude but fails all three identification gates. These license different sentences, and neither is the stronger result in a single ordering.

Third, `n_gates_passed` is not comparable across outcomes, because some gates are conditional on the baseline. `vitality_sub_temporal` and `vitality_sub_stability` each pass `placebo_lead_null`, but a placebo test has nothing to falsify when the baseline effect is itself null; those are vacuous passes, and the 1/9 rows should be read as "no reportable effect" rather than as a graded score.

Fourth, `model_family_agreement` fails for three outcomes, and the disagreement runs one way: SPDM reports all five direct effects as significant, TWFE two. For `vitality_sub_stability` the sign also differs, `-0.257` (p = .655) against `+0.570` (p = .024). The cause is the standard error, not the point estimate — `0.137` for SPDM against `0.515` for TWFE clustered on dong, for `vitality_sub_economic`. As recorded in section 5, `splm` models no dependence in the time dimension, and the residual AR(1) coefficient runs `0.61` to `0.81` across outcomes. The two tables' p-values must not be read side by side.

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
| All published | 21 | 405 | 277 | 267 | 20.3 |
| Main text | 2 | 15 | 11 | 11 | 0.8 |
| Appendix | 19 | 390 | 266 | 256 | 19.5 |

Two readings, and the second is the more useful one.

The search is large: the main text rests on 15 tests while the published tables carry 405, spread across appendix families that are searches by construction — age-mix, sector-share, vitality components, COVID interactions, spatial model families, W variants. Any appendix result quoted in support of a claim is selected from that surface, and the reporting should say so.

The adjustment nevertheless changes very little: 277 unadjusted rejections become 267 under BH across all 405 tests, and the main-text count is unchanged at 11. The appendix results are not a field of marginal p-values that multiplicity would sweep away. That is worth stating explicitly, because the honest concern about these families is the one in sections 3C and 5A.1 — timing, collinearity, and an invalid resample — rather than the count.

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

> **The GTWR tables currently in `03_Output/01_Tables/` were produced before this contract and do not match it.** They are retained because a full rerun costs at least twelve hours; the gap is measured rather than assumed.

| | Contracted (7.0) | Published output |
| --- | --- | --- |
| `st_bw` | `60` | **`90`** (explicit run-time override; see [decision_log.md](../03_Log/decision_log.md), 2026-09-04 entry) |
| `lamda` | `0.5` dimensionless | **`0.05` raw-unit** (retired convention; roughly 76:1 in favour of space, against the contract's 1:1) |
| Time distance | symmetric `abs(t_i - t_j)` | legacy `GWmodel::ti.distv()` string comparison |
| Collinearity schema | `local_vif_max`, `local_cn_centered`, `local_cn_gtwr` | `local_cn_gtwr` only |
| Local inference | `estimate_se`, `estimate_t`, `estimate_p`, BH-FDR flag | **absent** (see below) |
| Run date | pending | `gtwr_*_lean` 2026-06-23, `gtwr_*_extended` 2026-06-27 |

Two consequences for anyone reading the published tables:

- `gtwr_main_models_<control_set>.csv` reports `collinearity_warn_share` near `1.0`. That column was written under the retired flag, which keyed off the **uncentered** condition number. It is not evidence of pervasive collinearity under the current criterion. Measured on the same specs by [09_backfill_gtwr_collin_diag.R](../../02_Code/80_optional/gtwr/09_backfill_gtwr_collin_diag.R), the current criterion (`local_vif_max >= 10`) flags 1.4% of rows, with a median `local_vif_max` of 1.86.
- `gtwr_local_coefficients_<control_set>.csv` does not yet carry `local_vif_max` or `local_cn_centered` columns. Until the rerun, `gtwr_collin_diag_backfill_<control_set>.csv` (7Y) is the source for all three diagnostics.
- **No published GTWR table carries a local standard error.** `GWmodel::gtwr()` returns `<var>_SE` and `<var>_TV` for every estimation point, and the extraction read only the coefficient. The code now reads all three (section 7.2), but the published tables predate that, so `sd_beta` and `share_positive` in `gtwr_main_models_<control_set>.csv` remain the only descriptions of the local surface and **neither separates a varying relationship from the sampling noise of many small local fits**. Until the rerun, no statement of the form "the effect is positive in region X" is supported by these tables. Section 7Z reports what can be established without the rerun.

QC checks `G02` and `G03` run whenever the GTWR outputs exist, not only under the opt-in flag: GTWR is optional to produce, but not optional to be correct once published. `G03` reports the diagnostic schema as pending-rerun rather than failed until the rerun lands.

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
  - Actual estimation of main outcomes x `age60_floating_share` specs is performed using `GWmodel::gtwr()`.
  - The control pool follows the same `GTWR_CONTROL_SET` contract as the main GTWR.
  - Because it is excluded from the default `run_all.R` and required test plans, the absence of raw output is not considered a failure.

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

## 7D) GWR Delta Appendix

- Execution condition: Run [04_run_gwr_delta.R](../../02_Code/80_optional/gtwr/04_run_gwr_delta.R) directly.
- Manual quarterly appendix sidecar
- Outputs:
  - `gwr_delta_main_models.csv`
  - `gwr_delta_local_coefficients.csv`
  - `gwr_delta_floating_models.csv`
  - `gwr_delta_floating_local_coefficients.csv`
  - `gwr_delta_controls_used.csv`
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

## 7F) GTWR Bandwidth Sensitivity Diagnostic

- Manual quarterly diagnostic
- Execution condition: Run [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R) directly.
- Outputs:
  - `gtwr_bandwidth_sensitivity_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_bandwidth_sensitivity_cache/<control_set>/main/*.rds`
- Implementation Principles:
  - Requires baseline `gtwr_main_models_<control_set>.csv` and `gtwr_local_coefficients_<control_set>.csv` first.
  - The fixed bandwidth grid is re-estimated by spec, and the sensitivity regarding correlation, absolute difference, sign flip, and local collinearity diagnostics relative to the baseline latest-quarter beta is saved.

## 7G) GTWR Lamda Sensitivity Diagnostic

- Manual quarterly diagnostic
- Execution condition: Run [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R) directly.
- Outputs:
  - `gtwr_lamda_sensitivity_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_lamda_sensitivity_cache/<control_set>/main/*.rds`
- Implementation Principles:
  - Requires baseline `gtwr_main_models_<control_set>.csv` and `gtwr_local_coefficients_<control_set>.csv` first.
  - The lamda grid is re-estimated by spec using the fixed main bandwidth, and sensitivity regarding correlation, absolute difference, sign flip, and local collinearity diagnostics relative to the baseline latest-quarter beta is saved.

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

The only search run under the current convention does not support either contracted value, and the gap is not small.

| Outcome | CV-best `lamda` | CV-best `st_bw` | On a grid edge |
| --- | ---: | ---: | --- |
| `vitality_index_base` | `0.900` | **`30`** | bandwidth |
| `vitality_sub_economic` | `0.995` | **`30`** | lamda and bandwidth |
| `vitality_sub_social` | `0.995` | **`30`** | lamda and bandwidth |
| `vitality_sub_stability` | `0.750` | **`30`** | bandwidth |
| `vitality_sub_temporal` | `0.750` | **`30`** | bandwidth |

The contracted `lamda = 0.5` is preferred for **none** of the five outcomes, and the contracted `st_bw = 60` for none either; `st_bw = 30` wins for all five and sits at the bottom of the grid, so the optimum is pinned rather than bracketed and CV would go lower still. Every outcome prefers a strongly space-weighted mix (`0.75` or above), which is the direction the retired raw-unit default happened to sit in.

What that costs is measurable in 7F, with the caveat of 7E.1 that the table itself is on the retired convention. Moving from the published `st_bw = 90` to `30` leaves the local betas correlated at `0.554` with `21.9%` of dongs flipping sign; moving merely to the contracted `60` still flips `8.0%`. A bandwidth chosen against CV for comparability is a defensible choice, but it has to be reported as a choice with that price, not as a neutral default.

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
  - Recomputes `local_cn_uncentered`, `local_cn_centered`, and `local_vif_max` for specs that were estimated before the current diagnostic schema, **without refitting** the GTWR.
  - Each metric is reported twice, once under the legacy `GWmodel::ti.distv()` string-comparison time distance and once under the symmetric `|t_i - t_j|` distance, so the reach of the corrected time comparison can be measured before a full rerun is scheduled.
  - Gates on reproducing the stored `local_cn_gtwr_latest` to prove the estimation sample was reconstructed exactly as the original run saw it; the lean run reproduced it across all 2,125 dong-outcome rows to a maximum relative difference of 2.457e-12.
  - Reports the earliest and latest focal quarter separately, because the legacy time comparison distorted the two endpoints to different degrees.

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

| Outcome | Levels OLS | Within (TWFE) | Published GTWR mean |
| --- | ---: | ---: | ---: |
| `vitality_sub_economic` | `+1.487` | `-0.960` | `+0.511` |
| `vitality_sub_social` | `-0.514` | `-1.885` | `-0.870` |
| `vitality_sub_temporal` | `+0.798` | `-1.295` | `+0.813` |
| `vitality_sub_stability` | `+1.435` | `-0.163` | `+1.135` |
| `vitality_index_base` | `+1.156` | `-1.355` | `+0.704` |

The published local mean matches the **levels** sign for 5 of 5 outcomes and the **within** sign for 1. The sign disagreement between GTWR and the global models is therefore not a local phenomenon; it is the levels-versus-within gap, which the ESDA layer already documents for this panel (section 1A). GTWR results must not be narrated as the global effect varying by place, because it is not that effect. Either the interpretation states the levels estimand explicitly, or the panel is two-way demeaned before fitting so the local coefficients become local versions of the within estimate. The first is the current choice; the second is recorded as the alternative and would require a rerun.

**At the contracted angle the kernel is a cross, not an ellipse.** With `ksi = 0` the Huang et al. (2010) distance collapses to `(sqrt(lamda*d_S) + sqrt((1-lamda)*d_T))^2`, which penalises a neighbour distant in both dimensions far more than one distant in either alone. Measured over the bandwidth-nearest window:

| `ksi` | `st_bw` | Same quarter, other dong | Same dong, other quarter | Genuinely spatiotemporal |
| --- | ---: | ---: | ---: | ---: |
| `0` (contracted) | `60` | 82.3% | 9.3% | **6.7%** |
| `pi/4` | `60` | 76.8% | 8.8% | 12.7% |
| `pi/2` | `60` | 50.6% | 6.7% | 41.0% |
| `3pi/4` | `60` | 8.9% | 2.6% | 86.8% |
| `pi` | `60` | 0.0% | 0.0% | **98.3%** |
| `0` (contracted) | `90` (published) | 77.9% | 7.6% | 13.3% |
| `pi/2` | `90` | 44.3% | 5.2% | 49.4% |

This sweep is the project's only working sensitivity on the angle parameter, because the appendix that section 7.2 credited with that role never estimates anything (section 7X). It is geometric rather than estimate-based, which is what makes it cheap enough to run without a refit.

At the contracted setting the model is close to a stack of per-quarter GWRs — a median of 51 distinct dongs at the focal quarter — with a thin own-dong temporal thread of about seven points. This is a legitimate specification, but it is not what "spatiotemporal weighting" conveys on its own, and it must be stated wherever GTWR results are presented, alongside the kernel and the angle parameter that section 7.0 already requires.

**The dispersion that H3 reads as heterogeneity is largely a bandwidth choice.** Across the bandwidth sensitivity grid, `sd_beta` for `vitality_index_base` falls monotonically as the bandwidth widens: `7.79` at 30, `4.97` at 60, `4.62` at 90 (published), `4.37` at 120, `3.87` at 180. The spread of the local coefficient field is therefore not a fixed property of the data, and any statement about how much the effect varies across Seoul is a statement conditional on a bandwidth that section 7H.1 shows was not chosen by cross-validation.

**The reported quarter is the temporal edge.** Every reported coefficient comes from the last quarter, where the kernel has no future side:

| Focal quarter | Own-dong points in window | Past | Future |
| --- | ---: | ---: | ---: |
| `2019Q4` (first) | 3.5 | 0.0 | 2.5 |
| `2022Q4` (middle) | 5.9 | 2.5 | 2.5 |
| `2025Q4` (**reported**) | 3.5 | 2.5 | 0.0 |

The support falls by about 40% and becomes entirely backward-looking. The consequence is visible in the published betas: the reported quarter's mean local coefficient lies **outside the range spanned by the other 24 quarters** for `vitality_index_base` (`0.704` against `0.742`-`2.512`), `vitality_sub_economic` (`0.511` against `0.567`-`2.813`), and `vitality_sub_social` (`-0.870` against `-0.869`-`0.722`). The dispersion is unchanged (latest/other `sd` ratio `0.85`-`1.03`), so it is the level that shifts, not the spread. A latest-quarter reading is defensible only if the edge is stated; a claim that the latest quarter shows a change over the panel is not supported, because the earliest quarter sits at the mirror-image edge.

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
