"""The vendored copies in mcp/ must match their sources. Fix with scripts/sync_shared.sh."""

import pytest

from conftest import PROJECT_DIR
from siargao_mcp import ROOT

VENDORED = {
    "surfaces/home_first_run.json": "fixtures/home_first_run.json",
    "data/stays.json": "fixtures/stays_dataset.json",
    "catalog/siargao_catalog.json": "catalog/siargao_catalog.json",
    "catalog/images.json": "catalog/images.json",
    "catalog/spec/v0_9/server_to_client.json": "catalog/spec/v0_9/server_to_client.json",
    "catalog/spec/v0_9/common_types.json": "catalog/spec/v0_9/common_types.json",
    "catalog/spec/v0_9/SOURCE.txt": "catalog/spec/v0_9/SOURCE.txt",
}


@pytest.mark.parametrize(("copy", "source"), sorted(VENDORED.items()))
def test_vendored_copy_matches_source(copy: str, source: str) -> None:
    src = PROJECT_DIR / source
    if not src.exists():
        pytest.skip(f"{source} is not available (outside the repo, for example in a Docker build)")
    assert (ROOT / copy).read_bytes() == src.read_bytes(), (
        f"mcp/{copy} drifted from {source}; run scripts/sync_shared.sh"
    )


def test_sync_script_lists_every_vendored_file() -> None:
    script = (ROOT / "scripts" / "sync_shared.sh").read_text()
    for copy, source in VENDORED.items():
        assert f"copy {source} {copy}" in script
