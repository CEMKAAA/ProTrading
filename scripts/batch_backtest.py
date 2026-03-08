"""
Batch Backtest Runner
Runs backtests for multiple strategy/preset/symbol combinations without needing the FastAPI server.
Usage: python -m scripts.batch_backtest [--strategy_id X] [--preset Y] [--symbol Z]
"""

import sys
import os
import json
import time
import logging
from datetime import datetime
from dataclasses import asdict
from pathlib import Path

# Force unbuffered output for background execution
os.environ["PYTHONUNBUFFERED"] = "1"

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from dashboard.backend.core.backtest_engine import BacktestEngine, BacktestConfig
from dashboard.backend.core.advanced_backtest_engine import AdvancedEventBacktestEngine
from dashboard.backend.core.strategy_registry import StrategyRegistry
from dashboard.backend.core.strategies.factory import create_strategy
from dashboard.backend.core.instrument_specs import get_instrument
from dashboard.backend.core.config_builder import build_config_from_preset

logging.basicConfig(
    level=logging.WARNING,
    format="%(levelname)s | %(message)s",
)
# Suppress noisy loggers during batch runs
for name in ("dashboard", "urllib3", "matplotlib"):
    logging.getLogger(name).setLevel(logging.ERROR)

RESULTS_DIR = PROJECT_ROOT / "scripts" / "results"
RESULTS_DIR.mkdir(exist_ok=True)


def build_backtest_config(strategy_id, preset_id, symbol, timeframe, start_date, end_date, initial_balance=10000.0):
    """Build a BacktestConfig from registry preset + instrument specs.

    Delegates to the shared ``config_builder.build_config_from_preset``
    so that batch and UI always produce identical configs.
    """
    return build_config_from_preset(
        strategy_id=strategy_id,
        preset_id=preset_id,
        symbol=symbol,
        timeframe=timeframe,
        start_date=start_date,
        end_date=end_date,
        initial_balance=initial_balance,
        data_source="csv_only",
    )


def _make_progress_cb():
    """Create a progress callback that prints percentage every 10%."""
    state = {"last": 0, "t0": time.time()}

    def cb(progress, message):
        pct = int(progress)
        if pct >= state["last"] + 10 or pct >= 100:
            elapsed = time.time() - state["t0"]
            print(f"    [{pct:3d}%] {elapsed:5.0f}s | {message}", flush=True)
            state["last"] = pct

    return cb


def run_single_backtest(strategy_id, preset_id, symbol, timeframe, start_date, end_date, initial_balance=10000.0, engine_mode="legacy"):
    """Run a single backtest and return results dict.

    Args:
        engine_mode: "legacy" for BacktestEngine, "advanced" for AdvancedEventBacktestEngine.
    """
    config, strategy_config = build_backtest_config(
        strategy_id, preset_id, symbol, timeframe, start_date, end_date, initial_balance
    )

    # Inject instrument metadata for strategy factory
    inst = get_instrument(symbol)
    strategy_config["_instrument"] = inst
    strategy_config["symbol"] = symbol

    strategy = create_strategy(strategy_id, strategy_config)
    if engine_mode == "advanced":
        engine = AdvancedEventBacktestEngine(config, strategy=strategy)
    else:
        engine = BacktestEngine(config, strategy=strategy)

    t0 = time.time()
    results = engine.run(progress_callback=_make_progress_cb())
    elapsed = time.time() - t0

    # Extract key metrics — results dict has metrics nested under 'metrics' key
    m = results.get("metrics", {})
    ms = results.get("microstructure_analysis") or {}
    metrics = {
        "strategy_id": strategy_id,
        "preset": preset_id,
        "symbol": symbol,
        "timeframe": timeframe,
        "period": f"{start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}",
        "elapsed_sec": round(elapsed, 1),
        "total_trades": m.get("total_trades", 0),
        "winning_trades": m.get("winning_trades", 0),
        "losing_trades": m.get("losing_trades", 0),
        "win_rate": m.get("win_rate", 0),
        "net_profit": m.get("net_profit", 0),
        "profit_factor": m.get("profit_factor", 0),
        "sharpe_ratio": m.get("sharpe_ratio", 0),
        "sortino_ratio": m.get("sortino_ratio", 0),
        "max_drawdown_pct": m.get("max_drawdown_percent", 0),
        "avg_rr": m.get("avg_rr_ratio", 0),
        "expectancy": m.get("expectancy", 0),
        "final_balance": m.get("final_balance", initial_balance),
        "largest_win": m.get("largest_win", 0),
        "largest_loss": m.get("largest_loss", 0),
        "data_hash": results.get("data_hash", ""),
        "micro_trade_count": ms.get("trade_count", 0),
        "micro_avg_fill_probability": ms.get("avg_fill_probability", 0.0),
        "micro_total_impact_usd": ms.get("total_impact_usd", 0.0),
    }
    return metrics, results


def print_results_table(all_results):
    """Print a formatted comparison table."""
    if not all_results:
        print("No results to display.")
        return

    # Header
    print("\n" + "=" * 146)
    print(f"{'Strategy':<28} {'Preset':<14} {'Trades':>7} {'WR%':>6} {'PF':>6} {'Sharpe':>7} {'DD%':>6} {'Net$':>10} {'MImp$':>8} {'MFill':>7} {'AvgRR':>6} {'Time':>6}")
    print("-" * 146)

    for r in all_results:
        # Color coding via verdict
        trades = r["total_trades"]
        wr = r["win_rate"]
        pf = r["profit_factor"]
        sharpe = r["sharpe_ratio"]
        dd = r["max_drawdown_pct"]
        net = r["net_profit"]

        print(
            f"{r['strategy_id']:<28} {r['preset']:<14} "
            f"{trades:>7} {wr:>5.1f}% {pf:>6.2f} {sharpe:>7.3f} {dd:>5.1f}% "
            f"${net:>9.2f} ${r.get('micro_total_impact_usd', 0):>7.2f} {r.get('micro_avg_fill_probability', 0):>7.3f} "
            f"{r['avg_rr']:>6.2f} {r['elapsed_sec']:>5.1f}s"
        )

    print("=" * 146)

    # Verdict summary
    print("\nVERDICT (Sharpe>1.0, PF>1.3, DD<15%, WR>45%):")
    for r in all_results:
        checks = []
        if r["sharpe_ratio"] >= 1.0:
            checks.append("Sharpe OK")
        else:
            checks.append(f"Sharpe FAIL ({r['sharpe_ratio']:.3f})")
        if r["profit_factor"] >= 1.3:
            checks.append("PF OK")
        else:
            checks.append(f"PF FAIL ({r['profit_factor']:.2f})")
        if r["max_drawdown_pct"] <= 15.0:
            checks.append("DD OK")
        else:
            checks.append(f"DD FAIL ({r['max_drawdown_pct']:.1f}%)")
        if r["win_rate"] >= 45.0:
            checks.append("WR OK")
        else:
            checks.append(f"WR FAIL ({r['win_rate']:.1f}%)")

        all_pass = (
            r["sharpe_ratio"] >= 1.0
            and r["profit_factor"] >= 1.3
            and r["max_drawdown_pct"] <= 15.0
            and r["win_rate"] >= 45.0
        )
        verdict = "DEPLOY" if all_pass else ("TUNE" if r["net_profit"] > 0 else "KILL")
        tag = f"[{verdict}]"
        print(f"  {tag:<8} {r['strategy_id']:<28} {r['preset']:<14} | {', '.join(checks)}")
    print()


def analyze_trades(results):
    """Analyze trade-level data to identify win/loss patterns."""
    trades = results.get("trades", [])
    if not trades:
        print("  No trade data available for analysis.")
        return

    print(f"\n{'='*80}")
    print(f"TRADE ANALYSIS ({len(trades)} trades)")
    print(f"{'='*80}")

    ms = results.get("microstructure_analysis") or {}
    if ms:
        print(
            "  Microstructure: "
            f"trades={int(ms.get('trade_count', 0))}, "
            f"avg_fill_p={float(ms.get('avg_fill_probability', 0.0)):.3f}, "
            f"avg_fill_ratio={float(ms.get('avg_fill_ratio', 0.0)):.3f}, "
            f"total_impact=${float(ms.get('total_impact_usd', 0.0)):.2f}"
        )

    # Exit reason distribution
    exit_reasons = {}
    for t in trades:
        reason = t.get("exit_reason", "Unknown")
        is_win = t.get("profit_loss", 0) > 0
        if reason not in exit_reasons:
            exit_reasons[reason] = {"wins": 0, "losses": 0, "total_pnl": 0.0}
        if is_win:
            exit_reasons[reason]["wins"] += 1
        else:
            exit_reasons[reason]["losses"] += 1
        exit_reasons[reason]["total_pnl"] += t.get("profit_loss", 0)

    print("\n  Exit Reason Breakdown:")
    print(f"  {'Reason':<25} {'Wins':>5} {'Loss':>5} {'WR%':>6} {'Net$':>10}")
    print(f"  {'-'*55}")
    for reason, data in sorted(exit_reasons.items(), key=lambda x: -(x[1]["wins"] + x[1]["losses"])):
        total = data["wins"] + data["losses"]
        wr = data["wins"] / total * 100 if total > 0 else 0
        print(f"  {reason:<25} {data['wins']:>5} {data['losses']:>5} {wr:>5.1f}% ${data['total_pnl']:>9.2f}")

    # Bias strength distribution
    bias_buckets = {"0-25": {"w": 0, "l": 0}, "26-40": {"w": 0, "l": 0},
                    "41-60": {"w": 0, "l": 0}, "61-80": {"w": 0, "l": 0}, "81-100": {"w": 0, "l": 0}}
    for t in trades:
        er = t.get("entry_reason") or {}
        bs = er.get("bias_strength", 0)
        is_win = t.get("profit_loss", 0) > 0
        if bs <= 25:
            bucket = "0-25"
        elif bs <= 40:
            bucket = "26-40"
        elif bs <= 60:
            bucket = "41-60"
        elif bs <= 80:
            bucket = "61-80"
        else:
            bucket = "81-100"
        if is_win:
            bias_buckets[bucket]["w"] += 1
        else:
            bias_buckets[bucket]["l"] += 1

    print("\n  Bias Strength vs Win Rate:")
    print(f"  {'Bias Range':<12} {'Wins':>5} {'Loss':>5} {'Total':>6} {'WR%':>6}")
    print(f"  {'-'*38}")
    for bucket, data in bias_buckets.items():
        total = data["w"] + data["l"]
        wr = data["w"] / total * 100 if total > 0 else 0
        print(f"  {bucket:<12} {data['w']:>5} {data['l']:>5} {total:>6} {wr:>5.1f}%")

    # R-multiple distribution
    r_wins = [t.get("r_multiple", 0) for t in trades if t.get("profit_loss", 0) > 0]
    r_losses = [t.get("r_multiple", 0) for t in trades if t.get("profit_loss", 0) <= 0]
    if r_wins:
        print(f"\n  R-Multiple (Wins):  avg={sum(r_wins)/len(r_wins):.2f}R  med={sorted(r_wins)[len(r_wins)//2]:.2f}R  max={max(r_wins):.2f}R")
    if r_losses:
        print(f"  R-Multiple (Losses): avg={sum(r_losses)/len(r_losses):.2f}R  med={sorted(r_losses)[len(r_losses)//2]:.2f}R  min={min(r_losses):.2f}R")

    # MFE/MAE analysis - how far did losers go in our favor before turning?
    loser_mfe = [t.get("max_favorable_excursion", 0) for t in trades if t.get("profit_loss", 0) <= 0]
    if loser_mfe:
        high_mfe_losers = sum(1 for m in loser_mfe if m >= 0.5)
        reached_1r = sum(1 for m in loser_mfe if m >= 1.0)
        reached_15r = sum(1 for m in loser_mfe if m >= 1.5)
        print(f"\n  Losing Trades MFE (how far in favor before reversing):")
        print(f"    Avg MFE: {sum(loser_mfe)/len(loser_mfe):.2f}R | "
              f"Reached >=0.5R: {high_mfe_losers}/{len(loser_mfe)} ({high_mfe_losers/len(loser_mfe)*100:.0f}%) | "
              f">=1R: {reached_1r} | >=1.5R: {reached_15r}")

    # Direction analysis
    longs = [t for t in trades if t.get("direction") == "BUY"]
    shorts = [t for t in trades if t.get("direction") == "SELL"]
    long_wins = sum(1 for t in longs if t.get("profit_loss", 0) > 0)
    short_wins = sum(1 for t in shorts if t.get("profit_loss", 0) > 0)
    print(f"\n  Direction: LONG {long_wins}/{len(longs)} WR={long_wins/len(longs)*100:.1f}% | "
          f"SHORT {short_wins}/{len(shorts)} WR={short_wins/len(shorts)*100:.1f}%" if longs and shorts else "")

    # Cost analysis
    total_spread = sum(t.get("spread_cost", 0) for t in trades)
    total_slippage = sum(t.get("slippage_cost", 0) for t in trades)
    total_commission = sum(t.get("commission_cost", 0) for t in trades)
    total_swap = sum(t.get("swap_cost", 0) for t in trades)
    total_costs = total_spread + total_slippage + total_commission + total_swap
    total_gross = sum(t.get("gross_pnl", 0) for t in trades)
    print(f"\n  Cost Breakdown: spread=${total_spread:.0f} slip=${total_slippage:.0f} "
          f"comm=${total_commission:.0f} swap=${total_swap:.0f} | Total=${total_costs:.0f}")
    print(f"  Gross P&L: ${total_gross:.0f} -> Net after costs: ${total_gross-total_costs:.0f}")

    # OB confluence analysis
    trades_with_ob = [t for t in trades if (t.get("entry_reason") or {}).get("ob")]
    trades_without_ob = [t for t in trades if not (t.get("entry_reason") or {}).get("ob")]
    ob_wins = sum(1 for t in trades_with_ob if t.get("profit_loss", 0) > 0)
    no_ob_wins = sum(1 for t in trades_without_ob if t.get("profit_loss", 0) > 0)
    if trades_with_ob:
        print(f"\n  OB Confluence: WITH OB {ob_wins}/{len(trades_with_ob)} WR={ob_wins/len(trades_with_ob)*100:.1f}% | "
              f"WITHOUT OB {no_ob_wins}/{len(trades_without_ob)} WR={no_ob_wins/len(trades_without_ob)*100:.1f}%")

    print()


def save_results(all_results, filename):
    """Save results to JSON."""
    path = RESULTS_DIR / filename
    with open(path, "w") as f:
        json.dump(all_results, f, indent=2, default=str)
    print(f"Results saved to {path}")


def run_strategy_suite(strategy_id, symbol, timeframe, start_date, end_date, presets=None, engine_mode="legacy"):
    """Run all presets for a single strategy and return results."""
    if presets is None:
        presets = ["conservative", "default", "aggressive"]

    results = []
    for preset in presets:
        label = f"{strategy_id} / {preset} / {symbol} {timeframe}"
        print(f"\n>>> Running: {label} ...")
        try:
            metrics, _ = run_single_backtest(
                strategy_id, preset, symbol, timeframe, start_date, end_date,
                engine_mode=engine_mode
            )
            results.append(metrics)
            print(f"    Done in {metrics['elapsed_sec']}s | {metrics['total_trades']} trades | "
                  f"WR={metrics['win_rate']:.1f}% | PF={metrics['profit_factor']:.2f} | "
                  f"Sharpe={metrics['sharpe_ratio']:.3f} | DD={metrics['max_drawdown_pct']:.1f}% | "
                  f"Net=${metrics['net_profit']:.2f}")
        except Exception as e:
            print(f"    FAILED: {e}")
            results.append({
                "strategy_id": strategy_id, "preset": preset, "symbol": symbol,
                "timeframe": timeframe, "error": str(e),
                "total_trades": 0, "win_rate": 0, "profit_factor": 0,
                "sharpe_ratio": 0, "max_drawdown_pct": 0, "net_profit": 0,
                "avg_rr": 0, "elapsed_sec": 0, "expectancy": 0,
                "final_balance": 10000, "largest_win": 0, "largest_loss": 0,
            })
    return results


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Batch Backtest Runner")
    parser.add_argument("--strategy", type=str, help="Single strategy ID to test")
    parser.add_argument("--preset", type=str, help="Single preset (conservative/default/aggressive)")
    parser.add_argument("--symbol", type=str, default="XAUUSD", help="Trading symbol")
    parser.add_argument("--timeframe", type=str, default="M1", help="Timeframe")
    parser.add_argument("--start", type=str, default="2022-01-01", help="Start date YYYY-MM-DD")
    parser.add_argument("--end", type=str, default="2024-12-31", help="End date YYYY-MM-DD")
    parser.add_argument("--balance", type=float, default=10000.0, help="Initial balance")
    parser.add_argument("--analyze", action="store_true", help="Output trade-level analysis")
    parser.add_argument("--engine", type=str, default="legacy", choices=["legacy", "advanced"],
                        help="Engine mode: legacy (BacktestEngine) or advanced (AdvancedEventBacktestEngine)")
    args = parser.parse_args()

    start_date = datetime.strptime(args.start, "%Y-%m-%d")
    end_date = datetime.strptime(args.end, "%Y-%m-%d")
    presets = args.preset.split(",") if args.preset else None

    if args.strategy:
        # Single strategy mode
        if args.analyze and presets and len(presets) == 1:
            # Single preset + analyze: show trade-level data
            label = f"{args.strategy} / {presets[0]} / {args.symbol} {args.timeframe}"
            print(f"\n>>> Running: {label} ...")
            metrics, full_results = run_single_backtest(
                args.strategy, presets[0], args.symbol, args.timeframe,
                start_date, end_date, args.balance, engine_mode=args.engine
            )
            results = [metrics]
            print(f"    Done in {metrics['elapsed_sec']}s | {metrics['total_trades']} trades | "
                  f"WR={metrics['win_rate']:.1f}% | PF={metrics['profit_factor']:.2f} | "
                  f"Sharpe={metrics['sharpe_ratio']:.3f} | DD={metrics['max_drawdown_pct']:.1f}% | "
                  f"Net=${metrics['net_profit']:.2f}")
            analyze_trades(full_results)
        else:
            results = run_strategy_suite(
                args.strategy, args.symbol, args.timeframe,
                start_date, end_date, presets, engine_mode=args.engine
            )
    else:
        # Default: run ORB strategies
        results = []
        for sid in ["orb_strategy", "advanced_orb_strategy"]:
            results.extend(run_strategy_suite(
                sid, args.symbol, args.timeframe, start_date, end_date, presets,
                engine_mode=args.engine
            ))

    print_results_table(results)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    save_results(results, f"batch_{timestamp}.json")
