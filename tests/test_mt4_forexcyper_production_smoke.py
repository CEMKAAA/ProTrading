from datetime import datetime, timezone

from dashboard.backend.services.mt4_log_automation_service import MT4LogAutomationService


def _mk_service_with_callback():
    calls = []

    def _cb(**kwargs):
        calls.append(dict(kwargs or {}))

    return MT4LogAutomationService(on_indicator_signal=_cb), calls


def test_forexcyper_mt5_alert_parsing_buy_sell_and_symbol_tf():
    svc = MT4LogAutomationService()
    buy_line = (
        "MH\t0\t12:10:01.111\tForexCyperSystem (XAUUSD,M5)\t"
        "Alert: 5M XAUUSD Just Made a BUY Arrow!"
    )
    sell_line = (
        "MH\t0\t12:10:02.111\tForexCyperSystem (BTCUSD,M15)\t"
        "Alert: 15M BTCUSD Just Made a SELL Arrow!"
    )

    buy = svc._parse_line(line=buy_line, source_file="20260408.log", file_date="20260408")
    sell = svc._parse_line(line=sell_line, source_file="20260408.log", file_date="20260408")

    assert isinstance(buy, dict)
    assert isinstance(sell, dict)
    assert str(buy.get("signal_profile")) == "forexcyper"
    assert str(sell.get("signal_profile")) == "forexcyper"
    assert str(buy.get("signal_hint")) == "BUY"
    assert str(sell.get("signal_hint")) == "SELL"
    assert str(buy.get("symbol")) == "XAUUSD"
    assert str(sell.get("symbol")) == "BTCUSD"
    assert str(buy.get("timeframe")) == "M5"
    assert str(sell.get("timeframe")) == "M15"


def test_forexcyper_license_failure_does_not_create_signal_hint():
    svc = MT4LogAutomationService()
    line = (
        "MH\t0\t12:10:01.111\tForexCyperSystem (XAUUSD,M5)\t"
        "Alert: License key check failed contact admin@xyz.com"
    )
    ev = svc._parse_line(line=line, source_file="20260408.log", file_date="20260408")
    assert isinstance(ev, dict)
    assert str(ev.get("signal_profile")) == "forexcyper"
    assert str(ev.get("signal_hint")) == ""


def test_instance_explicit_enable_disable_isolation_same_indicator():
    svc, calls = _mk_service_with_callback()
    ind = "ForexCyperSystem"
    ik = "forexcypersystem"
    svc._indicator_stats[ik] = {
        "indicator": ind,
        "key": ik,
        "automation_enabled": False,
        "lot_size": 0.05,
    }
    on_key = f"{ik}|XAUUSD|M5"
    off_key = f"{ik}|XAUUSD|M15"
    svc._instance_stats[on_key] = {
        "instance_key": on_key,
        "indicator": ind,
        "indicator_key": ik,
        "symbol": "XAUUSD",
        "timeframe": "M5",
        "automation_mode": "explicit",
        "automation_enabled": True,
        "lot_size": 0.08,
    }
    svc._instance_stats[off_key] = {
        "instance_key": off_key,
        "indicator": ind,
        "indicator_key": ik,
        "symbol": "XAUUSD",
        "timeframe": "M15",
        "automation_mode": "explicit",
        "automation_enabled": False,
        "lot_size": 0.03,
    }

    ev_on = {
        "indicator": ind,
        "signal_profile": "forexcyper",
        "signal_hint": "BUY",
        "symbol": "XAUUSD",
        "timeframe": "M5",
        "message": "BUY arrow",
        "event_ts": datetime.now(timezone.utc).isoformat(),
    }
    ev_off = dict(ev_on)
    ev_off["timeframe"] = "M15"
    ev_off["message"] = "SELL arrow"
    ev_off["signal_hint"] = "SELL"

    svc._maybe_forward_signal(ev_on, from_backfill=False)
    svc._maybe_forward_signal(ev_off, from_backfill=False)

    assert len(calls) == 1
    assert str(calls[0].get("timeframe")) == "M5"


def test_instance_lot_override_propagates_to_callback_payload():
    svc, calls = _mk_service_with_callback()
    ind = "ForexCyperSystem"
    ik = "forexcypersystem"
    key = f"{ik}|BTCUSD|M1"
    svc._indicator_stats[ik] = {
        "indicator": ind,
        "key": ik,
        "automation_enabled": False,
        "lot_size": 0.05,
    }
    svc._instance_stats[key] = {
        "instance_key": key,
        "indicator": ind,
        "indicator_key": ik,
        "symbol": "BTCUSD",
        "timeframe": "M1",
        "automation_mode": "explicit",
        "automation_enabled": True,
        "lot_size": 0.11,
    }
    ev = {
        "indicator": ind,
        "signal_profile": "forexcyper",
        "signal_hint": "SELL",
        "symbol": "BTCUSD",
        "timeframe": "M1",
        "message": "SELL arrow",
        "event_ts": datetime.now(timezone.utc).isoformat(),
    }
    svc._maybe_forward_signal(ev, from_backfill=False)
    assert len(calls) == 1
    assert abs(float(calls[0].get("lot_override") or 0.0) - 0.11) < 1e-9


def test_dedupe_burst_500_same_message_forwards_once():
    svc, calls = _mk_service_with_callback()
    ind = "ForexCyperSystem"
    ik = "forexcypersystem"
    key = f"{ik}|XAUUSD|M5"
    svc._indicator_stats[ik] = {
        "indicator": ind,
        "key": ik,
        "automation_enabled": False,
        "lot_size": 0.05,
    }
    svc._instance_stats[key] = {
        "instance_key": key,
        "indicator": ind,
        "indicator_key": ik,
        "symbol": "XAUUSD",
        "timeframe": "M5",
        "automation_mode": "explicit",
        "automation_enabled": True,
        "lot_size": 0.05,
    }
    ev = {
        "indicator": ind,
        "signal_profile": "forexcyper",
        "signal_hint": "BUY",
        "symbol": "XAUUSD",
        "timeframe": "M5",
        "message": "same-buy-arrow",
        "event_ts": datetime.now(timezone.utc).isoformat(),
    }
    for _ in range(500):
        svc._maybe_forward_signal(dict(ev), from_backfill=False)
    state = svc.get_state(limit=50)
    assert len(calls) == 1
    assert int(state.get("forward_skip_duplicate") or 0) >= 499


def test_multi_instance_stress_10000_only_explicit_enabled_instances_forward():
    svc, calls = _mk_service_with_callback()
    ind = "ForexCyperSystem"
    ik = "forexcypersystem"
    svc._indicator_stats[ik] = {
        "indicator": ind,
        "key": ik,
        "automation_enabled": False,
        "lot_size": 0.05,
    }
    enabled = [("XAUUSD", "M5", 0.05), ("XAUUSD", "M15", 0.06), ("BTCUSD", "M1", 0.07)]
    enabled_set = {(sym, tf) for sym, tf, _lot in enabled}
    for sym, tf, lot in enabled:
        key = f"{ik}|{sym}|{tf}"
        svc._instance_stats[key] = {
            "instance_key": key,
            "indicator": ind,
            "indicator_key": ik,
            "symbol": sym,
            "timeframe": tf,
            "automation_mode": "explicit",
            "automation_enabled": True,
            "lot_size": lot,
        }

    syms = ["XAUUSD", "BTCUSD", "USDJPY", "EURUSD"]
    tfs = ["M1", "M5", "M15", "M30", "H1"]
    for i in range(10000):
        sym = syms[i % len(syms)]
        tf = tfs[i % len(tfs)]
        hint = "BUY" if i % 2 == 0 else "SELL"
        ev = {
            "indicator": ind,
            "signal_profile": "forexcyper",
            "signal_hint": hint,
            "symbol": sym,
            "timeframe": tf,
            "message": f"{sym}-{tf}-{hint}-{i}",
            "event_ts": datetime.now(timezone.utc).isoformat(),
        }
        svc._maybe_forward_signal(ev, from_backfill=False)

    assert len(calls) > 0
    assert all((str(c.get("symbol")), str(c.get("timeframe"))) in enabled_set for c in calls)
