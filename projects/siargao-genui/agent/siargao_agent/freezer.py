"""Promote a logged surface to a frozen template (used by scripts/freeze.py)."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .config import A2UI_VERSION
from .surface_log import read_entry
from .validation import message_kind, validate_messages

INTENT_RE = re.compile(r"^[a-z][a-z0-9_]{1,63}$")


class FreezeError(ValueError):
    pass


@dataclass
class FreezeResult:
    template_path: Path
    data_path: Path
    id_map: dict[str, str]


def _kebab(cid: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", cid.lower()).strip("-") or "item"


def normalise_ids(components: list[dict[str, Any]]) -> dict[str, str]:
    """Map every component id to a unique kebab-case id ("root" stays "root")."""
    mapping: dict[str, str] = {}
    used: set[str] = set()
    for comp in components:
        old = comp.get("id")
        if not isinstance(old, str):
            continue
        new = "root" if old == "root" else _kebab(old)
        if new == "root" and old != "root":
            new = "root-item"
        base, n = new, 2
        while new in used:
            new = f"{base}-{n}"
            n += 1
        used.add(new)
        mapping[old] = new
    return mapping


def _rename(components: list[dict[str, Any]], mapping: dict[str, str]) -> list[dict[str, Any]]:
    out = []
    for comp in components:
        comp = json.loads(json.dumps(comp))
        if comp.get("id") in mapping:
            comp["id"] = mapping[comp["id"]]
        children = comp.get("children")
        if isinstance(children, list):
            comp["children"] = [mapping.get(c, c) for c in children]
        elif isinstance(children, dict) and children.get("componentId") in mapping:
            children["componentId"] = mapping[children["componentId"]]
        out.append(comp)
    return out


def build_template(entry: dict[str, Any], intent: str, keywords: list[str], title: str | None, text: str | None):
    messages = entry.get("messages") or []
    if not messages:
        raise FreezeError("that log line has no A2UI messages (was it a text reply?)")
    create = next((m["createSurface"] for m in messages if message_kind(m) == "createSurface"), None)
    components: list[dict[str, Any]] = []
    for m in messages:
        if message_kind(m) == "updateComponents":
            components.extend(m["updateComponents"].get("components") or [])
    data = next(
        (
            m["updateDataModel"].get("value")
            for m in messages
            if message_kind(m) == "updateDataModel" and m["updateDataModel"].get("path", "/") in ("", "/")
        ),
        None,
    )
    if create is None or not components:
        raise FreezeError("the surface needs createSurface and updateComponents messages")
    if not isinstance(data, dict):
        raise FreezeError('the surface needs an updateDataModel at path "/" holding an object')

    mapping = normalise_ids(components)
    components = _rename(components, mapping)
    create = {**create, "surfaceId": intent}
    tpl_messages = [
        {"version": A2UI_VERSION, "createSurface": create},
        {"version": A2UI_VERSION, "updateComponents": {"surfaceId": intent, "components": components}},
    ]
    full = [
        *tpl_messages,
        {"version": A2UI_VERSION, "updateDataModel": {"surfaceId": intent, "path": "/", "value": data}},
    ]
    errors = validate_messages(full, surface_id=intent)
    if errors:
        raise FreezeError("the surface is not valid, refusing to freeze it:\n  - " + "\n  - ".join(errors))
    template = {
        "intent": intent,
        "title": title or intent.replace("_", " ").capitalize(),
        "prompt": entry.get("prompt", ""),
        "keywords": keywords,
        "text": text or entry.get("text") or title or intent.replace("_", " ").capitalize(),
        "messages": tpl_messages,
    }
    return template, data, mapping


def freeze(
    log_path: Path,
    line: int,
    intent: str,
    *,
    templates_dir: Path,
    data_dir: Path,
    keywords: list[str] | None = None,
    title: str | None = None,
    text: str | None = None,
    force: bool = False,
) -> FreezeResult:
    if not INTENT_RE.match(intent):
        raise FreezeError(f"intent must be snake_case like 'food_guide', got {intent!r}")
    try:
        entry = read_entry(log_path, line)
    except (OSError, ValueError) as e:
        raise FreezeError(str(e)) from e
    template, data, mapping = build_template(
        entry, intent, [k.strip() for k in keywords or [] if k.strip()], title, text
    )
    tpl_path = Path(templates_dir) / f"{intent}.json"
    data_path = Path(data_dir) / f"{intent}.json"
    existing = [p for p in (tpl_path, data_path) if p.exists()]
    if existing and not force:
        raise FreezeError(f"{', '.join(map(str, existing))} already exists; pass --force to overwrite")
    tpl_path.parent.mkdir(parents=True, exist_ok=True)
    data_path.parent.mkdir(parents=True, exist_ok=True)
    tpl_path.write_text(json.dumps(template, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    data_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return FreezeResult(tpl_path, data_path, mapping)
