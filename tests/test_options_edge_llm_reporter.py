from dashboard.backend.core.options_edge.llm_reporter import OptionsEdgeReporter


def _sample_payload():
    scan = {"scan_id": "abc123", "universe_size": 100, "top_n": 8}
    candidates = [
        {
            "symbol": "AAPL",
            "sector": "Technology",
            "selected": True,
            "score_total": 78.2,
            "score_vol_edge": 0.81,
            "score_liquidity": 0.74,
        }
    ]
    trades = [
        {
            "symbol": "AAPL",
            "structure_type": "short_strangle",
            "pop_est": 0.71,
            "max_profit": 118.0,
            "max_loss": 236.0,
            "quality_flags": ["max_loss_proxy_unbounded"],
            "max_loss_is_proxy": True,
        }
    ]
    insights = {"AAPL": {"news": [{"title": "headline"}]}}
    return scan, candidates, trades, insights


def test_reporter_deterministic_default():
    scan, candidates, trades, insights = _sample_payload()
    r = OptionsEdgeReporter()
    out = r.build_report(scan=scan, candidates=candidates, trades=trades, symbol_insights=insights)
    assert out["llm_used"] is False
    assert "market_summary" in out
    assert "risk_summary" in out
    assert isinstance(out.get("candidate_notes"), list)


def test_reporter_local_provider_success(monkeypatch):
    class _FakeResp:
        status_code = 200

        @staticmethod
        def json():
            return {
                "ok": True,
                "model": "gpt-oss-20b",
                "result": {
                    "market_summary": "m",
                    "risk_summary": "r",
                    "candidate_notes": [{"symbol": "AAPL", "text": "x"}],
                    "warnings": [],
                },
            }

    class _FakeClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        @staticmethod
        def post(url, json):
            return _FakeResp()

    import dashboard.backend.core.options_edge.llm_reporter as mod

    monkeypatch.setattr(mod.httpx, "Client", _FakeClient)
    scan, candidates, trades, insights = _sample_payload()
    r = OptionsEdgeReporter()
    out = r.build_report(
        scan=scan,
        candidates=candidates,
        trades=trades,
        symbol_insights=insights,
        llm_provider="local_gptoss_http",
        llm_model="gpt-oss-20b",
    )
    assert out["llm_used"] is True
    assert out["llm_model"] == "gpt-oss-20b"
    assert out["market_summary"] == "m"


def test_reporter_local_provider_fallback(monkeypatch):
    class _BadClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        @staticmethod
        def post(url, json):
            raise RuntimeError("connection refused")

    import dashboard.backend.core.options_edge.llm_reporter as mod

    monkeypatch.setattr(mod.httpx, "Client", _BadClient)
    scan, candidates, trades, insights = _sample_payload()
    r = OptionsEdgeReporter()
    out = r.build_report(
        scan=scan,
        candidates=candidates,
        trades=trades,
        symbol_insights=insights,
        llm_provider="local_gptoss_http",
        llm_model="gpt-oss-20b",
    )
    assert out["llm_used"] is False
    assert any("fallback" in str(w).lower() for w in (out.get("warnings") or []))


def test_reporter_anthropic_provider_success(monkeypatch):
    class _FakeResp:
        status_code = 200

        @staticmethod
        def json():
            return {
                "id": "msg_test",
                "content": [
                    {
                        "type": "text",
                        "text": (
                            '{"market_summary":"m","risk_summary":"r",'
                            '"candidate_notes":[{"symbol":"AAPL","text":"n"}],'
                            '"trade_decisions":[],"warnings":[]}'
                        ),
                    }
                ],
            }

    class _FakeClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        @staticmethod
        def post(url, json, headers):
            return _FakeResp()

    import dashboard.backend.core.options_edge.llm_reporter as mod

    monkeypatch.setattr(mod.httpx, "Client", _FakeClient)
    scan, candidates, trades, insights = _sample_payload()
    r = OptionsEdgeReporter()
    r.anthropic_api_key = "test-key"
    out = r.build_report(
        scan=scan,
        candidates=candidates,
        trades=trades,
        symbol_insights=insights,
        llm_provider="anthropic_claude",
        llm_model="claude-3-5-haiku-latest",
    )
    assert out["llm_used"] is True
    assert out["llm_model"] == "claude-3-5-haiku-latest"
    assert out["market_summary"] == "m"


def test_reporter_anthropic_provider_fallback(monkeypatch):
    def _raise(*args, **kwargs):
        raise RuntimeError("anthropic down")

    scan, candidates, trades, insights = _sample_payload()
    r = OptionsEdgeReporter()
    monkeypatch.setattr(r, "_build_anthropic_claude", _raise)
    out = r.build_report(
        scan=scan,
        candidates=candidates,
        trades=trades,
        symbol_insights=insights,
        llm_provider="anthropic_claude",
        llm_model="claude-3-5-haiku-latest",
    )
    assert out["llm_used"] is False
    assert any("Claude FAILED" in str(w) for w in (out.get("warnings") or []))
