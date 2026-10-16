"""Settings read from the environment, with paths that work from any cwd."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

PACKAGE_DIR = Path(__file__).resolve().parent
AGENT_DIR = PACKAGE_DIR.parent
CATALOG_DIR = PACKAGE_DIR / "catalog"
CATALOG_PATH = CATALOG_DIR / "siargao_catalog.json"
RULES_PATH = CATALOG_DIR / "rules.txt"
IMAGES_PATH = CATALOG_DIR / "images.json"
DEFAULT_TEMPLATES_DIR = AGENT_DIR / "templates"
DEFAULT_DATA_DIR = AGENT_DIR / "data"
DEFAULT_SURFACE_LOG = AGENT_DIR / "logs" / "surfaces.jsonl"

CATALOG_ID = "https://siargao-genui.example/catalogs/v1/catalog.json"
A2UI_VERSION = "v0.9"
A2UI_EXTENSION_URI = "https://a2ui.org/a2a-extension/a2ui/v0.9"
# docs/CONTRACT.md: the MIME type for A2UI inside an A2A DataPart.
A2UI_MIME_TYPE = "application/a2ui+json"

# The newest Gemini Flash id that google-adk 2.12.0 uses as its built-in
# default (LlmAgent.DEFAULT_MODEL). Override with GEMINI_MODEL.
DEFAULT_GEMINI_MODEL = "gemini-3.5-flash"

MODES = ("offline", "live")


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class Settings:
    mode: str = "offline"
    model: str = DEFAULT_GEMINI_MODEL
    # One extra model call when the first answer fails validation. Off by
    # default so a live request costs exactly one call.
    model_retry: bool = False
    surface_log: Path = DEFAULT_SURFACE_LOG
    templates_dir: Path = DEFAULT_TEMPLATES_DIR
    data_dir: Path = DEFAULT_DATA_DIR
    base_url: str = "http://localhost:10002"
    # True when PUBLIC_URL is set: the agent card then always shows base_url.
    # Otherwise the card shows the URL the client used.
    base_url_pinned: bool = False

    @property
    def live(self) -> bool:
        return self.mode == "live"

    @classmethod
    def from_env(cls) -> Settings:
        mode = os.environ.get("SIARGAO_MODE", "offline").strip().lower() or "offline"
        if mode not in MODES:
            raise ValueError(f"SIARGAO_MODE must be one of {MODES}, got {mode!r}")
        port = os.environ.get("PORT", "10002")
        return cls(
            mode=mode,
            model=os.environ.get("GEMINI_MODEL", "").strip() or DEFAULT_GEMINI_MODEL,
            model_retry=_env_bool("SIARGAO_MODEL_RETRY", False),
            surface_log=Path(os.environ.get("SURFACE_LOG") or DEFAULT_SURFACE_LOG),
            templates_dir=Path(os.environ.get("SIARGAO_TEMPLATES_DIR") or DEFAULT_TEMPLATES_DIR),
            data_dir=Path(os.environ.get("SIARGAO_DATA_DIR") or DEFAULT_DATA_DIR),
            base_url=(os.environ.get("PUBLIC_URL") or f"http://localhost:{port}").rstrip("/"),
            base_url_pinned=bool(os.environ.get("PUBLIC_URL")),
        )
