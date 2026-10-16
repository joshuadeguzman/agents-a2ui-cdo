"""Pick a template for a prompt, or hand it to the model.

Order: an explicit metadata.siargao.intent wins, then keyword rules, then the
model. Built-in intents have regex rules below. Templates added with
scripts/freeze.py bring their own "keywords" list (plain substrings, case
insensitive), checked after the built-in rules.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from .templates import TemplateStore

# (intent, pattern). First match wins, so the most specific rules go first.
KEYWORD_RULES: list[tuple[str, re.Pattern[str]]] = [
    ("home_first_run", re.compile(r"a2ui://home|^\s*(home|start|get started|hi|hello)\s*[.!?]*\s*$", re.I)),
    (
        "stays_near_cloud9",
        re.compile(
            r"search_stays|\bstays?\b|\bhotels?\b|\bhostels?\b|"
            r"\baccommodations?\b|\bwhere (to|should i|can i) (stay|sleep)\b|"
            r"\bplace to stay\b|\bvillas?\b|\bresorts?\b|\bhomestays?\b|\bbungalows?\b",
            re.I,
        ),
    ),
    (
        "flights_under_8000",
        re.compile(
            r"\bflights?\b|\bfares?\b|\bairfares?\b|\bplane tickets?\b|\bfly(ing)? (to|from)\b|"
            r"\bairlines?\b",
            re.I,
        ),
    ),
    (
        "surf_this_week",
        re.compile(
            r"\bsurf\b.*\b(week|today|tomorrow|weekend|forecast|report|conditions?|swell|waves?)\b|"
            r"\bhow'?s the surf\b|\bsurf (report|forecast|conditions?)\b|\bswell\b|"
            r"\bwaves? (this|today|tomorrow)\b",
            re.I,
        ),
    ),
    (
        "returning_flexible",
        re.compile(
            r"\b(been|went) to siargao\b|\bbeen there\b|\breturning\b|\bcome back\b|"
            r"\bgo back\b|\bsecond (time|trip)\b|\bflexible\b|\bagain\b",
            re.I,
        ),
    ),
    (
        "first_time_trip",
        re.compile(
            r"\bfirst[- ](time|trip|visit)\b|\bplan (my|a|our) (\w+ )?trip\b|\bitinerary\b|"
            r"\b\d+\s*-?\s*days?\b.*\bsiargao\b|\bsiargao\b.*\b\d+\s*-?\s*days?\b",
            re.I,
        ),
    ),
]


@dataclass(frozen=True)
class Route:
    intent: str | None  # None means the model handles it.
    reason: str  # "metadata", "keywords", "template-keywords" or "model"


def route(prompt: str, store: TemplateStore, requested_intent: str | None = None) -> Route:
    if requested_intent and requested_intent in store:
        return Route(requested_intent, "metadata")
    text = prompt or ""
    for intent, pattern in KEYWORD_RULES:
        if intent in store and pattern.search(text):
            return Route(intent, "keywords")
    lowered = text.lower()
    for intent in store.intents:
        tpl = store.get(intent)
        if tpl and any(k.lower() in lowered for k in tpl.keywords):
            return Route(intent, "template-keywords")
    return Route(None, "model")
