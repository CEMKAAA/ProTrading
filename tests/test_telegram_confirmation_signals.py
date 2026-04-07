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
