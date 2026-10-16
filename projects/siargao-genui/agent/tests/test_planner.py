from __future__ import annotations

import json
import subprocess
import sys

from conftest import AGENT_DIR, live_planner, load_fixture, make_stub_llm, model_answer, read_log

from siargao_agent.planner import MODEL_FAILED_TEXT, OFFLINE_TEXT, Request


def _food_guide_messages(store):
    """A valid surface with a model-chosen surfaceId, built from a template."""
    raw = json.dumps(store.render("surf_this_week").messages).replace('"surf_this_week"', '"food_guide"')
    return json.loads(raw)


async def test_template_reply_and_log(planner, log_path):
    fixture = load_fixture("first_time_trip")
    reply = await planner.respond(Request(prompt=fixture["prompt"], intent="first_time_trip"))
    assert reply.format == "a2ui"
    assert reply.messages == fixture["messages"]
    meta = reply.metadata
    assert meta["intent"] == "first_time_trip"
    assert meta["source"] == "template"
    assert meta["modelCalls"] == 0
    assert meta["valid"] is True
    assert isinstance(meta["latencyMs"], int)
    (entry,) = read_log(log_path)
    assert entry["intent"] == "first_time_trip"
    assert entry["template"] == "first_time_trip"
    assert entry["model"] is None
    assert entry["messages"] == fixture["messages"]
    for key in ("timestamp", "prompt", "source", "latencyMs", "valid", "modelCalls"):
        assert key in entry


async def test_text_format_returns_template_markdown(planner):
    fixture = load_fixture("surf_this_week")
    reply = await planner.respond(Request(prompt=fixture["prompt"], response_format="text"))
    assert reply.format == "text"
    assert reply.text == fixture["text"]
    assert reply.messages == []
    assert reply.metadata["intent"] == "surf_this_week"


async def test_offline_unknown_prompt_gets_text_and_no_model(planner, log_path):
    reply = await planner.respond(Request(prompt="Where can I get the best lechon?"))
    assert reply.format == "text"
    assert reply.text == OFFLINE_TEXT
    assert reply.metadata["modelCalls"] == 0
    assert reply.metadata["intent"] == "unknown"
    assert read_log(log_path)[0]["modelCalls"] == 0


def test_offline_never_imports_the_model_stack(tmp_path):
    code = (
        "import asyncio, sys\n"
        "from siargao_agent.config import Settings\n"
        "from siargao_agent.server import build_app\n"
        "from siargao_agent.planner import Request\n"
        f"app = build_app(Settings(mode='offline', surface_log=__import__('pathlib').Path({str(tmp_path)!r}) / 'l'))\n"
        "p = app.state.planner\n"
        "asyncio.run(p.respond(Request(prompt='what is the meaning of life')))\n"
        "asyncio.run(p.respond(Request(prompt='Flights to Siargao under 8,000')))\n"
        "bad = [m for m in sys.modules if m.startswith(('google.adk', 'google.genai'))]\n"
        "print('LOADED', bad)\n"
        "sys.exit(1 if bad else 0)\n"
    )
    result = subprocess.run([sys.executable, "-c", code], cwd=AGENT_DIR, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


async def test_action_gets_confirmation(planner):
    action = {
        "name": "choose_stay",
        "sourceComponentId": "stay-2",
        "surfaceId": "stays_near_cloud9",
        "context": {"stayId": "cloud9-surf-cabins", "nights": 3},
        "timestamp": "2026-10-17T10:00:00Z",
    }
    reply = await planner.respond(Request(action=action))
    assert reply.format == "text"
    assert reply.text == "Saved Cloud 9 Surf Cabins for 3 nights."
    assert reply.metadata["intent"] == "stays_near_cloud9"
    assert reply.metadata["modelCalls"] == 0


async def test_flight_action(planner):
    action = {"name": "choose_flight", "surfaceId": "flights_under_8000", "context": {"flightId": "ceb-iao-morning"}}
    reply = await planner.respond(Request(action=action))
    assert reply.text == "Saved the Cebu to Siargao flight at PHP 2,980 one way (sample fare)."


async def test_valid_model_output_passes_through(settings, store, log_path):
    stub = make_stub_llm([model_answer(_food_guide_messages(store))])
    planner = live_planner(settings, store, stub)
    reply = await planner.respond(Request(prompt="Where should I eat in General Luna?"))
    assert reply.format == "a2ui"
    assert reply.metadata == {
        **reply.metadata,
        "intent": "food_guide",
        "source": "model",
        "modelCalls": 1,
        "valid": True,
    }
    assert reply.messages == _food_guide_messages(store)
    assert stub.calls == 1
    # The SDK-generated system prompt carries our catalog and rules.
    assert "siargao-genui.example/catalogs/v1/catalog.json" in stub.system_prompts[0]
    assert "RULES FOR THE SIARGAO CATALOG" in stub.system_prompts[0]
    (entry,) = read_log(log_path)
    assert entry["source"] == "model" and entry["model"] == "stub-llm" and entry["valid"] is True


async def test_invalid_model_output_falls_back_to_text(settings, store, log_path):
    bad = _food_guide_messages(store)
    bad[1]["updateComponents"]["components"][0]["children"].append("missing-child")
    stub = make_stub_llm([model_answer(bad)])
    planner = live_planner(settings, store, stub)
    reply = await planner.respond(Request(prompt="Where should I eat in General Luna?"))
    assert reply.format == "text"
    assert reply.text == MODEL_FAILED_TEXT
    assert reply.metadata["valid"] is False
    assert reply.metadata["modelCalls"] == 1
    assert stub.calls == 1
    (entry,) = read_log(log_path)
    assert entry["valid"] is False
    assert any("missing-child" in e for e in entry["errors"])


async def test_unparseable_model_output_falls_back(settings, store):
    stub = make_stub_llm(["Sorry, I only speak prose."])
    reply = await live_planner(settings, store, stub).respond(Request(prompt="tell me a story"))
    assert reply.format == "text" and reply.metadata["valid"] is False and reply.metadata["modelCalls"] == 1


async def test_retry_is_capped_at_one_extra_call(settings, store):
    stub = make_stub_llm(["no json", model_answer(_food_guide_messages(store))])
    reply = await live_planner(settings, store, stub, retry=True).respond(Request(prompt="food?"))
    assert reply.format == "a2ui" and reply.metadata["modelCalls"] == 2 and stub.calls == 2

    stub = make_stub_llm(["no json"])
    reply = await live_planner(settings, store, stub, retry=True).respond(Request(prompt="food?"))
    assert reply.metadata["valid"] is False and reply.metadata["modelCalls"] == 2 and stub.calls == 2


async def test_model_em_dashes_are_rewritten(settings, store):
    messages = _food_guide_messages(store)
    messages[2]["updateDataModel"]["value"]["hero"]["title"] = "Eat " + chr(0x2014) + " drink"
    stub = make_stub_llm([model_answer(messages)])
    reply = await live_planner(settings, store, stub).respond(Request(prompt="food?"))
    assert reply.format == "a2ui"
    assert reply.messages[2]["updateDataModel"]["value"]["hero"]["title"] == "Eat, drink"


async def test_live_text_format_uses_model_text(settings, store):
    stub = make_stub_llm(["## Food in General Luna\n\n- Try kinilaw."])
    reply = await live_planner(settings, store, stub).respond(Request(prompt="food?", response_format="text"))
    assert reply.format == "text"
    assert reply.text.startswith("## Food in General Luna")
    assert reply.metadata["modelCalls"] == 1 and reply.metadata["source"] == "model"


async def test_templates_never_call_the_model_in_live_mode(settings, store):
    stub = make_stub_llm(["unused"])
    reply = await live_planner(settings, store, stub).respond(Request(prompt="Flights to Siargao under 8,000"))
    assert reply.metadata["source"] == "template" and stub.calls == 0
