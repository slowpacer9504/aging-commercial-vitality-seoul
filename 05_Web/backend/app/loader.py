"""In-memory typed load of the R-built artifacts at FastAPI startup."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pandas as pd

from .config import settings
from .errors import ManifestError
from .models import (
    CoefficientFeature,
    CoefficientFeatureCollection,
    CoefficientFeatureProps,
    CoefficientsRow,
    LookupRow,
    PanelPoint,
    SummaryRow,
)


def _read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def _to_float(x: Any) -> float | None:
    if x is None:
        return None
    try:
        v = float(x)
    except (TypeError, ValueError):
        return None
    if pd.isna(v):
        return None
    return v


def _to_int(x: Any) -> int | None:
    if x is None:
        return None
    try:
        v = int(x)
    except (TypeError, ValueError):
        return None
    if pd.isna(v):
        return None
    return v


def _to_bool(x: Any) -> bool:
    if isinstance(x, bool):
        return x
    if isinstance(x, str):
        return x.strip().lower() in {"true", "1", "yes"}
    return bool(x)


@dataclass
class LoadedData:
    """Application-wide singleton built once at startup."""

    manifest: dict[str, Any]
    raw_geojson: dict[str, Any]                 # raw GeoJSON FeatureCollection (geometry+adm_cd only)
    geometry_by_adm_cd: dict[str, dict[str, Any]]

    # nested: control_set -> outcome -> adm_cd -> CoefficientsRow
    coefficients: dict[str, dict[str, dict[str, CoefficientsRow]]]
    control_sets: list[str]
    outcomes: list[str]
    focal_var: list[str]
    target_yq: list[str]
    panel_quarters: list[str]
    estimate_breaks: list[float]
    delta_breaks: list[float]
    delta_earliest_yq: str
    delta_latest_yq: str

    lookup: dict[str, LookupRow]

    summary: dict[str, list[SummaryRow]]       # control_set -> [SummaryRow]

    # Panel is loaded lazily as pandas DataFrame for filtered queries.
    panel: dict[str, pd.DataFrame]             # control_set -> DataFrame


def load_coefficients_for_control(control_set: str) -> dict[str, dict[str, CoefficientsRow]]:
    raw = _read_json(settings.data_dir / "json" / f"coefficients_{control_set}.json")
    out: dict[str, dict[str, CoefficientsRow]] = {}
    for outcome, by_adm in raw.items():
        rows: dict[str, CoefficientsRow] = {}
        for adm_cd, row in by_adm.items():
            rows[adm_cd] = CoefficientsRow(
                adm_cd=str(row.get("adm_cd", adm_cd)),
                outcome=str(row["outcome"]),
                focal_var=str(row["focal_var"]),
                estimate=_to_float(row.get("estimate")),
                earliest_estimate=_to_float(row.get("earliest_estimate")),
                latest_estimate=_to_float(row.get("latest_estimate")),
                earliest_yq=str(row["earliest_yq"]),
                latest_yq=str(row["latest_yq"]),
                target_yq=str(row["target_yq"]),
                estimate_type=str(row["estimate_type"]),
                control_set=str(row["control_set"]),
                method=str(row["method"]),
                n_obs=_to_int(row.get("n_obs")),
                n_eff=_to_float(row.get("n_eff")),
                bw_obs_n=_to_int(row.get("bw_obs_n")),
                local_cn_gtwr_earliest=_to_float(row.get("local_cn_gtwr_earliest")),
                local_cn_gtwr_latest=_to_float(row.get("local_cn_gtwr_latest")),
                collinearity_warn_latest=_to_bool(row.get("collinearity_warn_latest")),
                collinearity_warn_flag=_to_bool(row.get("collinearity_warn_flag")),
                status=row.get("status"),
                message=row.get("message"),
                collinearity_diag_message=row.get("collinearity_diag_message"),
            )
        out[outcome] = rows
    return out


def load_lookup() -> dict[str, LookupRow]:
    raw = _read_json(settings.data_dir / "json" / "lookup.json")
    out: dict[str, LookupRow] = {}
    for adm_cd, row in raw.items():
        out[adm_cd] = LookupRow(
            adm_cd=str(row.get("adm_cd", adm_cd)),
            adm_nm=str(row.get("adm_nm", "")),
            adstrd_nm=row.get("adstrd_nm"),
            gu_prefix=row.get("gu_prefix"),
            gu_name=row.get("gu_name"),
            gu_order=row.get("gu_order"),
            living_area=row.get("living_area"),
            living_area_order=row.get("living_area_order"),
            boundary_year=row.get("boundary_year"),
        )
    return out


def load_summary(control_set: str) -> list[SummaryRow]:
    raw = _read_json(settings.data_dir / "json" / f"summary_{control_set}.json")
    rows: list[SummaryRow] = []
    for r in raw:
        rows.append(
            SummaryRow(
                method=str(r.get("method", "GWmodel::gtwr")),
                outcome=str(r["outcome"]),
                focal_var=str(r.get("focal_var", "lag4_age60_resident_share")),
                target_yq=str(r.get("target_yq", "")),
                estimate_type=str(r.get("estimate_type", "latest")),
                earliest_yq=str(r.get("earliest_yq", "")),
                latest_yq=str(r.get("latest_yq", "")),
                n_locations=_to_int(r.get("n_locations")) or 0,
                n_valid=_to_int(r.get("n_valid")) or 0,
                mean_beta=_to_float(r.get("mean_beta")),
                sd_beta=_to_float(r.get("sd_beta")),
                p25_beta=_to_float(r.get("p25_beta")),
                p50_beta=_to_float(r.get("p50_beta")),
                p75_beta=_to_float(r.get("p75_beta")),
                share_positive=_to_float(r.get("share_positive")),
                st_bw=_to_float(r.get("st_bw")),
                global_lm_r2=_to_float(r.get("global_lm_r2")),
                global_lm_r2_adj=_to_float(r.get("global_lm_r2_adj")),
                gtw_aic=_to_float(r.get("gtw_aic")),
                gtw_aicc=_to_float(r.get("gtw_aicc")),
                gtw_enp=_to_float(r.get("gtw_enp")),
                gtw_edf=_to_float(r.get("gtw_edf")),
                collinearity_warn_n=_to_int(r.get("collinearity_warn_n")),
                collinearity_warn_share=_to_float(r.get("collinearity_warn_share")),
                latest_missing_n=_to_int(r.get("latest_missing_n")),
                latest_coverage_share=_to_float(r.get("latest_coverage_share")),
                max_local_cn_gtwr=_to_float(r.get("max_local_cn_gtwr")),
                control_set=str(r.get("control_set", control_set)),
                outcome_group=r.get("outcome_group"),
                outcome_order=_to_int(r.get("outcome_order")),
            )
        )
    return rows


PANEL_DTYPES = {
    "adm_cd": "string",
    "year": "int16",
    "quarter": "int8",
    "yq": "string",
    "quarter_index": "int16",
    "time_id": "int16",
    "outcome": "string",
    "focal_var": "string",
    "estimate_type": "string",
    "control_set": "string",
    "window_scope": "string",
    "status": "string",
    "n_obs": "Int64",
    "n_eff": "float64",
    "bw_obs_n": "Int64",
    "target_yq": "string",
    "fit_scope": "string",
    "recent_period_n": "Int64",
    "location_frac": "float64",
    "location_n": "Int64",
}


def load_panel(control_set: str) -> pd.DataFrame:
    """Load panel CSV once; filter columns to those the API exposes."""
    path = settings.out_tables / f"gtwr_local_beta_panel_{control_set}.csv"
    if not path.exists():
        raise ManifestError(f"Panel CSV missing: {path}")
    df = pd.read_csv(path, dtype=PANEL_DTYPES, low_memory=False)
    keep = [
        "adm_cd", "year", "quarter", "yq", "quarter_index", "time_id",
        "outcome", "focal_var", "estimate", "estimate_type", "control_set",
        "n_obs", "n_eff", "bw_obs_n",
    ]
    return df[keep]


def load_all() -> LoadedData:
    """Read everything and validate the manifest coverage gate at startup."""
    manifest_path = settings.data_dir / "_build_manifest.json"
    if not manifest_path.exists():
        raise ManifestError(
            f"Build manifest missing at {manifest_path}. Run `Rscript 05_Web/build_data.R` first."
        )
    manifest: dict[str, Any] = _read_json(manifest_path)

    # Validate the coverage gate (re-check at backend boot, not just R-side).
    if int(manifest.get("geojson_features", 0)) != 425:
        raise ManifestError("manifest.geojson_features != 425")
    if float(manifest.get("csv_adm_cd_match_percent", 0)) != 100.0:
        raise ManifestError("manifest.csv_adm_cd_match_percent < 100")
    if str(manifest.get("crs_out", "")) != "EPSG:4326":
        raise ManifestError("manifest.crs_out != EPSG:4326")

    raw_geojson = _read_json(settings.data_dir / "geojson" / "seoul_adm_dong.geojson")
    geometry_by_adm_cd: dict[str, dict[str, Any]] = {}
    for f in raw_geojson.get("features", []):
        props = f.get("properties", {})
        adm_cd = props.get("adm_cd")
        if adm_cd is None:
            continue
        geometry_by_adm_cd[adm_cd] = f["geometry"]

    control_sets = list(manifest["control_sets"])
    coefficients: dict[str, dict[str, dict[str, CoefficientsRow]]] = {}
    summary: dict[str, list[SummaryRow]] = {}
    panel: dict[str, pd.DataFrame] = {}
    for cs in control_sets:
        coefficients[cs] = load_coefficients_for_control(cs)
        summary[cs] = load_summary(cs)
        panel[cs] = load_panel(cs)

    return LoadedData(
        manifest=manifest,
        raw_geojson=raw_geojson,
        geometry_by_adm_cd=geometry_by_adm_cd,
        coefficients=coefficients,
        control_sets=control_sets,
        outcomes=list(manifest["outcomes"]) if isinstance(manifest["outcomes"], list) else [manifest["outcomes"]],
        focal_var=list(manifest["focal_var"]) if isinstance(manifest["focal_var"], list) else [manifest["focal_var"]],
        target_yq=list(manifest["target_yq"]) if isinstance(manifest["target_yq"], list) else [manifest["target_yq"]],
        panel_quarters=list(manifest["panel_quarters"]) if isinstance(manifest["panel_quarters"], list) else [manifest["panel_quarters"]],
        estimate_breaks=[float(x) for x in manifest["estimate_breaks"]],
        delta_breaks=[float(x) for x in manifest["delta_breaks"]],
        delta_earliest_yq=str(manifest["delta_earliest_yq"]),
        delta_latest_yq=str(manifest["delta_latest_yq"]),
        lookup=load_lookup(),
        summary=summary,
        panel=panel,
    )


# ---------------------------------------------------------------------------
# View builders
# ---------------------------------------------------------------------------

def build_coefficient_feature_collection(
    coeffs: dict[str, dict[str, CoefficientsRow]],
    lookup: dict[str, LookupRow],
    geometry_by_adm_cd: dict[str, dict[str, Any]],
    outcome: str,
    control_set: str,
    target_yq: str,
    view: str = "latest",
    estimates: dict[str, float | None] | None = None,
) -> CoefficientFeatureCollection:
    rows_by_adm = coeffs.get(outcome, {})
    features: list[CoefficientFeature] = []
    for adm_cd, row in rows_by_adm.items():
        lk = lookup.get(adm_cd)
        estimate = row.estimate if estimates is None else estimates.get(adm_cd)
        props = CoefficientFeatureProps(
            adm_cd=adm_cd,
            adm_nm=lk.adm_nm if lk else None,
            gu_name=lk.gu_name if lk else None,
            living_area=lk.living_area if lk else None,
            outcome=outcome,
            control_set=control_set,
            target_yq=target_yq,
            view=view,
            focal_var=row.focal_var,
            estimate=estimate,
            earliest_estimate=row.earliest_estimate,
            latest_estimate=row.latest_estimate,
            earliest_yq=row.earliest_yq,
            latest_yq=row.latest_yq,
            n_obs=row.n_obs,
            n_eff=row.n_eff,
            bw_obs_n=row.bw_obs_n,
            local_cn_gtwr_earliest=row.local_cn_gtwr_earliest,
            local_cn_gtwr_latest=row.local_cn_gtwr_latest,
            collinearity_warn_latest=row.collinearity_warn_latest,
            collinearity_warn_flag=row.collinearity_warn_flag,
        )
        geom = geometry_by_adm_cd.get(adm_cd)
        from .models import FeatureGeometry
        geometry = FeatureGeometry(type=geom["type"], coordinates=geom["coordinates"]) if geom else None
        features.append(CoefficientFeature(properties=props, geometry=geometry))
    return CoefficientFeatureCollection(features=features)


def quarter_estimates(
    panel_df: pd.DataFrame,
    outcome: str,
    yq: str,
) -> dict[str, float | None]:
    """Per-dong estimate for a single quarter, sourced from the panel CSV."""
    sub = panel_df[(panel_df["outcome"] == outcome) & (panel_df["yq"] == yq)]
    out: dict[str, float | None] = {}
    for _, r in sub.iterrows():
        out[str(r["adm_cd"])] = _to_float(r.get("estimate"))
    return out


def delta_estimates(
    coeffs: dict[str, dict[str, CoefficientsRow]],
    outcome: str,
) -> dict[str, float | None]:
    """Earliest-to-latest delta (latest - earliest) per dong."""
    out: dict[str, float | None] = {}
    for adm_cd, row in coeffs.get(outcome, {}).items():
        if row.latest_estimate is not None and row.earliest_estimate is not None:
            out[adm_cd] = row.latest_estimate - row.earliest_estimate
        else:
            out[adm_cd] = None
    return out


def panel_points_for(
    panel_df: pd.DataFrame,
    adm_cd: str,
    outcome: str,
    control_set: str,
    q_start: str | None = None,
    q_end: str | None = None,
) -> list[PanelPoint]:
    mask = (panel_df["adm_cd"] == adm_cd) & (panel_df["outcome"] == outcome)
    if q_start:
        mask &= panel_df["yq"] >= q_start
    if q_end:
        mask &= panel_df["yq"] <= q_end
    sub = panel_df[mask].sort_values("time_id")
    points: list[PanelPoint] = []
    for _, r in sub.iterrows():
        points.append(
            PanelPoint(
                adm_cd=str(r["adm_cd"]),
                year=int(r["year"]),
                quarter=int(r["quarter"]),
                yq=str(r["yq"]),
                quarter_index=int(r["quarter_index"]),
                time_id=int(r["time_id"]),
                outcome=str(r["outcome"]),
                focal_var=str(r["focal_var"]),
                estimate=_to_float(r.get("estimate")),
                estimate_type=(str(r["estimate_type"]) if pd.notna(r.get("estimate_type")) else None),
                control_set=str(r["control_set"]),
                n_obs=_to_int(r.get("n_obs")),
                n_eff=_to_float(r.get("n_eff")),
                bw_obs_n=_to_int(r.get("bw_obs_n")),
            )
        )
    return points


# ---------------------------------------------------------------------------
# FastAPI dependency
# ---------------------------------------------------------------------------

from fastapi import Request


def get_data_dep(request: Request) -> "LoadedData":
    """Return the LoadedData singleton populated at startup by the lifespan."""
    data = getattr(request.app.state, "data", None)
    if data is None:
        raise ManifestError("Loader ran before lifespan initialised app.state.data")
    return data
