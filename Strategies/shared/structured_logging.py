"""
Structured Logging and Critical Event Alerting

Provides:
- JSON-format log handler for machine-readable log aggregation
- Critical event alert hook (writes to shared alerts file)
- Can be attached to any existing logger without replacing current handlers
"""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Dict, Optional


class JSONFormatter(logging.Formatter):
    """
    Formats log records as JSON lines for machine parsing.

    Output example:
        {"ts":"2026-02-10T22:15:00Z","level":"WARNING","strategy":"orb_strategy",
         "msg":"Daily loss limit hit","data":{"pnl":-150.0}}
    """

    def __init__(self, strategy_id: str = "unknown"):
        super().__init__()
        self.strategy_id = strategy_id

    def format(self, record: logging.LogRecord) -> str:
        entry: Dict[str, Any] = {
            "ts": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "strategy": self.strategy_id,
            "logger": record.name,
            "msg": record.getMessage(),
        }

        # Include exception info if present
        if record.exc_info and record.exc_info[1]:
            entry["exception"] = self.formatException(record.exc_info)

        # Include extra structured data if attached
        if hasattr(record, "structured_data"):
            entry["data"] = record.structured_data

        return json.dumps(entry, default=str)


class CriticalAlertHandler(logging.Handler):
    """
    Writes CRITICAL and ERROR events to a shared alerts file.

    This provides a simple, file-based alerting mechanism that external
    monitoring tools (scripts, dashboards, Slack bots) can watch.

    Alert file format: one JSON line per alert, newest at bottom.
    External tools can tail -f or poll the file for new entries.
    """

    def __init__(
        self,
        alerts_dir: Optional[Path] = None,
        max_file_size: int = 1 * 1024 * 1024,  # 1MB
        strategy_id: str = "unknown",
    ):
        super().__init__(level=logging.ERROR)
        if alerts_dir is None:
            alerts_dir = Path(__file__).parent.parent.parent / "logs" / "alerts"
        alerts_dir.mkdir(parents=True, exist_ok=True)
        self.alert_file = alerts_dir / "critical_events.jsonl"
        self.max_file_size = max_file_size
        self.strategy_id = strategy_id

    def emit(self, record: logging.LogRecord) -> None:
        try:
            entry = {
                "ts": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
                "level": record.levelname,
                "strategy": self.strategy_id,
                "msg": record.getMessage(),
            }
            if record.exc_info and record.exc_info[1]:
                entry["exception"] = logging.Formatter().formatException(record.exc_info)

            line = json.dumps(entry, default=str) + "\n"

            # Rotate if file is too large
            if self.alert_file.exists() and self.alert_file.stat().st_size > self.max_file_size:
                archive = self.alert_file.with_suffix(".1.jsonl")
                if archive.exists():
                    archive.unlink()
                self.alert_file.rename(archive)

            with open(self.alert_file, "a", encoding="utf-8") as f:
                f.write(line)

        except Exception:
            self.handleError(record)


def attach_structured_logging(
    logger: logging.Logger,
    strategy_id: str,
    json_log_dir: Optional[Path] = None,
    enable_json_file: bool = True,
    enable_critical_alerts: bool = True,
) -> None:
    """
    Attach structured logging handlers to an existing logger.

    Non-invasive: existing handlers (console, plain text file) remain untouched.

    Args:
        logger: The logger to enhance
        strategy_id: Strategy identifier for structured entries
        json_log_dir: Directory for JSON log files
        enable_json_file: Whether to add JSON file handler
        enable_critical_alerts: Whether to add critical alert handler
    """
    if json_log_dir is None:
        json_log_dir = Path(__file__).parent.parent.parent / "logs" / "structured"
    json_log_dir.mkdir(parents=True, exist_ok=True)

    if enable_json_file:
        # Check if JSON handler already attached
        for h in logger.handlers:
            if isinstance(getattr(h, 'formatter', None), JSONFormatter):
                return  # Already attached

        json_file = json_log_dir / f"{strategy_id}.jsonl"
        json_handler = RotatingFileHandler(
            str(json_file),
            maxBytes=5 * 1024 * 1024,
            backupCount=3,
            encoding="utf-8",
        )
        json_handler.setFormatter(JSONFormatter(strategy_id=strategy_id))
        json_handler.setLevel(logging.INFO)
        logger.addHandler(json_handler)

    if enable_critical_alerts:
        # Check if alert handler already attached
        for h in logger.handlers:
            if isinstance(h, CriticalAlertHandler):
                return  # Already attached

        alert_handler = CriticalAlertHandler(strategy_id=strategy_id)
        logger.addHandler(alert_handler)
