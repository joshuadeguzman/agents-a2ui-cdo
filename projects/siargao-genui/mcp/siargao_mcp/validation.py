"""Runtime validation of A2UI v0.9 messages against the Siargao catalog.

This uses JSON Schema (the vendored A2UI v0.9 server_to_client.json with
siargao_catalog.json plugged in as its catalog.json) plus a few semantic
checks: a Stack root, every child exists and is reachable, every data binding
resolves, and image keys exist in images.json.

It deliberately does not import the a2ui SDK at runtime. a2ui-agent-sdk 0.8.0
pulls in google-adk and google-genai, which is far too heavy for a server that
makes no model calls. The tests run the SDK validator
(a2ui.utils.validate_payload) on every surface this server produces.
"""

from __future__ import annotations

import json
from functools import cache
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import best_match
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

from . import CATALOG_DIR

SPEC_DIR = CATALOG_DIR / "spec" / "v0_9"
# server_to_client.json and common_types.json refer to "catalog.json" relative
# to their own $id, which resolves to this URI.
SPEC_CATALOG_URI = "https://a2ui.org/specification/v0_9/catalog.json"

_MISSING = object()


def _load(name: str) -> Any:
    with (CATALOG_DIR / name).open(encoding="utf-8") as f:
        return json.load(f)


@cache
def message_validator() -> Draft202012Validator:
    s2c = _load("spec/v0_9/server_to_client.json")
    common = _load("spec/v0_9/common_types.json")
    cat = _load("siargao_catalog.json")

    def res(contents: dict[str, Any]) -> Resource:
        return Resource.from_contents(contents, default_specification=DRAFT202012)

    registry = Registry().with_resources(
        [
            (s2c["$id"], res(s2c)),
            (common["$id"], res(common)),
            (SPEC_CATALOG_URI, res(cat)),
            (cat["$id"], res(cat)),
        ]
    )
    return Draft202012Validator(s2c, registry=registry)


@cache
def image_keys() -> frozenset[str]:
    return frozenset(img["key"] for img in _load("images.json")["images"])


def resolve_pointer(data: Any, pointer: str) -> Any:
    if pointer in ("", "/"):
        return data
    if not pointer.startswith("/"):
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


def _is_binding(value: Any) -> bool:
    return isinstance(value, dict) and set(value) == {"path"} and isinstance(value["path"], str)


def _bindings(value: Any, where: str):
    if _is_binding(value):
        yield where, value["path"]
    elif isinstance(value, dict):
        for k, v in value.items():
            yield from _bindings(v, f"{where}.{k}")
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from _bindings(v, f"{where}[{i}]")


def _semantic_errors(messages: list[dict[str, Any]]) -> list[str]:
    components: list[dict[str, Any]] = []
    data: Any = {}
    for msg in messages:
        if "updateComponents" in msg:
            components += msg["updateComponents"].get("components", [])
        if "updateDataModel" in msg and msg["updateDataModel"].get("path", "/") == "/":
            data = msg["updateDataModel"].get("value", {})

    errors: list[str] = []
    by_id = {c.get("id"): c for c in components}
    root = by_id.get("root")
    if root is None or root.get("component") != "Stack":
        errors.append("the root component must exist and be a Stack")
        return errors

    reachable: set[str] = set()
    stack = ["root"]
    while stack:
        cid = stack.pop()
        if cid in reachable:
            continue
        reachable.add(cid)
        for child in by_id[cid].get("children") or []:
            if child not in by_id:
                errors.append(f"{cid}: child {child!r} does not exist")
            else:
                stack.append(child)
    errors += [f"{cid}: not reachable from root" for cid in by_id if cid not in reachable]

    for comp in components:
        cid = comp.get("id")
        props = {k: v for k, v in comp.items() if k not in ("id", "component")}
        for where, path in _bindings(props, cid):
            if resolve_pointer(data, path) is _MISSING:
                errors.append(f"{where}: binding {path!r} does not resolve in the data model")
        image = comp.get("image")
        if image is not None:
            key = resolve_pointer(data, image["path"]) if _is_binding(image) else image
            if key is not _MISSING and key not in image_keys():
                errors.append(f"{cid}.image: {key!r} is not a known image key")
    return errors


def validate_messages(messages: Any) -> list[str]:
    """Return a list of problems with an A2UI message list; empty means valid."""
    if not isinstance(messages, list) or not messages:
        return ["messages must be a non-empty JSON array"]
    errors: list[str] = []
    validator = message_validator()
    for i, msg in enumerate(messages):
        err = best_match(validator.iter_errors(msg))
        if err is not None:
            loc = "/".join(str(p) for p in err.absolute_path) or "(message)"
            errors.append(f"schema: messages[{i}] at {loc}: {err.message[:300]}")
    if errors:
        return errors
    return _semantic_errors(messages)
