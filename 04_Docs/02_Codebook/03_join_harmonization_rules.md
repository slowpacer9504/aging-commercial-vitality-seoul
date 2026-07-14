# Join/Harmonization Rules

## 1) Basic Join Keys

- Panel keys: `adm_cd`, `yq`
- Quarterly join: `adm_cd`, `yq`
- Year/as-of join: aggregate by `adm_cd`, `year` and then join to the `adm_cd`, `yq` panel
- Static join: `adm_cd`

## 2) Spatial Standards

- All analysis units are based on 2020 Seoul administrative dongs (`adm_cd`).
- Spatial weights and map visualizations use the same boundaries.
- `adm_region_lookup.parquet` is a static lookup that reads the `adm_cd` and administrative dong names of the 2020 boundaries, combined with the 5 major regional zones in Seoul using the 6-digit prefix of the `adm_cd` (autonomous district).
- No additional cross-year boundary reconciliation steps are included.

## 3) Seoul Commercial District Raw Quarterly Publication

- Quarterly sources from the Seoul commercial district raw data are directly published based on `adm_cd-yq`.
- Additive flows use quarterly totals, while levels/shares use quarterly representatives or denominator-weighted quarterly proportions.
- Temporal/stability components are calculated using the quarterly cross-section and the rolling 4-quarter distribution.
- Yearly/static sources are aggregated by `adm_cd-year` or `adm_cd`, specifying source precision, and joined using the quarter-end as-of rule.
- After the active base publication, only the standard time keys `year`, `quarter`, `yq`, and `quarter_index` remain.
- The canonical quarterly base is `seoul_quarter_base.parquet`.

## 4) Auxiliary Covariate Harmonization

- [03_build_auxiliary_covariates.R](../../02_Code/01_preprocess/03_build_auxiliary_covariates.R) processes auxiliary public-data sources into `adm_cd-year`, `adm_cd`, or record-level pre-aggregation units and publishes them to fit the `adm_cd-yq` panel.
- Official land prices are preserved as original annual values after creating administrative dong-year area-weighted averages based on representative parcel points.
- The Korea Real Estate Board's monthly regional land price index is matched 1:1 with Seoul's legal dong boundaries using legal dong names. An administrative dong quarterly adjustment factor, `land_price_lpi_factor`, is then created using an area-weighted crosswalk of legal dong-administrative dong spatial intersections. The final active land price control variables are `land_price_adjusted` (annual official land price multiplied by this adjustment factor) and its log, `ln_land_price_adjusted`.
- Seoul business establishment statistics by worker size and dong are matched by administrative dong name to the 2020 `adm_cd` to create `workplace_worker_population.parquet`, which is then joined to `aux_covariates_lag_support`. Differences in dot notations (`.`/`·`) are normalized. `상일1동` and `상일2동` are aggregated into the 2020 `상일동`, and `개포3동` is mapped to the 2020 `일원2동`. For `항동` from 2018-2019, the pre-division values of `오류2동` are distributed using the 2020 worker ratio between `오류2동` and `항동`. For 2025, the 2024 observations are carried forward.
- Public transit sources are published by `adm_cd-yq`. Bus stop counts repeat single-year snapshots, take the quarter-end latest from monthly snapshots, and record carry-forward status in QC. Subway station counts are calculated based on the opening date rule `open_date <= quarter_end`.
- Medical, large-scale store, and senior sources retain a record-level pre-aggregation layer, but only the quarterly as-of counts or status are reflected in the active panel.
- The walk-environment cache is managed as an `adm_cd` static layer.

## 5) Shared Panel Build

- [01_build_living_population_inflow.R](../../02_Code/80_optional/preprocess/01_build_living_population_inflow.R) publishes `living_population_external_inflow.parquet` from monthly ZIP files of Seoul living population internal migration and metropolitan area domestic/foreign inflows.
- Internal migration only uses rows where the destination administrative dong's district differs from the residence district. Metropolitan area data uses all rows as external inflow.
- Since living population is a point-in-time count, day-time rows are not accumulated; instead, an `adm_cd-month` average point-in-time population is calculated. The monthly averages within the same quarter are then averaged again and joined as `adm_cd-yq` values.
- If the number of ZIP members for a given month is insufficient, the monthly average of observed days is used as the representative value for that month. This is tracked using `month_success_days`, `month_expected_days`, and `month_coverage_flag` in `living_population_inflow_manifest.csv`.
- [04_build_golmok_survival_rate.R](../../02_Code/01_preprocess/04_build_golmok_survival_rate.R) publishes `golmok_survival_rate.parquet` from the `selectSurvivalRate.json` response of the Seoul commercial district analysis service.
- New enterprise survival rates are reconstructed as-of into administrative dong-quarter rows using a 3-year block based on Q4 requests for reference years `2019`, `2022`, and `2025`. `survival_3y` is used in the active stability sub-index.
- Administrative dong-quarters where the survival rate cohort denominator is 0 are not arbitrarily imputed but kept as missing values and recorded in `golmok_survival_rate_qc.csv`.
- [05_build_registered_resident_population.R](../../02_Code/01_preprocess/05_build_registered_resident_population.R) publishes the active `registered_resident_population.parquet` and the 2018Q1-2025Q4 `registered_resident_population_lag_support.parquet` from the Ministry of the Interior and Safety's monthly resident population CSVs by 5-year age groups.
- Resident population matches administrative dong names with the 2020 `adm_cd` boundaries. Changes such as divisions and renamings during the analysis period are standardized to the 2020 baseline (e.g., `상일제1동 -> 상일동`, `강일동+상일제2동 -> 강일동`, `개포3동 -> 일원2동`, 2025's `신설동+용두동+용신동 -> 용신동`).
- The monthly stock of registered resident population is aggregated into a quarterly average, while the elderly proportion is joined as a denominator-weighted quarterly proportion.
- Since `항동`, which split from `오류제2동` in 2020, was included in `오류제2동` from 2018-2019, the original 2018-2019 `오류제2동` values are distributed using the same month/age group proportions of the 2020 `오류제2동`/`항동`. These division-distributed rows are tracked with `registered_boundary_proxy_flag` and `registered_boundary_proxy_reference_year`.
- [06_build_analysis_panel.R](../../02_Code/01_preprocess/06_build_analysis_panel.R) merges `seoul_quarter_base`, `aux_covariates`, `living_population_external_inflow`, `golmok_survival_rate`, and `registered_resident_population` based on `adm_cd`, `year`, `quarter`, `yq`, and `quarter_index`. It also creates the registered 4-quarter and 2-quarter lag variables from the lag-support layer.
- The results immediately after joining are saved as `panel_merged_base.parquet`, and the results after shared derivation are saved as `panel_main_pre_vitality.parquet`.
- Quarter-overlapping variables are removed from the active contract.

## 6) Shared Derived Transforms

- Shared quarterly transforms are calculated after sorting by `quarter_index` within the `adm_cd` group.
- The active shared panel retains only concurrent source variables and registered lag variables; legacy shift/lead derived columns are not published.
- Shared derived variables such as `store_density` are calculated at the `panel_main_pre_vitality` stage.
- [07_build_vitality_index.R](../../02_Code/01_preprocess/07_build_vitality_index.R) publishes the final `panel_main.parquet` and `vitality_components.parquet`.

## 7) Model-side Contract

- `panel_main.parquet` is the common input for all active models.
- The appendix sidecar also starts from the same `panel_main` contract.
- The time FE of TWFE uses `yq`, and the panel time index of SPDM is also a `time_id` based on `yq`.
- GTWR is a quarterly resident-only local sidecar.

## 8) Join Failure Policies

- `FAIL`
  - Missing essential keys/inputs
  - Violation of quarterly publication/as-of rules
  - Detection of negative structural counts
  - Inability to generate core outputs
- `WARN`
  - Coverage degradation
  - Source-specific partial missing
  - Missing optional auxiliary variables
- `MANUAL`
  - Full processed parquet audit
  - Interactive output review
