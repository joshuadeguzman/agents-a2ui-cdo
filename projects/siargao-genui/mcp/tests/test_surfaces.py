from __future__ import annotations

import json

import pytest

from conftest import FIXTURES_DIR, load_json, sdk_validate
from siargao_mcp import ROOT
from siargao_mcp.surfaces import (
    MAX_STAY_RESULTS,
    build_stays_surface,
    home_first_run_messages,
    search_stays,
    stays_summary,
)
from siargao_mcp.validation import validate_messages

EM_DASH = chr(0x2014)


def _data(messages):
    return messages[2]["updateDataModel"]["value"]


def _components(messages):
    return messages[1]["updateComponents"]["components"]


def test_fixture_inputs_reproduce_fixture_exactly() -> None:
    messages, stays = build_stays_surface("Cloud 9", 3, 4500)
    fixture = load_json(FIXTURES_DIR / "stays_near_cloud9.json")
    assert messages == fixture["messages"]
    assert len(stays) == 4


def test_home_messages_equal_fixture() -> None:
    assert home_first_run_messages() == load_json(FIXTURES_DIR / "home_first_run.json")["messages"]


def test_area_match_ignores_case_and_surrounding_space() -> None:
    expected = [s["id"] for s in search_stays("Cloud 9", 3, 4500)]
    assert [s["id"] for s in search_stays("cLoUd 9", 3, 4500)] == expected
    assert [s["id"] for s in search_stays("  cloud 9 ", 3, 4500)] == expected


def test_area_match_is_exact_not_substring() -> None:
    assert search_stays("Cloud", 3, 10000) == []
    assert search_stays("Luna", 3, 10000) == []


def test_price_boundary_is_inclusive() -> None:
    assert [s["id"] for s in search_stays("Cloud 9", 1, 4200)][-1] == "tuason-point-pool-suites"
    assert "tuason-point-pool-suites" not in [s["id"] for s in search_stays("Cloud 9", 1, 4199)]
    assert [s["id"] for s in search_stays("General Luna", 1, 750)] == ["general-luna-surf-hostel"]
    assert search_stays("General Luna", 1, 749) == []


def test_at_most_four_results_cheapest_first() -> None:
    # Cloud 9 has 5 stays; the 7,800 villa is the one dropped.
    stays = search_stays("Cloud 9", 2, 10000)
    assert len(stays) == MAX_STAY_RESULTS
    assert "palm-villa-siargao" not in [s["id"] for s in stays]
    prices = [s["pricePerNight"] for s in stays]
    assert prices == sorted(prices)


def test_ties_sort_by_id(monkeypatch: pytest.MonkeyPatch) -> None:
    from siargao_mcp import surfaces

    fake = (
        {"id": "b", "area": "X", "pricePerNight": 1000},
        {"id": "a", "area": "X", "pricePerNight": 1000},
        {"id": "c", "area": "X", "pricePerNight": 900},
    )
    monkeypatch.setattr(surfaces, "_dataset", lambda: fake)
    assert [s["id"] for s in search_stays("x", 1, 5000)] == ["c", "a", "b"]


def test_nights_does_not_filter_but_reaches_the_surface() -> None:
    assert search_stays("Cloud 9", 1, 4500) == search_stays("Cloud 9", 14, 4500)
    messages, _ = build_stays_surface("Cloud 9", 7, 4500)
    assert _data(messages)["query"] == {"area": "Cloud 9", "nights": 7, "max_price": 4500}
    cards = [c for c in _components(messages) if c["component"] == "StayCard"]
    assert all(c["action"]["event"]["context"]["nights"] == 7 for c in cards)
    assert _data(messages)["hero"]["eyebrow"] == "7 nights, up to PHP 4,500 per night"


def test_slider_value_is_max_price() -> None:
    messages, _ = build_stays_surface("Pacifico", 2, 3000)
    slider = next(c for c in _components(messages) if c["component"] == "BudgetSlider")
    assert slider["value"] == {"path": "/query/max_price"}
    assert _data(messages)["query"]["max_price"] == 3000


@pytest.mark.parametrize(
    ("area", "nights", "max_price"),
    [
        ("Cloud 9", 3, 4500),
        ("Cloud 9", 1, 10000),
        ("general luna", 2, 2500),
        ("Pacifico", 1, 2500),
        ("Pilar", 4, 1800),
        ("Burgos", 5, 9000),
        ("Cloud 9", 1, 500),
        ("Mars", 2, 5000),
    ],
)
def test_every_surface_validates(area: str, nights: int, max_price: int) -> None:
    messages, stays = build_stays_surface(area, nights, max_price)
    assert validate_messages(messages) == []
    sdk_validate(messages)
    grid = [c for c in _components(messages) if c["id"] == "stays-grid"]
    if stays:
        assert grid[0]["children"] == [f"stay-{i + 1}" for i in range(len(stays))]
    else:
        assert grid == []
    assert EM_DASH not in json.dumps(messages, ensure_ascii=False)


def test_zero_results_surface_suggests_higher_budget() -> None:
    messages, stays = build_stays_surface("Cloud 9", 3, 1000)
    assert stays == []
    data = _data(messages)
    assert data["stays"] == []
    assert "1,600" in data["empty"]["body"]
    assert "higher" in data["hero"]["subtitle"]
    note = next(c for c in _components(messages) if c["id"] == "no-results")
    assert note["component"] == "LocalNote"
    assert note["tone"] == "heads_up"
    root = _components(messages)[0]
    assert root["children"] == ["hero", "price-slider", "no-results", "local-note"]


def test_unknown_area_lists_known_areas() -> None:
    messages, _ = build_stays_surface("Mars", 2, 5000)
    body = _data(messages)["empty"]["body"]
    for area in ("Cloud 9", "General Luna", "Pacifico", "Pilar", "Burgos"):
        assert area in body


def test_summary_mentions_totals_for_nights() -> None:
    _, stays = build_stays_surface("Cloud 9", 3, 4500)
    text = stays_summary("Cloud 9", 3, 4500, stays)
    assert text.startswith("4 stays near Cloud 9 for 3 nights, up to PHP 4,500 per night:")
    assert "PHP 4,800 for 3 nights" in text
    assert "Nothing matched" in stays_summary("Cloud 9", 3, 500, [])


def test_validation_catches_broken_surface() -> None:
    messages, _ = build_stays_surface("Cloud 9", 3, 4500)
    del _data(messages)["hero"]
    assert any("/hero/title" in e for e in validate_messages(messages))
    messages, _ = build_stays_surface("Cloud 9", 3, 4500)
    _components(messages)[0]["component"] = "Nope"
    assert validate_messages(messages)


def test_no_em_dashes_in_mcp_sources() -> None:
    for path in ROOT.rglob("*"):
        if ".venv" in path.parts or "__pycache__" in path.parts or not path.is_file():
            continue
        if path.suffix in {".py", ".json", ".md", ".sh", ".txt", ".toml"} or path.name in {"Dockerfile"}:
            assert EM_DASH not in path.read_text(encoding="utf-8"), path
