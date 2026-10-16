# Fixtures

Recorded A2UI v0.9 surfaces for every demo intent. The app reads them in offline mode (`DEMO_MODE=offline`), and the agent and MCP server use them as templates. The format is defined in `docs/CONTRACT.md`.

| File | Path | Prompt |
| --- | --- | --- |
| `first_time_trip.json` | a2a | Plan my first trip to Siargao, 4 days, mid budget |
| `returning_flexible.json` | a2a | I've been to Siargao before. My dates are flexible. Where should I go this time? |
| `flights_under_8000.json` | a2a | Flights to Siargao under 8,000 |
| `surf_this_week.json` | a2a | How's the surf in Siargao this week? |
| `home_first_run.json` | mcp_resource | Read resource `a2ui://home/first-run` |
| `stays_near_cloud9.json` | mcp_tool | `search_stays(area="Cloud 9", nights=3, max_price=4500)` |

Each fixture has three messages: `createSurface`, `updateComponents`, and `updateDataModel` with `path` "/" and the whole data model. Components bind to the data model with `{"path": "/..."}`, so a template keeps the components and swaps the data. The `text` field holds the same answer as markdown for the plain text side of the toggle.

All prices are sample prices in PHP for the demo, not live data. Surf conditions and flight fares are also sample data.

## `stays_dataset.json` and the `search_stays` filter

`stays_dataset.json` holds 10 sample stays (`id`, `name`, `area`, `pricePerNight`, `rating`, `note`, `image`). The MCP tool `search_stays(area, nights, max_price)` filters it with this rule:

1. Keep stays whose `area` equals `area`, ignoring case.
2. Keep stays with `pricePerNight <= max_price`.
3. Sort by `pricePerNight` ascending, then by `id`.
4. Return at most 4 results.

`nights` does not filter. It is carried into the surface (`/query/nights`) and into each Choose button's event context.

`stays_near_cloud9.json` is exactly the result of `search_stays(area="Cloud 9", nights=3, max_price=4500)`: the data model `/stays` equals the filtered list and `/query` holds the arguments. `catalog/tools/validate_fixtures.py` checks this, so if you change the dataset, regenerate the fixture to match.

## Validate

From `projects/siargao-genui`:

```sh
catalog/.venv/bin/python catalog/tools/validate_fixtures.py
```
