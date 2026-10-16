"""Smoke test a running agent over A2A JSON-RPC, the way the Flutter app calls it.

    .venv/bin/python scripts/smoke.py [BASE_URL]      # default http://localhost:10002

For every fixture intent it sends message/stream (SSE) and message/send with
the CONTRACT metadata, checks every event parses the way genui_a2a 0.10.1
parses it, and validates the returned A2UI with the a2ui SDK
(a2ui.utils.validate_payload against the vendored catalog). It also sends one
responseFormat "text" request and one action. Exits 1 on any failure.

The helpers (parse_sse, check_event, ...) are reused by tests/test_server.py.
"""

from __future__ import annotations

import json
import sys
import time
import uuid
from pathlib import Path
from typing import Any

AGENT_DIR = Path(__file__).resolve().parents[1]
CATALOG_PATH = AGENT_DIR / "siargao_agent" / "catalog" / "siargao_catalog.json"
FIXTURES_DIR = AGENT_DIR.parent / "fixtures"
EXTENSION_URI = "https://a2ui.org/a2a-extension/a2ui/v0.9"
CATALOG_ID = "https://siargao-genui.example/catalogs/v1/catalog.json"
INTENTS = [
    "first_time_trip",
    "returning_flexible",
    "flights_under_8000",
    "surf_this_week",
    "home_first_run",
    "stays_near_cloud9",
]
A2UI_KEYS = ("createSurface", "updateComponents", "updateDataModel", "deleteSurface")
EVENT_KINDS = ("task", "status-update", "task-status-update", "artifact-update")
TASK_STATES = (
    "submitted",
    "working",
    "input-required",
    "completed",
    "canceled",
    "failed",
    "rejected",
    "auth-required",
    "unknown",
)


# --- the genui_a2a 0.10.1 view of the wire format ---------------------------


def parse_sse(body: str) -> list[dict[str, Any]]:
    """Mirror genui_a2a's SseParser: data: lines, blank line ends an event,
    the JSON-RPC "result" is the event."""
    events, data = [], []
    for line in body.splitlines():
        if line.startswith("data:"):
            data.append(line[5:].strip())
        elif line.startswith(":") or line.startswith(("event:", "id:", "retry:")):
            # genui_a2a logs a warning for event:/id:/retry: lines and skips them.
            continue
        elif line == "" and data:
            events.append(_rpc_result(json.loads("\n".join(data))))
            data = []
    if data:
        events.append(_rpc_result(json.loads("\n".join(data))))
    return events


def _rpc_result(payload: dict[str, Any]) -> dict[str, Any]:
    if "error" in payload:
        raise AssertionError(f"JSON-RPC error: {payload['error']}")
    return payload["result"]


def check_part(part: dict[str, Any]) -> list[str]:
    kind = part.get("kind")
    if kind == "text":
        return [] if isinstance(part.get("text"), str) else ["text part without text"]
    if kind == "data":
        return [] if isinstance(part.get("data"), dict) else ["data part without object data"]
    if kind == "file":
        return [] if isinstance(part.get("file"), dict) else ["file part without file"]
    return [f"unknown part kind {kind!r} (genui_a2a throws)"]


def check_message(msg: dict[str, Any]) -> list[str]:
    errors = []
    if msg.get("role") not in ("user", "agent"):
        errors.append(f"bad role {msg.get('role')!r}")
    if not isinstance(msg.get("messageId"), str):
        errors.append("message without messageId")
    if not isinstance(msg.get("parts"), list):
        return [*errors, "message without parts"]
    for p in msg["parts"]:
        errors += check_part(p)
    return errors


def check_status(status: dict[str, Any]) -> list[str]:
    if status.get("state") not in TASK_STATES:
        return [f"bad task state {status.get('state')!r}"]
    return check_message(status["message"]) if status.get("message") else []


def check_event(event: dict[str, Any]) -> list[str]:
    """Problems genui_a2a would hit parsing this stream event."""
    kind = event.get("kind")
    if kind not in EVENT_KINDS:
        return [f"event kind {kind!r} is not one genui_a2a accepts (it throws ArgumentError)"]
    errors = []
    if kind == "task":
        for key in ("id", "contextId", "status"):
            if key not in event:
                errors.append(f"task event without {key}")
    else:
        for key in ("taskId", "contextId"):
            if not isinstance(event.get(key), str):
                errors.append(f"{kind} event without {key}")
    if kind in ("task", "status-update", "task-status-update"):
        errors += check_status(event.get("status") or {})
    return errors


def a2ui_messages(message: dict[str, Any]) -> list[dict[str, Any]]:
    """What genui_a2a feeds to the renderer: DataParts with an A2UI key."""
    return [
        p["data"]
        for p in message.get("parts", [])
        if p.get("kind") == "data" and any(k in p.get("data", {}) for k in A2UI_KEYS)
    ]


def texts(message: dict[str, Any]) -> list[str]:
    return [p["text"] for p in message.get("parts", []) if p.get("kind") == "text"]


def final_message_from_stream(events: list[dict[str, Any]]) -> dict[str, Any] | None:
    last = None
    for e in events:
        if e.get("kind") in ("status-update", "task-status-update") and (e.get("status") or {}).get("message"):
            last = e["status"]["message"]
    return last


def sdk_validate(messages: list[dict[str, Any]]) -> list[str]:
    from a2ui.core import A2uiError
    from a2ui.schema.catalog import CatalogConfig
    from a2ui.utils import validate_payload

    catalog = CatalogConfig.from_path("siargao", str(CATALOG_PATH)).to_catalog(protocol_version="0.9")
    try:
        validate_payload([catalog], messages)
    except A2uiError as e:
        return [f"{type(e).__name__}: {e}"]
    return []


def rpc_body(method: str, parts: list[dict[str, Any]], metadata: dict[str, Any] | None) -> dict[str, Any]:
    """The request genui_a2a builds (A2A 0.3), plus the CONTRACT metadata."""
    message = {
        "kind": "message",
        "role": "user",
        "messageId": str(uuid.uuid4()),
        "parts": parts,
        "metadata": metadata,
    }
    params: dict[str, Any] = {"message": message}
    if method == "message/stream":
        params.update({"configuration": None, "metadata": None})
    return {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}


HEADERS = {"Content-Type": "application/json", "X-A2A-Extensions": EXTENSION_URI}


# --- the smoke run -----------------------------------------------------------


def run(base_url: str) -> int:
    import httpx

    failures: list[str] = []
    rows: list[str] = []
    client = httpx.Client(base_url=base_url, timeout=60)

    card = client.get("/.well-known/agent-card.json").json()
    exts = (card.get("capabilities") or {}).get("extensions") or []
    ext = next((e for e in exts if e.get("uri") == EXTENSION_URI), None)
    ok_card = bool(ext) and CATALOG_ID in ((ext or {}).get("params") or {}).get("supportedCatalogIds", [])
    print(
        f"agent card: name={card.get('name')!r} url={card.get('url')} a2ui_extension={'ok' if ok_card else 'MISSING'}"
    )
    if not ok_card:
        failures.append("agent card lacks the A2UI v0.9 extension with our catalogId")

    def check(
        label: str, intent: str | None, message: dict[str, Any] | None, events_errors: list[str], ms: float, expect: str
    ) -> None:
        errs = list(events_errors)
        if message is None:
            errs.append("no final message")
            meta, msgs, txt = {}, [], []
        else:
            meta = (message.get("metadata") or {}).get("siargao") or {}
            msgs, txt = a2ui_messages(message), texts(message)
        if expect == "a2ui":
            kinds = [next(k for k in m if k in A2UI_KEYS) for m in msgs]
            if kinds != ["createSurface", "updateComponents", "updateDataModel"]:
                errs.append(f"unexpected A2UI sequence {kinds}")
            errs += sdk_validate(msgs) if msgs else []
            if intent and any(m[k].get("surfaceId") != intent for m in msgs for k in A2UI_KEYS if k in m):
                errs.append("surfaceId does not match intent")
        elif not txt:
            errs.append("expected a text part")
        for key in ("intent", "source", "modelCalls", "latencyMs", "valid"):
            if key not in meta:
                errs.append(f"metadata.siargao.{key} missing")
        status = "PASS" if not errs else "FAIL"
        rows.append(
            f"{status} {label:<34} intent={meta.get('intent')!s:<20} source={meta.get('source')!s:<8} "
            f"modelCalls={meta.get('modelCalls')} valid={meta.get('valid')} latencyMs={meta.get('latencyMs')} "
            f"roundTripMs={ms:.0f} parts={len(msgs)} a2ui + {len(txt)} text"
        )
        failures.extend(f"{label}: {e}" for e in errs)

    def stream(parts, metadata) -> tuple[dict[str, Any] | None, list[str], float]:
        t0 = time.perf_counter()
        resp = client.post(
            "/", json=rpc_body("message/stream", parts, metadata), headers={**HEADERS, "Accept": "text/event-stream"}
        )
        ms = (time.perf_counter() - t0) * 1000
        events = parse_sse(resp.text)
        errs = [e for ev in events for e in check_event(ev)]
        finals = [e for e in events if e.get("final")]
        if len(finals) != 1:
            errs.append(f"expected one final event, got {len(finals)}")
        return final_message_from_stream(events), errs, ms

    def send(parts, metadata) -> tuple[dict[str, Any] | None, list[str], float]:
        t0 = time.perf_counter()
        resp = client.post("/", json=rpc_body("message/send", parts, metadata), headers=HEADERS).json()
        ms = (time.perf_counter() - t0) * 1000
        result = _rpc_result(resp)
        errs = [] if result.get("kind") == "task" else ["message/send must return a Task (genui_a2a parses Task)"]
        errs += check_event(result)
        return (result.get("status") or {}).get("message"), errs, ms

    for intent in INTENTS:
        prompt = json.loads((FIXTURES_DIR / f"{intent}.json").read_text())["prompt"]
        meta = {"siargao": {"responseFormat": "a2ui", "intent": intent}}
        parts = [{"kind": "text", "text": prompt}]
        check(f"stream {intent}", intent, *stream(parts, meta), expect="a2ui")
        check(f"send   {intent}", intent, *send(parts, meta), expect="a2ui")

    text_meta = {"siargao": {"responseFormat": "text", "intent": "surf_this_week"}}
    check(
        "stream text surf_this_week",
        None,
        *stream([{"kind": "text", "text": "How's the surf in Siargao this week?"}], text_meta),
        expect="text",
    )

    action = {
        "version": "v0.9",
        "action": {
            "name": "choose_stay",
            "sourceComponentId": "stay-2",
            "surfaceId": "stays_near_cloud9",
            "context": {"stayId": "cloud9-surf-cabins", "nights": 3},
            "timestamp": "2026-10-17T10:00:00Z",
        },
    }
    msg, errs, ms = send([{"kind": "data", "data": action}], None)
    check("send   action choose_stay", None, msg, errs, ms, expect="text")
    if msg:
        print(f"action reply: {texts(msg)}")

    print("\n".join(rows))
    if failures:
        print("\nFAILURES:\n  " + "\n  ".join(failures))
        return 1
    print(f"\nall {len(rows)} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(run(sys.argv[1] if len(sys.argv) > 1 else "http://localhost:10002"))
