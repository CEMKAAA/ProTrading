from dashboard.backend.core.workbench.agent import WorkbenchAgent


def test_agent_tool_specs_include_memory_tools():
    specs = WorkbenchAgent._tool_specs()
    names = {str(s.get("name") or "") for s in specs if isinstance(s, dict)}
    assert "search_memory" in names
    assert "save_memory_note" in names


def test_save_memory_note_scope_has_enum():
    specs = WorkbenchAgent._tool_specs()
    row = next((s for s in specs if isinstance(s, dict) and str(s.get("name") or "") == "save_memory_note"), None)
    assert isinstance(row, dict)
    params = row.get("parameters") if isinstance(row.get("parameters"), dict) else {}
    props = params.get("properties") if isinstance(params.get("properties"), dict) else {}
    scope = props.get("scope") if isinstance(props.get("scope"), dict) else {}
    assert scope.get("enum") == ["GLOBAL", "SESSION", "SYMBOL"]


def test_parse_final_payload_extracts_memory_notes():
    agent = WorkbenchAgent()
    text = (
        '{"reply":"ok","proposed_actions":[{"action_type":"REVIEW_NOTE","summary":"x"}],'
        '"memory_notes":[{"content":"Always align FVG with higher timeframe trend",'
        '"memory_type":"trader_rule","scope":"GLOBAL","importance":0.95}]}'
    )
    reply, actions, memory_notes = agent._parse_final_payload(text)
    assert reply == "ok"
    assert isinstance(actions, list) and len(actions) == 1
    assert isinstance(memory_notes, list) and len(memory_notes) == 1
    assert memory_notes[0]["scope"] == "GLOBAL"
    assert memory_notes[0]["memory_type"] == "trader_rule"


def test_parse_final_payload_keeps_notes_without_reply():
    agent = WorkbenchAgent()
    text = (
        '{"proposed_actions":[{"action_type":"REVIEW_NOTE","summary":"x"}],'
        '"memory_notes":[{"content":"Use H4 FVG first, then M15 entry","memory_type":"trader_rule","scope":"GLOBAL"}]}'
    )
    reply, actions, memory_notes = agent._parse_final_payload(text)
    assert reply == ""
    assert len(actions) == 1
    assert len(memory_notes) == 1


def test_normalize_memory_notes_clamps_and_filters():
    raw = [
        {"content": "short", "memory_type": "x"},
        {"content": "   Use 4H FVG as anchor before 5M entries   ", "scope": "invalid", "importance": 5.0},
    ]
    out = WorkbenchAgent._normalize_memory_notes(raw)
    assert len(out) == 1
    assert out[0]["scope"] == "SESSION"
    assert out[0]["importance"] == 1.0


def test_system_prompt_mentions_locked_identity():
    agent = WorkbenchAgent()
    prompt = agent._system_prompt(
        context={"identity": {"lock_personality": True, "persona": "Apprentice"}},
        permissions={},
        objective="chat",
    )
    assert "Identity profile is locked" in prompt
    assert "Locked Identity JSON" in prompt
