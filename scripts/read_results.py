"""Read and display batch backtest results."""
import json
import glob
import sys

pattern = sys.argv[1] if len(sys.argv) > 1 else "scripts/results/batch_*.json"
files = sorted(glob.glob(pattern))

for f in files:
    with open(f) as fh:
        data = json.load(fh)
    rows = data if isinstance(data, list) else data.get("results", [])
    for r in rows:
        sid = r.get("strategy_id", r.get("strategy", "?"))
        preset = r.get("preset", "?")
        sym = r.get("symbol", "?")
        tf = r.get("timeframe", "?")
        trades = r.get("total_trades", 0)
        wr = r.get("win_rate", 0)
        pf = r.get("profit_factor", 0)
        sharpe = r.get("sharpe_ratio", 0)
        dd = r.get("max_drawdown_pct", 0)
        net = r.get("net_profit", 0)
        avg_rr = r.get("avg_rr", 0)
        print(
            f"{sid:30s} {preset:15s} {sym:8s} {tf:4s} "
            f"| T={trades:4d} WR={wr:5.1f}% PF={pf:5.2f} "
            f"Sh={sharpe:6.2f} DD={dd:5.1f}% Net=${net:9.2f} RR={avg_rr:5.2f}"
        )
