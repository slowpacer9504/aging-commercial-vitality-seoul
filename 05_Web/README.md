# 05_Web — Spatiotemporal GTWR Explorer for Neighborhood Commercial Vitality

This module provides an interactive visual analytics platform and static web explorer designed to investigate localized Geographically and Temporally Weighted Regression (GTWR) estimates across Seoul's 425 administrative dongs over 25 consecutive quarters (2019Q4–2025Q4).

* **Live Deployment (GitHub Pages):** <https://slowpacer9504.github.io/aging-commercial-vitality-seoul/>
* **Parent Project:** Master's Thesis — *The Impact of Population Aging on Neighborhood Commercial Vitality: Spatiotemporal Analysis Using Urban Big Data from Seoul*

---

## 1. Research Context & Reporting Contract

Per the canonical research plan (`04_Docs/01_Design/research_plan.md` §7.4), the global empirical findings are anchored in Spatial Panel Durbin Models (SPDM), while GTWR serves as a resident-only local sidecar to surface fine-grained spatial and temporal heterogeneity.

The web explorer strictly implements this reporting hierarchy:
* **Canonical Baseline (`view=latest`, 2025Q4):** Primary cross-sectional snapshot summarizing post-pandemic steady-state local aging coefficients ($\hat{\beta}_{2025Q4}$) across five commercial vitality outcomes and two control specifications (Lean vs Extended).
* **Panel Explorer (`view=quarter`):** Evaluates quarter-by-quarter parameter stability across 25 quarters under consistent, fixed break calibrations.
* **Long-Term Dynamics (`view=delta`):** Surfaces structural temporal shifts ($\Delta = \hat{\beta}_{2025Q4} - \hat{\beta}_{2019Q4}$) as a supplementary diagnostic.

---

## 2. Key Analytical Capabilities

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          SPATIAL EXPLORATION STACK                          │
├──────────────────────────────┬──────────────────────────────────────────────┤
│ 1. Multi-Scale Filtering     │ 5 Living Areas → 25 Districts → 425 Dongs    │
│ 2. Context-Aware Boundaries  │ 3-Tier Dynamic Highlights (Solid / Dashed)   │
│ 3. Aggregate Ribbon Dynamics │ Mean Trend Line + IQR (50%) + Min-Max Bands │
│ 4. Spatiotemporal Scatter    │ 4-Quadrant Trajectory (2019Q4 vs 2025Q4)     │
│ 5. Guided Story Tour         │ 5 Curated Empirical Research Highlights      │
│ 6. Scientific Data Export    │ Watermarked Map PNGs & Filtered Panel CSVs   │
└──────────────────────────────┴──────────────────────────────────────────────┘
```

### 2.1 Multi-Scale Spatial Partitioning & 3-Tier Boundary Hierarchy
* **Metropolitan Living Areas (`5대 생활권`):** High-level spatial filtering for Seoul's 5 major planning zones (`도심권`, `동북권`, `서북권`, `서남권`, `동남권`) with automated camera framing (`flyTo`) and district dropdown pruning.
* **3-Tier Context-Aware Boundary System:** High-contrast **Deep Violet (`#8b5cf6`)** and **Electric Indigo (`#6366f1`)** perimeter layers provide unambiguous visual separation over both positive (red) and negative (blue) choropleth polygons:
  * *Living Area Focus:* Solid outer regional perimeter (`3.0px`).
  * *District Focus:* Regional boundary transitions to dashed guide (`1.8px`) while the focal district is highlighted with a solid stroke (`3.2px`).
  * *Dong Focus:* District boundary transitions to dashed outline (`2.2px`) while the selected dong receives primary solid emphasis (`3.0px`).

### 2.2 Aggregate Regional Ribbon Trajectories (`RegionalTrajectoryChart`)
* **Multi-Dong Distributional Envelopes:** Renders the 25-quarter temporal trajectory of aggregated sub-dongs within any selected Living Area or District.
* **Dual-Layered Ribbon Bands:** Displays the central **Mean line ($\bar{\beta}_t$)**, an **Interquartile Range (IQR 50%) inner ribbon**, and a **Full Min–Max outer envelope** to visualize localized dispersion and structural shocks (e.g., COVID-19 pandemic contraction and recovery).

### 2.3 Spatiotemporal Trajectory Scatter Plot
* **Empirical Quadrant Dynamics:** Classifies 425 administrative dongs based on baseline (2019Q4) versus terminal (2025Q4) coefficient transitions:
  * 🔴 **Persistent Hotspot** (Positive $\to$ Positive)
  * 🔴 **Turnaround to Positive** (Negative $\to$ Positive)
  * 🔵 **Persistent Coldspot** (Negative $\to$ Negative)
  * 🔵 **Deteriorated to Negative** (Positive $\to$ Negative)
* **Bidirectional Brushing & Linking:** Selections in the scatter plot instantly isolate corresponding dongs on the map and vice versa.

### 2.4 Mobile-Optimized Responsive Architecture
* **Unified 2-Button Navigation:** Streamlined top navigation (`Controls` & `Settings`) and native bottom sheet modals (`MobileMenuModal.tsx`) for touch viewports ($\le 768\text{px}$).
* **Full-Bleed Map Viewport:** Accommodates mobile Safari floating address bars via `viewport-fit=cover` and dynamic safe-area offsets.

---

## 3. Data Pipeline & Spatial Integrity Gates

```
01_Data/02_Boundary/       03_Output/01_Tables/gtwr/
 (SHP, EPSG:5186)             (Panel CSVs)
        │                           │
        └─────────────┬─────────────┘
                      ▼
             05_Web/build_data.R
                      │
     ┌────────────────┴────────────────┐
     ▼                                 ▼
 GeoJSON Vector Layers           Optimized Static JSON
 (seoul_adm_dong.geojson)        (coefficients_*.json,
 (seoul_gu.geojson)              panel_*.json, lookup.json)
```

The data ingestion script (`build_data.R`) transforms upstream R model outputs into lightweight static web artifacts (`frontend/public/data/`) and enforces three strict coverage invariants in `_build_manifest.json`:

1. **Polygon Invariant:** Exactly 425 administrative dong features (`geojson_features == 425`).
2. **Key Match Invariant:** 100.0% join consistency between model tables and spatial geometries (`csv_adm_cd_match_percent == 100`).
3. **Coordinate System Invariant:** Valid WGS84 projection (`crs_out == "EPSG:4326"`).

---

## 4. Quick Start & Execution

### 4.1 Data Build (R)
Run from the repository root:
```bash
Rscript 05_Web/build_data.R
```

### 4.2 Frontend Development Server (Static Fallback Mode)
```bash
cd 05_Web/frontend
npm install
npm run dev
# Open http://localhost:5173
```

### 4.3 Fullstack Development Mode (FastAPI Backend + Frontend)
```bash
# Terminal A — Backend (FastAPI on :8000)
cd 05_Web/backend
uv venv --python 3.11 .venv
uv pip install -e .
.venv/bin/uvicorn app.main:app --reload --port 8000 --host 127.0.0.1

# Terminal B — Frontend (Vite on :5173)
cd 05_Web/frontend
npm run dev
```

---

## 5. Verification & Test Suite

```bash
# Backend test suite (pytest, 10 tests)
cd 05_Web/backend && .venv/bin/pytest

# Frontend test suite (vitest, 18 test suites / 63 tests)
cd 05_Web/frontend && npm test -- --run

# Production bundle compilation (TypeScript strict + Vite)
cd 05_Web/frontend && npm run build
```

---

## 6. Directory Layout

```text
05_Web/
├── README.md                # Module specification and architecture guide
├── Makefile                 # Automation targets: dev, build, test, clean
├── build_data.R             # R pipeline: SHP/CSV transformation & coverage gate
├── .gitignore               # Ignored build outputs and dependencies
│
├── backend/                 # Optional FastAPI backend service (Pydantic v2)
│   ├── pyproject.toml       # Python package configuration
│   ├── app/                 # Routers: meta, coefficients, panel, summary, health
│   └── tests/               # Backend pytest suite
│
└── frontend/                # React 19 + TypeScript + Vite + MapLibre GL
    ├── package.json         # Frontend dependencies and scripts
    ├── public/data/         # Static GeoJSON and JSON artifacts (GitHub Pages ready)
    └── src/
        ├── types/api.ts     # Pydantic-mirrored strict TypeScript interfaces
        ├── api/             # API client, static fallback loaders, and endpoints
        ├── state/           # Zustand application store, constants, and living areas
        ├── controls/        # Outcome, Model, LivingArea, GuFilter, RibbonChart, MobileMenu
        ├── map/             # MapView (MapLibre), ColorScale, Legend, Overlay, Popup
        ├── sidebar/         # GlobalSummary, LinkedScatterPlot, ScatterPlotModal
        ├── tour/            # StoryTourBanner, empirical narrative scenes
        ├── utils/           # Canvas composite export & dynamic slug generators
        └── __tests__/       # Vitest test suite (63 unit and integration tests)
```

---

## 7. License

This module is licensed under the [MIT License](../LICENSE).
