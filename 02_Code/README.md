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
- `02_Code/03_models/01_run_twfe_main.R`
- `02_Code/03_models/02_run_spdm_main.R`
- `02_Code/04_robustness/01_run_spdm_w_robustness.R`
- `02_Code/04_robustness/02_run_robustness.R`
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

> Note: `06_select_gtwr_bandwidth.R` is a bandwidth *search* utility rather than an experiment runner; it is documented under the GTWR local-analysis section above.

### Manual QC & Reporting Sidecars

- **QC Processed Outputs**: `02_Code/06_qc/02_check_processed_parquet_outputs.R`
- **Review Outputs in RStudio**: `02_Code/06_qc/03_open_outputs_for_rstudio_review.R`
- **Build Presentation Artifacts**: `02_Code/05_reporting/02_build_presentation_artifacts.R`
- **Build GTWR Level Artifacts**: `02_Code/05_reporting/03_build_gtwr_level_artifacts.R`

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

## Specification Navigation

- Spec hub: [00_spec_index.md](../04_Docs/02_Codebook/00_spec_index.md)
- Data spec: [01_data_spec.md](../04_Docs/02_Codebook/01_data_spec.md)
- Variable dictionary: [02_variable_dictionary.md](../04_Docs/02_Codebook/02_variable_dictionary.md)
- Join / harmonization rules: [03_join_harmonization_rules.md](../04_Docs/02_Codebook/03_join_harmonization_rules.md)
- Model spec: [04_model_spec.md](../04_Docs/02_Codebook/04_model_spec.md)
- Spec-to-code map: [99_spec_to_code_map.csv](../04_Docs/02_Codebook/99_spec_to_code_map.csv)
