"""Builds the A2UI surfaces this server returns. No model calls, only templates."""

from __future__ import annotations

import copy
import json
from functools import cache
from typing import Any

from . import DATA_DIR, SURFACES_DIR, TEMPLATES_DIR

VERSION = "v0.9"
MAX_STAY_RESULTS = 4


def _load(path) -> Any:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


@cache
def _home_fixture() -> dict[str, Any]:
    return _load(SURFACES_DIR / "home_first_run.json")


@cache
def _stays_template() -> dict[str, Any]:
    return _load(TEMPLATES_DIR / "stays.json")


@cache
def _dataset() -> tuple[dict[str, Any], ...]:
    return tuple(_load(DATA_DIR / "stays.json")["stays"])


def home_first_run_messages() -> list[dict[str, Any]]:
    """The static home surface: the messages of the home_first_run fixture."""
    return copy.deepcopy(_home_fixture()["messages"])


def search_stays(area: str, nights: int, max_price: float) -> list[dict[str, Any]]:
    """The filter rule from fixtures/README.md.

    Case-insensitive exact area match, pricePerNight <= max_price, sorted by
    price ascending then id, at most 4 results. nights does not filter.
    """
    del nights
    wanted = area.strip().casefold()
    hits = [s for s in _dataset() if s["area"].casefold() == wanted and s["pricePerNight"] <= max_price]
    hits.sort(key=lambda s: (s["pricePerNight"], s["id"]))
    return [dict(s) for s in hits[:MAX_STAY_RESULTS]]


def known_areas() -> list[str]:
    seen: dict[str, str] = {}
    for s in _dataset():
        seen.setdefault(s["area"].casefold(), s["area"])
    return list(seen.values())


def _money(amount: float) -> str:
    return f"{amount:,.0f}" if float(amount).is_integer() else f"{amount:,.2f}"


def _plural(n: int, word: str) -> str:
    return f"{n} {word}" if n == 1 else f"{n} {word}s"


def _fill(value: Any, mapping: dict[str, str]) -> Any:
    """Replace {key} placeholders in every string inside value."""
    if isinstance(value, str):
        for key, sub in mapping.items():
            value = value.replace("{" + key + "}", sub)
        return value
    if isinstance(value, dict):
        return {k: _fill(v, mapping) for k, v in value.items()}
    if isinstance(value, list):
        return [_fill(v, mapping) for v in value]
    return value


def _stay_card(index: int, stay: dict[str, Any], nights: int) -> dict[str, Any]:
    card = _fill(_stays_template()["stayCard"], {"i": str(index), "n": str(index + 1)})
    card["action"]["event"]["context"] = {"stayId": stay["id"], "nights": nights}
    return card


def build_stays_surface(area: str, nights: int, max_price: int) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Fill the stays template. Returns (messages, stays)."""
    tpl = _stays_template()
    surface_id = tpl["surfaceId"]
    stays = search_stays(area, nights, max_price)

    canonical = {a.casefold(): a for a in known_areas()}
    area_key = area.strip().casefold()
    display_area = canonical.get(area_key, area.strip())
    words = {
        "area": display_area,
        "max_price": _money(max_price),
        "nights_label": _plural(nights, "night"),
        "count_label": _plural(len(stays), "stay"),
    }
    text = tpl["copy"]
    note = tpl["notes"].get(area_key, tpl["notes"]["default"])

    data: dict[str, Any] = {
        "query": {"area": area, "nights": nights, "max_price": max_price},
        "hero": {
            "eyebrow": _fill(text["eyebrow"], words),
            "title": _fill(text["title"], words),
            "subtitle": _fill(text["subtitle"], words),
        },
        "stays": stays,
        "note": dict(note),
    }

    components = copy.deepcopy(tpl["components"])
    if stays:
        out: list[dict[str, Any]] = []
        for comp in components:
            out.append(comp)
            if comp["id"] == "stays-grid":
                cards = [_stay_card(i, s, nights) for i, s in enumerate(stays)]
                comp["children"] = [c["id"] for c in cards]
                out += cards
        components = out
    else:
        empty = copy.deepcopy(tpl["emptyState"])
        components = [empty if c["id"] == "stays-grid" else c for c in components]
        root = components[0]
        root["children"] = [empty["id"] if c == "stays-grid" else c for c in root["children"]]
        in_area = sorted(s["pricePerNight"] for s in _dataset() if s["area"].casefold() == area_key)
        if in_area:
            body = _fill(text["emptyNoteBodyCheaper"], {**words, "cheapest": _money(in_area[0])})
        else:
            body = _fill(text["emptyNoteBodyUnknownArea"], {**words, "areas": ", ".join(known_areas())})
            data["note"] = dict(tpl["notes"]["default"])
        data["hero"]["title"] = _fill(text["emptyTitle"], words)
        data["hero"]["subtitle"] = _fill(text["emptySubtitle"], words)
        data["empty"] = {"title": _fill(text["emptyNoteTitle"], words), "body": body}

    messages = [
        {"version": VERSION, "createSurface": {"surfaceId": surface_id, "catalogId": tpl["catalogId"]}},
        {"version": VERSION, "updateComponents": {"surfaceId": surface_id, "components": components}},
        {"version": VERSION, "updateDataModel": {"surfaceId": surface_id, "path": "/", "value": data}},
    ]
    return messages, stays


def stays_summary(area: str, nights: int, max_price: int, stays: list[dict[str, Any]]) -> str:
    """A short plain text summary for the TextContent item next to the surface."""
    canonical = {a.casefold(): a for a in known_areas()}
    display_area = canonical.get(area.strip().casefold(), area.strip())
    head = f"{_plural(len(stays), 'stay')} near {display_area} for {_plural(nights, 'night')}, "
    head += f"up to PHP {_money(max_price)} per night"
    if not stays:
        return head + ". Nothing matched. Try a higher max price or another area."
    items = "; ".join(
        f"{s['name']}, PHP {_money(s['pricePerNight'])} per night "
        f"(PHP {_money(s['pricePerNight'] * nights)} for {_plural(nights, 'night')})"
        for s in stays
    )
    return f"{head}: {items}. Sample prices."
