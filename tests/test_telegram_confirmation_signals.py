from datetime import datetime, timedelta, timezone

from dashboard.backend.services.telegram_bridge_service import TelegramBridgeService


def test_parse_confirmation_signal_basic():
    raw = """
XAUUSD SELL NOW 4630/4635

TP1 4625
TP2 4620
TP3 4615
TP4 4610
TP5 4600

SL 4641
Follow risk management guys
"""
    parsed = TelegramBridgeService._parse_confirmation_signal(raw)
    assert isinstance(parsed, dict)
    assert parsed["symbol"] == "XAUUSD"
    assert parsed["direction"] == "SELL"
    assert parsed["entry_low"] == 4630.0
    assert parsed["entry_high"] == 4635.0
    assert parsed["stop_loss"] == 4641.0
    assert [row["index"] for row in parsed["tps"]] == [1, 2, 3, 4, 5]
    assert [row["price"] for row in parsed["tps"]] == [4625.0, 4620.0, 4615.0, 4610.0, 4600.0]


def test_parse_confirmation_signal_paroz_gold_format():
    raw = """
GOLD SELL 4653/4655

TP: 4651
TP: 4649
TP: 4647
TP: 4645
TP: 4643
TP: 4641
TP: 4639

SL: 4663
"""
    parsed = TelegramBridgeService._parse_confirmation_signal(raw)
    assert isinstance(parsed, dict)
    assert parsed["symbol"] == "XAUUSD"
    assert parsed["direction"] == "SELL"
    assert parsed["entry_low"] == 4653.0
    assert parsed["entry_high"] == 4655.0
    assert parsed["stop_loss"] == 4663.0
    assert [row["index"] for row in parsed["tps"]] == [1, 2, 3, 4, 5, 6, 7]
    assert [row["price"] for row in parsed["tps"]] == [4651.0, 4649.0, 4647.0, 4645.0, 4643.0, 4641.0, 4639.0]


def test_confirmation_signal_source_match_channel_title():
    msg = {"text": "XAUUSD SELL NOW 4630/4635", "chat": {"id": -1001}}
    chat = {"id": -1001, "title": "Elite Pips Academy", "type": "channel"}
    assert TelegramBridgeService._message_matches_confirm_signal_source(msg, chat) is True


def test_confirmation_signal_source_match_forward_origin():
    msg = {
        "text": "XAUUSD SELL NOW 4630/4635",
        "forward_origin": {
            "type": "channel",
            "chat": {"title": "Elite Pips Academy"},
        },
    }
    chat = {"id": 7119946313, "type": "private"}
    assert TelegramBridgeService._message_matches_confirm_signal_source(msg, chat) is True


def test_confirmation_signal_source_match_styled_unicode_title():
    msg = {"text": "XAUUSD SELL NOW 4630/4635", "chat": {"id": -1001}}
    chat = {"id": -1001, "title": "𝐄𝐥𝐢𝐭𝐞 𝐏𝐢𝐩𝐬 𝐀𝐜𝐚𝐝𝐞𝐦𝐲", "type": "channel"}
    assert TelegramBridgeService._message_matches_confirm_signal_source(msg, chat) is True


def test_confirmation_signal_detects_confirm_message():
    assert TelegramBridgeService._is_confirm_signal_message("Confirm Signal") is True
    assert TelegramBridgeService._is_confirm_signal_message("CONFIRM SIGNAL") is True
    assert TelegramBridgeService._is_confirm_signal_message("tp 1 hit") is False


def test_confirmation_signal_waits_for_confirm_before_execute(monkeypatch):
    svc = TelegramBridgeService()

    raw_signal = """
XAUUSD SELL NOW 4630/4635

TP1 4625
TP2 4620
TP3 4615
TP4 4610
TP5 4600

SL 4641
Follow risk management guys
"""

    class FakeLiveService:
        @staticmethod
        def get_recent_candles(symbol, timeframe, count, resolve_symbol):
            return [{"close": 4632.0}]

    svc._live_service = FakeLiveService()
    monkeypatch.setattr(svc, "_confirm_signal_requires_confirm", lambda: True)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", lambda *, chat_id, signal: "EXEC_OK")

    chat = {"id": -1001, "title": "Elite Pips Academy", "type": "channel"}
    msg = {"chat": chat}

    first = svc._handle_confirmation_signal_message(
        chat_id=7119946313,
        msg=msg,
        chat=chat,
        text=raw_signal,
        push_only=False,
    )
    assert isinstance(first, str)
    assert "Pending confirmation stored" in first

    second = svc._handle_confirmation_signal_message(
        chat_id=7119946313,
        msg=msg,
        chat=chat,
        text="Confirm Signal",
        push_only=False,
    )
    assert isinstance(second, str)
    assert "Confirm Signal received." in second
    assert "EXEC_OK" in second


def test_channel_specific_confirm_policy_elite_vs_paroz(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", lambda *, chat_id, signal: "EXEC_OK")
    monkeypatch.setattr(svc, "_confirm_signal_requires_confirm", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_require_confirm_titles", lambda: ["Elite Pips Academy"])
    monkeypatch.setattr(svc, "_confirm_signal_no_confirm_titles", lambda: ["PAROZGOLD_TRADER"])

    elite_text = """
XAUUSD SELL NOW 4660/4665
TP1 4655
TP2 4650
TP3 4645
TP4 4640
TP5 4630
SL 4670
"""
    paroz_text = """
GOLD SELL 4653/4655
TP: 4651
TP: 4649
TP: 4647
TP: 4645
TP: 4643
TP: 4641
TP: 4639
SL: 4663
"""
    elite = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg={"chat": {"id": -11, "title": "Elite Pips Academy"}},
        chat={"id": -11, "title": "Elite Pips Academy", "type": "channel"},
        text=elite_text,
        push_only=False,
    )
    assert isinstance(elite, str)
    assert "Pending confirmation stored" in elite

    paroz = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg={"chat": {"id": -12, "title": "PAROZGOLD_TRADER"}},
        chat={"id": -12, "title": "PAROZGOLD_TRADER", "type": "channel"},
        text=paroz_text,
        push_only=False,
    )
    assert isinstance(paroz, str)
    assert "EXEC_OK" in paroz
    assert "Pending confirmation stored" not in paroz


def test_source_match_rule_handles_spaced_vs_compact_alias():
    assert TelegramBridgeService._source_matches_rule("PAROZ GOLD TRADER", "PAROZGOLD_TRADER") is True
    assert TelegramBridgeService._source_matches_rule("t.me/PAROZGOLD_TRADER", "PAROZ GOLD TRADER") is True


def test_channel_specific_confirm_policy_paroz_styled_title_works_with_compact_no_confirm(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", lambda *, chat_id, signal: "EXEC_OK")
    monkeypatch.setattr(svc, "_confirm_signal_requires_confirm", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_require_confirm_titles", lambda: ["Elite Pips Academy"])
    monkeypatch.setattr(svc, "_confirm_signal_no_confirm_titles", lambda: ["PAROZGOLD_TRADER"])

    paroz_text = """
GOLD SELL 4653/4655
TP: 4651
TP: 4649
TP: 4647
TP: 4645
TP: 4643
TP: 4641
TP: 4639
SL: 4663
"""
    # Styled source title often comes from channel display name in Telethon bridge.
    styled_title = "𝐏𝐀𝐑𝐎𝐙 𝐆𝐎𝐋𝐃 𝐓𝐑𝐀𝐃𝐄𝐑"
    out = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg={"chat": {"id": -12, "title": styled_title}},
        chat={"id": -12, "title": styled_title, "type": "channel"},
        text=paroz_text,
        push_only=False,
    )
    assert isinstance(out, str)
    assert "EXEC_OK" in out
    assert "Pending confirmation stored" not in out


def test_channel_specific_confirm_policy_unknown_channel_no_confirm_when_require_list_defined(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", lambda *, chat_id, signal: "EXEC_OK")
    monkeypatch.setattr(svc, "_confirm_signal_requires_confirm", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_require_confirm_titles", lambda: ["Elite Pips Academy"])
    monkeypatch.setattr(svc, "_confirm_signal_no_confirm_titles", lambda: ["PAROZGOLD_TRADER"])

    raw = """
XAUUSD SELL NOW 4660/4665
TP1 4655
TP2 4650
TP3 4645
TP4 4640
TP5 4630
SL 4670
"""
    out = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg={"chat": {"id": -13, "title": "Another Gold Room"}},
        chat={"id": -13, "title": "Another Gold Room", "type": "channel"},
        text=raw,
        push_only=False,
    )
    assert isinstance(out, str)
    assert "EXEC_OK" in out
    assert "Pending confirmation stored" not in out


def test_confirmation_ladder_lots_reject_too_small_default_lot():
    svc = TelegramBridgeService()

    class FakeLiveService:
        @staticmethod
        def get_symbol_info(symbol):
            return {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0}

    svc._live_service = FakeLiveService()
    lots, err = svc._build_confirmation_ladder_lots(symbol="XAUUSD", total_lot=0.01, stage_count=5)
    assert lots is None
    assert "default_lot_too_small_for_5tp" in str(err)


def test_confirmation_ladder_lots_accept_splitable_lot():
    svc = TelegramBridgeService()

    class FakeLiveService:
        @staticmethod
        def get_symbol_info(symbol):
            return {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0}

    svc._live_service = FakeLiveService()
    lots, err = svc._build_confirmation_ladder_lots(symbol="XAUUSD", total_lot=0.05, stage_count=5)
    assert err is None
    assert lots == [0.01, 0.01, 0.01, 0.01, 0.01]


def test_confirmation_stage_units_modes():
    assert TelegramBridgeService._build_confirmation_stage_units(total_units=10, stage_count=5, mode="equal") == [2, 2, 2, 2, 2]
    assert TelegramBridgeService._build_confirmation_stage_units(total_units=10, stage_count=5, mode="front_loaded") == [3, 2, 2, 2, 1]
    assert TelegramBridgeService._build_confirmation_stage_units(total_units=10, stage_count=5, mode="runner") == [1, 2, 2, 2, 3]


def test_confirmation_ladder_lots_front_loaded_mode(monkeypatch):
    svc = TelegramBridgeService()

    class FakeLiveService:
        @staticmethod
        def get_symbol_info(symbol):
            return {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0}

    svc._live_service = FakeLiveService()
    monkeypatch.setattr(svc, "_confirm_signal_tp_distribution_mode", lambda: "front_loaded")
    lots, err = svc._build_confirmation_ladder_lots(symbol="XAUUSD", total_lot=0.10, stage_count=5)
    assert err is None
    assert lots == [0.03, 0.02, 0.02, 0.02, 0.01]


def test_confirmation_ladder_lots_runner_mode(monkeypatch):
    svc = TelegramBridgeService()

    class FakeLiveService:
        @staticmethod
        def get_symbol_info(symbol):
            return {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0}

    svc._live_service = FakeLiveService()
    monkeypatch.setattr(svc, "_confirm_signal_tp_distribution_mode", lambda: "runner")
    lots, err = svc._build_confirmation_ladder_lots(symbol="XAUUSD", total_lot=0.10, stage_count=5)
    assert err is None
    assert lots == [0.01, 0.02, 0.02, 0.02, 0.03]


def test_confirmation_ladder_lots_accept_demo_five_lot():
    svc = TelegramBridgeService()

    class FakeLiveService:
        @staticmethod
        def get_symbol_info(symbol):
            return {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0}

    svc._live_service = FakeLiveService()
    lots, err = svc._build_confirmation_ladder_lots(symbol="XAUUSD", total_lot=5.0, stage_count=5)
    assert err is None
    assert lots == [1.0, 1.0, 1.0, 1.0, 1.0]


def test_execute_confirmation_force_single_trade_01_mode(monkeypatch):
    svc = TelegramBridgeService()

    observed = {"lot": None, "stages": None}

    class FakeLiveService:
        @staticmethod
        def place_market_order(symbol, direction, lot_size, stop_loss, take_profit, comment):
            return {
                "ok": True,
                "position": 12345,
                "lot_size": float(lot_size),
            }

        @staticmethod
        def get_open_positions(symbol):
            return []

    svc._live_service = FakeLiveService()
    monkeypatch.setattr(svc, "_confirm_signal_force_single_trade_01", lambda: True)

    def _fake_build_lots(*, symbol, total_lot, stage_count):
        observed["lot"] = float(total_lot)
        observed["stages"] = int(stage_count)
        return [0.01], None

    monkeypatch.setattr(svc, "_build_confirmation_ladder_lots", _fake_build_lots)

    signal = {
        "symbol": "XAUUSD",
        "direction": "SELL",
        "stop_loss": 4670.0,
        "timeframe": "M5",
        "tps": [
            {"index": 1, "price": 4655.0},
            {"index": 2, "price": 4650.0},
            {"index": 3, "price": 4645.0},
            {"index": 4, "price": 4640.0},
            {"index": 5, "price": 4630.0},
        ],
    }
    out = svc._execute_confirmation_signal_auto(chat_id=1, signal=signal)
    assert "Confirmation ladder executed" in out
    assert "Stages: 1/5" in out
    assert "Stage mode: single_01" in out
    assert observed["lot"] == 0.01
    assert observed["stages"] == 1


def test_confirm_signal_feed_dedupes_same_source_and_message_id():
    svc = TelegramBridgeService()
    source = "Elite Pips Academy"
    chat = {"id": -1001, "title": source, "type": "channel"}
    text = "TP 1 HIT\n50+PIPS PROFIT DONE ENJOY"

    svc._append_confirm_signal_feed(
        source=source,
        chat=chat,
        text=text,
        kind="tp_hit",
        source_message_id=2282,
    )
    svc._append_confirm_signal_feed(
        source=source,
        chat=chat,
        text=text,
        kind="tp_hit",
        source_message_id=2282,
    )

    state = svc.get_telegram_automation_state(limit=100)
    feed = state.get("feed") if isinstance(state, dict) else []
    rows = [
        r
        for r in (feed or [])
        if int((r or {}).get("source_message_id") or 0) == 2282
        and str((r or {}).get("source") or "") == source
    ]
    assert len(rows) == 1


def test_confirm_signal_feed_keeps_same_message_id_for_different_sources():
    svc = TelegramBridgeService()
    svc._append_confirm_signal_feed(
        source="Elite Pips Academy",
        chat={"id": -1001, "title": "Elite Pips Academy", "type": "channel"},
        text="Confirm Signal",
        kind="confirm_signal",
        source_message_id=100,
    )
    svc._append_confirm_signal_feed(
        source="PAROZGOLD_TRADER",
        chat={"id": -1002, "title": "PAROZGOLD_TRADER", "type": "channel"},
        text="TP 1 HIT",
        kind="tp_hit",
        source_message_id=100,
    )
    state = svc.get_telegram_automation_state(limit=100)
    feed = state.get("feed") if isinstance(state, dict) else []
    rows = [r for r in (feed or []) if int((r or {}).get("source_message_id") or 0) == 100]
    assert len(rows) == 2


def test_ingest_mt4_indicator_signal_dedupes_duplicate_payload(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_mt4_exec_enabled", lambda: False)
    monkeypatch.setattr(svc, "_mt4_exec_dedupe_window_sec", lambda: 120.0)

    payload = {
        "indicator": "Hydra Signals Indicator",
        "signal_profile": "hydra",
        "signal_hint": "BUY",
        "symbol": "USDJPY",
        "timeframe": "M5",
        "message": "HYDRA BUY SIGNAL USDJPY",
        "event_ts": datetime.now(timezone.utc).isoformat(),
    }
    first = svc.ingest_mt4_indicator_signal(payload=payload)
    second = svc.ingest_mt4_indicator_signal(payload=payload)

    assert first.get("ok") is True
    assert first.get("executed") is False
    assert first.get("reason") == "mt4_execution_disabled"
    assert second.get("ok") is True
    assert second.get("executed") is False
    assert second.get("reason") == "duplicate_signal"


def test_ingest_mt4_indicator_signal_rejects_stale_event(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_mt4_exec_max_signal_age_sec", lambda: 10.0)
    monkeypatch.setattr(svc, "_mt4_exec_enabled", lambda: False)

    old_ts = (datetime.now(timezone.utc) - timedelta(minutes=2)).isoformat()
    payload = {
        "indicator": "Intrepid",
        "signal_profile": "intrepid",
        "signal_hint": "SELL",
        "symbol": "XAUUSD",
        "timeframe": "M5",
        "message": "INTREPID SELL SIGNAL XAUUSD",
        "event_ts": old_ts,
    }
    out = svc.ingest_mt4_indicator_signal(payload=payload)
    assert out.get("ok") is True
    assert out.get("executed") is False
    assert out.get("reason") == "stale_signal"
