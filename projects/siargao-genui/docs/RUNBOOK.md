# Runbook

All commands run from `projects/siargao-genui/` unless noted. Python is 3.12 at `/Library/Frameworks/Python.framework/Versions/3.12/bin/python3`. Flutter is 3.47.5 at `~/fvm/versions/3.47.5/bin`.

```sh
export PATH=~/fvm/versions/3.47.5/bin:$PATH
PY=/Library/Frameworks/Python.framework/Versions/3.12/bin/python3
```

## The short version

```sh
./run.sh --help
```

`run.sh` covers the common cases (Cloud Run, local servers, offline; simulator or Chrome) and asks for missing settings once. The rest of this file is the manual route.

## One time setup

```sh
(cd catalog && $PY -m venv .venv && .venv/bin/pip install -r requirements.txt)
(cd agent && $PY -m venv .venv && .venv/bin/pip install -r requirements.txt -r requirements-dev.txt -c constraints.txt)
(cd mcp && $PY -m venv .venv && .venv/bin/pip install -r requirements.txt -r requirements-dev.txt)
(cd app && flutter pub get)
```

## Demo offline (no servers, no model)

```sh
cd app && flutter run -d chrome
```

Deep links on web: `?tab=chat&intent=first_time_trip&view=both`, `?tab=home`, `?tab=search`, `?tab=gallery`.

To show the A2UI stream on stage, click `{ }` Show stream in the app bar, or open `?tab=chat&inspect=1&pace=step`. In Step mode each message waits for "Render next" (or PageDown / right arrow from a clicker), so the audience sees createSurface, then updateComponents, then updateDataModel build the screen. Replay on a card rebuilds that surface without a new request.

## Demo against local servers

Three terminals:

```sh
cd agent && .venv/bin/python -m siargao_agent          # :10002, offline templates
cd mcp && .venv/bin/python -m siargao_mcp              # :10003/mcp
cd app && flutter run -d chrome --dart-define=DEMO_MODE=live \
  --dart-define=AGENT_URL=http://localhost:10002 \
  --dart-define=MCP_URL=http://localhost:10003/mcp
```

To let free-typed prompts reach Gemini, start the agent in live mode instead:

```sh
cd agent && SIARGAO_MODE=live GOOGLE_GENAI_USE_VERTEXAI=TRUE \
  GOOGLE_CLOUD_PROJECT=devfest-genui-manila GOOGLE_CLOUD_LOCATION=global \
  .venv/bin/python -m siargao_agent
```

## Checks

```sh
(cd catalog && .venv/bin/python tools/validate_fixtures.py && .venv/bin/pytest -q)
(cd agent && .venv/bin/pytest -q && .venv/bin/ruff check . && .venv/bin/ruff format --check .)
(cd mcp && .venv/bin/pytest -q && .venv/bin/ruff check . && .venv/bin/ruff format --check .)
(cd app && flutter analyze && dart format --set-exit-if-changed . && flutter test)
```

Smoke tests against running servers:

```sh
agent/.venv/bin/python agent/scripts/smoke.py http://localhost:10002
mcp/.venv/bin/python mcp/scripts/smoke.py http://localhost:10003
```

## Changing the catalog or fixtures

1. Edit `catalog/siargao_catalog.json` or `catalog/tools/build_fixtures.py`.
2. `cd catalog && .venv/bin/python tools/build_fixtures.py && .venv/bin/python tools/validate_fixtures.py && .venv/bin/python tools/gen_dart.py`
3. Sync copies: `app/tool/sync_shared.sh`, `agent/scripts/sync_catalog.sh`, `mcp/scripts/sync_shared.sh`.
4. Run all checks. The drift tests tell you if a copy was missed.

## Explore, then freeze

1. Run the agent in live mode and try prompts. Each reply is logged to `agent/logs/surfaces.jsonl`.
2. Pick a good line and freeze it:
   ```sh
   cd agent && .venv/bin/python scripts/freeze.py --log logs/surfaces.jsonl --line N --intent my_intent --keywords "a,b"
   ```
3. Restart the agent. Matching prompts now return the template with 0 model calls.

## Screenshots

```sh
cd app
flutter build web --release --no-web-resources-cdn --dart-define=DEMO_MODE=offline
(cd build/web && python3 -m http.server 8080) &
tool/screenshots.sh http://localhost:8080 ../docs/screens
```

## Images

Drop photos into `app/assets/img/<key>.jpg` (or `.png`, `.webp`). Keys are listed in `catalog/images.json`. The prompts for the first three are in `../../tmp/imagegen/siargao-prompts.jsonl`. Until then the app shows placeholders.

## Deploy to Cloud Run

The easy way, from `projects/siargao-genui/`:

```sh
./run.sh --redeploy        # deploy (asks only for missing settings), then open the app on the simulator
./deploy.sh                # deploy only
./deploy.sh --reconfigure  # ask every question again
DRY_RUN=1 ./deploy.sh      # prints what it would run, changes nothing
```

It shows a summary and only deploys after you type `deploy`. It runs the agent and MCP tests, can grant `roles/aiplatform.user` for Vertex, deploys siargao-agent and siargao-mcp, smoke tests both, and can build and deploy siargao-web. Answers are saved in `.env.local` (git ignored, chmod 600), including a Gemini API key if you chose one. The key is set as an env var on the agent service.

For the manual route, see the step-by-step commands in `docs/REPORT.md` ("Deploy tomorrow"). Each `deploy.sh` refuses to run unless `CONFIRM_DEPLOY=yes` is set.
