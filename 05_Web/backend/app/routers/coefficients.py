"""GET /api/coefficients/{control_set}/{outcome} — latest / quarter / delta GeoJSON."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Path, Query

from .. import loader as _loader
from ..errors import api_error
from ..models import (
    CoefficientFeatureCollection,
    ControlSet,
    OUTCOMES,
)

router = APIRouter()

VIEWS = ("latest", "quarter", "delta")


@router.get(
    "/coefficients/{control_set}/{outcome}",
    response_model=CoefficientFeatureCollection,
)
def get_coefficients(
    control_set: ControlSet = Path(...),
    outcome: str = Path(..., description="One of " + ", ".join(OUTCOMES)),
    view: str = Query("latest", description="One of latest | quarter | delta"),
    yq: str | None = Query(None, description="Required when view=quarter, e.g. 2023Q2"),
    data: _loader.LoadedData = Depends(_loader.get_data_dep),
):
    if outcome not in OUTCOMES:
        raise api_error(
            "invalid_outcome",
            f"Unknown outcome: {outcome!r}",
            hint=f"Allowed: {', '.join(OUTCOMES)}",
            status=422,
        )
    if view not in VIEWS:
        raise api_error(
            "invalid_view",
            f"Unknown view: {view!r}",
            hint=f"Allowed: {', '.join(VIEWS)}",
            status=422,
        )

    paid = data.coefficients.get(control_set)
    if paid is None:
        raise api_error("invalid_control_set", f"Unknown control_set: {control_set!r}", status=422)

    if view == "latest":
        return _loader.build_coefficient_feature_collection(
            paid,
            data.lookup,
            data.geometry_by_adm_cd,
            outcome=outcome,
            control_set=control_set,
            target_yq=data.target_yq[0],
            view="latest",
        )

    if view == "delta":
        return _loader.build_coefficient_feature_collection(
            paid,
            data.lookup,
            data.geometry_by_adm_cd,
            outcome=outcome,
            control_set=control_set,
            target_yq=f"{data.delta_earliest_yq}\u2192{data.delta_latest_yq}",
            view="delta",
            estimates=_loader.delta_estimates(paid, outcome),
        )

    if yq is None:
        raise api_error(
            "missing_yq",
            "view=quarter requires a yq query parameter.",
            hint="Provide yq, e.g. /api/coefficients/lean/vitality_index_base?view=quarter&yq=2023Q2",
            status=422,
        )
    if yq not in data.panel_quarters:
        raise api_error(
            "invalid_yq",
            f"Unknown quarter: {yq!r}",
            hint=f"Allowed: {data.panel_quarters[0]} .. {data.panel_quarters[-1]}",
            status=422,
        )
    panel_df = data.panel.get(control_set)
    return _loader.build_coefficient_feature_collection(
        paid,
        data.lookup,
        data.geometry_by_adm_cd,
        outcome=outcome,
        control_set=control_set,
        target_yq=yq,
        view="quarter",
        estimates=_loader.quarter_estimates(panel_df, outcome, yq),
    )
