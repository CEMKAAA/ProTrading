from dashboard.backend.services.telegram_bridge_service import TelegramBridgeService


def test_execution_report_aggregates_by_combo_and_sorts_desc():
    svc = TelegramBridgeService()

    rows = [
        {
            "source_type": "mt_indicator",
            "source_name": "Hydra Signals Indicator",
            "indicator": "Hydra Signals Indicator",
            "symbol": "XAUUSD",
            "timeframe": "M5",
            "status": "closed",
            "realized_pnl": 15.0,
        },
        {
            "source_type": "mt_indicator",
            "source_name": "Hydra Signals Indicator",
            "indicator": "Hydra Signals Indicator",
            "symbol": "XAUUSD",
            "timeframe": "M5",
            "status": "closed",
            "realized_pnl": -5.0,
        },
        {
            "source_type": "telegram_channel",
            "source_name": "Elite Pips Academy",
            "indicator": "",
            "symbol": "XAUUSD",
            "timeframe": "M5",
            "status": "closed",
            "realized_pnl": 4.0,
        },
    ]

    svc.get_automation_execution_logs = lambda limit=200: list(rows)  # type: ignore[method-assign]
    out = svc.get_automation_execution_report(limit=100)
    assert bool(out.get("ok")) is True
    report_rows = out.get("rows") or []
    assert len(report_rows) >= 2
    # Hydra combo total pnl = +10 should rank before Elite +4.
    assert float(report_rows[0].get("total_realized_pnl") or 0.0) >= float(report_rows[1].get("total_realized_pnl") or 0.0)


def test_append_closed_execution_log_from_row_passes_realized_and_extremes():
    svc = TelegramBridgeService()
    captured = {}

    def _fake_append(**kwargs):
        captured.update(kwargs)

    svc._append_automation_execution_log = _fake_append  # type: ignore[method-assign]
    svc._should_log_ticket_close = lambda ticket: True  # type: ignore[method-assign]
    svc._resolve_position_realized_stats = (  # type: ignore[method-assign]
        lambda **kwargs: {"realized_pnl": 12.34, "close_count": 1, "last_close_ts": "2026-04-09T10:00:00+00:00"}
    )

    class _DummySvc:
        pass

    svc._get_live_service = lambda: _DummySvc()  # type: ignore[method-assign]

    svc._append_closed_execution_log_from_row(
        row={
            "broker_ticket": 12345,
            "symbol": "XAUUSD",
            "timeframe": "M5",
            "direction": "BUY",
            "source_name": "Hydra Signals Indicator",
            "source_tag": "mt4|hydra|hydra signals indicator",
            "profile": "hydra",
            "indicator": "Hydra Signals Indicator",
            "stage_lots": [0.02, 0.01, 0.01, 0.01, 0.00],
            "max_profit": 25.0,
            "max_loss": -6.5,
        },
        reason="final_tp_reached",
        svc=_DummySvc(),  # type: ignore[arg-type]
    )

    assert str(captured.get("status") or "") == "closed"
    assert int(captured.get("ticket") or 0) == 12345
    assert abs(float(captured.get("realized_pnl") or 0.0) - 12.34) < 1e-9
    assert abs(float(captured.get("max_profit") or 0.0) - 25.0) < 1e-9
    assert abs(float(captured.get("max_loss") or 0.0) - (-6.5)) < 1e-9


def test_reverse_close_isolated_by_source_tag_combo():
    svc = TelegramBridgeService()
    closed = []

    class _Live:
        def close_position(self, **kwargs):
            closed.append(int(kwargs.get("position_ticket") or 0))
            return {"ok": True}

        def get_open_positions(self, symbol=None):
            return []

    svc._get_live_service = lambda: _Live()  # type: ignore[method-assign]
    svc._append_closed_execution_log_from_row = lambda **kwargs: None  # type: ignore[method-assign]
    svc._active_confirmation_signal_ladders = {
        "a": {
            "symbol": "XAUUSD",
            "timeframe": "M5",
            "direction": "BUY",
            "broker_ticket": 101,
            "source_tag": "mt4|fxnuke|fxnukeesc|XAUUSD|M5",
        },
        "b": {
            "symbol": "XAUUSD",
            "timeframe": "M5",
            "direction": "BUY",
            "broker_ticket": 202,
            "source_tag": "mt4|intrepid|intrepid trend direction|XAUUSD|M5",
        },
    }

    out = svc._close_mt4_reverse_positions(
        symbol="XAUUSD",
        incoming_direction="SELL",
        timeframe="M5",
        source_tag="mt4|fxnuke|fxnukeesc|XAUUSD|M5",
    )
    assert bool(out.get("ok")) is True
    assert closed == [101]
