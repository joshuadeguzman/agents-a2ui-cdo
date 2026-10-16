from __future__ import annotations

import pytest
from conftest import FIXTURE_INTENTS, load_fixture

from siargao_agent.intents import (
    first_time_trip_text,
    flights_text,
    parse_amount_cap,
    search_stays,
    stays_text,
)
from siargao_agent.templates import Draft
from siargao_agent.validation import validate_messages


def test_every_fixture_intent_has_a_template(store):
    # Frozen templates (scripts/freeze.py) may add intents beyond the fixtures.
    assert set(FIXTURE_INTENTS) <= set(store.intents)


def test_every_template_validates(store):
    for intent in store.intents:
        rendered = store.render(intent, "")
        assert validate_messages(rendered.messages, intent) == [], intent


@pytest.mark.parametrize("intent", FIXTURE_INTENTS)
def test_template_reproduces_fixture(store, intent):
    fixture = load_fixture(intent)
    rendered = store.render(intent, fixture["prompt"])
    assert rendered.messages == fixture["messages"]
    assert rendered.text == fixture["text"]
    assert validate_messages(rendered.messages, surface_id=intent) == []


@pytest.mark.parametrize(
    ("intent", "builder"),
    [
        ("first_time_trip", first_time_trip_text),
        ("flights_under_8000", lambda d: flights_text(d, 8000)),
        ("stays_near_cloud9", stays_text),
    ],
)
def test_text_builders_reproduce_default_text(store, intent, builder):
    tpl = store.get(intent)
    draft = Draft(intent, "", tpl.data, tpl.text, tpl.components, tpl)
    assert builder(draft) == tpl.text


def _data(rendered):
    return rendered.messages[2]["updateDataModel"]["value"]


def _component_ids(rendered):
    return [c["id"] for c in rendered.messages[1]["updateComponents"]["components"]]


def test_flights_cap_filters_and_prunes_cards(store):
    rendered = store.render("flights_under_8000", "Cheap flights under 5k please")
    data = _data(rendered)
    assert [f["fare"] for f in data["flights"]] == [2980, 3650, 4890]
    assert data["search"]["maxFare"] == 5000
    ids = _component_ids(rendered)
    assert "flight-3" in ids and "flight-4" not in ids and "flight-5" not in ids
    assert "PHP 5,000" in rendered.text and "5,420" not in rendered.text
    assert validate_messages(rendered.messages, "flights_under_8000") == []


def test_flights_cap_below_cheapest_is_still_valid(store):
    rendered = store.render("flights_under_8000", "flights under 1,000")
    assert _data(rendered)["flights"] == []
    assert validate_messages(rendered.messages, "flights_under_8000") == []


def test_stays_new_search_updates_cards_and_context(store):
    rendered = store.render("stays_near_cloud9", "stays in General Luna for 2 nights under 3000")
    data = _data(rendered)
    assert data["query"] == {"area": "General Luna", "nights": 2, "max_price": 3000}
    assert data["stays"] == search_stays("General Luna", 2, 3000)
    cards = {c["id"]: c for c in rendered.messages[1]["updateComponents"]["components"]}
    assert cards["stay-1"]["action"]["event"]["context"] == {"stayId": "general-luna-surf-hostel", "nights": 2}
    assert "stay-3" not in cards
    assert validate_messages(rendered.messages, "stays_near_cloud9") == []


def test_first_trip_days_and_budget(store):
    rendered = store.render("first_time_trip", "first trip to Siargao, 3 days, cheap")
    data = _data(rendered)
    assert len(data["days"]) == 3
    assert data["trip"]["eyebrow"] == "3 days, low budget"
    labels = [i["label"] for i in data["budget"]["items"]]
    assert "Sugba Lagoon boat share and fees" not in labels
    assert "day-4" not in _component_ids(rendered)
    assert "(3 days, low budget)" in rendered.text
    assert validate_messages(rendered.messages, "first_time_trip") == []


def test_returning_prefs_from_prompt(store):
    rendered = store.render("returning_flexible", "been to Siargao, flexible, June or July, 2 weeks, budget 2,000")
    prefs = _data(rendered)["prefs"]
    assert prefs == {"months": ["June", "July"], "length": ["2 weeks"], "maxPerNight": 2000}
    assert "**Suggested setup:** 2 weeks in June or July, stays up to PHP 2,000 per night" in rendered.text


def test_surf_level_from_prompt(store):
    rendered = store.render("surf_this_week", "surf this week? I'm advanced")
    assert _data(rendered)["prefs"]["level"] == ["Advanced"]


@pytest.mark.parametrize(
    ("prompt", "cap"),
    [
        ("Flights to Siargao under 8,000", 8000),
        ("below 5k", 5000),
        ("max PHP 3500", 3500),
        ('search_stays(area="Cloud 9", nights=3, max_price=4500)', 4500),
        ("stay up to 3 nights", None),
        ("plan my trip", None),
    ],
)
def test_parse_amount_cap(prompt, cap):
    assert parse_amount_cap(prompt) == cap
