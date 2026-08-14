"""GET /api/meta — enumeration of valid query parameters."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from .. import loader as _loader
from ..models import MetaResponse

router = APIRouter()


@router.get("/meta", response_model=MetaResponse)
def get_meta(data: _loader.LoadedData = Depends(_loader.get_data_dep)):
    manifest = data.manifest
    return MetaResponse(
        outcomes=data.outcomes,
        control_sets=data.control_sets,
        focal_var=data.focal_var,
        target_yq=data.target_yq,
        panel_quarters=data.panel_quarters,
        estimate_breaks=data.estimate_breaks,
        delta_breaks=data.delta_breaks,
        delta_earliest_yq=data.delta_earliest_yq,
        delta_latest_yq=data.delta_latest_yq,
        n_locations=int(manifest["geojson_features"]),
        coverage_percent=float(manifest["csv_adm_cd_match_percent"]),
        crs=str(manifest["crs_out"]),
        artifacts={k: str(v) for k, v in manifest.get("artifacts", {}).items()},
    )
