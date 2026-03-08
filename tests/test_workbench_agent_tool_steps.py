from dashboard.backend.api import simulation_routes as routes


def test_agent_effective_max_tool_steps_external_provider_uses_configurable_cap(monkeypatch):
    monkeypatch.setenv("WORKBENCH_EXTERNAL_MAX_TOOL_STEPS", "8")
    assert routes._agent_effective_max_tool_steps("claude", 10) == 8
    assert routes._agent_effective_max_tool_steps("openai_compat", 6) == 6


def test_agent_effective_max_tool_steps_non_external_provider_unclamped_by_external_cap(monkeypatch):
    monkeypatch.setenv("WORKBENCH_EXTERNAL_MAX_TOOL_STEPS", "2")
    assert routes._agent_effective_max_tool_steps("deterministic", 9) == 9
