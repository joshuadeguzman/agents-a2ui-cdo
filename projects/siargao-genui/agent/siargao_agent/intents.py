"""Small per-intent data functions.

Each function reads the prompt, changes draft.data (and the markdown in
draft.text to match), and leaves the components alone. When the prompt asks
for nothing different from the template default, the function changes nothing,
so the fixture prompt renders exactly the fixture.

The one exception is stays_near_cloud9: its StayCard buttons carry the stay id
and nights as literal event context, so after a new search the function writes
the new values into those literals. The component tree itself is unchanged.
"""

from __future__ import annotations

import json
import re
from collections.abc import Callable
from functools import cache
from typing import Any

from .config import DEFAULT_DATA_DIR
from .templates import Draft

# ---------------------------------------------------------------------------
# Prompt parsing helpers
# ---------------------------------------------------------------------------

_NUM = r"(?:php|p|₱)?\s*(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)\s*(k)?\b"
MIN_PRICE = 100
_CAP_WORDS = r"(?:under|below|less than|cheaper than|at most|max(?:imum)?|up to|no more than|budget(?: of)?|<=?)"


def _to_number(digits: str, k: str | None) -> int:
    value = float(digits.replace(",", ""))
    if k:
        value *= 1000
    return round(value)


def parse_amount_cap(prompt: str) -> int | None:
    """A price cap such as "under 8,000", "below 5k", "max_price=4500", "budget 3000"."""
    text = prompt.lower()
    m = re.search(r"max_price\s*=\s*(\d+)", text)
    if m:
        return int(m.group(1))
    for m in re.finditer(_CAP_WORDS + r"\s*(?:of\s*)?" + _NUM, text):
        value = _to_number(m.group(1), m.group(2))
        # Prices are at least 100; "up to 3 nights" is not a price.
        if value >= MIN_PRICE:
            return value
    return None


def parse_nights(prompt: str) -> int | None:
    text = prompt.lower()
    m = re.search(r"nights\s*=\s*(\d+)", text) or re.search(r"\b(\d{1,2})\s*nights?\b", text)
    return int(m.group(1)) if m else None


def parse_days(prompt: str) -> int | None:
    m = re.search(r"\b(\d{1,2})\s*-?\s*days?\b", prompt.lower())
    return int(m.group(1)) if m else None


def peso(amount: float) -> str:
    return f"PHP {int(amount):,}"


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))


# ---------------------------------------------------------------------------
# first_time_trip
# ---------------------------------------------------------------------------

FIRST_TRIP_DEFAULT = (4, "mid")
# Per person: nightly share of the room, food per day, and the stay label.
FIRST_TRIP_TIERS = {
    "low": (750, 600, "hostel dorm bed"),
    "mid": (2500, 1000, "half of a PHP 5,000 room"),
    "high": (6000, 2000, "half of a PHP 12,000 villa"),
}
# Budget lines that belong to a day of the plan; they go when the day goes.
FIRST_TRIP_DAY_ITEMS = {"Island hopping tour": 3, "Sugba Lagoon boat share and fees": 4}


def parse_budget_tier(prompt: str) -> str | None:
    text = prompt.lower()
    if re.search(r"\b(cheap|low|tight|backpack\w*|shoestring)\b", text):
        return "low"
    if re.search(r"\b(luxury|high|splurge|premium|fancy)\b", text):
        return "high"
    if re.search(r"\b(mid|medium|moderate)\b", text):
        return "mid"
    return None


def first_time_trip_text(draft: Draft) -> str:
    data = draft.data
    trip = data["trip"]
    paragraphs = draft.template.text.split("\n\n")
    intro = paragraphs[1]
    tail = draft.template.text[draft.template.text.index("**Local tip:**") :]
    out = [f"## {trip['title']} ({trip['eyebrow']})", intro]
    for day in data["days"]:
        lines = [f"**Day {day['day']}: {day['title']}**"]
        for item in day["items"]:
            note = f" ({item['note']})" if item.get("note") else ""
            lines.append(f"- {item['time']}: {item['activity']}{note}")
        out.append("\n".join(lines))
    budget = data["budget"]
    lines = [f"**{budget['title']}**"]
    lines += [f"- {i['label']}: {peso(i['amount'])}" for i in budget["items"]]
    lines.append(f"- **{budget['totalLabel']}: {peso(sum(i['amount'] for i in budget['items']))}**")
    out.append("\n".join(lines))
    out.append(tail)
    return "\n\n".join(out)


def first_time_trip(draft: Draft) -> None:
    days = parse_days(draft.prompt)
    days = _clamp(days, 2, 4) if days else FIRST_TRIP_DEFAULT[0]
    tier = parse_budget_tier(draft.prompt) or FIRST_TRIP_DEFAULT[1]
    if (days, tier) == FIRST_TRIP_DEFAULT:
        return
    data = draft.data
    data["days"] = data["days"][:days]
    data["trip"]["eyebrow"] = f"{days} days, {tier} budget"
    nightly, food, stay_label = FIRST_TRIP_TIERS[tier]
    items = []
    for item in data["budget"]["items"]:
        label = item["label"]
        if FIRST_TRIP_DAY_ITEMS.get(label, 0) > days:
            continue
        if label.startswith("Stay,"):
            item = {"label": f"Stay, {days - 1} nights ({stay_label})", "amount": nightly * (days - 1)}
        elif label.startswith("Food and drinks"):
            item = {"label": f"Food and drinks, {days} days", "amount": food * days}
        items.append(item)
    data["budget"]["items"] = items
    draft.text = first_time_trip_text(draft)
    draft.notes.append(f"days={days} tier={tier}")


# ---------------------------------------------------------------------------
# flights_under_8000
# ---------------------------------------------------------------------------

FLIGHTS_DEFAULT_CAP = 8000
FLIGHTS_SLIDER = (2000, 12000)


def flights_text(draft: Draft, cap: int) -> str:
    flights = draft.data["flights"]
    tmpl = draft.template.text
    intro = tmpl.split("\n\n")[1]
    tail = tmpl[tmpl.index("**What the") :]
    out = [f"## {draft.data['hero']['title']}", intro]
    if flights:
        out.append("\n".join(f"- **{f['name']}** ({f['route']}): {peso(f['fare'])}. {f['note']}." for f in flights))
    else:
        out.append(draft.data["hero"]["subtitle"])
    out.append(tail)
    return "\n\n".join(out)


def flights_under_8000(draft: Draft) -> None:
    cap = parse_amount_cap(draft.prompt)
    if cap is None or cap == FLIGHTS_DEFAULT_CAP:
        return
    data = draft.data
    all_flights = data["flights"]
    # Fares are sorted cheapest first, so the filter keeps a prefix and the
    # literal flight ids on the remaining cards stay correct.
    data["flights"] = [f for f in all_flights if f["fare"] <= cap]
    data["search"]["maxFare"] = _clamp(cap, *FLIGHTS_SLIDER)
    data["hero"]["title"] = f"Flights to Siargao under {peso(cap)}"
    if not data["flights"]:
        cheapest = min(all_flights, key=lambda f: f["fare"])
        data["hero"]["subtitle"] = (
            f"No sample fares at or under {peso(cap)}. The cheapest is {peso(cheapest['fare'])} "
            f"from {cheapest['origin']}."
        )
    draft.text = flights_text(draft, cap)
    draft.notes.append(f"maxFare={cap} results={len(data['flights'])}")


# ---------------------------------------------------------------------------
# stays_near_cloud9
# ---------------------------------------------------------------------------

STAYS_AREAS = ["Cloud 9", "General Luna", "Pacifico", "Pilar", "Burgos"]
STAYS_MAX_RESULTS = 4
STAYS_SLIDER = (500, 10000)


@cache
def stays_dataset() -> list[dict[str, Any]]:
    path = DEFAULT_DATA_DIR / "stays_dataset.json"
    return json.loads(path.read_text(encoding="utf-8"))["stays"]


def search_stays(area: str, nights: int, max_price: float) -> list[dict[str, Any]]:
    """The search_stays rule from fixtures/README.md (shared with the MCP tool)."""
    del nights  # Carried into the surface, not used to filter.
    hits = [s for s in stays_dataset() if s["area"].casefold() == area.casefold() and s["pricePerNight"] <= max_price]
    hits.sort(key=lambda s: (s["pricePerNight"], s["id"]))
    return hits[:STAYS_MAX_RESULTS]


def parse_area(prompt: str) -> str | None:
    text = prompt.lower()
    m = re.search(r"area\s*=\s*[\"']([^\"']+)[\"']", text)
    if m:
        text = m.group(1)
    for area in STAYS_AREAS:
        pattern = re.escape(area.lower()).replace(r"\ ", r"\s*")
        if re.search(pattern, text):
            return area
    if re.search(r"\bcloud\s*nine\b", text):
        return "Cloud 9"
    return None


def stays_text(draft: Draft) -> str:
    data = draft.data
    q = data["query"]
    n = q["nights"]
    night_word = "night" if n == 1 else "nights"
    tmpl = draft.template.text
    tail = tmpl[tmpl.index("**Local tip:**") :]
    out = [
        f"## {data['hero']['title']}",
        f"{n} {night_word}, up to {peso(q['max_price'])} per night. Sample prices, cheapest first.",
    ]
    if data["stays"]:
        out.append(
            "\n".join(
                f"- **{s['name']}** ({s['area']}, rated {s['rating']}): {peso(s['pricePerNight'])} per night, "
                f"{peso(s['pricePerNight'] * n)} for {n} {night_word}. {s['note']}."
                for s in data["stays"]
            )
        )
    else:
        out.append(data["hero"]["subtitle"])
    out.append(tail)
    return "\n\n".join(out)


def stays_near_cloud9(draft: Draft) -> None:
    data = draft.data
    default = dict(data["query"])
    query = {
        "area": parse_area(draft.prompt) or default["area"],
        "nights": parse_nights(draft.prompt) or default["nights"],
        "max_price": parse_amount_cap(draft.prompt) or default["max_price"],
    }
    query["nights"] = _clamp(query["nights"], 1, 30)
    if query == default:
        return
    stays = search_stays(query["area"], query["nights"], query["max_price"])
    data["query"] = {**query, "max_price": _clamp(query["max_price"], *STAYS_SLIDER)}
    data["stays"] = stays
    n = query["nights"]
    night_word = "night" if n == 1 else "nights"
    data["hero"]["eyebrow"] = f"{n} {night_word}, up to {peso(query['max_price'])} per night"
    if stays:
        data["hero"]["title"] = f"{len(stays)} {'stay' if len(stays) == 1 else 'stays'} near {query['area']}"
    else:
        data["hero"]["title"] = f"No stays near {query['area']} at this price"
        data["hero"]["subtitle"] = "Try a higher price per night or another area."
    # Keep the literal event context on each card in step with the new list.
    by_id = {c.get("id"): c for c in draft.components}
    for i, stay in enumerate(stays):
        card = by_id.get(f"stay-{i + 1}")
        if card is None:
            continue
        ctx = card.get("action", {}).get("event", {}).get("context")
        if isinstance(ctx, dict):
            ctx["stayId"] = stay["id"]
            ctx["nights"] = n
    draft.text = stays_text(draft)
    draft.notes.append(f"query={query} results={len(stays)}")


# ---------------------------------------------------------------------------
# returning_flexible
# ---------------------------------------------------------------------------

MONTHS = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
]


def _join_or(items: list[str]) -> str:
    if len(items) <= 1:
        return "".join(items)
    return ", ".join(items[:-1]) + " or " + items[-1]


def returning_setup_line(prefs: dict[str, Any]) -> str:
    length = (prefs.get("length") or ["1 week"])[0]
    months = _join_or(prefs.get("months") or [])
    when = f" in {months}" if months else ""
    return f"**Suggested setup:** {length}{when}, stays up to {peso(prefs['maxPerNight'])} per night (sample price)."


def returning_flexible(draft: Draft) -> None:
    data = draft.data
    prefs = data["prefs"]
    before = json.dumps(prefs, sort_keys=True)
    text = draft.prompt.lower()

    months = [m for m in data["when"]["options"] if re.search(rf"\b{m.lower()}\b", text)]
    if months:
        prefs["months"] = months
    if re.search(r"\b2\s*weeks?\b|\btwo weeks?\b|\bfortnight\b", text):
        prefs["length"] = ["2 weeks"]
    elif re.search(r"\b(1|one|a)\s*week\b", text):
        prefs["length"] = ["1 week"]
    elif re.search(r"\b(4|four)\s*nights?\b|\blong weekend\b", text):
        prefs["length"] = ["4 nights"]
    cap = parse_amount_cap(draft.prompt)
    if cap is not None:
        # Snap to the slider: 1,000 to 10,000 in steps of 500.
        prefs["maxPerNight"] = _clamp(round(cap / 500.0) * 500, 1000, 10000)

    if json.dumps(prefs, sort_keys=True) == before:
        return
    draft.text = re.sub(r"\*\*Suggested setup:\*\*[^\n]*", returning_setup_line(prefs), draft.text, count=1)
    draft.notes.append(f"prefs={prefs}")


# ---------------------------------------------------------------------------
# surf_this_week
# ---------------------------------------------------------------------------


def surf_this_week(draft: Draft) -> None:
    text = draft.prompt.lower()
    for level in draft.data["levels"]["options"]:
        if re.search(rf"\b{level.lower()}\b", text):
            if draft.data["prefs"]["level"] != [level]:
                draft.data["prefs"]["level"] = [level]
                draft.notes.append(f"level={level}")
            return


DATA_FUNCTIONS: dict[str, Callable[[Draft], None]] = {
    "first_time_trip": first_time_trip,
    "flights_under_8000": flights_under_8000,
    "stays_near_cloud9": stays_near_cloud9,
    "returning_flexible": returning_flexible,
    "surf_this_week": surf_this_week,
}
