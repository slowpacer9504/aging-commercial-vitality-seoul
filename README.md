# The Impact of Population Aging on Neighborhood Commercial Vitality: A Spatiotemporal Analysis Using Seoul Big Data

This project is an analysis codebase and research specification package designed to estimate the direct and indirect impacts of population aging on the commercial vitality of neighborhood commercial districts (at the administrative-dong level) in Seoul, as well as their spatiotemporal heterogeneity.

---

## 1. Directory Structure

This repository is structured as follows to maximize research reproducibility:

```text
├── 01_Data/                  # Data for analysis (Excluded from Git tracking)
│   ├── 01_Raw_Data/          # Collected raw public data
│   ├── 02_Boundary/          # Seoul administrative-dong boundary spatial data
│   └── 03_Processed_Data/    # Preprocessed and joined analysis panel data
│
├── 02_Code/                  # Analysis pipeline scripts
│   ├── 00_setup/             # Package installation and shared configurations
│   ├── 01_preprocess/        # Quarterly panel data construction and variable/vitality index generation
│   ├── 02_esda/              # Spatial weights matrix construction and spatial autocorrelation diagnostics (Moran's I, LISA)
│   ├── 03_models/            # Panel model estimation (TWFE baseline, SPDM main, GTWR local sidecar)
│   ├── 04_robustness/        # Model robustness checks (spatial weights matrix sensitivity, etc.)
│   ├── 05_reporting/         # Generation of results tables and visualization figures
│   ├── 06_qc/                # Data contracts and model consistency quality control (QC)
│   ├── 80_optional/          # Supplementary analysis scripts such as interaction and mediation path analyses
│   ├── 90_templates/         # Execution templates for writing code
│   ├── 99_utils/             # Shared utility helper functions (.R)
│   ├── run_all.R             # Automated end-to-end pipeline execution script
│   └── README.md             # Detailed guide for the analysis code
│
├── 03_Output/                # Model estimation results, reporting tables, and figures (Excluded from Git tracking)
│
├── 04_Docs/                  # Research specifications and guidelines
│   ├── 01_Design/            # Research plan and procedural manual
│   └── 02_Codebook/          # Specifications mapping data specs, variable dictionary, and model specs
│
├── README.md                 # This main guide document
├── AGENTS.md                 # Agent operation guidelines (Excluded from Git tracking)
└── R.Rproj                   # RStudio project file
```

---

## 2. Quick Start

This analysis uses the `here` package to automatically recognize the project root directory. To ensure reproducibility, you must start the analysis by opening the `R.Rproj` file first.

### 2.1 Package Installation
When setting up the environment for the first time, run the following script to install all required R packages at once.
```R
source("02_Code/00_setup/install_packages.R")
```

### 2.2 Running the Full Pipeline
To execute the entire default pipeline—from data preprocessing to model estimation and the output of tables and figures—run the following command:
```R
source("02_Code/run_all.R")
```
Alternatively, you can run it from the terminal (Bash) as follows:
```bash
Rscript 02_Code/run_all.R
```

---

## 3. Documentation Reference

For detailed theoretical backgrounds, variable definitions, and model equations of the research, please refer to the following documents:

* **Research Plan Summary**: [research_plan.md](04_Docs/01_Design/research_plan.md)
* **Step-by-step Procedure**: [research_procedure.md](04_Docs/01_Design/research_procedure.md)
* **Project File Tree**: [file_tree.md](04_Docs/01_Design/file_tree.md)
* **Variable and Model Specification Hub**: [00_spec_index.md](04_Docs/02_Codebook/00_spec_index.md)
