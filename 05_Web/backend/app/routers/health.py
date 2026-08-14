"""GET /api/health — fast startup/integrity check."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from .. import loader as _loader
from ..models import HealthResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def get_health(data: _loader.LoadedData = Depends(_loader.get_data_dep)):
    return HealthResponse(ok=True, manifest=data.manifest)
