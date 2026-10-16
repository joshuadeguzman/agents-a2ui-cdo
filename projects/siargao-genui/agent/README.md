# Siargao agent

Python A2A agent for the Siargao travel planner demo. It answers with A2UI v0.9 surfaces for the Siargao catalog. Known prompts are served from frozen templates (no model call). Everything else goes to Gemini through an ADK `LlmAgent`, in live mode only. The wire format follows `../docs/CONTRACT.md`.

## How a request is answered

1. A DataPart with `action` (a button tap) gets a short text confirmation, for example "Saved Cloud 9 Surf Cabins for 3 nights."
2. Otherwise the prompt is routed: `metadata.siargao.intent` first, then keyword rules (`siargao_agent/router.py`, plus `keywords` in frozen templates), then the model.
3. A template keeps its components fixed (`templates/<intent>.json`). Its data (`data/<intent>.json`) can be adjusted from the prompt by a small function in `siargao_agent/intents.py`, for example "flights under 5k" or "stays in General Luna for 2 nights under 3000".
4. `responseFormat: "text"` returns the template's markdown instead of A2UI.
5. Every surface (template or model) is validated with the a2ui SDK `validate_payload` plus semantic checks. An invalid one falls back to text with `valid: false`.
6. The reply message carries `metadata.siargao = {intent, source, modelCalls, latencyMs, valid}`.
7. Every reply is appended to `logs/surfaces.jsonl` (`SURFACE_LOG` overrides).

On the wire, a `message/stream` response is a `task` event followed by one `status-update` (`final: true`, state `completed`) whose message holds one DataPart per A2UI message, or one markdown TextPart. `message/send` returns that Task. This is the shape genui_a2a 0.10.1 reads.

## Setup

```sh
cd projects/siargao-genui/agent
/Library/Frameworks/Python.framework/Versions/3.12/bin/python3 -m venv .venv
.venv/bin/pip install -r requirements.txt -r requirements-dev.txt -c constraints.txt
```

## Run offline (default, no model)

```sh
.venv/bin/python -m siargao_agent            # http://localhost:10002
curl http://localhost:10002/.well-known/agent-card.json
.venv/bin/python scripts/smoke.py http://localhost:10002
```

Prompts that no template covers get a polite text reply saying the model is disabled (modelCalls 0).

## Run live (Gemini on Vertex AI)

```sh
gcloud auth application-default login        # once
SIARGAO_MODE=live \
GOOGLE_GENAI_USE_VERTEXAI=TRUE \
GOOGLE_CLOUD_PROJECT=devfest-genui-manila \
GOOGLE_CLOUD_LOCATION=global \
GEMINI_MODEL=gemini-3.5-flash \
.venv/bin/python -m siargao_agent
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `SIARGAO_MODE` | `offline` | `offline` never imports or calls a model. `live` enables the model path. |
| `GEMINI_MODEL` | `gemini-3.5-flash` | Model id (the google-adk 2.12.0 default). |
| `GEMINI_THINKING_LEVEL` | `low` | Gemini thinking level. Set it empty to send no thinking config. |
| `SIARGAO_MODEL_RETRY` | `false` | Allow one extra model call when the first answer fails validation. |
| `SURFACE_LOG` | `logs/surfaces.jsonl` | Where replies are logged. |
| `PORT` | `10002` | Listen port (Cloud Run sets 8080). |
| `PUBLIC_URL` | unset | Pins the agent card `url`. Unset, the card shows the URL the client used. |

## Test and lint

```sh
.venv/bin/python -m pytest
.venv/bin/ruff check . && .venv/bin/ruff format --check .
```

Tests never call a model: the model path runs against a stub ADK `BaseLlm`.

## Freeze a model surface into a template

Find the line in the log, then:

```sh
.venv/bin/python scripts/freeze.py --log logs/surfaces.jsonl --line 7 --intent food_guide --keywords "where to eat,food"
```

It writes `templates/food_guide.json` (createSurface and updateComponents, surfaceId set to the intent, component ids normalised to kebab-case) and `data/food_guide.json` (the data model). It validates first and will not overwrite without `--force`. Pass `--text` to set the markdown served for `responseFormat: text` (otherwise the logged text is used). Restart the agent to serve it.

## Catalog copies

`siargao_agent/catalog/` and `data/stays_dataset.json` are copies of `../catalog/` and `../fixtures/stays_dataset.json`, so the Docker build context stays inside `agent/`. After changing the source run:

```sh
scripts/sync_catalog.sh
```

A test fails when the copies drift.

## Deploy to Cloud Run

The image defaults to `SIARGAO_MODE=live`. The script refuses to run without the confirmation variable:

```sh
CONFIRM_DEPLOY=yes ./deploy.sh
```

It runs `gcloud run deploy siargao-agent --source .` in project `devfest-genui-manila`, region `asia-southeast1`, with the Vertex env vars and `--allow-unauthenticated` (the Flutter web app calls it directly). The Cloud Run service account needs the Vertex AI User role (`roles/aiplatform.user`) to call Gemini. After deploying:

```sh
.venv/bin/python scripts/smoke.py https://<service-url>
```

To build the image locally: `docker build -t siargao-agent .` then `docker run -p 8080:8080 -e SIARGAO_MODE=offline siargao-agent`.
