# The Impact of Population Aging on Neighborhood Commercial Vitality: A Spatiotemporal Analysis using Seoul Big Data

> **Last updated**: 2026-09-04

## 1. Background and Problem Statement

Seoul is experiencing rapid population aging alongside a restructuring of local consumption patterns. The same aging trend can stabilize basic demand in some areas, while weakening mobility and business diversity in others. Therefore, the relationship between aging and commercial vitality should not be interpreted as a simple correlation, but rather as a structure that encompasses spatial dependence and inter-regional interactions.

This document serves as the active design anchor for the current project. Execution sequences, output contracts, and QC rules are specified in [research_procedure.md](research_procedure.md) and the codebook.

## 2. Research Objectives

The purpose of this study is to formulate an empirical framework capable of explaining neighborhood commercial districts in Seoul from the perspectives of aging and spatial dependence. The specific objectives are as follows:

1. Estimate the global relationship between residence-based aging and neighborhood commercial vitality.
2. Estimate the spatial spillover effects that aging and vitality changes in a specific area have on neighboring regions.
3. Identify local spatiotemporal patterns to account for regional coefficient variations that the global model cannot fully explain.

This study does not reduce commercial vitality to a single numerical value. Instead, we first interpret the four dimensions of economic vitality, social vitality, temporal sustainability, and structural stability, utilizing the composite index only as a supplementary summary.

## 3. Key Research Questions

- `RQ1. Direct Effects and Global Relationships`
  - In what direction and magnitude does `age60_resident_share` (operationalized as `lag4_age60_resident_share`) relate to neighborhood commercial vitality in Seoul's administrative dongs?
  - Does this relationship manifest differently across `economic`, `social`, `temporal`, and `stability` dimensions?

- `RQ2. Spatial Dependence and Spillovers`
  - Do aging and commercial vitality exhibit spatial autocorrelation?
  - Does spatial dependence remain in the residuals of the non-spatial baseline model?
  - What patterns emerge in the direct, indirect, and total effects within the spatial model?

- `RQ3. Local Spatiotemporal Heterogeneity`
  - Does the global average effect apply uniformly across all regions?
  - What spatial patterns do the magnitude and direction of regional coefficients exhibit?

### 3.1 Research Hypotheses

The following hypotheses are derived from the three research questions and the theoretical mechanism discussed in Section 5. Because commercial vitality is defined multidimensionally, the direct-effect hypothesis is stated at the dimension level rather than for a single aggregate index.

- **H1 (Direct effects).** Residence-based aging (`lag4_age60_resident_share`) exerts a statistically significant direct effect on the commercial vitality of Seoul's administrative dongs, and the direction and magnitude of this effect differ across the four vitality dimensions. Consistent with the elderly consumption mechanism, essential-goods repeat consumption and reliance on local living zones (Aging in Place) are expected to stabilize demand in the economic and structural dimensions, whereas reduced mobility and a narrow activity space are expected to weaken mobility-dependent dimensions such as social vitality (floating population); a daytime-centered use pattern is likewise expected to shift the time-of-day distribution, altering the temporal sustainability dimension.

  **Identification status of H1 (2026-09-04).** Before the dimension-by-dimension reading below, one limit applies to all of them. `age60_resident_share` is close to a deterministic within-dong linear trend, with a median absolute correlation of `0.993` against `quarter_index` and above `0.9` in `85.4%` of dongs. Under two-way fixed effects the identifying variation is therefore differential trend slope, and the 4-quarter lag does not separate an aging effect from any dong-level trend correlated with it. The placebo test confirms this directly: a 4-quarter *lead* of the exposure predicts current vitality at least as well as the lag for `vitality_sub_economic` (p = .032) and `vitality_sub_social` (p = .011), and the lag does not survive a horse race against it. Only `vitality_index_base` survives the addition of dong-specific linear trends. H1 is therefore tested as a **conditional association**, not as a causal effect; the results should be worded accordingly, and the diagnostics in [04_model_spec.md section 6B.1](../02_Codebook/04_model_spec.md) reported with them.

  **Evidential status of H1 by dimension (2026-09-04).** H1 is tested on the full sample, and the influence diagnostic in [04_model_spec.md section 6A](../02_Codebook/04_model_spec.md) is reported alongside it rather than used to redefine the sample. On the current evidence the four dimensions are not equally supported. The social dimension is robust to influence: the effect holds below `p = 0.001` under every exclusion variant. It does not, however, survive dong-specific linear trends (`-1.840` to `-0.607`, p = .248), so its robustness is to outlying districts rather than to differential trends. The economic dimension and the composite are directionally consistent but materially dependent on a few districts, and their magnitudes must be reported with that dependence. The temporal dimension is **not supported**: the full-sample coefficient reverses sign when any of the influential districts is removed, and a single dong accounts for `94.3%` of it, so the mechanism stated above for time-of-day distribution is not evidenced here and must not be asserted as a finding. The structural dimension is not statistically distinguishable from zero in either direction. The reason is substantive rather than technical: the districts driving the temporal tail are undergoing residential redevelopment or absorbed the COVID collapse of the central business district, and neither mechanism is population aging.

  **Joint status of H1 across all diagnostics (2026-09-04).** The two paragraphs above report the identification and influence diagnostics separately, and each leaves two or three dimensions standing. They are not the same two or three. [05_run_evidence_synthesis.R](../../02_Code/04_robustness/05_run_evidence_synthesis.R) cross-tabulates all nine gates against all five outcomes, and the intersection is empty: no outcome clears every diagnostic, and the best clears six of nine. One gate fails for every outcome, which makes it a property of the design rather than of any dimension — entered against a 4-quarter lead, the lag is not significant anywhere, though the two are separable (within correlation `0.674`, VIF `1.8`). Of the two dimensions that remain reportable, `vitality_index_base` is `descriptive_only`, the only outcome to survive dong-specific trends but losing 5% significance when nine tail dongs are dropped, and `vitality_sub_social` is a `conditional_association`, stable in magnitude but failing all three identification gates. The remaining three are `not_supported` under the control contract. H1 must be written against this table, in [04_model_spec.md section 6C.1](../02_Codebook/04_model_spec.md), rather than against any single diagnostic.

- **H2 (Spatial spillovers).** Aging and commercial vitality exhibit positive spatial autocorrelation. Spatial dependence remains in the residuals of the non-spatial TWFE baseline, and aging in one area exerts spatial spillover effects on the commercial vitality of adjacent areas, quantified through the direct, indirect, and total effects of the SPDM.

- **H3 (Local spatiotemporal heterogeneity).** The effect of aging on commercial vitality does not apply uniformly across Seoul; the direction and magnitude of regional coefficients exhibit local spatiotemporal heterogeneity that the global model alone cannot capture, as explored by the GTWR sidecar.

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
3. **Temporal sustainability / structural stability component**
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

The TWFE model serves as the non-spatial baseline. By controlling for time-invariant characteristics and common shocks via regional and quarterly fixed effects, it provides an interpretable baseline on the same quarterly window. The samples are close but not identical: TWFE uses complete cases while the SPDM enforces a balanced panel, so the two differ by up to 24 observations depending on the outcome. A strictly common-sample TWFE is available as the `twfe_common` family of the spatial family comparison sidecar. What justifies the spatial extension is not the TWFE residual Moran, which is near zero, but the panel LM tests of the selection sidecar together with the levels-versus-within evidence in [04_model_spec.md section 1](../02_Codebook/04_model_spec.md): spatial structure survives the within transform in the exposure but largely not in the outcomes, which points to spillovers through `W X` rather than through `W y`.

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
The temporal sustainability sub-index reflects both the time-of-day distribution within a day and the quarterly stability over a year.
The structural stability sub-index combines a structural diversity axis and a store persistence axis with equal weights. The structural diversity axis is the pooled z-score of the sector diversity index. The store persistence axis is the average of the pooled z-scores of relative operating months compared to Seoul and the 3-year survival rate of new businesses (`survival_3y`) from the Seoul Commercial District Analysis Service. `closure_rate` and `stability_score = -closure_rate` are kept as supporting diagnostic variables for closure pressure, but are excluded from the active structural stability sub-index components.
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

`ln_resident_pop` is the `log1p` of the intra-quarter average of the administrative dong-monthly total population stock from the Ministry of the Interior and Safety Resident Registration Population. `transit_accessibility` is a public transit accessibility control variable generated by averaging the pooled z-scores of `bus_stop_count_aux` and `subway_station_count_aux`. The main model injects `lag4_transit_accessibility`, which is the same composite rebuilt from the lagged counts and standardized over the lagged sample rather than the 4-quarter lag of the contemporaneous composite; the two differ negligibly but not exactly, and the construction is documented in [02_variable_dictionary.md section 4](../02_Codebook/02_variable_dictionary.md). Every GTWR control set logs a separate diagnostic for its complete-case sample and three local collinearity measures computed on the GTWR spatiotemporal weights. `local_vif_max` is the largest weighted variance inflation factor in the local design and is the primary reading; `local_cn_centered` is the condition number of the weighted, centered local design; `local_cn_gtwr` applies the uncentered `local_CN` calculation convention from `GWmodel::gwr.collin.diagno()` tailored to the spatiotemporal distance and kernel weights of the GTWR. The collinearity warning flag is raised at the `local_vif_max` threshold contracted in [04_model_spec.md section 7.0](../02_Codebook/04_model_spec.md), VIF being the one criterion with an established rule of thumb; `local_cn_centered` is reported without a threshold, since Belsley's condition-index cut-off of 30 is defined for the uncentered, column-scaled construction and does not transfer to a centered one. The three measures condition on different things rather than correcting one another. `local_cn_gtwr` follows Belsley (1984), who argues against centering precisely because it hides dependency involving the intercept, and so describes the conditioning of the full coefficient vector including the local intercept. On this panel it runs an order of magnitude above the centered measure because the intercept is nearly dependent with the large-mean log controls, while the variance inflation factors stay low; the current values are reported in `gtwr_collin_diag_backfill_<control_set>.csv` rather than restated here, because they change with every rerun. That backfill table is the only source for all three measures until the pending GTWR rerun lands: the published `gtwr_local_coefficients_<control_set>.csv` predates the three-metric schema and carries `local_cn_gtwr` alone, and the `collinearity_warn_share` in `gtwr_main_models_<control_set>.csv` was written under the retired uncentered flag rather than the VIF criterion described here. See [04_model_spec.md section 7.1](../02_Codebook/04_model_spec.md). Because the estimand is the slope on the aging exposure rather than the local intercept, the predictor-space measures are the operative ones for interpretation.

### 6.4 Period Flags and Auxiliary Variables

- `covid_period`
  - An appendix interaction flag indicating the quarter range `2020Q1-2022Q2`.
- Additional age-mixes, alternative vitality index definitions, and sample window sensitivities are covered in robustness checks or the appendix.

## 7. Methodology Stack

The active methodology stack is configured as follows:

### 7.1 ESDA

- Purpose: Verify distributions and the presence of spatial autocorrelation.
- Role: An exploratory step to initiate discussions on spatial dependence and spillovers.
- Key Outputs: Global Moran's I, Bivariate Moran's I, LISA, Emerging Hot Spot Analysis (EHSA), and distribution maps.

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

> **Parameter values are not stated here.** The bandwidth, kernel, `lamda`, angle parameter, and control set are contracted in the authoritative table at [04_model_spec.md section 7.0](../02_Codebook/04_model_spec.md), and the gap between that contract and the currently published GTWR outputs is stated in section 7.1 of the same document. This section carries the reasoning behind those choices, not the numbers; the numbers moved to a single owner after three documents independently asserted a bandwidth that no published output actually used (see [decision_log.md](../03_Log/decision_log.md), 2026-09-04).

- Bandwidth: the main GTWR uses a fixed adaptive bandwidth rather than a searched one, chosen for outcome comparability, local coefficient stability, bandwidth-selection results, and sensitivity diagnostics. The `bw.gtwr()` full-panel/anchor-quarter exploration is strictly executed in [06_select_gtwr_bandwidth.R](../../02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R), and its selection results are not automatically injected into the main GTWR. [07_run_gtwr_bandwidth_sensitivity.R](../../02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R) iteratively applies a fixed adaptive bandwidth grid to the same specification, logging the latest-quarter beta agreement, sign flips, and local collinearity diagnostic shifts against the contracted baseline in a supplementary table.
- Kernel: the local weighting kernel is applied to the combined spatiotemporal distance, and the angle parameter of the Huang et al. (2010) distance is held at its default in every active and appendix specification, so the interaction term enters at full weight. Both are required reporting items and must be stated wherever GTWR results are presented.
- Spatiotemporal Weighting: `lamda` is dimensionless. The spatial and temporal distances are each divided by their own observed span before being combined, so `lamda` expresses the share of weight on the full spatial extent and the midpoint weights the two dimensions equally. This departs from `GWmodel::st.dist()`, which mixes raw metres with quarter counts and therefore absorbs their scale gap into the parameter; the previous raw-unit `lamda` of `0.05` corresponds to approximately `0.987` under the dimensionless convention, and values recorded under the two conventions are not comparable.
- Lamda Sensitivity: [08_run_gtwr_lamda_sensitivity.R](../../02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R) re-estimates the GTWR for each value in the `GTWR_LAMDA_SENSITIVITY_GRID`, logging correlations with the baseline latest-quarter betas, absolute shifts, sign flips, and local collinearity diagnostic changes in a supplementary table.
- Specification Search: [10_search_gtwr_lamda_bw_cv.R](../../02_Code/80_optional/gtwr/10_search_gtwr_lamda_bw_cv.R) locates the lamda and bandwidth region by leave-one-out cross validation without fitting the GTWR, and flags whether an optimum is bracketed or sits on a grid edge. It informs where to look, not what to report: the reported bandwidth remains the fixed adaptive value of the active contract, chosen for outcome comparability and local coefficient stability, and the CV-preferred values are recorded in [decision_log.md](../03_Log/decision_log.md) so the gap between the prediction-optimal and the reported specification is explicit rather than implicit.
- Control Set: the `lean` default holds the resident-population and land-price controls only. The `extended` setting, which adds the transit accessibility composite and the workplace worker population, is reserved for sensitivity/expanded specifications.
- Reporting Surface: GTWR local coefficients are summarized based on the latest quarter betas, while earliest-to-latest deltas are only derived as a supplementary appendix diagnostic.

## 8. Boundary between Main Text and Appendix

- **Main text**
  - Logic for constructing the quarterly panel
  - Definitions of vitality indices and core variables
  - Key ESDA results
  - TWFE baseline and residual Moran's I
  - SPDM main impacts
  - **Influence robustness for the reported effects** (`influence_robustness_summary.csv`)
  - Summary GTWR maps (as needed)

- **Appendix**
  - Interaction family
  - Age-mix family
  - SPDM channel path sidecar
  - Spatial family comparison (`SLX`, `SAR`, `SDM`, `SEM`, `SDEM`, `SARAR/SAC`, `GNS`)
  - Detailed W robustness tables
  - Per-dong `influence_dfbeta.csv` and the outcome-tail listing
  - Additional GTWR sidecars
  - Detailed QC inventory

This structure ensures the main text sustains the interpretative flow of `ESDA -> TWFE -> SPDM main -> GTWR (optional)`, while cleanly segregating the channel paths, supplementary sensitivities, and local sidecars into the appendix.

Influence robustness sits in the main text rather than the appendix because of the 2026-09-04 decision to keep the full sample as the main specification. That decision is defensible only if the reader can see which effects depend on a handful of districts, so the summary table travels with the impacts it qualifies. The per-dong `dfbeta` detail stays in the appendix; the summary does not.
