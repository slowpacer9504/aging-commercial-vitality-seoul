# 05_Web — GTWR Local-Coefficient Explorer

Interactive web app that visualizes GTWR (Geographically and Temporally
Weighted Regression) **local-coefficient** results on a Seoul
administrative-dong map.

This app is **supplementary** to the existing R research pipeline
(`02_Code/**`). It only consumes existing outputs under
`03_Output/01_Tables/` and reproduces the administrative-dong boundary from
`01_Data/02_Boundary/`. Nothing in `01_Data/`, `02_Code/`, or `04_Docs/` is
modified.

> **Canonical reporting contract** (per
> `04_Docs/01_Design/research_plan.md` §7.4 line 224):
> *"GTWR local coefficients are summarized based on the latest quarter betas,
> while earliest-to-latest deltas are only derived as a supplementary appendix
> diagnostic."*
>
> The app's default state is therefore `view=latest` (`target_yq=2025Q4`) /
> `outcome=vitality_index_base` / `control_set=lean`. Three views are offered:
>
> - **Latest quarter** — the canonical reporting surface.
> - **Specific quarter** — any of the 25 quarters (2019Q4 → 2025Q4), sourced
>   from the panel CSV; coloured with the *same* fixed breaks as `latest` so
>   quarters stay comparable.
> - **Change (Δ)** — earliest→latest delta (`latest_estimate − earliest_estimate`),
>   coloured with its own `delta_breaks`.
>
> The popup time-series chart is labelled **`(Supplementary)`** because it
> surfaces panel deltas — a diagnostic, not the reporting surface.

## Stack

- **R build step** — reuses the project `renv` (`sf`, `dplyr`, `jsonlite`) to
  convert the boundary SHP (EPSG:5186) → EPSG:4326 GeoJSON and emits per
  outcome/control_set JSON files plus a `_build_manifest.json` coverage gate.
- **Backend** — FastAPI + Pydantic v2 + pandas. Loaded at startup; serves
  `/api/{meta,coefficients,panel,summary,health}` and
  `/assets/seoul_adm_dong.geojson` (with `content-type: application/geo+json`).
- **Frontend** — React 19 + Vite 6 + TypeScript (strict, no `as any`) +
  MapLibre GL v5 via `react-map-gl/maplibre` + `d3-scale-chromatic` (RdYlBu_r
  diverging scale anchored at 0) + `recharts` (popup chart) + `zustand`
  (state).

## Quick start (verified on this machine)

```bash
# 1. Build data artifacts (R, run from the project root so renv activates)
Rscript 05_Web/build_data.R
# Expect: "Coverage gate: OK (features=425, match=100%, CRS=EPSG:4326)"

# 2. Backend deps (Python 3.11)
cd 05_Web/backend
uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python \
  "fastapi>=0.115,<1.0" "uvicorn[standard]>=0.34,<1.0" \
  "pydantic>=2.10,<3.0" "pydantic-settings>=2.7,<3.0" "pandas>=2.2,<3.0" \
  "pytest>=8.0" "httpx>=0.27"

# 3. Frontend deps (Node 20+)
cd ../frontend
npm install

# 4. Run both servers (two terminals or `cd ../ && make dev`)
#
# Terminal A — backend on :8000
cd 05_Web/backend && .venv/bin/uvicorn app.main:app --reload --port 8000 --host 127.0.0.1
#
# Terminal B — frontend on :5173 (proxies /api and /assets to :8000)
cd 05_Web/frontend && npm run dev
```

Open <http://localhost:5173>. Click any dong on the map to open the popup with
diagnostics and the Supplementary panel time-series.

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

## Tests

```bash
# Backend (pytest, 10 tests)
cd 05_Web/backend && .venv/bin/pytest

# Frontend (vitest, 56 tests)
cd 05_Web/frontend && npm test -- --run

# Frontend production build (strict tsc + vite build)
cd 05_Web/frontend && npm run build
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | manifest + coverage sanity check |
| GET | `/api/meta` | outcomes, control_sets, `target_yq`, map bounds, colour breaks |
| GET | `/api/coefficients/{control_set}/{outcome}?view={latest\|quarter\|delta}&yq=YYYYQN` | GeoJSON FeatureCollection. `view=latest` (default) returns the canonical 2025Q4 coefficients; `view=quarter&yq=...` returns that quarter's panel estimates; `view=delta` returns earliest→latest deltas |
| GET | `/api/panel/{adm_cd}?outcome=...&control_set=...&q_start=...&q_end=...` | ≤25 `PanelPoint` rows for that dong (Supplementary) |
| GET | `/api/summary/{control_set}` | per-outcome global summary from `gtwr_main_models_*.csv` |
| GET | `/assets/seoul_adm_dong.geojson` | raw EPSG:4326 GeoJSON (425 features) for the map layer |

## Directory layout

```
05_Web/
├── README.md
├── Makefile                  # make {dev, build, test, install, kill, clean}
├── build_data.R             # R: SHP(5186)→GeoJSON(4326) + JSON + manifest
├── .gitignore               # node_modules, .venv, data/, dist/, __pycache__
│
├── data/                    # gitignored build artifacts
│   ├── geojson/seoul_adm_dong.geojson
│   ├── json/{coefficients,summary,lookup}_{lean,extended}.json
│   └── _build_manifest.json # features=425, match=100% gate, colour breaks
│
├── backend/                 # FastAPI (Pydantic v2)
│   ├── pyproject.toml       # PEP-621 deps
│   ├── app/
│   │   ├── main.py          # FastAPI app, CORS, lifespan loader, StaticFiles
│   │   ├── config.py        # pydantic-settings
│   │   ├── errors.py        # typed HTTPException wrapper
│   │   ├── models.py        # Pydantic v2 responses (no `Any`)
│   │   ├── loader.py        # in-memory load + view builder + depend
│   │   └── routers/{meta,coefficients,panel,summary,health}.py
│   └── tests/{conftest,test_endpoints}.py   # 10 tests
│
└── frontend/                # Vite + React 19 + TS strict
    ├── package.json, tsconfig.json, vite.config.ts, vitest.config.ts
    ├── public/data/         # Static mode data artifacts (Cloudflare/GitHub Pages ready)
    └── src/
        ├── main.tsx, App.tsx, index.css
        ├── types/api.ts                     # Pydantic mirror (no `any`)
        ├── api/{client,endpoints,staticFallback}.ts
        ├── state/{store,constants}.ts
        ├── controls/{OutcomeSelector,ControlSetSelector,ViewModeSelector,QuarterSelector,SearchBox,ResearchGuideModal,SupplementaryBanner}.tsx
        ├── map/{MapView,colorScale,Legend,HoverTooltip}.tsx
        │   └── popup/{FeaturePopup,TimeseriesChart,DiagnosticsTable}.tsx
        ├── sidebar/GlobalSummary.tsx
        └── __tests__/{setup,colorScale,store,api,Legend,SearchBox,QuarterSelector,SupplementaryBanner,DiagnosticsTable,TimeseriesChart}.test.tsx
```

## Coverage gate (build_data.R)

`build_data.R` writes `data/_build_manifest.json` and exits **non-zero** if any
of the following fail:

- `geojson_features == 425`
- `csv_adm_cd_match_percent == 100`
- `crs_out == "EPSG:4326"` (MapLibre only accepts WGS84)

The FastAPI lifespan **re-validates these three invariants at startup** — a
stale build (or a deliberately corrupted manifest) refuses to boot, so a
broken geography can never leak into the web app. Any missing `adm_cd` is
listed in the manifest.

## Data sources consumed (read-only)

- **Boundary:** `01_Data/02_Boundary/01_Seoul/서울시 상권분석서비스(영역-행정동)/...shp`
  (425 administrative dongs, EPSG:5186). The 8-digit `ADSTRD_CD` is zero-padded
  to the 10-digit `adm_cd` used by the GTWR CSVs (`"00" + ADSTRD_CD`). The
  coverage gate confirms 425 / 425 adm_cd match exactly.
- **Coefficients:** `03_Output/01_Tables/gtwr_local_coefficients_{lean,extended}.csv`
- **Panel (Supplementary):** `03_Output/01_Tables/gtwr_local_beta_panel_{lean,extended}.csv`
- **Lookup:** `03_Output/01_Tables/adm_region_lookup.csv`
- **Global summary:** `03_Output/01_Tables/gtwr_main_models_{lean,extended}.csv`

These CSVs are produced by the existing pipeline (see
`04_Docs/01_Design/research_procedure.md` §2.17). Run
`02_Code/run_all.R` followed by the GTWR sidecar
`02_Code/03_models/03_run_gtwr_main.R` before running `build_data.R` if the
CSVs are missing.

## License

Same MIT license as the parent project.
