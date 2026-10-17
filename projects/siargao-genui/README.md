# Siargao GenUI

Demo for the DevFest Manila talk "Powering Generative UI in the Cloud". A Siargao travel planner where an ADK agent sends A2UI v0.9 and a Flutter app renders it with its own widgets.

| Folder | What it is |
| --- | --- |
| `app/` | Flutter app (web, iOS, Android) built on the genui SDK |
| `agent/` | Python ADK agent that returns A2UI v0.9 over A2A |
| `mcp/` | MCP server with one static surface (resource) and one templated surface (tool) |
| `catalog/` | The widget catalog: names and JSON schemas, shared by app and agent |
| `fixtures/` | Recorded A2UI for every demo intent, used in offline mode |
| `docs/` | Contract, architecture, runbook, and the build report |

## Try it

```sh
./run.sh            # app on the iOS Simulator against Cloud Run (deploys first if needed)
./run.sh --local    # agent and MCP server on this Mac, no cloud
./run.sh --offline  # app only, recorded fixtures
./run.sh --help     # all options (--chrome, --redeploy, --setup)
```

It asks only for settings it has not saved yet (project, agent mode, Gemini API key or Vertex AI) and keeps them in `.env.local`, which git ignores. Nothing is deployed until you type `deploy`.

Start with `docs/RUNBOOK.md`. The shared rules live in `docs/CONTRACT.md`.
