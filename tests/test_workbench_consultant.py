from dashboard.backend.core.workbench.consultant import WorkbenchConsultant


def test_consultant_init_defaults():
    c = WorkbenchConsultant()
    out = c.chat(
        message="Summarize my context",
        context={"symbol": "XAUUSD", "timeframe": "M15"},
        conversation_history=[],
        provider="deterministic",
    )
    assert out["ok"] is True
    assert out["provider"] == "deterministic"
    assert out["model"] == "deterministic"
    assert isinstance(out.get("reply"), str) and len(out.get("reply")) > 0


def test_consultant_unknown_provider():
    c = WorkbenchConsultant()
    out = c.chat(
        message="hello",
        context={},
        conversation_history=[],
        provider="not_real_provider",
    )
    assert out["ok"] is False
    assert "Unknown provider" in str(out.get("error", ""))


def test_consultant_empty_context_no_crash():
    c = WorkbenchConsultant()
    out = c.chat(
        message="What do you see?",
        context={},
        conversation_history=[{"role": "user", "content": "hi"}],
        provider="deterministic",
    )
    assert out["ok"] is True
    assert isinstance(out.get("reply"), str)


def test_consultant_connection_error_graceful():
    c = WorkbenchConsultant()
    out = c.chat(
        message="hello",
        context={},
        conversation_history=[],
        provider="local_gptoss_http",
        llm_url="http://127.0.0.1:1",
        timeout_sec=1,
    )
    assert out["ok"] is False
    assert "error" in out
