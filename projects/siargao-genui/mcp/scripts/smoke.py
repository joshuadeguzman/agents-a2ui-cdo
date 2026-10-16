"""Smoke test a running Siargao MCP server with plain JSON-RPC POSTs (no initialize).

Usage (from mcp/):
    .venv/bin/python scripts/smoke.py http://localhost:10003
    .venv/bin/python scripts/smoke.py https://siargao-mcp-XXXX.asia-southeast1.run.app

Checks tools/list, resources/list, resources/read a2ui://home/first-run,
tools/call search_stays with the fixture inputs, and a CORS preflight. Every
A2UI payload is validated against the vendored catalog (and with the a2ui SDK
when it is installed). Exits 1 on any failure.
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from siargao_mcp.validation import validate_messages  # noqa: E402

MIME = "application/a2ui+json"
HEADERS = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
FIXTURE = ROOT.parent / "fixtures" / "stays_near_cloud9.json"


def rpc(url: str, rid: int, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    body: dict[str, Any] = {"jsonrpc": "2.0", "id": rid, "method": method}
    if params is not None:
        body["params"] = params
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=HEADERS, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read())
    if "error" in payload:
        raise RuntimeError(f"{method}: {payload['error']}")
    return payload["result"]


def sdk_check(messages: list[Any]) -> str:
    try:
        from a2ui.schema.catalog import CatalogConfig
        from a2ui.utils import validate_payload
    except ImportError:
        return "sdk skipped"
    cat = CatalogConfig.from_path("siargao", str(ROOT / "catalog" / "siargao_catalog.json")).to_catalog(
        protocol_version="0.9"
    )
    validate_payload([cat], messages)
    return "sdk ok"


def check_surface(label: str, mime: str, text: str, meta: dict[str, Any]) -> list[Any]:
    assert mime == MIME, f"{label}: mimeType {mime!r}"
    messages = json.loads(text)
    errors = validate_messages(messages)
    assert not errors, f"{label}: {errors}"
    sdk = sdk_check(messages)
    s = meta["siargao"]
    print(
        f"ok   {label}: {len(messages)} messages, mimeType {mime}, catalog ok, {sdk}, "
        f"_meta.siargao intent={s['intent']} latencyMs={s['latencyMs']} valid={s['valid']}"
    )
    return messages


def main(base_url: str) -> int:
    url = base_url.rstrip("/")
    if not url.endswith("/mcp"):
        url += "/mcp"
    failed = False

    def step(name, fn):
        nonlocal failed
        try:
            fn()
        except Exception as e:  # noqa: BLE001
            failed = True
            print(f"FAIL {name}: {e}")

    def tools_list():
        tools = rpc(url, 1, "tools/list")["tools"]
        print(f"ok   tools/list: {[t['name'] for t in tools]}")

    def resources_list():
        res = rpc(url, 2, "resources/list")["resources"]
        print(f"ok   resources/list: {[(r['uri'], r.get('mimeType')) for r in res]}")

    def resources_read():
        result = rpc(url, 3, "resources/read", {"uri": "a2ui://home/first-run"})
        c = result["contents"][0]
        check_surface("resources/read a2ui://home/first-run", c.get("mimeType"), c["text"], result["_meta"])

    def tools_call():
        args = {"area": "Cloud 9", "nights": 3, "max_price": 4500}
        result = rpc(url, 4, "tools/call", {"name": "search_stays", "arguments": args})
        assert not result.get("isError"), result
        res = result["content"][0]["resource"]
        messages = check_surface(f"tools/call search_stays {args}", res.get("mimeType"), res["text"], result["_meta"])
        if FIXTURE.exists():
            same = messages == json.loads(FIXTURE.read_text())["messages"]
            assert same, "output differs from fixtures/stays_near_cloud9.json"
            print("ok   tools/call output equals fixtures/stays_near_cloud9.json messages")
        print(f"     summary: {result['content'][1]['text']}")

    def preflight():
        req = urllib.request.Request(
            url,
            method="OPTIONS",
            headers={
                "Origin": "http://localhost:8080",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "content-type,accept,mcp-protocol-version",
            },
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            allow = resp.headers.get("access-control-allow-origin")
            assert resp.status == 200 and allow == "*", (resp.status, allow)
            print(f"ok   CORS preflight: {resp.status}, allow-origin {allow}")

    for name, fn in [
        ("tools/list", tools_list),
        ("resources/list", resources_list),
        ("resources/read", resources_read),
        ("tools/call", tools_call),
        ("CORS preflight", preflight),
    ]:
        step(name, fn)
    print("FAILED" if failed else "ALL OK")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "http://localhost:10003"))
