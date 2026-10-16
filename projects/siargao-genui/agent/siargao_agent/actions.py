"""Short text confirmations for user actions. No model call."""

from __future__ import annotations

import json
from typing import Any

from .config import DEFAULT_DATA_DIR
from .intents import peso, stays_dataset


def _fmt(value: Any) -> str:
    if isinstance(value, list):
        items = [str(v) for v in value]
        if len(items) <= 1:
            return "".join(items)
        return ", ".join(items[:-1]) + " and " + items[-1]
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def _flight(flight_id: str) -> dict[str, Any] | None:
    path = DEFAULT_DATA_DIR / "flights_under_8000.json"
    try:
        flights = json.loads(path.read_text(encoding="utf-8"))["flights"]
    except (OSError, KeyError, ValueError):
        return None
    return next((f for f in flights if f.get("id") == flight_id), None)


def confirm_action(action: dict[str, Any]) -> str:
    name = str(action.get("name") or "action")
    ctx = action.get("context") if isinstance(action.get("context"), dict) else {}

    if name == "choose_stay":
        stay = next((s for s in stays_dataset() if s["id"] == ctx.get("stayId")), None)
        label = stay["name"] if stay else "your stay"
        nights = ctx.get("nights")
        if isinstance(nights, int | float) and nights > 0:
            n = int(nights)
            return f"Saved {label} for {n} {'night' if n == 1 else 'nights'}."
        return f"Saved {label}."
    if name == "choose_flight":
        flight = _flight(str(ctx.get("flightId")))
        if flight:
            return f"Saved the {flight['name']} flight at {peso(flight['fare'])} one way (sample fare)."
        return "Saved that flight."
    if name == "book_plan":
        days = ctx.get("days")
        days_txt = f"{_fmt(days)} day " if days else ""
        return f"Saved your {days_txt}Siargao plan. Booking is not live in this demo."
    if name == "refine_plan":
        change = ctx.get("change")
        if change == "cheaper":
            return "Got it, a cheaper plan. Try asking for a low budget first trip."
        if change == "more_surf":
            return "Got it, more surf time. I will add another morning session at Jacking Horse."
        return "Got it, I will adjust the plan."
    if name == "plan_flexible_trip":
        parts = []
        if ctx.get("length"):
            parts.append(_fmt(ctx["length"]))
        if ctx.get("months"):
            parts.append(f"in {_fmt(ctx['months'])}")
        if ctx.get("maxPerNight"):
            parts.append(f"with stays up to {peso(float(ctx['maxPerNight']))} per night")
        detail = " ".join(parts) if parts else "your dates"
        return f"Looking for {detail}. Sample prices only in this demo."
    if name == "more_spots":
        return "More spots coming up. Ask about Burgos, Pacifico or the Sohoton cove day trip."
    if name == "book_surf_lesson":
        level = _fmt(ctx.get("level")) if ctx.get("level") else "a"
        spot = ctx.get("spot") or "Jacking Horse"
        return f"Saved a {level.lower()} surf lesson at {spot}."
    if name == "find_board_rental":
        area = ctx.get("area") or "Cloud 9"
        return f"Board rentals near {area} start around PHP 500 a day (sample price)."
    return f"Got it: {name.replace('_', ' ')}."
