# Project File Tree

This document provides a comprehensive snapshot of all tracked files in the repository. 
For detailed information regarding code execution or variables, please refer to `02_Code/README.md` and the documents in `04_Docs/02_Codebook/`.

```text
├── README.md                                      # Main project overview and guide
│
├── 01_Data/                                       # Data directory (Git untracked except directory structure)
│   ├── 01_Raw_Data/                               # Raw public datasets (01~14)
│   │   ├── 01_Seoul_Commercial_District_Administrative_Dong/
│   │   ├── 02_서울생활인구_관내이동/
│   │   ├── 03_서울생활인구_대도시권_내외국인/
│   │   ├── 04_주민등록인구현황_행정구역(읍면동)별:5세별 주민등록인구(2019~2025, 월)/
│   │   ├── 05_서울시_공동주택_아파트_정보/
│   │   ├── 06_한국부동산원_전국지가변동률조사/
│   │   ├── 07_서울시_사업체현황(종사자규모별:동별)_통계/
│   │   ├── 08_서울시_대규모점포_인허가_정보/
│   │   ├── 09_서울시_병의원_인허가_정보/
│   │   ├── 10_노인복지시설/
│   │   ├── 11_서울시_역사_마스터_정보/
│   │   ├── 12_서울시_버스정류소_위치_정보/
│   │   ├── 13_도로/
│   │   └── 14_보도/
│   │
│   ├── 02_Boundary/                               # Spatial boundary files (SHPs, GeoJSONs)
│   │   ├── 01_Seoul/                              # Seoul administrative district boundary
│   │   ├── 02_Commercial_District/                # Commercial district spatial boundaries
│   │   ├── 03_Land_Price/                         # Land price zone boundaries
│   │   ├── 04_Park/                               # Park and green zone spatial data
│   │   └── 05_수치표고모델(DEM)_90M/              # Digital elevation model for slope calculation
│   │
│   └── 03_Processed_Data/                         # Preprocessed intermediate & final data
│       ├── 01_Intermediate/                       # Intermediate files (geocode caches, crosswalks)
│       ├── 02_Analysis_Ready/                     # Analyzable variables parquet datasets
│       └── 03_Panel/                              # Final merged analysis panel (panel_main.parquet)
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
├── 03_Output/                                     # Output artifacts (Git untracked except directory structure)
│   ├── 01_Tables/                                 # Statistical tables (CSVs, HTMLs)
│   ├── 02_Figures/                                # Model diagnostics and coefficient plots (PNGs)
│   ├── 03_Maps/                                   # Local coefficient spatial distribution maps (PNGs)
│   ├── 04_Logs/                                   # Process, geocoding, and runtime cache logs
│   └── 05_report/                                 # Publication-ready presentation materials
│
└── 04_Docs/                                       # Design docs and Codebooks
    ├── file_tree.md                               # Project file tree (this file)
    │
    ├── 01_Design/
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
