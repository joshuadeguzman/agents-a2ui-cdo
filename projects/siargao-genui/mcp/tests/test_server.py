from __future__ import annotations

import json
from typing import Any

import httpx
import pytest
from mcp import Client, types

from conftest import FIXTURES_DIR, load_json, sdk_validate
from siargao_mcp import A2UI_MIME_TYPE
from siargao_mcp.server import HOME_URI, STAYS_URI, TOOL_NAME, create_server, read_home, run_tool
from siargao_mcp.validation import validate_messages

FIXTURE_ARGS = {"area": "Cloud 9", "nights": 3, "max_price": 4500}
META_KEYS = {"intent", "source", "modelCalls", "latencyMs", "valid"}
HEADERS = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}


def _check_meta(meta: dict[str, Any] | None, intent: str, valid: bool = True) -> None:
    assert meta is not None
    siargao = meta["siargao"]
    assert set(siargao) == META_KEYS
    assert siargao["intent"] == intent
    assert siargao["source"] == "template"
    assert siargao["modelCalls"] == 0
    assert isinstance(siargao["latencyMs"], int) and siargao["latencyMs"] >= 0
    assert siargao["valid"] is valid


# Direct handler calls


def test_read_home_returns_a2ui_resource() -> None:
    result = read_home(HOME_URI)
    content = result.contents[0]
    assert content.mime_type == A2UI_MIME_TYPE
    assert content.uri == HOME_URI
    messages = json.loads(content.text)
    assert messages == load_json(FIXTURES_DIR / "home_first_run.json")["messages"]
    assert validate_messages(messages) == []
    sdk_validate(messages)
    _check_meta(result.meta, "home_first_run")
    _check_meta(content.meta, "home_first_run")


def test_read_unknown_resource_is_an_error() -> None:
    from mcp.shared.exceptions import MCPError

    with pytest.raises(MCPError):
        read_home("a2ui://nope")


def test_tool_returns_embedded_surface_and_summary() -> None:
    result = run_tool(TOOL_NAME, FIXTURE_ARGS)
    assert not result.is_error
    embedded, summary = result.content
    assert isinstance(embedded, types.EmbeddedResource)
    assert embedded.resource.uri == STAYS_URI
    assert embedded.resource.mime_type == A2UI_MIME_TYPE
    assert json.loads(embedded.resource.text) == load_json(FIXTURES_DIR / "stays_near_cloud9.json")["messages"]
    assert isinstance(summary, types.TextContent)
    assert summary.text.startswith("4 stays near Cloud 9")
    _check_meta(result.meta, "stays_near_cloud9")


@pytest.mark.parametrize(
    "args",
    [
        {"area": "Cloud 9", "nights": 0, "max_price": 4500},
        {"area": "Cloud 9", "nights": 3, "max_price": 100},
        {"area": "", "nights": 3, "max_price": 4500},
        {"area": "Cloud 9", "nights": 3},
        {"area": "Cloud 9", "nights": 3, "max_price": 4500, "extra": 1},
    ],
)
def test_bad_arguments_are_an_error_result(args: dict[str, Any]) -> None:
    result = run_tool(TOOL_NAME, args)
    assert result.is_error
    assert result.content[0].text.startswith("Invalid arguments for search_stays")
    _check_meta(result.meta, "stays_near_cloud9", valid=False)


def test_unknown_tool_is_an_error_result() -> None:
    assert run_tool("nope", {}).is_error


def test_validation_failure_returns_error_and_logs(monkeypatch: pytest.MonkeyPatch, caplog) -> None:
    from siargao_mcp import server

    monkeypatch.setattr(server, "validate_messages", lambda messages: ["boom"])
    result = run_tool(TOOL_NAME, FIXTURE_ARGS)
    assert result.is_error
    assert "failed A2UI validation" in result.content[0].text
    assert "failed validation" in caplog.text


# In-process MCP client session (SDK client, in-memory transport)


async def test_in_process_client_lists_reads_and_calls() -> None:
    async with Client(create_server()) as client:
        resources = (await client.list_resources()).resources
        assert [(r.uri, r.mime_type) for r in resources] == [(HOME_URI, A2UI_MIME_TYPE)]

        read = await client.read_resource(HOME_URI)
        assert read.contents[0].mime_type == A2UI_MIME_TYPE
        sdk_validate(json.loads(read.contents[0].text))
        _check_meta(read.meta, "home_first_run")

        tools = (await client.list_tools()).tools
        assert [t.name for t in tools] == [TOOL_NAME]
        assert set(tools[0].input_schema["required"]) == {"area", "nights", "max_price"}

        result = await client.call_tool(TOOL_NAME, FIXTURE_ARGS)
        assert not result.is_error
        assert result.content[0].resource.mime_type == A2UI_MIME_TYPE
        assert (
            json.loads(result.content[0].resource.text)
            == load_json(FIXTURES_DIR / "stays_near_cloud9.json")["messages"]
        )
        _check_meta(result.meta, "stays_near_cloud9")


# Real HTTP (uvicorn on a free port)


async def test_sdk_client_over_streamable_http(base_url: str) -> None:
    async with Client(f"{base_url}/mcp") as client:
        assert [r.uri for r in (await client.list_resources()).resources] == [HOME_URI]
        result = await client.call_tool(TOOL_NAME, {"area": "general luna", "nights": 2, "max_price": 2500})
        messages = json.loads(result.content[0].resource.text)
        sdk_validate(messages)
        assert [s["id"] for s in messages[2]["updateDataModel"]["value"]["stays"]] == [
            "general-luna-surf-hostel",
            "tourism-road-studios",
        ]


def _post(base_url: str, body: dict[str, Any], **headers: str) -> httpx.Response:
    return httpx.post(f"{base_url}/mcp", json=body, headers={**HEADERS, **headers}, timeout=10)


def test_plain_post_tools_call_without_initialize(base_url: str) -> None:
    body = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": TOOL_NAME, "arguments": FIXTURE_ARGS},
    }
    resp = _post(base_url, body, Origin="http://localhost:8080")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("application/json")
    assert resp.headers["access-control-allow-origin"] == "*"
    result = resp.json()["result"]
    item = result["content"][0]
    assert item["type"] == "resource"
    assert item["resource"]["uri"] == STAYS_URI
    assert item["resource"]["mimeType"] == A2UI_MIME_TYPE
    assert json.loads(item["resource"]["text"]) == load_json(FIXTURES_DIR / "stays_near_cloud9.json")["messages"]
    assert result["content"][1]["type"] == "text"
    assert result["isError"] is False
    _check_meta(result["_meta"], "stays_near_cloud9")


def test_plain_post_resources_read_without_initialize(base_url: str) -> None:
    resp = _post(base_url, {"jsonrpc": "2.0", "id": 2, "method": "resources/read", "params": {"uri": HOME_URI}})
    assert resp.status_code == 200
    result = resp.json()["result"]
    content = result["contents"][0]
    assert content["mimeType"] == A2UI_MIME_TYPE
    sdk_validate(json.loads(content["text"]))
    _check_meta(result["_meta"], "home_first_run")
    _check_meta(content["_meta"], "home_first_run")


def test_plain_post_lists(base_url: str) -> None:
    tools = _post(base_url, {"jsonrpc": "2.0", "id": 3, "method": "tools/list"}).json()["result"]["tools"]
    assert [t["name"] for t in tools] == [TOOL_NAME]
    resources = _post(base_url, {"jsonrpc": "2.0", "id": 4, "method": "resources/list"}).json()["result"]
    assert resources["resources"][0]["mimeType"] == A2UI_MIME_TYPE


def test_accept_json_only_also_works(base_url: str) -> None:
    resp = _post(base_url, {"jsonrpc": "2.0", "id": 5, "method": "tools/list"}, Accept="application/json")
    assert resp.status_code == 200
    assert resp.json()["result"]["tools"]


def test_cors_preflight(base_url: str) -> None:
    resp = httpx.options(
        f"{base_url}/mcp",
        headers={
            "Origin": "http://localhost:8080",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type,accept,mcp-protocol-version,mcp-session-id",
        },
    )
    assert resp.status_code == 200
    assert resp.headers["access-control-allow-origin"] == "*"
    assert "POST" in resp.headers["access-control-allow-methods"]
    assert "mcp-protocol-version" in resp.headers["access-control-allow-headers"]


def test_cors_exposes_session_header(base_url: str) -> None:
    resp = _post(base_url, {"jsonrpc": "2.0", "id": 6, "method": "tools/list"}, Origin="https://example.com")
    assert "mcp-session-id" in resp.headers["access-control-expose-headers"].lower()


def test_healthz(base_url: str) -> None:
    resp = httpx.get(f"{base_url}/healthz")
    assert resp.status_code == 200
    assert resp.json()["ok"] is True


def test_browser_get_on_root_shows_status_page(base_url: str) -> None:
    resp = httpx.get(base_url + "/", timeout=10)
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/html")
    assert "Siargao MCP server" in resp.text
    assert HOME_URI in resp.text
    assert "search_stays" in resp.text
