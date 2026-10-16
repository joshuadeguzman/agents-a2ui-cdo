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

Start with `docs/RUNBOOK.md`. The shared rules live in `docs/CONTRACT.md`.
