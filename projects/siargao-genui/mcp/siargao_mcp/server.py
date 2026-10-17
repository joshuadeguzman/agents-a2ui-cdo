"""The Siargao MCP server: one A2UI resource and one A2UI tool.

Built on the low-level `mcp.server.Server` (mcp 2.x) rather than `MCPServer`
so every result can carry `_meta.siargao` at the result level, which
`MCPServer` does not expose for resources.
"""

from __future__ import annotations

import html
import json
import logging
import os
import time
from functools import cache
from typing import Annotated, Any

from mcp import types
from mcp.server import Server, ServerRequestContext
from mcp.server.transport_security import TransportSecuritySettings
from mcp.shared.exceptions import MCPError
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from starlette.applications import Starlette
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import HTMLResponse, JSONResponse
from starlette.routing import Route
from starlette.types import ASGIApp

from . import A2UI_MIME_TYPE, __version__
from .surfaces import (
    build_stays_surface,
    home_first_run_messages,
    known_areas,
    stays_summary,
)
from .validation import validate_messages

logger = logging.getLogger("siargao_mcp")

HOME_URI = "a2ui://home/first-run"
STAYS_URI = "a2ui://search/stays"
TOOL_NAME = "search_stays"
MCP_PATH = "/mcp"

INSTRUCTIONS = (
    "Siargao travel planner surfaces as A2UI v0.9 (mimeType application/a2ui+json). "
    f"Read {HOME_URI} for the home screen. Call {TOOL_NAME} to search sample stays by area "
    "and budget; it returns an embedded A2UI resource plus a short text summary. "
    "All prices are sample data in PHP."
)


class SearchStaysArgs(BaseModel):
    """Arguments for search_stays. Its JSON Schema is the tool's inputSchema."""

    model_config = ConfigDict(extra="forbid", title="search_stays arguments")

    area: Annotated[
        str,
        Field(
            min_length=1,
            max_length=60,
            description="Area on Siargao, matched ignoring case. Sample data covers: "
            "Cloud 9, General Luna, Pacifico, Pilar, Burgos.",
            examples=["Cloud 9"],
        ),
    ]
    nights: Annotated[
        int,
        Field(ge=1, le=30, description="Number of nights. Shown on the surface and sent back when a stay is chosen."),
    ]
    max_price: Annotated[
        int,
        Field(
            ge=500,
            le=10000,
            description="Maximum price per night in PHP, inclusive. 500 to 10000, the range of the budget slider.",
            examples=[4500],
        ),
    ]


TOOL = types.Tool(
    name=TOOL_NAME,
    title="Search stays",
    description=(
        "Search sample places to stay on Siargao by area and maximum price per night, and get the "
        "results as an A2UI v0.9 surface. Returns up to 4 stays in the area (matched ignoring case) "
        "priced at or below max_price, cheapest first. The result content has one embedded resource "
        f"({STAYS_URI}, mimeType {A2UI_MIME_TYPE}) whose text is the JSON array of A2UI messages "
        "(createSurface, updateComponents, updateDataModel), plus a short text summary. With no "
        "matches it still returns a valid surface that suggests a higher budget. Sample prices in PHP."
    ),
    input_schema=SearchStaysArgs.model_json_schema(),
    annotations=types.ToolAnnotations(
        title="Search stays",
        read_only_hint=True,
        destructive_hint=False,
        idempotent_hint=True,
        open_world_hint=False,
    ),
)

HOME_RESOURCE = types.Resource(
    uri=HOME_URI,
    name="home_first_run",
    title="Siargao home, first run",
    description=(
        "The Home screen for a first-time visitor as an A2UI v0.9 surface: hero, quick prompt chips, "
        "featured spots and a local tip. The text is a JSON array of A2UI messages."
    ),
    mime_type=A2UI_MIME_TYPE,
)


def siargao_meta(intent: str, started: float, valid: bool) -> dict[str, Any]:
    latency_ms = round((time.perf_counter() - started) * 1000)
    return {
        "siargao": {
            "intent": intent,
            "source": "template",
            "modelCalls": 0,
            "latencyMs": latency_ms,
            "valid": valid,
        }
    }


@cache
def _home_surface() -> tuple[str, tuple[str, ...]]:
    """The home surface JSON and its validation errors. It is static, so validate once."""
    messages = home_first_run_messages()
    return json.dumps(messages, ensure_ascii=False), tuple(validate_messages(messages))


async def list_resources(
    ctx: ServerRequestContext, params: types.PaginatedRequestParams | None
) -> types.ListResourcesResult:
    return types.ListResourcesResult(resources=[HOME_RESOURCE])


async def read_resource(ctx: ServerRequestContext, params: types.ReadResourceRequestParams) -> types.ReadResourceResult:
    return read_home(str(params.uri))


def read_home(uri: str) -> types.ReadResourceResult:
    started = time.perf_counter()
    if uri != HOME_URI:
        raise MCPError(code=types.INVALID_PARAMS, message=f"Unknown resource: {uri}", data={"uri": uri})
    text, errors = _home_surface()
    if errors:
        logger.warning("home_first_run surface failed validation: %s", list(errors))
        raise MCPError(
            code=types.INTERNAL_ERROR,
            message="The home surface failed A2UI validation",
            data={"uri": uri, "errors": list(errors)},
        )
    meta = siargao_meta("home_first_run", started, True)
    content = types.TextResourceContents(uri=HOME_URI, mime_type=A2UI_MIME_TYPE, text=text, _meta=meta)
    return types.ReadResourceResult(contents=[content], _meta=meta)


async def list_tools(ctx: ServerRequestContext, params: types.PaginatedRequestParams | None) -> types.ListToolsResult:
    return types.ListToolsResult(tools=[TOOL])


async def call_tool(ctx: ServerRequestContext, params: types.CallToolRequestParams) -> types.CallToolResult:
    return run_tool(params.name, params.arguments or {})


def _error_result(message: str, started: float) -> types.CallToolResult:
    return types.CallToolResult(
        content=[types.TextContent(type="text", text=message)],
        is_error=True,
        _meta=siargao_meta("stays_near_cloud9", started, False),
    )


def run_tool(name: str, arguments: dict[str, Any]) -> types.CallToolResult:
    started = time.perf_counter()
    if name != TOOL_NAME:
        return _error_result(f"Unknown tool: {name}. This server has one tool, {TOOL_NAME}.", started)
    try:
        args = SearchStaysArgs.model_validate(arguments)
    except ValidationError as e:
        problems = "; ".join(
            f"{'.'.join(str(p) for p in err['loc']) or 'arguments'}: {err['msg']}" for err in e.errors()
        )
        return _error_result(f"Invalid arguments for {TOOL_NAME}: {problems}", started)

    messages, stays = build_stays_surface(args.area, args.nights, args.max_price)
    errors = validate_messages(messages)
    if errors:
        logger.warning("search_stays surface failed validation for %s: %s", args.model_dump(), errors)
        return _error_result("The stays surface failed A2UI validation: " + "; ".join(errors), started)

    meta = siargao_meta("stays_near_cloud9", started, True)
    surface = types.EmbeddedResource(
        type="resource",
        resource=types.TextResourceContents(
            uri=STAYS_URI,
            mime_type=A2UI_MIME_TYPE,
            text=json.dumps(messages, ensure_ascii=False),
        ),
    )
    summary = types.TextContent(type="text", text=stays_summary(args.area, args.nights, args.max_price, stays))
    return types.CallToolResult(content=[surface, summary], _meta=meta)


def create_server() -> Server:
    return Server(
        "siargao-mcp",
        version=__version__,
        title="Siargao GenUI MCP",
        description="A2UI v0.9 surfaces for the Siargao travel planner demo.",
        instructions=INSTRUCTIONS,
        on_list_resources=list_resources,
        on_read_resource=read_resource,
        on_list_tools=list_tools,
        on_call_tool=call_tool,
    )


async def healthz(request: Request) -> JSONResponse:
    return JSONResponse({"ok": True, "service": "siargao-mcp", "version": __version__, "areas": known_areas()})


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


async def home(request: Request) -> HTMLResponse:
    """A status page for people who open the service URL in a browser."""
    e = html.escape
    base = str(request.base_url).rstrip("/")
    seconds = int(time.time() - STARTED_AT)
    hours, rest = divmod(seconds, 3600)
    uptime = f"{hours} h {rest // 60} min" if hours else f"{rest // 60} min {rest % 60} s"
    rows = [
        ("Cloud Run service", f"<code>{e(os.environ.get('K_SERVICE', 'local'))}</code>"),
        ("Revision", f"<code>{e(os.environ.get('K_REVISION', 'local'))}</code>"),
        ("Instance up for", e(uptime)),
        ("MCP endpoint", f"<code>{e(base)}{MCP_PATH}</code> (Streamable HTTP, POST JSON-RPC)"),
        ("Resource", f"<code>{HOME_URI}</code>, <code>{A2UI_MIME_TYPE}</code>"),
        ("Tool", f"<code>search_stays(area, nights, max_price)</code>, areas: {e(', '.join(known_areas()))}"),
        ("Health", f"<a href='{e(base)}/healthz'>/healthz</a>"),
    ]
    body = "".join(f"<tr><td>{e(k)}</td><td>{v}</td></tr>" for k, v in rows)
    return HTMLResponse(
        "<!doctype html><html lang=en><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'>"
        f"<title>Siargao MCP server</title><style>{PAGE_STYLE}</style></head><body><main>"
        "<h1>Siargao MCP server</h1><p class=sub>A2UI surfaces over MCP, deployed on Google Cloud Run</p>"
        f"<span class=ok>Running</span><table>{body}</table>"
        "<p class=note>This page is for browsers. MCP clients POST to the endpoint above.</p>"
        "</main></body></html>"
    )


def create_app(server: Server | None = None) -> ASGIApp:
    """The ASGI app: Streamable HTTP at /mcp (stateless, JSON responses), wrapped in permissive CORS."""
    server = server or create_server()
    inner: Starlette = server.streamable_http_app(
        streamable_http_path=MCP_PATH,
        json_response=True,
        stateless_http=True,
        # DNS rebinding protection would reject the Cloud Run Host header and
        # browser origins. This demo server is public and read-only by design.
        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
        host="0.0.0.0",
        custom_starlette_routes=[
            Route("/healthz", healthz, methods=["GET"]),
            Route("/", home, methods=["GET"]),
        ],
    )
    return CORSMiddleware(
        inner,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
        expose_headers=["Mcp-Session-Id", "Mcp-Protocol-Version"],
        max_age=600,
    )
