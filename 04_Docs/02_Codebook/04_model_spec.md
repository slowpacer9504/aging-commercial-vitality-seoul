# Model Specification

## 0) Canonical vs Supplementary Surface

- The active canonical model surface is [02_run_esda.R](../../02_Code/02_esda/02_run_esda.R) -> [01_run_twfe_main.R](../../02_Code/03_models/01_run_twfe_main.R) -> [02_run_spdm_main.R](../../02_Code/03_models/02_run_spdm_main.R) -> [01_run_spdm_w_robustness.R](../../02_Code/04_robustness/01_run_spdm_w_robustness.R) -> [02_run_robustness.R](../../02_Code/04_robustness/02_run_robustness.R) -> [01_make_tables_figures.R](../../02_Code/05_reporting/01_make_tables_figures.R).
- All active canonical models and reporting use the `2019Q4~2025Q4` analysis sample. `2019Q1~2019Q3` is maintained only as a rolling/lag warm-up period for panel construction.
- TWFE, SPDM, GTWR, and optional preprocessing scripts under `80_optional/**` are part of a manual direct-run surface that is excluded from the default run and required test plans. Executing these files directly will perform the actual tasks without needing a separate `RUN_*` execution flag.
- The TWFE channel, interaction, age-mix, sector-share, selection, and family-comparison, SPDM channel path, and GTWR local appendix series are treated as supplementary/manual or appendix sidecars. The SPDM channel path is executed directly via [07_run_spdm_channel_path.R](../../02_Code/80_optional/spdm/07_run_spdm_channel_path.R).

## 1) ESDA

- Objective: Identify the presence of spatial dependence.
- Inputs: `panel_main.parquet`, `W_*.rds`
- Outputs:
  - `global_morans_i.csv`
  - `global_morans_i_by_w.csv`
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
  - `Global Moran's I`, `Global Bivariate Moran's I`, `Univariate LISA`, `Bivariate LISA`, and `EHSA` are executed reproducibly based on a quarterly sequence.
  - The p-values for Global Moran's I are calculated using a permutation approach with a deterministic seed.
  - LISA quadrants are classified based on the signs of `z(x)` and `W z(x)` for univariate, and `z(x)` and `W z(y)` for bivariate analyses.
  - Bivariate LISA maps save all combinations of calculated aging variables and vitality indicators.
  - EHSA uses `queen_include_self` weights (queen contiguity including self-neighbors), following the Gi* convention of `sfdep::emerging_hotspot_analysis()`.
  - The core variables are `age60_resident_share`, `age60_floating_share`, `vitality_sub_*`, and `vitality_index_base`.

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

## 3B) TWFE Interaction Models

- Appendix resident FE COVID interaction family
- Inputs: `panel_main.parquet`, `twfe_main_controls_used.csv`
- Period flag: `covid_period = 1` represents the `2020Q1~2022Q2` quarterly sample.
- Equation structure:
  - `M4`: `Y_it ~ lag4_age60_resident_share + lag4_age60_resident_share:covid_period + controls | adm_cd + yq`

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
  - `ln_floating_pop` is a component of the dependent variable, so it is excluded from the main SPDM control contract.

## 5B) SPDM Interaction Models

- Appendix resident SDM COVID interaction family
- Inputs: `panel_main.parquet`, `W_queen.rds`, `spdm_main_controls_used.csv`
- Period flag: `covid_period = 1` represents the `2020Q1~2022Q2` quarterly sample.
- Equation structure:
  - `M4`: `Y_it ~ lag4_age60_resident_share + lag4_age60_resident_share:covid_period + controls`

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
  - Default `a*b` inference utilizes a dong-level wild residual bootstrap. If the bootstrap is disabled or yields insufficient valid draws, `delta_independent_approx` is used as a fallback, but the result is interpreted as a mediation-oriented channel inference rather than an automatic full mediation judgment.
  - Runtime defaults are `RUN_SPDM_CHANNEL_BOOTSTRAP=TRUE`, `SPDM_CHANNEL_BOOTSTRAP_R=1000`, `SPDM_CHANNEL_BOOTSTRAP_CORES=4`, `SPDM_CHANNEL_IMPACT_SIM_R=1000`, and `SPDM_CHANNEL_IMPACT_CORES=4`. It uses parallel execution on macOS/Linux/GCP and sequential fallback on Windows.

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

## 5F) SPDM Selection Sidecar

- Appendix selection family
- Outputs:
  - `spdm_selection_tests.csv`
  - `spdm_selection_family_comparison.csv`
- Implementation Principles:
  - Compares SEM, SAR, and SDM selection diagnostics within the same quarterly control contract as the main queen sample.
  - The family comparison table also stores `sample_min_yq` and `sample_max_yq`.

## 6) Robustness

- Objective: Check sensitivity to outcome definitions, sample windows, and W-Moran specifications.
- Outputs:
  - `robustness_summary.csv`
  - `robustness_compare.png`
- Implementation Principles:
  - The canonical shared panel retains only contemporaneous source variables and registered model lag variables.
  - Unregistered lag/lead families are not created.
  - Sample windows compare the `full` (`2019Q4~2025Q4`) and `pre2025` quarterly windows.

## 7) GTWR Main Optional Sidecar

- Objective: Explain resident-only local heterogeneity.
- Inputs: `panel_main.parquet`, `2020 Seoul administrative boundary`
- Execution condition: Run [03_run_gtwr_main.R](../../02_Code/03_models/03_run_gtwr_main.R) directly.
- Outputs:
  - `gtwr_main_models_<control_set>.csv`
  - `gtwr_local_beta_panel_<control_set>.csv`
  - `gtwr_local_coefficients_<control_set>.csv`
  - `gtwr_controls_used_<control_set>.csv`
  - `gtwr_main_frozen_spec_<control_set>.csv`
  - `gtwr_latest_summary_table_<control_set>.csv`
  - `gtwr_latest_rankings_table_<control_set>.csv`
  - `gtwr_delta_summary_table_<control_set>.csv`
  - `gtwr_delta_rankings_table_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/main/*.rds`
- Implementation Principles:
  - Executed based on a quarterly sample.
  - `GTWR_CONTROL_SET=lean` is used as the default control specification.
  - The lean control pool consists solely of `lag4_ln_resident_pop` and `lag4_ln_land_price_adjusted`.
  - `GTWR_CONTROL_SET=extended` adds `lag4_transit_accessibility` and `lag4_ln_workplace_worker_pop` to the lean controls.
  - In GTWR extended, the number of bus stops and subway stations are not input as separate controls but as a `lag4_transit_accessibility` composite, and workplace population size is controlled via `lag4_ln_workplace_worker_pop`.
  - Records the local condition-number based on GTWR spatiotemporal weights as a diagnostic.
  - The local condition-number applies the local_CN calculation convention of `GWmodel::gwr.collin.diagno()` adapted to GTWR's `st.dist`/`gw.weight` spatiotemporal weights.
  - The default bandwidth is uniformly fixed at `GTWR_ST_BW=60`.
  - Under `adaptive=TRUE`, a bandwidth of 60 means 60 spatiotemporal neighbors around each estimation point.
  - [03_run_gtwr_main.R](../../02_Code/03_models/03_run_gtwr_main.R) does not run `bw.gtwr()` even if `GTWR_BANDWIDTH_STRATEGY` is not fixed.
  - `bw.gtwr()` full-panel/anchor-quarter search, fixed bandwidth grid sensitivity, and lambda grid sensitivity are only executed in [06_select_gtwr_bandwidth.R](../../02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R), [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R), and [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R), respectively.
  - The default fixed bandwidth grid for [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R) is `30, 60, 90, 120, 180`, with a baseline of `GTWR_ST_BW=60`.
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

## 7F) GTWR Bandwidth Sensitivity Diagnostic

- Manual quarterly diagnostic
- Execution condition: Run [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R) directly.
- Outputs:
  - `gtwr_bandwidth_sensitivity_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_bandwidth_sensitivity_cache/<control_set>/main/*.rds`
- Implementation Principles:
  - Requires baseline `gtwr_main_models_<control_set>.csv` and `gtwr_local_coefficients_<control_set>.csv` first.
  - The fixed bandwidth grid is re-estimated by spec, and the sensitivity regarding correlation, absolute difference, sign flip, and local condition-number relative to the baseline latest-quarter beta is saved.

## 7G) GTWR Lamda Sensitivity Diagnostic

- Manual quarterly diagnostic
- Execution condition: Run [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R) directly.
- Outputs:
  - `gtwr_lamda_sensitivity_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_lamda_sensitivity_cache/<control_set>/main/*.rds`
- Implementation Principles:
  - Requires baseline `gtwr_main_models_<control_set>.csv` and `gtwr_local_coefficients_<control_set>.csv` first.
  - The lamda grid is re-estimated by spec using the fixed main bandwidth, and sensitivity regarding correlation, absolute difference, sign flip, and local condition-number relative to the baseline latest-quarter beta is saved.

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
