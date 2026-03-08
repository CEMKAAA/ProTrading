from dashboard.backend.core.workbench.agent import WorkbenchAgent
from dashboard.backend.core.workbench.intent_classifier import get_tools_for_intent


def test_system_prompt_parts_uses_delta_context():
    agent = WorkbenchAgent()
    static_part, dynamic_part = agent._system_prompt_parts(  # noqa: SLF001
        context={"session": {"symbol": "XAUUSD", "timeframe": "M15"}},
        permissions={"can_chat": True},
        objective="chat",
        allowed_tool_names=["get_market_snapshot"],
        include_tool_summaries=False,
        delta_context={"price": 123.45, "trigger_count": 1},
    )
    assert "Locked Identity JSON" in static_part
    assert "\"price\": 123.45" in dynamic_part
    assert "\"trigger_count\": 1" in dynamic_part


def test_system_prompt_parts_empty_delta_falls_back_to_compact_context():
    agent = WorkbenchAgent()
    _, dynamic_part = agent._system_prompt_parts(  # noqa: SLF001
        context={"session": {"symbol": "XAUUSD", "timeframe": "M15"}, "bars": []},
        permissions={"can_chat": True},
        objective="chat",
        include_tool_summaries=False,
        delta_context={},
    )
    assert "\"session\"" in dynamic_part
    assert "\"symbol\": \"XAUUSD\"" in dynamic_part


def test_trim_history_coalesces_consecutive_roles():
    agent = WorkbenchAgent()
    out = agent._trim_history(  # noqa: SLF001
        [
            {"role": "user", "content": "first"},
            {"role": "user", "content": "second"},
            {"role": "assistant", "content": "done"},
        ],
        max_messages=12,
        max_chars=200,
    )
    assert len(out) == 2
    assert out[0]["role"] == "user"
    assert "first" in out[0]["content"]
    assert "second" in out[0]["content"]


def test_pruned_toolset_smaller_than_full():
    full_specs = WorkbenchAgent._tool_specs()  # noqa: SLF001
    pruned = WorkbenchAgent._tool_specs_filtered(get_tools_for_intent("what is current price?"))  # noqa: SLF001
    assert len(pruned) < len(full_specs)
