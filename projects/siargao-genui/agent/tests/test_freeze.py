from __future__ import annotations

import json
import shutil
import subprocess
import sys

import pytest
from conftest import AGENT_DIR, live_planner, make_stub_llm, model_answer, read_log

from siargao_agent.config import DEFAULT_DATA_DIR, DEFAULT_TEMPLATES_DIR
from siargao_agent.freezer import FreezeError, freeze
from siargao_agent.planner import Planner, Request
from siargao_agent.surface_log import SurfaceLog
from siargao_agent.templates import TemplateStore
from siargao_agent.validation import validate_messages


def _model_surface(store):
    """A model-style surface: its own surfaceId and snake_case component ids."""
    raw = json.dumps(store.render("surf_this_week").messages).replace('"surf_this_week"', '"siargao_food"')
    messages = json.loads(raw)
    comps = messages[1]["updateComponents"]["components"]
    comps[1]["id"] = "Hero_Block"
    comps[0]["children"][0] = "Hero_Block"
    return messages


@pytest.fixture
def dirs(tmp_path):
    templates, data = tmp_path / "templates", tmp_path / "data"
    shutil.copytree(DEFAULT_TEMPLATES_DIR, templates)
    shutil.copytree(DEFAULT_DATA_DIR, data)
    return templates, data


async def test_freeze_round_trip(settings, store, log_path, dirs):
    templates_dir, data_dir = dirs
    # 1. A live model answer gets logged.
    stub = make_stub_llm([model_answer(_model_surface(store), "Here is where to eat.")])
    reply = await live_planner(settings, store, stub).respond(Request(prompt="where to eat in General Luna"))
    assert reply.metadata["source"] == "model" and reply.metadata["valid"] is True
    assert len(read_log(log_path)) == 1

    # 2. The CLI freezes log line 1 into a template.
    cmd = [
        sys.executable,
        str(AGENT_DIR / "scripts" / "freeze.py"),
        "--log", str(log_path),
        "--line", "1",
        "--intent", "food_guide",
        "--keywords", "where to eat, food",
        "--templates-dir", str(templates_dir),
        "--data-dir", str(data_dir),
    ]  # fmt: skip
    done = subprocess.run(cmd, capture_output=True, text=True, cwd=AGENT_DIR)
    assert done.returncode == 0, done.stderr
    tpl = json.loads((templates_dir / "food_guide.json").read_text())
    data = json.loads((data_dir / "food_guide.json").read_text())
    assert tpl["keywords"] == ["where to eat", "food"]
    assert [next(iter(k for k in m if k != "version")) for m in tpl["messages"]] == [
        "createSurface",
        "updateComponents",
    ]
    assert all(m[k]["surfaceId"] == "food_guide" for m in tpl["messages"] for k in m if k != "version")
    ids = [c["id"] for c in tpl["messages"][1]["updateComponents"]["components"]]
    assert "hero-block" in ids and "Hero_Block" not in ids
    assert data == reply.messages[2]["updateDataModel"]["value"]

    # 3. Refuses to overwrite without --force.
    again = subprocess.run(cmd, capture_output=True, text=True, cwd=AGENT_DIR)
    assert again.returncode == 1 and "--force" in again.stderr
    assert subprocess.run([*cmd, "--force"], capture_output=True, text=True, cwd=AGENT_DIR).returncode == 0

    # 4. A fresh store serves it from a template, by keyword, with no model call.
    new_store = TemplateStore(templates_dir, data_dir)
    planner = Planner(settings, new_store, SurfaceLog(log_path))
    served = await planner.respond(Request(prompt="Where to eat tonight?"))
    assert served.format == "a2ui"
    assert served.metadata["intent"] == "food_guide"
    assert served.metadata["source"] == "template" and served.metadata["modelCalls"] == 0
    assert validate_messages(served.messages, surface_id="food_guide") == []
    assert served.messages[2]["updateDataModel"]["value"] == data


def test_freeze_refuses_invalid_surface(tmp_path, store):
    bad = _model_surface(store)
    bad[1]["updateComponents"]["components"][0]["children"].append("ghost")
    log = tmp_path / "log.jsonl"
    log.write_text(json.dumps({"prompt": "x", "messages": bad, "text": ""}) + "\n")
    with pytest.raises(FreezeError, match="ghost"):
        freeze(log, 1, "bad_one", templates_dir=tmp_path / "t", data_dir=tmp_path / "d")
    assert not (tmp_path / "t" / "bad_one.json").exists()


def test_freeze_refuses_text_only_line(tmp_path):
    log = tmp_path / "log.jsonl"
    log.write_text(json.dumps({"prompt": "x", "messages": [], "text": "hi"}) + "\n")
    with pytest.raises(FreezeError, match="no A2UI"):
        freeze(log, 1, "nothing", templates_dir=tmp_path, data_dir=tmp_path)


def test_freeze_rejects_bad_intent_name(tmp_path):
    with pytest.raises(FreezeError, match="snake_case"):
        freeze(tmp_path / "x", 1, "Bad-Name", templates_dir=tmp_path, data_dir=tmp_path)
