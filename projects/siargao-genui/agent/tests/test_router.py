from __future__ import annotations

import pytest
from conftest import FIXTURE_INTENTS, load_fixture

from siargao_agent.router import route


@pytest.mark.parametrize("intent", FIXTURE_INTENTS)
def test_fixture_prompt_routes_by_keywords(store, intent):
    decision = route(load_fixture(intent)["prompt"], store)
    assert decision.intent == intent
    assert decision.reason == "keywords"


def test_metadata_intent_wins_over_keywords(store):
    decision = route("Flights to Siargao under 8,000", store, requested_intent="surf_this_week")
    assert decision.intent == "surf_this_week"
    assert decision.reason == "metadata"


def test_unknown_metadata_intent_falls_back_to_keywords(store):
    decision = route("Where can I stay near Cloud 9?", store, requested_intent="no_such_intent")
    assert decision.intent == "stays_near_cloud9"
    assert decision.reason == "keywords"


@pytest.mark.parametrize(
    ("prompt", "intent"),
    [
        ("any cheap hotels in General Luna?", "stays_near_cloud9"),
        ("what are the airfares from Cebu", "flights_under_8000"),
        ("surf forecast for the weekend", "surf_this_week"),
        ("Going back to Siargao for a second trip", "returning_flexible"),
        ("make me an itinerary", "first_time_trip"),
        ("hello", "home_first_run"),
    ],
)
def test_keyword_rules(store, prompt, intent):
    assert route(prompt, store).intent == intent


@pytest.mark.parametrize("prompt", ["Best lechon near General Luna?", "What should I pack?", ""])
def test_unmatched_prompt_goes_to_model(store, prompt):
    decision = route(prompt, store)
    assert decision.intent is None
    assert decision.reason == "model"
