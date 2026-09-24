"""Check whether frozen trade ledgers reproduce the EA campaign summaries."""

import csv
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports" / "time_matrix_5y_20260924"
FAMILIES = ("orb_current", "macross", "soladvanced")
EPSILON = 1e-7


def read_rows(path):
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def verify_family(family):
    checked = 0
    discrepancies = []
    for summary_path in sorted(REPORTS.glob(f"{family}_*_5y.csv")):
        symbol = summary_path.name[len(family) + 1 : -len("_5y.csv")]
        if not symbol or not symbol[0].isupper():
            continue
        trades_path = REPORTS / f"{family}_{symbol}_trades.csv"
        if not trades_path.exists():
            discrepancies.append(f"{summary_path.name}: trade ledger missing")
            continue
        key = "path" if family == "soladvanced" else "strategy_id"
        trades = defaultdict(list)
        for trade in read_rows(trades_path):
            trades[trade[key]].append(trade)
        for summary in read_rows(summary_path):
            if summary["status"] not in ("AUDITED", "AUDITED_OPEN"):
                continue
            checked += 1
            rows = trades[summary[key]]
            closed = [row for row in rows if row["valid"] == "1" and row["closed"] == "1"]
            opened = sum(row["valid"] == "1" and row["closed"] != "1" for row in rows)
            wins = sum(float(row["net_r"]) > EPSILON for row in closed)
            losses = sum(float(row["net_r"]) < -EPSILON for row in closed)
            net_r = sum(float(row["net_r"]) for row in closed)
            expected = (int(summary["total"]), int(summary["wins"]),
                        int(summary["losses"]), int(summary["open"]))
            actual = (len(rows), wins, losses, opened)
            if actual != expected or abs(net_r - float(summary["net_r"])) > 1e-5:
                discrepancies.append(
                    f"{family}/{symbol}/{summary[key]}: counts {actual} != {expected}; "
                    f"netR {net_r:.8f} != {summary['net_r']}"
                )
            if family != "soladvanced":
                keys = [(row["entry_time"], row["time_matrix_time"]) for row in rows]
                if len(keys) != len(set(keys)):
                    discrepancies.append(f"{family}/{symbol}/{summary[key]}: ambiguous trade keys")
    return checked, discrepancies


def main():
    failures = []
    for family in FAMILIES:
        checked, issues = verify_family(family)
        print(f"{family}: {checked} auditable strategies, {len(issues)} discrepancies")
        failures.extend(issues)
    for issue in failures[:30]:
        print(issue)
    if failures:
        raise SystemExit(f"Baseline ledger is not safe to merge: {len(failures)} discrepancies")


if __name__ == "__main__":
    main()
