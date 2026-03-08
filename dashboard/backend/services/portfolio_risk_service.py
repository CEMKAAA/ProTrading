"""
Portfolio Risk Governor Service

Background watchdog that enforces portfolio-level guardrails on live strategies.
"""

from __future__ import annotations

import threading
import time
import logging
from typing import Optional

logger = logging.getLogger(__name__)


class PortfolioRiskGovernorService:
    def __init__(self):
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._manager = None

    def _loop(self):
        if self._manager is None:
            try:
                from Strategies.strategy_manager import StrategyManager
                self._manager = StrategyManager()
            except Exception as e:
                logger.debug(f"Portfolio governor manager init failed: {e}")
                self._manager = None

        while not self._stop.is_set():
            sleep_s = 15
            try:
                if self._manager is None:
                    from Strategies.strategy_manager import StrategyManager
                    self._manager = StrategyManager()

                report = self._manager.evaluate_portfolio_governor(enforce=True)
                cfg = report.get("config", {})
                sleep_s = int(cfg.get("check_interval_seconds", 15) or 15)
                if report.get("status") == "breached":
                    logger.warning(
                        "Portfolio governor breach: %s | actions=%s",
                        report.get("breaches"),
                        len(report.get("enforced_actions", [])),
                    )
            except Exception as e:
                logger.debug(f"Portfolio governor loop error: {e}")
                sleep_s = 15

            self._stop.wait(max(5, sleep_s))

    def start(self):
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, daemon=True, name="portfolio-risk-governor")
        self._thread.start()
        logger.info("Portfolio risk governor service started")

    def stop(self):
        self._stop.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2)
        self._manager = None
        logger.info("Portfolio risk governor service stopped")
