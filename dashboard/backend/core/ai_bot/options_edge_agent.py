"""
Options-edge AI bot planner.

Phase-1 scope:
- consume persisted options-edge scan + trade candidates
- generate report with pluggable provider (deterministic/local_gptoss/anthropic_claude/openai_compat)
- translate report trade decisions into an executable plan (paper-first)
"""

from __future__ import annotations

import json
import math
import os
from typing import Any, Dict, List, Optional, Sequence, Tuple

import httpx
from sqlalchemy.orm import Session

from ...models.database import (
    OptionsEdgeScanRunModel,
    OptionsEdgeCandidateScoreModel,
    OptionsEdgeTradeCandidateModel,
)
from ..options_edge import OptionsEdgeReporter


def _safe_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return float(default)
        f = float(v)
        if math.isnan(f) or math.isinf(f):
            return float(default)
        return float(f)
    except Exception:
        return float(default)


def _clamp(v: float, lo: float, hi: float) -> float:
    return float(max(lo, min(hi, v)))


def _extract_json_object(text: str) -> Optional[Dict[str, Any]]:
    raw = str(text or "").strip()
    if not raw:
        return None
    try:
        obj = json.loads(raw)
        if isinstance(obj, dict):
            return obj
    except Exception:
        pass
    if "```" in raw:
        for part in raw.split("```"):
            s = part.strip()
            if s.lower().startswith("json"):
                s = s[4:].strip()
            try:
                obj = json.loads(s)
                if isinstance(obj, dict):
                    return obj
            except Exception:
                continue
    lo = raw.find("{")
    hi = raw.rfind("}")
    if lo >= 0 and hi > lo:
        try:
            obj = json.loads(raw[lo : hi + 1])
            if isinstance(obj, dict):
                return obj
        except Exception:
            return None
    return None


class OptionsEdgeAIBotAgent:
    """Provider-agnostic planner for options-edge."""

    def __init__(self, db: Session):
        self.db = db
        self.reporter = OptionsEdgeReporter()

    def build_plan(
        self,
        *,
        scan_id: str,
        provider: str,
        model_label: Optional[str],
        account_balance: float,
        risk_pct: float,
        max_contracts_cap: int,
        dry_run: bool,
        llm_url: Optional[str] = None,
        api_key: Optional[str] = None,
    ) -> Dict[str, Any]:
        scan, candidates, trades, symbol_insights = self._load_context(scan_id)
        provider_norm = str(provider or "deterministic").strip().lower()
        label = (model_label or "").strip() or None

        if provider_norm == "anthropic_claude":
            if llm_url:
                self.reporter.anthropic_url = str(llm_url).strip()
            if api_key:
                self.reporter.anthropic_api_key = str(api_key).strip()

        if provider_norm in {"deterministic", "local_gptoss_http", "anthropic_claude"}:
            report = self.reporter.build_report(
                scan=scan,
                candidates=candidates,
                trades=trades,
                symbol_insights=symbol_insights,
                llm_provider=provider_norm,
                llm_model=label or (
                    "deterministic"
                    if provider_norm == "deterministic"
                    else ("gpt-oss-20b" if provider_norm == "local_gptoss_http" else "claude-3-5-haiku-latest")
                ),
            )
        elif provider_norm == "openai_compat":
            report = self._build_openai_compat_report(
                scan=scan,
                candidates=candidates,
                trades=trades,
                symbol_insights=symbol_insights,
                llm_url=llm_url,
                api_key=api_key,
                model_label=label,
            )
        else:
            raise ValueError(f"Unsupported provider '{provider_norm}'")

        plan_rows, notes = self._report_to_execution_plan(
            report=report,
            trades=trades,
            account_balance=float(account_balance),
            risk_pct=float(risk_pct),
            max_contracts_cap=int(max_contracts_cap),
            dry_run=bool(dry_run),
        )
        report_warnings = report.get("warnings") if isinstance(report.get("warnings"), list) else []
        fallback_used = bool(
            provider_norm == "local_gptoss_http" and not bool(report.get("llm_used"))
        )
        if fallback_used:
            notes.insert(0, "GPT-OSS fallback detected: deterministic report was used for this run.")
        if provider_norm == "anthropic_claude" and not bool(report.get("llm_used")):
            notes.insert(0, "Claude fallback detected: deterministic report was used for this run.")
        for w in report_warnings:
            sw = str(w or "").strip()
            if sw:
                notes.append(f"report_warning: {sw}")
        return {
            "provider": provider_norm,
            "model_label": str(report.get("llm_model") or label or provider_norm),
            "report": report,
            "execution_plan": plan_rows,
            "notes": notes,
            "fallback_used": fallback_used,
        }

    def _load_context(
        self, scan_id: str
    ) -> Tuple[Dict[str, Any], List[Dict[str, Any]], List[Dict[str, Any]], Dict[str, Any]]:
        row = (
            self.db.query(OptionsEdgeScanRunModel)
            .filter(OptionsEdgeScanRunModel.scan_id == scan_id)
            .first()
        )
        if not row:
            raise ValueError("scan_id not found")

        cand_rows = (
            self.db.query(OptionsEdgeCandidateScoreModel)
            .filter(OptionsEdgeCandidateScoreModel.scan_id == scan_id)
            .all()
        )
        trade_rows = (
            self.db.query(OptionsEdgeTradeCandidateModel)
            .filter(OptionsEdgeTradeCandidateModel.scan_id == scan_id)
            .all()
        )
        candidates = []
        for c in cand_rows:
            candidates.append(
                {
                    "symbol": c.symbol,
                    "sector": c.sector,
                    "selected": bool(c.selected),
                    "score_total": _safe_float(c.score_total, 0.0),
                    "score_vol_edge": _safe_float(c.score_vol_edge, 0.0),
                    "score_liquidity": _safe_float(c.score_liquidity, 0.0),
                    "score_event_timing": _safe_float(c.score_event_timing, 0.0),
                    "score_risk": _safe_float(c.score_risk, 0.0),
                    "builder_status": c.builder_status,
                }
            )
        trades = []
        for t in trade_rows:
            qf = t.quality_flags if isinstance(t.quality_flags, list) else []
            legs = t.legs_json if isinstance(t.legs_json, list) else []
            trades.append(
                {
                    "id": int(t.id),
                    "symbol": t.symbol,
                    "structure_type": t.structure_type,
                    "legs_json": legs,
                    "legs_count": max(1, len(legs)),
                    "pop_est": _safe_float(t.pop_est, 0.0),
                    "max_profit": _safe_float(t.max_profit, 0.0),
                    "max_loss": _safe_float(t.max_loss, 0.0),
                    "quality_flags": qf,
                    "max_loss_is_proxy": bool("max_loss_proxy_unbounded" in qf),
                }
            )

        summary = row.summary_json if isinstance(row.summary_json, dict) else {}
        live_data = summary.get("live_data", {}) if isinstance(summary, dict) else {}
        symbol_insights = live_data.get("symbol_insights", {}) if isinstance(live_data, dict) else {}
        scan = {
            "scan_id": row.scan_id,
            "universe_size": int(row.universe_size or 0),
            "top_n": int(row.top_n or 8),
        }
        return scan, candidates, trades, (symbol_insights if isinstance(symbol_insights, dict) else {})

    def _build_openai_compat_report(
        self,
        *,
        scan: Dict[str, Any],
        candidates: Sequence[Dict[str, Any]],
        trades: Sequence[Dict[str, Any]],
        symbol_insights: Dict[str, Any],
        llm_url: Optional[str],
        api_key: Optional[str],
        model_label: Optional[str],
    ) -> Dict[str, Any]:
        base_url = (llm_url or os.getenv("AI_BOT_OPENAI_BASE_URL") or "https://api.openai.com/v1").strip().rstrip("/")
        key = (api_key or os.getenv("AI_BOT_OPENAI_API_KEY") or os.getenv("OPENAI_API_KEY") or "").strip()
        if not key:
            raise ValueError("openai_compat selected but API key is missing")
        model = (model_label or os.getenv("AI_BOT_OPENAI_MODEL") or "gpt-4.1-mini").strip()

        compact_candidates = sorted(
            [c for c in candidates if bool(c.get("selected", True))],
            key=lambda x: _safe_float(x.get("score_total"), 0.0),
            reverse=True,
        )[:20]
        compact_trades = sorted(
            list(trades),
            key=lambda x: (_safe_float(x.get("pop_est"), 0.0), _safe_float(x.get("max_profit"), 0.0)),
            reverse=True,
        )[:20]

        payload = {
            "scan": scan,
            "candidates": compact_candidates,
            "trades": compact_trades,
            "symbol_insights": symbol_insights,
        }
        system = (
            "You are an options trading assistant. "
            "Use only provided numbers. No forecasting language. "
            "Output strict JSON only."
        )
        user = (
            "Return JSON object with keys market_summary, risk_summary, candidate_notes, trade_decisions, warnings.\n"
            "trade_decisions must be array of objects: "
            "{symbol,action,structure,confidence,reasons,scan_evidence}.\n"
            "action must be ENTER|WATCH|SKIP. "
            "scan_evidence should include numeric fields when possible (score_total, pop_est, max_profit, max_loss).\n\n"
            f"Input:\n{json.dumps(payload, ensure_ascii=True)}"
        )
        req = {
            "model": model,
            "temperature": 0.15,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        }
        headers = {
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        }
        with httpx.Client(timeout=90.0) as client:
            resp = client.post(f"{base_url}/chat/completions", json=req, headers=headers)
        if resp.status_code >= 400:
            raise ValueError(f"openai_compat call failed: HTTP {resp.status_code} - {resp.text[:300]}")
        data = resp.json()
        content = str((((data or {}).get("choices") or [{}])[0].get("message") or {}).get("content") or "")
        parsed = _extract_json_object(content)
        if not isinstance(parsed, dict):
            raise ValueError("openai_compat returned non-JSON content")
        return self._normalize_report(parsed, model_label=model)

    @staticmethod
    def _normalize_report(report: Dict[str, Any], model_label: str) -> Dict[str, Any]:
        out = {
            "report_version": "ai_bot_v1",
            "llm_used": True,
            "llm_model": model_label,
            "market_summary": str(report.get("market_summary") or "").strip(),
            "risk_summary": str(report.get("risk_summary") or "").strip(),
            "candidate_notes": [],
            "trade_decisions": [],
            "warnings": [],
        }
        notes = report.get("candidate_notes")
        if isinstance(notes, list):
            for n in notes:
                if isinstance(n, dict):
                    sym = str(n.get("symbol") or "?").strip()
                    text = str(n.get("text") or "").strip()
                    if text:
                        out["candidate_notes"].append({"symbol": sym, "text": text})
        warnings = report.get("warnings")
        if isinstance(warnings, list):
            out["warnings"] = [str(x).strip() for x in warnings if str(x).strip()]
        decisions = report.get("trade_decisions")
        if isinstance(decisions, list):
            for d in decisions:
                if not isinstance(d, dict):
                    continue
                action = str(d.get("action") or "WATCH").upper().strip()
                if action not in {"ENTER", "WATCH", "SKIP"}:
                    action = "WATCH"
                out["trade_decisions"].append(
                    {
                        "symbol": str(d.get("symbol") or "?").strip(),
                        "action": action,
                        "structure": str(d.get("structure") or "none").strip(),
                        "confidence": _clamp(_safe_float(d.get("confidence"), 0.5), 0.0, 1.0),
                        "reasons": [str(x).strip() for x in (d.get("reasons") or []) if str(x).strip()],
                        "scan_evidence": d.get("scan_evidence") if isinstance(d.get("scan_evidence"), dict) else {},
                    }
                )
        return out

    def _report_to_execution_plan(
        self,
        *,
        report: Dict[str, Any],
        trades: Sequence[Dict[str, Any]],
        account_balance: float,
        risk_pct: float,
        max_contracts_cap: int,
        dry_run: bool,
    ) -> Tuple[List[Dict[str, Any]], List[str]]:
        notes: List[str] = []
        if dry_run:
            notes.append("dry_run=true: plan emits paper intents only; no broker orders are sent.")

        by_symbol: Dict[str, Dict[str, Any]] = {}
        for tr in sorted(
            list(trades),
            key=lambda x: (_safe_float(x.get("pop_est"), 0.0), _safe_float(x.get("max_profit"), 0.0)),
            reverse=True,
        ):
            sym = str(tr.get("symbol") or "").upper().strip()
            if sym and sym not in by_symbol:
                by_symbol[sym] = tr

        decisions = report.get("trade_decisions") if isinstance(report.get("trade_decisions"), list) else []
        plan: List[Dict[str, Any]] = []
        for d in decisions:
            if not isinstance(d, dict):
                continue
            sym = str(d.get("symbol") or "").upper().strip()
            action = str(d.get("action") or "WATCH").upper().strip()
            if action not in {"ENTER", "WATCH", "SKIP"}:
                action = "WATCH"
            reasons = [str(x).strip() for x in (d.get("reasons") or []) if str(x).strip()]
            reason = reasons[0] if reasons else "No explicit reason provided."
            conf = _clamp(_safe_float(d.get("confidence"), 0.5), 0.0, 1.0)
            evidence = d.get("scan_evidence") if isinstance(d.get("scan_evidence"), dict) else {}

            tr = by_symbol.get(sym)
            if action == "ENTER" and tr is not None:
                contracts, sz_note = self._calc_contracts(
                    account_balance=account_balance,
                    risk_pct=risk_pct,
                    max_loss=_safe_float(tr.get("max_loss"), 0.0),
                    legs_count=int(tr.get("legs_count") or 2),
                    max_contracts_cap=max_contracts_cap,
                )
                if contracts <= 0:
                    plan_action = "WATCH"
                    reason = f"{reason} | Position size is 0 at current risk budget ({sz_note})."
                else:
                    plan_action = "OPEN_PAPER" if dry_run else "OPEN"
                plan.append(
                    {
                        "symbol": sym,
                        "action": plan_action,
                        "structure_type": str(tr.get("structure_type") or d.get("structure") or "unknown"),
                        "trade_candidate_id": int(tr.get("id")) if tr.get("id") is not None else None,
                        "contracts": int(max(0, contracts)),
                        "confidence": conf,
                        "reason": reason,
                        "evidence": {
                            **evidence,
                            "pop_est": _safe_float(tr.get("pop_est"), 0.0),
                            "max_profit": _safe_float(tr.get("max_profit"), 0.0),
                            "max_loss": _safe_float(tr.get("max_loss"), 0.0),
                            "max_loss_is_proxy": bool(tr.get("max_loss_is_proxy")),
                        },
                    }
                )
            elif action == "ENTER" and tr is None:
                plan.append(
                    {
                        "symbol": sym,
                        "action": "SKIP",
                        "structure_type": str(d.get("structure") or "none"),
                        "trade_candidate_id": None,
                        "contracts": 0,
                        "confidence": conf,
                        "reason": f"{reason} | No persisted trade candidate found for symbol.",
                        "evidence": evidence,
                    }
                )
            else:
                plan.append(
                    {
                        "symbol": sym,
                        "action": action,
                        "structure_type": str((tr or {}).get("structure_type") or d.get("structure") or "none"),
                        "trade_candidate_id": int((tr or {}).get("id")) if (tr or {}).get("id") is not None else None,
                        "contracts": 0,
                        "confidence": conf,
                        "reason": reason,
                        "evidence": evidence,
                    }
                )

        if len(plan) == 0:
            notes.append("No trade_decisions returned by report provider; execution plan is empty.")
        enter_count = sum(1 for x in plan if str(x.get("action")).upper().startswith("OPEN"))
        notes.append(f"Planned actions: {len(plan)} total, {enter_count} open intents.")
        return plan, notes

    @staticmethod
    def _calc_contracts(
        *,
        account_balance: float,
        risk_pct: float,
        max_loss: float,
        legs_count: int,
        max_contracts_cap: int,
    ) -> Tuple[int, str]:
        if account_balance <= 0 or risk_pct <= 0 or max_loss <= 0:
            return 0, "invalid_inputs"
        risk_budget = account_balance * (risk_pct / 100.0)
        # Keep in sync with options-edge sizing endpoint assumptions.
        commission_per_leg = 0.65
        risk_per_contract = max_loss + (commission_per_leg * max(1, int(legs_count)) * 2.0)
        qty = int(min(max_contracts_cap, math.floor(risk_budget / max(risk_per_contract, 1e-9))))
        if qty <= 0:
            return 0, f"risk_budget=${risk_budget:.2f} < risk_per_contract=${risk_per_contract:.2f}"
        return qty, f"risk_budget=${risk_budget:.2f}, risk_per_contract=${risk_per_contract:.2f}"
