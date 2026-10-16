# Siargao MCP server

Delivers A2UI v0.9 surfaces over MCP for the Siargao travel planner demo ("Powering Generative UI in the Cloud", DevFest Manila). No model calls: every surface is a template filled with sample data.

| What | MCP | A2UI surface |
| --- | --- | --- |
| Home, first run | resource `a2ui://home/first-run` | `home_first_run` (copy of `fixtures/home_first_run.json`) |
| Stay search | tool `search_stays(area, nights, max_price)` | `stays_near_cloud9`, embedded resource `a2ui://search/stays` |

Both use `mimeType: application/a2ui+json`, and the text is the JSON array of A2UI messages (`createSurface`, `updateComponents`, `updateDataModel`). See `../docs/CONTRACT.md`, "MCP surface".

Endpoint: `http://localhost:10003/mcp`. Streamable HTTP, stateless, JSON responses, CORS open to any origin. `GET /healthz` returns `{"ok": true, ...}`.

## Run

```sh
cd projects/siargao-genui/mcp
python3.12 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt   # or requirements.txt for runtime only
.venv/bin/python -m siargao_mcp                 # PORT defaults to 10003, host 0.0.0.0
```

## Test and lint

```sh
.venv/bin/pytest
.venv/bin/ruff check . && .venv/bin/ruff format --check .
.venv/bin/python scripts/smoke.py http://localhost:10003   # against a running server
```

`scripts/smoke.py` sends `tools/list`, `resources/list`, `resources/read`, `tools/call` and a CORS preflight, validates every surface, and prints a summary.

## Vendored files

The Docker build context is `mcp/` only, so the server reads copies of shared files:

| Copy | Source |
| --- | --- |
| `surfaces/home_first_run.json` | `../fixtures/home_first_run.json` |
| `data/stays.json` | `../fixtures/stays_dataset.json` |
| `catalog/` | `../catalog/siargao_catalog.json`, `images.json`, `spec/v0_9/*` |

After changing a fixture or the catalog, run `scripts/sync_shared.sh`. `tests/test_vendored.py` fails when a copy drifts.

`templates/stays.json` holds the fixed components of the stays surface (derived from `fixtures/stays_near_cloud9.json`), the StayCard prototype, the empty state, and the copy. `search_stays(area="Cloud 9", nights=3, max_price=4500)` reproduces the fixture's `messages` exactly (tested).

## Calling it from the app

No `initialize` is needed. In stateless mode the SDK creates a ready session for every POST, so each request below works on its own. No `Mcp-Session-Id` is issued or required. Send these headers:

```
Content-Type: application/json
Accept: application/json, text/event-stream
```

`Accept: application/json` alone also works. The response is always a single JSON body (`Content-Type: application/json`), never SSE.

### tools/call search_stays

```sh
curl -s http://localhost:10003/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_stays","arguments":{"area":"Cloud 9","nights":3,"max_price":4500}}}'
```

```json
{"jsonrpc": "2.0", "id": 1, "result": {
  "_meta": {"siargao": {"intent": "stays_near_cloud9", "source": "template", "modelCalls": 0, "latencyMs": 17, "valid": true}},
  "content": [
    {"type": "resource", "resource": {"uri": "a2ui://search/stays", "mimeType": "application/a2ui+json", "text": "[{\"version\": \"v0.9\", \"createSurface\": ...}, ...]"}},
    {"type": "text", "text": "4 stays near Cloud 9 for 3 nights, up to PHP 4,500 per night: ..."}
  ],
  "isError": false}}
```

Parse `content[0].resource.text` as JSON to get the message list.

Arguments: `area` (string, 1 to 60 chars, matched ignoring case), `nights` (integer 1 to 30), `max_price` (integer 500 to 10000, the budget slider range). Bad arguments return `isError: true` with a text item explaining why and `_meta.siargao.valid: false`. With zero matches the tool still returns a valid surface: the grid is replaced by a `LocalNote` (`no-results`, tone `heads_up`) that names the cheapest stay in that area, or lists the known areas.

Filter rule (`fixtures/README.md`): area equal ignoring case, `pricePerNight <= max_price`, sort by price then id, at most 4. `nights` does not filter; it lands in `/query/nights` and in each Choose button's event context.

### resources/read a2ui://home/first-run

```sh
curl -s http://localhost:10003/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"a2ui://home/first-run"}}'
```

```json
{"jsonrpc": "2.0", "id": 2, "result": {
  "_meta": {"siargao": {"intent": "home_first_run", "source": "template", "modelCalls": 0, "latencyMs": 0, "valid": true}},
  "contents": [{"_meta": {"siargao": {...same...}}, "uri": "a2ui://home/first-run", "mimeType": "application/a2ui+json", "text": "[...A2UI messages...]"}]}}
```

An unknown URI is a JSON-RPC error `-32602`.

### Lists

```sh
curl -s http://localhost:10003/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/list"}'
curl -s http://localhost:10003/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":4,"method":"resources/list"}'
```

### CORS preflight

```sh
curl -s -i -X OPTIONS http://localhost:10003/mcp \
  -H 'Origin: http://localhost:8080' -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type,accept,mcp-protocol-version'
```

Returns 200 with `access-control-allow-origin: *`. Responses expose `Mcp-Session-Id` and `Mcp-Protocol-Version`.

Regular MCP clients (for example the SDK `Client`, or an MCP inspector) can still run the usual `initialize` handshake. It works, it is just not required.

## Response metadata

`_meta.siargao` is `{intent, source: "template", modelCalls: 0, latencyMs, valid}`, as in the contract. It is on the `tools/call` result, and on both the `resources/read` result and `contents[0]`. `latencyMs` is the server-side time to build and validate the surface.

## Validation

Every surface is validated before it is returned: JSON Schema (the vendored A2UI v0.9 `server_to_client.json` with `siargao_catalog.json` as its catalog) plus semantic checks (Stack root, children exist and are reachable, bindings resolve, image keys exist). It costs about 15 ms. The home surface is static, so it is validated once and cached. A failure is logged as a warning and returned as an error (`isError: true` for the tool, JSON-RPC `-32603` for the resource).

The a2ui SDK validator (`a2ui.utils.validate_payload`) runs in the tests and in `scripts/smoke.py`, not in the server: `a2ui-agent-sdk==0.8.0` pulls in `google-adk` and `google-genai`, which would bloat the image for no runtime benefit.

## SDK version

`mcp==2.3.0` (the current major). The server uses the low-level `mcp.server.Server` with explicit handlers, because `MCPServer` (the 2.x name for FastMCP) only lets a resource carry static `_meta` on its contents, not a per-request `_meta` on the result. Streamable HTTP runs with `stateless_http=True, json_response=True`. DNS rebinding protection is turned off on purpose: it would reject the Cloud Run `Host` header and browser origins, and the server is public, read-only demo data.

## Deploy (you run this)

```sh
cd projects/siargao-genui/mcp
CONFIRM_DEPLOY=yes ./deploy.sh
```

It syncs the vendored files and runs `gcloud run deploy siargao-mcp --source . --project devfest-genui-manila --region asia-southeast1 --allow-unauthenticated`. Without `CONFIRM_DEPLOY=yes` it refuses. `.gcloudignore` keeps `.venv/` out of the upload. Then:

```sh
.venv/bin/python scripts/smoke.py "$(gcloud run services describe siargao-mcp --project devfest-genui-manila --region asia-southeast1 --format 'value(status.url)')"
```

Local container check (needs Docker running):

```sh
docker build -t siargao-mcp .
docker run --rm -p 10003:10003 siargao-mcp
```
