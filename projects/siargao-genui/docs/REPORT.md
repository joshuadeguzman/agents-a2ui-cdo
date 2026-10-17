# Morning report

Built overnight on 2026-10-17. Everything is committed locally on `main` in the `a2ui` repo. Nothing was pushed, deployed, or changed in Google Cloud.

## Summary

- The demo is complete and runs offline by default: catalog, fixtures, Flutter app, ADK agent and MCP server.
- All checks pass: Flutter analyze, format and 99 tests (including 10 goldens), plus 55 catalog, 76 agent and 49 MCP pytest tests, all ruff clean.
- The app was run against the local agent and MCP server in live mode, with screenshots.
- One live Gemini call (of the 5 allowed) confirmed the model path works on Vertex AI. That surface was then frozen into a template.
- Six step branches are built, tagged `step-1` to `step-6`, and each was verified from a clean checkout. `step-6-explore-freeze` is identical to `main` under `projects/siargao-genui/`, except for this report and `docs/screens/steps/`, which were added to `main` afterwards.

## What works

| Area | Status | Evidence |
| --- | --- | --- |
| Catalog (10 components, v0.9 format) | Works | `catalog/tools/validate_fixtures.py`: all 6 fixtures ok. pytest 55 passed. |
| Fixtures (6 intents) | Work | Validated with the v0.9 JSON schemas and the a2ui SDK `validate_payload`, plus semantic checks. |
| Flutter app | Works | `flutter analyze`: no issues. `dart format`: 0 changed. `flutter test`: 99 passed (widget tests per item, 10 goldens, unknown component skip, every fixture through a real SurfaceController, mocked A2A and MCP clients). |
| Web build, offline | Works | `flutter build web --release --no-web-resources-cdn` |
| Agent (ADK + a2ui SDK, A2A 0.3) | Works offline | pytest 76 passed, ruff clean. `scripts/smoke.py`: all 6 intents valid over `message/stream` and `message/send`, plus a text request and an action. |
| Agent model path | Works live | 1 call to `gemini-3.5-flash` on Vertex AI (`global`): valid surface, 15.9 s, 1 model call. See `agent/examples/`. |
| Explore, then freeze | Works | The live surface was frozen with `scripts/freeze.py` into `rainy_day_general_luna`. The same prompt now returns it offline with 0 model calls in about 45 ms. |
| MCP server | Works | pytest 49 passed, ruff clean. `scripts/smoke.py`: resource and tool both return `mimeType: application/a2ui+json` and validate. The tool output equals the `stays_near_cloud9` fixture exactly. CORS preflight ok. |
| App against local servers | Works | Live build against `localhost:10002` and `localhost:10003/mcp`. The agent logged the app's A2UI and text requests, and the MCP server answered 8 POSTs with 200. Screenshots are in `docs/screens/live/`. |

## What does not work, or was skipped

- **No real photos.** `app/assets/img/` is empty, because `output/imagegen/siargao/` was empty and generating images costs money. The app shows tasteful placeholders with alt text. Drop files named by the keys in `catalog/images.json` into `app/assets/img/`. Prompts for three of them are in `tmp/imagegen/siargao-prompts.jsonl`.
- **No Docker builds.** The Docker daemon was not running. The Dockerfiles were checked by copying their file layout and starting the servers from it, but no image was built.
- **No Android or iOS builds.** Only web was built and screenshotted, because disk space was tight (it is now at about 9 GB free). The `android/` and `ios/` folders exist from `flutter create`, but they are untested.
- **Live mode in the app was only tested against the agent in offline mode** (templates, 0 model calls). The free-typed prompt path from the app to Gemini was not clicked through, to save model calls. The same request shape was tested directly with curl, and that was the one live call.
- **Only 1 of 5 live model calls was used.** There was no need for more.

## Pinned versions (verified on 2026-10-17)

| Piece | Version |
| --- | --- |
| Flutter / Dart | 3.47.5 / 3.13.4 (`~/fvm/versions/3.47.5`) |
| genui | 0.10.4 |
| genui_a2a | 0.10.1 |
| json_schema_builder | 0.1.7 |
| a2ui_core (Dart) | 0.1.1 |
| Other Dart packages | http 1.6.0, flutter_markdown_plus 1.0.12, intl 0.20.2, collection 1.19.1, flutter_lints 6.0.0 |
| Python | 3.12.3 |
| a2ui-agent-sdk | 0.8.0 (a2ui-core 0.3.0) |
| a2a-sdk | 0.3.26, with the `[http-server]` extra |
| google-adk | 2.12.0 |
| google-genai | 2.31.0 |
| mcp | 2.3.0 |
| Web server bits | starlette 1.8.0, sse-starlette 3.5.0, uvicorn 0.54.0, pydantic 2.14.1 |
| Validation | jsonschema 4.26.0, referencing 0.37.0 |
| Dev tools | pytest 9.1.1, pytest-asyncio 1.4.0, httpx 0.28.1, ruff 0.17.1 |
| Gemini model | `gemini-3.5-flash` (the google-adk 2.12.0 default), Vertex AI location `global` |
| A2UI spec files | vendored from google/A2UI commit 0d0ed91 (`catalog/spec/v0_9/SOURCE.txt`) |

Things that surprised me while reading the source:

- genui_a2a 0.10.1 speaks A2A 0.3 JSON-RPC (`message/stream`). The current a2a-sdk is 1.2.2, which is a newer protocol. a2ui-agent-sdk 0.8.0 pins a2a-sdk 0.3.26, so the pair matches. Do not upgrade a2a-sdk on its own.
- The genui README announces a redesign into `a2ui_core`, `a2ui_agent` and `a2ui_flutter` with a different API. We stay on genui 0.10.4. Worth one line in the talk.
- The A2UI MIME type is now `application/a2ui+json`. a2ui-agent-sdk 0.8.0 marks `application/json+a2ui` as deprecated, but `create_a2ui_part` still writes it for v0.9, so the agent sets the type itself.
- `A2uiAgentConnector` drops the response metadata, so the app could not show the model call count with it. The app uses a small A2A client of its own (`app/lib/services/a2a_service.dart`) that sends the same extension header.

## Branches

Every step was checked out from its tag into a clean worktree and verified there.

| Step | Branch | Tag | Analyze | Format | flutter test | Web build | pytest | ruff | Screen |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `step-1-plain-text` | `step-1` (de4b0b4) | pass | pass | 10 pass | pass | n/a | n/a | `step-1-chat-text.png` |
| 2 | `step-2-catalog` | `step-2` (33b0cf2) | pass | pass | 53 pass | pass | catalog 55 | pass | `step-2-gallery.png` |
| 3 | `step-3-a2ui-local` | `step-3` (7c33199) | pass | pass | 74 pass | pass | catalog 55 | pass | `step-3-chat-both.png` |
| 4 | `step-4-a2ui-agent` | `step-4` (2ebe8ec) | pass | pass | 87 pass | pass | catalog 55, agent 61 | pass | `step-4-chat-live.png` |
| 5 | `step-5-mcp-surfaces` | `step-5` (bf733d2) | pass | pass | 99 pass | pass | catalog 55, agent 61, mcp 49 | pass | `step-5-home-live.png`, `step-5-search-live.png` |
| 6 | `step-6-explore-freeze` | `step-6` (bbc21d2) | pass | pass | 99 pass | pass | catalog 55, agent 76, mcp 49 | pass | `step-6-chat-template-live.png` |
| main | `main` | none | pass | pass | 99 pass | pass | catalog 55, agent 76, mcp 49 | pass | `docs/screens/` |

What each step adds:

1. A plain text chat that answers from the recorded fixtures' text.
2. The catalog, the catalog widgets and a static gallery.
3. A2UI from fixtures in Chat with genui, the text and A2UI toggle, and side-by-side view.
4. The agent over A2A. It replays recorded fixtures (`source: recorded`), sends anything else to Gemini in live mode, and validates everything.
5. The MCP server, with the Home and Search tabs.
6. Template routing with data functions, the surface log, `freeze.py`, and the frozen rainy day example.

`git diff step-3-a2ui-local step-4-a2ui-agent` is a good slide source.

## Screenshots

All of these are in `projects/siargao-genui/docs/screens/`.

- **Offline, 1440x900:** `chat-text-1440.png`, `chat-a2ui-1440.png`, `chat-both-1440.png`, `home-1440.png`, `search-1440.png`, `gallery-1440.png`
- **Offline, 390x844 (2x):** `chat-text-390.png`, `chat-a2ui-390.png`, `home-390.png`, `search-390.png`, `gallery-390.png`
- **Live against local servers:** `live/chat-both-1440.png`, `live/chat-a2ui-390.png`, `live/home-1440.png`, `live/home-390.png`, `live/search-1440.png`, `live/search-390.png`
- **Per step:** `steps/step-1-chat-text.png` through `steps/step-6-chat-template-live.png`
- **Goldens, one per catalog widget:** `app/test/goldens/`

I reviewed every screenshot. There is no overflow, no clipped text and no red error box, and placeholders keep their aspect ratios. Small things left as they are:

- At 390 px wide the plain text heading "Your first Siargao trip (4 days, mid budget)" breaks after "(4".
- The 16:9 hero image is tall inside the chat columns at 1440. Real photos will look better there than the placeholder does.
- The prompt chips at 390 px scroll sideways, so the second chip is cut at the edge.
- The step 1 caption reads "0 model calls · template", although templates only arrive in step 6.

## Deploy tomorrow (you run these)

Shortcut: `./deploy.sh` in `projects/siargao-genui/` asks the questions below and runs all of it after you type `deploy`. `DRY_RUN=1 ./deploy.sh` previews it. The manual steps:

Each `deploy.sh` refuses to run unless `CONFIRM_DEPLOY=yes` is set. The APIs these need are already enabled in `devfest-genui-manila`: Cloud Run, Cloud Build, Artifact Registry and Vertex AI. I checked this read-only.

```sh
# 0. Auth and project
gcloud auth login
gcloud config set project devfest-genui-manila
cd ~/Desktop/a2ui/projects/siargao-genui

# 1. Run the checks once more
(cd agent && .venv/bin/pytest -q) && (cd mcp && .venv/bin/pytest -q)

# 2. Let the Cloud Run runtime service account call Gemini (only if the first live call returns 403)
PROJECT_NUMBER=$(gcloud projects describe devfest-genui-manila --format='value(projectNumber)')
gcloud projects add-iam-policy-binding devfest-genui-manila \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/aiplatform.user"

# 3. Deploy the agent (siargao-agent, asia-southeast1, live mode, gemini-3.5-flash @ global)
cd agent && CONFIRM_DEPLOY=yes ./deploy.sh
AGENT_URL=$(gcloud run services describe siargao-agent --region asia-southeast1 --format 'value(status.url)')
.venv/bin/python scripts/smoke.py "$AGENT_URL"
cd ..

# 4. Deploy the MCP server (siargao-mcp)
cd mcp && CONFIRM_DEPLOY=yes ./deploy.sh
MCP_BASE=$(gcloud run services describe siargao-mcp --region asia-southeast1 --format 'value(status.url)')
.venv/bin/python scripts/smoke.py "$MCP_BASE"
cd ..

# 5. Optional: host the Flutter web app on Cloud Run too (siargao-web)
cd app/web_deploy && CONFIRM_DEPLOY=yes AGENT_URL="$AGENT_URL" MCP_URL="$MCP_BASE/mcp" ./deploy.sh
cd ../..

# 6. Or run the app locally against the deployed services
cd app && flutter run -d chrome --dart-define=DEMO_MODE=live \
  --dart-define=AGENT_URL="$AGENT_URL" --dart-define=MCP_URL="$MCP_BASE/mcp"
```

Things that can come up during deploy:

- **Artifact Registry prompt:** the first `--source` deploy asks to create the `cloud-run-source-deploy` repository in Artifact Registry. Answer yes.
- **Cloud Build permission error:** if the build fails on permissions, the default compute service account may need `roles/run.builder`. Grant it with `gcloud projects add-iam-policy-binding devfest-genui-manila --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" --role="roles/run.builder"`, then rerun.
- **Model not found:** if the first live request fails with model not found, redeploy with `GEMINI_MODEL=<id> CONFIRM_DEPLOY=yes ./deploy.sh`, or try `GEMINI_LOCATION=us-central1`. The overnight test of `gemini-3.5-flash` at `global` worked from a laptop with ADC.
- **Region:** Cloud Run runs in `asia-southeast1`. The model call goes to the Vertex `global` endpoint.

## Needs your decision

1. **Public services.** All three deploy scripts use `--allow-unauthenticated`, because the Flutter web app calls the services straight from the browser. That is simple for a talk, but anyone with the URL can spend Gemini calls through the agent. Options:
   - keep it public and set `--max-instances 3` (already set);
   - put the agent behind IAP or an API key;
   - deploy the agent with `SIARGAO_MODE=offline` and switch it to live only for the demo slot.
2. **A dedicated service account** for the agent instead of the default compute account. It is cleaner, but it needs IAM changes I did not make.
3. **Photos.** Generate or shoot the 14 images in `catalog/images.json`. The placeholders are fine, but photos sell the demo.
4. **genui redesign.** genui is moving to `a2ui_core`, `a2ui_agent` and `a2ui_flutter`. The demo is pinned to 0.10.4, which works. Decide whether to mention the move in the talk.
5. **Gemini model.** `gemini-3.5-flash` is ADK's default and worked. google-genai also lists newer `gemini-3.6/3.7/3.8-flash` ids, which were not tested.
6. **Untracked files.** `CLAUDE.md`, `MCP-SETUP.md`, `.mcp.json` and `.claude/` at the repo root were left untracked, as I found them.

## Where things are

- `docs/CONTRACT.md`: the shared wire contract (catalog id, fixture format, ports, metadata, MCP shapes).
- `docs/ARCHITECTURE.md`: how the pieces fit together.
- `docs/RUNBOOK.md`: setup, run, test, freeze and screenshot commands.
- `catalog/README.md`, `agent/README.md`, `mcp/README.md` and `app/CLAUDE.md` cover each project.
