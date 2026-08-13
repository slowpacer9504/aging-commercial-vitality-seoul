# Variable Dictionary

## 1) Key Variables

- `adm_cd`
  - 10-digit administrative district (dong) code
- `year`
  - Year identifier
- `quarter`
  - Quarter identifier, `1` to `4`
- `yq`
  - Canonical year-quarter identifier, e.g., `2019Q1`
- `quarter_index`
  - Integer-based sequential quarter index starting from `2019Q1`
- `covid_period`
  - Appendix interaction flag indicating the `2020Q1~2022Q2` sample period

## 1A) Regional Reference Metadata

- `adm_nm`
  - Administrative district name (based on 2020 boundaries)
- `adstrd_nm`
  - Original source administrative district name aligned with 2020 boundaries
- `gu_name`
  - Autonomous district (Gu) name
- `living_area`
  - Name of the Seoul 5 major living zones
- `gu_prefix`
  - 6-digit prefix of `adm_cd` identifying the autonomous district

These variables are static metadata stored in `adm_region_lookup.parquet`. They are not used as explanatory variables in the models, but rather for mapping administrative district names for resident population data, summarizing GTWR results by region, performing QC, and generating reporting deliverables.

## 2) Core Independent Variables

- `main exposure`
  - `lag4_age60_resident_share` (4-quarter lag of `age60_resident_share`)
- `supporting exposure`
  - `age60_floating_share`
  - `age60_sales_share`
- `descriptive raw-scale support`
  - `age60_resident_share`
  - `age60_floating_share`
  - `age60_sales_share`
  - `ln_age60_sales_amount`

## 3) Dependent Variables

- `primary vitality outcomes`
  - `vitality_sub_economic`
  - `vitality_sub_social`
  - `vitality_sub_temporal`
  - `vitality_sub_stability`
- `supplementary composite`
  - `vitality_index_base`
- `robustness composites`
  - `vitality_index_entropy`
  - `vitality_index_pca`
- `ESDA support outcomes`
  - `ln_total_sales`
  - `ln_floating_pop`
  - `diversity_index`

## 4) Core Control Variables

- `lag4_ln_resident_pop`
- `lag4_ln_land_price_adjusted`
- `lag4_transit_accessibility`
- `lag4_ln_workplace_worker_pop`

These four variables serve as the baseline control candidate pool for TWFE/SPDM, corresponding to the 4-quarter lagged values of `ln_resident_pop`, `ln_land_price_adjusted`, `transit_accessibility`, and `ln_workplace_worker_pop`, respectively. The usable subset is finalized after checking for finite counts and multicollinearity.
`ln_land_price_adjusted` is a land price variable constructed by applying the quarterly average correction factor from the Korea Real Estate Board's monthly land price index to the annual official assessed land price.
`ln_workplace_worker_pop` is the log of the workplace worker population, mapped to 2020 administrative district boundaries using Seoul's administrative district-level statistics on the number of workers by establishment size.
Since `ln_floating_pop` is a component of social vitality, it is not used as a main control variable.
Variables like `ln_official_land_price`, `ln_apartment_household_count`, `hospital_count_aux_core`, and `mall_count_aux_core` are kept in the `panel_main` for diagnostic and supplementary purposes, but they are not used as active control variables in the TWFE/SPDM/GTWR models.

GTWR employs a separate control set.

- `lean`
  - `lag4_ln_resident_pop`
  - `lag4_ln_land_price_adjusted`
- `extended`
  - `lag4_ln_resident_pop`
  - `lag4_ln_land_price_adjusted`
  - `lag4_transit_accessibility`
  - `lag4_ln_workplace_worker_pop`

In the GTWR extended specification, instead of directly including `bus_stop_count_aux` and `subway_station_count_aux`, we use `lag4_transit_accessibility` (the standardized average of the two variables) along with `lag4_ln_workplace_worker_pop` (to control for workplace population size) as additional controls.
`bus_stop_count_aux` is based on mixed-frequency snapshot sources. For years with only a single snapshot (e.g., 2019, 2020, 2025), the snapshot value is repeated across all 4 quarters of that year. For the monthly snapshot period spanning from January 2021 to April 2024, the most recent snapshot available prior to the end of the quarter is used.
For `subway_station_count_aux`, the opening date rules are applied to the station master data, counting stations where `open_date <= quarter_end` for each quarter.

## 5) Appendix Sidecar Variables

- COVID interaction appendix
  - `covid_period`
- TWFE/SPDM resident age-population appendix
  - `ln_young_resident_pop`
  - `ln_middle_resident_pop`
  - `ln_old_resident_pop`
  - `lag4_ln_resident_pop` retained as lagged resident scale control
- GTWR age-band appendix
  - `age20_resident_share`
  - `age30_resident_share`
  - `age40_resident_share`
  - `age50_resident_share`
  - `age60_64_resident_share`
  - `age65_74_resident_share`
  - `age75plus_resident_share`
  - `age65plus_resident_share`
  - `age20_floating_share`
  - `age30_floating_share`
  - `age40_floating_share`
  - `age50_floating_share`

## 6) Design Principles

- The age threshold is unified to `60+` in the active design.
- The main exposure variable is `lag4_age60_resident_share`.
- The resident population size and the share of the elderly population are derived from the Ministry of the Interior and Safety's (MOIS) monthly resident registration data by 5-year age groups, not from the Seoul Commercial Area Analysis Service.
- The mediator for the optional SPDM channel path is `lag2_age60_floating_share`, with `age60_floating_share` and `age60_sales_share` serving as supplementary dimensions.
- The four `vitality_sub_*` sub-indices take precedence in reporting, while `vitality_index_base` serves as a supplementary composite index.
- For the optional SPDM channel path, the standalone `vitality_sub_social` indicator is excluded because its source overlaps with the mediator (floating population). However, the overall vitality index (`vitality_index_base`), which encompasses all four sub-dimensions, is still used.
- `vitality_sub_economic` is composed of the average of the pooled z-scores of `ln_sales_count` and `ln_total_sales`.
- The economic transaction scale dimension (`economic_transaction_scale`) uses the same components as the active economic sub-index: the average of the pooled z-scores of `ln_sales_count` and `ln_total_sales`.
- `ln_total_store_count` and `ln_sales_per_store` are retained in the panel but excluded from both the economic sub-index components and the reporting economic components.
- `vitality_sub_social` comprises the internal floating population scale (`ln_floating_pop`) and the external inflow population scale (`ln_external_inflow_pop`).
- `vitality_sub_temporal` consists of intraday time variance (`sales_time_entropy`, `floating_time_entropy`) and year-round quarterly stability (`sales_quarter_stability`, `floating_quarter_stability`).
- `vitality_sub_stability` is calculated as the equal-weighted average of the structural diversity dimension and the store persistence dimension.
- The structural diversity dimension is the pooled z-score of `diversity_index`.
- The store persistence dimension averages the pooled z-scores of `operating_months_rel_seoul` and the 3-year survival rate of new businesses (`survival_3y`).
- `closure_rate` and `stability_score = -closure_rate` are retained as supplementary variables for diagnosing closure pressure but are not included in the active structural stability sub-index.
- Component z-scores for the vitality indices and sub-indices are calculated as pooled z-scores based on the active analysis period (`2019Q4~2025Q4 adm_cd-yq` sample), rather than as quarterly cross-sectional z-scores.
- Since `ln_floating_pop` is a component of both `vitality_sub_social` and the composite vitality index, it is excluded from the main control candidate pool.
- The active shared panel retains only contemporaneous source variables and registered model lag variables.

## 7) Source Attribution Principles

- The definitive variable dictionary is `02_variable_dictionary.csv`, and the `raw_data_source` column records the original data sources upon which each variable depends.
- For variables based on the Seoul Commercial Area Analysis Service, the detailed original tables must be specified (e.g., street-level floating population, estimated sales, stores, commercial area change indicators, apartments).
- For variables based on MOIS resident registration data, include references to the monthly resident population by 5-year age groups, the administrative district name-to-`adm_cd` mapping, and the boundary adjustment rules based on 2020 standards.
- For external supplementary variables, record the names of the original public datasets. (e.g., Official assessed land price boundary data, Seoul bus stop location information, Seoul station master information, Seoul hospital/clinic licensing information, Seoul large-scale store licensing information).
- For Seoul Living Population variables, explicitly distinguish between intra-district movement and domestic/foreign sources from the broader metropolitan area. Also, document the external inflow filters and time-of-day aggregation definitions.
- For the 3-year survival rate of new businesses, cite the JSON response from the Seoul Commercial Area Analysis Service website as the source, noting the 3-year block request method and the handling policy for missing values in small cohorts.
- For derived indices, document the direct source of the final formula (e.g., `vitality_index_base` is derived from the vitality sub-indices based on the Seoul Commercial Area Analysis Service).

## 8) Quarterly Publication Principles

- `source_periodicity` indicates the temporal structure of the source data. (e.g., `quarterly`, `annual_update_q4`, `annual_snapshot`, `permit_records`, `derived`).
- `publication_method` describes how the aggregation or as-of methodology publishes quarterly or raw records into `adm_cd-yq` variables. (e.g., `quarterly_sum_then_log`, `quarterly_mean_then_log`, `denominator_weighted_quarterly_ratio`, `q4_snapshot_asof`, `active_stock_by_year_asof`).
- `publication_formula` provides a concise summary of the actual code-based formula used for quarterly publication.
- `publication_note` highlights interpretation-critical exceptions such as Q4 snapshot as-of, denominator-weighted ratios, permit active-stock, or the generation of derived indices.
- Additive flows default to quarterly sums. (e.g., `ln_total_sales`, `ln_sales_count`, `ln_age60_sales_amount`).
- Levels or stocks typically use quarterly averages, Q4 snapshot as-of, or approval date-based active stocks. For instance, `ln_floating_pop` is a quarterly average, `ln_resident_pop` is the quarterly average stock from MOIS monthly resident population data, and `ln_total_store_count` is the `log1p` transformation of the quarterly representative value for the store count stock.
- Resident population-based shares (`age60_resident_share`, `age60_64_resident_share`, `age65_74_resident_share`, `age75plus_resident_share`, `age65plus_resident_share`) are denominator-weighted quarterly proportions, calculated by dividing the sum of the monthly populations for the specific age group within a quarter by the sum of the total monthly populations for the same quarter.
- The TWFE/SPDM age-mix appendix utilizes `ln_young_resident_pop`, `ln_middle_resident_pop`, and `ln_old_resident_pop`, which are `log1p` transformations of the aggregated populations for youth (20s-30s), middle-aged (40s-50s), and the elderly (60+) based on the quarterly average stock of the resident population. The resident population age-share variables (`age20_resident_share` to `age60plus_resident_share`) are calculated against an adult population denominator (ages 20 and over) and are maintained for the GTWR age-band appendix and diagnostic support.
- `Hang-dong`, which was separated from `Oryu 2-dong` in 2020, was included in `Oryu 2-dong` in 2019. Thus, the 2019 source values for `Oryu 2-dong` are distributed based on the proportional breakdown by month and age group between the newly divided `Oryu 2-dong` and `Hang-dong` in 2020. This district-split distribution is tracked using `registered_boundary_proxy_flag` and `registered_boundary_proxy_reference_year`.
- Official assessed land prices are assigned to administrative districts based on the internal representative point of the parcel polygon, and then calculated as an area-weighted average by administrative district and year. This annual-level value is preserved as the original variable `ln_official_land_price`.
- The active land price control variable is `ln_land_price_adjusted`, which incorporates the monthly regional land price index from the Korea Real Estate Board. The adjustment factor for legal districts is the average of the 3-month index ratio for the given quarter compared to the index of December of the previous year. This is converted into an administrative district adjustment factor, `land_price_lpi_factor`, using spatial intersection area-weights between legal and administrative districts, and then multiplied by the annual official assessed land price.
- External inflow population from the Seoul Living Population data is first averaged on a daily/time-of-day basis for each month and ZIP code, then aggregated to the administrative district-month level. The quarterly average is then derived by averaging the monthly averages within that quarter. If a month has insufficient days of data, the monthly average based on available observation days is used as the representative value for that month, and a coverage flag is logged in the manifest.
- New business survival rates are reconstructed as-of by administrative district and quarter from the 3-year block data (Q4 of the reference year) provided by the Seoul Commercial Area Analysis Service JSON. The original survival rate values are used directly for `survival_3y`, and rows with a cohort denominator of 0 are left as missing values without arbitrary imputation.
- Sales per store are calculated by dividing the quarterly total sales by the representative quarterly store count, followed by a `log1p` transformation (e.g., `ln_sales_per_store`).
- Quarterly stability is computed as `-log1p(sd(q1:q4) / mean(q1:q4))` only when valid values exist for all four quarters and the quarterly mean is positive (e.g., `sales_quarter_stability`, `floating_quarter_stability`).
- Proportion variables should use denominator-weighted quarterly ratios whenever possible (e.g., `age60_floating_share`, `age60_sales_share`).
- Q4 update-based sources are currently designated in the code as `q4_snapshot`, `q4_snapshot_ratio`, `q4_snapshot_then_log`, or `q4_snapshot_difference`.
- If a Q4 observation is missing for a Q4 update-based source, it is left as missing rather than imputed with the most recent quarter's value from the same year.
- Vitality sub-indices and composite indices are derived from the finalized quarterly components rather than being re-aggregated directly from the raw sources.
- The standardization of vitality sub-indices and composite indices follows a pooled panel standardization approach. This means the mean and standard deviation of the active analysis period (`2019Q4~2025Q4 adm_cd-yq` sample) are used; quarterly standardization is not part of the active contract.
