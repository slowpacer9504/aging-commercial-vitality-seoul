"""Pytest fixtures. Starlette TestClient properly activates FastAPI lifespan."""
from __future__ import annotations

import pytest
from starlette.testclient import TestClient

from app.main import app


@pytest.fixture(scope="session")
def client() -> TestClient:
    # `with` triggers startup/shutdown (lifespan) handlers.
    with TestClient(app) as c:
        yield c
