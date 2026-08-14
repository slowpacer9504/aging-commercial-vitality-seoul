"""Typed FastAPI error helpers."""
from __future__ import annotations

from fastapi import HTTPException
from .models import ApiError


class ManifestError(Exception):
    """Raised when the build manifest is missing or invalid."""


def api_error(code: str, detail: str, hint: str | None = None, status: int = 404) -> HTTPException:
    return HTTPException(
        status_code=status,
        detail=ApiError(code=code, detail=detail, hint=hint).model_dump(),
    )
