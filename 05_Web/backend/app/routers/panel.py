"""GET /api/panel/{adm_cd} — Supplementary time-series panel rows."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Path, Query

from .. import loader as _loader
from ..errors import api_error
from ..models import ControlSet, OUTCOMES, PanelResponse

router = APIRouter()


@router.get("/panel/{adm_cd}", response_model=PanelResponse)
def get_panel(
    adm_cd: str = Path(...),
    outcome: str = Query(..., description="One of " + ", ".join(OUTCOMES)),
    control_set: ControlSet = Query("lean"),
    q_start: str | None = Query(None, description="Inclusive lower-quarter (e.g. 2019Q4)"),
    q_end: str | None = Query(None, description="Inclusive upper-quarter (e.g. 2025Q4)"),
    data: _loader.LoadedData = Depends(_loader.get_data_dep),
):
    if outcome not in OUTCOMES:
        raise api_error(
            "invalid_outcome",
            f"Unknown outcome: {outcome!r}",
            hint=f"Allowed: {', '.join(OUTCOMES)}",
            status=422,
        )
    panel_df = data.panel.get(control_set)
    if panel_df is None:
        raise api_error("invalid_control_set", f"Unknown control_set: {control_set!r}", status=422)

    # Validate adm_cd is in the canonical 425-dong set.
    if adm_cd not in data.geometry_by_adm_cd:
        raise api_error(
            "unknown_adm_cd",
            f"adm_cd {adm_cd!r} has no Seoul administrative-dong geometry.",
            status=404,
        )

    points = _loader.panel_points_for(
        panel_df,
        adm_cd=adm_cd,
        outcome=outcome,
        control_set=control_set,
        q_start=q_start,
        q_end=q_end,
    )
    if not points:
        raise api_error(
            "no_panel_data",
            f"No panel rows for adm_cd={adm_cd!r} outcome={outcome!r} control_set={control_set!r}.",
            status=404,
        )

    lk = data.lookup.get(adm_cd)
    return PanelResponse(
        adm_cd=adm_cd,
        adm_nm=lk.adm_nm if lk else None,
        gu_name=lk.gu_name if lk else None,
        control_set=control_set,
        outcome=outcome,
        target_yq=data.target_yq[0] if data.target_yq else "",
        points=points,
    )
