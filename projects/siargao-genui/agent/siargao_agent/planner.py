"""Decide how to answer one request and build the reply. No A2A types here.

respond() is the whole policy:

1. A user action gets a short text confirmation.
2. Otherwise route the prompt (metadata intent, keywords, then the model).
3. A template renders, then validates; responseFormat "text" returns its
   markdown instead.
4. The model path runs only in live mode. Offline, unrouted prompts get a
   polite text reply and modelCalls 0.
5. Every surface is validated; an invalid one falls back to text with
   valid=false. Every reply is logged.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

from .actions import confirm_action
from .config import Settings
from .router import route
from .surface_log import SurfaceLog
from .templates import TemplateStore
from .validation import validate_messages

logger = logging.getLogger(__name__)

OFFLINE_TEXT = (
    "I can only answer the demo prompts right now, because the model is disabled in offline mode. "
    "Try: plan my first trip to Siargao, flights under 8,000, how's the surf this week, "
    "stays near Cloud 9, or flexible dates for a return trip."
)
MODEL_FAILED_TEXT = (
    "Sorry, I could not build a valid view for that just now. Try again, or pick one of the demo prompts."
)
UNKNOWN_INTENT = "unknown"


@dataclass
class Request:
    prompt: str = ""
    response_format: str = "a2ui"  # "a2ui" or "text"
    intent: str | None = None
    action: dict[str, Any] | None = None


@dataclass
class Reply:
    intent: str
    source: str  # "template" or "model"
    format: str  # "a2ui" or "text"
    messages: list[dict[str, Any]] = field(default_factory=list)
    text: str = ""
    model_calls: int = 0
    valid: bool = True
    latency_ms: int = 0
    producer: str = ""  # template name or model id
    errors: list[str] = field(default_factory=list)
    route_reason: str = ""

    @property
    def metadata(self) -> dict[str, Any]:
        """The metadata.siargao object from docs/CONTRACT.md."""
        return {
            "intent": self.intent,
            "source": self.source,
            "modelCalls": self.model_calls,
            "latencyMs": self.latency_ms,
            "valid": self.valid,
        }


class Planner:
    def __init__(
        self,
        settings: Settings,
        store: TemplateStore,
        surface_log: SurfaceLog,
        model_path_factory: Callable[[], Any] | None = None,
    ):
        self.settings = settings
        self.store = store
        self.log = surface_log
        self._model_path_factory = model_path_factory
        self._model_path: Any = None

    @property
    def model_path(self) -> Any:
        if self._model_path is None:
            if self._model_path_factory is None:
                raise RuntimeError("no model path configured")
            self._model_path = self._model_path_factory()
        return self._model_path

    async def respond(self, req: Request) -> Reply:
        start = time.perf_counter()
        try:
            reply = await self._respond(req)
        except Exception as e:
            logger.exception("request failed")
            reply = Reply(
                intent=req.intent or UNKNOWN_INTENT,
                source="template",
                format="text",
                text=MODEL_FAILED_TEXT,
                valid=False,
                errors=[f"{type(e).__name__}: {e}"],
            )
        reply.latency_ms = round((time.perf_counter() - start) * 1000)
        self._write_log(req, reply)
        return reply

    async def _respond(self, req: Request) -> Reply:
        if req.action is not None:
            return Reply(
                intent=str(req.action.get("surfaceId") or req.intent or "action"),
                source="template",
                format="text",
                text=confirm_action(req.action),
                producer=f"action:{req.action.get('name')}",
                route_reason="action",
            )

        decision = route(req.prompt, self.store, req.intent)
        if decision.intent is not None:
            return self._from_template(decision.intent, req, decision.reason)
        if not self.settings.live:
            return Reply(
                intent=UNKNOWN_INTENT,
                source="template",
                format="text",
                text=OFFLINE_TEXT,
                producer="offline",
                route_reason="model-disabled",
            )
        return await self._from_model(req)

    def _from_template(self, intent: str, req: Request, reason: str) -> Reply:
        rendered = self.store.render(intent, req.prompt)
        base = {"intent": intent, "source": "template", "producer": intent, "route_reason": reason}
        if req.response_format == "text":
            return Reply(format="text", text=rendered.text, **base)
        tpl = self.store.get(intent)
        sid = tpl.create_surface.get("surfaceId") if tpl else intent
        errors = validate_messages(rendered.messages, surface_id=sid)
        if errors:
            logger.warning("template %s failed validation: %s", intent, errors)
            return Reply(
                format="text", text=rendered.text, valid=False, errors=errors, messages=rendered.messages, **base
            )
        return Reply(format="a2ui", messages=rendered.messages, text=rendered.text, **base)

    async def _from_model(self, req: Request) -> Reply:
        mp = self.model_path
        producer = str(getattr(mp, "model_name", self.settings.model))
        if req.response_format == "text":
            result = await mp.generate_text(req.prompt)
            return Reply(
                intent=UNKNOWN_INTENT,
                source="model",
                format="text",
                text=result.text if result.valid else MODEL_FAILED_TEXT,
                model_calls=result.model_calls,
                valid=result.valid,
                producer=producer,
                errors=result.errors,
                route_reason="model",
            )
        result = await mp.generate_surface(req.prompt)
        if result.valid:
            return Reply(
                intent=result.surface_id or UNKNOWN_INTENT,
                source="model",
                format="a2ui",
                messages=result.messages,
                text=result.text,
                model_calls=result.model_calls,
                producer=producer,
                route_reason="model",
            )
        return Reply(
            intent=result.surface_id or UNKNOWN_INTENT,
            source="model",
            format="text",
            text=MODEL_FAILED_TEXT,
            messages=result.messages,
            model_calls=result.model_calls,
            valid=False,
            producer=producer,
            errors=result.errors,
            route_reason="model",
        )

    def _write_log(self, req: Request, reply: Reply) -> None:
        self.log.write(
            {
                "intent": reply.intent,
                "prompt": req.prompt,
                "responseFormat": req.response_format,
                "action": req.action,
                "source": reply.source,
                "template": reply.producer if reply.source == "template" else None,
                "model": reply.producer if reply.source == "model" else None,
                "route": reply.route_reason,
                "format": reply.format,
                "latencyMs": reply.latency_ms,
                "valid": reply.valid,
                "modelCalls": reply.model_calls,
                "errors": reply.errors,
                "text": reply.text,
                "messages": reply.messages,
            }
        )
