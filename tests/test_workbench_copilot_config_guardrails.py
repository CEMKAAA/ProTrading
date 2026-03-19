from dashboard.backend.core.workbench_copilot.session_loop import normalize_copilot_config


def test_normalize_copilot_config_keeps_guardrail_and_watchdog_fields():
    cfg = normalize_copilot_config(
        {
            "guardrail_enabled": False,
            "guardrail_session_filter_enabled": True,
            "guardrail_news_filter_enabled": True,
            "guardrail_max_risk_per_trade_usd": 1250.0,
            "guardrail_news_lookback_min": 90,
            "watchdog_mode": "claude",
            "watchdog_interval_sec": 45,
            "watchdog_llm_min_interval_sec": 240,
            "watchdog_trigger_requires_approval": True,
            "watchdog_model_label": "claude-haiku-4-5-20251001",
            "watchdog_llm_url": "https://api.anthropic.com",
            "market_news_provider": "ibkr",
            "market_news_llm_summary_enabled": True,
            "market_news_summary_model": "claude-haiku-4-5-20251001",
            "market_news_llm_timeout_sec": 9,
            "market_news_ibkr_host": "127.0.0.1",
            "market_news_ibkr_port": 7497,
        }
    )
    assert cfg["guardrail_enabled"] is False
    assert cfg["guardrail_session_filter_enabled"] is True
    assert cfg["guardrail_news_filter_enabled"] is True
    assert float(cfg["guardrail_max_risk_per_trade_usd"]) == 1250.0
    assert int(cfg["guardrail_news_lookback_min"]) == 90
    assert str(cfg["watchdog_mode"]) == "claude"
    assert int(cfg["watchdog_interval_sec"]) == 45
    assert int(cfg["watchdog_llm_min_interval_sec"]) == 240
    assert cfg["watchdog_trigger_requires_approval"] is True
    assert str(cfg["watchdog_model_label"]) == "claude-haiku-4-5-20251001"
    assert str(cfg["watchdog_llm_url"]) == "https://api.anthropic.com"
    assert str(cfg["market_news_provider"]) == "ibkr"
    assert cfg["market_news_llm_summary_enabled"] is True
    assert str(cfg["market_news_summary_model"]) == "claude-haiku-4-5-20251001"
    assert int(cfg["market_news_llm_timeout_sec"]) == 9
    assert str(cfg["market_news_ibkr_host"]) == "127.0.0.1"
    assert int(cfg["market_news_ibkr_port"]) == 7497
