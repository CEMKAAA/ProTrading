"""
Atomic File Bridge cTrader Python Listener
Build: 2026-07-08.ctrader-python-production-v1

Production-guard port of the MT5 Atomic file listener. This is designed as an
external/service listener. Broker-specific cTrader/OpenAPI calls are isolated in
BrokerAdapter so the production logic does not need to be rewritten again.
"""
from __future__ import annotations

import argparse
import csv
import dataclasses
import datetime as dt
import hashlib
import json
import math
import os
import tempfile
import time
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

BUILD = "2026-07-08.ctrader-python-production-v1"


@dataclasses.dataclass
class Config:
    executor_enabled: bool = True
    bridge_latest_path: str = ""
    poll_milliseconds: int = 500
    max_signal_age_seconds: int = 900
    ignore_existing_signal_on_init: bool = True
    symbol_map_csv: str = ""
    use_builtin_oil_symbol_map: bool = True
    builtin_oil_symbol_map_csv: str = "UKOILm=XBRUSD,UKOIL=XBRUSD,USOILm=XTIUSD,USOIL=XTIUSD"
    require_mapped_symbol_equals_chart: bool = True
    source_timeframe_filter: str = ""
    default_source_tf_to_chart_period: bool = True
    source_filter: str = ""
    rebase_levels_to_live_entry: bool = False
    rebase_only_when_source_differs: bool = True
    close_reverse: bool = True
    close_reverse_across_source_tf: bool = False
    fail_if_reverse_close_fails: bool = True
    enable_close_only_signals: bool = True
    permanent_reject_guard: bool = True
    label_prefix: str = "AFB_CT_PY"
    use_risk_lot: bool = True
    local_risk_pct: float = 1.0
    use_bridge_risk_pct: bool = True
    use_balance_for_risk: bool = False
    manual_volume_units: float = 1000.0
    max_volume_units: float = 0.0
    use_margin_shrink_guard: bool = True
    max_margin_usage_pct: float = 40.0
    fail_closed_on_risk_error: bool = True
    block_if_min_volume_exceeds_risk: bool = True
    no_money_retry_shrink: bool = True
    max_spread_pips: float = 0.0
    manage_hcbe: bool = True
    half_close_fraction: float = 0.50
    audit_enabled: bool = True
    audit_file_prefix: str = "AtomicFileBridge_cTraderPy_Audit_"
    poll_heartbeat_seconds: int = 300
    chart_symbol: str = ""
    chart_timeframe: str = ""


@dataclasses.dataclass
class BridgeSignal:
    valid: bool = False
    version: str = ""
    written_gmt: dt.datetime = dataclasses.field(default_factory=lambda: dt.datetime.min.replace(tzinfo=dt.timezone.utc))
    source_login: str = ""
    source_symbol: str = ""
    source_tf: str = ""
    event_id: str = ""
    source: str = ""
    direction: int = 0
    signal_time: dt.datetime = dataclasses.field(default_factory=lambda: dt.datetime.min.replace(tzinfo=dt.timezone.utc))
    bridge_entry: float = 0.0
    sl: float = 0.0
    tp: float = 0.0
    half_trigger: float = 0.0
    half_label: str = ""
    source_build: str = ""
    source_bid: float = 0.0
    source_ask: float = 0.0
    risk_pct: float = 0.0


@dataclasses.dataclass
class Position:
    id: str
    symbol: str
    trade_type: str  # BUY / SELL
    volume: float
    entry_price: float
    sl: float
    tp: float
    label: str
    comment: str = ""
    net_profit: float = 0.0


@dataclasses.dataclass
class HalfState:
    position_id: str
    event_id: str
    source_tf: str
    direction: int
    entry: float
    half_trigger: float
    initial_volume: float
    stop_loss: float
    take_profit: float
    done: bool = False


@dataclasses.dataclass
class OrderResult:
    ok: bool
    position: Optional[Position] = None
    error: str = ""


class BrokerAdapter(ABC):
    @property
    @abstractmethod
    def account_id(self) -> str: ...
    @property
    @abstractmethod
    def symbol(self) -> str: ...
    @property
    @abstractmethod
    def timeframe(self) -> str: ...
    @property
    @abstractmethod
    def equity(self) -> float: ...
    @property
    @abstractmethod
    def balance(self) -> float: ...
    @property
    @abstractmethod
    def margin(self) -> float: ...
    @property
    @abstractmethod
    def free_margin(self) -> float: ...
    @property
    @abstractmethod
    def bid(self) -> float: ...
    @property
    @abstractmethod
    def ask(self) -> float: ...
    @property
    @abstractmethod
    def pip_size(self) -> float: ...
    @property
    @abstractmethod
    def spread_pips(self) -> float: ...
    @property
    @abstractmethod
    def volume_min(self) -> float: ...
    @property
    @abstractmethod
    def volume_step(self) -> float: ...

    @abstractmethod
    def normalize_volume_down(self, volume: float) -> float: ...
    @abstractmethod
    def amount_risked(self, volume: float, stop_loss_pips: float) -> float: ...
    @abstractmethod
    def volume_for_fixed_risk(self, risk_money: float, stop_loss_pips: float) -> float: ...
    @abstractmethod
    def estimated_margin(self, trade_type: str, volume: float) -> float: ...
    @abstractmethod
    def positions(self) -> List[Position]: ...
    @abstractmethod
    def execute_market_order(self, trade_type: str, volume: float, label: str, sl_pips: float, tp_pips: float, comment: str) -> OrderResult: ...
    @abstractmethod
    def close_position(self, position: Position, volume: Optional[float] = None) -> OrderResult: ...
    @abstractmethod
    def modify_position(self, position: Position, sl: float, tp: float) -> OrderResult: ...


class DryRunAdapter(BrokerAdapter):
    """Safe local adapter for parser/risk/audit dry-runs. It never trades."""
    def __init__(self, symbol: str = "XAUUSD", timeframe: str = "1"):
        self._symbol = symbol
        self._timeframe = timeframe
        self._positions: List[Position] = []
        self._bid = 2400.00
        self._ask = 2400.20

    @property
    def account_id(self) -> str: return "DRYRUN"
    @property
    def symbol(self) -> str: return self._symbol
    @property
    def timeframe(self) -> str: return self._timeframe
    @property
    def equity(self) -> float: return 10000.0
    @property
    def balance(self) -> float: return 10000.0
    @property
    def margin(self) -> float: return 0.0
    @property
    def free_margin(self) -> float: return 10000.0
    @property
    def bid(self) -> float: return self._bid
    @property
    def ask(self) -> float: return self._ask
    @property
    def pip_size(self) -> float: return 0.01
    @property
    def spread_pips(self) -> float: return (self._ask - self._bid) / self.pip_size
    @property
    def volume_min(self) -> float: return 1.0
    @property
    def volume_step(self) -> float: return 1.0

    def normalize_volume_down(self, volume: float) -> float:
        return max(0.0, math.floor(volume / self.volume_step) * self.volume_step)
    def amount_risked(self, volume: float, stop_loss_pips: float) -> float:
        return volume * stop_loss_pips * 0.01
    def volume_for_fixed_risk(self, risk_money: float, stop_loss_pips: float) -> float:
        return self.normalize_volume_down(risk_money / max(0.000001, stop_loss_pips * 0.01))
    def estimated_margin(self, trade_type: str, volume: float) -> float:
        return volume * 0.1
    def positions(self) -> List[Position]:
        return list(self._positions)
    def execute_market_order(self, trade_type: str, volume: float, label: str, sl_pips: float, tp_pips: float, comment: str) -> OrderResult:
        entry = self.ask if trade_type == "BUY" else self.bid
        sl = entry - sl_pips * self.pip_size if trade_type == "BUY" else entry + sl_pips * self.pip_size
        tp = entry + tp_pips * self.pip_size if trade_type == "BUY" else entry - tp_pips * self.pip_size
        pos = Position(str(int(time.time() * 1000)), self.symbol, trade_type, volume, entry, sl, tp, label, comment)
        self._positions.append(pos)
        return OrderResult(True, pos)
    def close_position(self, position: Position, volume: Optional[float] = None) -> OrderResult:
        if volume is None or volume >= position.volume:
            self._positions = [p for p in self._positions if p.id != position.id]
        else:
            position.volume -= volume
        return OrderResult(True, position)
    def modify_position(self, position: Position, sl: float, tp: float) -> OrderResult:
        position.sl = sl
        position.tp = tp
        return OrderResult(True, position)

class AtomicFileBridgePythonListener:
    def __init__(self, adapter: BrokerAdapter, config: Config):
        self.adapter = adapter
        self.cfg = config
        self.cfg.chart_symbol = self.cfg.chart_symbol or adapter.symbol
        self.cfg.chart_timeframe = self.cfg.chart_timeframe or adapter.timeframe
        self.last_seen_event_id = ""
        self.last_rejected_event_id = ""
        self.last_poll_heartbeat = dt.datetime.min.replace(tzinfo=dt.timezone.utc)
        self.last_read_fail_audit = dt.datetime.min.replace(tzinfo=dt.timezone.utc)
        self.last_action = "boot"
        self.last_detail = ""
        self.last_signal = "none"
        self.half_states: Dict[str, HalfState] = {}
        self.bridge_path = self.resolve_bridge_path()
        self.audit_dir = self.bridge_path.parent
        self.lock_dir = Path(tempfile.gettempdir()) / "AtomicFileBridge_cTraderPy_Locks"
        self.lock_dir.mkdir(parents=True, exist_ok=True)

    def start(self) -> None:
        self.audit_raw("init", f"build={BUILD} bridge={self.bridge_path} symbol={self.adapter.symbol} risk_capital_source={'ctrader_balance' if self.cfg.use_balance_for_risk else 'ctrader_equity'} use_bridge_risk_pct={self.cfg.use_bridge_risk_pct} margin_guard={self.cfg.use_margin_shrink_guard}")
        self.repair_open_position_states("init")
        if self.cfg.ignore_existing_signal_on_init:
            sig, detail = self.try_read_signal()
            if sig and self.signal_identity_matches(sig)[0]:
                self.last_seen_event_id = sig.event_id
                self.audit("init_baseline_existing_signal", sig, "seeded_last_seen=1 no_trade_on_attach " + detail)
            else:
                self.audit_raw("init_baseline_empty", detail)

    def run_forever(self) -> None:
        self.start()
        while True:
            self.poll_bridge("timer")
            self.repair_open_position_states("timer")
            self.manage_half_close()
            time.sleep(max(0.1, self.cfg.poll_milliseconds / 1000.0))

    def poll_bridge(self, caller: str) -> None:
        sig, detail = self.try_read_signal()
        now = utcnow()
        if not sig:
            self.set_action("read_failed", detail)
            init_marker = any(x in detail.lower() for x in ("bridge_init_marker", "source=bridge_initiated", "dir=init"))
            throttle = 60 if init_marker else 10
            if seconds_since(self.last_read_fail_audit, now) >= throttle:
                self.last_read_fail_audit = now
                self.audit_raw("bridge_initiated_seen" if init_marker else "read_failed", f"caller={caller} {detail}")
            return

        if self.cfg.poll_heartbeat_seconds > 0 and seconds_since(self.last_poll_heartbeat, now) >= self.cfg.poll_heartbeat_seconds:
            self.last_poll_heartbeat = now
            self.audit_raw("poll_heartbeat", f"caller={caller} {detail} last_seen={self.last_seen_event_id} last_rejected={self.last_rejected_event_id}")

        identity_ok, _ = self.signal_identity_matches(sig)
        if identity_ok:
            self.repair_open_position_states("poll_identity_match")

        if sig.event_id == self.last_seen_event_id or (self.cfg.permanent_reject_guard and sig.event_id == self.last_rejected_event_id):
            self.set_action("idle_duplicate_latest", short_event(sig.event_id))
            return

        identity_ok, reason = self.signal_identity_matches(sig)
        if not identity_ok:
            if self.cfg.permanent_reject_guard:
                self.last_rejected_event_id = sig.event_id
            self.audit("skip_filter", sig, f"caller={caller} {reason} {detail}")
            return

        self.audit("signal_received", sig, f"caller={caller} mapped_symbol={self.map_symbol(sig.source_symbol)} {detail}")

        age = (utcnow() - sig.written_gmt).total_seconds() if sig.written_gmt.year > 1 else 0
        if self.cfg.max_signal_age_seconds > 0 and age > self.cfg.max_signal_age_seconds:
            if self.cfg.permanent_reject_guard:
                self.last_rejected_event_id = sig.event_id
            self.audit("skip_stale", sig, f"age_sec={age:.0f} max={self.cfg.max_signal_age_seconds}")
            return

        if not self.cfg.executor_enabled:
            self.last_seen_event_id = sig.event_id
            self.audit("skip_executor_off", sig, "executor disabled")
            return

        if self.cfg.enable_close_only_signals and self.is_close_only_signal(sig):
            ok, close_detail = self.close_same_direction_positions(sig)
            if ok:
                self.last_seen_event_id = sig.event_id
            elif self.cfg.permanent_reject_guard:
                self.last_rejected_event_id = sig.event_id
            self.audit("close_only_processed", sig, f"caller={caller} {close_detail}")
            return

        if self.cfg.max_spread_pips > 0 and self.adapter.spread_pips > self.cfg.max_spread_pips:
            if self.cfg.permanent_reject_guard:
                self.last_rejected_event_id = sig.event_id
            self.audit("skip_spread", sig, f"spread_pips={self.adapter.spread_pips:.2f} max={self.cfg.max_spread_pips:.2f}")
            return

        if self.execute_signal(sig):
            self.last_seen_event_id = sig.event_id

    def execute_signal(self, sig: BridgeSignal) -> bool:
        trade_type = "BUY" if sig.direction > 0 else "SELL"
        entry = self.adapter.ask if sig.direction > 0 else self.adapter.bid
        rebase_detail = ""
        if self.should_rebase_levels(sig):
            rebase_detail = self.rebase_levels_to_live_entry(sig, entry)
            if rebase_detail:
                self.audit("levels_rebased", sig, rebase_detail)

        ok, sl_pips, tp_pips, stop_detail = self.validate_stops(sig, entry)
        if not ok:
            if self.cfg.permanent_reject_guard:
                self.last_rejected_event_id = sig.event_id
            self.audit("skip_geometry", sig, stop_detail + " " + self.stop_context(entry, sig.sl, sig.tp))
            return False

        if not self.claim_event(sig.event_id):
            duplicate_reverse_detail = ""
            if self.cfg.close_reverse:
                _, duplicate_reverse_detail = self.close_reverse_positions(sig)
            self.audit("skip_duplicate_global", sig, "lock_exists " + duplicate_reverse_detail)
            return True

        if self.cfg.close_reverse:
            reverse_ok, reverse_detail = self.close_reverse_positions(sig)
            if not reverse_ok:
                self.release_event(sig.event_id)
                if self.cfg.permanent_reject_guard:
                    self.last_rejected_event_id = sig.event_id
                self.audit("skip_reverse_close_failed", sig, reverse_detail)
                if self.cfg.fail_if_reverse_close_fails:
                    return False

        volume, lot_detail = self.resolve_volume(sig, sl_pips)
        if volume <= 0:
            self.release_event(sig.event_id)
            if self.cfg.permanent_reject_guard:
                self.last_rejected_event_id = sig.event_id
            self.audit("skip_lot", sig, lot_detail)
            return False

        label = self.build_label(sig)
        comment = self.build_comment(sig)
        result = self.adapter.execute_market_order(trade_type, volume, label, sl_pips, tp_pips, comment)
        final_volume = volume
        order_prefix = ""
        if not result.ok:
            retry_detail = ""
            retry_volume = 0.0
            original_error = result.error
            if self.cfg.no_money_retry_shrink and self.is_no_money_error(original_error):
                retry_volume, retry_detail = self.shrink_volume_to_free_margin(trade_type, volume)
            if 0 < retry_volume < volume:
                retry = self.adapter.execute_market_order(trade_type, retry_volume, label, sl_pips, tp_pips, comment)
                if retry.ok:
                    result = retry
                    final_volume = retry_volume
                    order_prefix = f"original_error={original_error} original_volume={volume} retry_volume={retry_volume} {retry_detail} "
                    self.audit("order_sent_no_money_retry", sig, order_prefix + f"sl_pips={sl_pips:.2f} tp_pips={tp_pips:.2f} {lot_detail}")
                else:
                    self.release_event(sig.event_id)
                    if self.cfg.permanent_reject_guard and self.is_permanent_order_failure(retry.error):
                        self.last_rejected_event_id = sig.event_id
                    self.audit("order_failed_no_money_retry", sig, f"original_error={original_error} retry_error={retry.error} original_volume={volume} retry_volume={retry_volume} sl_pips={sl_pips:.2f} tp_pips={tp_pips:.2f} {retry_detail} {lot_detail}")
                    return False
            else:
                self.release_event(sig.event_id)
                permanent = self.is_permanent_order_failure(original_error)
                if self.cfg.permanent_reject_guard and permanent:
                    self.last_rejected_event_id = sig.event_id
                self.audit("order_failed", sig, f"error={original_error} permanent_reject={1 if permanent else 0} volume={volume} sl_pips={sl_pips:.2f} tp_pips={tp_pips:.2f} {self.stop_context(entry, sig.sl, sig.tp)} {retry_detail} {lot_detail}")
                return False

        if result.position and self.cfg.manage_hcbe and sig.half_trigger > 0:
            p = result.position
            self.half_states[p.id] = HalfState(p.id, sig.event_id, normalize_tf(sig.source_tf), sig.direction, p.entry_price, sig.half_trigger, p.volume, sig.sl, sig.tp)

        pos = result.position
        self.audit("order_sent", sig, order_prefix + f"position={pos.id if pos else '-'} volume={pos.volume if pos else final_volume} live_entry={entry} fill_entry={pos.entry_price if pos else entry} sl_pips={sl_pips:.2f} tp_pips={tp_pips:.2f} rebase={rebase_detail} {lot_detail}")
        return True

    def resolve_volume(self, sig: BridgeSignal, stop_loss_pips: float) -> Tuple[float, str]:
        if not self.cfg.use_risk_lot:
            manual = self.adapter.normalize_volume_down(self.cfg.manual_volume_units)
            return manual, f"manual_volume={manual}"
        risk_pct = sig.risk_pct if self.cfg.use_bridge_risk_pct and sig.risk_pct > 0 else self.cfg.local_risk_pct
        risk_capital = self.adapter.balance if self.cfg.use_balance_for_risk else self.adapter.equity
        risk_money = risk_capital * max(0.0, risk_pct) / 100.0
        if risk_money <= 0 or stop_loss_pips <= 0:
            return 0.0, f"risk_unavailable risk_money={risk_money:.2f} stop_loss_pips={stop_loss_pips:.2f}"
        try:
            volume = self.adapter.volume_for_fixed_risk(risk_money, stop_loss_pips)
        except Exception as exc:
            return 0.0, f"volume_for_fixed_risk_failed error={exc} risk_money={risk_money:.2f} stop_loss_pips={stop_loss_pips:.2f}"
        if self.cfg.max_volume_units > 0:
            volume = min(volume, self.cfg.max_volume_units)
        min_risk = self.adapter.amount_risked(self.adapter.volume_min, stop_loss_pips)
        if self.cfg.block_if_min_volume_exceeds_risk and volume < self.adapter.volume_min and min_risk > risk_money * 1.001:
            return 0.0, f"min_volume_exceeds_risk risk_money={risk_money:.2f} stop_loss_pips={stop_loss_pips:.2f} raw_volume={volume} min_volume={self.adapter.volume_min} min_volume_risk={min_risk:.2f}"
        volume = self.adapter.normalize_volume_down(volume)
        if volume < self.adapter.volume_min:
            fallback = self.adapter.normalize_volume_down(self.cfg.manual_volume_units)
            return (0.0 if self.cfg.fail_closed_on_risk_error else fallback), f"volume_below_min risk_money={risk_money:.2f} stop_loss_pips={stop_loss_pips:.2f} volume={volume} min={self.adapter.volume_min}"
        estimated_risk = self.adapter.amount_risked(volume, stop_loss_pips)
        if self.cfg.block_if_min_volume_exceeds_risk and estimated_risk > risk_money * 1.001:
            return 0.0, f"normalized_volume_exceeds_risk risk_money={risk_money:.2f} stop_loss_pips={stop_loss_pips:.2f} volume={volume} estimated_risk={estimated_risk:.2f}"
        margin_detail = ""
        if self.cfg.use_margin_shrink_guard and self.cfg.max_margin_usage_pct > 0:
            shrunk, margin_detail = self.shrink_volume_to_margin_limit("BUY" if sig.direction > 0 else "SELL", volume, self.cfg.max_margin_usage_pct)
            if shrunk <= 0:
                return 0.0, margin_detail
            volume = shrunk
            estimated_risk = self.adapter.amount_risked(volume, stop_loss_pips)
        detail = f"risk_lot risk_pct={risk_pct:.3f} pct_source={'bridge' if self.cfg.use_bridge_risk_pct and sig.risk_pct > 0 else 'local'} risk_capital_source={'ctrader_balance' if self.cfg.use_balance_for_risk else 'ctrader_equity'} risk_capital={risk_capital:.2f} risk_money={risk_money:.2f} stop_loss_pips={stop_loss_pips:.2f} volume={volume} estimated_risk={estimated_risk:.2f} {margin_detail}"
        return volume, detail

    def manage_half_close(self) -> None:
        if not self.cfg.manage_hcbe or not self.half_states:
            return
        for pos_id, st in list(self.half_states.items()):
            pos = next((p for p in self.adapter.positions() if p.id == pos_id), None)
            if not pos:
                self.half_states.pop(pos_id, None)
                continue
            if st.done or st.half_trigger <= 0:
                continue
            trigger_px = self.adapter.bid if st.direction > 0 else self.adapter.ask
            reached = self.adapter.bid >= st.half_trigger if st.direction > 0 else self.adapter.ask <= st.half_trigger
            if not reached:
                continue
            desired_close = pos.volume * min(1.0, max(0.0, self.cfg.half_close_fraction))
            close_volume = self.adapter.normalize_volume_down(desired_close)
            if close_volume <= 0 or close_volume >= pos.volume or pos.volume - close_volume < self.adapter.volume_min:
                max_close = self.adapter.normalize_volume_down(pos.volume - self.adapter.volume_min)
                if 0 < max_close < pos.volume:
                    close_volume = max_close
            remaining = self.adapter.normalize_volume_down(pos.volume - close_volume)
            risk_pips = abs(st.entry - st.stop_loss) / self.adapter.pip_size if self.adapter.pip_size > 0 else 0
            hc_pips = abs(st.half_trigger - st.entry) / self.adapter.pip_size if self.adapter.pip_size > 0 else 0
            hc_r = hc_pips / risk_pips if risk_pips > 0 else 0
            expected_full_risk = self.adapter.amount_risked(pos.volume, risk_pips) if risk_pips > 0 else 0
            expected_half_pnl = self.adapter.amount_risked(close_volume, hc_pips) if hc_pips > 0 and close_volume > 0 else 0
            base = f"pos={pos.id} label={pos.label} src_tf={st.source_tf} type={pos.trade_type} entry={st.entry} hc={st.half_trigger} trigger_px={trigger_px} volume={pos.volume} desired_close={desired_close} close_volume={close_volume} remaining_volume={remaining} min_volume={self.adapter.volume_min} fraction={self.cfg.half_close_fraction:.2f} sl={st.stop_loss} tp={st.take_profit} risk_pips={risk_pips:.2f} hc_pips={hc_pips:.2f} hc_r={hc_r:.3f} expected_full_risk={expected_full_risk:.2f} expected_half_pnl_at_hc={expected_half_pnl:.2f}"
            if close_volume <= 0 or close_volume >= pos.volume or remaining < self.adapter.volume_min:
                self.audit_raw("halfbe_blocked_volume", base + " reason=partial_close_impossible_for_broker_volume")
                continue
            close = self.adapter.close_position(pos, close_volume)
            if not close.ok:
                self.audit_raw("halfbe_partial_close_failed", base + f" err={close.error}")
                continue
            remaining_pos = next((p for p in self.adapter.positions() if p.id == pos.id), None)
            if not remaining_pos:
                st.done = True
                self.audit_raw("halfbe_partial_close_success_position_closed", base)
                continue
            mod = self.adapter.modify_position(remaining_pos, remaining_pos.entry_price, remaining_pos.tp)
            self.audit_raw("halfbe_done" if mod.ok else "halfbe_sl_to_be_failed_after_partial", base + f" be_sl={remaining_pos.entry_price} remaining_after={remaining_pos.volume} modify_err={mod.error}")
            st.done = True

    def close_reverse_positions(self, sig: BridgeSignal) -> Tuple[bool, str]:
        reverse = "SELL" if sig.direction > 0 else "BUY"
        return self.close_scoped_positions(sig, reverse, "reverse_close")

    def close_same_direction_positions(self, sig: BridgeSignal) -> Tuple[bool, str]:
        same = "BUY" if sig.direction > 0 else "SELL"
        return self.close_scoped_positions(sig, same, "close_only")

    def close_scoped_positions(self, sig: BridgeSignal, trade_type: str, event_prefix: str) -> Tuple[bool, str]:
        found = closed = failed = 0
        parts: List[str] = []
        for p in self.scoped_positions(sig):
            if p.trade_type != trade_type:
                continue
            found += 1
            pnl = p.net_profit
            res = self.adapter.close_position(p)
            if not res.ok:
                failed += 1
                msg = f"pos={p.id} dir={p.trade_type} volume={p.volume} pnl={pnl:.2f} err={res.error}"
                parts.append("close_failed " + msg)
                self.audit(event_prefix + "_failed", sig, msg)
            else:
                closed += 1
                msg = f"pos={p.id} dir={p.trade_type} volume={p.volume} pnl={pnl:.2f}"
                parts.append("closed " + msg)
                self.audit(event_prefix + "_sent", sig, msg)
        if found == 0:
            self.audit(event_prefix + "_none", sig, "no_position_in_scope")
        scope = "all_source_tf" if self.cfg.close_reverse_across_source_tf else "same_source_tf"
        return failed == 0, f"{event_prefix}_found={found} closed={closed} failed={failed} scope={scope} " + " ".join(parts)

    def scoped_positions(self, sig: BridgeSignal) -> Iterable[Position]:
        sig_tf = normalize_tf(sig.source_tf)
        for p in self.adapter.positions():
            if not same_text(p.symbol, self.adapter.symbol):
                continue
            if not p.label.startswith(self.cfg.label_prefix):
                continue
            if not self.cfg.close_reverse_across_source_tf:
                pos_tf = self.position_source_tf(p)
                if sig_tf and pos_tf and not same_text(sig_tf, pos_tf):
                    continue
            yield p

    def repair_open_position_states(self, reason: str) -> None:
        if not self.cfg.manage_hcbe:
            return
        for p in self.adapter.positions():
            if p.symbol != self.adapter.symbol or not p.label.startswith(self.cfg.label_prefix) or p.id in self.half_states:
                continue
            half = parse_comment_float(p.comment, "half")
            if half <= 0:
                continue
            self.half_states[p.id] = HalfState(p.id, parse_comment_str(p.comment, "event"), self.position_source_tf(p), 1 if p.trade_type == "BUY" else -1, p.entry_price, half, p.volume, parse_comment_float(p.comment, "sl"), parse_comment_float(p.comment, "tp"))
            self.audit_raw("position_state_repaired", f"reason={reason} pos={p.id} label={p.label} source_tf={self.position_source_tf(p)} entry={p.entry_price} half={half} sl={parse_comment_float(p.comment, 'sl')} tp={parse_comment_float(p.comment, 'tp')}")

    def shrink_volume_to_margin_limit(self, trade_type: str, requested: float, max_margin_pct: float) -> Tuple[float, str]:
        if max_margin_pct <= 0:
            return requested, ""
        min_v = self.adapter.volume_min
        min_pct = self.projected_margin_pct(trade_type, min_v)
        if min_pct > max_margin_pct:
            return 0.0, f"min_volume_margin_exceeds_limit min_volume={min_v} projected_margin_pct={min_pct:.2f} max_margin_pct={max_margin_pct:.2f}"
        best = self.adapter.normalize_volume_down(requested)
        if self.projected_margin_pct(trade_type, best) <= max_margin_pct:
            return best, f"margin_no_shrink volume={best} projected_margin_pct={self.projected_margin_pct(trade_type, best):.2f} max_margin_pct={max_margin_pct:.2f}"
        while best >= min_v and self.projected_margin_pct(trade_type, best) > max_margin_pct:
            best = self.adapter.normalize_volume_down(best - self.adapter.volume_step)
        if best < min_v:
            return 0.0, f"margin_shrink_no_valid_volume requested_volume={requested} max_margin_pct={max_margin_pct:.2f}"
        return best, f"margin_shrink requested_volume={requested} shrunk_volume={best} projected_margin_pct={self.projected_margin_pct(trade_type, best):.2f} max_margin_pct={max_margin_pct:.2f}"

    def shrink_volume_to_free_margin(self, trade_type: str, requested: float) -> Tuple[float, str]:
        best = self.adapter.normalize_volume_down(requested)
        while best >= self.adapter.volume_min:
            margin = self.adapter.estimated_margin(trade_type, best)
            if margin <= self.adapter.free_margin * 0.98:
                return best, f"free_margin_retry requested_volume={requested} shrunk_volume={best} required_margin={margin:.2f} free_margin={self.adapter.free_margin:.2f}"
            best = self.adapter.normalize_volume_down(best - self.adapter.volume_step)
        return 0.0, f"free_margin_retry_no_valid_volume requested_volume={requested} free_margin={self.adapter.free_margin:.2f}"

    def projected_margin_pct(self, trade_type: str, volume: float) -> float:
        return float("inf") if self.adapter.equity <= 0 else (self.adapter.margin + self.adapter.estimated_margin(trade_type, volume)) * 100.0 / self.adapter.equity

    def validate_stops(self, sig: BridgeSignal, entry: float) -> Tuple[bool, float, float, str]:
        if sig.direction > 0:
            sl_pips = (entry - sig.sl) / self.adapter.pip_size
            tp_pips = (sig.tp - entry) / self.adapter.pip_size
        else:
            sl_pips = (sig.sl - entry) / self.adapter.pip_size
            tp_pips = (entry - sig.tp) / self.adapter.pip_size
        if sl_pips <= 0 or tp_pips <= 0:
            return False, sl_pips, tp_pips, f"invalid_sl_tp entry={entry} sl={sig.sl} tp={sig.tp} sl_pips={sl_pips:.2f} tp_pips={tp_pips:.2f}"
        return True, sl_pips, tp_pips, "ok"

    def try_read_signal(self) -> Tuple[Optional[BridgeSignal], str]:
        if not self.bridge_path.exists():
            return None, f"file_not_found {self.bridge_path}"
        try:
            text = self.bridge_path.read_text(encoding="utf-8-sig")
        except Exception as exc:
            return None, f"file_read_failed {exc}"
        fields = parse_csv_flat(text)
        if len(fields) < 17:
            return None, f"not_enough_fields count={len(fields)}"
        offset = 0
        if fields[0] == "version":
            offset = 17
            if len(fields) > 17 and fields[17] == "risk_pct":
                offset = 18
        if len(fields) < offset + 17:
            return None, f"not_enough_data_fields count={len(fields)} offset={offset}"
        sig = BridgeSignal()
        sig.version = fields[offset + 0]
        sig.written_gmt = parse_date(fields[offset + 1])
        sig.source_login = fields[offset + 2]
        sig.source_symbol = fields[offset + 3]
        sig.source_tf = fields[offset + 4]
        sig.event_id = fields[offset + 5]
        sig.source = fields[offset + 6]
        raw_dir = fields[offset + 7]
        sig.direction = 1 if raw_dir == "BUY" else -1 if raw_dir == "SELL" else 0
        sig.signal_time = parse_date(fields[offset + 8])
        sig.bridge_entry = to_float(fields[offset + 9])
        sig.sl = to_float(fields[offset + 10])
        sig.tp = to_float(fields[offset + 11])
        sig.half_trigger = to_float(fields[offset + 12])
        sig.half_label = fields[offset + 13]
        sig.source_build = fields[offset + 14]
        sig.source_bid = to_float(fields[offset + 15])
        sig.source_ask = to_float(fields[offset + 16])
        sig.risk_pct = to_float(fields[offset + 17]) if len(fields) > offset + 17 else 0.0
        sig.valid = bool(sig.event_id and sig.direction)
        detail = f"read_ok fields={len(fields)} offset={offset} event={sig.event_id} source_symbol={sig.source_symbol} source_tf={sig.source_tf} dir={raw_dir} risk_pct={sig.risk_pct:.3f}"
        if not sig.valid:
            detail = ("bridge_init_marker " if same_text(sig.source, "bridge_initiated") or same_text(raw_dir, "INIT") else "invalid_parsed_signal ") + detail
            return None, detail
        return sig, detail

    def signal_identity_matches(self, sig: BridgeSignal) -> Tuple[bool, str]:
        mapped = self.map_symbol(sig.source_symbol)
        if self.cfg.require_mapped_symbol_equals_chart and not same_text(mapped, self.adapter.symbol):
            return False, f"symbol_filter source={sig.source_symbol} mapped={mapped} chart={self.adapter.symbol}"
        tf_filter = self.cfg.source_timeframe_filter.strip()
        if not tf_filter and self.cfg.default_source_tf_to_chart_period:
            tf_filter = self.adapter.timeframe
        if tf_filter and normalize_tf(tf_filter) != normalize_tf(sig.source_tf):
            return False, f"tf_filter source={sig.source_tf} expected={tf_filter}"
        if self.cfg.source_filter and self.cfg.source_filter.lower() not in sig.source.lower():
            return False, f"source_filter source={sig.source} expected={self.cfg.source_filter}"
        return True, ""

    def map_symbol(self, source: str) -> str:
        mapped = map_symbol_from_csv(source, self.cfg.symbol_map_csv)
        if mapped:
            return mapped
        if self.cfg.use_builtin_oil_symbol_map:
            mapped = map_symbol_from_csv(source, self.cfg.builtin_oil_symbol_map_csv)
            if mapped:
                return mapped
        if source.lower().endswith("m") and same_text(source[:-1], self.adapter.symbol):
            return self.adapter.symbol
        return source

    def should_rebase_levels(self, sig: BridgeSignal) -> bool:
        if not self.cfg.rebase_levels_to_live_entry or sig.bridge_entry <= 0 or sig.sl <= 0 or sig.tp <= 0:
            return False
        if not same_text(self.map_symbol(sig.source_symbol), self.adapter.symbol):
            return False
        if self.cfg.rebase_only_when_source_differs and same_text(sig.source_symbol, self.adapter.symbol):
            return False
        return True

    def rebase_levels_to_live_entry(self, sig: BridgeSignal, live_entry: float) -> str:
        old_sl, old_tp, old_half, src = sig.sl, sig.tp, sig.half_trigger, sig.bridge_entry
        if sig.direction > 0:
            risk, reward = src - old_sl, old_tp - src
            if risk > 0: sig.sl = live_entry - risk
            if reward > 0: sig.tp = live_entry + reward
            if old_half > 0 and old_half - src > 0: sig.half_trigger = live_entry + (old_half - src)
        else:
            risk, reward = old_sl - src, src - old_tp
            if risk > 0: sig.sl = live_entry + risk
            if reward > 0: sig.tp = live_entry - reward
            if old_half > 0 and src - old_half > 0: sig.half_trigger = live_entry - (src - old_half)
        return f"source_entry={src} live_entry={live_entry} old_sl={old_sl} old_tp={old_tp} old_half={old_half} new_sl={sig.sl} new_tp={sig.tp} new_half={sig.half_trigger} mapped={self.map_symbol(sig.source_symbol)}"

    def is_close_only_signal(self, sig: BridgeSignal) -> bool:
        return "closeonly" in sig.source.lower() or "invalidate_close" in sig.event_id.lower()

    def is_no_money_error(self, error: str) -> bool:
        return any(x in normalize_error(error) for x in ("nomoney", "notenoughmoney", "insufficient", "margin"))

    def is_permanent_order_failure(self, error: str) -> bool:
        return any(x in normalize_error(error) for x in ("invalid", "badvolume", "stoploss", "takeprofit"))

    def build_label(self, sig: BridgeSignal) -> str:
        return f"{self.cfg.label_prefix}|T{normalize_tf(sig.source_tf)}|{hash32(sig.event_id):08X}"

    def build_comment(self, sig: BridgeSignal) -> str:
        return f"event={short_event(sig.event_id)};src={sig.source};tf={normalize_tf(sig.source_tf)};half={sig.half_trigger};sl={sig.sl};tp={sig.tp}"

    def position_source_tf(self, p: Position) -> str:
        for part in p.label.split("|"):
            if len(part) > 1 and part[0].upper() == "T":
                return normalize_tf(part[1:])
        return normalize_tf(parse_comment_str(p.comment, "tf"))

    def stop_context(self, entry: float, sl: float, tp: float) -> str:
        return f"bid={self.adapter.bid} ask={self.adapter.ask} entry={entry} sl_dist={abs(entry - sl):.5f} tp_dist={abs(entry - tp):.5f} spread_pips={self.adapter.spread_pips:.2f}"

    def claim_event(self, event_id: str) -> bool:
        path = self.lock_dir / f"{safe_name(self.adapter.account_id)}_{safe_name(self.adapter.symbol)}_{hash32(event_id):08X}.lock"
        try:
            fd = os.open(str(path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(f"{utcnow().isoformat()} {event_id}\n")
            return True
        except FileExistsError:
            return False

    def release_event(self, event_id: str) -> None:
        path = self.lock_dir / f"{safe_name(self.adapter.account_id)}_{safe_name(self.adapter.symbol)}_{hash32(event_id):08X}.lock"
        try:
            path.unlink(missing_ok=True)
        except Exception:
            pass

    def resolve_bridge_path(self) -> Path:
        if self.cfg.bridge_latest_path.strip():
            return Path(self.cfg.bridge_latest_path.strip())
        appdata = os.environ.get("APPDATA", str(Path.home() / "AppData" / "Roaming"))
        return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files" / "AtomicFileBridge_Latest.csv"

    def audit(self, event: str, sig: BridgeSignal, detail: str) -> None:
        self.last_action = event
        self.last_detail = detail
        self.last_signal = f"{sig.source_symbol} {sig.source_tf} {'BUY' if sig.direction > 0 else 'SELL'} {short_event(sig.event_id)}"
        if self.cfg.audit_enabled:
            self.write_audit(event, sig.source_symbol, sig.source_tf, sig.event_id, sig.source, "BUY" if sig.direction > 0 else "SELL", sig.bridge_entry, sig.sl, sig.tp, sig.half_trigger, detail)

    def audit_raw(self, event: str, detail: str) -> None:
        self.set_action(event, detail)
        if self.cfg.audit_enabled:
            self.write_audit(event, "", "", "", "", "-", 0, 0, 0, 0, detail)

    def write_audit(self, event: str, source_symbol: str, source_tf: str, event_id: str, source: str, direction: str, entry: float, sl: float, tp: float, half: float, detail: str) -> None:
        self.audit_dir.mkdir(parents=True, exist_ok=True)
        path = self.audit_dir / f"{self.cfg.audit_file_prefix}{utcnow().strftime('%Y%m%d')}.csv"
        header = not path.exists()
        with path.open("a", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            if header:
                w.writerow(["time_gmt", "build", "event", "account", "chart_symbol", "source_symbol", "source_tf", "event_id", "source", "dir", "entry", "sl", "tp", "half", "detail"])
            w.writerow([utcnow().strftime("%Y-%m-%d %H:%M:%S"), BUILD, event, self.adapter.account_id, self.adapter.symbol, source_symbol, source_tf, event_id, source, direction, entry, sl, tp, half, detail])

    def set_action(self, action: str, detail: str) -> None:
        self.last_action = action
        self.last_detail = detail


def load_config(path: str) -> Config:
    cfg = Config()
    if not path:
        return cfg
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    for k, v in data.items():
        if hasattr(cfg, k):
            setattr(cfg, k, v)
    return cfg


def parse_csv_flat(text: str) -> List[str]:
    rows = list(csv.reader(text.splitlines()))
    return [cell.strip() for row in rows for cell in row]


def parse_date(s: str) -> dt.datetime:
    if not s:
        return dt.datetime.min.replace(tzinfo=dt.timezone.utc)
    clean = s.strip()
    for fmt in ("%Y.%m.%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M:%S.%fZ"):
        try:
            return dt.datetime.strptime(clean, fmt).replace(tzinfo=dt.timezone.utc)
        except ValueError:
            pass
    try:
        return dt.datetime.fromisoformat(clean.replace("Z", "+00:00")).astimezone(dt.timezone.utc)
    except ValueError:
        return dt.datetime.min.replace(tzinfo=dt.timezone.utc)


def to_float(s: str) -> float:
    try:
        return float(str(s).strip())
    except Exception:
        return 0.0


def map_symbol_from_csv(source: str, csv_text: str) -> str:
    for part in csv_text.replace(";", ",").split(","):
        if "=" not in part:
            continue
        lhs, rhs = part.split("=", 1)
        if same_text(lhs.strip(), source):
            return rhs.strip()
    return ""


def same_text(a: str, b: str) -> bool:
    return (a or "").strip().lower() == (b or "").strip().lower()


def normalize_tf(tf: str) -> str:
    s = (tf or "").strip().upper().replace("PERIOD_", "").replace("TIMEFRAME_", "")
    mapping = {"M1": "1", "M5": "5", "M15": "15", "M30": "30", "H1": "60", "H4": "240", "D1": "1440", "W1": "10080", "MN1": "43200"}
    if s in mapping:
        return mapping[s]
    if s.startswith("M") and s[1:].isdigit():
        return s[1:]
    return s


def parse_comment_str(comment: str, key: str) -> str:
    for part in (comment or "").split(";"):
        if "=" not in part:
            continue
        lhs, rhs = part.split("=", 1)
        if same_text(lhs, key):
            return rhs.strip()
    return ""


def parse_comment_float(comment: str, key: str) -> float:
    return to_float(parse_comment_str(comment, key))


def normalize_error(error: str) -> str:
    return (error or "").lower().replace("_", "").replace(" ", "")


def hash32(s: str) -> int:
    digest = hashlib.blake2s((s or "").encode("utf-8"), digest_size=4).digest()
    return int.from_bytes(digest, "big", signed=False)


def short_event(s: str) -> str:
    if not s:
        return ""
    return s if len(s) <= 42 else s[:24] + "..." + s[-14:]


def safe_name(s: str) -> str:
    return "".join(ch if ch.isalnum() else "_" for ch in (s or "_"))


def utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def seconds_since(old: dt.datetime, now: Optional[dt.datetime] = None) -> float:
    return ((now or utcnow()) - old).total_seconds()


def main() -> None:
    parser = argparse.ArgumentParser(description="Atomic File Bridge cTrader Python Listener")
    parser.add_argument("--config", default="", help="JSON config path")
    parser.add_argument("--dry-run", action="store_true", help="Use DryRunAdapter. Real trading needs a BrokerAdapter implementation.")
    parser.add_argument("--symbol", default="XAUUSD", help="Dry-run symbol")
    parser.add_argument("--tf", default="1", help="Dry-run timeframe")
    args = parser.parse_args()
    cfg = load_config(args.config)
    adapter = DryRunAdapter(args.symbol, args.tf)
    listener = AtomicFileBridgePythonListener(adapter, cfg)
    listener.run_forever()


if __name__ == "__main__":
    main()
