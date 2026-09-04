# Research Procedure

> **Last updated**: 2026-09-04

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

### 2.2 [01_build_adm_region_lookup.R](../../02_Code/01_preprocess/01_build_adm_region_lookup.R): Build Administrative Dong-District-Living Area Lookup

The purpose of this step is to create a static lookup linking `adm_cd`, administrative dong names, autonomous district names, and the 5 major regional living areas, based on the 2020 Seoul administrative dong boundaries. While this lookup is not directly fed into the statistical models of the analysis panel, it serves as a foundational asset to reuse the same regional classifications in mapping administrative dong names from resident population sources, aggregating GTWR results by region, performing QC, and generating reporting outputs.

Core outputs are as follows:

- `adm_region_lookup.parquet`
  - Static lookup based on `adm_cd`
- `adm_region_lookup.csv`
  - Companion table for review and reporting
- `adm_region_lookup_qc.csv`
  - QC checks for 425 administrative dongs, 25 autonomous districts, 5 regional living areas, and the number of dongs per district contracts

This step does not modify the raw boundary sources. Autonomous districts are identified by the first 6 digits of `adm_cd`, and the Seoul 5 major regional living areas classification table is joined.

### 2.3 [02_build_seoul_quarter_base.R](../../02_Code/01_preprocess/02_build_seoul_quarter_base.R): Build Seoul Commercial District Quarterly Base

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

### 2.4 [03_build_auxiliary_covariates.R](../../02_Code/01_preprocess/03_build_auxiliary_covariates.R): Organize Supplementary Public Data as `adm_cd-yq` Covariates

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

### 2.5 [01_build_living_population_inflow.R](../../02_Code/80_optional/preprocess/01_build_living_population_inflow.R): Build External Inflow Population based on Seoul Living Population (Optional)

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

### 2.6 [04_build_golmok_survival_rate.R](../../02_Code/01_preprocess/04_build_golmok_survival_rate.R): Build Newly Established Firm Survival Rate

The purpose of this step is to directly call the `selectSurvivalRate.json` response from the Seoul Commercial District Analysis Service website to construct a newly established firm survival rate layer on an `adm_cd-yq` basis. Because it parses and saves the JSON response used for webpage inquiries instead of performing PDF/OCR extraction, it can preserve not only the survival rates but also the number of surviving firms and cohort denominators.

The study period `2019Q1-2025Q4` is secured by making Q4 requests for the base years `2019`, `2022`, and `2025`. Since each request returns a 3-year block, the `2019` request provides `2017-2019`, `2022` provides `2020-2022`, and `2025` provides `2023-2025`. Only the `2019-2025` values from these are joined to the active panel on an as-of basis, with the administrative dong codes padded to the project canonical `10-digit adm_cd`.

Main outputs are as follows:

- `golmok_survival_rate.parquet`
  - `survival_1y`, `survival_3y`, `survival_5y` along with surviving firm counts and cohort denominators
- `golmok_survival_all_levels.parquet`
  - Raw-level parsing results including Seoul total, autonomous districts, and administrative dongs
- `golmok_survival_rate_qc.csv`
  - QC for key uniqueness, quarterly coverage, rate ranges, numerator/denominator recalculation diffs, and small cohort sizes

`survival_3y` is used in the store persistence axis of the active stability sub-index. Administrative dong-quarters with a survival rate denominator of 0 are not arbitrarily replaced but kept as `NA`, and the missing values and small cohort counts are logged in the QC file.

### 2.7 [05_build_registered_resident_population.R](../../02_Code/01_preprocess/05_build_registered_resident_population.R): Build Registered Resident Population

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

### 2.8 [06_build_analysis_panel.R](../../02_Code/01_preprocess/06_build_analysis_panel.R): Join Common Analysis Panel and Create Common Derived Variables

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

### 2.9 [07_build_vitality_index.R](../../02_Code/01_preprocess/07_build_vitality_index.R): Vitality Index Construction and `panel_main` Publication

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
  - structural diversity axis: `diversity_index`
  - store persistence axis: `operating_months_rel_seoul`, `survival_3y`
  - final subindex: Equal-weighted average of pooled-z structural diversity axis and pooled-z store persistence axis

Additionally, the following supplementary composites are created:

- `vitality_index_base`
- `vitality_index_entropy`
- `vitality_index_pca`

The standardization baseline is the active analysis period sample, `2019Q4-2025Q4 adm_cd-yq`. [07_build_vitality_index.R](../../02_Code/01_preprocess/07_build_vitality_index.R) standardizes individual components using pooled z-scores to create sub-indices, which are then standardized again via pooled z-scores to calculate the composites. Cross-sectional standardization per quarter is not used in the active workflow.

#### Outlier policy: none, by design, and what follows from it

No winsorising, trimming, or robust standardization is applied at any stage of preprocessing. Every extreme value a source produces reaches the models. This is a deliberate choice, because the extremes here are real events rather than data errors, but it has three consequences that must be reported rather than discovered:

1. **The sub-indices are strongly left-skewed.** In the active window the minima reach `-7.1` standard deviations for `vitality_sub_economic`, `-6.8` for `vitality_sub_social`, `-9.1` for `vitality_sub_stability`, and `-14.3` for `vitality_sub_temporal`, against maxima of only `+2.2` to `+3.3`. The quarterly stability components are the source: they are bounded above and unbounded below, so a z-score is a poor summary of them. The time-of-day entropy components are well behaved.
2. **A few dongs set the scale for everyone else.** Dongs beyond five pooled z units inflate the pooled standard deviation by `22.1%` for `vitality_sub_temporal` and by `6%` to `11%` for the other sub-indices. A coefficient reported per standard deviation is therefore denominated in a unit those dongs helped define.
3. **The affected dongs are shocked, not aging.** They fall into two groups: large-scale residential redevelopment (`개포1동`, `반포본동`, `잠실6동`, `둔촌1동`, `고덕2동`, `항동`), where the housing stock is demolished and quarterly sales collapse, and the COVID tourism collapse in the central business district (`명동`, `회현동`, `소공동`). Neither mechanism is population aging.

The same redevelopment shock also drives the panel's only missing data: `둔촌1동` lacks 24 of 25 quarters of vitality and `항동` lacks 8, which is why the SPDM balanced-sample rule reports `n_units` of 423 or 424 for some outcomes.

Because these are real events, the policy is retained rather than replaced by a trimming rule. What the design owes the reader instead is the sensitivity, which [03_run_influence_robustness.R](../../02_Code/04_robustness/03_run_influence_robustness.R) produces: leave-one-dong-out influence on the exposure coefficient, and re-estimation without the tail and the most influential dongs. Its results must accompany any main-text claim about `vitality_sub_temporal` in particular.

### 2.10 [01_build_spatial_weights.R](../../02_Code/02_esda/01_build_spatial_weights.R): Spatial Weights Matrix Construction

This step constructs the common spatial contract using the 2020 base Seoul administrative dong boundaries.

- main W: `Queen`
- robustness W: `Rook`, `kNN6`, `kNN8`

All models and map visualizations must share the same `adm_cd` ordering and same-boundary contract.

### 2.11 [02_run_esda.R](../../02_Code/02_esda/02_run_esda.R): Quarterly Spatial Diagnostics

ESDA is the stage to confirm the presence of spatial patterns before estimating models.

- Distribution maps, LISA, bivariate LISA, and global bivariate Moran are computed on the latest quarter cross-section. Global Moran's I is computed for **every quarter** of the active window; EHSA uses the full sequence by construction.
- Global Moran's I uses a reproducible permutation p-value, and alternative W sensitivity is calculated the same way.
- **Levels and within, side by side.** `global_morans_i_within.csv` reports Moran's I on the levels and on the two-way within transform for every variable-quarter. The reason is that the estimators identify from within-dong, within-quarter deviations, so autocorrelation that lives only in the cross-sectional levels is removed by the fixed effects before estimation and cannot on its own motivate a spatial model. Over the 25 quarters the level scale is significant in 175 of 175 variable-quarters against 102 for the within scale, and the split is asymmetric: the exposures keep their spatial structure (`age60_resident_share` 92% of quarters, `age60_floating_share` 96%) while the outcomes largely lose it (`vitality_sub_economic` 64%, `vitality_sub_social` 44%, `vitality_sub_stability` 8%). That asymmetry is why the surviving SPDM spillovers run through `W X` rather than `W y`, and it is also why the TWFE residual Moran is near zero.
- **Multiplicity.** LISA performs one test per dong, so about `alpha * n` rejections are expected under the null before any real cluster exists. Local and summary tables carry the Benjamini-Hochberg `p_value_fdr`, `significant_fdr`, `cluster_fdr`, and `n_expected_by_chance` beside the uncorrected columns. Cluster counts quoted as findings must be the corrected ones.
- Permutation counts live in `config.R`, not in the script. LISA and bivariate use 9,999 rather than the previous hard-coded 499, whose two-sided p-value floor of 0.004 made a Bonferroni threshold for 425 tests unreachable by construction.
- LISA quadrants are classified based on the signs of `z(x)` and `W z(x)` for univariate, and `z(x)` and `W z(y)` for bivariate cases.
- Bivariate LISA maps are generated for all combinations of `age60_resident_share`/`age60_floating_share` and the vitality indicators.
- EHSA is calculated using the quarterly sequence. Following the Gi* convention in `sfdep::emerging_hotspot_analysis()`, EHSA uses `queen_include_self` weights that include self-neighbors in the queen contiguity.
- Key variables are `age60_resident_share`, `age60_floating_share`, `vitality_sub_*`, and `vitality_index_base`.

### 2.11A [03_run_exploratory_diagnostics.R](../../02_Code/02_esda/03_run_exploratory_diagnostics.R): Functional Form and Temporal Shape

Two exploratory questions the spatial ESDA does not address, both run by default.

- **Functional form.** Every active model enters `lag4_age60_resident_share` linearly over an exposure ranging from about 0.11 to 0.49, and that assumption had never been inspected. `exposure_response_bins.csv` bins the exposure into equal-count bins on the two-way within transform and reports the mean outcome per bin; `exposure_linearity_tests.csv` tests the linear specification against a quadratic term and, separately, against bin dummies, the latter making no assumption about the form of the departure.
- **Temporal shape.** `outcome_quarterly_trend.csv` and its figure report the cross-sectional mean, median, p10, p90, and standard deviation of each outcome by quarter with the `covid_period` flag attached. A 25-quarter window containing the COVID shock warrants more than the single sales-trend figure the reporting layer previously produced.

Both are diagnostics. A rejected linearity test is an input to a modelling decision recorded in [decision_log.md](../03_Log/decision_log.md), not an automatic respecification.

### 2.12 [01_run_twfe_main.R](../../02_Code/03_models/01_run_twfe_main.R): Quarterly TWFE Baseline

TWFE provides non-spatial baselines and residual Moran diagnostics.

- Input: `panel_main.parquet`, `W_queen.rds`
- Base specification: `y_it ~ lag4_age60_resident_share + lag4_controls_it | adm_cd + yq`
- Standard Errors: `cluster = ~ adm_cd` is the primary contract. `twfe_main_models.csv` additionally carries `std.error_twoway` and `p.value_twoway` from clustering on `adm_cd + yq`, because clustering on the dong alone absorbs within-dong serial correlation but nothing about contemporaneous correlation across dongs in the same quarter, which is difficult to defend in a project premised on spatial dependence. Two-way clustering inflates the standard errors by 6% to 32% and changes no conclusion at the 5% level on this panel, which is why it is reported beside the primary rather than replacing it.
- Residual serial correlation: `twfe_main_diagnostics.csv` reports `resid_ar1`, the AR(1) coefficient of the within-transformed residuals inside each dong. It runs between `0.61` and `0.81` with p-values below `1e-170` for every outcome. This does not invalidate the estimates, since dong clustering is valid under arbitrary within-dong dependence, but it states how much dependence the clustering is absorbing and makes clear that any independent-error specification would be badly wrong.
- Global multicollinearity: `max_vif_within` and per-term `vif_within_terms`, computed on the two-way within transform because that is the design the estimator inverts. The realized maximum is `1.17`, so collinearity among the global regressors is negligible.
- Dependent Variables: `vitality_sub_*`, `vitality_index_base`

Required outputs are as follows:

- `twfe_main_models.csv`
- `twfe_main_controls_used.csv`
- `twfe_main_diagnostics.csv`
- `twfe_main_residual_moran.csv`
- `twfe_main_residual_moran_by_yq.csv`

### 2.12A [04_run_identification_diagnostics.R](../../02_Code/04_robustness/04_run_identification_diagnostics.R): Identification Diagnostics

The 4-quarter lag is justified in the design as avoiding simultaneous response. A lag imposes temporal ordering, but ordering is not identification. This step measures whether the lag actually separates an aging effect from a dong-level trend, and it runs by default.

- **Exposure persistence.** `age60_resident_share` is close to a deterministic within-dong linear trend: median absolute correlation with `quarter_index` of `0.993`, above `0.9` in `85.4%` of dongs, over a median within-dong range of `5.76` percentage points. Under two-way fixed effects the identifying variation is therefore differential trend slope.
- **Placebo lead.** A 4-quarter lead of the exposure is built in-script, never written to `panel_main`, and entered in place of the lag. Under a causal reading the lead should not perform; it performs at least as well for `vitality_sub_economic` (p = .032) and `vitality_sub_social` (p = .011). In a horse race the lag collapses for `vitality_sub_economic`, from `-0.961` to `-0.212` (p = .639). The two are separable enough for this to be informative: their within correlation is `0.674`, a variance inflation factor of `1.8`.
- **Dong-specific trends.** Adding `adm_cd[quarter_index]` absorbs the differential-trend variation. Only `vitality_index_base` survives. `vitality_sub_social` falls from `-1.840` (p < .001) to `-0.607` (p = .248).

The consequence for the design is stated in [research_plan.md section 3.1](research_plan.md): H1 is tested as a conditional association, not a causal effect. The step changes no specification.

### 2.13 [02_run_spdm_main.R](../../02_Code/03_models/02_run_spdm_main.R): Quarterly SPDM Main Model

SPDM is the main global model of the active design.

- Input: `panel_main.parquet`, `W_queen.rds`
- Main exposure: `lag4_age60_resident_share`
- Specification: `y_it = rho W y_it + X_it beta + W X_it theta + adm_cd FE + yq FE + e_it`
- Implementation: `W lag4_age60_resident_share` and `W controls` are manually generated by `yq`, and estimated using `splm::spml(lag=TRUE, spatial.error="none", model="within", effect="twoways")`.
- Main output: `direct / indirect / total effects`
- Impact: Uses true SDM matrix impacts based on `S = (I - rho W)^(-1)` and `S(beta I + theta W)`.
- Standard Errors: Coefficients and spatial parameters use model-based asymptotic ML `vcov` from `splm::spml()`, and impact SEs/CIs are computed via simulation from the same `vcov`. This output is reported as model-based inference, not robust SEs. A reduced-form dong-level wild bootstrap returns `0.92` times the model-based standard error for `vitality_sub_social`, so the model-based figure is not understated; what it is conditional on is the error structure the model assumes, and that structure contains no time-dimension dependence even though the TWFE residuals on the same panel have an AR(1) coefficient of `0.61` to `0.81`. See [04_model_spec.md section 5](../02_Codebook/04_model_spec.md).
- Estimator caveats: `splm::spml()` applies no Lee-Yu bias correction and offers none, and it maps panel rows to the weights matrix by position without checking the mapping. `assert_spdm_panel_alignment()` therefore verifies the row order of every period against the `listw` `region.id` immediately before each fit; sorting this panel alphabetically instead, which differs from `region.id` for 393 of 425 dongs, moves `rho` by 21% and `theta` by a factor of 2.3 with no error raised.
- Sample rule: each outcome-control specification is reduced to complete cases, and only dongs observed in every remaining quarter are kept, so the estimation panel is strictly balanced. A specification is accepted only if at least 20 dongs and at least `SPDM_MIN_PERIODS` quarters survive; the default of 20 is a floor on the length of the balanced panel, not a per-dong observation count. This is why `n_units` differs across outcomes (423 to 425) instead of always equalling 425, and the realized dimensions are logged per outcome in `spdm_main_models.csv` and `spdm_impacts.csv`.

Core outputs are as follows:

- `spdm_main_models.csv`
- `spdm_impacts.csv`
- `spdm_controls_used.csv`
- `spdm_main_diagnostics.csv`

### 2.14 [07_run_spdm_channel_path.R](../../02_Code/80_optional/spdm/07_run_spdm_channel_path.R): Optional SPDM Channel Path Sidecar

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

### 2.15 [01_run_spdm_w_robustness.R](../../02_Code/04_robustness/01_run_spdm_w_robustness.R): W Sensitivity Check

This step iteratively estimates the same resident-only quarterly SDM contract across `queen`, `rook`, `knn6`, and `knn8`. Its purpose is to check sensitivity to the choice of W matrix.

### 2.16 [05_run_spdm_family_comparison_sidecar.R](../../02_Code/80_optional/spdm/05_run_spdm_family_comparison_sidecar.R): Spatial Family Comparison

This step is a manual sidecar for the appendix. It reconstructs the exact quarterly Queen sample and selected control contract of the main SPDM, then compares `TWFE`, `SLX`, `SAR`, `SDM`, `SEM`, `SDEM`, `SARAR/SAC`, and `GNS` under identical conditions. The effects for `SLX` and `SDEM` are reported as `W X` effects without the endogenous `W y` feedback multiplier, saved as `direct=beta`, `indirect=theta`, and `total=beta+theta`. `GNS` is the most general appendix sensitivity family incorporating `W y`, `W X`, and spatial errors, with its average effects recorded via the SDM matrix impact method.

### 2.17 [03_run_gtwr_main.R](../../02_Code/03_models/03_run_gtwr_main.R): Optional Quarterly Local Sidecar

GTWR main is a quarterly resident-only local sidecar.

> **Parameter values are contracted elsewhere.** Bandwidth, kernel, `lamda`, angle parameter, control set, and the local VIF warning threshold live in the authoritative table at [04_model_spec.md section 7.0](../02_Codebook/04_model_spec.md); section 7.1 there records how the currently published GTWR outputs differ from that contract. This section describes how the step is executed, not what the parameters are set to.

- Execution Condition: Direct execution of [03_models/03_run_gtwr_main.R](../../02_Code/03_models/03_run_gtwr_main.R)
- Inputs: `panel_main.parquet`, 2020 base Seoul administrative dong boundaries
- Interpretation level: Local heterogeneity description of the **levels** relationship. GTWR carries no fixed effects while TWFE and SPDM are within estimators, and on this panel the published local mean matches the levels-OLS sign for 5 of 5 outcomes and the within sign for 1. The local surface is therefore not a decomposition of the global effect and must not be narrated as one; see [04_model_spec.md section 7Z.1](../02_Codebook/04_model_spec.md).
- Local inference: `GWmodel::gtwr()` returns `<var>_SE` and `<var>_TV` per estimation point. These are extracted into `estimate_se`, `estimate_t`, `estimate_p`, and a Benjamini-Hochberg flag across dongs, because the dispersion of a local coefficient field is not evidence of a varying relationship until it is separated from the sampling noise of many small local fits. They are conditional on the bandwidth and come from overlapping windows, so they screen rather than prove. The published outputs predate this extraction and carry none.
- Execution method: Computations run per outcome-exposure spec, utilizing parallel workers up to `GTWR_PARALLEL_SPECS`.
- Resumption method: Per-spec RDS caches are saved to `03_Output/04_Logs/gtwr_spec_cache/<control_set>/main/`, and if interrupted and restarted, valid completed specs are reused.
- Control set: selected by `GTWR_CONTROL_SET`. `lean` uses the resident-population and land-price controls only; `extended` adds the transit accessibility composite and the workplace worker population. The member variables of each set are listed in [research_plan.md section 6.3](research_plan.md).
- Bandwidth strategy: Main GTWR uses a fixed adaptive bandwidth, so under `adaptive=TRUE` the bandwidth counts spatiotemporal neighbours around each estimation point rather than a metric radius. `full_panel_bw_gtwr` and `anchor_quarter_bw_gtwr` searches are only performed in [06_select_gtwr_bandwidth.R](../../02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R), and the selected results are saved to `gtwr_bandwidth_selection_<control_set>.csv` and the bandwidth cache; they are never injected into the main run. [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R) applies `GTWR_BANDWIDTH_SENSITIVITY_GRID` iteratively to the same outcome-control-spec, saving beta correlations against the contracted baseline, absolute changes, sign flips, and local collinearity diagnostic shifts to `gtwr_bandwidth_sensitivity_<control_set>.csv`.
- Lamda sensitivity: Executed exclusively in [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R). It re-estimates GTWR applying each value in `GTWR_LAMDA_SENSITIVITY_GRID` to the same outcome-control-spec, logging correlations, absolute changes, sign flips, and local collinearity diagnostic shifts against baseline latest-quarter betas to `gtwr_lamda_sensitivity_<control_set>.csv`.
- Local collinearity diagnostics: Three measures are computed per estimation point from the same GTWR spatiotemporal weights. `local_vif_max` is the largest weighted variance inflation factor, following the weighted-correlation convention `GWmodel::gwr.collin.diagno()` uses for its own local VIFs. `local_cn_centered` is the condition number of the weighted, centered local design. `local_cn_gtwr` follows the uncentered `local_CN` calculation convention of `GWmodel::gwr.collin.diagno()`. The warning flag is raised when `local_vif_max >= GTWR_LOCAL_VIF_WARN_THRESHOLD`. `local_cn_centered` and `local_cn_gtwr` are reported without thresholds: no established cut-off exists for a condition number computed on a centered design, and Belsley's 30 applies to the uncentered construction that `local_cn_gtwr` implements. The uncentered measure conditions on the local intercept as well as the predictors, which is why it is large here. Until the pending rerun, these three columns exist only in `gtwr_collin_diag_backfill_<control_set>.csv`; the published `gtwr_local_coefficients_<control_set>.csv` and the `collinearity_warn_share` of `gtwr_main_models_<control_set>.csv` predate this schema.
- Kernel and angle parameter: the weighting kernel is set by `GTWR_KERNEL` and applied to the combined spatiotemporal distance, with `bisquare`, `gaussian`, `exponential`, `tricube`, and `boxcar` accepted. `GTWR_KSI` is the angle parameter of the Huang et al. (2010) distance and is held at its default everywhere except the experiment sidecar, so the interaction term enters at full weight. Both are required reporting items wherever GTWR results are presented.
- Spatiotemporal distance: Built directly by `build_gtwr_st_dmat()` rather than by `GWmodel::st.dist()`, and passed to `bw.gtwr()` and `gtwr()` as `st.dMat`. `GWmodel::ti.distv()` compares observation times with `as.character()`, so the integer period ids this panel uses make `"25" >= "3"` false and assign a 1e50 "future" distance to genuinely past quarters. The project therefore supplies the symmetric temporal distance `|t_i - t_j|` of Huang et al. (2010) and never lets GWmodel reach `ti.distm()`; a fit or bandwidth search that would have to rebuild the matrix internally is refused rather than silently run on corrupted weights.
- Dimensionless `lamda`: the spatial and temporal distances are divided by their own observed spans before being combined, so `lamda` is the share of weight placed on the full spatial extent and the midpoint weights space and time equally. `GWmodel::st.dist()` combines raw units instead, which folds the metre-versus-quarter scale gap into the parameter: on this panel space spans 338-33,772 metres against 0-24 quarters, so the previous raw-unit `lamda` of `0.05` corresponds to roughly `0.987` here, about 76:1 in favour of space. `GTWR_LAMDA_SENSITIVITY_GRID` spans the dimensionless range with interior points, so the criterion can be bracketed rather than pinned at a grid boundary as it was under the raw-unit grid. Lamda values recorded before 2026-09-02 follow the raw-unit convention and are not comparable with later ones.

The core operational principles for GTWR are:

1. Only quarterly samples are used.
2. The main control pool is selected via `GTWR_CONTROL_SET`. The default `lean` uses only resident population scale and land price controls, while `extended` adds transit accessibility composites.
3. The main bandwidth is unified to the fixed adaptive value contracted in [04_model_spec.md section 7.0](../02_Codebook/04_model_spec.md). `bw.gtwr()` searches (full-panel or anchor-quarter), fixed bandwidth grid sensitivities, and lamda grid sensitivities are strictly separated into [06_select_gtwr_bandwidth.R](../../02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R), [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R), and [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R) respectively.
4. Main raw/output surfaces are constructed based on latest-quarter local betas. That quarter is the temporal edge of the kernel: the own-dong support falls by about 40% and becomes entirely backward-looking, and the reported mean local coefficient lies outside the range of the other 24 quarters for three of five outcomes. Latest-quarter results are reported as edge estimates, and an earliest-to-latest change is not claimed from two mirror-image edges.
4a. At the contracted angle parameter the spatiotemporal distance collapses to a perfect square, so only about 7% of the window is genuinely spatiotemporal against 82% at the focal quarter. The specification is close to a stack of per-quarter GWRs with a thin own-dong temporal thread, and that has to be stated wherever the results are presented.
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
- [09_backfill_gtwr_collin_diag.R](../../02_Code/80_optional/gtwr/09_backfill_gtwr_collin_diag.R): Direct execution recomputes the three local collinearity diagnostics for already-estimated specs without refitting, reporting each under both the legacy string-comparison and the symmetric time distance, and gating on reproduction of the stored `local_cn_gtwr_latest`. Writes `gtwr_collin_diag_backfill_<control_set>.csv`.
- [11_diagnose_gtwr_estimand.R](../../02_Code/80_optional/gtwr/11_diagnose_gtwr_estimand.R): Direct execution establishes what the local surface estimates and what its kernel averages over, without refitting. Compares a levels OLS, the two-way within estimator, and the published local mean on one sample; classifies the bandwidth-nearest window as same-quarter, same-dong, or genuinely both-different at the contracted angle and at the right angle; and reports the kernel's own-dong support at every focal quarter beside whether the reported quarter's published mean is typical of the others. Writes `gtwr_estimand_comparison_<control_set>.csv`, `gtwr_kernel_geometry_<control_set>.csv`, and `gtwr_temporal_edge_<control_set>.csv`.
- [10_search_gtwr_lamda_bw_cv.R](../../02_Code/80_optional/gtwr/10_search_gtwr_lamda_bw_cv.R): Direct execution runs a leave-one-out CV search over the lamda and bandwidth grids without fitting GTWR, on a seeded focal subsample of a common complete-case sample. Writes `gtwr_lamda_bw_cv_search_<control_set>.csv`. It is a search tool: the reported bandwidth still comes from `06_select_gtwr_bandwidth.R` and the active contract, and the output flags whether an optimum sits on a grid edge.
- [01_make_tables_figures.R](../../02_Code/05_reporting/01_make_tables_figures.R) derives latest-minus-earliest delta summaries/rankings whenever sidecar raw local coefficients are present.

### 2.18 [02_run_robustness.R](../../02_Code/04_robustness/02_run_robustness.R) and Reporting

[02_run_robustness.R](../../02_Code/04_robustness/02_run_robustness.R) checks outcome-definition, sample-window, and W-Moran sensitivities against the quarterly contract. [01_make_tables_figures.R](../../02_Code/05_reporting/01_make_tables_figures.R) bundles tables and figures for the main text/appendices, and additionally publishes Pearson correlation matrices and pairwise correlation tables for main analysis variables. Reporting selectively attaches optional artifacts only when source inputs exist.

### 2.19 [03_run_influence_robustness.R](../../02_Code/04_robustness/03_run_influence_robustness.R): Influence Robustness

This step measures how much of each reported effect rests on individual administrative dongs, and it runs by default rather than on request.

- Primary measure: leave-one-dong-out `dfbeta` on the TWFE exposure coefficient, one refit per dong per outcome, about two minutes for the five outcomes. It re-estimates TWFE rather than the SPDM main because several hundred refits are tractable under TWFE and are not under SPDM, where a single five-outcome run takes roughly eleven minutes; TWFE shares the exposure and control contract and is the declared diagnostic layer.
- Secondary measure: the outcome-tail listing and the percentage by which tail dongs inflate the pooled standard deviation, which is the unit every "per standard deviation" coefficient is quoted in.
- Three exclusion variants per outcome, `tail`, `top_k`, and `union_tail`, each recording sign flips and changes in 5% significance.
- Outputs: `influence_dfbeta.csv`, `influence_outlier_dongs.csv`, `influence_robustness_summary.csv`.

**Why it is canonical.** The 2026-09-04 decision is to keep the full sample as the main specification rather than excluding shocked districts, because redevelopment and the COVID collapse of the central business district are real events rather than data errors, and excluding them would introduce a sample definition chosen after seeing the results. That decision is only defensible if the reader can see which effects depend on a handful of districts, so the diagnostic is not an optional check that may or may not be current; it must be produced by the same run that produces the impacts it qualifies. `influence_robustness_summary.csv` belongs in the main text with the effects, and the per-dong `influence_dfbeta.csv` in the appendix. The specific reading requirement, including which dimensions the current evidence does and does not support, is in [04_model_spec.md section 6A.1](../02_Codebook/04_model_spec.md).

### 2.20 [05_run_evidence_synthesis.R](../../02_Code/04_robustness/05_run_evidence_synthesis.R): Evidence Synthesis

Sections 2.11A, 2.12A, 2.19 and the standard-error and specification checks of 2.12 and 2.13 each report a survivable result on their own: two or three of the five outcomes come through every time. The outcomes that come through are not the same ones each time. This step computes the intersection, which is what a main-text claim actually has to clear.

- It estimates nothing. It reads the published diagnostic tables and cross-tabulates nine gates over five audits against the five reported outcomes, recording per gate the source table and the statistic behind the verdict.
- The modification time of every source is carried into `evidence_synthesis.csv`, so a synthesis computed over stale diagnostics is visible rather than silent.
- Each gate carries a `role` tag and each outcome a `claim_tier`. The tier names a kind of claim, not a quality ranking; `n_gates_passed` travels beside it so a reader who weighs the gates differently need not accept the rule.
- A gate that no outcome passes is reported as a design-level failure, because that limitation cannot be answered by choosing a different outcome.
- Outputs: `evidence_synthesis_gates.csv`, `evidence_synthesis.csv`, `evidence_synthesis_matrix.png`.

**What the first run establishes.** No outcome passes all nine gates; the best passes six. `lag_beats_lead` fails for all five, which makes it a property of the design: entered against the 4-quarter lead, the lag is not significant for any outcome, and the two are separable (within correlation `0.674`, VIF `1.8`). `vitality_index_base` is `descriptive_only` — it alone survives dong-specific trends, but loses 5% significance when nine union-tail dongs are dropped. `vitality_sub_social` is `conditional_association` — a stable magnitude that fails all three identification gates. The remaining three are `not_supported`, their baseline not being significant under the control contract. The full reading requirement is in [04_model_spec.md section 6C.1](../02_Codebook/04_model_spec.md).

### 2.21 [04_build_test_inventory.R](../../02_Code/06_qc/04_build_test_inventory.R): Published Test Inventory

The main text rests on 15 exposure-side tests; the published tables carry 405. Nothing in the project counted them and no table carried an adjusted p-value, so a reader had no way to see how large the search was behind any one appendix result.

- Reads published tables only; estimates nothing and re-fits nothing.
- Excludes control terms and spatial nuisance parameters, which nobody claims anything about.
- Applies Benjamini-Hochberg within each table and across the whole published surface. The families share a panel, an exposure and a control contract, so this is a conservative summary of search size, not an exact error rate.
- Outputs: `model_test_inventory.csv`, `model_test_inventory_adjusted.csv`.

The first run gives 277 unadjusted rejections against 267 under BH, with the main-text count unchanged at 11. The appendix is not a field of marginal p-values; the substantive concerns about those families are timing and collinearity (section 2.22) and the channel-path resample ([04_model_spec.md section 5A.1](../02_Codebook/04_model_spec.md)), not the count. Full reading requirement in [04_model_spec.md section 6D.1](../02_Codebook/04_model_spec.md).

### 2.22 Optional Sidecar Contracts Worth Stating

Three properties of the appendix families are not visible from their variable names and are required reading with their results.

- **Age-mix timing.** The TWFE and SPDM age-mix families enter contemporaneous exposures (`ln_young_resident_pop`, `ln_middle_resident_pop`, `ln_old_resident_pop`) alongside 4-quarter-lagged controls. The main design lags the exposure to avoid simultaneous response; this family does not. The sector-share family is also contemporaneous, and that is stated in its own contract.
- **Age-mix collinearity.** The three log age-group populations move together within a dong: within VIFs of `9.08`, `17.75` and `10.37` against `1.17` for the main TWFE design. `max_vif_within` and `vif_within_terms` are now recorded in both age-mix diagnostics tables. Dropping the same-domain total control does not fix it, so it is a property of the family rather than of the control contract.
- **Weights alignment.** `01_run_spdm_interaction_models.R`, `03_run_spdm_sector_share_experiment.R` and `07_run_spdm_channel_path.R` call `splm::spml()` directly. Their unit ordering is correct because `keep_ids` comes from `intersect()` against `region.id`, but `splm` maps rows to weights by position and raises nothing when the two disagree, so all three now assert alignment before every fit as the main path does.

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
