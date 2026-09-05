# 02_Code

This directory contains the core R scripts for the end-to-end data pipeline, spatial analysis, and econometric modeling (TWFE, SPDM, GTWR) to estimate the impact of aging on neighborhood commercial vitality in Seoul.

## Quick Start

The same steps as the main [README Quick Start](../README.md#1-quick-start) are reproduced here so this directory guide stays self-contained.

1. Open `R.Rproj` so `here::here()` resolves the project root correctly.
2. Restore the pinned package environment with renv (recommended), or install the latest set from CRAN:

```r
renv::restore()                                    # exact versions from renv.lock
# or
source("02_Code/00_setup/install_packages.R")      # latest CRAN versions
```

3. If auxiliary preprocessing needs fresh geocoding beyond the existing cache, set:

```r
Sys.setenv(
  KAKAO_REST_API_KEY = "your_kakao_rest_api_key",
  NAVER_CLIENT_ID = "your_naver_client_id",
  NAVER_CLIENT_SECRET = "your_naver_client_secret"
)
```

4. Run the canonical default pipeline:

```r
source("02_Code/run_all.R")
```

Command-line alternative:

```bash
Rscript 02_Code/run_all.R
```

`02_Code/80_optional/preprocess/01_build_living_population_inflow.R` streams large Seoul Living Population ZIP files. For a smoke test without overwriting the canonical output, set `LIVING_POP_SAMPLE_MONTHS=201901`; the script writes sample-tagged output paths.

## Active Canonical Workflow

The active default order is:

- `02_Code/01_preprocess/01_build_adm_region_lookup.R`
- `02_Code/01_preprocess/02_build_seoul_quarter_base.R`
- `02_Code/01_preprocess/03_build_auxiliary_covariates.R`
- `02_Code/01_preprocess/04_build_golmok_survival_rate.R`
- `02_Code/01_preprocess/05_build_registered_resident_population.R`
- `02_Code/01_preprocess/06_build_analysis_panel.R`
- `02_Code/01_preprocess/07_build_vitality_index.R`
- `02_Code/02_esda/01_build_spatial_weights.R`
- `02_Code/02_esda/02_run_esda.R`
- `02_Code/02_esda/03_run_exploratory_diagnostics.R`
- `02_Code/03_models/01_run_twfe_main.R`
- `02_Code/03_models/02_run_spdm_main.R`
- `02_Code/04_robustness/01_run_spdm_w_robustness.R`
- `02_Code/04_robustness/02_run_robustness.R`
- `02_Code/04_robustness/03_run_influence_robustness.R`
- `02_Code/04_robustness/04_run_identification_diagnostics.R`
- `02_Code/04_robustness/05_run_evidence_synthesis.R`
- `02_Code/06_qc/01_validate_method_dataset_alignment.R`
- `02_Code/05_reporting/01_make_tables_figures.R`

### Manual Optional Sidecars

These scripts are **outside** of the default `run_all.R` pipeline. You must execute them directly if you need their specific outputs.

#### 1. Optional Preprocessing
- **Living Population Inflow**:
  `02_Code/80_optional/preprocess/01_build_living_population_inflow.R`

#### 2. GTWR Local-Analysis
Run the GTWR main model manually:
```bash
Rscript 02_Code/03_models/03_run_gtwr_main.R
```
*(Helper implementation: `02_Code/99_utils/utils_gtwr_main.R`)*

**Execution Options (Environment Variables):**
- **Control Set**: `GTWR_CONTROL_SET=lean` (default) or `extended` (adds transit & location controls).
- **Parallelization**: `GTWR_PARALLEL_SPECS=<n>` (default: `5`)
- **Caching**:
  - `GTWR_RESUME_SPECS=TRUE` (default: `TRUE`; resume from completed cache — set `FALSE` to force a fresh run)
  - `GTWR_REFRESH_SPEC_CACHE=TRUE` (clear cache and recompute; default: `FALSE`)
- **Bandwidth**:
  - `GTWR_BANDWIDTH_STRATEGY`: `fixed` (default), `full_panel_bw_gtwr`, or `anchor_quarter_bw_gtwr`.
  - `GTWR_ST_BW`: Spatiotemporal bandwidth (default: 60).
  - Search script: `02_Code/80_optional/gtwr/06_select_gtwr_bandwidth.R` (Use `GTWR_REFRESH_BW_CACHE=TRUE` to recompute cache).
- **Kernel and angle**: `GTWR_KERNEL=bisquare` (default) and `GTWR_KSI=0` (default). Both are required reporting items for a GTWR specification.
- Full list: see [Environment Variable Reference](#environment-variable-reference) below.

**Outputs:**
- Main outputs are tagged by control set (e.g., `gtwr_main_models_lean.csv`).
- Main reporting uses the latest-quarter local beta; delta values are logged to `gtwr_delta_*` appendix tables.

#### 3. TWFE Supplementary Sidecars
- `02_Code/80_optional/twfe/01_run_twfe_channel_models.R`
- `02_Code/80_optional/twfe/02_run_twfe_interaction_models.R`
- `02_Code/80_optional/twfe/03_run_twfe_age_mix_experiment.R`
- `02_Code/80_optional/twfe/04_run_twfe_vitality_component_models.R`

#### 4. SPDM Supplementary Sidecars (Optional Appendix)
- `02_Code/80_optional/spdm/01_run_spdm_interaction_models.R`
- `02_Code/80_optional/spdm/02_run_spdm_age_mix_experiment.R`
- `02_Code/80_optional/spdm/03_run_spdm_sector_share_experiment.R`
- `02_Code/80_optional/spdm/04_run_spdm_selection_sidecar.R`
- `02_Code/80_optional/spdm/05_run_spdm_family_comparison_sidecar.R`
- `02_Code/80_optional/spdm/06_run_spdm_vitality_component_models.R`
- `02_Code/80_optional/spdm/07_run_spdm_channel_path.R`

#### 5. Additional GTWR Experiments
- `02_Code/80_optional/gtwr/01_run_gtwr_floating_only.R`
- `02_Code/80_optional/gtwr/02_run_gtwr_age_band.R`
- `02_Code/80_optional/gtwr/03_run_gtwr_sector_share.R`
- `02_Code/80_optional/gtwr/04_run_gwr_delta.R`
- `02_Code/80_optional/gtwr/05_run_gtwr_experiment.R`
- `02_Code/80_optional/gtwr/07_run_gtwr_bandwidth_sensitivity.R`
- `02_Code/80_optional/gtwr/08_run_gtwr_lamda_sensitivity.R`
- `02_Code/80_optional/gtwr/09_backfill_gtwr_collin_diag.R` — recomputes the three local collinearity diagnostics for already-estimated specs without refitting
- `02_Code/80_optional/gtwr/10_search_gtwr_lamda_bw_cv.R` — leave-one-out CV search over the lamda and bandwidth grids without fitting GTWR; a search tool, not a reporting one

> Note: `06_select_gtwr_bandwidth.R` is a bandwidth *search* utility rather than an experiment runner; it is documented under the GTWR local-analysis section above.

### Manual QC & Reporting Sidecars

- **QC Processed Outputs**: `02_Code/06_qc/02_check_processed_parquet_outputs.R`
- **Published Test Inventory**: `02_Code/06_qc/04_build_test_inventory.R` — counts every exposure-side test in the published model tables and reports Benjamini-Hochberg within each table and across the whole surface
- **Review Outputs in RStudio**: `02_Code/06_qc/03_open_outputs_for_rstudio_review.R`
- **Build Presentation Artifacts**: `02_Code/05_reporting/02_build_presentation_artifacts.R`
- **Build GTWR Level Artifacts**: `02_Code/05_reporting/03_build_gtwr_level_artifacts.R`

## Environment Variable Reference

This is the complete list of environment variables read by the pipeline. The default pipeline runs with **none** of them set. Values are read once in `00_setup/config.R` unless another script is noted; an invalid value falls back to the default rather than raising, and every such fallback is warned at config time and recorded in the `### Run environment` block of `model_run_log.md`, so a run that silently used a default instead of the value you asked for is visible in the log.

### Pipeline-wide

| Variable | Default | Purpose |
| --- | --- | --- |
| `CFG_OUTPUT_TAG` | *(empty)* | Suffix appended to output paths to isolate a run |
| `RSTUDIO` | set by RStudio | Read, not set by the user; `06_qc/03_open_outputs_for_rstudio_review.R` opens viewers only when it is `1` |
| `BUILD_OPTIONAL_APPENDIX_TABLES` | `false` | Gate for the optional appendix tables in `05_reporting/01_make_tables_figures.R` (`spatial_family_main_table.csv`, `gtwr_latest_*`, `gtwr_delta_*`, `gwr_delta_summary_table.csv`). They are **not** written by a default run |
| `QC_CONTRACT_GATE` | `true` | When true, `06_qc/01_validate_method_dataset_alignment.R` stops the run if any method-dataset contract check is `FAIL`, before `05_reporting` builds tables on it. The QC table and log line are written first, so a failing run still leaves the full diagnostic behind. Set to `false` only to inspect downstream artifacts while knowingly working against a failing contract; the bypass is warned and logged |
| `EDA_EXPOSURE_BINS` | `20` | Read by `02_esda/03_run_exploratory_diagnostics.R`. Number of equal-count exposure bins used for the binned response table and the lack-of-fit test. More bins resolve finer departures from linearity at the cost of noisier bin means |
| `INFLUENCE_TAIL_Z` | `5` | Read by `04_robustness/03_run_influence_robustness.R`. Pooled-z threshold used to name outcome-tail dongs. Not a rejection rule; only a way to identify dongs far enough out to move a pooled standard deviation |
| `INFLUENCE_TOP_K` | `10` | Read by `04_robustness/03_run_influence_robustness.R`. Number of highest-`\|dfbeta\|` dongs dropped in the `top_k` exclusion variant |
| `SYNTHESIS_INFLUENCE_PCT_TOL` | `50` | Read by `04_robustness/05_run_evidence_synthesis.R`. Percentage by which the exposure coefficient may move across influence-exclusion variants and still pass the `influence_stable` gate. A stated convention, not an inferential rule; the underlying `pct_change` values travel with the output |
| `GTWR_DIAG_GEOM_POINTS` | `300` | Read by `80_optional/gtwr/11_diagnose_gtwr_estimand.R`. Focal points sampled when classifying the bandwidth-nearest window; the window composition is a distributional property, so a few hundred draws pin it to more precision than the question needs |
| `GTWR_DIAG_EDGE_POINTS` | `60` | Read by `80_optional/gtwr/11_diagnose_gtwr_estimand.R`. Focal points sampled per quarter when measuring the kernel's own-dong temporal support |
| `GTWR_DIAG_KSI_GRID` | `0,0.7854,1.5708,2.3562,3.1416` | Read by `80_optional/gtwr/11_diagnose_gtwr_estimand.R`. Angle-parameter grid for the kernel-geometry sweep. This is the project's only working `ksi` sensitivity: the experiment appendix that was believed to provide one never estimates. The contracted `GTWR_KSI` is always added to the grid |

### Preprocessing

| Variable | Default | Purpose |
| --- | --- | --- |
| `KAKAO_REST_API_KEY` | *(empty)* | Kakao geocoding key; needed only for fresh geocoding beyond the cache (`01_preprocess/03_build_auxiliary_covariates.R`) |
| `NAVER_CLIENT_ID`, `NAVER_CLIENT_SECRET` | *(empty)* | Naver geocoding keys, same condition |
| `GOLMOK_COOKIE` | *(empty)* | Session cookie for the `selectSurvivalRate.json` endpoint when the survival-rate layer is rebuilt |
| `GOLMOK_SURVIVAL_FORCE_REBUILD` | `false` | Refetch the survival-rate JSON instead of reusing the saved responses |
| `LIVING_POP_HOURS` | `0-23` | Hour window aggregated for the living-population inflow layer |
| `LIVING_POP_CORES` | `1` | Parallel workers for monthly ZIP processing; the parquet, manifest, and QC files are still written once by the parent |
| `LIVING_POP_FORCE_REBUILD` | `false` | Rebuild the inflow layer even when the output exists |
| `LIVING_POP_SAMPLE_MONTHS` | *(empty)* | Stream only a sample month (e.g. `201901`) for a smoke test; writes sample-tagged outputs |
| `LIVING_POP_ENCODING` | `UTF-8` | Encoding used to read the living-population ZIP members |
| `LIVING_POP_SUPPRESSED_VALUE` | `0` | Value substituted for suppressed cells in the source |

### SPDM

| Variable | Default | Purpose |
| --- | --- | --- |
| `SPDM_MIN_PERIODS` | `20` | Minimum number of quarters a balanced estimation panel must retain for a specification to be accepted. A floor on panel length, not a per-dong observation count |
| `SPDM_OPTIONAL_SPEC_CORES` | `1` | Parallel spec workers for the optional SPDM sidecars |
| `SPDM_OPTIONAL_IMPACT_CORES` | `1` | Parallel workers for impact simulation in the optional SPDM sidecars |
| `RUN_SPDM_CHANNEL_BOOTSTRAP` | `true` | Run the wild residual bootstrap in the channel-path sidecar; when disabled, inference falls back to `delta_independent_approx` |
| `SPDM_CHANNEL_BOOTSTRAP_R` | `1000` | Bootstrap draws |
| `SPDM_CHANNEL_BOOTSTRAP_CORES` | `4` | Parallel bootstrap workers (Windows falls back to sequential) |
| `SPDM_CHANNEL_BOOTSTRAP_METHOD` | `adm_cd_wild_residual` | Bootstrap scheme, clustered at the administrative dong |
| `SPDM_CHANNEL_BOOTSTRAP_SEED` | `cfg$esda_seed` | Seed for the bootstrap draws |
| `SPDM_CHANNEL_IMPACT_SIM_R` | `1000` | Impact simulation draws |
| `SPDM_CHANNEL_IMPACT_CORES` | `4` | Parallel workers for impact simulation |

### GTWR specification

| Variable | Default | Purpose |
| --- | --- | --- |
| `GTWR_CONTROL_SET` | `lean` | `lean` (resident population + land price) or `extended` (adds transit accessibility + workplace workers) |
| `GTWR_KERNEL` | `bisquare` | Local weighting kernel; also accepts `gaussian`, `exponential`, `tricube`, `boxcar`. **Required reporting item** |
| `GTWR_ADAPTIVE` | `true` | Adaptive kernel, so a bandwidth counts neighbours rather than metres |
| `GTWR_ST_BW` | `60` | Fixed adaptive spatiotemporal bandwidth of the active contract |
| `GTWR_LAMDA` | `0.5` | Dimensionless share of weight on the full spatial extent; `0.5` weights space and time equally. Values recorded before 2026-09-02 follow the raw-unit convention and are not comparable |
| `GTWR_KSI` | `0` | Angle parameter of the Huang et al. (2010) spatiotemporal distance; held at the default outside the experiment sidecar. **Required reporting item** |
| `GTWR_BANDWIDTH_STRATEGY` | `fixed` | `fixed`, `full_panel_bw_gtwr`, or `anchor_quarter_bw_gtwr`. The main GTWR never runs `bw.gtwr()` even if this is changed |
| `GTWR_BW_APPROACH` | `CV` | Criterion used by `bw.gtwr()` in the selection sidecar |
| `GTWR_BW_ANCHOR_YQ` | first active quarter | Anchor quarter for `anchor_quarter_bw_gtwr` |
| `GTWR_LOCAL_VIF_WARN_THRESHOLD` | `10` | Local collinearity warning cut-off on `local_vif_max`, the only one of the three measures with an established rule of thumb |
| `GTWR_LOCAL_CN_WARN_THRESHOLD` | `100` | Retained for reference reporting only; does not raise the warning flag |

### GTWR runtime and caching

| Variable | Default | Purpose |
| --- | --- | --- |
| `GTWR_PARALLEL_SPECS` | `5` | Parallel spec workers |
| `GTWR_RESUME_SPECS` | `true` | Reuse valid completed spec caches after an interruption |
| `GTWR_REFRESH_SPEC_CACHE` | `false` | Clear the spec cache and recompute |
| `GTWR_REFRESH_BW_CACHE` | `false` | Recompute the bandwidth-selection cache |
| `GTWR_USE_FROZEN_SPEC` | `true` | Reuse the frozen control/spec contract so sidecars match the baseline |
| `GTWR_REFRESH_FROZEN_SPEC` | `false` | Rebuild the frozen spec record |
| `GTWR_REUSE_ST_DMAT` | `false` | Reuse a cached spatiotemporal distance matrix across specs |
| `GTWR_REFRESH_BANDWIDTH_SENSITIVITY_CACHE` | `false` | Recompute the bandwidth-sensitivity cache |
| `GTWR_REFRESH_LAMDA_SENSITIVITY_CACHE` | `false` | Recompute the lamda-sensitivity cache |
| `GTWR_LEVEL_CONTROL_SET` | `auto` | Force one source family in `05_reporting/03_build_gtwr_level_artifacts.R` |
| `GTWR_LEVEL_TABLE_DIR` | *(empty)* | Override the table directory for GTWR level artifacts |
| `GTWR_LEVEL_INPUT_ROOT` | project root | Override the root the GTWR level artifact builder reads inputs from |

### GTWR sensitivity and search grids

| Variable | Default | Purpose |
| --- | --- | --- |
| `GTWR_BANDWIDTH_SENSITIVITY_GRID` | `30,60,90,120,180` | Fixed adaptive bandwidth grid for `07_run_gtwr_bandwidth_sensitivity.R` |
| `GTWR_LAMDA_SENSITIVITY_GRID` | `0.1,0.25,0.5,0.75,0.9` | Dimensionless lamda grid for `08_run_gtwr_lamda_sensitivity.R` |
| `GTWR_CV_SEARCH_LAMDA_GRID` | `0.1,0.25,0.5,0.75,0.9,0.9867` | Lamda grid for the CV search (`10_search_gtwr_lamda_bw_cv.R`) |
| `GTWR_CV_SEARCH_BW_GRID` | `30,60,90,120,180` | Bandwidth grid for the CV search |
| `GTWR_CV_SEARCH_FOCAL_N` | `300` | Focal subsample size used to estimate the CV surface |
| `GTWR_CV_SEARCH_SEED` | `20260902` | Seed for the focal subsample |

### GTWR experiment sidecar (`05_run_gtwr_experiment.R`)

| Variable | Default | Purpose |
| --- | --- | --- |
| `GTWR_EXPERIMENT_OUTCOMES` | *(empty)* | Outcome subset; empty means the standard five |
| `GTWR_EXPERIMENT_REQUIRED_CONTROLS` | *(empty)* | Controls forced into every candidate |
| `GTWR_EXPERIMENT_OPTIONAL_POOL` | *(empty)* | Optional control pool searched over |
| `GTWR_EXPERIMENT_CONTROL_STRATEGIES` | `baseline` | Control-strategy grid |
| `GTWR_EXPERIMENT_BW_APPROACHES` | `CV` | Bandwidth criteria searched |
| `GTWR_EXPERIMENT_MIN_ST_BW_GRID` | `30` | Minimum bandwidth grid |
| `GTWR_EXPERIMENT_LAMDA_GRID` | `0.05` | Lamda grid. **Raw-unit legacy value**: under the dimensionless convention adopted 2026-09-02, `0.05` no longer means what it did before |
| `GTWR_EXPERIMENT_KSI_GRID` | `0` | Angle-parameter grid; the only place `ksi` is varied |
| `GTWR_EXPERIMENT_TOPN_RAW` | `1` | Number of top candidates whose raw local surfaces are persisted |

## Directory Roles

- `00_setup/`: shared config and package loading (`config.R`, `packages.R`, `install_packages.R`, plus `senior_geocode_manual_fix.csv`)
- `99_utils/`: utility helpers (`utils_age_mix.R`, `utils_esda_maps.R`, `utils_gtwr_main.R`, `utils_io.R`, `utils_model.R`, `utils_qc.R`, `utils_spatial.R`, `utils_spdm.R`, `utils_transform.R`)
- `01_preprocess/`: active short-run quarterly-panel preprocessing
- `02_esda/`: spatial weights and ESDA
- `03_models/`: canonical TWFE and SPDM models, plus the manual GTWR main (`03_run_gtwr_main.R`)
- `04_robustness/`: SPDM W robustness and supplementary robustness
- `05_reporting/`: tables, figures, presentation, and GTWR artifact builders
- `06_qc/`: active QC plus manual audit helpers
- `80_optional/`: manual direct-run preprocessing, TWFE, SPDM, and GTWR sidecars
- `90_templates/`: preprocessing and modeling templates (`00_template_preprocessing_aging_commerce.R`, `00_template_modeling_aging_commerce.R`)
- `95_tests/`: numeric regression tests for the utility functions that produce reported quantities

## Tests

```bash
Rscript 02_Code/95_tests/run_tests.R    # exits 0 on pass, 1 on failure
```

127 assertions over five utility surfaces that compute reported quantities:

- `compute_true_sdm_effects()` — LeSage-Pace direct/indirect/total impacts
- `build_gtwr_st_dmat()` with its `gtwr_st_combine()` / `gtwr_st_scales()` helpers — the symmetric spatiotemporal distance that replaced the defective `GWmodel::ti.distv()` time comparison
- `weighted_design_collin_diag()` — local VIF and condition numbers
- `extract_gtwr_local_inference()` — the GTWR local standard errors and t-values that `GWmodel::gtwr()` returns per estimation point, which the extraction previously discarded
- `build_spdm_reduced_form_resampler()` with `spdm_within_transform()` — the reduced form `y* = S(Z gamma + e*)` the channel-path bootstrap resamples through, and its round-trip guard

The suite is base R with no `testthat` dependency, runs in a few seconds, needs no pipeline output, and should be run before committing any change to `99_utils/`. Checks that compare against `03_Output/01_Tables/spdm_impacts.csv` skip rather than fail when the outputs are absent, so it works on a fresh clone.

## Specification Navigation

- Spec hub: [00_spec_index.md](../04_Docs/02_Codebook/00_spec_index.md)
- Data spec: [01_data_spec.md](../04_Docs/02_Codebook/01_data_spec.md)
- Variable dictionary: [02_variable_dictionary.md](../04_Docs/02_Codebook/02_variable_dictionary.md)
- Join / harmonization rules: [03_join_harmonization_rules.md](../04_Docs/02_Codebook/03_join_harmonization_rules.md)
- Model spec: [04_model_spec.md](../04_Docs/02_Codebook/04_model_spec.md)
- Spec-to-code map: [99_spec_to_code_map.csv](../04_Docs/02_Codebook/99_spec_to_code_map.csv)
