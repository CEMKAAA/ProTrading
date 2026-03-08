"""
One-shot migration for stale preset overrides in backtest_configs.

Some legacy configs stored instrument fallback values (e.g. NAS100 spread/SL/FVG)
that can mask tuned preset values during strategy config assembly.

This script updates only rows that match a stale signature:
- DB value equals instrument fallback
- preset value for that key differs from instrument fallback
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Dict

ROOT_DIR = Path(__file__).resolve().parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from dashboard.backend.core.instrument_specs import get_instrument
from dashboard.backend.core.strategy_registry import StrategyRegistry
from dashboard.backend.models.database import BacktestConfigModel, SessionLocal


STALE_KEYS: Dict[str, str] = {
    "max_spread_usd": "max_spread",
    "min_sl_usd": "min_sl",
    "max_sl_usd": "max_sl",
    "min_fvg_gap": "min_fvg_gap",
    "slippage_atr_factor": "slippage_atr_factor",
}

LEGACY_SWAP_DEFAULTS = {
    "swap_long_per_lot": -8.5,
    "swap_short_per_lot": -3.2,
}

TF_HINT_RE = re.compile(r"(?:^|_)(m\d+|h\d+|d\d+)(?:_|$)", re.IGNORECASE)


def _same_value(a, b, tol: float = 1e-9) -> bool:
    if a is None or b is None:
        return a is b
    try:
        return abs(float(a) - float(b)) <= tol
    except (TypeError, ValueError):
        return a == b


def _extract_timeframe_hint(preset_id: str | None) -> str | None:
    if not preset_id:
        return None
    m = TF_HINT_RE.search(preset_id)
    if not m:
        return None
    return m.group(1).upper()


def migrate(dry_run: bool) -> None:
    db = SessionLocal()
    try:
        rows = db.query(BacktestConfigModel).all()
        changed_rows = 0
        changed_fields = 0

        for row in rows:
            strategy_id = getattr(row, "strategy_id", None)
            preset_id = getattr(row, "preset_name", None) or getattr(row, "preset", None)
            symbol = getattr(row, "symbol", None)
            if not strategy_id or not preset_id or not symbol:
                continue

            strategy = StrategyRegistry.get_strategy(strategy_id)
            if strategy is None:
                continue

            preset_cfg = StrategyRegistry.get_preset_config(strategy_id, preset_id, symbol)
            inst = get_instrument(symbol)

            row_updates = []

            for key, inst_attr in STALE_KEYS.items():
                row_v = getattr(row, key, None)
                preset_v = preset_cfg.get(key)
                inst_v = getattr(inst, inst_attr)
                if row_v is None or preset_v is None:
                    continue
                if _same_value(row_v, inst_v) and not _same_value(preset_v, inst_v):
                    setattr(row, key, preset_v)
                    row_updates.append(f"{key}: {row_v} -> {preset_v}")

            for key, legacy_default in LEGACY_SWAP_DEFAULTS.items():
                row_v = getattr(row, key, None)
                inst_v = inst.swap_long if key == "swap_long_per_lot" else inst.swap_short
                if row_v is None:
                    continue
                if _same_value(row_v, legacy_default) and not _same_value(inst_v, legacy_default):
                    setattr(row, key, inst_v)
                    row_updates.append(f"{key}: {row_v} -> {inst_v}")

            tf_hint = _extract_timeframe_hint(preset_id)
            if tf_hint:
                current_tf = str(getattr(row, "timeframe", "") or "").upper()
                if current_tf != tf_hint:
                    setattr(row, "timeframe", tf_hint)
                    row_updates.append(f"timeframe: {current_tf or '<empty>'} -> {tf_hint}")

            if row_updates:
                changed_rows += 1
                changed_fields += len(row_updates)
                print(f"[config:{row.id}] {row.strategy_id}/{preset_id}/{symbol}")
                for u in row_updates:
                    print(f"  - {u}")

        if dry_run:
            db.rollback()
            print(f"\nDRY RUN complete: {changed_rows} rows, {changed_fields} field updates.")
        else:
            db.commit()
            print(f"\nMigration complete: {changed_rows} rows, {changed_fields} field updates.")
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Fix stale preset overrides in saved backtest configs.")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Persist updates (default is dry-run).",
    )
    args = parser.parse_args()
    migrate(dry_run=not args.apply)


if __name__ == "__main__":
    main()
