"""Frozen templates: fixed components, data that may change per request.

A template lives in two files:

- templates/<intent>.json: {intent, title, prompt, keywords, text, messages},
  where messages holds the createSurface and updateComponents messages. The
  components never change.
- data/<intent>.json: the default data model (the updateDataModel value).

render() copies the data, lets the intent's data function in intents.py adjust
it from the prompt, and returns the three A2UI messages plus the markdown text
used for responseFormat text.

The one generic component rule: a FlexGrid item whose bindings no longer
resolve (because a data function filtered the list it points into) is dropped
from the grid. That keeps a filtered list valid without editing the template.
"""

from __future__ import annotations

import copy
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .config import A2UI_VERSION
from .validation import child_ids, iter_bindings, resolves


@dataclass
class Template:
    intent: str
    title: str
    prompt: str
    keywords: list[str]
    text: str
    create_surface: dict[str, Any]
    components: list[dict[str, Any]]
    data: dict[str, Any]


@dataclass
class Draft:
    """What a data function works on. It may change data and text."""

    intent: str
    prompt: str
    data: dict[str, Any]
    text: str
    components: list[dict[str, Any]]
    template: Template
    notes: list[str] = field(default_factory=list)


@dataclass
class Rendered:
    intent: str
    messages: list[dict[str, Any]]
    text: str
    notes: list[str]


class TemplateError(ValueError):
    pass


def load_template(template_path: Path, data_path: Path) -> Template:
    raw = json.loads(template_path.read_text(encoding="utf-8"))
    intent = raw.get("intent") or template_path.stem
    messages = raw.get("messages") or []
    create = next((m["createSurface"] for m in messages if "createSurface" in m), None)
    update = next((m["updateComponents"] for m in messages if "updateComponents" in m), None)
    if create is None or update is None:
        raise TemplateError(f"{template_path}: needs createSurface and updateComponents messages")
    if not data_path.exists():
        raise TemplateError(f"{template_path}: missing data file {data_path}")
    data = json.loads(data_path.read_text(encoding="utf-8"))
    return Template(
        intent=intent,
        title=raw.get("title") or intent,
        prompt=raw.get("prompt", ""),
        keywords=[k for k in raw.get("keywords", []) if isinstance(k, str) and k.strip()],
        text=raw.get("text") or raw.get("title") or intent,
        create_surface=create,
        components=update.get("components") or [],
        data=data,
    )


def prune_unresolved_grid_items(components: list[dict[str, Any]], data: Any) -> list[dict[str, Any]]:
    """Drop FlexGrid children whose data bindings no longer resolve."""
    by_id = {c.get("id"): c for c in components}
    dropped: set[str] = set()
    for comp in components:
        if comp.get("component") != "FlexGrid" or not isinstance(comp.get("children"), list):
            continue
        keep = []
        for cid in comp["children"]:
            child = by_id.get(cid)
            props = {k: v for k, v in (child or {}).items() if k not in ("id", "component")}
            if child is not None and all(resolves(data, p) for _, p in iter_bindings(props, cid)):
                keep.append(cid)
            else:
                dropped.add(cid)
        comp["children"] = keep
    if not dropped:
        return components
    # Also drop anything only reachable through a dropped item.
    reachable: set[str] = set()
    stack = ["root"]
    while stack:
        cid = stack.pop()
        if cid in reachable or cid not in by_id:
            continue
        reachable.add(cid)
        stack.extend(child_ids(by_id[cid]))
    return [c for c in components if c.get("id") in reachable]


class TemplateStore:
    """All templates in a templates dir, with their data files."""

    def __init__(self, templates_dir: Path, data_dir: Path):
        self.templates_dir = Path(templates_dir)
        self.data_dir = Path(data_dir)
        self._templates: dict[str, Template] = {}
        self.reload()

    def reload(self) -> None:
        templates: dict[str, Template] = {}
        for path in sorted(self.templates_dir.glob("*.json")):
            tpl = load_template(path, self.data_dir / path.name)
            templates[tpl.intent] = tpl
        self._templates = templates

    def __contains__(self, intent: object) -> bool:
        return intent in self._templates

    def get(self, intent: str) -> Template | None:
        return self._templates.get(intent)

    @property
    def intents(self) -> list[str]:
        return list(self._templates)

    def render(self, intent: str, prompt: str = "") -> Rendered:
        from .intents import DATA_FUNCTIONS

        tpl = self._templates.get(intent)
        if tpl is None:
            raise KeyError(intent)
        draft = Draft(
            intent=intent,
            prompt=prompt or "",
            data=copy.deepcopy(tpl.data),
            text=tpl.text,
            components=copy.deepcopy(tpl.components),
            template=tpl,
        )
        fn = DATA_FUNCTIONS.get(intent)
        if fn is not None:
            fn(draft)
        components = prune_unresolved_grid_items(draft.components, draft.data)
        sid = tpl.create_surface.get("surfaceId", intent)
        messages = [
            {"version": A2UI_VERSION, "createSurface": copy.deepcopy(tpl.create_surface)},
            {"version": A2UI_VERSION, "updateComponents": {"surfaceId": sid, "components": components}},
            {"version": A2UI_VERSION, "updateDataModel": {"surfaceId": sid, "path": "/", "value": draft.data}},
        ]
        return Rendered(intent=intent, messages=messages, text=draft.text, notes=draft.notes)
