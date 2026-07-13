# Data Specification

## 1) Hierarchical Structure

- Raw: `01_Data/01_Raw_Data`
- Boundary: `01_Data/02_Boundary`
- Intermediate: `01_Data/03_Processed_Data/01_Intermediate`
- Analysis Ready: `01_Data/03_Processed_Data/02_Analysis_Ready`
- Panel: `01_Data/03_Processed_Data/03_Panel`
- Outputs: `03_Output/*`

## 2) Key Input Datasets

- Seoul Commercial Service
  - Core source for building the `2019Q1~2025Q4` quarterly panel.
  - Quarterly data is published directly at the `adm_cd-yq` level.
- Auxiliary Public Data
  - Structural variables including official land prices, transportation, medical facilities, large-scale retail stores, senior welfare facilities, and pedestrian environments.
- Seoul Business Worker Status by Administrative Dong
  - Total worker counts by administrative dong are mapped to the 2020 administrative boundaries to create a control variable for the workplace population.
  - For 2018–2019, the pre-division `Oryu 2-dong` values are allocated between `Oryu 2-dong` and `Hang-dong` based on their 2020 worker ratio. For 2025, the latest 2024 observation is carried forward.
- Seoul Living Population
  - External inflow population is derived from internal migration and the monthly metropolitan area ZIP records of domestic/foreign populations.
  - Since the living population is a snapshot count, we first compute the monthly average of the snapshot populations rather than an annual sum, then publish the quarterly average of those monthly averages.
  - For source ZIPs with insufficient days in a month, the observation-based monthly average is used as the representative value for that month, and the number of successful days along with a coverage flag is recorded in the manifest.
- Seoul Commercial Service Startup Survival Rate JSON
  - The 1-year, 3-year, and 5-year startup survival rates, along with their numerators and denominators, are collected from the website's `selectSurvivalRate.json` endpoint and published at the `adm_cd-yq` level.
  - The active stability sub-index utilizes the 3-year survival rate (`survival_3y`).
- MOIS Registered Resident Population
  - The residential population size and the share of the elderly population are calculated from the monthly administrative dong resident population CSVs aggregated by 5-year age groups.
  - Monthly population stocks are averaged over the quarter, and the elderly share is published as a denominator-weighted quarterly share.
  - Source administrative dong names are mapped to the 2020 Seoul administrative boundaries (`adm_cd`), with any district divisions or name changes standardized to the 2020 baseline.
- 2020 Seoul Administrative Dong Boundaries
  - The common baseline for spatial weight matrices and map visualizations.
  - The source baseline for the static `adm_cd`-dong-gu-living area lookup.

## 3) Key Analytical Datasets

- `seoul_quarter_base.parquet`
  - canonical short-run Seoul quarterly base
- `adm_region_lookup.parquet`
  - static lookup for administrative dong, gu, and 5 major living areas by `adm_cd`
- `aux_covariates.parquet`
  - auxiliary public-data integration layer by `adm_cd-yq`
- `aux_covariates_lag_support.parquet`
  - auxiliary lag-support layer for 2018Q1~2025Q4 by `adm_cd-yq`
- `workplace_worker_population.parquet`
  - annual as-of layer for workplace population/workers for 2018~2025 by `adm_cd-year`
- `land_price_lpi_bjd_adm_crosswalk.parquet`
  - area-weighted legal-to-administrative dong crosswalk converting legal dong land price indices to 2020 administrative boundaries
- `land_price_lpi_factor_adm_quarter.parquet`
  - Korea Real Estate Board land price index adjustment factor layer by `adm_cd-yq`
- `living_population_external_inflow.parquet`
  - Seoul living population external inflow layer by `adm_cd-yq`
- `golmok_survival_rate.parquet`
  - Seoul Commercial Service startup survival rate layer by `adm_cd-yq`
- `registered_resident_population.parquet`
  - residential population and elderly share layer based on MOIS registered population by `adm_cd-yq`
- `registered_resident_population_lag_support.parquet`
  - registered resident population lag-support layer for 2018Q1~2025Q4 by `adm_cd-yq`
- `registered_resident_population_monthly.parquet`
  - intermediate monthly registered resident population layer used for age-sum validation
- `medical_source_preagg.parquet`
- `mall_source_preagg.parquet`
- `senior_source_preagg.parquet`
- `bus_stop_source_preagg.parquet`
- `subway_station_source_preagg.parquet`
- `apartment_registry_source_preagg.parquet`
- `senior_geocode_cache.parquet`
- `medical_geocode_cache.parquet`
- `mall_geocode_cache.parquet`
- `apartment_geocode_cache.parquet`
- `walk_betweenness_local800_len_v1.parquet`
  - static walk-environment cache
- `panel_merged_base.parquet`
  - shared panel immediately following the merge of the quarter base and auxiliary covariates
- `panel_main_pre_vitality.parquet`
  - pre-vitality panel reflecting shared quarterly derivations and the registered model lag contract
- `panel_main.parquet`
  - final canonical panel with the vitality index appended
- `vitality_components.parquet`
  - vitality sub-index and composite component table
- `W_queen.rds`, `W_rook.rds`, `W_knn6.rds`, `W_knn8.rds`

## 4) Active QC Rules

- Key Duplication: 0 occurrences of duplicate `adm_cd x yq` keys
- Panel Construction Time Horizon: `2019Q1~2025Q4`
- Active Analysis Period: `2019Q4~2025Q4`
- Coordinate Reference System (CRS): `EPSG:5179`
- Retention of `year`, `quarter`, `yq`, and `quarter_index` in the active shared panel
- Quarterly Publication Rule Checks
  - `panel_quarter_aggregation_qc.csv` (`FAIL` if quarterly publication rules or coverage expectations break)
- Panel Merge Structure Checks
  - `panel_join_coverage_qc.csv` (`WARN`)
  - `panel_structural_count_flags.csv` (`FAIL` if structural counts are negative)
- Land Price Observation/Imputation Checks
  - `land_price_imputation_qc.csv` (`WARN`)
- Land Price Index Adjusted Official Land Price Checks
  - `land_price_lpi_raw_match_qc.csv` (`FAIL` if monthly land price index legal dong names fail 1:1 matching with legal dong boundaries)
  - `land_price_lpi_crosswalk_qc.csv` (`FAIL` if the 425 administrative dong coverage or the normalized weight sum is incorrect)
  - `land_price_lpi_adjustment_qc.csv` (`WARN` for quarterly adjustment factor and adjusted land price coverage)
- Workplace Population Alignment Checks
  - `workplace_worker_population_qc.csv` (`FAIL` if annual Seoul totals diverge or 425 administrative dong coverage is unmet; `WARN` for 2018~2019 `Hang-dong` backcasts and 2025 carry-forward counts)
- Seoul Living Population External Inflow Checks
  - `living_population_inflow_manifest.csv` (`WARN` for member-level processing logs and month-level coverage flags)
  - `living_population_inflow_qc.csv` (`WARN` for annual coverage and value ranges)
- Startup Survival Rate Checks
  - `golmok_survival_rate_qc.csv` (`WARN` for annual coverage, rate ranges, small cohort counts, and numerator/denominator recomputation diffs)
- Registered Resident Population Checks
  - `registered_resident_population_mapping_qc.csv` (`FAIL` if source administrative names fail to map to an `adm_cd`)
  - `registered_resident_population_qc.csv` (`FAIL` if 12-month coverage is incomplete, elderly share ranges are abnormal, or core variables are missing; `WARN` for dong division allocation counts)
- Vitality Index Component Checks
  - `vitality_component_qc.csv` (`WARN`, or `FAIL` if core index generation is impossible)
- Processed Output Integrity Checks (Manual)
  - `processed_parquet_inventory.csv`
  - `processed_parquet_schema.csv`
  - `processed_parquet_missing_summary.csv`
  - `processed_parquet_qc_checks.csv`
- Administrative Dong, Gu, and Living Area Lookup Checks
  - `adm_region_lookup_qc.csv` (`FAIL` if there is a mismatch in the 425 administrative dongs, 25 gu, 5 living areas, or the number of dongs per gu)

## 5) Optional Supplementary Surface

- interaction / age-mix / family-comparison appendix scripts
- `03_run_gtwr_main.R`, additional GTWR sidecars, GTWR bandwidth/lamda diagnostic scripts
  - manual direct-run local analysis only

The assets above are not mandatory contracts for the canonical default run, active QC, or active success criteria.

## 6) Manual QC & Interactive Review Helpers

- `02_check_processed_parquet_outputs.R`
  - A full parquet audit that reads all parquets under `03_Processed_Data` and generates an inventory, schema, missing summary, and QC checks.
  - Assesses the raw quarterly staging layer separately from the active quarterly publication layer.
- `03_open_outputs_for_rstudio_review.R`
  - An interactive review helper that does not persist any additional outputs.
