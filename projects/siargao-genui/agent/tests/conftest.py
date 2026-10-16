from __future__ import annotations

import json
from dataclasses import replace
from pathlib import Path
from typing import Any

import pytest

from siargao_agent.config import AGENT_DIR, DEFAULT_DATA_DIR, DEFAULT_TEMPLATES_DIR, Settings
from siargao_agent.planner import Planner
from siargao_agent.surface_log import SurfaceLog
from siargao_agent.templates import TemplateStore

PROJECT_DIR = AGENT_DIR.parent
FIXTURES_DIR = PROJECT_DIR / "fixtures"
FIXTURE_INTENTS = [
    "first_time_trip",
    "returning_flexible",
    "flights_under_8000",
    "surf_this_week",
    "home_first_run",
    "stays_near_cloud9",
]


def load_fixture(intent: str) -> dict[str, Any]:
    return json.loads((FIXTURES_DIR / f"{intent}.json").read_text(encoding="utf-8"))


def read_log(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


@pytest.fixture(scope="session")
def store() -> TemplateStore:
    return TemplateStore(DEFAULT_TEMPLATES_DIR, DEFAULT_DATA_DIR)


@pytest.fixture
def log_path(tmp_path: Path) -> Path:
    return tmp_path / "surfaces.jsonl"


@pytest.fixture
def settings(log_path: Path) -> Settings:
    return Settings(mode="offline", surface_log=log_path)


@pytest.fixture
def planner(settings: Settings, store: TemplateStore) -> Planner:
    return Planner(settings, store, SurfaceLog(settings.surface_log))


def make_stub_llm(responses: list[str]):
    """An ADK BaseLlm that returns canned text and counts calls. No network."""
    from google.adk.models._capabilities import LlmCapabilities
    from google.adk.models.base_llm import BaseLlm
    from google.adk.models.llm_response import LlmResponse
    from google.genai import types

    class StubLlm(BaseLlm):
        replies: list[str]
        calls: int = 0
        system_prompts: list[str] = []  # noqa: RUF012 - pydantic field, copied per instance

        @property
        def capabilities(self) -> LlmCapabilities:
            return LlmCapabilities(output_schema_and_tools=False)

        async def generate_content_async(self, llm_request, stream: bool = False):
            self.calls += 1
            self.system_prompts.append(str(llm_request.config.system_instruction or ""))
            text = self.replies[min(self.calls - 1, len(self.replies) - 1)]
            yield LlmResponse(content=types.Content(role="model", parts=[types.Part.from_text(text=text)]))

    return StubLlm(model="stub-llm", replies=responses)


def live_planner(settings: Settings, store: TemplateStore, stub, *, retry: bool = False) -> Planner:
    from siargao_agent.model_path import ModelPath

    live = replace(settings, mode="live", model_retry=retry)
    return Planner(live, store, SurfaceLog(live.surface_log), lambda: ModelPath(stub, store, retry=retry))


def model_answer(messages: list[dict[str, Any]], sentence: str = "Here is a food guide.") -> str:
    return f"{sentence}\n<a2ui-json>{json.dumps(messages)}</a2ui-json>"
