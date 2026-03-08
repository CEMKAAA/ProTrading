from __future__ import annotations

from typing import Any, Dict, Iterable

import numpy as np

from .models import MicrostructureSnapshot


def _to_float(value: Any, default: float = 0.0) -> float:
    try:
        if value is None:
            return float(default)
        if isinstance(value, (list, tuple, dict)):
            return float(default)
        if np.isnan(value):
            return float(default)
        return float(value)
    except Exception:
        return float(default)


def build_snapshot_from_bar(bar: Any, config: Any) -> MicrostructureSnapshot:
    """Build a microstructure snapshot from a bar-like object (Series/dict)."""
    flow_col = str(getattr(config, "micro_flow_imbalance_col", "of_flow_imbalance"))
    dom_col = str(getattr(config, "micro_dom_imbalance_col", "dom_imbalance"))
    absorption_col = str(getattr(config, "micro_absorption_col", "dom_absorption_score"))
    lva_col = str(getattr(config, "micro_lva_velocity_col", "lva_velocity"))

    raw = {
        flow_col: _to_float(bar.get(flow_col, 0.0), 0.0),
        dom_col: _to_float(bar.get(dom_col, 0.0), 0.0),
        absorption_col: _to_float(bar.get(absorption_col, 0.0), 0.0),
        lva_col: _to_float(bar.get(lva_col, 0.0), 0.0),
    }

    return MicrostructureSnapshot(
        spread=_to_float(bar.get("spread", 0.0), 0.0),
        volume=max(0.0, _to_float(bar.get("volume", 0.0), 0.0)),
        flow_imbalance=float(np.clip(raw[flow_col], -1.0, 1.0)),
        dom_imbalance=float(np.clip(raw[dom_col], -1.0, 1.0)),
        absorption_score=raw[absorption_col],
        lva_velocity=max(0.0, raw[lva_col]),
        raw_columns=raw,
    )


def summarize_microstructure_from_trades(trades: Iterable[Any]) -> Dict[str, float]:
    """Aggregate microstructure execution diagnostics from trade entry metadata."""
    fill_probs = []
    fill_ratios = []
    entry_impacts = []
    exit_impacts = []

    for t in trades:
        meta = None
        if isinstance(t, dict):
            meta = t.get("entry_reason")
        else:
            meta = getattr(t, "entry_reason", None)

        if not isinstance(meta, dict):
            continue
        if str(meta.get("execution_mode", "bar")).lower() != "microstructure":
            continue

        if "micro_fill_probability" in meta:
            fill_probs.append(_to_float(meta.get("micro_fill_probability"), 0.0))
        if "micro_fill_ratio" in meta:
            fill_ratios.append(_to_float(meta.get("micro_fill_ratio"), 0.0))
        if "micro_entry_impact_usd" in meta:
            entry_impacts.append(_to_float(meta.get("micro_entry_impact_usd"), 0.0))
        if "micro_exit_impact_usd" in meta:
            exit_impacts.append(_to_float(meta.get("micro_exit_impact_usd"), 0.0))

    trade_count = len(fill_probs) if fill_probs else 0
    summary = {
        "trade_count": trade_count,
        "avg_fill_probability": float(np.mean(fill_probs)) if fill_probs else 0.0,
        "avg_fill_ratio": float(np.mean(fill_ratios)) if fill_ratios else 0.0,
        "avg_entry_impact_usd": float(np.mean(entry_impacts)) if entry_impacts else 0.0,
        "avg_exit_impact_usd": float(np.mean(exit_impacts)) if exit_impacts else 0.0,
        "total_entry_impact_usd": float(np.sum(entry_impacts)) if entry_impacts else 0.0,
        "total_exit_impact_usd": float(np.sum(exit_impacts)) if exit_impacts else 0.0,
    }
    summary["total_impact_usd"] = summary["total_entry_impact_usd"] + summary["total_exit_impact_usd"]
    return summary
