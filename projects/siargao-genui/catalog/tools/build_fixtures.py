# ruff: noqa: E501
"""Write the recorded Siargao fixtures into ../fixtures.

Usage: .venv/bin/python tools/build_fixtures.py [OUT_DIR]
Run tools/validate_fixtures.py afterwards.
"""

import json
import sys
from pathlib import Path

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "fixtures"
CATALOG_ID = "https://siargao-genui.example/catalogs/v1/catalog.json"


def b(path):
    return {"path": path}


def c(cid, component, **props):
    return {"id": cid, "component": component, **props}


def ev(name, **context):
    return {"event": {"name": name, "context": context}}


def fixture(intent, title, prompt, path, text, components, data):
    return {
        "intent": intent,
        "title": title,
        "prompt": prompt,
        "path": path,
        "source": "template",
        "modelCalls": 0,
        "text": text,
        "messages": [
            {"version": "v0.9", "createSurface": {"surfaceId": intent, "catalogId": CATALOG_ID}},
            {"version": "v0.9", "updateComponents": {"surfaceId": intent, "components": components}},
            {"version": "v0.9", "updateDataModel": {"surfaceId": intent, "path": "/", "value": data}},
        ],
    }


def write(name, obj):
    (OUT / f"{name}.json").write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")


def php(n):
    return f"PHP {n:,}"


# ---------------------------------------------------------------- stays dataset
STAYS = [
    {
        "id": "boardwalk-homestay",
        "name": "Boardwalk Family Homestay",
        "area": "Cloud 9",
        "pricePerNight": 1600,
        "rating": 4.4,
        "note": "Family run rooms with breakfast, 6 min walk to the Cloud 9 boardwalk",
        "image": "stay-boardwalk-homestay",
    },
    {
        "id": "cloud9-surf-cabins",
        "name": "Cloud 9 Surf Cabins",
        "area": "Cloud 9",
        "pricePerNight": 2800,
        "rating": 4.6,
        "note": "Thatched cabins with board racks, 3 min walk to the break",
        "image": "stay-cloud9-surf-cabins",
    },
    {
        "id": "catangnan-garden-bungalows",
        "name": "Catangnan Garden Bungalows",
        "area": "Cloud 9",
        "pricePerNight": 3400,
        "rating": 4.5,
        "note": "Quiet garden bungalows on the Cloud 9 road, aircon and fast wifi",
        "image": "stay-catangnan-bungalows",
    },
    {
        "id": "tuason-point-pool-suites",
        "name": "Tuason Point Pool Suites",
        "area": "Cloud 9",
        "pricePerNight": 4200,
        "rating": 4.7,
        "note": "Small pool, ocean view rooms, 8 min walk to Cloud 9",
        "image": "stay-palm-villa",
    },
    {
        "id": "palm-villa-siargao",
        "name": "Palm Villa Siargao",
        "area": "Cloud 9",
        "pricePerNight": 7800,
        "rating": 4.8,
        "note": "Private villa for up to 4 with its own pool",
        "image": "stay-palm-villa",
    },
    {
        "id": "general-luna-surf-hostel",
        "name": "General Luna Surf Hostel",
        "area": "General Luna",
        "pricePerNight": 750,
        "rating": 4.3,
        "note": "Dorm beds, social nights, on Tourism Road",
        "image": "stay-general-luna-hostel",
    },
    {
        "id": "tourism-road-studios",
        "name": "Tourism Road Studios",
        "area": "General Luna",
        "pricePerNight": 2200,
        "rating": 4.2,
        "note": "Studios with kitchenettes, walk to cafes and the night market",
        "image": "stay-boardwalk-homestay",
    },
    {
        "id": "pacifico-surf-camp",
        "name": "Pacifico Surf Camp",
        "area": "Pacifico",
        "pricePerNight": 2500,
        "rating": 4.6,
        "note": "Beachfront huts on the quiet north east coast, uncrowded waves",
        "image": "stay-pacifico-surf-camp",
    },
    {
        "id": "magpupungko-beach-cottages",
        "name": "Magpupungko Beach Cottages",
        "area": "Pilar",
        "pricePerNight": 1800,
        "rating": 4.3,
        "note": "Simple cottages 5 min from the Magpupungko rock pools",
        "image": "stay-catangnan-bungalows",
    },
    {
        "id": "burgos-beach-lodge",
        "name": "Burgos Beach Lodge",
        "area": "Burgos",
        "pricePerNight": 2000,
        "rating": 4.4,
        "note": "Laid back lodge in the far north, near Alegria beach",
        "image": "stay-pacifico-surf-camp",
    },
]


def search_stays(area, nights, max_price):
    hits = [s for s in STAYS if s["area"].casefold() == area.casefold() and s["pricePerNight"] <= max_price]
    hits.sort(key=lambda s: (s["pricePerNight"], s["id"]))
    return hits[:4]


write(
    "stays_dataset",
    {
        "description": "Sample stays for the search_stays MCP tool. Sample prices in PHP per night, not live data. See fixtures/README.md for the filter rule.",
        "currency": "PHP",
        "stays": STAYS,
    },
)

# ---------------------------------------------------------------- first_time_trip
days = [
    {
        "day": 1,
        "title": "Land and settle in General Luna",
        "image": "siargao-flight",
        "items": [
            {
                "time": "10:30",
                "activity": "Land at Sayak Airport (IAO), Del Carmen",
                "note": "Direct flights from Manila, Cebu and Clark",
            },
            {
                "time": "11:15",
                "activity": "Shared van to General Luna",
                "note": "About 1 hour, around PHP 350 per person",
            },
            {"time": "14:00", "activity": "Check in near Cloud 9"},
            {"time": "17:30", "activity": "Sunset on the Cloud 9 boardwalk"},
            {"time": "19:30", "activity": "Dinner on Tourism Road"},
        ],
    },
    {
        "day": 2,
        "title": "Surf lesson and the Maasin river",
        "image": "cloud-9-boardwalk",
        "items": [
            {
                "time": "07:00",
                "activity": "Beginner surf lesson at Jacking Horse",
                "note": "About PHP 1,500 for 1.5 hours with board and coach",
            },
            {"time": "12:00", "activity": "Lunch and a nap, it gets hot"},
            {
                "time": "14:30",
                "activity": "Scooter to the Maasin river rope swing",
                "note": "Scooter rental about PHP 500 per day",
            },
            {"time": "19:00", "activity": "Dinner and live music in General Luna"},
        ],
    },
    {
        "day": 3,
        "title": "Island hopping: Naked, Daku, Guyam",
        "image": "guyam-island",
        "items": [
            {
                "time": "08:00",
                "activity": "Boat from the General Luna port",
                "note": "Shared tour about PHP 1,500 per person with lunch",
            },
            {"time": "08:30", "activity": "Naked Island sandbar"},
            {"time": "11:00", "activity": "Daku Island, grilled seafood lunch"},
            {"time": "14:00", "activity": "Swim and snorkel at Guyam Island"},
            {"time": "16:00", "activity": "Back in town, free evening"},
        ],
    },
    {
        "day": 4,
        "title": "Sugba Lagoon, then fly home",
        "image": "sugba-lagoon",
        "items": [
            {"time": "06:30", "activity": "Van to Del Carmen", "note": "Leave bags in the van or at the port"},
            {
                "time": "07:30",
                "activity": "Boat to Sugba Lagoon, paddle board and swim",
                "note": "About PHP 1,200 per person for boat share and fees",
            },
            {"time": "12:00", "activity": "Lunch in Del Carmen"},
            {"time": "13:30", "activity": "Sayak Airport, 10 min away", "note": "Afternoon flight out"},
        ],
    },
]
budget_items = [
    {"label": "Return flight from Manila", "amount": 7500},
    {"label": "Stay, 3 nights (half of a PHP 5,000 room)", "amount": 7500},
    {"label": "Airport vans, both ways", "amount": 700},
    {"label": "Surf lesson", "amount": 1500},
    {"label": "Island hopping tour", "amount": 1500},
    {"label": "Sugba Lagoon boat share and fees", "amount": 1200},
    {"label": "Scooter rental, 2 days", "amount": 1000},
    {"label": "Food and drinks, 4 days", "amount": 4000},
]
total = sum(i["amount"] for i in budget_items)

ftt_components = [
    c(
        "root",
        "Stack",
        children=["hero", "days-heading", "days-grid", "budget", "local-note", "next-actions"],
        gap="large",
    ),
    c(
        "hero",
        "Heading",
        eyebrow=b("/trip/eyebrow"),
        title=b("/trip/title"),
        subtitle=b("/trip/subtitle"),
        image=b("/trip/image"),
    ),
    c("days-heading", "Heading", title=b("/daysHeading")),
    c("days-grid", "FlexGrid", children=["day-1", "day-2", "day-3", "day-4"], minItemWidth=280),
]
for i in range(4):
    ftt_components.append(
        c(
            f"day-{i + 1}",
            "ItineraryDay",
            day=b(f"/days/{i}/day"),
            title=b(f"/days/{i}/title"),
            items=b(f"/days/{i}/items"),
            image=b(f"/days/{i}/image"),
        )
    )
ftt_components += [
    c(
        "budget",
        "CostBreakdown",
        title=b("/budget/title"),
        currency=b("/budget/currency"),
        items=b("/budget/items"),
        totalLabel=b("/budget/totalLabel"),
    ),
    c("local-note", "LocalNote", title=b("/note/title"), body=b("/note/body"), tone="local", author=b("/note/author")),
    c(
        "next-actions",
        "Actions",
        buttons=[
            {
                "label": "Book this plan",
                "style": "primary",
                "action": ev("book_plan", intent="first_time_trip", days=4),
            },
            {
                "label": "Make it cheaper",
                "style": "secondary",
                "action": ev("refine_plan", intent="first_time_trip", change="cheaper"),
            },
            {
                "label": "Add a surf day",
                "style": "text",
                "action": ev("refine_plan", intent="first_time_trip", change="more_surf"),
            },
        ],
    ),
]
ftt_data = {
    "trip": {
        "eyebrow": "4 days, mid budget",
        "title": "Your first Siargao trip",
        "subtitle": "Surf, islands and lagoons, based in General Luna near Cloud 9.",
        "image": "cloud-9-boardwalk",
    },
    "daysHeading": "Day by day",
    "days": days,
    "budget": {
        "title": "Estimated cost per person (sample prices)",
        "currency": "PHP",
        "items": budget_items,
        "totalLabel": "Estimated total",
    },
    "note": {
        "title": "Bring cash and go early",
        "body": "ATMs in General Luna often run dry on weekends and many small places take cash only. Walk the Cloud 9 boardwalk at sunrise, before the crowds and the heat.",
        "author": "From a Siargao local",
    },
}


def day_md(d):
    lines = [f"**Day {d['day']}: {d['title']}**"]
    for it in d["items"]:
        note = f" ({it['note']})" if it.get("note") else ""
        lines.append(f"- {it['time']}: {it['activity']}{note}")
    return "\n".join(lines)


ftt_text = "\n\n".join(
    [
        "## Your first Siargao trip (4 days, mid budget)",
        "Base yourself in General Luna near Cloud 9. You get surf, island hopping and Sugba Lagoon without long transfers.",
        *[day_md(d) for d in days],
        "**Estimated cost per person (sample prices)**\n"
        + "\n".join(f"- {i['label']}: {php(i['amount'])}" for i in budget_items)
        + f"\n- **Estimated total: {php(total)}**",
        "**Local tip:** bring cash. ATMs in General Luna often run dry on weekends and many small places take cash only. Walk the Cloud 9 boardwalk at sunrise, before the crowds and the heat.",
        "Want me to book this plan, make it cheaper, or add another surf day?",
    ]
)
write(
    "first_time_trip",
    fixture(
        "first_time_trip",
        "First-time Siargao trip",
        "Plan my first trip to Siargao, 4 days, mid budget",
        "a2a",
        ftt_text,
        ftt_components,
        ftt_data,
    ),
)

# ---------------------------------------------------------------- returning_flexible
spots = [
    {
        "eyebrow": "North east coast",
        "title": "Pacifico",
        "subtitle": "Long quiet beach and uncrowded waves. Stay two nights instead of a day trip.",
        "image": "pacifico-beach",
    },
    {
        "eyebrow": "Pilar, low tide only",
        "title": "Magpupungko rock pools",
        "subtitle": "Go on a weekday morning at low tide. Check the tide table the night before.",
        "image": "magpupungko-pools",
    },
    {
        "eyebrow": "Del Carmen",
        "title": "Sugba Lagoon by paddle board",
        "subtitle": "Skip the jump platform crowd and paddle into the mangroves early.",
        "image": "sugba-lagoon",
    },
]
rf_components = [
    c(
        "root",
        "Stack",
        children=[
            "hero",
            "when-chips",
            "length-chips",
            "budget-slider",
            "spots-heading",
            "spots-grid",
            "local-note",
            "next-actions",
        ],
        gap="medium",
    ),
    c("hero", "Heading", eyebrow=b("/hero/eyebrow"), title=b("/hero/title"), subtitle=b("/hero/subtitle")),
    c(
        "when-chips",
        "ChipRow",
        label=b("/when/label"),
        options=b("/when/options"),
        selected=b("/prefs/months"),
        multiSelect=True,
    ),
    c(
        "length-chips",
        "ChipRow",
        label=b("/length/label"),
        options=b("/length/options"),
        selected=b("/prefs/length"),
        multiSelect=False,
    ),
    c(
        "budget-slider",
        "BudgetSlider",
        label=b("/budgetLabel"),
        min=1000,
        max=10000,
        step=500,
        value=b("/prefs/maxPerNight"),
        currency="PHP",
    ),
    c("spots-heading", "Heading", title=b("/spotsHeading/title"), subtitle=b("/spotsHeading/subtitle")),
    c("spots-grid", "FlexGrid", children=["spot-1", "spot-2", "spot-3"], minItemWidth=260),
]
for i in range(3):
    rf_components.append(
        c(
            f"spot-{i + 1}",
            "Heading",
            eyebrow=b(f"/spots/{i}/eyebrow"),
            title=b(f"/spots/{i}/title"),
            subtitle=b(f"/spots/{i}/subtitle"),
            image=b(f"/spots/{i}/image"),
        )
    )
rf_components += [
    c("local-note", "LocalNote", title=b("/note/title"), body=b("/note/body"), tone="local", author=b("/note/author")),
    c(
        "next-actions",
        "Actions",
        buttons=[
            {
                "label": "Find dates and prices",
                "style": "primary",
                "action": ev(
                    "plan_flexible_trip",
                    months=b("/prefs/months"),
                    length=b("/prefs/length"),
                    maxPerNight=b("/prefs/maxPerNight"),
                ),
            },
            {
                "label": "Show me more spots",
                "style": "secondary",
                "action": ev("more_spots", intent="returning_flexible"),
            },
        ],
    ),
]
rf_data = {
    "hero": {
        "eyebrow": "Welcome back",
        "title": "Siargao, the quieter side",
        "subtitle": "Pick when you can go and your budget. Here are spots most first-timers skip.",
    },
    "when": {
        "label": "Which months work?",
        "options": ["March", "April", "May", "June", "July", "August", "September", "October"],
    },
    "length": {"label": "How long?", "options": ["4 nights", "1 week", "2 weeks"]},
    "budgetLabel": "Max stay price per night",
    "prefs": {"months": ["April", "May"], "length": ["1 week"], "maxPerNight": 3500},
    "spotsHeading": {"title": "Lesser-known spots", "subtitle": "Worth the extra scooter ride."},
    "spots": spots,
    "note": {
        "title": "Pick your season",
        "body": "September to November brings the biggest swell and the surf cup crowds at Cloud 9. For calm water, easy island hopping and cheaper rooms, March to June is the sweet spot.",
        "author": "From a Siargao local",
    },
}
rf_text = "\n\n".join(
    [
        "## Siargao, the quieter side",
        "Welcome back. Since you have done the classics, here is how to plan a flexible return trip.",
        "**When to go**\n- March to June: calm water, easy island hopping, cheaper rooms.\n- September to November: biggest swell and the surf cup crowds at Cloud 9.",
        "**Suggested setup:** 1 week in April or May, stays up to PHP 3,500 per night (sample price).",
        "**Lesser-known spots**\n" + "\n".join(f"- **{s['title']}** ({s['eyebrow']}): {s['subtitle']}" for s in spots),
        "Tell me your months, trip length and nightly budget and I will find dates and prices.",
    ]
)
write(
    "returning_flexible",
    fixture(
        "returning_flexible",
        "Returning traveler, flexible dates",
        "I've been to Siargao before. My dates are flexible. Where should I go this time?",
        "a2a",
        rf_text,
        rf_components,
        rf_data,
    ),
)

# ---------------------------------------------------------------- home_first_run
featured = [
    {
        "eyebrow": "Del Carmen",
        "title": "Sugba Lagoon",
        "subtitle": "Turquoise lagoon in the mangroves. Paddle board, swim, jump.",
        "image": "sugba-lagoon",
    },
    {
        "eyebrow": "Island hopping",
        "title": "Guyam Island",
        "subtitle": "A tiny palm island 15 minutes by boat from General Luna.",
        "image": "guyam-island",
    },
    {
        "eyebrow": "Pilar",
        "title": "Magpupungko rock pools",
        "subtitle": "Natural pools that appear at low tide on the east coast.",
        "image": "magpupungko-pools",
    },
]
home_components = [
    c(
        "root",
        "Stack",
        children=["hero", "quick-chips", "featured-heading", "featured-grid", "local-note"],
        gap="large",
    ),
    c(
        "hero",
        "Heading",
        eyebrow=b("/hero/eyebrow"),
        title=b("/hero/title"),
        subtitle=b("/hero/subtitle"),
        image=b("/hero/image"),
    ),
    c(
        "quick-chips",
        "ChipRow",
        label=b("/quick/label"),
        options=b("/quick/options"),
        selected=b("/quick/selected"),
        multiSelect=False,
    ),
    c("featured-heading", "Heading", title=b("/featuredHeading")),
    c("featured-grid", "FlexGrid", children=["spot-1", "spot-2", "spot-3"], minItemWidth=240),
]
for i in range(3):
    home_components.append(
        c(
            f"spot-{i + 1}",
            "Heading",
            eyebrow=b(f"/featured/{i}/eyebrow"),
            title=b(f"/featured/{i}/title"),
            subtitle=b(f"/featured/{i}/subtitle"),
            image=b(f"/featured/{i}/image"),
        )
    )
home_components.append(c("local-note", "LocalNote", title=b("/note/title"), body=b("/note/body"), tone="tip"))
home_data = {
    "hero": {
        "eyebrow": "Siargao, Surigao del Norte",
        "title": "Plan your Siargao trip",
        "subtitle": "Surf breaks, island hopping and lagoons. Ask anything or start with a quick pick.",
        "image": "cloud-9-boardwalk",
    },
    "quick": {
        "label": "Start with",
        "options": [
            "First trip, 4 days",
            "Flights under 8,000",
            "Surf this week",
            "Stays near Cloud 9",
            "Flexible dates",
        ],
        "selected": [],
    },
    "featuredHeading": "Featured spots",
    "featured": featured,
    "note": {
        "title": "Best time to go",
        "body": "March to October is the drier stretch. November to February brings more rain and rougher boat rides, so keep a spare day in your plan.",
    },
}
home_text = "\n\n".join(
    [
        "## Plan your Siargao trip",
        "Surf breaks, island hopping and lagoons. Ask anything, or start with one of these:",
        "- First trip, 4 days\n- Flights under 8,000\n- Surf this week\n- Stays near Cloud 9\n- Flexible dates",
        "**Featured spots**\n" + "\n".join(f"- **{s['title']}** ({s['eyebrow']}): {s['subtitle']}" for s in featured),
        "**Best time to go:** March to October is the drier stretch. November to February brings more rain and rougher boat rides, so keep a spare day in your plan.",
    ]
)
write(
    "home_first_run",
    fixture(
        "home_first_run",
        "Home, first run",
        "Read resource a2ui://home/first-run",
        "mcp_resource",
        home_text,
        home_components,
        home_data,
    ),
)

# ---------------------------------------------------------------- flights_under_8000
flights = [
    {
        "id": "ceb-iao-morning",
        "name": "Cebu to Siargao",
        "route": "CEB to IAO, direct, about 1h",
        "note": "Morning departure, 7 kg carry-on included",
        "fare": 2980,
        "origin": "Cebu",
    },
    {
        "id": "ceb-iao-midday",
        "name": "Cebu to Siargao",
        "route": "CEB to IAO, direct, about 1h",
        "note": "Midday departure, 20 kg checked bag included",
        "fare": 3650,
        "origin": "Cebu",
    },
    {
        "id": "mnl-iao-early",
        "name": "Manila to Siargao",
        "route": "MNL to IAO, direct, about 1h 45m",
        "note": "Early morning departure, 7 kg carry-on included",
        "fare": 4890,
        "origin": "Manila",
    },
    {
        "id": "crk-iao-morning",
        "name": "Clark to Siargao",
        "route": "CRK to IAO, direct, about 1h 55m",
        "note": "Morning departure, skips Manila traffic",
        "fare": 5420,
        "origin": "Clark",
    },
    {
        "id": "mnl-iao-midday",
        "name": "Manila to Siargao",
        "route": "MNL to IAO, direct, about 1h 50m",
        "note": "Late morning departure, 20 kg checked bag included",
        "fare": 6750,
        "origin": "Manila",
    },
]
fl_components = [
    c(
        "root",
        "Stack",
        children=["hero", "origin-chips", "fare-slider", "flights-grid", "fare-breakdown", "baggage-note"],
        gap="medium",
    ),
    c(
        "hero",
        "Heading",
        eyebrow=b("/hero/eyebrow"),
        title=b("/hero/title"),
        subtitle=b("/hero/subtitle"),
        image=b("/hero/image"),
    ),
    c(
        "origin-chips",
        "ChipRow",
        label=b("/origins/label"),
        options=b("/origins/options"),
        selected=b("/search/origins"),
        multiSelect=True,
    ),
    c(
        "fare-slider",
        "BudgetSlider",
        label=b("/search/maxFareLabel"),
        min=2000,
        max=12000,
        step=500,
        value=b("/search/maxFare"),
        currency="PHP",
    ),
    c("flights-grid", "FlexGrid", children=[f"flight-{i + 1}" for i in range(len(flights))], minItemWidth=260),
]
for i, f in enumerate(flights):
    fl_components.append(
        c(
            f"flight-{i + 1}",
            "StayCard",
            image="siargao-flight",
            name=b(f"/flights/{i}/name"),
            area=b(f"/flights/{i}/route"),
            note=b(f"/flights/{i}/note"),
            pricePerNight=b(f"/flights/{i}/fare"),
            priceUnit="one way",
            currency="PHP",
            action=ev("choose_flight", flightId=f["id"], origin=f["origin"]),
            actionLabel="Select",
        )
    )
fare_items = [
    {"label": "Base fare", "amount": 3290},
    {"label": "Fuel surcharge", "amount": 620},
    {"label": "Taxes and airport fees", "amount": 680},
    {"label": "Booking and service fees", "amount": 300},
]
assert sum(i["amount"] for i in fare_items) == 4890
fl_components += [
    c(
        "fare-breakdown",
        "CostBreakdown",
        title=b("/breakdown/title"),
        currency="PHP",
        items=b("/breakdown/items"),
        totalLabel="Fare, one way",
    ),
    c("baggage-note", "LocalNote", title=b("/note/title"), body=b("/note/body"), tone="heads_up"),
]
fl_data = {
    "hero": {
        "eyebrow": "Sample fares, not live",
        "title": "Flights to Siargao under PHP 8,000",
        "subtitle": "Direct one-way flights to Sayak Airport (IAO) in Del Carmen, cheapest first.",
        "image": "siargao-flight",
    },
    "origins": {"label": "Flying from", "options": ["Manila", "Cebu", "Clark"]},
    "search": {"origins": ["Manila", "Cebu", "Clark"], "maxFare": 8000, "maxFareLabel": "Max fare, one way"},
    "flights": flights,
    "breakdown": {"title": "What the PHP 4,890 Manila fare includes (sample)", "items": fare_items},
    "note": {
        "title": "Watch the baggage",
        "body": "Promo fares usually include only a 7 kg carry-on. Add checked bags or a surfboard when you book: it costs far less online than at the airport counter.",
    },
}
fl_text = "\n\n".join(
    [
        "## Flights to Siargao under PHP 8,000",
        "Sample one-way fares to Sayak Airport (IAO) in Del Carmen, cheapest first. These are not live prices.",
        "\n".join(f"- **{f['name']}** ({f['route']}): {php(f['fare'])}. {f['note']}." for f in flights),
        "**What the PHP 4,890 Manila fare includes (sample)**\n"
        + "\n".join(f"- {i['label']}: {php(i['amount'])}" for i in fare_items),
        "**Heads up:** promo fares usually include only a 7 kg carry-on. Add checked bags or a surfboard when you book: it costs far less online than at the airport counter.",
        "From Sayak Airport it is about 1 hour by shared van to General Luna.",
    ]
)
write(
    "flights_under_8000",
    fixture(
        "flights_under_8000",
        "Flights under PHP 8,000",
        "Flights to Siargao under 8,000",
        "a2a",
        fl_text,
        fl_components,
        fl_data,
    ),
)

# ---------------------------------------------------------------- surf_this_week
breaks = {
    "beginner": [
        {
            "eyebrow": "Beginner, sand and reef",
            "title": "Jacking Horse",
            "subtitle": "1 to 2 ft all week. Soft rolling waves next to Cloud 9, best at mid to high tide.",
        },
        {
            "eyebrow": "Beginner to intermediate",
            "title": "Quiksilver",
            "subtitle": "2 to 3 ft, cleanest before 9am. Easy paddle out from the Cloud 9 area.",
        },
    ],
    "advanced": [
        {
            "eyebrow": "Advanced, shallow reef",
            "title": "Cloud 9",
            "subtitle": "3 to 5 ft from Thursday. Fast right-hand barrels, crowded at dawn.",
            "image": "cloud-9-boardwalk",
        },
        {
            "eyebrow": "Advanced, boat access",
            "title": "Stimpy's",
            "subtitle": "4 to 6 ft lefts on the outer reef. Go with a local boatman and a buddy.",
        },
    ],
}
st_components = [
    c(
        "root",
        "Stack",
        children=[
            "hero",
            "level-chips",
            "beginner-heading",
            "beginner-grid",
            "advanced-heading",
            "advanced-grid",
            "surf-costs",
            "safety-note",
            "next-actions",
        ],
        gap="medium",
    ),
    c(
        "hero",
        "Heading",
        eyebrow=b("/hero/eyebrow"),
        title=b("/hero/title"),
        subtitle=b("/hero/subtitle"),
        image=b("/hero/image"),
    ),
    c(
        "level-chips",
        "ChipRow",
        label=b("/levels/label"),
        options=b("/levels/options"),
        selected=b("/prefs/level"),
        multiSelect=False,
    ),
    c("beginner-heading", "Heading", title="Best for beginners"),
    c("beginner-grid", "FlexGrid", children=["break-jacking-horse", "break-quiksilver"], minItemWidth=260),
    c("advanced-heading", "Heading", title="For experienced surfers"),
    c("advanced-grid", "FlexGrid", children=["break-cloud9", "break-stimpys"], minItemWidth=260),
]
for gid, level in (
    ("break-jacking-horse", ("beginner", 0)),
    ("break-quiksilver", ("beginner", 1)),
    ("break-cloud9", ("advanced", 0)),
    ("break-stimpys", ("advanced", 1)),
):
    lv, i = level
    props = {
        "eyebrow": b(f"/breaks/{lv}/{i}/eyebrow"),
        "title": b(f"/breaks/{lv}/{i}/title"),
        "subtitle": b(f"/breaks/{lv}/{i}/subtitle"),
    }
    if "image" in breaks[lv][i]:
        props["image"] = b(f"/breaks/{lv}/{i}/image")
    st_components.append(c(gid, "Heading", **props))
surf_cost_items = [
    {"label": "Surf lesson, 1.5 hours with coach", "amount": 1500},
    {"label": "Softboard rental, full day", "amount": 500},
    {"label": "Boat to the outer reefs, per person", "amount": 1000},
]
st_components += [
    c(
        "surf-costs",
        "CostBreakdown",
        title=b("/costs/title"),
        currency="PHP",
        items=b("/costs/items"),
        totalLabel="If you do it all",
    ),
    c(
        "safety-note",
        "LocalNote",
        title=b("/note/title"),
        body=b("/note/body"),
        tone="heads_up",
        author=b("/note/author"),
    ),
    c(
        "next-actions",
        "Actions",
        buttons=[
            {
                "label": "Book a lesson",
                "style": "primary",
                "action": ev("book_surf_lesson", spot="Jacking Horse", level=b("/prefs/level")),
            },
            {"label": "Find a board rental", "style": "secondary", "action": ev("find_board_rental", area="Cloud 9")},
        ],
    ),
]
st_data = {
    "hero": {
        "eyebrow": "Surf report, sample data",
        "title": "Siargao surf this week",
        "subtitle": "Small and friendly early in the week, a bigger swell from Thursday. Light offshore winds before 9am.",
        "image": "cloud-9-boardwalk",
    },
    "levels": {"label": "Your level", "options": ["Beginner", "Intermediate", "Advanced"]},
    "prefs": {"level": ["Beginner"]},
    "breaks": breaks,
    "costs": {"title": "Surf costs (sample prices)", "items": surf_cost_items},
    "note": {
        "title": "Respect the reef",
        "body": "Cloud 9 and Stimpy's break over shallow reef. Wear reef booties, never surf them at low tide, and stay out of the lineup at Cloud 9 if you are still learning.",
        "author": "From a Siargao surf coach",
    },
}


def break_md(bk):
    return f"- **{bk['title']}** ({bk['eyebrow']}): {bk['subtitle']}"


st_text = "\n\n".join(
    [
        "## Siargao surf this week (sample data)",
        "Small and friendly early in the week, a bigger swell from Thursday. Light offshore winds before 9am.",
        "**Best for beginners**\n" + "\n".join(break_md(x) for x in breaks["beginner"]),
        "**For experienced surfers**\n" + "\n".join(break_md(x) for x in breaks["advanced"]),
        "**Surf costs (sample prices)**\n" + "\n".join(f"- {i['label']}: {php(i['amount'])}" for i in surf_cost_items),
        "**Safety:** Cloud 9 and Stimpy's break over shallow reef. Wear reef booties, never surf them at low tide, and stay out of the lineup at Cloud 9 if you are still learning.",
    ]
)
write(
    "surf_this_week",
    fixture(
        "surf_this_week",
        "Surf this week",
        "How's the surf in Siargao this week?",
        "a2a",
        st_text,
        st_components,
        st_data,
    ),
)

# ---------------------------------------------------------------- stays_near_cloud9
QUERY = {"area": "Cloud 9", "nights": 3, "max_price": 4500}
results = search_stays(QUERY["area"], QUERY["nights"], QUERY["max_price"])
sn_components = [
    c("root", "Stack", children=["hero", "price-slider", "stays-grid", "local-note"], gap="medium"),
    c("hero", "Heading", eyebrow=b("/hero/eyebrow"), title=b("/hero/title"), subtitle=b("/hero/subtitle")),
    c(
        "price-slider",
        "BudgetSlider",
        label="Max price per night",
        min=500,
        max=10000,
        step=500,
        value=b("/query/max_price"),
        currency="PHP",
    ),
    c("stays-grid", "FlexGrid", children=[f"stay-{i + 1}" for i in range(len(results))], minItemWidth=260),
]
for i, s in enumerate(results):
    sn_components.append(
        c(
            f"stay-{i + 1}",
            "StayCard",
            image=b(f"/stays/{i}/image"),
            name=b(f"/stays/{i}/name"),
            note=b(f"/stays/{i}/note"),
            pricePerNight=b(f"/stays/{i}/pricePerNight"),
            currency="PHP",
            area=b(f"/stays/{i}/area"),
            rating=b(f"/stays/{i}/rating"),
            action=ev("choose_stay", stayId=s["id"], nights=QUERY["nights"]),
            actionLabel="Choose",
        )
    )
sn_components.append(
    c("local-note", "LocalNote", title=b("/note/title"), body=b("/note/body"), tone="local", author=b("/note/author"))
)
sn_data = {
    "query": dict(QUERY),
    "hero": {
        "eyebrow": "3 nights, up to PHP 4,500 per night",
        "title": f"{len(results)} stays near Cloud 9",
        "subtitle": "Sample prices per night, cheapest first.",
    },
    "stays": results,
    "note": {
        "title": "Book the boardwalk side",
        "body": "Stays on the Cloud 9 road are a short walk to the break and to food. Further inland is cheaper but you will want a scooter.",
        "author": "From a Siargao local",
    },
}
sn_text = "\n\n".join(
    [
        f"## {len(results)} stays near Cloud 9",
        "3 nights, up to PHP 4,500 per night. Sample prices, cheapest first.",
        "\n".join(
            f"- **{s['name']}** ({s['area']}, rated {s['rating']}): {php(s['pricePerNight'])} per night, {php(s['pricePerNight'] * QUERY['nights'])} for 3 nights. {s['note']}."
            for s in results
        ),
        "**Local tip:** stays on the Cloud 9 road are a short walk to the break and to food. Further inland is cheaper but you will want a scooter.",
    ]
)
write(
    "stays_near_cloud9",
    fixture(
        "stays_near_cloud9",
        "Stays near Cloud 9",
        'search_stays(area="Cloud 9", nights=3, max_price=4500)',
        "mcp_tool",
        sn_text,
        sn_components,
        sn_data,
    ),
)
print("wrote fixtures to", OUT)
