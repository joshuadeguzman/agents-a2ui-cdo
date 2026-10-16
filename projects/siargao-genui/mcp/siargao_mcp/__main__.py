"""Run the server: python -m siargao_mcp (PORT env, default 10003)."""

import logging
import os

import uvicorn

from .server import create_app


def main() -> None:
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(levelname)s %(name)s: %(message)s")
    # Stateless mode logs "Terminating session: None" at INFO after every request.
    logging.getLogger("mcp.server.streamable_http").setLevel(logging.WARNING)
    port = int(os.environ.get("PORT", "10003"))
    host = os.environ.get("HOST", "0.0.0.0")
    uvicorn.run(create_app(), host=host, port=port, log_level="info", proxy_headers=True, forwarded_allow_ips="*")


if __name__ == "__main__":
    main()
