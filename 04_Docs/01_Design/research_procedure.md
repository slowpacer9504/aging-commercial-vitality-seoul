# Research Procedure

## 0. Document Purpose

This document is a detailed procedural guide explaining how the active research design is actually executed. It is not merely a checklist of execution order, but a reproducible summary of how the quarterly panel construction, spatial diagnostics, TWFE, SPDM, and GTWR are logically connected.

The document roles are separated as follows:

- [research_plan.md](research_plan.md)
  - Research background, questions, variable roles, and methodology priority
- [research_procedure.md](research_procedure.md)
  - Actual execution procedures, input-output contracts, and runtime/QC rules

The active analytical contract follows the quarterly panel criteria declared in this document.

## 1. Core Execution Principles

### 1.1 Current Methodology Stack

The current canonical methodology stack follows this order:

1. `ESDA`
2. `TWFE baseline / residual spatial-diagnostic`
3. `SPDM main global model`
4. `GTWR resident-only optional local sidecar`

This order represents both the execution sequence and the interpretation logical flow. We first confirm the presence of spatial patterns, establish a direction with non-spatial baselines, interpret direct and spillover effects via spatial expansion models, and only when necessary, read local heterogeneity through a separate sidecar.
The preprocessing, TWFE, SPDM, and GTWR sidecars under [`80_optional/**`](../../02_Code/80_optional) are manual surfaces outside of [run_all.R](../../02_Code/run_all.R), and the SPDM channel path is also included in this optional/manual surface. Executing these files directly will perform the actual tasks without requiring separate `RUN_*` execution flags.

### 1.2 Non-negotiable Execution Principles

1. The spatial unit is unified to **Seoul administrative dongs (`adm_cd`) based on 2020 boundaries**.
2. The canonical panel construction scope is **2019Q1-2025Q4**, and the active analysis period is **2019Q4-2025Q4**.
3. The common active keys are `adm_cd` and `yq`.
4. The active shared panel retains `year`, `quarter`, `yq`, and `quarter_index`.
5. The coordinate reference system (CRS) is `EPSG:5179`.
6. The canonical model timing contract is a **lagged quarterly contract**.
7. The main exposure is `lag4_age60_resident_share`.
8. `lag2_age60_floating_share` serves as an optional SPDM channel path mediator, while `age60_floating_share` and `age60_sales_share` are treated as supplementary axes for ESDA or appendices.
9. For dependent variables, individual vitality indicators are prioritized, and `vitality_index_base` is kept as a supplementary composite.
10. The primary spatial weights matrix is row-standardized `Queen`.
11. Alternative W matrices are `Rook`, `kNN6`, and `kNN8`.
12. TWFE is not the main inferential endpoint but a baseline / spatial-diagnostic layer.
13. SPDM main is the primary global model, centering on the reporting of direct / indirect / total effects.
14. [80_optional/spdm/07_run_spdm_channel_path.R](../../02_Code/80_optional/spdm/07_run_spdm_channel_path.R) is an optional channel path sidecar that tests the `lag4_age60_resident_share -> lag2_age60_floating_share -> vitality` pathway.
15. GTWR is an optional local sidecar restricted strictly to the resident-only quarterly contract.
16. A single `panel_main.parquet` serves as the authoritative source of truth, and ESDA/TWFE/SPDM/GTWR read only their method-specific views.
17. Original raw data and boundary sources must not be modified.

### 1.3 Summary of Data and Variable Contracts

- Core Datasets
  - `seoul_quarter_base.parquet`
  - `adm_region_lookup.parquet`
  - `aux_covariates.parquet`
  - `aux_covariates_lag_support.parquet`
  - `golmok_survival_rate.parquet`
  - `registered_resident_population.parquet`
  - `registered_resident_population_lag_support.parquet`
  - `panel_merged_base.parquet`
  - `panel_main_pre_vitality.parquet`
  - `panel_main.parquet`
  - `W_queen.rds`, `W_rook.rds`, `W_knn6.rds`, `W_knn8.rds`
- Original Data Axes
  - Seoul Commercial District Analysis Service raw data
  - Supplementary public data
  - 2020 base administrative dong boundaries
- Main Variable Axes
  - main exposure: `lag4_age60_resident_share`
  - channel mediator: `lag2_age60_floating_share`
  - supporting exposures: `age60_resident_share`, `age60_floating_share`, `age60_sales_share`
  - primary outcomes: `vitality_sub_economic`, `vitality_sub_social`, `vitality_sub_temporal`, `vitality_sub_stability`
  - supplementary composite: `vitality_index_base`
- robustness composites: `vitality_index_entropy`, `vitality_index_pca`
- channel path composite: `vitality_index_base`

## 2. Detailed Research Execution Procedures

### 2.1 Common Data Standards

The practical unit of analysis for this project is the `adm_cd x yq` quarterly panel. The core of the preprocessing is preserving the short-term variations of quarterly sources, while explicitly declaring source precision by appending yearly/static sources to the quarterly panel using a quarter-end as-of rule.
2019Q1-2019Q3 are retained as a warm-up period for calculating rolling 4-quarter indicators and validating lag variables, but the active analysis sample and reporting sample are restricted to `2019Q4-2025Q4`.

The common execution principles are as follows:

- Among the Seoul Commercial District Analysis Service data, quarterly sources are organized directly on an `adm_cd-yq` basis.
- Yearly and static sources are organized at the `adm_cd-year` or `adm_cd` level and then joined to the quarterly panel using an as-of approach.
- Models do not create separate slim panel files; they only read method-specific views of `panel_main`.
- Therefore, the practical handoff between preprocessing and modeling is firmly established through the single `panel_main.parquet` file.

### 2.1A [01_build_adm_region_lookup.R](../../02_Code/01_preprocess/01_build_adm_region_lookup.R): Build Administrative Dong-District-Living Area Lookup

The purpose of this step is to create a static lookup linking `adm_cd`, administrative dong names, autonomous district names, and the 5 major regional living areas, based on the 2020 Seoul administrative dong boundaries. While this lookup is not directly fed into the statistical models of the analysis panel, it serves as a foundational asset to reuse the same regional classifications in mapping administrative dong names from resident population sources, aggregating GTWR results by region, performing QC, and generating reporting outputs.

Core outputs are as follows:

- `adm_region_lookup.parquet`
  - Static lookup based on `adm_cd`
- `adm_region_lookup.csv`
  - Companion table for review and reporting
- `adm_region_lookup_qc.csv`
  - QC checks for 425 administrative dongs, 25 autonomous districts, 5 regional living areas, and the number of dongs per district contracts

This step does not modify the raw boundary sources. Autonomous districts are identified by the first 6 digits of `adm_cd`, and the Seoul 5 major regional living areas classification table is joined.

### 2.2 [02_build_seoul_quarter_base.R](../../02_Code/01_preprocess/02_build_seoul_quarter_base.R): Build Seoul Commercial District Quarterly Base

The purpose of this step is to integrate the raw tables of the Seoul Commercial District Analysis Service by source and create a quarterly base panel that serves as the reference grid for all subsequent analyses.

This script first scans all raw files to identify source types. The raw data is then processed in two tracks:

1. Quarterly sources with intra-year distribution (e.g., `estimated_sales`, `stores`, `street_population_floating_population`)
   - A quarterly publication rule is applied on an `adm_cd-yq` basis.
   - Additive flows use quarterly sums, levels/shares use quarterly representative values or denominator-weighted quarterly shares, and temporal/stability components are calculated using cross-sectional quarterly data and rolling 4-quarter distributions.
2. Remaining yearly sources
   - Directly standardized on an `adm_cd-year` basis.
   - For the quarterly panel, source precision is explicitly stated, and they are joined using a quarter-end as-of rule.
   - Q4-update-type sources from the Seoul Commercial District Analysis Service are published as strict Q4 snapshot as-of.
   - If a Q4 observation is missing, it is not replaced with the latest quarter's value of the same year but left as missing.

The core outputs of this step are as follows:

- `seoul_quarter_base.parquet`
  - Canonical quarterly base
- `seoul_raw_review.parquet`
  - Raw integration review companion
- `panel_quarter_aggregation_qc.csv`
  - QC log checking coverage and the results of applying quarterly publication rules

Crucially, by standardizing the source quarter codes during the raw provenance stage, **only the standard `year`, `quarter`, `yq`, and `quarter_index` remain after the active base.**

### 2.3 [03_build_auxiliary_covariates.R](../../02_Code/01_preprocess/03_build_auxiliary_covariates.R): Organize Supplementary Public Data as `adm_cd-yq` Covariates

The purpose of this step is to build a set of auxiliary variables that can be directly attached to the commercial district quarterly base. First, `base_quarter` is defined by reading the `adm_cd-yq` combinations actually present in `seoul_quarter_base.parquet`, and all supplementary sources are organized according to this standard.

Key tasks are as follows:

1. Reading raw files and cleaning columns
2. Assigning point/line/polygon data to `adm_cd` geometries
3. Processing geocoding, caching, and manual fixes
4. Publishing annual/static sources as as-of covariates tailored to the quarterly panel

Official land prices are processed by assigning administrative dongs to the internal representative points of parcel polygons, and then aggregating them as area-weighted averages by administrative dong and year using valid parcel areas as weights. In the quarterly panel, the official land price for a given year is identically published to all 4 quarters of that year. This is an active contract designed to control the overall land price level based on the total land area of the administrative dong, and strict intersection-area calculations between administrative dongs and parcels are not performed.

The main outputs of this step are as follows:

- `aux_covariates.parquet`
  - Canonical auxiliary contract on an `adm_cd-yq` basis
- `medical_source_preagg.parquet`, `mall_source_preagg.parquet`, `senior_source_preagg.parquet`
  - Reproducible record-level intermediates
- `walk_betweenness_local800_len_v1.parquet`
  - Static walk-environment cache
- Geocode/QC/unmatched logs

Public transit accessibility sources track quarterly source precision separately. Bus stops repeat single snapshots from 2019, 2020, and 2025 as the representative quarterly values for those respective years. For the monthly snapshots from January 2021 to April 2024, the latest snapshot prior to the end of each quarter is used. For the source gap after May 2024, the April 1, 2024 snapshot is carried forward. Subway stations apply an opening date rule to the station master, including only stations where `open_date <= quarter_end` in the quarter's count.

Medical facilities and large-scale retail are no longer included in the active control pool. While record-level pre-aggregation is maintained, they remain in the active panel strictly as permit-based as-of diagnostic variables.

### 2.4 [01_build_living_population_inflow.R](../../02_Code/80_optional/preprocess/01_build_living_population_inflow.R): Build External Inflow Population based on Seoul Living Population

The purpose of this step is to create an external inflow population layer on an `adm_cd-yq` basis by reading the monthly Seoul Living Population ZIP sources without fully extracting them. Because the social dimension of commercial vitality should reflect the scale of population flowing in from external living areas, not just simple internal floating populations, this output is managed as an optional preprocessing layer but is joined to the final panel if it exists.

Due to the high processing cost of monthly ZIP files, this step is excluded from the default execution of [run_all.R](../../02_Code/run_all.R) and the required test plan. If [01_build_living_population_inflow.R](../../02_Code/80_optional/preprocess/01_build_living_population_inflow.R) is executed manually and its outputs exist, they are joined on an `adm_cd-yq` basis in [06_build_analysis_panel.R](../../02_Code/01_preprocess/06_build_analysis_panel.R). If `living_population_external_inflow.parquet` already exists and `LIVING_POP_FORCE_REBUILD=FALSE`, this optional preprocessing script will reuse the existing output.
Full regeneration can utilize parallel processing for monthly ZIP units. If `LIVING_POP_CORES` is set to 2 or more, the monthly ZIP processing for INNER and METRO will be parallelized, while the final parquet, manifest, and QC files are written once by the parent process.

Aggregation definitions are as follows:

- Internal migration data: Only rows where the target administrative dong's district differs from the residential district are used.
- Metro area domestic/foreign data: All rows are used as external inflow.
- Time periods: The default is the full `0-23` hours (`LIVING_POP_HOURS=0-23`).
- Final indicators: Since the living population is a point-in-time stock and not a cumulative flow, the monthly average point-in-time population is calculated first, and then averaged across the months within the same quarter.
- For ZIP files with missing intra-month days, the average of the observed days is used as the monthly representative value, but `month_success_days`, `month_expected_days`, and `month_coverage_flag` are recorded in `living_population_inflow_manifest.csv`.
- In a full run, if a 12-month coverage for both INNER/METRO is not achieved, the process will fail. Partial months (1-9 days or 10-19 days) are used but tracked as warnings or severe warnings in the manifest.

Main outputs are as follows:

- `living_population_external_inflow.parquet`
  - `inner_external_inflow_pop`, `metro_external_inflow_pop`, `external_inflow_pop`
- `living_population_inflow_manifest.csv`
  - ZIP member processing success/error/skip logs
- `living_population_inflow_qc.csv`
  - QC for quarterly finite coverage and value ranges

### 2.5 [04_build_golmok_survival_rate.R](../../02_Code/01_preprocess/04_build_golmok_survival_rate.R): Build Newly Established Firm Survival Rate

The purpose of this step is to directly call the `selectSurvivalRate.json` response from the Seoul Commercial District Analysis Service website to construct a newly established firm survival rate layer on an `adm_cd-yq` basis. Because it parses and saves the JSON response used for webpage inquiries instead of performing PDF/OCR extraction, it can preserve not only the survival rates but also the number of surviving firms and cohort denominators.

The study period `2019Q1-2025Q4` is secured by making Q4 requests for the base years `2019`, `2022`, and `2025`. Since each request returns a 3-year block, the `2019` request provides `2017-2019`, `2022` provides `2020-2022`, and `2025` provides `2023-2025`. Only the `2019-2025` values from these are joined to the active panel on an as-of basis, with the administrative dong codes padded to the project canonical `10-digit adm_cd`.

Main outputs are as follows:

- `golmok_survival_rate.parquet`
  - `survival_1y`, `survival_3y`, `survival_5y` along with surviving firm counts and cohort denominators
- `golmok_survival_all_levels.parquet`
  - Raw-level parsing results including Seoul total, autonomous districts, and administrative dongs
- `golmok_survival_rate_qc.csv`
  - QC for key uniqueness, quarterly coverage, rate ranges, numerator/denominator recalculation diffs, and small cohort sizes

`survival_3y` is used in the store continuity axis of the active stability sub-index. Administrative dong-quarters with a survival rate denominator of 0 are not arbitrarily replaced but kept as `NA`, and the missing values and small cohort counts are logged in the QC file.

### 2.6 [05_build_registered_resident_population.R](../../02_Code/01_preprocess/05_build_registered_resident_population.R): Build Registered Resident Population

The purpose of this step is to match the monthly 5-year age group CSV files of the Ministry of the Interior and Safety's resident registration population status to the 2020 Seoul administrative dong codes, generating the resident population scale and the share of the elderly resident population. The resident population from the Seoul Commercial District Analysis Service is not used as the source for the active main exposure and `ln_resident_pop`.

Monthly stock variables are published as quarterly averages, not annual sums. `age60_resident_share`, `age60_64_resident_share`, `age65_74_resident_share`, `age75plus_resident_share`, and `age65plus_resident_share` are denominator-weighted quarterly shares calculated by dividing the monthly sums of the elderly population in the respective quarter by the monthly sums of the total population in the same quarter. For the TWFE/SPDM age-mix appendix, the quarterly average population counts for youth (20s-30s), middle-aged (40s-50s), and elderly (60s and older) are created from this resident population layer, log1p-transformed, and `ln_young_resident_pop`, `ln_middle_resident_pop`, and `ln_old_resident_pop` are all used as exposures. `lag4_ln_resident_pop` is maintained as a lagged resident scale control.

For the 2020 boundary matching, original administrative dong names are matched to boundary names, and any dong splits/renames during the analysis period are aggregated or reverted based on 2020. `Sangil-je1-dong` becomes `Sangil-dong`, `Gangil-dong + Sangil-je2-dong` becomes `Gangil-dong`, `Gaepo3-dong` becomes `Irwon2-dong`, and the 2025 `Sinseol-dong + Yongdu-dong + Yongsin-dong` is treated as `Yongsin-dong`. `Hang-dong`, which was split from `Oryu-je2-dong` in 2020, was included in the pre-split `Oryu-je2-dong` during 2018-2019. Therefore, the 2018-2019 raw values of `Oryu-je2-dong` are distributed according to the proportions of the same age groups in the same month for `Oryu-je2-dong`/`Hang-dong` in 2020. These split-distribution rows are tracked with `registered_boundary_proxy_flag` and `registered_boundary_proxy_reference_year`.

Main outputs are as follows:

- `registered_resident_population.parquet`
  - `resident_pop`, `age60_resident_pop`, `age60_resident_share`, `age65_74_resident_share`, `age75plus_resident_share`, etc.
- `registered_resident_population_lag_support.parquet`
  - 2018Q1-2025Q4 `adm_cd-yq` resident population lag-support layer
- `registered_resident_population_monthly.parquet`
  - Intermediate monthly stock and age total validation layer
- `registered_resident_population_mapping_qc.csv`
  - Mapping status between original administrative dong names and canonical `adm_cd`
- `registered_resident_population_qc.csv`
  - QC for quarterly coverage, 3-month coverage, split distribution counts, elderly share ranges, and age sum diffs

### 2.7 [06_build_analysis_panel.R](../../02_Code/01_preprocess/06_build_analysis_panel.R): Join Common Analysis Panel and Create Common Derived Variables

The purpose of this step is to join `seoul_quarter_base`, `aux_covariates`, `living_population_external_inflow`, `golmok_survival_rate`, and `registered_resident_population`; generate canonical lag variables from `aux_covariates_lag_support` and `registered_resident_population_lag_support`; create common derived variables and QCs shared by all downstream analyses at once; and publish `panel_main_pre_vitality`, the state just before calculating the final vitality indices.

First, key integrity is verified again:

- `seoul_quarter_base`: `adm_cd-yq` unique
- `aux_covariates`: `adm_cd-yq` unique
- `aux_covariates_lag_support`: 2018Q1-2025Q4 `adm_cd-yq` unique
- `workplace_worker_population`: 2018-2025 `adm_cd-year` unique
- `living_population_external_inflow`: `adm_cd-yq` unique when optional output exists
- `golmok_survival_rate`: `adm_cd-yq` unique
- `registered_resident_population`: `adm_cd-yq` unique
- `registered_resident_population_lag_support`: 2018Q1-2025Q4 `adm_cd-yq` unique

Then, they are joined by `adm_cd`, `year`, `quarter`, `yq`, and `quarter_index` to create `panel_merged_base.parquet`. This file is a provenance checkpoint. If issues arise later, it must be possible to isolate whether "the join itself broke" or "the derived variable calculation after the join broke."

The main variable groups created in this script include:

- `covid_period`
  - An appendix interaction flag marking the `2020Q1-2022Q2` quarter range
- `ln_total_sales`, `ln_sales_count`, `ln_total_store_count`, `ln_sales_per_store`
- `sales_quarter_stability`, `floating_quarter_stability`
- `ln_resident_pop`, `ln_floating_pop`, `ln_external_inflow_pop`, `ln_spend_total`
- `ln_official_land_price`, `ln_land_price_adjusted`
- `ln_workplace_worker_pop`
- `transit_accessibility`
- `lag4_age60_resident_share`, `lag4_ln_resident_pop`, `lag4_ln_land_price_adjusted`, `lag4_transit_accessibility`, `lag4_ln_workplace_worker_pop`
- `lag2_age60_floating_share`
- `store_density`, `resident_pop_density`, `floating_pop_density`
- `sales_per_store`, `sales_per_capita`
- `survival_3y`
- `stability_score` (`-closure_rate`, diagnostic support)
- `age60_sales_lq`

`ln_land_price_adjusted` applies the quarter-average adjustment factor of the Korea Real Estate Board's monthly regional land price index (relative to December of the previous year) to the existing administrative-dong-year official land price levels. The statutory dong-level land price index is matched to the administrative dong level using an area-weighted crosswalk between Seoul statutory dong boundaries and 2020 administrative dong boundaries. The original annual official land price log is preserved as `ln_official_land_price`, while active model controls use `ln_land_price_adjusted`.

Next, the shared quarterly contract is finalized:

- The canonical shared panel retains only contemporaneous source variables and registered model lag variables.
- Permitted lag variables are `lag4_age60_resident_share`, `lag4_ln_resident_pop`, `lag4_ln_land_price_adjusted`, `lag4_transit_accessibility`, `lag4_ln_workplace_worker_pop`, and `lag2_age60_floating_share`.
- Legacy suffix-type shift/lead derived columns and unregistered lag variables are not kept in the active shared panel.

Key QCs for this stage are as follows:

- `panel_join_coverage_qc.csv`
- `panel_quarter_aggregation_qc.csv`
- `panel_structural_count_flags.csv`
- `missing_data_log.csv`

### 2.8 [07_build_vitality_index.R](../../02_Code/01_preprocess/07_build_vitality_index.R): Vitality Index Construction and `panel_main` Publication

The purpose of this step is to calculate the vitality indices using `panel_main_pre_vitality` as input and publish `panel_main.parquet`, the final canonical shared panel.

The core principle is a publication contract stating, "We do not alter the common panel again; we only add the permitted vitality columns."

The components are grouped into four sub-dimensions:

- `vitality_sub_economic`
  - transaction scale axis: `ln_sales_count`, `ln_total_sales`
  - final subindex: Equal-weighted average of pooled-z `ln_sales_count` and pooled-z `ln_total_sales`
- `vitality_sub_social`
  - `ln_floating_pop`, `ln_external_inflow_pop`
- `vitality_sub_temporal`
  - `sales_time_entropy`, `floating_time_entropy`, `sales_quarter_stability`, `floating_quarter_stability`
- `vitality_sub_stability`
  - diversity axis: `diversity_index`
  - continuity axis: `operating_months_rel_seoul`, `survival_3y`
  - final subindex: Equal-weighted average of pooled-z diversity axis and pooled-z continuity axis

Additionally, the following supplementary composites are created:

- `vitality_index_base`
- `vitality_index_entropy`
- `vitality_index_pca`

The standardization baseline is the active analysis period sample, `2019Q4-2025Q4 adm_cd-yq`. [07_build_vitality_index.R](../../02_Code/01_preprocess/07_build_vitality_index.R) standardizes individual components using pooled z-scores to create sub-indices, which are then standardized again via pooled z-scores to calculate the composites. Cross-sectional standardization per quarter is not used in the active workflow.

### 2.8 [01_build_spatial_weights.R](../../02_Code/02_esda/01_build_spatial_weights.R): Spatial Weights Matrix Construction

This step constructs the common spatial contract using the 2020 base Seoul administrative dong boundaries.

- main W: `Queen`
- robustness W: `Rook`, `kNN6`, `kNN8`

All models and map visualizations must share the same `adm_cd` ordering and same-boundary contract.

### 2.9 [02_run_esda.R](../../02_Code/02_esda/02_run_esda.R): Quarterly Spatial Diagnostics

ESDA is the stage to confirm the presence of spatial patterns before estimating models.

- Distribution maps and LISA are saved focusing on the latest quarter cross-section.
- Global Moran's I uses a reproducible permutation p-value, and alternative W sensitivity is calculated the same way.
- LISA quadrants are classified based on the signs of `z(x)` and `W z(x)` for univariate, and `z(x)` and `W z(y)` for bivariate cases.
- Bivariate LISA maps are generated for all combinations of `age60_resident_share`/`age60_floating_share` and the vitality indicators.
- EHSA is calculated using the quarterly sequence. Following the Gi* convention in `sfdep::emerging_hotspot_analysis()`, EHSA uses `queen_include_self` weights that include self-neighbors in the queen contiguity.
- Key variables are `age60_resident_share`, `age60_floating_share`, `vitality_sub_*`, and `vitality_index_base`.

### 2.10 [01_run_twfe_main.R](../../02_Code/03_models/01_run_twfe_main.R): Quarterly TWFE Baseline

TWFE provides non-spatial baselines and residual Moran diagnostics.

- Input: `panel_main.parquet`, `W_queen.rds`
- Base specification: `y_it ~ lag4_age60_resident_share + lag4_controls_it | adm_cd + yq`
- Standard Errors: `cluster = ~ adm_cd`
- Dependent Variables: `vitality_sub_*`, `vitality_index_base`

Required outputs are as follows:

- `twfe_main_models.csv`
- `twfe_main_controls_used.csv`
- `twfe_main_diagnostics.csv`
- `twfe_main_residual_moran.csv`
- `twfe_main_residual_moran_by_yq.csv`

### 2.11 [02_run_spdm_main.R](../../02_Code/03_models/02_run_spdm_main.R): Quarterly SPDM Main Model

SPDM is the main global model of the active design.

- Input: `panel_main.parquet`, `W_queen.rds`
- Main exposure: `lag4_age60_resident_share`
- Specification: `y_it = rho W y_it + X_it beta + W X_it theta + adm_cd FE + yq FE + e_it`
- Implementation: `W lag4_age60_resident_share` and `W controls` are manually generated by `yq`, and estimated using `splm::spml(lag=TRUE, spatial.error="none", model="within", effect="twoways")`.
- Main output: `direct / indirect / total effects`
- Impact: Uses true SDM matrix impacts based on `S = (I - rho W)^(-1)` and `S(beta I + theta W)`.
- Standard Errors: Coefficients and spatial parameters use model-based asymptotic ML `vcov` from `splm::spml()`, and impact SEs/CIs are computed via simulation from the same `vcov`. This output is reported as model-based inference, not robust SEs.

Core outputs are as follows:

- `spdm_main_models.csv`
- `spdm_impacts.csv`
- `spdm_controls_used.csv`
- `spdm_main_diagnostics.csv`

### 2.12 [07_run_spdm_channel_path.R](../../02_Code/80_optional/spdm/07_run_spdm_channel_path.R): Optional SPDM Channel Path Sidecar

This step is an optional mediation-oriented channel sidecar executed only when directly running [02_Code/80_optional/spdm/07_run_spdm_channel_path.R](../../02_Code/80_optional/spdm/07_run_spdm_channel_path.R). It tests the `lag4_age60_resident_share -> lag2_age60_floating_share -> commercial vitality` pathway over the quarterly Queen SDM. By fixing `lag4_age60_resident_share` as `X` and `lag2_age60_floating_share` as the mediator `M`, it estimates the total-effect equation, mediator equation, and outcome equation simultaneously on identical balanced samples for each vitality outcome.

- Total-effect equation: `Y_it = rho W Y_it + X_it beta_c + W X_it theta_c + controls + W controls + FE + e_it`
- Mediator equation: `M_it = rho W M_it + X_it beta_a + W X_it theta_a + controls + W controls + FE + e_it`
- Outcome equation: `Y_it = rho W Y_it + X_it beta_c' + M_it beta_b + W X_it theta_c' + W M_it theta_b + controls + W controls + FE + e_it`
- Channel outcomes: `vitality_sub_economic`, `vitality_sub_temporal`, `vitality_sub_stability`, `vitality_index_base`
- Excluded outcome: `vitality_sub_social` overlaps directly with the floating population source, so it is excluded as a standalone outcome for the channel path. However, the comprehensive vitality index uses `vitality_index_base`, which includes social activity, to preserve the study's four-dimensional conceptual construct, while documenting the mediator source overlap caveat.
- Indirect effect: Records the `a*b` product effect across `direct`, `indirect`, and `total` scales, along with the attenuation diagnostic of the direct effect (`c - c'`).
- Inference: The default is wild residual bootstrap at the administrative dong level. If bootstrap is disabled or lacks valid draws, `delta_independent_approx` (assuming independence between `a` and `b` impact estimates) serves as a fallback.
- Runtime defaults: Default settings are `SPDM_CHANNEL_IMPACT_SIM_R=1000` for channel impact simulation, `SPDM_CHANNEL_BOOTSTRAP_R=1000` for bootstrap iterations, and `RUN_SPDM_CHANNEL_BOOTSTRAP=TRUE` to execute the bootstrap.
- Parallel runtime: Default core counts are `SPDM_CHANNEL_IMPACT_CORES=4` and `SPDM_CHANNEL_BOOTSTRAP_CORES=4`. On macOS/Linux/GCP, impact simulation draws and bootstrap draws are processed in parallel, whereas Windows safely falls back to sequential execution.

Core outputs are as follows:

- `spdm_channel_models.csv`
- `spdm_channel_impacts.csv`
- `spdm_channel_controls_used.csv`
- `spdm_channel_path_effects.csv`
- `spdm_channel_bootstrap_draws.csv`
- `spdm_channel_diagnostics.csv`

### 2.13 [01_run_spdm_w_robustness.R](../../02_Code/04_robustness/01_run_spdm_w_robustness.R): W Sensitivity Check

This step iteratively estimates the same resident-only quarterly SDM contract across `queen`, `rook`, `knn6`, and `knn8`. Its purpose is to check sensitivity to the choice of W matrix.

### 2.14 [05_run_spdm_family_comparison_sidecar.R](../../02_Code/80_optional/spdm/05_run_spdm_family_comparison_sidecar.R): Spatial Family Comparison

This step is a manual sidecar for the appendix. It reconstructs the exact quarterly Queen sample and selected control contract of the main SPDM, then compares `TWFE`, `SLX`, `SAR`, `SDM`, `SEM`, `SDEM`, `SARAR/SAC`, and `GNS` under identical conditions. The effects for `SLX` and `SDEM` are reported as `W X` effects without the endogenous `W y` feedback multiplier, saved as `direct=beta`, `indirect=theta`, and `total=beta+theta`. `GNS` is the most general appendix sensitivity family incorporating `W y`, `W X`, and spatial errors, with its average effects recorded via the SDM matrix impact method.

### 2.15 [03_run_gtwr_main.R](../../02_Code/03_models/03_run_gtwr_main.R): Optional Quarterly Local Sidecar

GTWR main is a quarterly resident-only local sidecar.

- Execution Condition: Direct execution of [03_models/03_run_gtwr_main.R](../../02_Code/03_models/03_run_gtwr_main.R)
- Inputs: `panel_main.parquet`, 2020 base Seoul administrative dong boundaries
- Interpretation level: Local heterogeneity description
- Execution method: Computations run per outcome-exposure spec, utilizing parallel workers up to `GTWR_PARALLEL_SPECS`.
- Resumption method: Per-spec RDS caches are saved to `03_Output/04_Logs/gtwr_spec_cache/<control_set>/main/`, and if interrupted and restarted, valid completed specs are reused.
- Control set: Default is `GTWR_CONTROL_SET=lean`. `lean` only uses resident-population-based `lag4_ln_resident_pop` and `lag4_ln_land_price_adjusted`. `extended` adds `lag4_transit_accessibility` and `lag4_ln_workplace_worker_pop` to these.
- Bandwidth strategy: Main GTWR uses fixed adaptive `GTWR_ST_BW=60`. Based on `adaptive=TRUE`, 60 spatiotemporal neighbors around each estimation point are used. `full_panel_bw_gtwr` and `anchor_quarter_bw_gtwr` searches are only performed in [06_select_gtwr_bandwidth.R](../../02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R), and the selected results are saved to `gtwr_bandwidth_selection_<control_set>.csv` and the bandwidth cache. [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R) applies the default `GTWR_BANDWIDTH_SENSITIVITY_GRID` (`30,60,90,120,180`) iteratively to the same outcome-control-spec, saving beta correlations against the baseline 60, absolute changes, sign flips, and local condition-number shifts to `gtwr_bandwidth_sensitivity_<control_set>.csv`.
- Lamda sensitivity: Executed exclusively in [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R). It re-estimates GTWR applying each value in `GTWR_LAMDA_SENSITIVITY_GRID` to the same outcome-control-spec, logging correlations, absolute changes, sign flips, and local condition-number shifts against baseline latest-quarter betas to `gtwr_lamda_sensitivity_<control_set>.csv`.
- Local CN Diagnostics: Follows the `GWmodel::gwr.collin.diagno()` local_CN calculation convention but applies the `st.dist`/`gw.weight`-based spatiotemporal weights used in GTWR.

The core operational principles for GTWR are:

1. Only quarterly samples are used.
2. The main control pool is selected via `GTWR_CONTROL_SET`. The default `lean` uses only resident population scale and land price controls, while `extended` adds transit accessibility composites.
3. The main bandwidth is unified to a fixed `GTWR_ST_BW=60`. `bw.gtwr()` searches (full-panel or anchor-quarter), fixed bandwidth grid sensitivities, and lamda grid sensitivities are strictly separated into [06_select_gtwr_bandwidth.R](../../02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R), [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R), and [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R) respectively.
4. Main raw/output surfaces are constructed based on latest-quarter local betas.
5. Earliest-to-latest deltas are derived exclusively for `gtwr_delta_*` auxiliary reporting tables.
6. The final CSV bundle aggregates and refreshes from the entire spec cache on every run.
7. Lamda and bandwidth sensitivities are computationally expensive and thus interpreted only as manual auxiliary diagnostics.
8. GTWR does not replace global causal claims.

Additional GTWR appendix sidecars share the same quarterly panel, `GWmodel::gtwr()` execution path, `GTWR_CONTROL_SET` contract, and fixed bandwidth default as main GTWR. They run when directly executing the respective `80_optional/gtwr` scripts, utilizing separate spec/bandwidth cache namespaces.

- [01_run_gtwr_floating_only.R](../../02_Code/80_optional/gtwr/01_run_gtwr_floating_only.R): Direct execution estimates main outcomes x `age60_floating_share`.
- [02_run_gtwr_age_band.R](../../02_Code/80_optional/gtwr/02_run_gtwr_age_band.R): Direct execution estimates configured resident/floating domain x age20~age50 exposure x main outcomes. The resident domain uses age shares based on Ministry of the Interior resident populations and the same-domain total control `ln_resident_pop`, while the floating domain omits `ln_floating_pop` as it overlaps with dependent variable components.
- [03_run_gtwr_sector_share.R](../../02_Code/80_optional/gtwr/03_run_gtwr_sector_share.R): Direct execution estimates resident-only and floating-only exposure families for sector-share outcomes.
- [06_select_gtwr_bandwidth.R](../../02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R): Saves `bw.gtwr()` search results for the resident-only main spec when `GTWR_BANDWIDTH_STRATEGY=full_panel_bw_gtwr` or `anchor_quarter_bw_gtwr`.
- [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R): Direct execution runs fixed bandwidth grid sensitivity against the resident-only main baseline output.
- [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R): Direct execution runs lamda grid sensitivity against the resident-only main baseline output.
- [01_make_tables_figures.R](../../02_Code/05_reporting/01_make_tables_figures.R) derives latest-minus-earliest delta summaries/rankings whenever sidecar raw local coefficients are present.

### 2.16 [02_run_robustness.R](../../02_Code/04_robustness/02_run_robustness.R) and Reporting

[02_run_robustness.R](../../02_Code/04_robustness/02_run_robustness.R) checks outcome-definition, sample-window, and W-Moran sensitivities against the quarterly contract. [01_make_tables_figures.R](../../02_Code/05_reporting/01_make_tables_figures.R) bundles tables and figures for the main text/appendices, and additionally publishes Pearson correlation matrices and pairwise correlation tables for main analysis variables. Reporting selectively attaches optional artifacts only when source inputs exist.

## 3. Active QC Rules

### 3.1 Data Contract QC

- Key duplication: 0 occurrences for `adm_cd x yq`
- Panel horizon: `2019Q1~2025Q4`
- Active analysis horizon: `2019Q4~2025Q4`
- Shared panel must retain `year`, `quarter`, `yq`, and `quarter_index`
- Check quarterly publication/as-of coverage and aggregation rules
- `FAIL` upon detecting negative structural counts
- `FAIL` upon absence of core vitality index component variables

### 3.2 Model Contract QC

- ESDA, TWFE, and SPDM must all operate based on `panel_main.parquet`.
- TWFE residual Moran outputs are mandatory.
- SPDM must report direct / indirect / total effects.
- SPDM channel path is an optional sidecar, and its absence is not interpreted as a failure. When executed, `a`, `b`, `c'`, `a*b` effects and diagnostics are reported as appendix artifacts.
- GTWR is an optional sidecar, and its absence is not interpreted as a failure.

### 3.3 Processed Output Integrity Check

- `method_dataset_contract_check.csv`
- `processed_parquet_inventory.csv`
- `processed_parquet_schema.csv`
- `processed_parquet_missing_summary.csv`
- `processed_parquet_qc_checks.csv`

These logs must be evaluated against the quarterly contract.
