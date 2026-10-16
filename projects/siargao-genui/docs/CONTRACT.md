# Shared contract

Every part of the demo (app, agent, MCP server, fixtures) follows this file. If you need to change it, change it here first.

## Versions

| Piece | Version |
| --- | --- |
| Flutter | 3.47.5 stable (Dart 3.13.4), from `~/fvm/versions/3.47.5/bin` |
| genui | 0.10.4 |
| genui_a2a | 0.10.1 |
| json_schema_builder | 0.1.7 |
| Python | 3.12 |
| a2ui-agent-sdk | 0.8.0 (pulls a2a-sdk 0.3.26, a2ui-core 0.3.0) |
| google-adk | 2.12.0 |
| A2UI protocol | v0.9 |
| A2A protocol | 0.3 JSON-RPC (`message/send`, `message/stream`), which is what genui_a2a 0.10.1 speaks |

## Catalog

- File: `catalog/siargao_catalog.json`, written in the A2UI v0.9 catalog format (same shape as the basic catalog in the A2UI spec).
- Catalog ID: `https://siargao-genui.example/catalogs/v1/catalog.json`. The `.example` domain is reserved, so this is a stable identifier and not a real URL.
- Components: `Stack`, `Heading`, `ItineraryDay`, `CostBreakdown`, `StayCard`, `BudgetSlider`, `ChipRow`, `LocalNote`, `FlexGrid`, `Actions`.
- Images are referenced by key, for example `"image": "cloud-9-boardwalk"`. The app maps a key to `app/assets/img/<key>.jpg` (then `.png`, then `.webp`) and shows a placeholder when no file exists.

## Fixtures

One file per intent in `fixtures/<intent>.json`:

```json
{
  "intent": "first_time_trip",
  "title": "First-time Siargao trip",
  "prompt": "Plan my first trip to Siargao, 4 days, mid budget",
  "path": "a2a",
  "source": "template",
  "modelCalls": 0,
  "text": "Markdown answer for the plain text side of the toggle.",
  "messages": [
    {"version": "v0.9", "createSurface": {"surfaceId": "first_time_trip", "catalogId": "https://siargao-genui.example/catalogs/v1/catalog.json"}},
    {"version": "v0.9", "updateComponents": {"surfaceId": "first_time_trip", "components": []}},
    {"version": "v0.9", "updateDataModel": {"surfaceId": "first_time_trip", "path": "/", "value": {}}}
  ]
}
```

- `path` is one of `a2a`, `mcp_resource`, `mcp_tool`.
- `source` is `template` or `model`. `modelCalls` is how many model calls produced the surface (0 for templates).
- `surfaceId` equals the intent name.
- Components bind to data with `{"path": "/..."}` where it makes sense, so a template keeps the components fixed and only the data model changes.

| Intent | Path | Tab |
| --- | --- | --- |
| `first_time_trip` | a2a | Chat |
| `returning_flexible` | a2a | Chat |
| `flights_under_8000` | a2a | Chat |
| `surf_this_week` | a2a | Chat |
| `home_first_run` | mcp_resource (`a2ui://home/first-run`) | Home |
| `stays_near_cloud9` | mcp_tool (`search_stays`) | Search |

## Local ports and URLs

| Service | Local URL | Notes |
| --- | --- | --- |
| Agent (A2A) | `http://localhost:10002` | Agent card at `/.well-known/agent-card.json`. Cloud Run sets `PORT`. |
| MCP server | `http://localhost:10003/mcp` | Streamable HTTP, stateless, JSON responses. |
| Flutter web | `http://localhost:8080` | Static build served for screenshots. |

Both servers allow CORS from any origin so the Flutter web build can call them.

## App configuration (`--dart-define`)

| Name | Default | Meaning |
| --- | --- | --- |
| `DEMO_MODE` | `offline` | `offline` reads `assets/fixtures/`. `live` calls the agent and MCP server. |
| `AGENT_URL` | `http://localhost:10002` | A2A base URL. |
| `MCP_URL` | `http://localhost:10003/mcp` | MCP endpoint. |

## Response metadata

The agent puts this on the A2A response message `metadata` under the key `siargao`:

```json
{"intent": "first_time_trip", "source": "template", "modelCalls": 0, "latencyMs": 12, "valid": true}
```

The MCP server puts the same object in the tool result `_meta.siargao` and the resource `_meta.siargao`.

## MIME types

- A2UI over MCP: `application/a2ui+json` (resource and embedded tool result).
- A2UI inside an A2A DataPart: a2ui-agent-sdk 0.8.0 also uses `application/a2ui+json` (`a2ui/a2a/parts.py`). The older `application/json+a2ui` is marked deprecated there. Some docs pages still show the old one.
