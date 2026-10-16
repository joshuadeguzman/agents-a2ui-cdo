"""Promote a logged surface to a frozen template.

    python scripts/freeze.py --log logs/surfaces.jsonl --line N --intent my_intent [--keywords "a,b"]

Writes templates/<intent>.json (createSurface + updateComponents, with
surfaceId set to the intent and component ids normalised to kebab-case) and
data/<intent>.json (the updateDataModel value). The surface is validated
first, and existing files are kept unless you pass --force. Restart the agent
to serve the new template; it is routed by --keywords (plain substrings) or by
metadata.siargao.intent.

Run from agent/ with the agent venv: .venv/bin/python scripts/freeze.py ...
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

AGENT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(AGENT_DIR))

from siargao_agent.config import DEFAULT_DATA_DIR, DEFAULT_TEMPLATES_DIR  # noqa: E402
from siargao_agent.freezer import FreezeError, freeze  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--log", type=Path, required=True, help="surface log (JSONL)")
    parser.add_argument("--line", type=int, required=True, help="1-based line number in the log")
    parser.add_argument("--intent", required=True, help="snake_case intent name; becomes the surfaceId")
    parser.add_argument("--keywords", default="", help="comma separated routing keywords")
    parser.add_argument("--title", default=None, help="template title (default from the intent)")
    parser.add_argument("--text", default=None, help="markdown for responseFormat text (default: the logged text)")
    parser.add_argument("--templates-dir", type=Path, default=DEFAULT_TEMPLATES_DIR)
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--force", action="store_true", help="overwrite an existing template")
    args = parser.parse_args(argv)

    try:
        result = freeze(
            args.log,
            args.line,
            args.intent,
            templates_dir=args.templates_dir,
            data_dir=args.data_dir,
            keywords=args.keywords.split(","),
            title=args.title,
            text=args.text,
            force=args.force,
        )
    except FreezeError as e:
        print(f"freeze: {e}", file=sys.stderr)
        return 1
    print(f"wrote {result.template_path}")
    print(f"wrote {result.data_path}")
    renamed = {k: v for k, v in result.id_map.items() if k != v}
    if renamed:
        print(f"renamed component ids: {renamed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
