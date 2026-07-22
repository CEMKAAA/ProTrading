#!/usr/bin/env python3
"""Evaluate a three-regime monotonic volatility-to-SL policy."""
from itertools import combinations_with_replacement
from pathlib import Path
import json
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
L = ROOT / "logs"
paths = {
    4000: L / "sol_advanced_volsl_forward.fixed4000.csv",
    5000: L / "sol_advanced_fixed_geometry_forward.fixed5000.csv",
    6000: L / "sol_advanced_fixed_geometry_forward.fixed6000.csv",
    7000: L / "sol_advanced_fixed_geometry_forward.fixed7000.csv",
    8000: L / "sol_advanced_volsl_forward.fixed8000.csv",
}
vol = pd.read_csv(L / "sol_advanced_volsl_forward.rel14_336_e100.csv")
keys = ["available", "direction", "entry"]
base = None
for pips, path in paths.items():
    frame = pd.read_csv(path)
    frame["available"] = pd.to_datetime(frame["available"], format="%Y.%m.%d %H:%M")
    frame = frame[keys + ["result", "r"]].rename(columns={"result": f"result_{pips}", "r": f"r_{pips}"})
    base = frame if base is None else base.merge(frame, on=keys, validate="one_to_one")
vol["available"] = pd.to_datetime(vol["available"], format="%Y.%m.%d %H:%M")
base = base.merge(vol[keys + ["sl"]].rename(columns={"sl": "sl_vol"}), on=keys, validate="one_to_one")
base["year"] = base.available.dt.year
base["vol_ratio"] = (base.entry - base.sl_vol).abs() / 400.0

def evaluate(frame, assignment, q1, q2):
    regimes = np.where(frame.vol_ratio < q1, 0, np.where(frame.vol_ratio < q2, 1, 2))
    wins = np.zeros(len(frame), dtype=bool)
    rs = np.zeros(len(frame), dtype=float)
    for idx, pips in enumerate(assignment):
        mask = regimes == idx
        wins[mask] = frame.loc[mask, f"result_{pips}"].eq("WIN")
        rs[mask] = frame.loc[mask, f"r_{pips}"]
    return {"trades": int(len(frame)), "wins": int(wins.sum()), "wr": float(wins.mean()), "net_r": float(rs.sum())}

dev = base[base.year.between(2021, 2023)]
q1, q2 = [float(x) for x in dev.vol_ratio.quantile([1/3, 2/3])]
rows = []
for assignment in combinations_with_replacement(paths.keys(), 3):
    total = evaluate(dev, assignment, q1, q2)
    year_scores = [evaluate(group, assignment, q1, q2) for _, group in dev.groupby("year")]
    rows.append({"assignment": assignment, **total, "min_dev_year_wr": min(x["wr"] for x in year_scores)})
ranked = sorted(rows, key=lambda x: (x["min_dev_year_wr"], x["wr"], x["net_r"]), reverse=True)
selected = ranked[0]
report = {
    "protocol": {"development": "2021-2023", "validation": "2024", "forward": "2025-2026"},
    "volatility_thresholds": [q1, q2],
    "selected": selected,
    "by_year_selected": {},
    "by_year_oracle_5_geometries": {},
    "top_candidates": ranked[:10],
}
for year, group in base.groupby("year"):
    y = str(int(year))
    report["by_year_selected"][y] = evaluate(group, selected["assignment"], q1, q2)
    wins = pd.concat([group[f"result_{p}"].eq("WIN") for p in paths], axis=1).any(axis=1)
    report["by_year_oracle_5_geometries"][y] = {"trades": int(len(group)), "wins": int(wins.sum()), "wr": float(wins.mean())}
report["overall_selected"] = evaluate(base, selected["assignment"], q1, q2)
out = L / "sol_advanced_volatility_three_regime_analysis.json"
out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2))
