from datetime import datetime, timedelta, timezone
import time

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


def test_parse_confirmation_signal_gold_vip_plain_tp_and_sl():
    raw = """
XAUUSD BUY 4608/4605

TP 4613
TP 4617
TP 4622
TP 4626
TP 4631
TP 4636
TP 4641
TP 4646
TP 4651
TP 4656
TP 4661
SL 4592
"""
    parsed = TelegramBridgeService._parse_confirmation_signal(raw)
    assert isinstance(parsed, dict)
    assert parsed["symbol"] == "XAUUSD"
    assert parsed["direction"] == "BUY"
    assert parsed["entry_low"] == 4605.0
    assert parsed["entry_high"] == 4608.0
    assert parsed["stop_loss"] == 4592.0
    assert [row["index"] for row in parsed["tps"]] == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    assert [row["price"] for row in parsed["tps"]] == [4613.0, 4617.0, 4622.0, 4626.0, 4631.0, 4636.0, 4641.0, 4646.0, 4651.0, 4656.0, 4661.0]


def test_parse_confirmation_signal_fx_mastermind_hash_and_superscripts():
    raw = """
#XAUUSD_SELL 4650/4655.00

TP¹ 4647.00
TP² 4644.00
TP³ 4641.00
TP⁴ 4638.00
TP⁵ 4635.00
TP⁶ 4632.00

SL¹ 4665.00
"""
    parsed = TelegramBridgeService._parse_confirmation_signal(raw)
    assert isinstance(parsed, dict)
    assert parsed["symbol"] == "XAUUSD"
    assert parsed["direction"] == "SELL"
    assert parsed["entry_low"] == 4650.0
    assert parsed["entry_high"] == 4655.0
    assert parsed["stop_loss"] == 4665.0
    assert [row["index"] for row in parsed["tps"]] == [1, 2, 3, 4, 5, 6]
    assert [row["price"] for row in parsed["tps"]] == [4647.0, 4644.0, 4641.0, 4638.0, 4635.0, 4632.0]


def test_parse_confirmation_signal_market_analysis_king_single_entry():
    raw = """
XAUUSD SELL 4664

TP 4662
TP 4660
TP 4658
TP 4656
TP 4654

SL 4674
"""
    parsed = TelegramBridgeService._parse_confirmation_signal(raw)
    assert isinstance(parsed, dict)
    assert parsed["symbol"] == "XAUUSD"
    assert parsed["direction"] == "SELL"
    assert parsed["entry_low"] == 4664.0
    assert parsed["entry_high"] == 4664.0
    assert parsed["entry_mid"] == 4664.0
    assert parsed["stop_loss"] == 4674.0
    assert [row["index"] for row in parsed["tps"]] == [1, 2, 3, 4, 5]
    assert [row["price"] for row in parsed["tps"]] == [4662.0, 4660.0, 4658.0, 4656.0, 4654.0]


def test_parse_confirmation_signal_henry_trader_hashtag_and_dash_range():
    raw = """
#XAUUSD #GOLD BUY 4805 - 4800

TP 4808- TP 4811 - TP 4614
TP 4817- TP 4820- TP 4823
TP 4830

SL 4792 Use lot size small
"""
    parsed = TelegramBridgeService._parse_confirmation_signal(raw)
    assert isinstance(parsed, dict)
    assert parsed["symbol"] == "XAUUSD"
    assert parsed["direction"] == "BUY"
    assert parsed["entry_low"] == 4800.0
    assert parsed["entry_high"] == 4805.0
    assert parsed["stop_loss"] == 4792.0
    assert [row["index"] for row in parsed["tps"]] == [1, 2, 3, 4, 5, 6, 7]
    assert [row["price"] for row in parsed["tps"]] == [4808.0, 4811.0, 4614.0, 4817.0, 4820.0, 4823.0, 4830.0]


def test_parse_confirmation_signal_henry_trader_underscore_format():
    raw = """
#XAUUSD_BUY 4801 / 4798

TP 4804- TP 4807 - TP 4610
TP 4813- TP 4816- TP 4820
TP 4823

SL 4787 Use lot size small
"""
    parsed = TelegramBridgeService._parse_confirmation_signal(raw)
    assert isinstance(parsed, dict)
    assert parsed["symbol"] == "XAUUSD"
    assert parsed["direction"] == "BUY"
    assert parsed["entry_low"] == 4798.0
    assert parsed["entry_high"] == 4801.0
    assert parsed["stop_loss"] == 4787.0
    assert [row["index"] for row in parsed["tps"]] == [1, 2, 3, 4, 5, 6, 7]
    assert [row["price"] for row in parsed["tps"]] == [4804.0, 4807.0, 4610.0, 4813.0, 4816.0, 4820.0, 4823.0]


def test_classify_confirmation_signal_henry_header_as_signal():
    raw = "#XAUUSD #GOLD BUY 4805 - 4800"
    assert TelegramBridgeService._classify_confirm_signal_message(raw) == "signal"


def test_source_scoped_classifier_rejects_henry_teaser_header():
    raw = "#XAUUSD #GOLD BUY 4805 - 4800"
    kind = TelegramBridgeService._classify_confirm_signal_message_for_sources(
        raw,
        source_names=["HENRY TRADER"],
    )
    parsed = TelegramBridgeService._parse_confirmation_signal_for_sources(
        raw,
        source_names=["HENRY TRADER"],
    )
    assert kind == "other"
    assert parsed is None


def test_tp_progress_gate_applies_only_to_henry_and_gold_vip_profiles():
    assert TelegramBridgeService._profile_requires_tp_progress_gate("henry") is True
    assert TelegramBridgeService._profile_requires_tp_progress_gate("gold_vip") is True
    assert TelegramBridgeService._profile_requires_tp_progress_gate("elite") is False
    assert TelegramBridgeService._profile_requires_tp_progress_gate("paroz") is False
    assert TelegramBridgeService._profile_requires_tp_progress_gate("fx_mastermind") is False
    assert TelegramBridgeService._profile_requires_tp_progress_gate("market_king") is False
    assert TelegramBridgeService._profile_requires_tp_progress_gate("generic") is False


def test_source_scoped_classifier_accepts_henry_on_henry_channel():
    raw = """
#XAUUSD #GOLD BUY 4805 - 4800
TP 4808- TP 4811 - TP 4814
SL 4792
"""
    kind = TelegramBridgeService._classify_confirm_signal_message_for_sources(
        raw,
        source_names=["HENRY TRADER"],
    )
    parsed = TelegramBridgeService._parse_confirmation_signal_for_sources(
        raw,
        source_names=["HENRY TRADER"],
    )
    assert kind == "signal"
    assert isinstance(parsed, dict)


def test_source_scoped_classifier_rejects_henry_style_on_elite_channel():
    raw = """
#XAUUSD #GOLD BUY 4805 - 4800
TP 4808- TP 4811 - TP 4814
SL 4792
"""
    kind = TelegramBridgeService._classify_confirm_signal_message_for_sources(
        raw,
        source_names=["Elite Pips Academy"],
    )
    parsed = TelegramBridgeService._parse_confirmation_signal_for_sources(
        raw,
        source_names=["Elite Pips Academy"],
    )
    assert kind == "other"
    assert parsed is None


def test_handle_confirmation_signal_routes_henry_source_profile_to_executor(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_confirm_signal_requires_confirm", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_require_confirm_titles", lambda: ["Elite Pips Academy"])
    monkeypatch.setattr(svc, "_confirm_signal_no_confirm_titles", lambda: [])
    monkeypatch.setattr(svc, "_confirm_signal_wait_entry_zone", lambda: False)

    seen = {"n": 0, "profile": ""}

    def _fake_exec(**kwargs):
        sig = kwargs.get("signal") if isinstance(kwargs.get("signal"), dict) else {}
        seen["n"] += 1
        seen["profile"] = str(sig.get("source_profile") or "")
        return "EXEC_OK"

    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", _fake_exec)

    raw = """
#XAUUSD #GOLD BUY 4805 - 4800
TP 4808- TP 4811 - TP 4814
TP 4817- TP 4820- TP 4823
SL 4792
"""
    out = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg={"chat": {"id": -21, "title": "HENRY TRADER"}},
        chat={"id": -21, "title": "HENRY TRADER", "type": "channel"},
        text=raw,
        push_only=False,
    )
    assert isinstance(out, str)
    assert "EXEC_OK" in out
    assert seen["n"] == 1
    assert seen["profile"] == "henry"


def test_handle_confirmation_signal_rejects_henry_payload_on_elite_source(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)

    seen = {"n": 0}

    def _fake_exec(**kwargs):
        seen["n"] += 1
        return "EXEC_OK"

    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", _fake_exec)

    raw = """
#XAUUSD #GOLD BUY 4805 - 4800
TP 4808- TP 4811 - TP 4814
SL 4792
"""
    out = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg={"chat": {"id": -22, "title": "Elite Pips Academy"}},
        chat={"id": -22, "title": "Elite Pips Academy", "type": "channel"},
        text=raw,
        push_only=False,
    )
    assert out is None
    assert seen["n"] == 0


def test_ingest_external_message_applies_source_scoped_detection_engine():
    svc = TelegramBridgeService()

    raw = """
#XAUUSD #GOLD BUY 4805 - 4800
TP 4808- TP 4811 - TP 4814
SL 4792
"""
    # Same payload, two different sources -> different detection outcomes.
    svc.ingest_external_channel_message(
        source_title="Elite Pips Academy",
        text=raw,
        source_message_id=1001,
        source_message_ts=datetime.now(timezone.utc).isoformat(),
    )
    svc.ingest_external_channel_message(
        source_title="HENRY TRADER",
        text=raw,
        source_message_id=1002,
        source_message_ts=datetime.now(timezone.utc).isoformat(),
    )

    st = svc.get_telegram_automation_state(limit=200)
    feed = list(st.get("feed") or [])
    elite_row = next((r for r in feed if int(r.get("source_message_id") or 0) == 1001), None)
    henry_row = next((r for r in feed if int(r.get("source_message_id") or 0) == 1002), None)

    assert isinstance(elite_row, dict)
    assert isinstance(henry_row, dict)
    assert str(elite_row.get("kind") or "") == "other"
    assert str(henry_row.get("kind") or "") == "signal"


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


def test_close_now_message_classified_and_parsed_as_close_instruction():
    raw = """
#XAUUSD_SELL
Close now
We have done already 100+ Pips profit
"""
    assert TelegramBridgeService._classify_confirm_signal_message(raw) == "close_instruction"
    hint = TelegramBridgeService._parse_close_instruction_signal_hint(raw)
    assert bool(hint.get("is_close_instruction")) is True
    assert str(hint.get("symbol") or "") == "XAUUSD"
    assert str(hint.get("direction") or "") == "SELL"


def test_classify_fx_mastermind_tp_hit_with_superscript_is_not_signal():
    raw = """
#XAUUSD_BUY

TP ⁶ HIT( ENJOY PROFIT )WITH 180+ PIPS DONE
"""
    assert TelegramBridgeService._classify_confirm_signal_message(raw) == "tp_hit"


def test_classify_all_target_hit_message_as_tp_hit():
    raw = """
#XAUUSD_BUY

All Target successfully hit 4844 hit
With 360+ PIPs profit done
"""
    assert TelegramBridgeService._classify_confirm_signal_message(raw) == "tp_hit"


def test_source_scoped_gold_vip_requires_full_signal_payload():
    raw_short = "XAUUSD BUY 4800"
    raw_full = """
XAUUSD BUY 4800/4797
TP 4803
TP 4806
TP 4809
SL 4785
"""
    kind_short = TelegramBridgeService._classify_confirm_signal_message_for_sources(
        raw_short,
        source_names=["GOLD VIP SIGNALS"],
    )
    kind_full = TelegramBridgeService._classify_confirm_signal_message_for_sources(
        raw_full,
        source_names=["GOLD VIP SIGNALS"],
    )
    assert kind_short == "other"
    assert kind_full == "signal"


def test_henry_reentry_blocked_until_tp_progress(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_confirm_signal_requires_confirm_for_sources", lambda source_names: False)
    monkeypatch.setattr(svc, "_confirm_signal_wait_entry_zone", lambda: False)

    seen = {"exec": 0}

    def _fake_exec(**kwargs):
        seen["exec"] += 1
        return "EXEC_OK"

    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", _fake_exec)

    chat = {"id": -77, "title": "HENRY TRADER", "type": "channel"}
    msg = {"chat": chat}
    sig_a = """
#XAUUSD_BUY 4805 / 4800

TP 4808- TP 4811 - TP 4814
TP 4817- TP 4820- TP 4823
TP 4830

SL 4792 Use lot size small
"""
    sig_b = """
#XAUUSD_BUY 4801 / 4798

TP 4804- TP 4807 - TP 4810
TP 4813- TP 4816- TP 4820
TP 4823

SL 4787 Use lot size small
"""

    out_a = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg=msg,
        chat=chat,
        text=sig_a,
        push_only=False,
    )
    assert isinstance(out_a, str) and "EXEC_OK" in out_a
    assert seen["exec"] == 1

    out_b_blocked = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg=msg,
        chat=chat,
        text=sig_b,
        push_only=False,
    )
    assert isinstance(out_b_blocked, str) and "Signal ignored (previous cycle still has no TP progress)" in out_b_blocked
    assert seen["exec"] == 1

    tp_msg = "#XAUUSD_BUY\nTP 1 HIT"
    svc._handle_confirmation_signal_message(
        chat_id=123,
        msg=msg,
        chat=chat,
        text=tp_msg,
        push_only=False,
    )

    out_b_after_tp = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg=msg,
        chat=chat,
        text=sig_b,
        push_only=False,
    )
    assert isinstance(out_b_after_tp, str) and "EXEC_OK" in out_b_after_tp
    assert seen["exec"] == 2


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
    monkeypatch.setattr(svc, "_confirm_signal_wait_entry_zone", lambda: False)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", lambda *, chat_id, signal, audit_ctx=None: "EXEC_OK")

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


def test_confirm_signal_executes_direct_even_if_wait_entry_zone_enabled(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_requires_confirm", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_wait_entry_zone", lambda: True)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_confirm_signal_require_confirm_titles", lambda: ["Elite Pips Academy"])
    monkeypatch.setattr(svc, "_confirm_signal_no_confirm_titles", lambda: [])
    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", lambda *, chat_id, signal, audit_ctx=None: "EXEC_OK")

    raw_signal = """
XAUUSD SELL NOW 4630/4635
TP1 4625
TP2 4620
TP3 4615
TP4 4610
TP5 4600
SL 4641
"""
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
    assert "EXEC_OK" in second
    st = svc.get_telegram_automation_state(limit=20)
    assert int(st.get("pending_entry_count") or 0) == 0


def test_no_confirm_signal_waits_for_entry_zone_then_executes(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_confirm_signal_requires_confirm", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_require_confirm_titles", lambda: ["Elite Pips Academy"])
    monkeypatch.setattr(svc, "_confirm_signal_no_confirm_titles", lambda: ["PAROZGOLD_TRADER"])
    monkeypatch.setattr(svc, "_confirm_signal_wait_entry_zone", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_entry_wait_max_sec", lambda: 300.0)
    monkeypatch.setattr(svc, "_confirm_signal_entry_attempt_cooldown_sec", lambda: 0.0)
    monkeypatch.setattr(svc, "_signal_live_price", lambda *, signal: float(signal.get("entry_high") or 0.0))

    seen = {"n": 0}

    def _fake_exec(**kwargs):
        seen["n"] += 1
        sig = kwargs.get("signal") if isinstance(kwargs.get("signal"), dict) else {}
        return f"Confirmation ladder executed\nSymbol: {str(sig.get('symbol') or '')}"

    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", _fake_exec)

    raw = """
GOLD SELL 4653/4655
TP: 4651
TP: 4649
TP: 4647
TP: 4645
TP: 4643
SL: 4663
"""
    out = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg={"chat": {"id": -12, "title": "PAROZGOLD_TRADER"}},
        chat={"id": -12, "title": "PAROZGOLD_TRADER", "type": "channel"},
        text=raw,
        push_only=False,
    )
    assert isinstance(out, str)
    assert "Signal queued" in out
    st0 = svc.get_telegram_automation_state(limit=50)
    assert int(st0.get("pending_entry_count") or 0) == 1
    svc._push_pending_entry_signals()
    st1 = svc.get_telegram_automation_state(limit=50)
    assert int(st1.get("pending_entry_count") or 0) == 0
    assert seen["n"] == 1


def test_pending_entry_executes_on_cross_without_inside(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_entry_wait_max_sec", lambda: 300.0)
    monkeypatch.setattr(svc, "_confirm_signal_entry_attempt_cooldown_sec", lambda: 0.0)
    monkeypatch.setattr(svc, "_signal_live_price", lambda *, signal: 4668.0)  # outside zone (above)
    monkeypatch.setattr(svc, "_signal_recent_zone_touch", lambda *, signal: False)

    seen = {"n": 0}

    def _fake_exec(**kwargs):
        seen["n"] += 1
        return "Confirmation ladder executed"

    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", _fake_exec)

    signal = {
        "symbol": "XAUUSD",
        "direction": "SELL",
        "entry_low": 4660.0,
        "entry_high": 4665.0,
        "stop_loss": 4670.0,
        "tps": [{"index": 1, "price": 4655.0}],
    }
    q = svc._queue_entry_signal(
        chat_id=1,
        signal=signal,
        source_label="PAROZ",
        source_key="1:paroz",
    )
    with svc._lock:
        cur = dict(svc._pending_entry_signals.get(str(q.get("id"))) or {})
        cur["last_zone_state"] = "below_zone"
        svc._pending_entry_signals[str(q.get("id"))] = dict(cur)

    svc._push_pending_entry_signals()
    st = svc.get_telegram_automation_state(limit=20)
    assert int(st.get("pending_entry_count") or 0) == 0
    assert seen["n"] == 1


def test_pending_entry_executes_on_recent_touch_fallback(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_entry_wait_max_sec", lambda: 300.0)
    monkeypatch.setattr(svc, "_confirm_signal_entry_attempt_cooldown_sec", lambda: 0.0)
    monkeypatch.setattr(svc, "_signal_live_price", lambda *, signal: 4668.0)  # outside zone
    monkeypatch.setattr(svc, "_signal_recent_zone_touch", lambda *, signal: True)

    seen = {"n": 0}

    def _fake_exec(**kwargs):
        seen["n"] += 1
        return "Confirmation ladder executed"

    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", _fake_exec)

    signal = {
        "symbol": "XAUUSD",
        "direction": "SELL",
        "entry_low": 4660.0,
        "entry_high": 4665.0,
        "stop_loss": 4670.0,
        "tps": [{"index": 1, "price": 4655.0}],
    }
    svc._queue_entry_signal(
        chat_id=1,
        signal=signal,
        source_label="PAROZ",
        source_key="1:paroz",
    )
    svc._push_pending_entry_signals()
    st = svc.get_telegram_automation_state(limit=20)
    assert int(st.get("pending_entry_count") or 0) == 0
    assert seen["n"] == 1


def test_close_instruction_closes_only_matching_source_position(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)

    class FakeLiveService:
        def __init__(self):
            self.closed = []

        def close_position(self, *, symbol, position_ticket, comment):
            self.closed.append((str(symbol), int(position_ticket), str(comment)))
            return {"ok": True}

    live = FakeLiveService()
    svc._live_service = live

    # Source A (Fx Mastermind) and Source B (another channel) both have XAUUSD SELL.
    source_a = svc._confirm_signal_source_key(123, "Trade With Fx Mastermind")
    source_b = svc._confirm_signal_source_key(123, "PAROZGOLD_TRADER")
    svc._register_confirmation_ladder(
        chat_id=123,
        session_id=0,
        symbol="XAUUSD",
        timeframe="M5",
        direction="SELL",
        trade_id=0,
        broker_ticket=1111,
        stage_lots=[0.01],
        tps=[{"index": 1, "price": 4797.0}],
        source_tag="telegram_noconfirm",
        order_comment="a111",
        source_key=source_a,
        source_name="Trade With Fx Mastermind",
    )
    svc._register_confirmation_ladder(
        chat_id=123,
        session_id=0,
        symbol="XAUUSD",
        timeframe="M5",
        direction="SELL",
        trade_id=0,
        broker_ticket=2222,
        stage_lots=[0.01],
        tps=[{"index": 1, "price": 4797.0}],
        source_tag="telegram_noconfirm",
        order_comment="b222",
        source_key=source_b,
        source_name="PAROZGOLD_TRADER",
    )

    close_msg = """#XAUUSD_SELL

Close it
Wait for better sniper entry
"""
    out = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg={"chat": {"id": -88, "title": "Trade With Fx Mastermind"}},
        chat={"id": -88, "title": "Trade With Fx Mastermind", "type": "channel"},
        text=close_msg,
        push_only=False,
    )
    assert isinstance(out, str)
    assert "Close instruction executed" in out
    assert "1111" in out
    assert live.closed == [("XAUUSD", 1111, "tg_close_instruction")]
    st = svc.get_telegram_automation_state(limit=20)
    assert int(st.get("active_ladder_count") or 0) == 1


def test_confirm_pending_keeps_multi_symbol_same_source_without_overwrite(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_requires_confirm", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_wait_entry_zone", lambda: False)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_confirm_signal_require_confirm_titles", lambda: ["Elite Pips Academy"])
    monkeypatch.setattr(svc, "_confirm_signal_no_confirm_titles", lambda: [])

    seen = {"symbols": []}

    def _fake_exec(**kwargs):
        sig = kwargs.get("signal") if isinstance(kwargs.get("signal"), dict) else {}
        sym = str(sig.get("symbol") or "").upper()
        seen["symbols"].append(sym)
        return f"EXEC_{sym}"

    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", _fake_exec)

    raw_xau = """
XAUUSD SELL NOW 4660/4665
TP1 4655
TP2 4650
TP3 4645
TP4 4640
TP5 4630
SL 4670
"""
    raw_eur = """
EURUSD BUY NOW 1.0800/1.0810
TP1 1.0820
TP2 1.0830
TP3 1.0840
TP4 1.0850
TP5 1.0860
SL 1.0780
"""
    chat = {"id": -11, "title": "Elite Pips Academy", "type": "channel"}
    msg = {"chat": chat}

    out1 = svc._handle_confirmation_signal_message(chat_id=123, msg=msg, chat=chat, text=raw_xau, push_only=False)
    out2 = svc._handle_confirmation_signal_message(chat_id=123, msg=msg, chat=chat, text=raw_eur, push_only=False)
    assert isinstance(out1, str) and "Pending confirmation stored" in out1
    assert isinstance(out2, str) and "Pending confirmation stored" in out2
    st0 = svc.get_telegram_automation_state(limit=50)
    assert int(st0.get("pending_confirm_count") or 0) == 2

    conf = svc._handle_confirmation_signal_message(chat_id=123, msg=msg, chat=chat, text="Confirm Signal", push_only=False)
    assert isinstance(conf, str)
    assert "EXEC_EURUSD" in conf
    st1 = svc.get_telegram_automation_state(limit=50)
    assert int(st1.get("pending_confirm_count") or 0) == 1
    assert seen["symbols"] == ["EURUSD"]


def test_channel_specific_confirm_policy_elite_vs_paroz(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_wait_entry_zone", lambda: False)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", lambda *, chat_id, signal, audit_ctx=None: "EXEC_OK")
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
    monkeypatch.setattr(svc, "_confirm_signal_wait_entry_zone", lambda: False)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", lambda *, chat_id, signal, audit_ctx=None: "EXEC_OK")
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
    monkeypatch.setattr(svc, "_confirm_signal_wait_entry_zone", lambda: False)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", lambda *, chat_id, signal, audit_ctx=None: "EXEC_OK")
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


def test_no_confirm_channel_executes_without_waiting_for_market_snapshot(monkeypatch):
    svc = TelegramBridgeService()
    monkeypatch.setattr(svc, "_confirm_signal_enabled", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_wait_entry_zone", lambda: False)
    monkeypatch.setattr(svc, "_message_matches_confirm_signal_source", lambda msg, chat: True)
    monkeypatch.setattr(svc, "_confirm_signal_requires_confirm", lambda: True)
    monkeypatch.setattr(svc, "_confirm_signal_require_confirm_titles", lambda: ["Elite Pips Academy"])
    monkeypatch.setattr(svc, "_confirm_signal_no_confirm_titles", lambda: ["PAROZGOLD_TRADER"])
    monkeypatch.setattr(svc, "_execute_confirmation_signal_auto", lambda *, chat_id, signal, audit_ctx=None: "EXEC_OK")

    class FakeLiveService:
        @staticmethod
        def get_recent_candles(symbol, timeframe, count, resolve_symbol):
            raise AssertionError("no-confirm flow should not call market snapshot before execution")

    svc._live_service = FakeLiveService()

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
    out = svc._handle_confirmation_signal_message(
        chat_id=123,
        msg={"chat": {"id": -12, "title": "PAROZGOLD_TRADER"}},
        chat={"id": -12, "title": "PAROZGOLD_TRADER", "type": "channel"},
        text=raw,
        push_only=False,
    )
    assert isinstance(out, str)
    assert "EXEC_OK" in out


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


def test_mt4_exec_profile_enabled_supports_alchemy(monkeypatch):
    monkeypatch.setattr(TelegramBridgeService, "_get_env_value", staticmethod(lambda _k, d="": d))
    assert TelegramBridgeService._mt4_exec_profile_enabled("alchemy") is True


def test_execute_confirmation_force_single_trade_mode_uses_operator_lot(monkeypatch):
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
    monkeypatch.setattr(svc, "_confirm_signal_default_lot", lambda: 0.05)

    def _fake_build_lots(*, symbol, total_lot, stage_count):
        observed["lot"] = float(total_lot)
        observed["stages"] = int(stage_count)
        return [float(total_lot)], None

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
    assert "Stage mode: single_trade" in out
    assert "Final TP: 4630.00000" in out
    assert observed["lot"] == 0.05
    assert observed["stages"] == 1


def test_execute_confirmation_gold_vip_many_tps_keeps_last_target_when_stage_reduced(monkeypatch):
    svc = TelegramBridgeService()
    observed = {"tp": None}

    class FakeLiveService:
        @staticmethod
        def place_market_order(symbol, direction, lot_size, stop_loss, take_profit, comment):
            observed["tp"] = float(take_profit)
            return {
                "ok": True,
                "position": 22334,
                "lot_size": float(lot_size),
            }

        @staticmethod
        def get_open_positions(symbol):
            return []

        @staticmethod
        def get_symbol_info(symbol):
            return {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0}

    svc._live_service = FakeLiveService()
    monkeypatch.setattr(svc, "_confirm_signal_force_single_trade_01", lambda: False)
    monkeypatch.setattr(svc, "_confirm_signal_default_lot", lambda: 0.05)

    signal = {
        "symbol": "XAUUSD",
        "direction": "BUY",
        "stop_loss": 4771.0,
        "timeframe": "M5",
        "source_profile": "gold_vip",
        "tps": [
            {"index": 1, "price": 4790.0},
            {"index": 2, "price": 4793.0},
            {"index": 3, "price": 4796.0},
            {"index": 4, "price": 4799.0},
            {"index": 5, "price": 4802.0},
            {"index": 6, "price": 4805.0},
            {"index": 7, "price": 4808.0},
            {"index": 8, "price": 4811.0},
            {"index": 9, "price": 4814.0},
            {"index": 10, "price": 4817.0},
            {"index": 11, "price": 4820.0},
        ],
    }
    out = svc._execute_confirmation_signal_auto(chat_id=1, signal=signal)
    assert "Confirmation ladder executed" in out
    assert "Stages: 5/11" in out
    assert "Final TP: 4820.00000" in out
    assert observed["tp"] == 4820.0


def test_execute_confirmation_elite_profile_remains_fixed_5tp(monkeypatch):
    svc = TelegramBridgeService()
    observed = {"tp": None}

    class FakeLiveService:
        @staticmethod
        def place_market_order(symbol, direction, lot_size, stop_loss, take_profit, comment):
            observed["tp"] = float(take_profit)
            return {
                "ok": True,
                "position": 99887,
                "lot_size": float(lot_size),
            }

        @staticmethod
        def get_open_positions(symbol):
            return []

        @staticmethod
        def get_symbol_info(symbol):
            return {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0}

    svc._live_service = FakeLiveService()
    monkeypatch.setattr(svc, "_confirm_signal_force_single_trade_01", lambda: False)
    monkeypatch.setattr(svc, "_confirm_signal_default_lot", lambda: 0.20)

    signal = {
        "symbol": "XAUUSD",
        "direction": "BUY",
        "stop_loss": 4771.0,
        "timeframe": "M5",
        "source_profile": "elite",
        "tps": [
            {"index": 1, "price": 4790.0},
            {"index": 2, "price": 4793.0},
            {"index": 3, "price": 4796.0},
            {"index": 4, "price": 4799.0},
            {"index": 5, "price": 4802.0},
            {"index": 6, "price": 4805.0},
            {"index": 7, "price": 4808.0},
            {"index": 8, "price": 4811.0},
            {"index": 9, "price": 4814.0},
            {"index": 10, "price": 4817.0},
            {"index": 11, "price": 4820.0},
        ],
    }
    out = svc._execute_confirmation_signal_auto(chat_id=1, signal=signal)
    assert "Confirmation ladder executed" in out
    assert "Stages: 5/11" in out
    assert "Final TP: 4802.00000" in out
    assert observed["tp"] == 4802.0


def test_execute_confirmation_market_closed_is_deferred():
    svc = TelegramBridgeService()

    class FakeLiveService:
        @staticmethod
        def place_market_order(symbol, direction, lot_size, stop_loss, take_profit, comment):
            return {
                "ok": False,
                "error": "order_send_failed:10018:TRADE_RETCODE_MARKET_CLOSED:Market closed",
            }

        @staticmethod
        def get_open_positions(symbol):
            return []

        @staticmethod
        def get_symbol_info(symbol):
            return {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0}

    svc._live_service = FakeLiveService()
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
    out = svc._execute_confirmation_signal_auto(chat_id=1, signal=signal, lot_override=0.01)
    assert out.lower().startswith("confirmation deferred: market closed")

    st = svc.get_telegram_automation_state(limit=100)
    logs = [dict(x) for x in (st.get("execution_logs") or [])]
    assert logs
    row = logs[-1]
    assert str(row.get("status") or "") == "deferred"
    assert str(row.get("message") or "") == "market_closed"


def test_execution_audit_logs_persist_across_service_instances():
    marker = f"persist_marker_{int(time.time() * 1000)}"
    svc_a = TelegramBridgeService()
    svc_a._append_automation_execution_log(
        source_type="telegram_channel",
        source_name="persist_test",
        trigger="unit_test",
        status="success",
        symbol="XAUUSD",
        timeframe="M5",
        direction="BUY",
        lot=0.05,
        ticket=123456789,
        message=marker,
    )

    svc_b = TelegramBridgeService()
    rows = svc_b.get_automation_execution_logs(limit=1000)
    assert any(str((r or {}).get("message") or "") == marker for r in rows)


def test_execute_confirmation_retries_invalid_stops_and_succeeds():
    svc = TelegramBridgeService()
    calls = {"n": 0}

    class FakeLiveService:
        @staticmethod
        def place_market_order(symbol, direction, lot_size, stop_loss, take_profit, comment):
            calls["n"] += 1
            if calls["n"] == 1:
                return {
                    "ok": False,
                    "error": "order_send_failed:10016:TRADE_RETCODE_INVALID_STOPS:Invalid stops",
                }
            return {"ok": True, "position": 777001, "lot_size": float(lot_size)}

        @staticmethod
        def get_open_positions(symbol):
            return []

        @staticmethod
        def get_symbol_info(symbol):
            return {
                "digits": 3,
                "point": 0.001,
                "trade_stops_level": 80,
                "trade_freeze_level": 0,
                "volume_min": 0.01,
                "volume_step": 0.01,
                "volume_max": 100.0,
            }

        @staticmethod
        def get_symbol_tick(symbol, resolve_symbol=False):
            return {"bid": 159.630, "ask": 159.632, "last": 159.631}

    svc._live_service = FakeLiveService()
    signal = {
        "symbol": "USDJPYm",
        "direction": "BUY",
        "stop_loss": 159.628,
        "timeframe": "M5",
        "tps": [
            {"index": 1, "price": 159.633},
            {"index": 2, "price": 159.634},
            {"index": 3, "price": 159.635},
            {"index": 4, "price": 159.636},
            {"index": 5, "price": 159.637},
        ],
    }
    out = svc._execute_confirmation_signal_auto(chat_id=1, signal=signal, lot_override=0.01)
    assert "Confirmation ladder executed" in out
    assert calls["n"] == 2


def test_mt_indicator_no_sl_weighted_ladder_and_partial_close(monkeypatch):
    svc = TelegramBridgeService()
    obs = {"comment": "", "open_stop_loss": "sentinel", "close_calls": []}

    class FakeLiveService:
        @staticmethod
        def place_market_order(symbol, direction, lot_size, stop_loss, take_profit, comment):
            obs["comment"] = str(comment)
            obs["open_stop_loss"] = stop_loss
            return {"ok": True, "position": 880001, "lot_size": float(lot_size)}

        @staticmethod
        def get_open_positions(symbol):
            # Keep price above TP1; ladder runner closes one stage per poll tick.
            return [
                {
                    "ticket": 880001,
                    "direction": "BUY",
                    "comment": str(obs.get("comment") or ""),
                    "current_price": 4801.0,
                }
            ]

        @staticmethod
        def close_position(symbol, position_ticket, lot_size=None, comment=None):
            obs["close_calls"].append(
                {"symbol": symbol, "ticket": int(position_ticket), "lot_size": float(lot_size or 0.0), "comment": str(comment or "")}
            )
            return {"ok": True}

        @staticmethod
        def get_symbol_info(symbol):
            return {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0}

    svc._live_service = FakeLiveService()
    monkeypatch.setattr(svc, "_confirm_signal_force_single_trade_01", lambda: False)
    monkeypatch.setattr(svc, "_confirm_signal_default_lot", lambda: 0.20)

    signal = {
        "symbol": "XAUUSD",
        "direction": "BUY",
        "timeframe": "M5",
        "stop_loss": None,
        "no_stop_loss": True,
        "stage_weights": [40, 25, 15, 10, 10],
        "tps": [
            {"index": 1, "price": 4790.0},
            {"index": 2, "price": 4793.0},
            {"index": 3, "price": 4796.0},
            {"index": 4, "price": 4799.0},
            {"index": 5, "price": 4802.0},
        ],
    }
    out = svc._execute_confirmation_signal_auto(
        chat_id=1,
        signal=signal,
        audit_ctx={
            "source_type": "mt_indicator",
            "source_name": "Hydra Signals Indicator",
            "trigger": "indicator_signal",
            "profile": "hydra",
            "indicator": "Hydra Signals Indicator",
        },
    )
    assert "Confirmation ladder executed" in out
    assert "Stage mode: weighted_indicator" in out
    assert "Stage lots: 0.0800 / 0.0500 / 0.0300 / 0.0200 / 0.0200" in out
    assert obs["open_stop_loss"] is None

    svc._push_confirmation_signal_ladders()
    assert len(obs["close_calls"]) == 1
    assert abs(float(obs["close_calls"][0]["lot_size"]) - 0.08) < 1e-9
    assert str(obs["close_calls"][0]["comment"]) == "tg_confirm_tp1"


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
