"""
Refresh dashboard/data/options/sp500_symbols.csv from public datasets.

Usage:
  python scripts/refresh_sp500_symbols.py
"""

from __future__ import annotations

import csv
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen


SOURCES = [
    # Community-maintained mirror (CSV with Symbol column).
    "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/main/data/constituents.csv",
    # Fallback plain list.
    "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/main/data/constituents_symbols.txt",
]


def _load_symbols_from_csv_text(text: str) -> list[str]:
    rows = list(csv.DictReader(text.splitlines()))
    if not rows:
        return []
    out: list[str] = []
    for row in rows:
        symbol = (row.get("Symbol") or row.get("symbol") or "").strip().upper()
        if symbol:
            out.append(symbol)
    return out


def _load_symbols_from_txt(text: str) -> list[str]:
    return [line.strip().upper() for line in text.splitlines() if line.strip()]


def _fetch_text(url: str, timeout_sec: int = 20) -> str:
    with urlopen(url, timeout=timeout_sec) as resp:  # nosec: B310
        return resp.read().decode("utf-8", errors="replace")


def _fetch_symbols() -> list[str]:
    for src in SOURCES:
        try:
            raw = _fetch_text(src)
            if src.endswith(".csv"):
                symbols = _load_symbols_from_csv_text(raw)
            else:
                symbols = _load_symbols_from_txt(raw)
            if symbols:
                return sorted(dict.fromkeys(symbols))
        except URLError:
            continue
        except Exception:
            continue
    return []


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    out_path = repo_root / "dashboard" / "data" / "options" / "sp500_symbols.csv"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    symbols = _fetch_symbols()
    if not symbols:
        print("No remote symbol source available. Kept existing file unchanged.")
        return 1

    with out_path.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["symbol"])
        for s in symbols:
            w.writerow([s])

    print(f"Wrote {len(symbols)} symbols to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

