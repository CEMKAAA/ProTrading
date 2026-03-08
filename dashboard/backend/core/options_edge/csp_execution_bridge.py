"""Execution bridge scaffolding for CSP strategy.

This module deliberately avoids placing live orders in current phase.
It prepares normalized order intents that can later be connected to
NautilusTrader + IB execution adapters.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional


@dataclass
class CSPOrderIntent:
    symbol: str
    side: str
    option_type: str
    strike: Optional[float]
    expiry_date: Optional[str]
    quantity: int
    limit_price: Optional[float]
    cash_secured_required: Optional[float]
    source_event: str
    source_date: Optional[str]
    metadata: Dict[str, Any]


class CSPExecutionBridge:
    """
    Broker-agnostic execution scaffold.
    `provider=nautilus_ib` is a placeholder until live adapter wiring is added.
    """

    def __init__(self, provider: str = "nautilus_ib"):
        self.provider = str(provider or "nautilus_ib").strip().lower()

    def preview_intents_from_trade_log(self, trade_log: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        for ev in trade_log or []:
            if not isinstance(ev, dict):
                continue
            event = str(ev.get("event") or "").strip().lower()
            if event not in {"open", "roll"}:
                continue
            symbol = str(ev.get("symbol") or "").upper().strip()
            if not symbol:
                continue
            strike = ev.get("new_strike") if event == "roll" else ev.get("strike")
            premium_total = ev.get("net_credit") if event == "roll" else ev.get("premium_total")
            limit_price = None
            if premium_total is not None:
                try:
                    limit_price = float(premium_total) / 100.0
                except Exception:
                    limit_price = None

            intent = CSPOrderIntent(
                symbol=symbol,
                side="SELL_TO_OPEN",
                option_type="P",
                strike=float(strike) if strike is not None else None,
                expiry_date=str(ev.get("new_expiry") or ev.get("expiry_date") or ""),
                quantity=1,
                limit_price=limit_price,
                cash_secured_required=(float(strike) * 100.0) if strike is not None else None,
                source_event=event,
                source_date=str(ev.get("date") or ""),
                metadata={"raw_event": ev},
            )
            out.append(
                {
                    "symbol": intent.symbol,
                    "side": intent.side,
                    "option_type": intent.option_type,
                    "strike": intent.strike,
                    "expiry_date": intent.expiry_date,
                    "quantity": intent.quantity,
                    "limit_price": intent.limit_price,
                    "cash_secured_required": intent.cash_secured_required,
                    "source_event": intent.source_event,
                    "source_date": intent.source_date,
                    "metadata": intent.metadata,
                }
            )
        return out

    def dispatch(self, intents: List[Dict[str, Any]], dry_run: bool = True) -> Dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat()
        results: List[Dict[str, Any]] = []
        for idx, intent in enumerate(intents or [], start=1):
            symbol = str((intent or {}).get("symbol") or "").upper().strip()
            status = "SIMULATED" if dry_run else "NOT_IMPLEMENTED"
            message = (
                "Dry-run preview only."
                if dry_run
                else "Live CSP execution adapter is not wired yet. Connect NautilusTrader + IB in execution phase."
            )
            results.append(
                {
                    "id": idx,
                    "symbol": symbol,
                    "status": status,
                    "provider": self.provider,
                    "timestamp": now,
                    "message": message,
                    "intent": intent,
                }
            )
        return {
            "ok": True,
            "provider": self.provider,
            "dry_run": bool(dry_run),
            "results": results,
            "submitted": len(results),
        }

