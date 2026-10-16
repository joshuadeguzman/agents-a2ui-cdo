"""A2A AgentExecutor: turns an A2A request into a Planner request and back.

Event sequence per request (what genui_a2a 0.10.1 expects):

1. A Task event (kind "task", state submitted). genui_a2a maps it to a status
   update with no message.
2. One TaskStatusUpdateEvent (kind "status-update", state completed,
   final true) whose status.message holds the answer: one DataPart per A2UI
   message (createSurface, updateComponents, updateDataModel) or one markdown
   TextPart, with metadata.siargao on the message.

The executor never enqueues a bare Message: genui_a2a's stream parser throws on
kind "message".
"""

from __future__ import annotations

import logging
import uuid
from typing import Any

from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater
from a2a.types import (
    AgentCard,
    DataPart,
    Message,
    Part,
    Role,
    Task,
    TaskState,
    TaskStatus,
    TextPart,
    UnsupportedOperationError,
)
from a2a.utils.errors import ServerError
from a2ui.a2a import try_activate_a2ui_extension

from .config import A2UI_MIME_TYPE
from .planner import Planner, Reply, Request

logger = logging.getLogger(__name__)


def _siargao_meta(context: RequestContext) -> dict[str, Any]:
    msg = context.message
    for source in (msg.metadata if msg else None, context.metadata):
        if isinstance(source, dict) and isinstance(source.get("siargao"), dict):
            return source["siargao"]
    return {}


def parse_request(context: RequestContext) -> Request:
    meta = _siargao_meta(context)
    texts: list[str] = []
    action: dict[str, Any] | None = None
    for part in context.message.parts if context.message else []:
        root = part.root
        if isinstance(root, TextPart) and root.text.strip():
            texts.append(root.text.strip())
        elif isinstance(root, DataPart):
            data = root.data or {}
            if isinstance(data.get("action"), dict):
                action = data["action"]
            elif isinstance(data.get("userAction"), dict):  # A2UI v0.8 shape
                action = data["userAction"]
    fmt = str(meta.get("responseFormat") or "a2ui").lower()
    intent = meta.get("intent")
    return Request(
        prompt="\n".join(texts),
        response_format="text" if fmt == "text" else "a2ui",
        intent=intent if isinstance(intent, str) and intent else None,
        action=action,
    )


def reply_parts(reply: Reply) -> list[Part]:
    if reply.format == "a2ui":
        return [Part(root=DataPart(data=m, metadata={"mimeType": A2UI_MIME_TYPE})) for m in reply.messages]
    return [Part(root=TextPart(text=reply.text))]


class SiargaoExecutor(AgentExecutor):
    def __init__(self, planner: Planner, agent_card: AgentCard):
        self.planner = planner
        self.agent_card = agent_card

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        try_activate_a2ui_extension(context, self.agent_card)
        req = parse_request(context)
        logger.info(
            "request: intent=%s format=%s action=%s prompt=%r",
            req.intent,
            req.response_format,
            bool(req.action),
            req.prompt[:120],
        )

        task = context.current_task
        if task is None:
            task = Task(
                id=context.task_id or str(uuid.uuid4()),
                context_id=context.context_id or str(uuid.uuid4()),
                status=TaskStatus(state=TaskState.submitted),
                history=[context.message] if context.message else [],
            )
            await event_queue.enqueue_event(task)

        reply = await self.planner.respond(req)
        logger.info("reply: %s", reply.metadata)
        message = Message(
            role=Role.agent,
            parts=reply_parts(reply),
            message_id=str(uuid.uuid4()),
            task_id=task.id,
            context_id=task.context_id,
            metadata={"siargao": reply.metadata},
        )
        updater = TaskUpdater(event_queue, task.id, task.context_id)
        await updater.update_status(TaskState.completed, message=message, final=True)

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        raise ServerError(error=UnsupportedOperationError())
