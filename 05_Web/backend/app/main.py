"""FastAPI entrypoint for the GTWR local-coefficient explorer."""
from __future__ import annotations

import json
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .config import settings
from .errors import ManifestError
from . import loader as _loader
from .routers import coefficients as coefficients_router
from .routers import health as health_router
from .routers import meta as meta_router
from .routers import panel as panel_router
from .routers import summary as summary_router


GEOJSON_MEDIA = "application/geo+json; charset=utf-8"


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        data = _loader.load_all()
    except ManifestError as exc:
        # Surface a clean startup failure rather than a stack trace.
        raise SystemExit(f"backend startup failed: {exc}") from exc
    app.state.data = data
    app.state.data_dir = settings.data_dir
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        title="GTWR Local-Coefficient Explorer",
        description=(
            "Backend serving Seoul GTWR local-coefficient results. "
            "The canonical reporting surface is the latest quarter (2025Q4); "
            "the panel endpoint exposes earliest-to-latest deltas as a Supplementary appendix diagnostic."
        ),
        version="0.1.0",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,
        allow_methods=["GET"],
        allow_headers=["*"],
    )
    app.include_router(meta_router.router, prefix="/api")
    app.include_router(health_router.router, prefix="/api")
    app.include_router(coefficients_router.router, prefix="/api")
    app.include_router(panel_router.router, prefix="/api")
    app.include_router(summary_router.router, prefix="/api")

    # GeoJSON via a typed FileResponse (better content-type than StaticFiles default).
    geojson_path = settings.data_dir / "geojson" / "seoul_adm_dong.geojson"

    @app.get("/assets/seoul_adm_dong.geojson", include_in_schema=True)
    def get_geojson() -> FileResponse:
        if not geojson_path.exists():
            raise ManifestError(f"GeoJSON missing: {geojson_path}. Run build_data.R.")
        return FileResponse(geojson_path, media_type=GEOJSON_MEDIA)

    # Mount data/json subtree as /assets/json (read-only). Useful for batch validation.
    json_dir = settings.data_dir / "json"
    if json_dir.exists():
        app.mount(
            "/assets/json",
            StaticFiles(directory=json_dir, check_dir=False),
            name="json",
        )

    return app


app = create_app()
