"""Validate A2UI messages against the Siargao catalog.

Every response the agent sends, template or model, goes through
validate_messages. It runs the a2ui SDK validator (a2ui.utils.validate_payload
with the catalog loaded by CatalogConfig) and then the semantic checks the SDK
does not cover: one Stack root, every child id exists and is reachable, data
bindings resolve, image keys exist, two-way inputs are bound.
"""

from __future__ import annotations

import json
from functools import cache
from typing import Any

from .config import A2UI_VERSION, CATALOG_ID, CATALOG_PATH, IMAGES_PATH

MESSAGE_KINDS = ("createSurface", "updateComponents", "updateDataModel", "deleteSurface")
# Properties that must be two-way bindings, per catalog/rules.txt.
TWO_WAY = {"BudgetSlider": "value", "ChipRow": "selected"}

_MISSING = object()


@cache
def catalog_json() -> dict[str, Any]:
    return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))


@cache
def image_keys() -> frozenset[str]:
    return frozenset(img["key"] for img in json.loads(IMAGES_PATH.read_text(encoding="utf-8"))["images"])


@cache
def sdk_catalog() -> Any:
    """The catalog as an a2ui SDK Catalog for protocol 0.9."""
    from a2ui.schema.catalog import CatalogConfig

    return CatalogConfig.from_path("siargao", str(CATALOG_PATH)).to_catalog(protocol_version="0.9")


def message_kind(msg: Any) -> str | None:
    if not isinstance(msg, dict):
        return None
    return next((k for k in msg if k in MESSAGE_KINDS), None)


def resolve_pointer(data: Any, pointer: str) -> Any:
    """Resolve a JSON Pointer in data; returns _MISSING when it does not exist."""
    if pointer in ("", "/"):
        return data
    if not isinstance(pointer, str) or not pointer.startswith("/"):
        return _MISSING
    node = data
    for raw in pointer[1:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(node, dict):
            if token not in node:
                return _MISSING
            node = node[token]
        elif isinstance(node, list):
            if not token.isdigit() or int(token) >= len(node):
                return _MISSING
            node = node[int(token)]
        else:
            return _MISSING
    return node


def resolves(data: Any, pointer: str) -> bool:
    return resolve_pointer(data, pointer) is not _MISSING


def is_binding(value: Any) -> bool:
    return isinstance(value, dict) and set(value) == {"path"} and isinstance(value["path"], str)


def iter_bindings(value: Any, where: str):
    """Yield (location, path) for every {"path": ...} binding inside value."""
    if is_binding(value):
        yield where, value["path"]
    elif isinstance(value, dict):
        for k, v in value.items():
            yield from iter_bindings(v, f"{where}.{k}")
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from iter_bindings(v, f"{where}[{i}]")


def child_ids(component: dict[str, Any]) -> list[str]:
    children = component.get("children")
    if isinstance(children, dict):
        cid = children.get("componentId")
        return [cid] if isinstance(cid, str) else []
    if isinstance(children, list):
        return [c for c in children if isinstance(c, str)]
    return []


def check_sdk(messages: list[Any]) -> list[str]:
    from a2ui.core import A2uiError
    from a2ui.utils import validate_payload

    try:
        validate_payload([sdk_catalog()], messages)
    except A2uiError as e:
        return [f"a2ui sdk: {type(e).__name__}: {e}"]
    except Exception as e:
        return [f"a2ui sdk crashed: {type(e).__name__}: {e}"]
    return []


def check_semantics(messages: list[Any], surface_id: str | None = None) -> list[str]:
    errors: list[str] = []
    if not isinstance(messages, list) or not messages:
        return ["messages must be a non-empty list"]
    kinds = [message_kind(m) for m in messages]
    if None in kinds:
        return [f"unknown message at index {kinds.index(None)}"]
    for i, m in enumerate(messages):
        if m.get("version") != A2UI_VERSION:
            errors.append(f"messages[{i}].version must be {A2UI_VERSION!r}")
    if kinds[0] != "createSurface":
        errors.append("the first message must be createSurface")
    if "updateComponents" not in kinds:
        errors.append("an updateComponents message is required")

    bodies = [(k, m[k]) for k, m in zip(kinds, messages, strict=True)]
    sids = {b.get("surfaceId") for _, b in bodies if isinstance(b, dict)}
    if len(sids) != 1:
        errors.append(f"all messages must share one surfaceId, got {sorted(map(str, sids))}")
    elif surface_id is not None and sids != {surface_id}:
        errors.append(f"surfaceId must be {surface_id!r}, got {next(iter(sids))!r}")

    for kind, body in bodies:
        if kind == "createSurface" and body.get("catalogId") != CATALOG_ID:
            errors.append(f"createSurface.catalogId must be {CATALOG_ID}")

    components: list[dict[str, Any]] = []
    for kind, body in bodies:
        if kind == "updateComponents":
            components.extend(c for c in body.get("components") or [] if isinstance(c, dict))

    data: Any = {}
    have_data = False
    for kind, body in bodies:
        if kind == "updateDataModel":
            path = body.get("path", "/")
            if path in ("", "/"):
                data = body.get("value", {})
                have_data = True

    by_id: dict[str, dict[str, Any]] = {}
    for comp in components:
        cid = comp.get("id")
        if cid in by_id:
            errors.append(f"duplicate component id {cid!r}")
        by_id[cid] = comp

    known = set(catalog_json()["components"])
    for comp in components:
        if comp.get("component") not in known:
            errors.append(f"{comp.get('id')}: unknown component {comp.get('component')!r}")

    root = by_id.get("root")
    if root is None:
        errors.append("no component with id 'root'")
    elif root.get("component") != "Stack":
        errors.append(f"root must be a Stack, got {root.get('component')!r}")

    reachable: set[str] = set()
    stack = ["root"] if root else []
    while stack:
        cid = stack.pop()
        if cid in reachable:
            continue
        reachable.add(cid)
        for child in child_ids(by_id[cid]):
            if child not in by_id:
                errors.append(f"{cid}: child {child!r} does not exist")
            else:
                stack.append(child)
    if root:
        errors.extend(f"{cid}: not reachable from root" for cid in by_id if cid not in reachable)

    for comp in components:
        cid = comp.get("id")
        if have_data:
            props = {k: v for k, v in comp.items() if k not in ("id", "component")}
            for where, path in iter_bindings(props, cid):
                if not resolves(data, path):
                    errors.append(f"{where}: binding {path!r} does not resolve in the data model")
        image = comp.get("image")
        if image is not None:
            key = resolve_pointer(data, image["path"]) if is_binding(image) else image
            if key is not _MISSING and (have_data or not is_binding(image)) and key not in image_keys():
                errors.append(f"{cid}.image: {key!r} is not a known image key")
        prop = TWO_WAY.get(comp.get("component"))
        if prop and not is_binding(comp.get(prop)):
            errors.append(f"{cid}.{prop} must be a {{'path': ...}} binding")
    return errors


def validate_messages(messages: list[Any], surface_id: str | None = None) -> list[str]:
    """Return a list of problems; an empty list means the surface is valid."""
    if not isinstance(messages, list) or not messages or any(message_kind(m) is None for m in messages):
        return check_semantics(messages, surface_id)
    return check_sdk(messages) + check_semantics(messages, surface_id)
