"""Application settings loaded from environment or sensible defaults."""
from __future__ import annotations

from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration for the GTWR explorer backend."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # The web app data directory (absolute or relative to backend/).
    data_dir: Path = Path(__file__).resolve().parent.parent.parent / "data"
    project_root: Path = Path(__file__).resolve().parent.parent.parent.parent

    # Final outputs from the R pipeline.
    out_tables: Path = project_root / "03_Output" / "01_Tables"

    # CORS — the Vite dev origin.
    cors_origins: list[str] = ["http://localhost:5173", "http://127.0.0.1:5173"]


settings = Settings()
