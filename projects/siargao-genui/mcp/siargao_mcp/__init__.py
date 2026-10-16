"""MCP server that delivers Siargao A2UI v0.9 surfaces as a resource and a tool."""

from pathlib import Path

__version__ = "0.1.0"

ROOT = Path(__file__).resolve().parents[1]
SURFACES_DIR = ROOT / "surfaces"
TEMPLATES_DIR = ROOT / "templates"
DATA_DIR = ROOT / "data"
CATALOG_DIR = ROOT / "catalog"

A2UI_MIME_TYPE = "application/a2ui+json"
CATALOG_ID = "https://siargao-genui.example/catalogs/v1/catalog.json"
