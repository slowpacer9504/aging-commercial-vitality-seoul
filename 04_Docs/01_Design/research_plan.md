# The Impact of Population Aging on Neighborhood Commercial Vitality: A Spatiotemporal Analysis using Seoul Big Data

## 1. Background and Problem Statement

Seoul is experiencing rapid population aging alongside a restructuring of local consumption patterns. The same aging trend can stabilize basic demand in some areas, while weakening mobility and business diversity in others. Therefore, the relationship between aging and commercial vitality should not be interpreted as a simple correlation, but rather as a structure that encompasses spatial dependence and inter-regional interactions.

This document serves as the active design anchor for the current project. Execution sequences, output contracts, and QC rules are specified in [research_procedure.md](research_procedure.md) and the codebook.

## 2. Research Objectives

The purpose of this study is to formulate an empirical framework capable of explaining neighborhood commercial districts in Seoul from the perspectives of aging and spatial dependence. The specific objectives are as follows:

1. Estimate the global relationship between residence-based aging and neighborhood commercial vitality.
2. Estimate the spatial spillover effects that aging and vitality changes in a specific area have on neighboring regions.
3. Identify local spatiotemporal patterns to account for regional coefficient variations that the global model cannot fully explain.

This study does not reduce commercial vitality to a single numerical value. Instead, we first interpret the four dimensions of economic vitality, social vitality, temporal vitality, and structural stability, utilizing the composite index only as a supplementary summary.

## 3. Key Research Questions

- `RQ1. Direct Effects and Global Relationships`
  - In what direction and magnitude does `age60_resident_share` relate to neighborhood commercial vitality in Seoul's administrative dongs?
  - Does this relationship manifest differently across `economic`, `social`, `temporal`, and `stability` dimensions?

- `RQ2. Spatial Dependence and Spillovers`
  - Do aging and commercial vitality exhibit spatial autocorrelation?
  - Does spatial dependence remain in the residuals of the non-spatial baseline model?
  - What patterns emerge in the direct, indirect, and total effects within the spatial model?

- `RQ3. Local Spatiotemporal Heterogeneity`
  - Does the global average effect apply uniformly across all regions?
  - What spatial patterns do the magnitude and direction of regional coefficients exhibit?

The `aging x covid_period` interaction, alternative vitality indices, and additional age-mix and sector-share models are addressed in the appendix or robustness checks. The main empirical narrative focuses on the three core questions above.
Appendix/sidecar scripts under [`80_optional/**`](../../02_Code/80_optional) are kept separate from the main [run_all.R](../../02_Code/run_all.R). They are managed as a manual execution surface, running without explicit execution flags when the files are run directly.

## 4. Unit of Analysis and Scope

### 4.1 Spatial Unit

- The unit of analysis is the **administrative dong (`adm_cd`) of Seoul, based on the 2020 boundary**.
- Spatial weight matrices and map visualizations use these exact same boundaries.
- The reference coordinate reference system (CRS) for geometry processing is `EPSG:5179`.

The administrative dong level provides a suitably granular view of the interactions between neighborhood commercial areas and resident demographics. It is also compatible with supplementary public data and provides an interpretable adjacency structure for spatial modeling.

### 4.2 Temporal Unit and Scope

- The canonical panel covers **2019Q1 to 2025Q4**, while the active analysis period is **2019Q4 to 2025Q4**.
- The active analysis unit is the `adm_cd x yq` quarterly panel.
- The active time keys are `year`, `quarter`, `yq`, and `quarter_index`.
- The canonical model timing contract relies on **lagged quarter variables**. Independent and control variables utilize `t-4` values. The mediator for the optional SPDM channel path sidecar uses `t-2` values.
- Source data from 2018 for registered resident population, bus stops, and official land prices are exclusively used as the lag-support range to calculate 4-quarter lags for the 2019 active panel.
- The period from 2019Q1 to 2019Q3 serves as a warm-up phase to construct rolling 4-quarter vitality indicators and lag variables. It is excluded from the main ESDA/TWFE/SPDM/GTWR models and reporting samples.

Quarterly data forms the time axis of the active shared panel. While annual and static data may contain repeated values across quarters, we explicitly retain these repetitions and track them via source precision and QC checks.

### 4.3 Data Sources

| Category | Period | Purpose | Status |
| --- | --- | --- | --- |
| Seoul Commercial District Analysis Service | 2019Q1-2025Q4 | Core source for building the quarterly base | active |
| Ministry of the Interior and Safety Resident Registration Population | 2018-2025 | Resident population size and elderly resident share (2018 is for lag-support) | active |
| Supplementary Public Data | 2018-2025 available years | Control variables, physical/location auxiliary info (2018 is for lag-support) | active |
| 2020 Administrative Dong Boundaries | static | Spatial unit, W matrix construction | active |

Among the Seoul Commercial District Analysis Service sources, quarterly data is injected directly at the `adm_cd-yq` level. Annual and static data are aggregated at the `adm_cd-year` or `adm_cd` level, then merged into the corresponding quarter using a quarter-end as-of rule. Thus, the reference data for the main text interpretation is a "shared panel that preserves quarterly commercial fluctuations while explicitly noting the precision of lower-frequency sources."

### 4.4 Quarterization Principles

The transition to a quarterly unit involves standardizing the publication rules and as-of rules for each source frequency.

1. **Additive flow**
   - Variables that inherently accumulate over a quarter (e.g., total sales, transaction counts) are published as quarterly sums.
2. **Level / stock / share / density**
   - Variables indicating levels (e.g., number of stores, floating population, shares, densities) are published as quarterly representative values or denominator-weighted quarterly shares.
   - Monthly sources are aggregated into quarterly monthly averages or denominator-weighted quarterly shares.
   - For the Q4-update structure sources from the Seoul Commercial District Analysis Service, observable quarterly values are prioritized, while annual/static sources are merged using the quarter-end as-of rule.
   - Resident population size and the elderly resident share are matched to the 2020 administrative dong boundaries from the 5-year age group monthly data of the Ministry of the Interior and Safety. They are then calculated as intra-quarter monthly stock averages and denominator-weighted quarterly shares.
3. **Temporal / stability component**
   - Time-of-day entropy and structural diversity are calculated within a single quarter cross-section.
   - Quarterly stability is computed using the rolling 4-quarter distribution leading up to the current quarter.
4. **Annual / static auxiliary**
   - Annual or static data is aggregated at the `adm_cd-year` or `adm_cd` level, joined to the `adm_cd-yq` panel using an as-of approach, and its source precision is recorded.
   - Official land prices are area-weighted averages by administrative dong-year, and the identical value is published across all four quarters of that year.
   - For data blending a single snapshot and monthly snapshots (e.g., the bus stop source for transit accessibility), the snapshot published per quarter and its carry-forward status are recorded in the QC.

These principles constitute the minimal contract for explicitly managing the repeated value issue of low-frequency sources while preserving quarterly commercial fluctuations. To clarify the temporal sequence in our analysis models, only registered lag variables are added to the canonical panel. Currently permitted lag variables are `lag4_age60_resident_share`, `lag4_ln_resident_pop`, `lag4_ln_land_price_adjusted`, `lag4_transit_accessibility`, `lag4_ln_workplace_worker_pop`, and `lag2_age60_floating_share`.

## 5. Theoretical Framework

This study interprets the relationship between aging and commercial vitality through the following four layers.

### 5.1 Direct Effects

Residence-based aging can alter the rhythm of local consumption, demand across business sectors, mobility patterns, and duration of stay. These changes can uniquely manifest in sales, store composition, time-of-day variance, and survival stability.

### 5.2 Spatial Spillover Effects

Commercial districts do not operate in isolation within administrative boundaries. Given that consumption structures, commercial accessibility, and mobility within living zones are interconnected across adjacent areas, aging and vitality changes in one region can ripple outward to surrounding areas.

### 5.3 Relationship Between Non-Spatial Baseline and Spatial Extension Models

The TWFE model serves as the non-spatial baseline. By controlling for time-invariant characteristics and common shocks via regional and quarterly fixed effects, it provides an interpretable baseline on the identical quarterly sample. If spatial dependence remains in its residuals, this provides the empirical justification for introducing the SPDM.

### 5.4 Local Heterogeneity

The GTWR is an optional local sidecar that illustrates how the average effects of the global model vary across regions. Rather than replacing the global causal estimates, it acts as a supplementary layer explaining local patterns atop the main resident-only quarterly contract. Floating-only, age-band, and sector-share GTWR models are designated as appendix sidecars under [`80_optional/gtwr`](../../02_Code/80_optional/gtwr), invoking the actual `GWmodel::gtwr()` when their respective scripts are executed directly.

## 6. Variable Design

### 6.1 Core Independent Variables

- **Main exposure**
  - `lag4_age60_resident_share`
- **Supporting exposures**
  - `age60_resident_share`
  - `age60_floating_share`
  - `age60_sales_share`

`lag4_age60_resident_share` serves as the main exposure variable because residence-based aging most stably reflects the structural demand base of a local commercial district, while the 4-quarter lag avoids simultaneous responses with the dependent variables. The source `age60_resident_share` is derived not from the 10-year resident population of the Seoul Commercial District Analysis Service, but from the 5-year monthly data of the Ministry of the Interior and Safety Resident Registration Population. `age60_floating_share` and `age60_sales_share` are interpreted as supplementary axes of activity and consumption. The mediator for the optional SPDM channel path sidecar uses `lag2_age60_floating_share`.
While the Ministry of the Interior and Safety data also issues `age60_64_resident_share`, `age65_74_resident_share`, `age75plus_resident_share`, and `age65plus_resident_share` for future sensitivity analyses, the canonical main exposure is strictly maintained as `lag4_age60_resident_share`.

### 6.2 Dependent Variables

- **Primary outcomes**
  - `vitality_sub_economic`
  - `vitality_sub_social`
  - `vitality_sub_temporal`
  - `vitality_sub_stability`
- **Supplementary composite**
  - `vitality_index_base`
- **Robustness composites**
  - `vitality_index_entropy`
  - `vitality_index_pca`

The main results tables and interpretations focus on the four primary vitality sub-indices. The composite index acts as a supplementary summary to verify if the overall direction remains consistent.
The economic vitality sub-index is constructed by calculating the pooled z-scores of estimated transaction counts and total estimated sales, and then averaging them. Total store count and sales per store are retained in the panel but excluded from the economic sub-index components.
The social vitality sub-index incorporates both the internal floating population size of the commercial district and the external inflow population size based on Seoul Living Population data.
The temporal vitality sub-index reflects both the time-of-day distribution within a day and the quarterly stability over a year.
The stability sub-index combines a structural diversity axis and a store persistence axis with equal weights. The structural diversity axis is the pooled z-score of the sector diversity index. The store persistence axis is the average of the pooled z-scores of relative operating months compared to Seoul and the 3-year survival rate of new businesses (`survival_3y`) from the Seoul Commercial District Analysis Service. `closure_rate` and `stability_score = -closure_rate` are kept as supporting diagnostic variables for closure pressure, but are excluded from the active stability sub-index components.
The individual components and sub-indices of vitality are standardized using pooled z-scores based on the mean and standard deviation of the active analysis period (`2019Q4-2025Q4 adm_cd-yq` sample), rather than cross-sectional quarterly benchmarks. This active contract aligns the scale across components while preserving the level changes across quarters within the indices themselves.

### 6.3 Control Variables

The baseline control candidate pool for the main TWFE/SPDM consists of the following four 4-quarter lag variables. Since `ln_floating_pop` is included in the social vitality components and the composite vitality index, it is not used as a main control variable. `ln_apartment_household_count`, `hospital_count_aux_core`, and `mall_count_aux_core` remain in `panel_main` as diagnostic/support variables but are not included as active TWFE/SPDM/GTWR controls.

- `lag4_ln_resident_pop`
- `lag4_ln_land_price_adjusted`
- `lag4_transit_accessibility`
- `lag4_ln_workplace_worker_pop`

`ln_land_price_adjusted` is an adjusted land price index created by multiplying the area-weighted official land price by administrative dong-year with the quarterly average adjustment coefficient of the Korea Real Estate Board's monthly regional land price index. The land price index by legal dong is mapped to the administrative dong unit using a legal dong-administrative dong spatial intersection area weight. The log of the original annual official land price, `ln_official_land_price`, is preserved in the panel but not used as an active control variable.
`ln_workplace_worker_pop` is derived by matching the total number of workers per administrative dong (from Seoul's establishment statistics by worker size) to the 2020 administrative dong boundaries and applying `log1p`. For 2018-2019, the value for `Hang-dong` is distributed using the 2020 worker ratio between `Oryu 2-dong` and `Hang-dong` to allocate the pre-split `Oryu 2-dong` value. For 2025, the latest observed value from 2024 is carried forward as an as-of value. The main model utilizes the 4-quarter lag of this variable.

The main TWFE/SPDM logs a usable subset based on finite observation counts and estimability.

The GTWR main sidecar employs a distinct control contract to account for the multicollinearity sensitivity of the local design matrix.

- `lean` Default Set
  - `lag4_ln_resident_pop`
  - `lag4_ln_land_price_adjusted`
- `extended` Optional Set
  - The two variables from the `lean` set
  - `lag4_transit_accessibility`
  - `lag4_ln_workplace_worker_pop`

`ln_resident_pop` is the `log1p` of the intra-quarter average of the administrative dong-monthly total population stock from the Ministry of the Interior and Safety Resident Registration Population. `transit_accessibility` is a public transit accessibility control variable generated by averaging the pooled z-scores of `bus_stop_count_aux` and `subway_station_count_aux`. The main model injects the 4-quarter lag composite of this variable. Every GTWR control set logs a separate diagnostic for its complete-case sample and the local condition-number based on the GTWR spatiotemporal weights. This local CN is an auxiliary diagnostic applying the `local_CN` calculation convention from `GWmodel::gwr.collin.diagno()` tailored to the spatiotemporal distance and kernel weights of the GTWR.

### 6.4 Period Flags and Auxiliary Variables

- `covid_period`
  - An appendix interaction flag indicating the quarter range `2020Q1-2022Q2`.
- Additional age-mixes, alternative vitality index definitions, and sample window sensitivities are covered in robustness checks or the appendix.

## 7. Methodology Stack

The active methodology stack is configured as follows:

### 7.1 ESDA

- Purpose: Verify distributions and the presence of spatial autocorrelation.
- Role: An exploratory step to initiate discussions on spatial dependence and spillovers.
- Key Outputs: Global Moran's I, Bivariate Moran's I, LISA, EHSA, and distribution maps.

### 7.2 TWFE

- Purpose: Provide a non-spatial baseline and a common quarterly sample baseline.
- Role: Functions as a baseline/spatial-diagnostic layer, rather than the main inferential endpoint.
- Key Feature: Justifies the introduction of spatial models via residual Moran's I.

### 7.3 SPDM

- Purpose: Simultaneously estimate global direct and indirect effects.
- Role: Acts as the **main global model** of the active design.
- Core Reporting Focus: Emphasizes **direct / indirect / total effects** over plain coefficients.
- The active implementation is a true SDM/SPDM, meaning it explicitly includes `W y`, `X`, and `W X` together.
- [02_run_spdm_main.R](../../02_Code/03_models/02_run_spdm_main.R) does not rely on `splm::spml()`'s Durbin placeholder. Instead, it directly creates and estimates `W lag4_age60_resident_share` and `W controls` from the quarterly panel.
- Direct, indirect, and total effects are computed using the matrix determinants `S = (I - rho W)^(-1)` and `S(beta I + theta W)`.
- Standard errors for coefficients and spatial parameters use the model-based asymptotic ML `vcov` from the `splm::spml()` fitted object. Impact standard errors and confidence intervals are calculated by drawing simulations for `rho`, `beta`, and `theta` from the same model-based `vcov`, and these are not termed robust SEs.
- [80_optional/spdm/07_run_spdm_channel_path.R](../../02_Code/80_optional/spdm/07_run_spdm_channel_path.R) is an optional mediation-oriented channel path sidecar. Within the same quarterly Queen SDM contract, it estimates the non-mediated `c` path, the `a` path (`lag4_age60_resident_share -> lag2_age60_floating_share`), the `b` path (`lag2_age60_floating_share -> vitality`), and the mediator-controlled `c'` path on the identical outcome-specific balanced sample. The `a*b` indirect effect and the attenuation of the direct effect (`c - c'`) are logged as separate outputs. Inference primarily utilizes an administrative dong-level wild residual bootstrap, falling back to `delta_independent_approx` only when the bootstrap is disabled or yields insufficient valid draws.
- Channel path outcomes utilize `vitality_sub_economic`, `vitality_sub_temporal`, `vitality_sub_stability`, and `vitality_index_base`, excluding the standalone `vitality_sub_social` indicator due to direct overlap with the mediator source. The composite vitality index maintains its default definition containing all four sub-indices, but interpretations are caveated noting that the social vitality component overlaps with the mediator source.

### 7.4 GTWR

- Purpose: Visualize the local heterogeneity remaining after the global model.
- Role: A **resident-only quarterly main local sidecar**, positioned as optional within the standard pipeline. Floating-only, age-band, and sector-share local GTWR models are appendix sidecars, generated by directly executing their respective scripts in [`80_optional/gtwr`](../../02_Code/80_optional/gtwr).
- Interpretation Level: Local heterogeneity description rather than a global causal claim.
- Bandwidth: To accommodate outcome comparability, local coefficient stability, bandwidth-selection results, and sensitivity diagnostics, the main GTWR defaults to a fixed adaptive bandwidth of `GTWR_ST_BW=60`. The `bw.gtwr()` full-panel/anchor-quarter exploration is strictly executed in [06_select_gtwr_bandwidth.R](../../02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R), and its selection results are not automatically injected into the main GTWR. [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R) iteratively applies a fixed adaptive bandwidth grid `30,60,90,120,180` to the same specification, logging the latest-quarter beta agreement, sign flips, and local condition-number shifts compared to the `60` baseline in a supplementary table.
- Lamda Sensitivity: [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R) re-estimates the GTWR for each value in the `GTWR_LAMDA_SENSITIVITY_GRID`, logging correlations with the baseline latest-quarter betas, absolute shifts, sign flips, and local condition-number changes in a supplementary table.
- Control Set: Defaults to `GTWR_CONTROL_SET=lean`. The `extended` setting, which adds the transit accessibility composite, is reserved for sensitivity/expanded specifications.
- Reporting Surface: GTWR local coefficients are summarized based on the latest quarter betas, while earliest-to-latest deltas are only derived as a supplementary appendix diagnostic.

## 8. Boundary between Main Text and Appendix

- **Main text**
  - Logic for constructing the quarterly panel
  - Definitions of vitality indices and core variables
  - Key ESDA results
  - TWFE baseline and residual Moran's I
  - SPDM main impacts
  - Summary GTWR maps (as needed)

- **Appendix**
  - Interaction family
  - Age-mix family
  - SPDM channel path sidecar
  - Spatial family comparison (`SLX`, `SAR`, `SDM`, `SEM`, `SDEM`, `SARAR/SAC`, `GNS`)
  - Detailed W robustness tables
  - Additional GTWR sidecars
  - Detailed QC inventory

This structure ensures the main text sustains the interpretative flow of `ESDA -> TWFE -> SPDM main -> GTWR (optional)`, while cleanly segregating the channel paths, supplementary sensitivities, and local sidecars into the appendix.
