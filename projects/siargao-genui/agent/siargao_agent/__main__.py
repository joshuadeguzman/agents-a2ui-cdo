"""Run the agent: python -m siargao_agent (PORT, default 10002, on 0.0.0.0)."""

from __future__ import annotations

import logging
import os

import uvicorn

from .config import Settings
from .server import build_app


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    settings = Settings.from_env()
    app = build_app(settings)
    uvicorn.run(
        app,
        host=os.environ.get("HOST", "0.0.0.0"),
        port=int(os.environ.get("PORT", "10002")),
        # Cloud Run terminates TLS; trust its X-Forwarded-* headers so the
        # agent card shows the https URL.
        proxy_headers=True,
        forwarded_allow_ips="*",
    )


if __name__ == "__main__":
    main()
