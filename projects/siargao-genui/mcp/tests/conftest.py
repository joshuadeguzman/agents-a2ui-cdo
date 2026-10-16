from __future__ import annotations

import json
import socket
import threading
import time
from collections.abc import Iterator
from functools import cache
from pathlib import Path
from typing import Any

import pytest
import uvicorn

from siargao_mcp import CATALOG_DIR, ROOT
from siargao_mcp.server import create_app

PROJECT_DIR = ROOT.parent
FIXTURES_DIR = PROJECT_DIR / "fixtures"


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


@cache
def _sdk_catalog() -> Any:
    from a2ui.schema.catalog import CatalogConfig

    return CatalogConfig.from_path("siargao", str(CATALOG_DIR / "siargao_catalog.json")).to_catalog(
        protocol_version="0.9"
    )


def sdk_validate(messages: list[dict[str, Any]]) -> None:
    """Validate with the a2ui SDK (raises on failure)."""
    from a2ui.utils import validate_payload

    validate_payload([_sdk_catalog()], messages)


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="session")
def base_url() -> Iterator[str]:
    """A real uvicorn server on a free port, running in a background thread."""
    port = _free_port()
    config = uvicorn.Config(create_app(), host="127.0.0.1", port=port, log_level="warning")
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    deadline = time.monotonic() + 10
    while not server.started:
        if time.monotonic() > deadline:
            raise RuntimeError("uvicorn did not start")
        time.sleep(0.05)
    yield f"http://127.0.0.1:{port}"
    server.should_exit = True
    thread.join(timeout=10)
