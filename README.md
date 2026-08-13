# The Impact of Population Aging on Neighborhood Commercial Vitality: A Spatiotemporal Analysis Using Seoul Big Data

This project is an analysis codebase and research specification package designed to estimate the direct and indirect impacts of population aging on the commercial vitality of neighborhood commercial districts (at the administrative-dong level) in Seoul, as well as their spatiotemporal heterogeneity.

## Research Framework

The figure below summarizes the conceptual pathway from population aging to neighborhood commercial vitality and the empirical methods used to estimate it (English rendering of `03_Output/05_report/figure_1_1_research_framework_clean`):

![Research framework](04_Docs/01_Design/figure_1_1_research_framework_en.png)

> **Figure 1.** Research framework: theoretical background and mechanism (top), empirical analysis framework (middle), and analytical methods with results and implications (bottom).

---

## 1. Quick Start

This analysis uses the `here` package to automatically recognize the project root directory. To ensure reproducibility, you must start the analysis by opening the `R.Rproj` file first.

### 1.1 Package Installation
When setting up the environment for the first time, run the following script to install all required R packages at once.
```R
source("02_Code/00_setup/install_packages.R")
```

### 1.2 Running the Full Pipeline
To execute the entire default pipeline—from data preprocessing to model estimation and the output of tables and figures—run the following command:
```R
source("02_Code/run_all.R")
```
Alternatively, you can run it from the terminal (Bash) as follows:
```bash
Rscript 02_Code/run_all.R
```

### 1.3 Configuration (Environment Variables)

The default pipeline runs **without any environment variables**. The following variables are only needed for optional behaviors:

| Variable | Purpose | Default |
| --- | --- | --- |
| `KAKAO_REST_API_KEY` | Kakao geocoding API key — required only when fresh geocoding beyond the existing cache is needed | *(empty)* |
| `NAVER_CLIENT_ID`, `NAVER_CLIENT_SECRET` | Naver geocoding API keys — same condition as above | *(empty)* |
| `LIVING_POP_SAMPLE_MONTHS` | Stream only a sample month (e.g. `201901`) of the Seoul Living Population for a smoke test; writes sample-tagged outputs | *(empty)* |
| `CFG_OUTPUT_TAG` | Custom suffix appended to output paths to isolate a run | *(empty)* |

> **Security note**: never commit real API keys. Set them in your local `.Renviron` file (loaded automatically by R at startup) or via `Sys.setenv()` in an untracked script.

Optional sidecar analyses (GTWR, SPDM experiments, robustness checks) expose additional environment variables (e.g. `GTWR_CONTROL_SET`, `GTWR_PARALLEL_SPECS`, `LIVING_POP_HOURS`). See [02_Code/README.md](02_Code/README.md) for the full reference.

---

## 2. Directory Structure

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
│   ├── 01_Tables/            # Tabular outputs (estimation models, coefficients, and diagnostics)
│   ├── 02_Figures/           # Analytical plots (coefficient plots, trend lines, etc.)
│   ├── 03_Maps/              # Spatial maps (LISA quadrant maps, emerging hotspot maps, etc.)
│   ├── 04_Logs/              # Quality control validation logs and GTWR spec/bandwidth caches
│   └── 05_report/            # Presentation-ready reports and slide-ready summaries
│
├── 04_Docs/                  # Research specifications and guidelines
│   ├── 01_Design/            # Research plan and procedural manual (incl. English research framework figure)
│   └── 02_Codebook/          # Specifications mapping data specs, variable dictionary, and model specs
│
├── README.md                 # This main guide document
└── R.Rproj                   # RStudio project file
```

---

## 3. Data Availability

The original data used in this study are **public open data** from Korean government agencies and are **not included in this repository** because of their large size (50+ GB) and public-data terms of use. The analysis code is fully reproducible once the raw data are placed in `01_Data/`.

### 3.1 Where to Obtain the Raw Data

| Source | Portal / Download |
| --- | --- |
| Seoul Commercial District Analysis Service (sales, stores, floating population, survival rates) | [golmok.seoul.go.kr](https://golmok.seoul.go.kr/) / [data.seoul.go.kr](https://data.seoul.go.kr/) |
| Seoul Living Population (internal movement, metro area) | [data.seoul.go.kr](https://data.seoul.go.kr/) |
| MOIS Resident Registration Population (5-year age groups by dong) | [jumin.mois.go.kr](https://jumin.mois.go.kr/) |
| Seoul business status by worker size, apartments, large retail stores, hospitals, subway stations, bus stops | [data.seoul.go.kr](https://data.seoul.go.kr/) |
| Official land prices, facilities, pedestrian environment | [vworld.kr](https://www.vworld.kr/) / [localdata.go.kr](https://www.localdata.go.kr/) |
| 2020 Seoul administrative dong boundaries | [SGIS](https://sgis.kostat.go.kr/) |

Detailed dataset-level specifications (source names, download URLs, granularity, temporal coverage, access dates, versions, and QC rules) are documented in:
* **Data Specification**: [01_data_spec.md](04_Docs/02_Codebook/01_data_spec.md)
* **Machine-readable dataset catalog**: [01_data_spec_datasets.csv](04_Docs/02_Codebook/01_data_spec_datasets.csv)

### 3.2 Acquisition Record and Integrity

Every raw file is cataloged with its access date (file mtime), embedded version timestamp, size, and MD5 checksum in:
* **Raw data manifest**: [raw_data_manifest.csv](04_Docs/01_Design/raw_data_manifest.csv)

> **Note**: `01_Data/**` and `03_Output/**` are excluded from Git tracking (see the local `.gitignore`). Reproducing the pipeline requires obtaining the raw data from the sources above; the manifest and codebook document exactly which files the analysis expects and how to verify them.

---

## 4. Documentation Reference

For detailed theoretical backgrounds, variable definitions, and model equations of the research, please refer to the following documents:

* **Research Plan Summary**: [research_plan.md](04_Docs/01_Design/research_plan.md)
* **Step-by-step Procedure**: [research_procedure.md](04_Docs/01_Design/research_procedure.md)
* **Project File Tree**: [file_tree.md](04_Docs/01_Design/file_tree.md)
* **Variable and Model Specification Hub**: [00_spec_index.md](04_Docs/02_Codebook/00_spec_index.md)
