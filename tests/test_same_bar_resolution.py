"""
Tests for OHLC path reconstruction in same-bar SL/TP resolution.

Tests _resolve_same_bar_sl_tp() which replaces the old distance-from-open
heuristic with deterministic path walking:
- Bullish bar (close >= open): O -> L -> H -> C
- Bearish bar (close < open):  O -> H -> L -> C

Covers all 8 combinations:
  2 directions (LONG/SHORT) x 2 bar types (bullish/bearish) x 2 outcomes (SL-first/TP-first)
Plus edge cases: doji bar, levels at exact extremes.
"""

import pytest
from types import SimpleNamespace

from dashboard.backend.core.backtest_engine import BacktestEngine, BacktestConfig


def make_position(stop_loss: float, take_profit: float) -> SimpleNamespace:
    """Create a minimal position mock with SL and TP."""
    return SimpleNamespace(stop_loss=stop_loss, take_profit=take_profit)


def make_bar(open_: float, high: float, low: float, close: float) -> dict:
    """Create a bar dict matching what the engine expects."""
    return {"open": open_, "high": high, "low": low, "close": close}


@pytest.fixture
def engine():
    """Create a minimal BacktestEngine instance for calling _resolve_same_bar_sl_tp."""
    config = BacktestConfig(
        symbol="XAUUSD",
        timeframe="M5",
        start_date="2024-01-01",
        end_date="2024-01-31",
        initial_balance=10000.0,
    )
    return BacktestEngine(config)


class TestLongBullishBar:
    """LONG position + Bullish bar (C >= O): path O -> L -> H -> C"""

    def test_sl_hit_first(self, engine):
        """Bullish bar visits Low before High. If SL is at Low, SL fires first."""
        # LONG entry at 2050, SL at 2040, TP at 2060
        # Bar: O=2050, H=2065, L=2035, C=2060 (bullish)
        # Path: O(2050) -> L(2035) -> H(2065) -> C(2060)
        # L=2035 <= SL=2040 → SL fires at first extreme
        bar = make_bar(2050, 2065, 2035, 2060)
        pos = make_position(stop_loss=2040, take_profit=2060)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=True)
        assert reason == "Stop Loss"
        assert price == 2040

    def test_tp_hit_first(self, engine):
        """Bullish bar: Low doesn't hit SL, High hits TP → TP fires."""
        # LONG entry at 2050, SL at 2030, TP at 2060
        # Bar: O=2050, H=2065, L=2045, C=2060 (bullish)
        # Path: O(2050) -> L(2045) -> H(2065) -> C(2060)
        # L=2045 > SL=2030 → skip; H=2065 >= TP=2060 → TP fires
        bar = make_bar(2050, 2065, 2045, 2060)
        pos = make_position(stop_loss=2030, take_profit=2060)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=True)
        assert reason == "Take Profit"
        assert price == 2060


class TestLongBearishBar:
    """LONG position + Bearish bar (C < O): path O -> H -> L -> C"""

    def test_tp_hit_first(self, engine):
        """Bearish bar visits High before Low. If TP is at High, TP fires first."""
        # LONG entry at 2050, SL at 2030, TP at 2060
        # Bar: O=2055, H=2065, L=2025, C=2040 (bearish)
        # Path: O(2055) -> H(2065) -> L(2025) -> C(2040)
        # H=2065 >= TP=2060 → TP fires at first extreme
        bar = make_bar(2055, 2065, 2025, 2040)
        pos = make_position(stop_loss=2030, take_profit=2060)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=True)
        assert reason == "Take Profit"
        assert price == 2060

    def test_sl_hit_first(self, engine):
        """Bearish bar: High doesn't hit TP, Low hits SL → SL fires."""
        # LONG entry at 2050, SL at 2030, TP at 2070
        # Bar: O=2055, H=2065, L=2025, C=2040 (bearish)
        # Path: O(2055) -> H(2065) -> L(2025) -> C(2040)
        # H=2065 < TP=2070 → skip; L=2025 <= SL=2030 → SL fires
        bar = make_bar(2055, 2065, 2025, 2040)
        pos = make_position(stop_loss=2030, take_profit=2070)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=True)
        assert reason == "Stop Loss"
        assert price == 2030


class TestShortBullishBar:
    """SHORT position + Bullish bar (C >= O): path O -> L -> H -> C"""

    def test_tp_hit_first(self, engine):
        """Bullish bar visits Low before High. For SHORT, TP is below → Low hits TP first."""
        # SHORT entry at 2050, SL at 2060, TP at 2040
        # Bar: O=2050, H=2065, L=2035, C=2060 (bullish)
        # Path: O(2050) -> L(2035) -> H(2065) -> C(2060)
        # L=2035 <= TP=2040 → TP fires at first extreme
        bar = make_bar(2050, 2065, 2035, 2060)
        pos = make_position(stop_loss=2060, take_profit=2040)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=False)
        assert reason == "Take Profit"
        assert price == 2040

    def test_sl_hit_first(self, engine):
        """Bullish bar: Low doesn't hit TP, High hits SL → SL fires."""
        # SHORT entry at 2050, SL at 2060, TP at 2030
        # Bar: O=2050, H=2065, L=2045, C=2060 (bullish)
        # Path: O(2050) -> L(2045) -> H(2065) -> C(2060)
        # L=2045 > TP=2030 → skip; H=2065 >= SL=2060 → SL fires
        bar = make_bar(2050, 2065, 2045, 2060)
        pos = make_position(stop_loss=2060, take_profit=2030)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=False)
        assert reason == "Stop Loss"
        assert price == 2060


class TestShortBearishBar:
    """SHORT position + Bearish bar (C < O): path O -> H -> L -> C"""

    def test_sl_hit_first(self, engine):
        """Bearish bar visits High before Low. For SHORT, SL is above → High hits SL first."""
        # SHORT entry at 2050, SL at 2060, TP at 2040
        # Bar: O=2055, H=2065, L=2035, C=2040 (bearish)
        # Path: O(2055) -> H(2065) -> L(2035) -> C(2040)
        # H=2065 >= SL=2060 → SL fires at first extreme
        bar = make_bar(2055, 2065, 2035, 2040)
        pos = make_position(stop_loss=2060, take_profit=2040)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=False)
        assert reason == "Stop Loss"
        assert price == 2060

    def test_tp_hit_first(self, engine):
        """Bearish bar: High doesn't hit SL, Low hits TP → TP fires."""
        # SHORT entry at 2050, SL at 2070, TP at 2030
        # Bar: O=2055, H=2065, L=2025, C=2040 (bearish)
        # Path: O(2055) -> H(2065) -> L(2025) -> C(2040)
        # H=2065 < SL=2070 → skip; L=2025 <= TP=2030 → TP fires
        bar = make_bar(2055, 2065, 2025, 2040)
        pos = make_position(stop_loss=2070, take_profit=2030)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=False)
        assert reason == "Take Profit"
        assert price == 2030


class TestEdgeCases:
    """Edge cases: doji, exact extremes."""

    def test_doji_treated_as_bullish(self, engine):
        """Doji (close == open) should use bullish path: O -> L -> H -> C."""
        # LONG, doji bar, SL at Low, TP at High
        bar = make_bar(2050, 2060, 2040, 2050)  # open == close (doji)
        pos = make_position(stop_loss=2040, take_profit=2060)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=True)
        # Doji path: O(2050) -> L(2040) -> H(2060) -> C(2050)
        # L=2040 <= SL=2040 → SL fires first
        assert reason == "Stop Loss"
        assert price == 2040

    def test_sl_at_exact_bar_extreme(self, engine):
        """SL exactly at bar low should be considered hit."""
        bar = make_bar(2050, 2060, 2040, 2055)  # bullish
        pos = make_position(stop_loss=2040, take_profit=2055)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=True)
        # L=2040 == SL=2040 → SL fires (Low visited first on bullish bar)
        assert reason == "Stop Loss"
        assert price == 2040

    def test_tp_at_exact_bar_extreme(self, engine):
        """TP exactly at bar high should be considered hit."""
        bar = make_bar(2050, 2060, 2045, 2055)  # bullish
        pos = make_position(stop_loss=2030, take_profit=2060)
        price, reason = engine._resolve_same_bar_sl_tp(bar, pos, is_long=True)
        # L=2045 > SL=2030 → skip; H=2060 >= TP=2060 → TP fires
        assert reason == "Take Profit"
        assert price == 2060
