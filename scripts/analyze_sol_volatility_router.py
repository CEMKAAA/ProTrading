#!/usr/bin/env python3
"""Evaluate causal volatility routing between fixed 4000/8000 pip geometries."""
from pathlib import Path
import json
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / "logs"
paths = {
    "narrow": LOGS / "sol_advanced_volsl_forward.fixed4000.csv",
    "wide": LOGS / "sol_advanced_volsl_forward.fixed8000.csv",
    "vol": LOGS / "sol_advanced_volsl_forward.rel14_336_e100.csv",
}
frames = {k: pd.read_csv(v) for k, v in paths.items()}
keys = ["available", "direction", "entry"]
for frame in frames.values():
    frame["available"] = pd.to_datetime(frame["available"], format="%Y.%m.%d %H:%M")
base = frames["narrow"].merge(
    frames["wide"][keys + ["result", "r"]], on=keys, suffixes=("_narrow", "_wide"), validate="one_to_one"
).merge(
    frames["vol"][keys + ["sl"]].rename(columns={"sl": "sl_vol"}), on=keys, validate="one_to_one"
)
base["year"] = base.available.dt.year
base["vol_ratio"] = (base.entry - base.sl_vol).abs() / 400.0
base["win_narrow"] = base.result_narrow.eq("WIN")
base["win_wide"] = base.result_wide.eq("WIN")
base["oracle_win"] = base.win_narrow | base.win_wide

def score(mask_wide, subset):
    m = mask_wide.loc[subset.index]
    wins = np.where(m, subset.win_wide, subset.win_narrow)
    rs = np.where(m, subset.r_wide, subset.r_narrow)
    return {"trades": int(len(subset)), "wins": int(wins.sum()), "wr": float(wins.mean()), "net_r": float(rs.sum())}

dev = base[base.year.between(2021, 2023)]
thresholds = sorted(set(float(x) for x in np.quantile(dev.vol_ratio, np.linspace(0.05, 0.95, 37))))
candidates = []
for threshold in thresholds:
    for wide_when_high in (True, False):
        mask = base.vol_ratio.ge(threshold) if wide_when_high else base.vol_ratio.lt(threshold)
        total = score(mask, dev)
        year_wrs = []
        for _, group in dev.groupby("year"):
            year_wrs.append(score(mask, group)["wr"])
        candidates.append({
            "threshold": threshold,
            "wide_when_high": wide_when_high,
            **total,
            "min_dev_year_wr": min(year_wrs),
        })
ranked = sorted(candidates, key=lambda x: (x["min_dev_year_wr"], x["wr"], x["net_r"]), reverse=True)
selected = ranked[0]
mask = base.vol_ratio.ge(selected["threshold"]) if selected["wide_when_high"] else base.vol_ratio.lt(selected["threshold"])
report = {
    "protocol": {"development": "2021-2023", "validation": "2024", "forward": "2025-2026"},
    "selected_on_development": selected,
    "overall_selected": score(mask, base),
    "by_year_selected": {},
    "by_year_narrow": {},
    "by_year_wide": {},
    "by_year_oracle": {},
    "outcome_overlap": {
        "both_win": int((base.win_narrow & base.win_wide).sum()),
        "narrow_only": int((base.win_narrow & ~base.win_wide).sum()),
        "wide_only": int((~base.win_narrow & base.win_wide).sum()),
        "both_loss": int((~base.win_narrow & ~base.win_wide).sum()),
    },
    "top_development_candidates": ranked[:10],
}
for year, group in base.groupby("year"):
    y = str(int(year))
    report["by_year_selected"][y] = score(mask, group)
    report["by_year_narrow"][y] = score(pd.Series(False, index=base.index), group)
    report["by_year_wide"][y] = score(pd.Series(True, index=base.index), group)
    report["by_year_oracle"][y] = {"trades": int(len(group)), "wins": int(group.oracle_win.sum()), "wr": float(group.oracle_win.mean())}

out = LOGS / "sol_advanced_volatility_router_analysis.json"
out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2))
