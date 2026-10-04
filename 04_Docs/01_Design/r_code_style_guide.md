# R Code Style Guide

> **Last updated**: 2026-09-05

This document defines the R coding standards specific to this project to implement the active quarterly workflow. It has three main objectives:

- Align the contract between documentation and code.
- Separate the canonical workflow from the optional/manual surface.
- Maintain reproducibility and verifiability.

## 1. Design Alignment Principles

The research contract that code must not compromise is the seventeen-item list in [research_procedure.md section 1.2](research_procedure.md), and model parameter values are contracted in [04_model_spec.md](../02_Codebook/04_model_spec.md). Both are authoritative; this guide does not restate them, because an earlier copy of eleven of those seventeen items here made this document a fourth place a contract value could silently diverge.

What this guide adds is the code-side obligation attached to that contract:

1. Read contract values from `cfg`, never as literals in a script. A hard-coded bandwidth, analysis window, key set, or lag depth is a defect even when the number is currently correct, because it cannot be changed in one place.
2. Assert the contract at input validation rather than assuming it. A script that requires the `adm_cd-yq` unique key must check it and fail loudly, not proceed on a silently duplicated key.
3. When a script must deviate from the contract, record the deviation in [decision_log.md](../03_Log/decision_log.md) and in the affected design document in the same change, not afterwards.

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
- `90_templates`: shared implementation pattern. Refer to [00_template_preprocessing_aging_commerce.R](../../02_Code/90_templates/00_template_preprocessing_aging_commerce.R) for preprocessing scripts and [00_template_modeling_aging_commerce.R](../../02_Code/90_templates/00_template_modeling_aging_commerce.R) for modeling/diagnostics scripts as specific templates.
- `95_tests`: numeric regression tests, run with `Rscript 02_Code/95_tests/run_tests.R`
- `99_utils`: shared utilities, including GTWR helper logic used by optional sidecars

## 2.1 Testing Obligation

A utility function that computes a **reported quantity** needs a test, because a wrong number is silent in a way that a wrong pipeline is not: the run succeeds, the table is written, and only the value is incorrect. On that basis `95_tests` covers the SDM impact formula, the spatiotemporal distance, the local collinearity diagnostics, the GTWR local standard-error and t-value extraction, and the reduced-form resampler behind the channel-path bootstrap.

Prefer closed-form assertions to stored snapshots. A snapshot only proves the output has not changed; an identity proves it is right. The suite uses, for example, `total = (beta + theta)/(1 - rho)`, which holds exactly for any row-standardised `W`, and the weighted VIF identity `1/(1 - r^2)`. Where a historical defect motivated a rewrite, pin the defect directly, as the `ti.distv()` time-comparison tests do.

Run the suite before committing a change to `99_utils`, and mutation-test any new assertion by breaking the function on purpose and confirming the suite goes red. The suite adds no dependency: it is base R, because `testthat` is not in `renv.lock` and a test harness is a poor reason to change a pinned analysis environment.

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
- `03_run_exploratory_diagnostics.R`
- `01_run_twfe_main.R`
- `02_run_spdm_main.R`
- `01_run_spdm_w_robustness.R`
- `02_run_robustness.R`
- `03_run_influence_robustness.R`
- `04_run_identification_diagnostics.R`
- `05_run_evidence_synthesis.R`
- `01_validate_method_dataset_alignment.R`
- `01_make_tables_figures.R`
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

Output and intermediate paths belong in the canonical registry in [config.R](../../02_Code/00_setup/config.R) (`cfg$paths`, `cfg$logs`, `cfg$get_*_path()`), not in the script that happens to write them. A path in the registry can be validated by QC, reused by reporting, and changed in one place.

Two honest qualifications, so the rule is followed rather than admired:

1. **Dynamic paths are exempt.** A filename built from a variable name or a control-set token — `distribution_map__%s.png`, `gtwr_main_models_<control_set>.csv` — cannot be a static registry entry. Build these with `sprintf()` at the call site, or with a registry *getter* that takes the varying part as an argument, which is the pattern `cfg$get_gtwr_main_models_path(control_set)` uses.
2. **Do not reintroduce the defensive fallback.** Patterns like `value_or(cfg$paths$x, file.path(cfg$dir_tables, "x.csv"))` and its `if (!is.null(cfg$paths$x)) ... else ...` equivalent were removed on 2026-09-04. They read as safety but are dead code: `config.R` always defines the entry, so the literal never fires — except on the one path that matters, where someone renames the registry key and the fallback silently starts writing to the old filename instead of failing. Call the registry entry directly and let a missing key be an error.

As of 2026-09-04 every output and log path in `02_Code/**` comes from the registry. The four remaining `file.path(cfg$dir_*, "literal")` expressions are raw **input** directory names (`cfg$dir_raw` and `cfg$dir_boundary` source folders), which are a separate contract from the output registry and are deliberately left in place.

## 6. Variable Naming Conventions

- Identifiers: `adm_cd`, `year`
- Log transformations: `ln_`
- Standardization: `_z`
- Spatial lags: `w_`
- Composite indices: `vitality_index_*`

There is no winsorization suffix, because there is no winsorization. [research_procedure.md section 2.9](research_procedure.md) states the outlier policy as a decision rather than an omission: no winsorising, trimming, or robust standardization is applied at any stage, and the price of that decision is paid by reporting the influence diagnostic beside the impacts. The `_w` convention and the `winsorize_vec()` helper were removed on 2026-09-05 so that neither reads as an available option. Reintroducing either is a design change that belongs in [decision_log.md](../03_Log/decision_log.md) first.

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
- Report significance for the main SPDM from `run_spdm_impact_bootstrap()`, the dong-level wild bootstrap through the reduced form, never from `vcov()` of an `splm` fit. That matrix treats a dong's errors as independent across quarters, and `splm` returns it with the covariance between `rho` and the coefficients set to zero. Draw one Rademacher weight per dong, not per row; a per-row weight breaks the serial dependence the bootstrap exists to carry. Keep model-based values only as `*_model` columns.
- Handle alternative W matrices in a separate robustness family.

### GTWR

- GTWR scripts under `80_optional/gtwr` also follow the manual direct-run contract.
- Restrict to quarterly resident-only local heterogeneity analysis.
- Use `GTWR_CONTROL_SET=lean` as the default; use extended only when explicitly chosen.
- Fix lean controls to `lag4_ln_resident_pop` and `lag4_ln_land_price_adjusted`.
- Extended controls add `lag4_transit_accessibility` and `lag4_ln_workplace_worker_pop` to the lean controls.
- Construct `transit_accessibility` as the pooled z-score average of `bus_stop_count_aux` and `subway_station_count_aux`; do not input these two raw counts directly as model controls.
- Save three GTWR spatiotemporal weight-based local collinearity diagnostics: `local_vif_max`, `local_cn_centered`, and the uncentered `local_cn_gtwr`. Flag on `local_vif_max` only, since VIF > 10 is the sole criterion with an established convention; report the two condition numbers without thresholds and do not describe either as correcting the other.
- Build the spatiotemporal distance matrix with `build_gtwr_st_dmat()` and pass it to every `bw.gtwr()` and `gtwr()` call as `st.dMat`. Never let GWmodel rebuild it internally: `GWmodel::ti.distv()` compares times as strings and mislabels past quarters as future for integer period ids.
- Keep `lamda` dimensionless by normalizing the spatial and temporal distances by their own spans (`gtwr_st_scales()`) before combining them, and compute the scales once per estimation sample so every column of a spec's distance matrix shares them. Do not compare `lamda` values across the raw-unit and dimensionless conventions.
- Unify bandwidth in main GTWR to the fixed adaptive value contracted in [04_model_spec.md section 7.0](../02_Codebook/04_model_spec.md), read from `cfg$gtwr_st_bw` rather than written as a literal. Perform `bw.gtwr()` search only in `06_select_gtwr_bandwidth.R`, fixed grid sensitivity in `07_run_gtwr_bandwidth_sensitivity.R`, and lamda grid sensitivity only in `08_run_gtwr_lamda_sensitivity.R`; both grids come from `cfg$gtwr_bandwidth_sensitivity_grid` and `cfg$gtwr_lamda_sensitivity_grid`.
- The `estimate` in the main output is the latest-quarter local beta, whereas delta is calculated only in supplementary reporting tables.
- Long-running executions must be resumable via outcome-exposure spec caches, limiting worker nodes with `GTWR_PARALLEL_SPECS`.

## 10. Logging and QC

- The canonical pipeline and the heavy manual GTWR entry point record their execution environment before the first step. `run_all.R` and `03_run_gtwr_main.R` call `log_run_environment()` from `utils_io.R`, which appends the R version, platform, renv library, `renv.lock` md5 and lock R version, output tag, and the version of every project package to `model_run_log.md`. GTWR, SPDM, and the permutation diagnostics are version-sensitive, so an output is only auditable when the log states which environment produced it. Environment capture must never abort a run: it is wrapped so a missing optional package or unreadable lockfile degrades to a logged note.
- Shared helpers live in one file only. `value_or()` belongs to `utils_io.R`, and the deterministic permutation seeding pair `deterministic_seed_from_label()` / `with_deterministic_seed()` belongs to `utils_spatial.R` next to the Moran alignment helpers. Do not redefine a shared helper inside a script: because every script sources the utilities into one environment, a local copy silently shadows the shared one for that whole script and the two definitions drift apart unnoticed.
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
