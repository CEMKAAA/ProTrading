"""
Options-edge reporter with pluggable LLM provider.

Current providers:
- deterministic (default, no external call)
- local_gptoss_http (calls local sidecar server)
- anthropic_claude (calls Anthropic Messages API)
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict, List, Sequence

import httpx
from httpx import ReadTimeout


def _safe_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return float(default)
        return float(v)
    except Exception:
        return float(default)


class OptionsEdgeReporter:
    """Build report payload from scan snapshots/candidates/trades."""

    def __init__(self):
        self.default_provider = self._resolve_setting("OPTIONS_EDGE_LLM_PROVIDER", "deterministic").lower().strip()
        self.default_url = self._resolve_setting("OPTIONS_EDGE_LLM_URL", "http://127.0.0.1:8012").strip()
        self.anthropic_url = self._resolve_setting("OPTIONS_EDGE_ANTHROPIC_URL", "https://api.anthropic.com/v1/messages").strip()
        self.anthropic_model = self._resolve_setting("OPTIONS_EDGE_ANTHROPIC_MODEL", "claude-3-5-haiku-latest").strip()
        self.anthropic_api_key = (
            self._resolve_setting("OPTIONS_EDGE_ANTHROPIC_API_KEY", "")
            or self._resolve_setting("ANTHROPIC_API_KEY", "")
        ).strip()
        # Keep a floor of 120s for local 20B inference even if env is set too low.
        # GPT-OSS 20B at ~2.3 tok/s needs ~350s for 800 tokens. Default 400s.
        cfg_timeout = _safe_float(self._resolve_setting("OPTIONS_EDGE_LLM_TIMEOUT_SEC", 400.0), 400.0)
        self.default_timeout_sec = max(120.0, cfg_timeout)
        # Token budgets: 800 is enough for 5-8 symbol JSON output (~400-600 tokens).
        # WARNING: Higher values = proportionally longer inference on local models.
        # GPT-OSS 20B Q4_K_M at 15 GPU layers: ~2.3 tok/s → 800 tokens ≈ 6 min.
        cfg_max_tokens = int(_safe_float(self._resolve_setting("OPTIONS_EDGE_LLM_MAX_TOKENS", 800.0), 800.0))
        self.default_max_tokens = max(400, min(cfg_max_tokens, 1024))
        cfg_retry_tokens = int(
            _safe_float(self._resolve_setting("OPTIONS_EDGE_LLM_RETRY_MAX_TOKENS", 600.0), 600.0)
        )
        self.retry_max_tokens = max(400, min(cfg_retry_tokens, 800))

    @staticmethod
    def _resolve_setting(name: str, default: Any = None) -> Any:
        env_val = os.getenv(name)
        if env_val is not None and str(env_val).strip() != "":
            return env_val
        # Fallback to dashboard/.env and repo .env to match connector behavior.
        repo_root = Path(__file__).resolve().parents[4]
        for p in [repo_root / "dashboard" / ".env", repo_root / ".env"]:
            if not p.exists():
                continue
            try:
                for raw in p.read_text(encoding="utf-8").splitlines():
                    line = raw.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    if k.strip() != name:
                        continue
                    val = v.strip().strip('"').strip("'")
                    if val != "":
                        return val
            except Exception:
                continue
        return default

    @staticmethod
    def _norm_candidate_notes(v: Any) -> List[Dict[str, Any]]:
        if not isinstance(v, list):
            return []
        out: List[Dict[str, Any]] = []
        for row in v:
            if isinstance(row, dict):
                out.append(
                    {
                        "symbol": str(row.get("symbol") or "?"),
                        "text": str(row.get("text") or "").strip(),
                    }
                )
            elif isinstance(row, str):
                out.append({"symbol": "?", "text": row.strip()})
        return [x for x in out if x["text"]]

    @staticmethod
    def _norm_warnings(v: Any) -> List[str]:
        if not isinstance(v, list):
            return []
        out: List[str] = []
        for row in v:
            txt = str(row or "").strip()
            if txt:
                out.append(txt)
        return out

    @staticmethod
    def _norm_trade_decisions(v: Any) -> List[Dict[str, Any]]:
        if not isinstance(v, list):
            return []
        out: List[Dict[str, Any]] = []
        for row in v:
            if not isinstance(row, dict):
                continue
            out.append(
                {
                    "symbol": str(row.get("symbol") or "?"),
                    "action": str(row.get("action") or "WATCH").upper(),
                    "structure": str(row.get("structure") or "none"),
                    "confidence": _safe_float(row.get("confidence"), 0.5),
                    "reasons": [str(x) for x in (row.get("reasons") or []) if str(x).strip()],
                    "scan_evidence": row.get("scan_evidence") if isinstance(row.get("scan_evidence"), dict) else {},
                }
            )
        return out

    @staticmethod
    def _best_trade_for_symbol(sym: str, trades: Sequence[Dict[str, Any]]) -> Dict[str, Any] | None:
        rows = [t for t in trades if str(t.get("symbol") or "") == sym]
        if not rows:
            return None
        # Prefer bounded structures first, then higher POP.
        def _key(t: Dict[str, Any]):
            proxy = bool(t.get("max_loss_is_proxy")) or ("max_loss_proxy_unbounded" in (t.get("quality_flags") or []))
            return (0 if proxy else 1, _safe_float(t.get("pop_est"), 0.0))
        return sorted(rows, key=_key, reverse=True)[0]

    @staticmethod
    def _find_json_end(text: str, start: int) -> int:
        """Walk forward from '{' tracking brace depth + string state.

        Returns the index of the matching '}' or -1 if truncated.
        """
        depth = 0
        in_str = False
        esc = False
        for i in range(start, len(text)):
            c = text[i]
            if esc:
                esc = False
                continue
            if c == '\\' and in_str:
                esc = True
                continue
            if c == '"':
                in_str = not in_str
                continue
            if in_str:
                continue
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return i
        return -1

    @staticmethod
    def _extract_json_object(text: str) -> Dict[str, Any] | None:
        t = str(text or "").strip()
        if not t:
            return None
        # Direct JSON first.
        try:
            obj = json.loads(t)
            if isinstance(obj, dict):
                return obj
        except Exception:
            pass
        # Try fenced code block.
        if "```" in t:
            parts = t.split("```")
            for part in parts:
                s = part.strip()
                if s.lower().startswith("json"):
                    s = s[4:].strip()
                try:
                    obj = json.loads(s)
                    if isinstance(obj, dict):
                        return obj
                except Exception:
                    continue
        # Brace-depth extraction: isolate outermost { ... } respecting strings.
        lo = t.find("{")
        if lo >= 0:
            hi = OptionsEdgeReporter._find_json_end(t, lo)
            if hi > lo:
                try:
                    obj = json.loads(t[lo : hi + 1])
                    if isinstance(obj, dict):
                        return obj
                except Exception:
                    pass
        return None

    def _build_deterministic(
        self,
        scan: Dict[str, Any],
        candidates: Sequence[Dict[str, Any]],
        trades: Sequence[Dict[str, Any]],
        symbol_insights: Dict[str, Any] | None = None,
        llm_model: str | None = None,
    ) -> Dict[str, Any]:
        """Existing deterministic report generator."""
        symbol_insights = symbol_insights or {}
        selected = [c for c in candidates if bool(c.get("selected", True))]
        top = sorted(selected, key=lambda x: _safe_float(x.get("score_total"), 0.0), reverse=True)

        sector_counts: Dict[str, int] = {}
        for c in selected:
            sector = str(c.get("sector") or "UNKNOWN")
            sector_counts[sector] = sector_counts.get(sector, 0) + 1
        total_selected = max(1, len(selected))
        top_sector = max(sector_counts.items(), key=lambda kv: kv[1])[0] if sector_counts else "UNKNOWN"
        top_sector_frac = (sector_counts.get(top_sector, 0) / total_selected) if sector_counts else 0.0

        mean_score = sum(_safe_float(c.get("score_total"), 0.0) for c in selected) / total_selected
        built_trades = len(trades)
        trade_pop_mean = (
            sum(_safe_float(t.get("pop_est"), 0.0) for t in trades) / max(1, len(trades))
            if trades else 0.0
        )

        warnings: List[str] = []
        if top_sector_frac > 0.50:
            warnings.append(
                f"Sector concentration risk: {top_sector} is {top_sector_frac * 100:.1f}% of selected candidates."
            )
        if built_trades == 0:
            warnings.append("No trade structures were built from selected symbols.")
        proxy_risk_count = sum(
            1
            for t in trades
            if bool(t.get("max_loss_is_proxy"))
            or ("max_loss_proxy_unbounded" in (t.get("quality_flags") or []))
        )
        if proxy_risk_count > 0:
            warnings.append(
                f"{proxy_risk_count} trade(s) use proxy max loss for unbounded risk structures (short strangle/straddle)."
            )
        if len(selected) < min(8, int(scan.get("top_n", 8) or 8)):
            warnings.append(
                f"Selection shortfall: only {len(selected)} symbols passed allocation for top_n={scan.get('top_n', 8)}."
            )

        market_summary = (
            f"Selected {len(selected)} of {int(scan.get('universe_size', 0))} symbols; "
            f"mean score {mean_score:.1f}/100; {built_trades} trade structures built."
        )
        risk_summary = (
            f"Top sector {top_sector} at {top_sector_frac * 100:.1f}% allocation; "
            f"mean POP across built trades {trade_pop_mean * 100:.1f}%."
        )

        candidate_notes: List[Dict[str, Any]] = []
        trade_decisions: List[Dict[str, Any]] = []
        for c in top[:8]:
            sym = str(c.get("symbol") or "?")
            best_trade = self._best_trade_for_symbol(sym, trades)
            note = (
                f"{sym}: score={_safe_float(c.get('score_total'), 0.0):.1f}, "
                f"vol={_safe_float(c.get('score_vol_edge'), 0.0):.2f}, "
                f"liq={_safe_float(c.get('score_liquidity'), 0.0):.2f}"
            )
            if best_trade:
                proxy_tag = ""
                if bool(best_trade.get("max_loss_is_proxy")) or (
                    "max_loss_proxy_unbounded" in (best_trade.get("quality_flags") or [])
                ):
                    proxy_tag = " [max_loss proxy]"
                note += (
                    f", best={best_trade.get('structure_type')}, "
                    f"pop={_safe_float(best_trade.get('pop_est'), 0.0) * 100:.1f}%, "
                    f"max_profit=${_safe_float(best_trade.get('max_profit'), 0.0):.2f}, "
                    f"max_loss=${_safe_float(best_trade.get('max_loss'), 0.0):.2f}{proxy_tag}"
                )

            insight = symbol_insights.get(sym, {}) if isinstance(symbol_insights, dict) else {}
            news_count = len(insight.get("news", [])) if isinstance(insight, dict) else 0
            if news_count > 0:
                note += f", news_items={news_count}"
            candidate_notes.append({"symbol": sym, "text": note})

            # Deterministic decision layer for new users: explicit action + scan evidence.
            score_total = _safe_float(c.get("score_total"), 0.0)
            score_vol = _safe_float(c.get("score_vol_edge"), 0.0)
            score_liq = _safe_float(c.get("score_liquidity"), 0.0)
            if best_trade is None:
                trade_decisions.append(
                    {
                        "symbol": sym,
                        "action": "SKIP",
                        "structure": "none",
                        "confidence": 0.25,
                        "reasons": ["No valid structure built for this symbol."],
                        "scan_evidence": {
                            "score_total": score_total,
                            "score_vol_edge": score_vol,
                            "score_liquidity": score_liq,
                        },
                    }
                )
                continue

            pop = _safe_float(best_trade.get("pop_est"), 0.0)
            structure = str(best_trade.get("structure_type") or "none")
            proxy = bool(best_trade.get("max_loss_is_proxy")) or ("max_loss_proxy_unbounded" in (best_trade.get("quality_flags") or []))
            max_profit = _safe_float(best_trade.get("max_profit"), 0.0)
            max_loss = _safe_float(best_trade.get("max_loss"), 0.0)
            rr = (max_profit / max(max_loss, 1e-9)) if max_loss > 0 else 0.0
            reasons: List[str] = []

            if proxy:
                action = "WATCH"
                confidence = 0.45
                reasons.append("Unbounded-risk structure detected; proxy max loss is less reliable for live execution.")
            elif score_total >= 72 and pop >= 0.70 and rr >= 0.18:
                action = "ENTER"
                confidence = 0.78
                reasons.append("High combined scan score and POP with bounded risk structure.")
            elif score_total >= 67 and pop >= 0.64:
                action = "WATCH"
                confidence = 0.60
                reasons.append("Setup is viable but below strict entry threshold; monitor for better pricing.")
            else:
                action = "SKIP"
                confidence = 0.55
                reasons.append("Insufficient edge versus thresholds (score/POP/reward-risk).")

            reasons.append(f"Trigger metrics: score={score_total:.1f}, POP={pop*100:.1f}%, maxP=${max_profit:.2f}, maxL=${max_loss:.2f}.")
            trade_decisions.append(
                {
                    "symbol": sym,
                    "action": action,
                    "structure": structure,
                    "confidence": confidence,
                    "reasons": reasons,
                    "scan_evidence": {
                        "score_total": score_total,
                        "score_vol_edge": score_vol,
                        "score_liquidity": score_liq,
                        "score_event_timing": _safe_float(c.get("score_event_timing"), 0.0),
                        "score_risk": _safe_float(c.get("score_risk"), 0.0),
                        "pop_est": pop,
                        "max_profit": max_profit,
                        "max_loss": max_loss,
                        "max_loss_is_proxy": proxy,
                    },
                }
            )

        return {
            "report_version": "deterministic_v1",
            "llm_used": False,
            "llm_model": llm_model or "deterministic",
            "market_summary": market_summary,
            "risk_summary": risk_summary,
            "candidate_notes": candidate_notes,
            "trade_decisions": trade_decisions,
            "warnings": warnings,
        }

    def _build_local_gptoss(
        self,
        *,
        scan: Dict[str, Any],
        candidates: Sequence[Dict[str, Any]],
        trades: Sequence[Dict[str, Any]],
        symbol_insights: Dict[str, Any],
        llm_model: str | None,
        llm_url: str,
        timeout_sec: float,
    ) -> Dict[str, Any]:
        # Keep payload compact to reduce latency/timeouts on local 20B inference.
        compact_candidates = sorted(
            list(candidates),
            key=lambda x: _safe_float(x.get("score_total"), 0.0),
            reverse=True,
        )[:8]
        compact_trades = sorted(
            list(trades),
            key=lambda x: _safe_float(x.get("pop_est"), 0.0),
            reverse=True,
        )[:14]
        payload = {
            "task": "options_edge_report",
            "input": {
                "scan": scan,
                "candidates": compact_candidates,
                "trades": compact_trades,
                "symbol_insights": symbol_insights,
            },
            "max_tokens": int(self.default_max_tokens),
            "temperature": 0.2,
        }
        url = f"{llm_url.rstrip('/')}/generate"
        budget_sec = max(120.0, float(timeout_sec))
        # Give the first attempt the FULL budget. Local 20B inference at ~2.3 tok/s
        # needs ~350s for 800 tokens. Splitting the budget into first/retry both
        # fail because neither slice is long enough for a complete inference run.
        try:
            with httpx.Client(timeout=budget_sec) as client:
                res = client.post(url, json=payload)
                if res.status_code >= 300:
                    raise RuntimeError(f"local_gptoss_http status={res.status_code}")
                body = res.json()
        except ReadTimeout:
            raise  # Don't retry on timeout - inference is genuinely slow, retrying wastes time
        if not isinstance(body, dict):
            raise RuntimeError("local_gptoss_http invalid JSON body")
        result_obj = body.get("result")
        if not isinstance(result_obj, dict):
            # Some sidecars may return raw text.
            parsed = self._extract_json_object(str(body.get("text") or body.get("raw_text") or ""))
            if not isinstance(parsed, dict):
                raise RuntimeError("local_gptoss_http missing result object")
            result_obj = parsed

        market_summary = str(result_obj.get("market_summary") or "").strip()
        risk_summary = str(result_obj.get("risk_summary") or "").strip()
        candidate_notes = self._norm_candidate_notes(result_obj.get("candidate_notes"))
        trade_decisions = self._norm_trade_decisions(result_obj.get("trade_decisions"))
        warnings = self._norm_warnings(result_obj.get("warnings"))
        if not market_summary or not risk_summary:
            raise RuntimeError("local_gptoss_http incomplete report payload")
        return {
            "report_version": "local_gptoss_http_v1",
            "llm_used": True,
            "llm_model": str(body.get("model") or llm_model or "gpt-oss-20b"),
            "market_summary": market_summary,
            "risk_summary": risk_summary,
            "candidate_notes": candidate_notes,
            "trade_decisions": trade_decisions,
            "warnings": warnings,
        }

    def _build_anthropic_claude(
        self,
        *,
        scan: Dict[str, Any],
        candidates: Sequence[Dict[str, Any]],
        trades: Sequence[Dict[str, Any]],
        symbol_insights: Dict[str, Any],
        llm_model: str | None,
        timeout_sec: float,
    ) -> Dict[str, Any]:
        api_key = str(self.anthropic_api_key or "").strip()
        if not api_key:
            raise RuntimeError("anthropic_claude missing API key (set OPTIONS_EDGE_ANTHROPIC_API_KEY)")

        model = str(llm_model or self.anthropic_model or "claude-3-5-haiku-latest").strip()
        compact_candidates = sorted(
            list(candidates),
            key=lambda x: _safe_float(x.get("score_total"), 0.0),
            reverse=True,
        )[:10]
        compact_trades = sorted(
            list(trades),
            key=lambda x: _safe_float(x.get("pop_est"), 0.0),
            reverse=True,
        )[:16]
        payload = {
            "scan": scan,
            "candidates": compact_candidates,
            "trades": compact_trades,
            "symbol_insights": symbol_insights,
        }
        system = (
            "You are an options trading assistant. "
            "Use only provided numbers. No price prediction language. "
            "Return strict JSON only."
        )
        user = (
            "Return a JSON object with keys: market_summary, risk_summary, candidate_notes, trade_decisions, warnings.\n"
            "candidate_notes: array of {symbol,text}.\n"
            "trade_decisions: array of {symbol,action,structure,confidence,reasons,scan_evidence}.\n"
            "action must be ENTER, WATCH, or SKIP.\n"
            "scan_evidence should include numeric metrics (score_total, pop_est, max_profit, max_loss) when available.\n\n"
            f"Input:\n{json.dumps(payload, ensure_ascii=True)}"
        )
        req = {
            "model": model,
            "max_tokens": int(max(500, min(self.default_max_tokens, 2048))),
            "temperature": 0.15,
            "system": system,
            "messages": [{"role": "user", "content": user}],
        }
        headers = {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }
        with httpx.Client(timeout=max(60.0, float(timeout_sec))) as client:
            res = client.post(self.anthropic_url, json=req, headers=headers)
        if res.status_code >= 300:
            raise RuntimeError(f"anthropic_claude status={res.status_code} body={res.text[:200]}")
        body = res.json()
        content_rows = body.get("content") if isinstance(body, dict) else None
        text = ""
        if isinstance(content_rows, list):
            for row in content_rows:
                if isinstance(row, dict) and str(row.get("type") or "").lower() == "text":
                    text += str(row.get("text") or "")
        parsed = self._extract_json_object(text)
        if not isinstance(parsed, dict):
            raise RuntimeError("anthropic_claude returned non-JSON content")

        market_summary = str(parsed.get("market_summary") or "").strip()
        risk_summary = str(parsed.get("risk_summary") or "").strip()
        candidate_notes = self._norm_candidate_notes(parsed.get("candidate_notes"))
        trade_decisions = self._norm_trade_decisions(parsed.get("trade_decisions"))
        warnings = self._norm_warnings(parsed.get("warnings"))
        if not market_summary or not risk_summary:
            raise RuntimeError("anthropic_claude incomplete report payload")
        return {
            "report_version": "anthropic_claude_v1",
            "llm_used": True,
            "llm_model": model,
            "market_summary": market_summary,
            "risk_summary": risk_summary,
            "candidate_notes": candidate_notes,
            "trade_decisions": trade_decisions,
            "warnings": warnings,
        }

    def build_report(
        self,
        scan: Dict[str, Any],
        candidates: Sequence[Dict[str, Any]],
        trades: Sequence[Dict[str, Any]],
        symbol_insights: Dict[str, Any] | None = None,
        llm_model: str | None = None,
        llm_provider: str | None = None,
    ) -> Dict[str, Any]:
        symbol_insights = symbol_insights or {}
        provider = str(llm_provider or self.default_provider or "deterministic").lower().strip()
        out = self._build_deterministic(
            scan=scan,
            candidates=candidates,
            trades=trades,
            symbol_insights=symbol_insights,
            llm_model=(llm_model or "deterministic"),
        )
        if provider == "deterministic":
            return out
        if provider == "local_gptoss_http":
            try:
                llm_out = self._build_local_gptoss(
                    scan=scan,
                    candidates=candidates,
                    trades=trades,
                    symbol_insights=symbol_insights,
                    llm_model=llm_model,
                    llm_url=self.default_url,
                    timeout_sec=self.default_timeout_sec,
                )
                return llm_out
            except Exception as e:
                err_type = type(e).__name__
                err_msg = str(e)[:200]
                warnings = list(out.get("warnings") or [])
                warnings.append(
                    f"GPT-OSS FAILED - fallback to deterministic. "
                    f"Error: {err_type}: {err_msg}"
                )
                out["warnings"] = warnings
                out["report_version"] = "deterministic_v1_fallback"
                out["llm_used"] = False
                attempted = (llm_model or "gpt-oss-20b").strip()
                out["llm_model"] = f"FALLBACK_deterministic (attempted: {attempted})"
                return out
        if provider == "anthropic_claude":
            try:
                llm_out = self._build_anthropic_claude(
                    scan=scan,
                    candidates=candidates,
                    trades=trades,
                    symbol_insights=symbol_insights,
                    llm_model=llm_model,
                    timeout_sec=self.default_timeout_sec,
                )
                return llm_out
            except Exception as e:
                err_type = type(e).__name__
                err_msg = str(e)[:200]
                warnings = list(out.get("warnings") or [])
                warnings.append(
                    f"Claude FAILED - fallback to deterministic. "
                    f"Error: {err_type}: {err_msg}"
                )
                out["warnings"] = warnings
                out["report_version"] = "deterministic_v1_fallback"
                out["llm_used"] = False
                attempted = (llm_model or self.anthropic_model or "claude").strip()
                out["llm_model"] = f"FALLBACK_deterministic (attempted: {attempted})"
                return out
        warnings = list(out.get("warnings") or [])
        warnings.append(f"Unknown llm provider '{provider}', used deterministic fallback.")
        out["warnings"] = warnings
        return out
