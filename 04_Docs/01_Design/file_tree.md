# Project File Tree

This document provides a comprehensive snapshot of all tracked files in the repository. 
For detailed information regarding code execution or variables, please refer to `02_Code/README.md` and the documents in `04_Docs/02_Codebook/`.

```text
├── .gitignore                                     # Git ignore list
├── AGENTS.md                                      # Guidelines for AI agent operations
├── R.Rproj                                        # RStudio project configuration
├── README.md                                      # Main project overview and guide
│
├── 02_Code/                                       # Analysis pipeline scripts
│   ├── README.md                                  # Detailed guide for running code
│   ├── run_all.R                                  # Automated end-to-end execution script
│   │
│   ├── 00_setup/                                  # Environment and shared settings
│   │   ├── config.R                               # Global constants, paths, and toggles
│   │   ├── install_packages.R                     # Package installer
│   │   ├── packages.R                             # Package loader
│   │   └── senior_geocode_manual_fix.csv          # Manual corrections for senior facility geocoding
│   │
│   ├── 01_preprocess/                             # Data generation and panel construction
│   │   ├── 01_build_adm_region_lookup.R
│   │   ├── 02_build_seoul_quarter_base.R
│   │   ├── 03_build_auxiliary_covariates.R
│   │   ├── 04_build_golmok_survival_rate.R
│   │   ├── 05_build_registered_resident_population.R
│   │   ├── 06_build_analysis_panel.R
│   │   └── 07_build_vitality_index.R
│   │
│   ├── 02_esda/                                   # Spatial weights and autocorrelation
│   │   ├── 01_build_spatial_weights.R
│   │   └── 02_run_esda.R
│   │
│   ├── 03_models/                                 # Core canonical models
│   │   ├── 01_run_twfe_main.R                     # TWFE baseline
│   │   ├── 02_run_spdm_main.R                     # SPDM global spatial model
│   │   └── 03_run_gtwr_main.R                     # GTWR local spatial model
│   │
│   ├── 04_robustness/                             # Robustness checks
│   │   ├── 01_run_spdm_w_robustness.R             # SPDM spatial weights robustness
│   │   └── 02_run_robustness.R                    # Alternative robustness checks
│   │
│   ├── 05_reporting/                              # Outputs, tables, and visualization
│   │   ├── 01_make_tables_figures.R
│   │   ├── 02_build_presentation_artifacts.R
│   │   └── 03_build_gtwr_level_artifacts.R
│   │
│   ├── 06_qc/                                     # Quality Control (QC)
│   │   ├── 01_validate_method_dataset_alignment.R
│   │   ├── 02_check_processed_parquet_outputs.R
│   │   └── 03_open_outputs_for_rstudio_review.R
│   │
│   ├── 80_optional/                               # Supplementary, sensitivity, and path analyses
│   │   ├── gtwr/
│   │   │   ├── 01_run_gtwr_floating_only.R
│   │   │   ├── 02_run_gtwr_age_band.R
│   │   │   ├── 03_run_gtwr_sector_share.R
│   │   │   ├── 04_run_gwr_delta.R
│   │   │   ├── 05_run_gtwr_experiment.R
│   │   │   ├── 06_select_gtwr_bandwidth.R
│   │   │   ├── 07_run_gtwr_bandwidth_sensitivity.R
│   │   │   └── 08_run_gtwr_lamda_sensitivity.R
│   │   ├── preprocess/
│   │   │   └── 01_build_living_population_inflow.R
│   │   ├── spdm/
│   │   │   ├── 01_run_spdm_interaction_models.R
│   │   │   ├── 02_run_spdm_age_mix_experiment.R
│   │   │   ├── 03_run_spdm_sector_share_experiment.R
│   │   │   ├── 04_run_spdm_selection_sidecar.R
│   │   │   ├── 05_run_spdm_family_comparison_sidecar.R
│   │   │   ├── 06_run_spdm_vitality_component_models.R
│   │   │   └── 07_run_spdm_channel_path.R
│   │   └── twfe/
│   │       ├── 01_run_twfe_channel_models.R
│   │       ├── 02_run_twfe_interaction_models.R
│   │       ├── 03_run_twfe_age_mix_experiment.R
│   │       └── 04_run_twfe_vitality_component_models.R
│   │
│   ├── 90_templates/                              # Boilerplate templates
│   │   ├── 00_template_modeling_aging_commerce.R
│   │   └── 00_template_preprocessing_aging_commerce.R
│   │
│   └── 99_utils/                                  # Utility scripts for reuse
│       ├── utils_age_mix.R
│       ├── utils_esda_maps.R
│       ├── utils_gtwr_main.R
│       ├── utils_io.R
│       ├── utils_model.R
│       ├── utils_qc.R
│       ├── utils_spatial.R
│       ├── utils_spdm.R
│       └── utils_transform.R
│
└── 04_Docs/                                       # Design docs and Codebooks
    ├── 01_Design/
    │   ├── file_tree.md                           # Project file tree (this file)
    │   ├── r_code_style_guide.md                  # R coding conventions
    │   ├── research_plan.md                       # Active research goals and framing
    │   └── research_procedure.md                  # Project procedure pipeline
    │
    └── 02_Codebook/
        ├── 00_spec_index.md                       # Main index of codebook specs
        ├── 01_data_spec.md                        # Explanations of data sources
        ├── 01_data_spec_datasets.csv              # List of source datasets
        ├── 02_variable_dictionary.md              # Variable definitions and logic
        ├── 02_variable_dictionary.csv             # Machine-readable variables list
        ├── 03_join_harmonization_rules.md         # Spatial and temporal join rules
        ├── 03_join_harmonization_rules.csv        # Machine-readable join rules
        ├── 04_model_spec.md                       # Econometric models specifications
        ├── 04_model_spec.csv                      # Machine-readable models list
        └── 99_spec_to_code_map.csv                # Mapping between specs and scripts
```
