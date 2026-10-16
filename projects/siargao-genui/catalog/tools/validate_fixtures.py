"""Validate the recorded A2UI fixtures against the Siargao catalog.

Each fixture in fixtures/<intent>.json is checked three ways:

1. JSON Schema: every message against the vendored A2UI v0.9
   server_to_client.json, with siargao_catalog.json plugged in as the
   catalog.json that the spec refers to.
2. a2ui SDK: the whole message list with a2ui.utils.validate_payload, using a
   Catalog loaded by a2ui.schema.CatalogConfig.from_path.
3. Semantic checks that neither schema covers: the fixture envelope from
   docs/CONTRACT.md, surfaceId == intent, a Stack root, every child id exists
   and every component is reachable, bindings resolve in the data model, image
   keys exist in images.json, and the stays_near_cloud9 data matches the
   search_stays filter over fixtures/stays_dataset.json.

Usage (from projects/siargao-genui):
    catalog/.venv/bin/python catalog/tools/validate_fixtures.py [fixture.json ...]

Exits with status 1 if any check fails.
"""

from __future__ import annotations

import argparse
import json
import sys
from functools import cache
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import best_match
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

CATALOG_DIR = Path(__file__).resolve().parents[1]
PROJECT_DIR = CATALOG_DIR.parent
FIXTURES_DIR = PROJECT_DIR / "fixtures"
CATALOG_PATH = CATALOG_DIR / "siargao_catalog.json"
IMAGES_PATH = CATALOG_DIR / "images.json"
SPEC_DIR = CATALOG_DIR / "spec" / "v0_9"
STAYS_DATASET_PATH = FIXTURES_DIR / "stays_dataset.json"

CATALOG_ID = "https://siargao-genui.example/catalogs/v1/catalog.json"
# server_to_client.json and common_types.json refer to "catalog.json" relative
# to their own $id, which resolves to this URI.
SPEC_CATALOG_URI = "https://a2ui.org/specification/v0_9/catalog.json"

# Intent -> path, from the table in docs/CONTRACT.md.
INTENTS = {
    "first_time_trip": "a2a",
    "returning_flexible": "a2a",
    "flights_under_8000": "a2a",
    "surf_this_week": "a2a",
    "home_first_run": "mcp_resource",
    "stays_near_cloud9": "mcp_tool",
}
NON_FIXTURE_FILES = {"stays_dataset.json"}
FIXTURE_KEYS = {"intent", "title", "prompt", "path", "source", "modelCalls", "text", "messages"}
MAX_COMPONENTS = 25
# Properties that must be two-way bindings, per catalog/rules.txt.
TWO_WAY = {"BudgetSlider": "value", "ChipRow": "selected"}
EM_DASH = chr(0x2014)

# The search_stays(area="Cloud 9", nights=3, max_price=4500) call that the
# stays_near_cloud9 fixture records.
STAYS_QUERY = {"area": "Cloud 9", "nights": 3, "max_price": 4500}
MAX_STAY_RESULTS = 4


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


@cache
def catalog() -> dict[str, Any]:
    return load_json(CATALOG_PATH)


@cache
def image_keys() -> frozenset[str]:
    return frozenset(img["key"] for img in load_json(IMAGES_PATH)["images"])


@cache
def message_validator() -> Draft202012Validator:
    """A validator for one server_to_client message with our catalog plugged in."""
    s2c = load_json(SPEC_DIR / "server_to_client.json")
    common = load_json(SPEC_DIR / "common_types.json")
    cat = catalog()

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
def sdk_catalog() -> Any:
    from a2ui.schema.catalog import CatalogConfig

    return CatalogConfig.from_path("siargao", str(CATALOG_PATH)).to_catalog(protocol_version="0.9")


def search_stays(stays: list[dict[str, Any]], area: str, nights: int, max_price: float) -> list[dict[str, Any]]:
    """The search_stays filter rule documented in fixtures/README.md.

    Case-insensitive exact area match, pricePerNight <= max_price, sorted by
    price ascending (then id), at most 4 results. nights does not filter.
    """
    del nights  # Carried through to the surface, not used for filtering.
    hits = [s for s in stays if s["area"].casefold() == area.casefold() and s["pricePerNight"] <= max_price]
    hits.sort(key=lambda s: (s["pricePerNight"], s["id"]))
    return hits[:MAX_STAY_RESULTS]


_MISSING = object()


def resolve_pointer(data: Any, pointer: str) -> Any:
    """Resolve a JSON Pointer in data, returning _MISSING if it does not exist."""
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


def is_binding(value: Any) -> bool:
    return isinstance(value, dict) and set(value) == {"path"} and isinstance(value["path"], str)


def iter_bindings(value: Any, where: str):
    """Yield (location, path) for every {"path": ...} data binding inside value."""
    if is_binding(value):
        yield where, value["path"]
    elif isinstance(value, dict):
        for k, v in value.items():
            yield from iter_bindings(v, f"{where}.{k}")
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from iter_bindings(v, f"{where}[{i}]")


def iter_strings(value: Any):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for k, v in value.items():
            yield k
            yield from iter_strings(v)
    elif isinstance(value, list):
        for v in value:
            yield from iter_strings(v)


def _narrow(err: Any) -> Any:
    """Make an anyComponent oneOf error point at the branch for that component.

    Without this, a bad property on a Heading reports "is not valid under any of
    the given schemas" for the whole component.
    """
    names = list(catalog()["components"])
    while err.validator == "oneOf" and err.context:
        inst = err.instance
        name = inst.get("component") if isinstance(inst, dict) else None
        if name not in names or len(err.validator_value) != len(names):
            break
        idx = names.index(name)
        branch = [e for e in err.context if e.relative_schema_path and e.relative_schema_path[0] == idx]
        if not branch:
            break
        # A failing property also makes unevaluatedProperties list every
        # property; report the real cause first.
        err = best_match([e for e in branch if e.validator != "unevaluatedProperties"] or branch)
    return err


def check_schema(messages: list[Any]) -> list[str]:
    errors = []
    validator = message_validator()
    for i, msg in enumerate(messages):
        err = best_match(validator.iter_errors(msg))
        if err is not None:
            err = _narrow(err)
            loc = "/".join(str(p) for p in err.absolute_path) or "(message)"
            errors.append(f"schema: messages[{i}] at {loc}: {err.message[:300]}")
    return errors


def check_sdk(messages: list[Any]) -> list[str]:
    from a2ui.core import A2uiError
    from a2ui.utils import validate_payload

    try:
        validate_payload([sdk_catalog()], messages)
    except A2uiError as e:
        return [f"a2ui sdk: {type(e).__name__}: {e}"]
    return []


def check_envelope(fixture: Any, name: str) -> list[str]:
    if not isinstance(fixture, dict):
        return ["fixture must be a JSON object"]
    errors = []
    keys = set(fixture)
    if missing := FIXTURE_KEYS - keys:
        errors.append(f"missing keys: {sorted(missing)}")
    if extra := keys - FIXTURE_KEYS:
        errors.append(f"unexpected keys: {sorted(extra)}")
    intent = fixture.get("intent")
    if intent != name:
        errors.append(f"intent {intent!r} must equal the file name {name!r}")
    if intent not in INTENTS:
        errors.append(f"intent {intent!r} is not one of {sorted(INTENTS)}")
    elif fixture.get("path") != INTENTS[intent]:
        errors.append(f"path must be {INTENTS[intent]!r} for {intent}, got {fixture.get('path')!r}")
    if fixture.get("source") not in ("template", "model"):
        errors.append("source must be 'template' or 'model'")
    mc = fixture.get("modelCalls")
    if not isinstance(mc, int) or isinstance(mc, bool) or mc < 0:
        errors.append("modelCalls must be a non-negative integer")
    elif fixture.get("source") == "template" and mc != 0:
        errors.append("modelCalls must be 0 for a template")
    for key in ("title", "prompt", "text"):
        if not isinstance(fixture.get(key), str) or not fixture.get(key, "").strip():
            errors.append(f"{key} must be a non-empty string")
    if not isinstance(fixture.get("messages"), list) or not fixture["messages"]:
        errors.append("messages must be a non-empty list")
    if any(EM_DASH in s for s in iter_strings(fixture)):
        errors.append("contains an em dash (U+2014); rewrite without it")
    return errors


def check_semantics(fixture: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    intent = fixture.get("intent")
    messages = fixture.get("messages") or []
    kinds = [next((k for k in m if k != "version"), None) if isinstance(m, dict) else None for m in messages]
    if kinds != ["createSurface", "updateComponents", "updateDataModel"]:
        errors.append(f"messages must be createSurface, updateComponents, updateDataModel in that order, got {kinds}")
        return errors
    create, update, data_msg = (m[k] for m, k in zip(messages, kinds, strict=True))

    for kind, body in zip(kinds, (create, update, data_msg), strict=True):
        if body.get("surfaceId") != intent:
            errors.append(f"{kind}.surfaceId {body.get('surfaceId')!r} must equal intent {intent!r}")
    if create.get("catalogId") != CATALOG_ID:
        errors.append(f"createSurface.catalogId must be {CATALOG_ID}")
    if data_msg.get("path", "/") != "/":
        errors.append("updateDataModel.path must be '/'")
    data = data_msg.get("value")
    if not isinstance(data, dict):
        errors.append("updateDataModel.value must be an object holding the whole data model")
        data = {}

    components = update.get("components") or []
    by_id: dict[str, dict[str, Any]] = {}
    for comp in components:
        cid = comp.get("id")
        if cid in by_id:
            errors.append(f"duplicate component id {cid!r}")
        by_id[cid] = comp
    if len(components) > MAX_COMPONENTS:
        errors.append(f"{len(components)} components; keep a surface at or under {MAX_COMPONENTS}")

    known = set(catalog()["components"])
    for comp in components:
        if comp.get("component") not in known:
            errors.append(f"{comp.get('id')}: unknown component {comp.get('component')!r}")

    root = by_id.get("root")
    if root is None:
        errors.append("no component with id 'root'")
    elif root.get("component") != "Stack":
        errors.append(f"root must be a Stack, got {root.get('component')!r}")

    # Children exist, and everything is reachable from root.
    reachable: set[str] = set()
    stack = ["root"] if root else []
    while stack:
        cid = stack.pop()
        if cid in reachable:
            continue
        reachable.add(cid)
        children = by_id[cid].get("children")
        if isinstance(children, dict):
            children = [children.get("componentId")]
        for child in children or []:
            if child not in by_id:
                errors.append(f"{cid}: child {child!r} does not exist")
            else:
                stack.append(child)
    if root:
        for cid in by_id:
            if cid not in reachable:
                errors.append(f"{cid}: not reachable from root")

    for comp in components:
        cid = comp.get("id")
        for where, path in iter_bindings({k: v for k, v in comp.items() if k not in ("id", "component")}, cid):
            if resolve_pointer(data, path) is _MISSING:
                errors.append(f"{where}: binding {path!r} does not resolve in the data model")
        if isinstance(comp.get("children"), dict):
            tpl = resolve_pointer(data, comp["children"].get("path", ""))
            if not isinstance(tpl, list):
                errors.append(f"{cid}.children: template path must point at an array")

        image = comp.get("image")
        if image is not None:
            key = resolve_pointer(data, image["path"]) if is_binding(image) else image
            if key is not _MISSING and key not in image_keys():
                errors.append(f"{cid}.image: {key!r} is not a key in catalog/images.json")

        prop = TWO_WAY.get(comp.get("component"))
        if prop and not is_binding(comp.get(prop)):
            errors.append(f"{cid}.{prop} must be a {{'path': ...}} binding so it is two-way")

    if intent == "stays_near_cloud9":
        errors += check_stays(data)
    return errors


def check_stays(data: dict[str, Any]) -> list[str]:
    dataset = load_json(STAYS_DATASET_PATH)["stays"]
    expected = search_stays(dataset, **STAYS_QUERY)
    errors = []
    if data.get("query") != STAYS_QUERY:
        errors.append(f"data /query must be {STAYS_QUERY}")
    if data.get("stays") != expected:
        errors.append("data /stays does not match search_stays over fixtures/stays_dataset.json")
    return errors


def validate_fixture_obj(fixture: Any, name: str, *, use_sdk: bool = True) -> list[str]:
    errors = check_envelope(fixture, name)
    if not isinstance(fixture, dict) or not isinstance(fixture.get("messages"), list):
        return errors
    messages = fixture["messages"]
    errors += check_schema(messages)
    if use_sdk:
        errors += check_sdk(messages)
    errors += check_semantics(fixture)
    return errors


def validate_fixture(path: Path, *, use_sdk: bool = True) -> list[str]:
    try:
        fixture = load_json(path)
    except json.JSONDecodeError as e:
        return [f"invalid JSON: {e}"]
    return validate_fixture_obj(fixture, path.stem, use_sdk=use_sdk)


def fixture_paths() -> list[Path]:
    return sorted(p for p in FIXTURES_DIR.glob("*.json") if p.name not in NON_FIXTURE_FILES)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("fixtures", nargs="*", type=Path, help="fixture files (default: all in fixtures/)")
    parser.add_argument("--no-sdk", action="store_true", help="skip the a2ui SDK validator")
    args = parser.parse_args(argv)

    paths = args.fixtures or fixture_paths()
    failed = False
    if not args.fixtures:
        missing = set(INTENTS) - {p.stem for p in paths}
        if missing:
            print(f"FAIL missing fixtures for intents: {sorted(missing)}")
            failed = True
    for path in paths:
        errors = validate_fixture(path, use_sdk=not args.no_sdk)
        if errors:
            failed = True
            print(f"FAIL {path.name}")
            for e in errors:
                print(f"  - {e}")
        else:
            print(f"ok   {path.name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
