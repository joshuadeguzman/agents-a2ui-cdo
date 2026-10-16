# Examples

`live_surface_rainy_day.jsonl` is one real log line from `logs/surfaces.jsonl`, recorded on 2026-10-17 with `SIARGAO_MODE=live` and `gemini-3.5-flash` on Vertex AI (location `global`). The model built the surface in 15.9 s with 1 model call, and it passed catalog validation.

It was promoted to a template with:

```sh
.venv/bin/python scripts/freeze.py --log examples/live_surface_rainy_day.jsonl --line 1 \
  --intent rainy_day_general_luna --keywords "rainy,rain day"
```

That wrote `templates/rainy_day_general_luna.json` and `data/rainy_day_general_luna.json`. The prompt "What should we do on a rainy day in General Luna?" now routes to the template offline: 0 model calls, about 45 ms.
