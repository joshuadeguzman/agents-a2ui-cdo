from __future__ import annotations

import sys

import httpx
import pytest
from conftest import AGENT_DIR, FIXTURE_INTENTS, load_fixture, read_log

from siargao_agent.config import CATALOG_ID, Settings
from siargao_agent.server import build_app

sys.path.insert(0, str(AGENT_DIR / "scripts"))
import smoke


@pytest.fixture
def app(log_path):
    return build_app(Settings(mode="offline", surface_log=log_path))


@pytest.fixture
async def client(app):
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as c:
        yield c


async def _stream(client, parts, metadata):
    resp = await client.post(
        "/",
        json=smoke.rpc_body("message/stream", parts, metadata),
        headers={**smoke.HEADERS, "Accept": "text/event-stream"},
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/event-stream")
    return resp.text, smoke.parse_sse(resp.text)


async def test_agent_card_advertises_a2ui_extension(client):
    card = (await client.get("/.well-known/agent-card.json")).json()
    exts = card["capabilities"]["extensions"]
    ext = next(e for e in exts if e["uri"] == "https://a2ui.org/a2a-extension/a2ui/v0.9")
    assert ext["params"]["supportedCatalogIds"] == [CATALOG_ID]
    assert card["capabilities"]["streaming"] is True
    assert card["url"] == "http://testserver"
    assert card["protocolVersion"]


async def test_cors_preflight_allows_any_origin_and_headers(client):
    resp = await client.options(
        "/",
        headers={
            "Origin": "http://localhost:8080",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type,x-a2a-extensions",
        },
    )
    assert resp.status_code == 200
    assert resp.headers["access-control-allow-origin"] == "*"
    assert "x-a2a-extensions" in resp.headers["access-control-allow-headers"].lower()


@pytest.mark.parametrize("intent", FIXTURE_INTENTS)
async def test_stream_returns_fixture_surface_in_dart_compatible_events(client, intent):
    fixture = load_fixture(intent)
    _raw, events = await _stream(
        client,
        [{"kind": "text", "text": fixture["prompt"]}],
        {"siargao": {"responseFormat": "a2ui", "intent": intent}},
    )
    assert [e["kind"] for e in events] == ["task", "status-update"]
    for e in events:
        assert smoke.check_event(e) == []
    final = events[-1]
    assert final["final"] is True
    assert final["status"]["state"] == "completed"
    message = final["status"]["message"]
    assert smoke.a2ui_messages(message) == fixture["messages"]
    assert all(p["metadata"]["mimeType"] == "application/a2ui+json" for p in message["parts"])
    meta = message["metadata"]["siargao"]
    assert meta["intent"] == intent and meta["source"] == "template" and meta["modelCalls"] == 0
    assert meta["valid"] is True
    assert smoke.sdk_validate(smoke.a2ui_messages(message)) == []


async def test_send_returns_task_with_surface(client):
    fixture = load_fixture("stays_near_cloud9")
    body = smoke.rpc_body("message/send", [{"kind": "text", "text": fixture["prompt"]}], None)
    result = (await client.post("/", json=body, headers=smoke.HEADERS)).json()["result"]
    assert result["kind"] == "task"
    assert smoke.check_event(result) == []
    assert smoke.a2ui_messages(result["status"]["message"]) == fixture["messages"]


async def test_text_format_over_a2a(client):
    fixture = load_fixture("returning_flexible")
    _, events = await _stream(
        client,
        [{"kind": "text", "text": fixture["prompt"]}],
        {"siargao": {"responseFormat": "text"}},
    )
    message = events[-1]["status"]["message"]
    assert smoke.texts(message) == [fixture["text"]]
    assert smoke.a2ui_messages(message) == []


async def test_action_over_a2a(client, log_path):
    action = {
        "version": "v0.9",
        "action": {
            "name": "choose_stay",
            "sourceComponentId": "stay-1",
            "surfaceId": "stays_near_cloud9",
            "context": {"stayId": "boardwalk-homestay", "nights": 3},
            "timestamp": "2026-10-17T10:00:00Z",
        },
    }
    body = smoke.rpc_body("message/send", [{"kind": "data", "data": action}], None)
    result = (await client.post("/", json=body, headers=smoke.HEADERS)).json()["result"]
    assert smoke.texts(result["status"]["message"]) == ["Saved Boardwalk Family Homestay for 3 nights."]
    assert read_log(log_path)[-1]["action"]["name"] == "choose_stay"


async def test_offline_unknown_prompt_over_a2a(client):
    _, events = await _stream(client, [{"kind": "text", "text": "Best lechon near General Luna?"}], None)
    message = events[-1]["status"]["message"]
    assert "offline mode" in smoke.texts(message)[0]
    assert message["metadata"]["siargao"]["modelCalls"] == 0


async def test_request_shape_from_genui_a2a_is_accepted(client):
    """genui_a2a sends nulls for optional fields; the server must accept them."""
    body = {
        "jsonrpc": "2.0",
        "id": 0,
        "method": "message/stream",
        "params": {
            "configuration": None,
            "metadata": None,
            "message": {
                "role": "user",
                "parts": [{"kind": "text", "metadata": None, "text": "Flights to Siargao under 8,000"}],
                "metadata": None,
                "extensions": None,
                "referenceTaskIds": None,
                "messageId": "4f1c2b4e-0000-4000-8000-000000000000",
                "taskId": None,
                "contextId": None,
                "kind": "message",
            },
        },
    }
    resp = await client.post("/", json=body, headers={**smoke.HEADERS, "Accept": "text/event-stream"})
    events = smoke.parse_sse(resp.text)
    assert events[-1]["status"]["message"]["metadata"]["siargao"]["intent"] == "flights_under_8000"


async def test_healthz(client):
    body = (await client.get("/healthz")).json()
    assert body["ok"] is True and body["mode"] == "offline"


async def test_browser_get_on_root_shows_status_page(client, monkeypatch):
    monkeypatch.setenv("K_SERVICE", "siargao-agent")
    monkeypatch.setenv("K_REVISION", "siargao-agent-00002-abc")
    resp = await client.get("/")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/html")
    assert "Siargao Planner" in resp.text
    assert "siargao-agent-00002-abc" in resp.text
    assert "/.well-known/agent-card.json" in resp.text
    # The JSON-RPC endpoint at the same path still takes POST.
    rpc = await client.post("/", json={"jsonrpc": "2.0", "id": "1", "method": "tasks/get", "params": {"id": "x"}})
    assert rpc.status_code == 200
    assert "jsonrpc" in rpc.json()
