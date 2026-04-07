"""
Fetch Telegram channel messages with a user account session (Telethon).

Use this when you cannot add a bot as channel admin.
The script can export the last N days of messages to JSON/JSONL/CSV.

Examples:
  python scripts/fetch_telegram_channel_messages.py --channel "Elite Pips Academy" --days 7
  python scripts/fetch_telegram_channel_messages.py --channel @elitepipsacademy --days 7 --out scripts/results/elite_week.json
  python scripts/fetch_telegram_channel_messages.py --channel "https://t.me/your_channel" --days 7 --out scripts/results/feed.csv

Required:
  TELEGRAM_API_ID and TELEGRAM_API_HASH env vars
  or pass --api-id / --api-hash directly.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import json
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


def _require_telethon():
    try:
        from telethon import TelegramClient  # type: ignore
        from telethon.errors import FloodWaitError  # type: ignore
    except Exception as exc:
        raise SystemExit(
            "Telethon is required. Install with: pip install telethon\n"
            f"Import error: {type(exc).__name__}: {str(exc)}"
        )
    return TelegramClient, FloodWaitError


def _slug(value: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9]+", "_", str(value or "").strip().lower()).strip("_")
    return s or "telegram_channel"


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export Telegram channel messages for last N days.")
    parser.add_argument("--channel", required=True, help="Channel username/title/link (e.g. @name or https://t.me/name)")
    parser.add_argument("--days", type=int, default=7, help="How many past days to fetch (default: 7)")
    parser.add_argument("--api-id", type=int, default=None, help="Telegram API ID (or env TELEGRAM_API_ID)")
    parser.add_argument("--api-hash", default=None, help="Telegram API hash (or env TELEGRAM_API_HASH)")
    parser.add_argument(
        "--session",
        default="scripts/.telegram_listener",
        help="Telethon session path prefix (default: scripts/.telegram_listener)",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Output path. Extension decides format: .json, .jsonl, .csv (default: scripts/results/<slug>_<ts>.json)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Hard max messages to scan (0 = no hard limit, default: 0)",
    )
    parser.add_argument(
        "--include-empty",
        action="store_true",
        help="Include messages that have no text/caption.",
    )
    return parser.parse_args()


def _resolve_output_path(channel: str, out: Optional[str]) -> Path:
    if out:
        p = Path(out)
        p.parent.mkdir(parents=True, exist_ok=True)
        return p
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    p = Path("scripts") / "results" / f"{_slug(channel)}_{ts}.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def _serialize_message(msg: Any) -> Dict[str, Any]:
    dt = getattr(msg, "date", None)
    date_iso = None
    if isinstance(dt, datetime):
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        date_iso = dt.astimezone(timezone.utc).isoformat()
    sender_id = getattr(msg, "sender_id", None)
    views = getattr(msg, "views", None)
    forwards = getattr(msg, "forwards", None)
    text = str(getattr(msg, "message", "") or "")
    return {
        "id": int(getattr(msg, "id", 0) or 0),
        "date_utc": date_iso,
        "sender_id": int(sender_id) if isinstance(sender_id, int) else sender_id,
        "text": text,
        "views": int(views) if isinstance(views, int) else views,
        "forwards": int(forwards) if isinstance(forwards, int) else forwards,
        "reply_to_msg_id": int(getattr(msg, "reply_to_msg_id", 0) or 0) or None,
        "has_media": bool(getattr(msg, "media", None) is not None),
    }


def _write_output(path: Path, rows: List[Dict[str, Any]]) -> None:
    ext = path.suffix.lower()
    if ext == ".csv":
        fieldnames = ["id", "date_utc", "sender_id", "text", "views", "forwards", "reply_to_msg_id", "has_media"]
        with path.open("w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fieldnames)
            w.writeheader()
            for row in rows:
                w.writerow({k: row.get(k) for k in fieldnames})
        return
    if ext == ".jsonl":
        with path.open("w", encoding="utf-8") as f:
            for row in rows:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
        return
    with path.open("w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)


async def _run() -> int:
    TelegramClient, FloodWaitError = _require_telethon()
    args = _parse_args()

    api_id = args.api_id if args.api_id is not None else int(os.getenv("TELEGRAM_API_ID", "0") or 0)
    api_hash = args.api_hash if args.api_hash is not None else str(os.getenv("TELEGRAM_API_HASH", "") or "").strip()

    if api_id <= 0 or not api_hash:
        raise SystemExit("Missing Telegram credentials. Set TELEGRAM_API_ID and TELEGRAM_API_HASH or pass --api-id/--api-hash.")

    since_dt = datetime.now(timezone.utc) - timedelta(days=max(1, int(args.days)))
    out_path = _resolve_output_path(args.channel, args.out)
    session_path = str(Path(args.session))

    client = TelegramClient(session_path, api_id, api_hash)
    await client.start()
    try:
        entity = await client.get_entity(args.channel)
        rows: List[Dict[str, Any]] = []
        scanned = 0
        limit = int(args.limit or 0)
        async for msg in client.iter_messages(entity):
            scanned += 1
            if limit > 0 and scanned > limit:
                break
            dt = getattr(msg, "date", None)
            if isinstance(dt, datetime):
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                if dt.astimezone(timezone.utc) < since_dt:
                    break
            row = _serialize_message(msg)
            if (not args.include_empty) and (not str(row.get("text") or "").strip()):
                continue
            rows.append(row)
        rows.reverse()  # oldest -> newest
        _write_output(out_path, rows)
        print(
            f"OK | channel={args.channel} | days={int(args.days)} | scanned={int(scanned)} "
            f"| exported={len(rows)} | out={out_path}"
        )
        return 0
    except FloodWaitError as exc:
        wait_s = int(getattr(exc, "seconds", 0) or 0)
        print(f"Telegram flood wait. Retry after {wait_s}s.")
        return 2
    finally:
        await client.disconnect()


def main() -> int:
    return asyncio.run(_run())


if __name__ == "__main__":
    raise SystemExit(main())

