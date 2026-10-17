"""The A2A Starlette app: agent card, JSON-RPC endpoint, health check, CORS."""

from __future__ import annotations

import html
import logging
import os
import time
from collections.abc import Callable
from typing import Any

from a2a.server.apps import A2AStarletteApplication
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import AgentCapabilities, AgentCard, AgentSkill
from a2a.utils.constants import AGENT_CARD_WELL_KNOWN_PATH, PREV_AGENT_CARD_WELL_KNOWN_PATH
from a2ui.a2a import get_a2ui_agent_extension
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import HTMLResponse, JSONResponse
from starlette.routing import Route

from . import __version__
from .config import A2UI_MIME_TYPE, CATALOG_ID, Settings
from .executor import SiargaoExecutor
from .planner import Planner
from .surface_log import SurfaceLog
from .templates import TemplateStore
from .validation import sdk_catalog

logger = logging.getLogger(__name__)

SKILL_EXAMPLES = {
    "first_time_trip": "Plan my first trip to Siargao, 4 days, mid budget",
    "returning_flexible": "I've been to Siargao before. My dates are flexible. Where should I go this time?",
    "flights_under_8000": "Flights to Siargao under 8,000",
    "surf_this_week": "How's the surf in Siargao this week?",
    "stays_near_cloud9": "Stays near Cloud 9 for 3 nights under 4,500",
}


def build_agent_card(settings: Settings, store: TemplateStore | None = None) -> AgentCard:
    extension = get_a2ui_agent_extension("0.9", supported_catalog_ids=[CATALOG_ID])
    skill = AgentSkill(
        id="plan_siargao_trip",
        name="Plan a Siargao trip",
        description=(
            "Plans trips to Siargao, Philippines: itineraries, flights, stays, surf and spots. Answers with A2UI "
            "v0.9 surfaces for the Siargao catalog, or markdown when metadata.siargao.responseFormat is text."
        ),
        tags=["travel", "siargao", "a2ui"],
        examples=list(SKILL_EXAMPLES.values()),
    )
    return AgentCard(
        name="Siargao Planner",
        description=(
            "Siargao travel planner for the 'Powering Generative UI in the Cloud' demo. Templates first, Gemini "
            f"for everything else (mode: {settings.mode})."
        ),
        url=settings.base_url,
        version=__version__,
        default_input_modes=["text/plain"],
        default_output_modes=["text/plain", A2UI_MIME_TYPE],
        capabilities=AgentCapabilities(streaming=True, extensions=[extension]),
        skills=[skill],
    )


STARTED_AT = time.time()

PAGE_STYLE = """
body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;margin:0;background:#f6f8f8;color:#1a1c1e}
main{max-width:760px;margin:48px auto;padding:0 24px}
h1{font-size:40px;margin:0 0 4px}
.sub{color:#4a5557;font-size:20px;margin:0 0 28px}
.ok{display:inline-block;background:#d5eef0;color:#00363a;border-radius:99px;padding:6px 14px;
  font-weight:600;margin-bottom:20px}
table{border-collapse:collapse;width:100%;background:#fff;border:1px solid #dde3e4;border-radius:16px;overflow:hidden}
td{padding:12px 16px;border-top:1px solid #dde3e4;font-size:18px;vertical-align:top}
tr:first-child td{border-top:0}
td:first-child{color:#4a5557;width:34%}
code{font-family:ui-monospace,Menlo,monospace;font-size:16px}
a{color:#00676e}
.note{color:#4a5557;margin-top:20px;font-size:16px}
"""


def status_page(title: str, subtitle: str, rows: list[tuple[str, str]], note: str) -> HTMLResponse:
    """A small status page for people who open the service URL in a browser.

    Values are escaped; a value wrapped in <a ...> by the caller is passed
    through as is.
    """
    body = "".join(f"<tr><td>{html.escape(k)}</td><td>{v}</td></tr>" for k, v in rows)
    return HTMLResponse(
        "<!doctype html><html lang=en><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'>"
        f"<title>{html.escape(title)}</title><style>{PAGE_STYLE}</style></head><body><main>"
        f"<h1>{html.escape(title)}</h1><p class=sub>{html.escape(subtitle)}</p>"
        f"<span class=ok>Running</span><table>{body}</table><p class=note>{html.escape(note)}</p>"
        "</main></body></html>"
    )


def _uptime() -> str:
    seconds = int(time.time() - STARTED_AT)
    hours, rest = divmod(seconds, 3600)
    return f"{hours} h {rest // 60} min" if hours else f"{rest // 60} min {rest % 60} s"


def default_model_path_factory(settings: Settings, store: TemplateStore) -> Callable[[], Any]:
    def factory() -> Any:
        from .model_path import ModelPath, default_model

        return ModelPath(default_model(settings.model), store, retry=settings.model_retry)

    return factory


def build_app(
    settings: Settings | None = None,
    *,
    model_path_factory: Callable[[], Any] | None = None,
    store: TemplateStore | None = None,
) -> Starlette:
    settings = settings or Settings.from_env()
    store = store or TemplateStore(settings.templates_dir, settings.data_dir)
    if model_path_factory is None and settings.live:
        model_path_factory = default_model_path_factory(settings, store)
    planner = Planner(settings, store, SurfaceLog(settings.surface_log), model_path_factory)
    card = build_agent_card(settings, store)
    a2a_app = A2AStarletteApplication(
        agent_card=card,
        http_handler=DefaultRequestHandler(
            agent_executor=SiargaoExecutor(planner, card),
            task_store=InMemoryTaskStore(),
        ),
    )

    async def agent_card(request: Request) -> JSONResponse:
        # Serve the card with the URL the client actually used unless
        # PUBLIC_URL pins it, so it is right on Cloud Run without a redeploy.
        url = settings.base_url if settings.base_url_pinned else str(request.base_url).rstrip("/")
        body = card.model_copy(update={"url": url}).model_dump(mode="json", by_alias=True, exclude_none=True)
        return JSONResponse(body)

    async def healthz(_request: Request) -> JSONResponse:
        return JSONResponse({"ok": True, "mode": settings.mode, "templates": store.intents})

    async def home(request: Request) -> HTMLResponse:
        # Browsers send GET. The A2A endpoint at the same path only takes POST.
        base = str(request.base_url).rstrip("/")
        e = html.escape
        model = f"{settings.model} (Gemini)" if settings.live else "none, templates only"
        rows = [
            ("Cloud Run service", f"<code>{e(os.environ.get('K_SERVICE', 'local'))}</code>"),
            ("Revision", f"<code>{e(os.environ.get('K_REVISION', 'local'))}</code>"),
            ("Instance up for", e(_uptime())),
            (
                "Protocol",
                "A2A 0.3 JSON-RPC (<code>message/send</code>, <code>message/stream</code>) "
                "with the A2UI v0.9 extension",
            ),
            ("Mode", e(settings.mode)),
            ("Model", e(model)),
            ("Frozen templates", e(f"{len(store.intents)} ({', '.join(store.intents)})")),
            ("Agent card", f"<a href='{e(base)}{AGENT_CARD_WELL_KNOWN_PATH}'>{e(AGENT_CARD_WELL_KNOWN_PATH)}</a>"),
            ("Health", f"<a href='{e(base)}/healthz'>/healthz</a>"),
        ]
        return status_page(
            "Siargao Planner",
            "A2UI agent, deployed on Google Cloud Run",
            rows,
            "This page is for browsers. The app talks to this same URL with POST requests.",
        )

    routes = [
        Route(AGENT_CARD_WELL_KNOWN_PATH, agent_card, methods=["GET"]),
        Route(PREV_AGENT_CARD_WELL_KNOWN_PATH, agent_card, methods=["GET"]),
        Route("/healthz", healthz, methods=["GET"]),
        Route("/", home, methods=["GET"]),
        *a2a_app.routes(),
    ]
    app = Starlette(
        routes=routes,
        middleware=[
            Middleware(
                CORSMiddleware,
                allow_origins=["*"],
                allow_methods=["*"],
                allow_headers=["*"],
                expose_headers=["*"],
            )
        ],
    )
    # Warm up: load the SDK catalog now, not on the first request; build the
    # model path in live mode (no model call happens here).
    sdk_catalog()
    if settings.live and model_path_factory is not None:
        planner.model_path  # noqa: B018
    app.state.planner = planner
    app.state.settings = settings
    app.state.agent_card = card
    logger.info("Siargao agent ready: mode=%s templates=%s", settings.mode, store.intents)
    return app
