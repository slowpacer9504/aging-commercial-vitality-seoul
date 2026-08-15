# 05_Web — GTWR Local-Coefficient Explorer

Interactive web application that visualizes GTWR (Geographically and Temporally Weighted Regression) **local-coefficient** results on a Seoul administrative-dong map.

**Live Deployment (GitHub Pages):** <https://slowpacer9504.github.io/aging-commercial-vitality-seoul/>

This app is **supplementary** to the existing R research pipeline (`02_Code/**`). It only consumes existing outputs under `03_Output/01_Tables/` and reproduces the administrative-dong boundary from `01_Data/02_Boundary/`. Nothing in `01_Data/`, `02_Code/`, or `04_Docs/` is modified.

> **Canonical reporting contract** (per `04_Docs/01_Design/research_plan.md` §7.4 line 224):
> *"GTWR local coefficients are summarized based on the latest quarter betas, while earliest-to-latest deltas are only derived as a supplementary appendix diagnostic."*
>
> The app's default state is therefore `view=latest` (`target_yq=2025Q4`) / `outcome=vitality_index_base` / `control_set=lean`. Three views are offered:
>
> - **Latest quarter** — the canonical reporting surface (2025Q4).
> - **Specific quarter** — any of the 25 quarters (2019Q4 → 2025Q4), sourced from the panel CSV; coloured with the *same* fixed breaks as `latest` so quarters stay comparable.
> - **Change (Δ)** — earliest→latest delta (`latest_estimate − earliest_estimate`), coloured with its own `delta_breaks`.
>
> The popup time-series chart is labelled **`(Supplementary)`** because it surfaces panel deltas — a diagnostic, not the reporting surface.

---

## Key Features

1. **Interactive Spatial Map & 3-Tier Hierarchical Boundary System**
   - 425 administrative dongs colored by GTWR local $\hat{\beta}$ estimates (RdYlBu diverging palette centered at 0).
   - Minimalist CartoDB `nolabels` basemap (clean background with no distracting road/place labels).
   - **Modern Academic Indigo & Violet Theme**: Distinct Deep Violet (`#8b5cf6`) and Electric Indigo (`#6366f1`) boundary highlights providing high contrast over both red (hotspot) and blue (coldspot) choropleth polygons.
   - **3-Tier Context-Aware Boundary Hierarchy**:
     - *Living Area selected*: Living Area perimeter highlighted in solid line (`3.0px`).
     - *District (Gu) selected*: Living Area shifts to dashed guide (`1.8px`) while District is emphasized in solid line (`3.2px`).
     - *Dong selected*: District perimeter transitions to dashed outline (`2.2px`) while the target Dong is strongly focused with a solid stroke (`3.0px`).
   - **Persistent Real-Time Hover Tooltip**: Hovering over unselected dongs displays live $\hat{\beta}$ tooltip cards even when a dong is actively pinned with the side panel open.

2. **5 Major Living Areas (`5대 생활권`) & Regional Ribbon Trajectory**
   - **Living Area Filter**: One-touch chip selector for Seoul's 5 Canonical Living Areas (`도심권`, `동북권`, `서북권`, `서남권`, `동남권`) with automatic camera zoom and district dropdown filtering.
   - **Aggregate Spatiotemporal Ribbon Chart (`RegionalTrajectoryChart`)**:
     - Visualizes multi-dong panel trajectories (2019Q4–2025Q4) inside sidebar summary cards for both Living Area and District filters.
     - Features a solid center **Mean line** ($\bar{\beta}_t$), an **Interquartile Range (IQR 50%) inner ribbon**, and a **Full Min–Max outer envelope**.
     - Provides interactive quarterly inspection tooltips and one-click aggregate CSV dataset export.

3. **Spatiotemporal Dynamics Scatter Plot ($\hat{\beta}_{2019Q4}$ vs $\hat{\beta}_{2025Q4}$)**
   - Plots Pre-COVID vs Post-COVID vitality trajectory with 4-quadrant dynamic classification:
     - 🔴 **Persistent Hotspot** (Q1: Positive $\to$ Positive)
     - 🔴 **Turnaround to Positive** (Q2: Negative $\to$ Positive)
     - 🔵 **Persistent Coldspot** (Q3: Negative $\to$ Negative)
     - 🔵 **Deteriorated to Negative** (Q4: Positive $\to$ Negative)
   - Interactive Brushing & Linking: filtering by Gu highlights that district's dongs and dims others to 20% opacity.
   - Available as both a compact sidebar widget and a full-size modal accessible from the top header button (`📈 Dynamics Scatter`).

4. **Guided Story Tour (`💡 Key Findings Tour`)**
   - 5 curated empirical findings navigating through specific spatial and temporal highlights (e.g., Northeast Seoul agglomeration, Gangnam GBD vs residential contrasts, Eunpyeong stability).
   - District-focused highlighting without intrusive dong popups during active narrative playback.

5. **Mobile-First Responsive Experience**
   - **2-Button Header Architecture**: Streamlined `🎛️ Controls` and `⚙️ Settings` navigation on viewports $\le 768\text{px}$.
   - **Native-Feeling Bottom Sheet Modal (`MobileMenuModal.tsx`)**: Unified tools and settings modal with gesture backdrop dismissal.
   - **Full-Bleed Viewport & Floating Address Bar Adaptation**: Renders seamlessly behind mobile Safari's translucent URL bar with safe-area bottom offset.

6. **Publication-Ready Export & Theme Support**
   - **Export Map as PNG**: Renders the active MapLibre WebGL canvas with automatically watermarked model specification badges and attribution.
   - **Specification-Based Slug Filenames**: Dynamic filenames reflecting active parameters (e.g., `seoul_gtwr_composite_lean_2025Q4.png`, `trajectory_gu_강남구_vitality_index_base_lean.csv`).
   - **Theme Support**: One-click toggle between crisp Light theme and high-contrast Dark theme.

---

## Architecture & Technology Stack

- **Data Pipeline (R)**: Reuses project `renv` (`sf`, `dplyr`, `jsonlite`). Converts boundary SHP (EPSG:5186) $\to$ EPSG:4326 GeoJSON, performs spatial union for 25 autonomous district boundaries (`seoul_gu.geojson`), generates per-outcome/control-set JSON files, and enforces a `_build_manifest.json` coverage gate.
- **Static Deployment Mode (GitHub Pages / Standalone)**: Artifacts in `frontend/public/data/` allow full client-side execution with zero backend dependency (initial transfer size: ~4.2 MB gzip).
- **Fullstack Mode (FastAPI)**: FastAPI + Pydantic v2 + pandas for dynamic backend API serving.
- **Frontend**: React 19 + Vite 6 + TypeScript (strict mode) + MapLibre GL v5 via `react-map-gl/maplibre` + Recharts + Zustand.

---

## Quick Start

### 1. Data Build (R)
Run from the project root:
```bash
Rscript 05_Web/build_data.R
# Expect: "Coverage gate: OK (features=425, match=100%, CRS=EPSG:4326)"
```

### 2. Frontend Development Server (Static Fallback Mode)
```bash
cd 05_Web/frontend
npm install
npm run dev
# Open http://localhost:5173
```

### 3. Fullstack Development Mode (Backend + Frontend)
```bash
# Terminal A — Backend on :8000
cd 05_Web/backend
uv venv --python 3.11 .venv
uv pip install -e .
.venv/bin/uvicorn app.main:app --reload --port 8000 --host 127.0.0.1

# Terminal B — Frontend on :5173
cd 05_Web/frontend
npm run dev
```

---

## Updating Web Data After GTWR Model Rerun

Whenever you rerun the GTWR model in R (`02_Code/03_models/03_run_gtwr_main.R`), refresh the static web artifacts and deploy the updated results with:

```bash
# 1. Rebuild web artifacts from updated 03_Output/ CSVs (run from project root)
Rscript 05_Web/build_data.R

# 2. Commit and push to deploy to GitHub Pages
git add 05_Web/frontend/public/data
git commit -m "chore: update web data from latest GTWR model run"
git push origin main
```

GitHub Actions automatically builds and deploys the updated frontend to GitHub Pages within ~1 minute.

---

## Tests

```bash
# Backend (pytest, 10 tests)
cd 05_Web/backend && .venv/bin/pytest

# Frontend (vitest, 18 test suites / 63 tests)
cd 05_Web/frontend && npm test -- --run

# Frontend production build verification (tsc + vite)
cd 05_Web/frontend && npm run build
```

---

## Directory Layout

```
05_Web/
├── README.md
├── Makefile                  # make {dev, build, test, install, clean}
├── build_data.R             # R: SHP(5186)→GeoJSON(4326) + Gu Dissolve + JSON + manifest
├── .gitignore               # node_modules, .venv, data/, dist/
│
├── data/                    # Build output artifacts
│   ├── geojson/             # seoul_adm_dong.geojson, seoul_gu.geojson, seoul_outer_mask.geojson
│   ├── json/                # coefficients, summary, lookup, quarter_estimates, panel
│   └── _build_manifest.json # features=425, match=100% gate, colour breaks
│
├── backend/                 # FastAPI (Pydantic v2)
│   ├── pyproject.toml       # PEP-621 dependencies
│   ├── app/
│   │   ├── main.py          # FastAPI app, CORS, lifespan loader, StaticFiles
│   │   ├── config.py, errors.py, models.py, loader.py
│   │   └── routers/{meta,coefficients,panel,summary,health}.py
│   └── tests/               # pytest suite
│
└── frontend/                # Vite + React 19 + TS strict
    ├── package.json, tsconfig.json, vite.config.ts, vitest.config.ts
    ├── public/data/         # Static mode data artifacts (GitHub Pages ready)
    └── src/
        ├── types/api.ts                     # Strict Pydantic mirror & Aggregate types
        ├── api/{client,endpoints,staticFallback}.ts
        ├── state/{store,constants}.ts       # Living area mappings, colors & Zustand store
        ├── controls/                        # Outcome, ControlSet, ViewMode, Quarter, LivingArea, GuFilter, RegionalTrajectoryChart, Export, Search, MobileMenuModal
        ├── map/                             # MapView, colorScale, Legend, HoverTooltip, MapSpecOverlay
        │   └── popup/                       # FeaturePopup, TimeseriesChart, DiagnosticsTable
        ├── sidebar/                         # GlobalSummary, LinkedScatterPlot, ScatterPlotModal
        ├── tour/                            # StoryTourBanner, storyTourData
        ├── utils/exportUtils.ts             # PNG watermark composite & slug filenames
        └── __tests__/                       # 18 Vitest suites (63 tests)
```

---

## Coverage Gate (`build_data.R`)

`build_data.R` writes `data/_build_manifest.json` and exits **non-zero** if any of the following fail:

- `geojson_features == 425`
- `csv_adm_cd_match_percent == 100`
- `crs_out == "EPSG:4326"` (MapLibre only accepts WGS84)

The FastAPI lifespan and frontend static loaders validate these invariants to ensure zero data leakage or geographic mismatch.

---

## License

Same MIT license as the parent project.

