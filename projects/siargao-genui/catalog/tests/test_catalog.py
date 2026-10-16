"""Tests for the Siargao catalog, the fixtures and the Dart codegen."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any

import gen_dart
import pytest
import validate_fixtures as vf
from jsonschema import Draft202012Validator

EXPECTED_COMPONENTS = [
    "Stack",
    "Heading",
    "ItineraryDay",
    "CostBreakdown",
    "StayCard",
    "BudgetSlider",
    "ChipRow",
    "LocalNote",
    "FlexGrid",
    "Actions",
]
EM_DASH = chr(0x2014)


def own_part(name: str) -> dict[str, Any]:
    spec = vf.catalog()["components"][name]
    return next(p for p in spec["allOf"] if p.get("properties", {}).get("component", {}).get("const") == name)


def load_fixture(intent: str) -> dict[str, Any]:
    return vf.load_json(vf.FIXTURES_DIR / f"{intent}.json")


# ---------------------------------------------------------------- catalog


def test_catalog_is_valid_draft_2020_12_schema():
    Draft202012Validator.check_schema(vf.catalog())


def test_catalog_identity():
    cat = vf.catalog()
    assert cat["catalogId"] == vf.CATALOG_ID
    assert cat["$id"] == vf.CATALOG_ID
    assert cat["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert {"CatalogComponentCommon", "anyComponent", "theme", "anyFunction"} <= set(cat["$defs"])


def test_all_ten_components_present():
    cat = vf.catalog()
    assert list(cat["components"]) == EXPECTED_COMPONENTS
    refs = [r["$ref"] for r in cat["$defs"]["anyComponent"]["oneOf"]]
    assert refs == [f"#/components/{n}" for n in EXPECTED_COMPONENTS]


@pytest.mark.parametrize("name", EXPECTED_COMPONENTS)
def test_component_shape_and_descriptions(name):
    spec = vf.catalog()["components"][name]
    assert spec.get("description", "").strip(), f"{name} needs a description"
    assert spec["unevaluatedProperties"] is False
    assert {"$ref": "https://a2ui.org/specification/v0_9/common_types.json#/$defs/ComponentCommon"} in spec["allOf"]
    part = own_part(name)
    assert part["required"][0] == "component"
    for prop, schema in part["properties"].items():
        if prop == "component":
            continue
        assert schema.get("description", "").strip(), f"{name}.{prop} needs a description"


def test_images_are_unique_and_sized():
    keys = [i["key"] for i in vf.load_json(vf.IMAGES_PATH)["images"]]
    assert len(keys) == len(set(keys))
    assert 10 <= len(keys) <= 14
    for img in vf.load_json(vf.IMAGES_PATH)["images"]:
        assert img["alt"].strip()


def test_sdk_loads_custom_catalog():
    cat = vf.sdk_catalog()
    assert cat.catalog_id == vf.CATALOG_ID
    assert str(cat.protocol_version) == "0.9"


def test_no_em_dashes_in_catalog_files():
    files = [
        *vf.CATALOG_DIR.glob("*.json"),
        *vf.CATALOG_DIR.glob("*.txt"),
        *vf.CATALOG_DIR.glob("*.md"),
        *vf.CATALOG_DIR.glob("tools/*.py"),
        *vf.FIXTURES_DIR.glob("*"),
    ]
    for path in files:
        if path.is_file():
            assert EM_DASH not in path.read_text(encoding="utf-8"), path


# ---------------------------------------------------------------- fixtures


def test_every_intent_has_a_fixture():
    assert {p.stem for p in vf.fixture_paths()} == set(vf.INTENTS)


@pytest.mark.parametrize("intent", sorted(vf.INTENTS))
def test_fixture_validates(intent):
    assert vf.validate_fixture(vf.FIXTURES_DIR / f"{intent}.json") == []


@pytest.mark.parametrize("intent", sorted(vf.INTENTS))
def test_fixture_size(intent):
    components = load_fixture(intent)["messages"][1]["updateComponents"]["components"]
    assert 8 <= len(components) <= 20


def test_fixtures_include_events_with_context():
    found = []
    for intent in vf.INTENTS:
        for comp in load_fixture(intent)["messages"][1]["updateComponents"]["components"]:
            actions = [comp.get("action")] + [b["action"] for b in comp.get("buttons", [])]
            for action in filter(None, actions):
                event = action["event"]
                assert event["name"]
                if event.get("context"):
                    found.append((intent, event["name"]))
    names = {n for _, n in found}
    assert {"choose_stay", "book_plan"} <= names


def test_main_passes_on_real_fixtures(capsys):
    assert vf.main([]) == 0
    assert "FAIL" not in capsys.readouterr().out


def _comps(f: dict[str, Any]) -> list[dict[str, Any]]:
    return f["messages"][1]["updateComponents"]["components"]


def _by_id(f: dict[str, Any], cid: str) -> dict[str, Any]:
    return next(c for c in _comps(f) if c["id"] == cid)


def _data(f: dict[str, Any]) -> dict[str, Any]:
    return f["messages"][2]["updateDataModel"]["value"]


BREAKAGES = {
    "unknown property": lambda f: _by_id(f, "hero").update(bogus=1),
    "bad enum": lambda f: _by_id(f, "local-note").update(tone="angry"),
    "unknown component": lambda f: _comps(f).append({"id": "x", "component": "Carousel", "children": []}),
    "missing required prop": lambda f: _by_id(f, "budget").pop("items"),
    "dangling child": lambda f: _by_id(f, "days-grid")["children"].append("day-9"),
    "orphan component": lambda f: _comps(f).append({"id": "lost", "component": "Heading", "title": "Lost"}),
    "no root": lambda f: _by_id(f, "root").update(id="top"),
    "root not a Stack": lambda f: _comps(f).__setitem__(
        0, {"id": "root", "component": "FlexGrid", "children": _by_id(f, "root")["children"]}
    ),
    "unresolved binding": lambda f: _by_id(f, "hero").update(title={"path": "/trip/missing"}),
    "unknown image key": lambda f: _data(f)["trip"].update(image="eiffel-tower"),
    "surfaceId mismatch": lambda f: f["messages"][1]["updateComponents"].update(surfaceId="other"),
    "wrong catalogId": lambda f: f["messages"][0]["createSurface"].update(catalogId="basic"),
    "function call": lambda f: _by_id(f, "hero").update(title={"call": "upper", "args": {}, "returnType": "string"}),
    "em dash in text": lambda f: f.update(text="Day 1 " + EM_DASH + " arrive"),
    "wrong path": lambda f: f.update(path="mcp_tool"),
    "bad version": lambda f: f["messages"][0].update(version="v0.8"),
}


@pytest.mark.parametrize("breakage", sorted(BREAKAGES))
def test_broken_fixture_fails(breakage):
    fixture = copy.deepcopy(load_fixture("first_time_trip"))
    BREAKAGES[breakage](fixture)
    assert vf.validate_fixture_obj(fixture, "first_time_trip"), f"{breakage} was not caught"


def test_broken_fixture_file_exits_nonzero(tmp_path: Path):
    fixture = load_fixture("first_time_trip")
    _by_id(fixture, "local-note")["tone"] = "angry"
    path = tmp_path / "first_time_trip.json"
    path.write_text(json.dumps(fixture), encoding="utf-8")
    assert vf.main([str(path)]) == 1


def test_two_way_inputs_must_be_bound():
    fixture = copy.deepcopy(load_fixture("stays_near_cloud9"))
    _by_id(fixture, "price-slider")["value"] = 4500
    errors = vf.validate_fixture_obj(fixture, "stays_near_cloud9", use_sdk=False)
    assert any("two-way" in e for e in errors)


# ---------------------------------------------------------------- stays


def test_search_stays_rule():
    stays = vf.load_json(vf.STAYS_DATASET_PATH)["stays"]
    assert len(stays) == 10
    assert len({s["id"] for s in stays}) == 10
    for s in stays:
        assert s["image"] in vf.image_keys()
    hits = vf.search_stays(stays, area="cloud 9", nights=3, max_price=4500)
    assert [s["pricePerNight"] for s in hits] == sorted(s["pricePerNight"] for s in hits)
    assert all(s["area"] == "Cloud 9" and s["pricePerNight"] <= 4500 for s in hits)
    assert 3 <= len(hits) <= 4
    cloud9 = [s for s in stays if s["area"] == "Cloud 9"]
    assert len(cloud9) > 4, "dataset should exercise the 4 result cap"
    assert len(vf.search_stays(stays, area="Cloud 9", nights=3, max_price=100000)) == 4
    assert vf.search_stays(stays, area="Nowhere", nights=3, max_price=100000) == []


def test_stays_fixture_matches_dataset():
    fixture = load_fixture("stays_near_cloud9")
    assert fixture["prompt"] == 'search_stays(area="Cloud 9", nights=3, max_price=4500)'
    stays = vf.load_json(vf.STAYS_DATASET_PATH)["stays"]
    assert _data(fixture)["stays"] == vf.search_stays(stays, **vf.STAYS_QUERY)
    cards = [c for c in _comps(fixture) if c["component"] == "StayCard"]
    assert len(cards) == len(_data(fixture)["stays"])


def test_tampered_stays_fixture_fails():
    fixture = copy.deepcopy(load_fixture("stays_near_cloud9"))
    _data(fixture)["stays"][0]["pricePerNight"] = 999
    assert any("search_stays" in e for e in vf.validate_fixture_obj(fixture, "stays_near_cloud9", use_sdk=False))


# ---------------------------------------------------------------- codegen


def test_component_schema_strips_component_property():
    schema = gen_dart.component_schema("StayCard", vf.catalog()["components"]["StayCard"])
    assert "component" not in schema["properties"]
    assert "component" not in schema["required"]
    assert schema["required"] == [r for r in own_part("StayCard")["required"] if r != "component"]


def test_dart_string_escaping():
    assert gen_dart.dart_string("plain") == "'plain'"
    assert gen_dart.dart_string("$ref") == "r'$ref'"
    assert gen_dart.dart_string("it's") == '"it\'s"'
    assert gen_dart.dart_string('it\'s "x" $y') == "'it\\'s \"x\" \\$y'"


@pytest.mark.skipif(gen_dart.find_dart() is None, reason="dart not installed")
def test_generated_dart_is_up_to_date():
    assert gen_dart.OUTPUT_PATH.exists(), "run catalog/tools/gen_dart.py"
    assert gen_dart.OUTPUT_PATH.read_text(encoding="utf-8") == gen_dart.render(), (
        "catalog_schemas.g.dart is stale; run catalog/tools/gen_dart.py"
    )
