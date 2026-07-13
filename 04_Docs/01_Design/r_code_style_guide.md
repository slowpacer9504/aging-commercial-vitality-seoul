# R Code Style Guide

This document defines the R coding standards specific to this project to implement the active quarterly workflow. It has three main objectives:

- Align the contract between documentation and code.
- Separate the canonical workflow from the optional/manual surface.
- Maintain reproducibility and verifiability.

## 1. Design Alignment Principles

The following principles must not be compromised in the code.

1. The spatial unit is the Seoul administrative dong (`adm_cd`) based on `2020` boundaries.
2. The active canonical panel construction period is `2019Q1~2025Q4`, and the active analysis sample is `2019Q4~2025Q4`.
3. The time keys of the active shared panel are `year`, `quarter`, `yq`, and `quarter_index`. The unique key is `adm_cd-yq`.
4. The main exposure is `lag4_age60_resident_share`.
5. The canonical timing contract uses a 4-quarter lag for exposure and controls, and a 2-quarter lag for channel mediators.
6. The default spatial weights matrix W is `Queen`, while `Rook`, `kNN6`, and `kNN8` are for robustness checks.
7. The active method stack is `ESDA -> TWFE -> SPDM -> GTWR (optional)`.
8. TWFE serves as the baseline / spatial diagnostic layer.
9. SPDM is the main global model.
10. GTWR is a resident-only optional local sidecar.
11. Quarterly raw data is directly issued as the base time unit of the active shared panel. Yearly/static sources are joined to `adm_cd-yq` via explicit as-of rules.

## 2. Interpreting the Project Structure

The directory structure should be read as follows to instantly differentiate the active from the optional surface.

- `00_setup`: active config and package loading
- `01_preprocess`: quarterly panel preprocessing
- `02_esda`: active ESDA and spatial weights
- `03_models`: canonical TWFE and SPDM models
- `04_robustness`: SPDM W robustness and supplementary robustness
- `05_reporting`: tables, figures, presentation, and GTWR artifact builders
- `06_qc`: active QC plus manual audit helpers
- `80_optional`: manual direct-run preprocessing, TWFE, SPDM, and GTWR sidecars
- `90_templates`: shared implementation pattern
- `99_utils`: shared utilities, including GTWR helper logic used by optional sidecars

## 3. Filenames and Script Roles

The active canonical surface follows this execution order:

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
- `01_make_tables_figures.R`
- `01_validate_method_dataset_alignment.R`
- `run_all.R`

The optional/manual surface is separated from the active canonical surface by directories and filenames such as `80_optional/**`, `05_reporting/02_*`, `05_reporting/03_*`, `06_qc/02_*`, and `06_qc/03_*`.
Scripts under `80_optional/**` are excluded from `run_all.R`, and when executed directly, they perform their tasks without requiring a separate `RUN_*` execution flag.
The SPDM channel path is an optional/manual sidecar located at `02_Code/80_optional/spdm/07_run_spdm_channel_path.R`.

## 4. File Header Rules

Every script must contain the following metadata at the top:

- `Script`
- `Project`
- `Purpose`
- `Author`
- `Created`
- `Type`
- `Inputs`
- `Outputs`
- `DependsOn`

For optional/manual scripts, clearly state their status in the header or early comments.

## 5. Input-Process-Output Structure

Scripts must explicitly maintain the following flow:

1. setup
2. input validation
3. helper definitions
4. main transformation / model fit
5. output write
6. log append

When reading intermediate outputs, prioritize the canonical path registry. Do not invent new filenames within the script.

## 6. Variable Naming Conventions

- Identifiers: `adm_cd`, `year`
- Log transformations: `ln_`
- Standardization: `_z`
- Winsorization: `_w`
- Spatial lags: `w_`
- Composite indices: `vitality_index_*`

In vitality index calculations, `_z` defaults to a pooled z-score based on the mean and standard deviation of the active analysis sample (`2019Q4~2025Q4 adm_cd-yq`). Auxiliary analyses requiring quarterly cross-section standardization must be separated from the active variable name with a distinct suffix.

Keep `year`, `quarter`, `yq`, and `quarter_index` in the active shared panel. Legacy shift/lead suffixes and raw `quarter_code_raw` should only be used in local objects within preprocessing and must be removed prior to quarterly publication.

## 7. Commenting Standards

Comments must explain contracts, not syntax.

Points that must be explained:

- canonical source selection
- quarterly publication / as-of rule
- weighted vs unweighted quarterly aggregation choice
- control exclusion rules
- complete-case sample determination
- spatial weights construction and W choice
- TWFE residual Moran diagnostics
- SPDM impacts calculation
- optional GTWR gating

Comments to avoid:

- Literal translations of single lines of code
- Canonical quarterly descriptions that conflict with the current design
- Explanations that exaggerate GTWR as a global causal model

## 8. Preprocessing Principles

- Enforce the `adm_cd-yq` unique key first.
- Do not aggregate additive flows and levels/shares using the same method.
- Maintain source precision for annual/static auxiliaries before joining them via quarter-end as-of rules.
- Maintain `panel_merged_base.parquet` as a provenance checkpoint.
- Retain only shared quarterly transforms and contemporaneous variables in `panel_main_pre_vitality.parquet`.

## 9. Modeling Principles

### TWFE

- Treat as the baseline model.
- Fix the FE structure to `| adm_cd + yq`.
- Save residual Moran outputs as a mandatory artifact.
- Exclude controls that overlap with the outcome for each respective outcome.

### SPDM

- Use the resident-only main exposure by default.
- The true SDM contract includes `W y`, `X`, and `W X`.
- Do not rely on Durbin placeholders in `splm::spml()` calls; explicitly create `W lag4_age60_resident_share` and `W controls`.
- Focus on saving direct / indirect / total effect tables rather than coefficient tables.
- Calculate direct / indirect / total effects using the SDM impact matrix.
- Handle alternative W matrices in a separate robustness family.

### GTWR

- GTWR scripts under `80_optional/gtwr` also follow the manual direct-run contract.
- Restrict to quarterly resident-only local heterogeneity analysis.
- Use `GTWR_CONTROL_SET=lean` as the default; use extended only when explicitly chosen.
- Fix lean controls to `lag4_ln_resident_pop` and `lag4_ln_land_price_adjusted`.
- Extended controls add `lag4_transit_accessibility` and `lag4_ln_workplace_worker_pop` to the lean controls.
- Construct `transit_accessibility` as the pooled z-score average of `bus_stop_count_aux` and `subway_station_count_aux`; do not input these two raw counts directly as model controls.
- Save the GTWR spatiotemporal weight-based local condition-number as a diagnostic.
- Unify bandwidth in main GTWR to a fixed `GTWR_ST_BW=60`. Perform `bw.gtwr()` search only in `06_select_gtwr_bandwidth.R`, fixed grid `(30,60,90,120,180)` sensitivity in `07_run_gtwr_bandwidth_sensitivity.R`, and lambda grid sensitivity only in `08_run_gtwr_lamda_sensitivity.R`.
- The `estimate` in the main output is the latest-quarter local beta, whereas delta is calculated only in supplementary reporting tables.
- Long-running executions must be resumable via outcome-exposure spec caches, limiting worker nodes with `GTWR_PARALLEL_SPECS`.

## 10. Logging and QC

- Halt immediately with a clear error on input missing.
- For optional source missing, clear or skip the source-dependent artifact without failing the entire active run.
- QC failures must be determined based solely on the active quarterly contract. Exclude optional/sidecar scripts from the required test plan.

## 11. Documentation Update Rules

When a design changes, review at least the following order together:

1. `research_plan.md`
2. `research_procedure.md`
3. `00_spec_index.md`
4. Related codebook docs
5. `config.R`
6. `run_all.R`
7. QC / reporting

In the preliminary documentation stage, documents can declare the quarterly final state first. However, the subsequent code stage must immediately follow up with config, preprocess, model, and QC under the same contract.
