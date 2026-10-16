"""The A2A Starlette app: agent card, JSON-RPC endpoint, health check, CORS."""

from __future__ import annotations

import logging
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
from starlette.responses import JSONResponse
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

    routes = [
        Route(AGENT_CARD_WELL_KNOWN_PATH, agent_card, methods=["GET"]),
        Route(PREV_AGENT_CARD_WELL_KNOWN_PATH, agent_card, methods=["GET"]),
        Route("/healthz", healthz, methods=["GET"]),
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
