"""Strict Pydantic v2 response models for the GTWR explorer API.

All field types are explicit. Numpy/pandas float64 coerces via plain `float`
in the loader before reaching the routers, so no `Any` or `noqa` is needed.
"""
from __future__ import annotations

from typing import Literal, Annotated
from pydantic import BaseModel, Field


ControlSet = Literal["lean", "extended"]

# Outcome identifiers are matched against the canonical set produced by the
# research pipeline. The Literal here doubles as the validation entry.
OUTCOMES: tuple[str, ...] = (
    "vitality_index_base",
    "vitality_sub_economic",
    "vitality_sub_social",
    "vitality_sub_stability",
    "vitality_sub_temporal",
)

# ---------------------------------------------------------------------------
# Domain models
# ---------------------------------------------------------------------------

class CoefficientsRow(BaseModel):
    adm_cd: str
    outcome: str
    focal_var: str
    estimate: float | None
    earliest_estimate: float | None
    latest_estimate: float | None
    earliest_yq: str
    latest_yq: str
    target_yq: str
    estimate_type: str
    control_set: str
    method: str
    n_obs: int | None
    n_eff: float | None
    bw_obs_n: int | None
    local_cn_gtwr_earliest: float | None
    local_cn_gtwr_latest: float | None
    collinearity_warn_latest: bool
    collinearity_warn_flag: bool
    status: str | None = None
    message: str | None = None
    collinearity_diag_message: str | None = None


class LookupRow(BaseModel):
    adm_cd: str
    adm_nm: str
    adstrd_nm: str | None = None
    gu_prefix: str | None = None
    gu_name: str | None = None
    gu_order: str | None = None
    living_area: str | None = None
    living_area_order: str | None = None
    boundary_year: str | None = None


class SummaryRow(BaseModel):
    method: str
    outcome: str
    focal_var: str
    target_yq: str
    estimate_type: str
    earliest_yq: str
    latest_yq: str
    n_locations: int
    n_valid: int
    mean_beta: float | None
    sd_beta: float | None
    p25_beta: float | None
    p50_beta: float | None
    p75_beta: float | None
    share_positive: float | None
    st_bw: float | None
    global_lm_r2: float | None
    global_lm_r2_adj: float | None
    gtw_aic: float | None
    gtw_aicc: float | None
    gtw_enp: float | None
    gtw_edf: float | None
    collinearity_warn_n: int | None
    collinearity_warn_share: float | None
    latest_missing_n: int | None
    latest_coverage_share: float | None
    max_local_cn_gtwr: float | None
    control_set: str
    outcome_group: str | None = None
    outcome_order: int | None = None


class PanelPoint(BaseModel):
    # Time-series (Supplementary) panel estimate per (adm_cd, quarter, outcome)
    adm_cd: str
    year: int
    quarter: int
    yq: str
    quarter_index: int
    time_id: int
    outcome: str
    focal_var: str
    estimate: float | None
    estimate_type: str | None = None
    control_set: str
    n_obs: int | None
    n_eff: float | None
    bw_obs_n: int | None


# ---------------------------------------------------------------------------
# HTTP response envelopes
# ---------------------------------------------------------------------------

class FeatureGeometry(BaseModel):
    type: Literal["Polygon", "MultiPolygon"]
    coordinates: list  # nested floats; opaque to Pydantic for perf

    model_config = {"arbitrary_types_allowed": False}


class CoefficientFeatureProps(BaseModel):
    adm_cd: str
    adm_nm: str | None
    gu_name: str | None
    living_area: str | None
    outcome: str
    control_set: str
    target_yq: str
    view: str
    focal_var: str
    estimate: float | None
    earliest_estimate: float | None
    latest_estimate: float | None
    earliest_yq: str | None
    latest_yq: str | None
    n_obs: int | None
    n_eff: float | None
    bw_obs_n: int | None
    local_cn_gtwr_earliest: float | None
    local_cn_gtwr_latest: float | None
    collinearity_warn_latest: bool
    collinearity_warn_flag: bool


class CoefficientFeature(BaseModel):
    type: Literal["Feature"] = "Feature"
    properties: CoefficientFeatureProps
    geometry: FeatureGeometry | None = None


class CoefficientFeatureCollection(BaseModel):
    type: Literal["FeatureCollection"] = "FeatureCollection"
    features: list[CoefficientFeature]


class MetaResponse(BaseModel):
    outcomes: list[str]
    control_sets: list[str]
    focal_var: list[str]
    target_yq: list[str]
    panel_quarters: list[str]
    estimate_breaks: list[float]
    delta_breaks: list[float]
    delta_earliest_yq: str
    delta_latest_yq: str
    n_locations: int
    coverage_percent: float
    crs: str
    artifacts: dict[str, str]


class HealthResponse(BaseModel):
    ok: bool
    manifest: dict[str, object] | None


class SummaryResponse(BaseModel):
    control_set: str
    summaries: list[SummaryRow]


class PanelResponse(BaseModel):
    adm_cd: str
    adm_nm: str | None
    gu_name: str | None
    control_set: str
    outcome: str
    target_yq: str
    points: list[PanelPoint]


class ApiError(BaseModel):
    detail: str
    code: str
    hint: str | None = None
