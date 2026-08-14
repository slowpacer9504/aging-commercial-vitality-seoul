"""GET /api/summary/{control_set} — global per-outcome summary."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Path

from .. import loader as _loader
from ..errors import api_error
from ..models import ControlSet, SummaryResponse

router = APIRouter()


@router.get("/summary/{control_set}", response_model=SummaryResponse)
def get_summary(
    control_set: ControlSet = Path(...),
    data: _loader.LoadedData = Depends(_loader.get_data_dep),
):
    summaries = data.summary.get(control_set)
    if summaries is None:
        raise api_error("invalid_control_set", f"Unknown control_set: {control_set!r}", status=422)
    return SummaryResponse(control_set=control_set, summaries=summaries)
