from dashboard.backend.core.workbench.intent_classifier import classify_intent, get_tools_for_intent


def test_classify_intent_market_query():
    intents = classify_intent("what is the current market price?")
    assert "market_query" in intents


def test_classify_intent_trade_action():
    intents = classify_intent("buy now with stop loss")
    assert "trade_action" in intents


def test_get_tools_for_intent_includes_submit():
    tools = get_tools_for_intent("anything")
    assert "submit_proposed_actions" in tools


def test_get_tools_for_intent_prunes_research_for_market_query():
    tools = get_tools_for_intent("what is price on m15?")
    assert "get_market_snapshot" in tools
    assert "run_research_optimize" not in tools
    assert "get_market_news" not in tools


def test_news_query_includes_market_news_tool():
    intents = classify_intent("Any macro news or FOMC headline risk on XAUUSD?")
    assert "news_query" in intents
    tools = get_tools_for_intent("Any macro news or FOMC headline risk on XAUUSD?")
    assert "get_market_news" in tools


def test_liquidity_language_maps_to_analysis_tools():
    intents = classify_intent("scan liquidity sweeps and equal highs on M15")
    assert "analysis" in intents
    tools = get_tools_for_intent("scan liquidity sweeps and equal highs on M15")
    assert "scan_tool" in tools
    assert "run_mtf_analysis" in tools


def test_identity_intent_includes_personality_switch_tool():
    intents = classify_intent("switch to master personality profile")
    assert "identity" in intents
    tools = get_tools_for_intent("switch to master personality profile")
    assert "set_agent_personality" in tools


def test_explicit_tool_name_forces_allowlist_inclusion():
    tools = get_tools_for_intent(
        "Run tools now: set_market_context(symbol='XAUUSD', timeframe='H4') and get_scheduled_triggers()"
    )
    assert "set_market_context" in tools
    assert "get_scheduled_triggers" in tools
