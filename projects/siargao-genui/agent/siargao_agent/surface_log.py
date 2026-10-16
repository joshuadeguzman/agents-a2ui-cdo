"""Append every response to a JSONL log (one JSON object per line).

scripts/freeze.py reads this log to promote a good model surface to a template.
"""

from __future__ import annotations

import json
import logging
import threading
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


class SurfaceLog:
    def __init__(self, path: Path):
        self.path = Path(path)
        self._lock = threading.Lock()

    def write(self, entry: dict[str, Any]) -> dict[str, Any]:
        record = {"timestamp": datetime.now(UTC).isoformat(timespec="milliseconds"), **entry}
        line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
        try:
            with self._lock:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                with self.path.open("a", encoding="utf-8") as f:
                    f.write(line + "\n")
        except OSError as e:  # Logging must never break a response.
            logger.warning("could not write surface log %s: %s", self.path, e)
        return record


def read_entry(path: Path, line_number: int) -> dict[str, Any]:
    """Return the entry on a 1-based line of a surface log."""
    if line_number < 1:
        raise ValueError("line numbers start at 1")
    with Path(path).open(encoding="utf-8") as f:
        for i, line in enumerate(f, start=1):
            if i == line_number:
                return json.loads(line)
    raise ValueError(f"{path} has fewer than {line_number} lines")
