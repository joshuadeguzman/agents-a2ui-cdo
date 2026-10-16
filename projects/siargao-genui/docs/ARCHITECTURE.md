# Architecture

The demo shows one idea: the agent sends a description of UI (A2UI v0.9 JSON), and the app renders it with its own Flutter widgets. Nothing executable crosses the wire. The app only ever draws components it already knows.

## Pieces

```
                 catalog/siargao_catalog.json   (single source of truth)
                  |              |                |
     gen_dart.py  |   sync       |   sync         |  validate
                  v              v                v
   app/lib/catalog/*.g.dart   agent/siargao_agent/catalog/   mcp/catalog/
                  |
 +----------------+------------------------------------------------+
 | Flutter app (genui 0.10.4)                                       |
 |  Chat tab    ---- A2A 0.3 JSON-RPC (message/stream, SSE) ----+   |
 |  Home tab    ---- MCP resources/read a2ui://home/first-run --|-+ |
 |  Search tab  ---- MCP tools/call search_stays ---------------|-+ |
 |  Offline: assets/fixtures/*.json (copies of fixtures/)       | | |
 +--------------------------------------------------------------|-|-+
                                                                v v
              agent/ (ADK + a2ui SDK, :10002)          mcp/ (MCP SDK, :10003)
              router -> template or Gemini             static resource + templated tool
              validate -> log -> reply                 validate -> reply
```

## Catalog

`catalog/siargao_catalog.json` defines 10 components in the A2UI v0.9 catalog format: Stack, Heading, ItineraryDay, CostBreakdown, StayCard, BudgetSlider, ChipRow, LocalNote, FlexGrid, Actions. Every property has a description, because the model reads them to decide what to send.

- The app gets typed schemas from `catalog/tools/gen_dart.py`, which writes `app/lib/catalog/catalog_schemas.g.dart`.
- The agent and MCP server keep vendored copies so each Docker build context stays inside its own folder. A test in each project fails if a copy drifts.
- `catalog/tools/validate_fixtures.py` checks every fixture against the v0.9 spec schemas with our catalog plugged in, runs the a2ui SDK `validate_payload`, and adds semantic checks (root exists, children exist, bindings resolve, image keys exist).

## Surfaces are components plus data

Each surface is three messages: `createSurface`, `updateComponents`, `updateDataModel`. Components bind to the data model with `{"path": "/..."}`. That split is what makes templates work: a frozen template keeps the component tree and only the data changes from request to request.

## Delivery paths

| Tab | Path | What happens |
| --- | --- | --- |
| Chat | A2A | The app sends the prompt with `metadata.siargao.responseFormat` (`a2ui` or `text`). The agent answers with one DataPart per A2UI message, or one markdown TextPart. |
| Home | MCP resource | `resources/read a2ui://home/first-run` returns a fixed surface, `mimeType: application/a2ui+json`. |
| Search | MCP tool | `tools/call search_stays(area, nights, max_price)` filters a small dataset and fills a template. It returns an embedded resource with `mimeType: application/a2ui+json`. |

Every response carries `siargao` metadata (`intent`, `source`, `modelCalls`, `latencyMs`, `valid`). The app shows the delivery path and the model call count on each screen.

## Agent: explore, then freeze

1. Route: explicit `intent` from the app, then keyword rules, then the model.
2. Template path: render `templates/<intent>.json` with data from `data/<intent>.json`, adjusted by small functions in `intents.py` (for example a fare cap parsed from "under 5k"). 0 model calls.
3. Model path (live mode only): ADK `LlmAgent` with a system prompt built by the a2ui SDK from our catalog and rules, Gemini on Vertex AI. 1 model call.
4. Validate every reply. An invalid surface falls back to text and is logged with `valid: false`.
5. Log every reply to `logs/surfaces.jsonl`.
6. `scripts/freeze.py` promotes a good logged surface to a template. The next identical request costs 0 model calls. `agent/examples/` holds a real example: a live Gemini surface frozen into `rainy_day_general_luna`.

## App safety

- Unknown components are removed before genui sees them (`lib/a2ui/surface_sanitizer.dart`), and Stack and FlexGrid only build children that exist and are in the catalog. A surface with an unknown component still renders the rest.
- genui reports render and validation errors on `SurfaceController.onSubmit`. The app records and logs them but never forwards them, so no error loops back to the agent.
- Images are local assets by key. A missing file shows a placeholder with the alt text, at the right aspect ratio.

## Offline mode

`DEMO_MODE=offline` (the default) reads `app/assets/fixtures/`, which are byte-identical copies of `fixtures/`. The agent's templates reproduce the fixtures exactly for the fixture prompts, and the MCP tool reproduces `stays_near_cloud9` exactly, so offline and live look the same for the demo prompts.

## Protocol notes

- genui_a2a 0.10.1 speaks A2A 0.3 JSON-RPC. a2ui-agent-sdk 0.8.0 pins a2a-sdk 0.3.26, which matches. The newer a2a-sdk 1.x is a different protocol version and would not work with this client.
- The app uses its own small A2A client (`lib/services/a2a_service.dart`) instead of `A2uiAgentConnector`. The connector in 0.10.1 drops response metadata (needed for the model call label) and overwrites request metadata.
- A2UI MIME type is `application/a2ui+json` on both paths. a2ui-agent-sdk 0.8.0 still writes the deprecated `application/json+a2ui` from `create_a2ui_part`, so the agent sets the MIME type itself.
- genui is being redesigned into `a2ui_core`, `a2ui_agent` and `a2ui_flutter` (see the genui README). This demo stays on genui 0.10.4 as planned.
