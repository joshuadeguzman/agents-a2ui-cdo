"""The model path: an ADK LlmAgent that writes A2UI for prompts no template covers.

The system prompt comes from the a2ui SDK (a2ui-agent-sdk 0.8.0):
DirectJsonFormat([catalog]).prompt_generator.generate(...) with
include_schema=True. That embeds the v0.9 agent-to-renderer schema, the common
types and our catalog, and adds the SDK's workflow rules (wrap JSON in
<a2ui-json> tags). Our catalog/rules.txt, the image keys and two rendered
templates as examples are added on top.

The answer is split with the SDK parser (DirectJsonFormat.parser.unwrap plus
a2ui.parser.parse_and_fix), lightly repaired (missing "version", em dashes) and
then validated by validation.validate_messages, same as every template.

Nothing here imports google.adk at module import time, so offline mode never
loads the model stack.
"""

from __future__ import annotations

import json
import logging
import os
import uuid
from dataclasses import dataclass, field
from typing import Any

from .config import A2UI_VERSION, CATALOG_ID, IMAGES_PATH, RULES_PATH
from .templates import TemplateStore
from .validation import message_kind, sdk_catalog, validate_messages

logger = logging.getLogger(__name__)

APP_NAME = "siargao"
USER_ID = "siargao-app"
EXAMPLE_INTENTS = ("surf_this_week", "stays_near_cloud9")
EM_DASH = chr(0x2014)

ROLE_DESCRIPTION = (
    "You are a friendly travel planner for Siargao island in the Philippines. You answer every request with "
    "one A2UI v0.9 surface that a Flutter app renders with the Siargao widget catalog, plus one short sentence "
    "of plain text before it."
)

WORKFLOW = f"""
- Reply with exactly one <a2ui-json> block. Inside it put a JSON array of exactly three messages:
  createSurface (catalogId "{CATALOG_ID}"), updateComponents, then updateDataModel with path "/" and the whole
  data model as value.
- Every message has "version": "{A2UI_VERSION}".
- Pick the surfaceId yourself: a short snake_case name for the request, for example "siargao_food_guide".
  Use the same surfaceId in all three messages.
- Before the block write one short, friendly sentence. Do not write anything after the block.
- Content is sample travel information for a demo. Keep prices realistic sample prices in PHP.
"""

TEXT_INSTRUCTION = (
    "You are a friendly travel planner for Siargao island in the Philippines. Answer in short markdown: a "
    "heading, two to five short sections or bullet lists, sample prices in PHP written like PHP 4,500. Say that "
    "prices are sample prices. Plain, friendly English. Never use em dashes. Do not output JSON."
)


def _images_block() -> str:
    images = json.loads(IMAGES_PATH.read_text(encoding="utf-8"))["images"]
    lines = [f'- "{img["key"]}": {img["alt"]}' for img in images]
    return "Image keys you may use (and no others):\n" + "\n".join(lines)


def _examples_block(store: TemplateStore | None) -> str:
    if store is None:
        return ""
    blocks = []
    for intent in EXAMPLE_INTENTS:
        if intent in store:
            rendered = store.render(intent)
            body = json.dumps(rendered.messages, ensure_ascii=False, separators=(",", ":"))
            blocks.append(f"---BEGIN {intent}---\n<a2ui-json>{body}</a2ui-json>\n---END {intent}---")
    if not blocks:
        return ""
    return "### Examples:\n" + "\n\n".join(blocks)


def build_system_prompt(store: TemplateStore | None = None) -> str:
    from a2ui.inference_formats import DirectJsonFormat

    fmt = DirectJsonFormat([sdk_catalog()])
    rules = RULES_PATH.read_text(encoding="utf-8").strip()
    prompt = fmt.prompt_generator.generate(
        role_description=ROLE_DESCRIPTION,
        workflow_description=WORKFLOW,
        ui_description=f"{rules}\n\n{_images_block()}",
        include_schema=True,
        include_examples=False,
    )
    examples = _examples_block(store)
    return f"{prompt}\n\n{examples}" if examples else prompt


def sanitize(text: str) -> str:
    """Rewrite em dashes the model may still produce."""
    return text.replace(f" {EM_DASH} ", ", ").replace(EM_DASH, ", ")


def sanitize_json(value: Any) -> Any:
    """sanitize() every string in a parsed JSON value (escaped dashes too)."""
    if isinstance(value, str):
        return sanitize(value)
    if isinstance(value, list):
        return [sanitize_json(v) for v in value]
    if isinstance(value, dict):
        return {k: sanitize_json(v) for k, v in value.items()}
    return value


def parse_model_output(content: str) -> tuple[str, list[dict[str, Any]], list[str]]:
    """Split a model answer into (text, A2UI messages, errors) with the SDK parser."""
    from a2ui.inference_formats import DirectJsonFormat
    from a2ui.parser import parse_and_fix

    fmt = DirectJsonFormat([sdk_catalog()])
    texts: list[str] = []
    messages: list[dict[str, Any]] = []
    try:
        parts = fmt.parser.unwrap(sanitize(content))
    except Exception as e:
        return sanitize(content).strip(), [], [f"parse: {type(e).__name__}: {e}"]
    for part in parts:
        if part.text and part.text.strip():
            texts.append(part.text.strip())
        if part.a2ui_raw is None:
            continue
        try:
            payload = sanitize_json(parse_and_fix(part.a2ui_raw))
        except Exception as e:
            return " ".join(texts), [], [f"parse: {type(e).__name__}: {e}"]
        items = payload if isinstance(payload, list) else [payload]
        for item in items:
            if isinstance(item, dict) and message_kind(item) and "version" not in item:
                item = {"version": A2UI_VERSION, **item}
            messages.append(item)
    return " ".join(texts), messages, []


@dataclass
class ModelResult:
    messages: list[dict[str, Any]] = field(default_factory=list)
    text: str = ""
    raw: str = ""
    model_calls: int = 0
    valid: bool = False
    errors: list[str] = field(default_factory=list)

    @property
    def surface_id(self) -> str | None:
        for m in self.messages:
            kind = message_kind(m)
            if kind and isinstance(m[kind], dict):
                return m[kind].get("surfaceId")
        return None


def default_model(model_name: str) -> Any:
    """The live model: Gemini on Vertex AI (or the Gemini API) via google-adk."""
    from google.adk.models import Gemini

    return Gemini(model=model_name)


def _generate_config() -> Any:
    from google.genai import types

    level = os.environ.get("GEMINI_THINKING_LEVEL", "low").strip().upper()
    kwargs: dict[str, Any] = {"temperature": 0.4}
    if level:
        kwargs["thinking_config"] = types.ThinkingConfig(thinking_level=level)
    return types.GenerateContentConfig(**kwargs)


class ModelPath:
    """Runs one LlmAgent per request kind and returns validated A2UI."""

    def __init__(self, model: Any, store: TemplateStore | None = None, *, retry: bool = False):
        from google.adk.agents import LlmAgent
        from google.adk.runners import InMemoryRunner

        self.model = model
        self.model_name = model if isinstance(model, str) else getattr(model, "model", type(model).__name__)
        self.retry = retry
        self.system_prompt = build_system_prompt(store)
        config = _generate_config()
        # Instructions are callables so ADK skips {state} injection: the
        # prompt is full of JSON braces.
        self._ui_agent = LlmAgent(
            name="siargao_planner",
            model=model,
            instruction=lambda _ctx: self.system_prompt,
            generate_content_config=config,
        )
        self._text_agent = LlmAgent(
            name="siargao_text",
            model=model,
            instruction=lambda _ctx: TEXT_INSTRUCTION,
            generate_content_config=config,
        )
        self._ui_runner = InMemoryRunner(agent=self._ui_agent, app_name=APP_NAME)
        self._text_runner = InMemoryRunner(agent=self._text_agent, app_name=APP_NAME)

    async def _call(self, runner: Any, agent_name: str, prompt: str) -> str:
        """One model call; returns the final text of the turn."""
        from google.adk.agents.run_config import RunConfig, StreamingMode
        from google.genai import types

        session = await runner.session_service.create_session(
            app_name=APP_NAME, user_id=USER_ID, session_id=uuid.uuid4().hex
        )
        chunks: list[str] = []
        async for event in runner.run_async(
            user_id=USER_ID,
            session_id=session.id,
            new_message=types.Content(role="user", parts=[types.Part.from_text(text=prompt)]),
            run_config=RunConfig(streaming_mode=StreamingMode.NONE),
        ):
            if event.author != agent_name or event.partial or not event.content or not event.content.parts:
                continue
            chunks.extend(p.text for p in event.content.parts if p.text and not p.thought)
        return "".join(chunks)

    async def generate_surface(self, prompt: str) -> ModelResult:
        result = ModelResult()
        attempts = 2 if self.retry else 1
        query = prompt
        for _ in range(attempts):
            result.model_calls += 1
            try:
                raw = await self._call(self._ui_runner, self._ui_agent.name, query)
            except Exception as e:
                logger.warning("model call failed: %s", e)
                result.errors = [f"model call failed: {type(e).__name__}: {e}"]
                return result
            result.raw = raw
            text, messages, errors = parse_model_output(raw)
            result.text, result.messages = text, messages
            if not errors:
                errors = validate_messages(messages) if messages else ["no A2UI messages in the answer"]
            result.errors = errors
            result.valid = not errors
            if result.valid:
                return result
            query = (
                f"Your previous answer was not valid A2UI: {'; '.join(errors)[:1500]}. "
                f"Answer the original request again, following every rule. Original request: {prompt}"
            )
        return result

    async def generate_text(self, prompt: str) -> ModelResult:
        result = ModelResult(model_calls=1)
        try:
            raw = await self._call(self._text_runner, self._text_agent.name, prompt)
        except Exception as e:
            logger.warning("model call failed: %s", e)
            result.errors = [f"model call failed: {type(e).__name__}: {e}"]
            return result
        result.raw = raw
        result.text = sanitize(raw).strip()
        result.valid = bool(result.text)
        if not result.valid:
            result.errors = ["empty model answer"]
        return result
