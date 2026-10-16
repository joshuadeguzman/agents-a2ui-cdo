"""The agent vendors catalog files; fail if they drift from the source.

Fix a failure with: agent/scripts/sync_catalog.sh
"""

from __future__ import annotations

import pytest
from conftest import AGENT_DIR, PROJECT_DIR

from siargao_agent.config import CATALOG_DIR

EM_DASH = chr(0x2014)


@pytest.mark.parametrize("name", ["siargao_catalog.json", "rules.txt", "images.json"])
def test_vendored_catalog_matches_source(name):
    assert (CATALOG_DIR / name).read_bytes() == (PROJECT_DIR / "catalog" / name).read_bytes(), (
        f"siargao_agent/catalog/{name} drifted from catalog/{name}; run scripts/sync_catalog.sh"
    )


def test_vendored_stays_dataset_matches_source():
    assert (AGENT_DIR / "data" / "stays_dataset.json").read_bytes() == (
        PROJECT_DIR / "fixtures" / "stays_dataset.json"
    ).read_bytes(), "data/stays_dataset.json drifted; run scripts/sync_catalog.sh"


def test_no_em_dashes_in_agent_files():
    skip = {".venv", "logs", "__pycache__", ".pytest_cache", ".ruff_cache"}
    offenders = []
    for path in AGENT_DIR.rglob("*"):
        if path.is_file() and not skip.intersection(path.relative_to(AGENT_DIR).parts):
            try:
                if EM_DASH in path.read_text(encoding="utf-8"):
                    offenders.append(str(path.relative_to(AGENT_DIR)))
            except UnicodeDecodeError:
                continue
    assert offenders == []
