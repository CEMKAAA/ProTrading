"""Freeze or verify the research baseline; this is not an incremental EA cache."""

import argparse
import csv
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports" / "time_matrix_5y_20260924"
MANIFEST = REPORTS / "baseline_manifest.json"
SOURCES = {
    "orb_current": ROOT / "IndicatorCodeExamples/orb",
    "macross": ROOT / "IndicatorCodeExamples/macrossover_orb",
    "soladvanced": ROOT / "IndicatorCodeExamples/SolAdvanced",
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def row_count(path):
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return sum(1 for _ in csv.DictReader(handle))


def snapshot():
    files = {}
    for path in sorted(REPORTS.glob("*.csv")):
        if not any(path.name.startswith(prefix + "_") for prefix in SOURCES):
            continue
        files[path.name] = {"sha256": sha256(path), "rows": row_count(path)}
    sources = {}
    for family, folder in SOURCES.items():
        sources[family] = {
            path.relative_to(ROOT).as_posix(): sha256(path)
            for path in sorted(folder.iterdir()) if path.suffix.lower() in {".mq5", ".mqh"}
        }
    shared = ROOT / "IndicatorCodeExamples/ResearchFiveYearLeaderboard.mqh"
    sources["shared"] = {shared.relative_to(ROOT).as_posix(): sha256(shared)}
    return {"schema": 1, "anchor_date": "2026-09-24", "window_days": 1820,
            "research_only": True, "reports": files, "sources": sources}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="freeze the current verified baseline")
    args = parser.parse_args()
    current = snapshot()
    if args.write:
        if MANIFEST.exists():
            raise SystemExit("Manifest already exists; refusing to overwrite the frozen baseline")
        MANIFEST.write_text(json.dumps(current, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Frozen {len(current['reports'])} CSV files at {MANIFEST}")
        return
    if not MANIFEST.exists():
        raise SystemExit("Baseline manifest missing; first verify the ledgers, then use --write")
    expected = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if expected != current:
        missing = set(expected["reports"]) - set(current["reports"])
        added = set(current["reports"]) - set(expected["reports"])
        changed = [name for name in expected["reports"].keys() & current["reports"].keys()
                   if expected["reports"][name] != current["reports"][name]]
        raise SystemExit(f"Baseline mismatch: missing={sorted(missing)}, added={sorted(added)}, "
                         f"changed={sorted(changed)} or source hash changed")
    print(f"Verified {len(current['reports'])} CSV files and all source hashes")


if __name__ == "__main__":
    main()
