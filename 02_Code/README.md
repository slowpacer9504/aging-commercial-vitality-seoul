# 02_Code

## Quick Start

1. Open `R.Rproj` so `here::here()` resolves the project root correctly.
2. Install packages once on a new machine:

```r
source("02_Code/00_setup/install_packages.R")
```

3. If auxiliary preprocessing needs fresh geocoding beyond the existing cache, set:

```r
Sys.setenv(KAKAO_REST_API_KEY = "your_kakao_rest_api_key")
```

4. Run the canonical default pipeline:

```r
source("02_Code/run_all.R")
```

Command-line alternative:

```bash
Rscript 02_Code/run_all.R
```

`80_optional/preprocess/01_build_living_population_inflow.R` streams large Seoul Living Population ZIP files. For a smoke test without overwriting the canonical output, set `LIVING_POP_SAMPLE_MONTHS=201901`; the script writes sample-tagged output paths.

## Active Canonical Workflow

The active default order is:

- `01_build_adm_region_lookup.R`
- `02_build_seoul_quarter_base.R`
- `03_build_auxiliary_covariates.R`
- `04_build_golmok_survival_rate.R`
- `05_build_registered_resident_population.R`
- `06_build_analysis_panel.R`
- `07_build_vitality_index.R`
- `01_build_spatial_weights.R`
- `02_run_esda.R`
- `01_run_twfe_main.R`
- `02_run_spdm_main.R`
- `01_run_spdm_w_robustness.R`
- `02_run_robustness.R`
- `01_validate_method_dataset_alignment.R`
- `01_make_tables_figures.R`

Manual optional preprocessing and local-analysis sidecars:

- `80_optional/preprocess/01_build_living_population_inflow.R`
- `80_optional/spdm/07_run_spdm_channel_path.R`
- `80_optional/gtwr/01_run_gtwr_main.R`
- helper implementation in `R/utils_gtwr_main.R`
- `80_optional/**` scripts are outside `run_all.R`; execute a file directly to run it.
- run SPDM channel path manually with `Rscript 02_Code/80_optional/spdm/07_run_spdm_channel_path.R`
- run GTWR manually with `Rscript 02_Code/80_optional/gtwr/01_run_gtwr_main.R`
- control set with `GTWR_CONTROL_SET=lean|extended`; `lean` is the default and `extended` adds transit-accessibility and additional location controls
- parallel specs with `GTWR_PARALLEL_SPECS=<n>`
- resume completed spec cache with `GTWR_RESUME_SPECS=TRUE`
- clear spec cache and recompute all specs with `GTWR_REFRESH_SPEC_CACHE=TRUE`
- bandwidth defaults to `GTWR_BANDWIDTH_STRATEGY=fixed` and `GTWR_ST_BW=480`
- bandwidth search uses `02_Code/80_optional/gtwr/07_select_gtwr_bandwidth.R` plus `GTWR_BANDWIDTH_STRATEGY=full_panel_bw_gtwr|anchor_quarter_bw_gtwr`; recompute that cache with `GTWR_REFRESH_BW_CACHE=TRUE`
- main GTWR outputs are tagged by control set, e.g. `gtwr_main_models_lean.csv`
- main reporting uses latest-quarter local beta; delta is written only to `gtwr_delta_*` appendix tables

Manual QC / reporting sidecars:

- `06_qc/02_check_processed_parquet_outputs.R`
- `06_qc/03_open_outputs_for_rstudio_review.R`
- `05_reporting/02_build_presentation_artifacts.R`
- `05_reporting/03_build_gtwr_level_artifacts.R`

## Directory Roles

- `00_setup`: shared config and package loading
- `R`: utility helpers
- `01_preprocess`: active short-run quarterly-panel preprocessing
- `02_esda`: spatial weights and ESDA
- `03_models`: canonical TWFE and SPDM models
- `04_robustness`: SPDM W robustness and supplementary robustness
- `05_reporting`: tables, figures, presentation, and GTWR artifact builders
- `06_qc`: active QC plus manual audit helpers
- `80_optional`: manual direct-run preprocessing, TWFE, SPDM, and GTWR sidecars
- `90_templates`: preprocessing and modeling templates

Retired long-run harmonization and classification branches are no longer part of the project surface. The codebase now assumes a short-run Seoul quarterly panel only.

## Specification Navigation

- Spec hub: `04_Docs/02_Codebook/00_spec_index.md`
- Data spec: `04_Docs/02_Codebook/01_data_spec.md`
- Variable dictionary: `04_Docs/02_Codebook/02_variable_dictionary.md`
- Join / harmonization rules: `04_Docs/02_Codebook/03_join_harmonization_rules.md`
- Model spec: `04_Docs/02_Codebook/04_model_spec.md`
- Spec-to-code map: `04_Docs/02_Codebook/99_spec_to_code_map.csv`
