"""LLM trading consultant for Workbench chat-style guidance."""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

import httpx


class WorkbenchConsultant:
    """Free-form chat consultant for Workbench sessions."""

    def __init__(self, anthropic_version: str = "2023-06-01") -> None:
        self.anthropic_version = str(anthropic_version or "2023-06-01")

    @staticmethod
    def _trim_history(history: Any, max_messages: int = 20) -> List[Dict[str, str]]:
        out: List[Dict[str, str]] = []
        if not isinstance(history, list):
            return out
        for row in history:
            if not isinstance(row, dict):
                continue
            role = str(row.get("role") or "").strip().lower()
            if role not in {"user", "assistant"}:
                continue
            content = str(row.get("content") or "").strip()
            if not content:
                continue
            out.append({"role": role, "content": content})
        if len(out) > int(max_messages):
            return out[-int(max_messages) :]
        return out

    @staticmethod
    def _default_model(provider: str) -> str:
        p = str(provider or "").strip().lower()
        if p == "local_gptoss_http":
            return "gpt-oss-20b"
        if p == "openai_compat":
            return "gpt-4.1-mini"
        if p == "claude":
            return "claude-3-5-sonnet-latest"
        return "deterministic"

    @staticmethod
    def _default_url(provider: str) -> str:
        p = str(provider or "").strip().lower()
        if p == "local_gptoss_http":
            return "http://127.0.0.1:8012"
        if p == "openai_compat":
            return "https://api.openai.com/v1"
        if p == "claude":
            return "https://api.anthropic.com"
        return ""

    @staticmethod
    def _safe_context(context: Any) -> Dict[str, Any]:
        if isinstance(context, dict):
            return context
        return {}

    @staticmethod
    def _deterministic_reply(message: str, context: Dict[str, Any]) -> str:
        symbol = str(context.get("symbol") or context.get("session", {}).get("symbol") or "N/A")
        timeframe = str(context.get("timeframe") or context.get("session", {}).get("timeframe") or "N/A")
        tool_state = context.get("tool_state") if isinstance(context.get("tool_state"), dict) else {}
        active_tools = tool_state.get("active_tools") if isinstance(tool_state.get("active_tools"), list) else []
        indicators = context.get("indicators") if isinstance(context.get("indicators"), dict) else {}
        indicator_flags = indicators.get("enabled") if isinstance(indicators.get("enabled"), dict) else {}
        enabled_inds = [k for k, v in indicator_flags.items() if bool(v)]
        recent_bars = context.get("recent_bars") if isinstance(context.get("recent_bars"), list) else []
        last_close = None
        if recent_bars:
            tail = recent_bars[-1]
            if isinstance(tail, dict):
                try:
                    last_close = float(tail.get("close"))
                except Exception:
                    last_close = None

        bullets: List[str] = [
            f"Context loaded for {symbol} {timeframe}.",
            f"Active tools: {', '.join(active_tools) if active_tools else 'none'}.",
            f"Visible indicators: {', '.join(enabled_inds) if enabled_inds else 'none'}.",
        ]
        if last_close is not None:
            bullets.append(f"Latest close in your chart payload: {last_close:.5f}.")
        bullets.append(
            "I can help break your question into: setup checklist, risk plan, and invalidation signals."
        )
        bullets.append(f"Your request: {message[:300]}")
        return "\n".join([f"- {b}" for b in bullets])

    def _system_prompt(self, context: Dict[str, Any]) -> str:
        ctx_json = json.dumps(context, ensure_ascii=True)
        return (
            "You are an execution-focused trading consultant for a chart workbench.\n"
            "Use ONLY the provided context and user message. Do not fabricate prices, indicators, or tool outputs.\n"
            "No guaranteed outcomes, no certainty language, and no personalized investment advice.\n"
            "Keep answers practical, concise, and explain risk/invalidation clearly.\n"
            "When context is missing, state what is missing.\n\n"
            f"Workbench context JSON:\n{ctx_json}"
        )

    def _chat_local_gptoss(
        self,
        message: str,
        context: Dict[str, Any],
        history: List[Dict[str, str]],
        model_label: str,
        llm_url: str,
        timeout_sec: int,
    ) -> str:
        url = f"{str(llm_url).rstrip('/')}/chat"
        history_text = "\n".join(
            [f"{h['role'].upper()}: {h['content']}" for h in history]
        )
        payload_msg = (
            f"MODEL={model_label}\n"
            f"HISTORY:\n{history_text or '(empty)'}\n\n"
            f"USER:\n{message}"
        )
        with httpx.Client(timeout=float(timeout_sec)) as client:
            resp = client.post(
                url,
                json={
                    "system": self._system_prompt(context),
                    "message": payload_msg,
                    "temperature": 0.4,
                    "max_tokens": 2048,
                },
            )
        if resp.status_code != 200:
            raise ValueError(f"local_gptoss_http failed: HTTP {resp.status_code}")
        body = (
            resp.json()
            if resp.headers.get("content-type", "").startswith("application/json")
            else {}
        )
        if isinstance(body, dict) and str(body.get("reply") or "").strip():
            return str(body.get("reply")).strip()
        return str(resp.text or "").strip()

    def _chat_openai_compat(
        self,
        message: str,
        context: Dict[str, Any],
        history: List[Dict[str, str]],
        model_label: str,
        llm_url: str,
        api_key: Optional[str],
        timeout_sec: int,
    ) -> str:
        key = str(api_key or os.getenv("OPENAI_API_KEY") or "").strip()
        if not key:
            raise ValueError("openai_compat selected but API key is missing")
        base = str(llm_url).strip().rstrip("/")
        url = f"{base}/chat/completions"
        messages: List[Dict[str, str]] = [{"role": "system", "content": self._system_prompt(context)}]
        messages.extend(history)
        messages.append({"role": "user", "content": message})
        with httpx.Client(timeout=float(timeout_sec)) as client:
            resp = client.post(
                url,
                headers={
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": model_label,
                    "temperature": 0.4,
                    "max_tokens": 2048,
                    "messages": messages,
                },
            )
        if resp.status_code != 200:
            raise ValueError(f"openai_compat failed: HTTP {resp.status_code}")
        body = (
            resp.json()
            if resp.headers.get("content-type", "").startswith("application/json")
            else {}
        )
        return str((((body.get("choices") or [{}])[0].get("message") or {}).get("content") or "")).strip()

    def _chat_claude(
        self,
        message: str,
        context: Dict[str, Any],
        history: List[Dict[str, str]],
        model_label: str,
        llm_url: str,
        api_key: Optional[str],
        timeout_sec: int,
    ) -> str:
        key = str(
            api_key
            or os.getenv("ANTHROPIC_API_KEY")
            or os.getenv("CLAUDE_API_KEY")
            or ""
        ).strip()
        if not key:
            raise ValueError("claude selected but API key is missing")
        base = str(llm_url).strip().rstrip("/")
        if base.endswith("/v1/messages"):
            url = base
        else:
            url = f"{base}/v1/messages"
        messages = history + [{"role": "user", "content": message}]
        with httpx.Client(timeout=float(timeout_sec)) as client:
            resp = client.post(
                url,
                headers={
                    "x-api-key": key,
                    "anthropic-version": self.anthropic_version,
                    "Content-Type": "application/json",
                },
                json={
                    "model": model_label,
                    "max_tokens": 2048,
                    "temperature": 0.4,
                    "system": self._system_prompt(context),
                    "messages": messages,
                },
            )
        if resp.status_code != 200:
            raise ValueError(f"claude failed: HTTP {resp.status_code}")
        body = (
            resp.json()
            if resp.headers.get("content-type", "").startswith("application/json")
            else {}
        )
        content_items = body.get("content") if isinstance(body, dict) else []
        texts: List[str] = []
        if isinstance(content_items, list):
            for item in content_items:
                if not isinstance(item, dict):
                    continue
                if str(item.get("type") or "") == "text":
                    texts.append(str(item.get("text") or ""))
        return "\n".join([t for t in texts if str(t).strip()]).strip()

    def chat(
        self,
        message: str,
        context: Optional[Dict[str, Any]] = None,
        conversation_history: Optional[List[Dict[str, str]]] = None,
        provider: str = "local_gptoss_http",
        model_label: Optional[str] = None,
        llm_url: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout_sec: Optional[int] = None,
    ) -> Dict[str, Any]:
        msg = str(message or "").strip()
        if not msg:
            return {"ok": False, "error": "Message is empty", "provider": str(provider or "")}

        p = str(provider or "local_gptoss_http").strip().lower()
        model = str(model_label or "").strip() or self._default_model(p)
        url = str(llm_url or "").strip() or self._default_url(p)
        timeout = int(timeout_sec or 90)
        timeout = max(10, min(600, timeout))
        safe_context = self._safe_context(context)
        history = self._trim_history(conversation_history or [], max_messages=20)

        try:
            if p == "deterministic":
                reply = self._deterministic_reply(msg, safe_context)
            elif p == "local_gptoss_http":
                reply = self._chat_local_gptoss(
                    message=msg,
                    context=safe_context,
                    history=history,
                    model_label=model,
                    llm_url=url,
                    timeout_sec=timeout,
                )
            elif p == "openai_compat":
                reply = self._chat_openai_compat(
                    message=msg,
                    context=safe_context,
                    history=history,
                    model_label=model,
                    llm_url=url,
                    api_key=api_key,
                    timeout_sec=timeout,
                )
            elif p == "claude":
                reply = self._chat_claude(
                    message=msg,
                    context=safe_context,
                    history=history,
                    model_label=model,
                    llm_url=url,
                    api_key=api_key,
                    timeout_sec=timeout,
                )
            else:
                return {"ok": False, "error": f"Unknown provider: {p}", "provider": p, "model": model}

            return {
                "ok": True,
                "reply": str(reply or "").strip(),
                "provider": p,
                "model": model,
                "generated_at": datetime.now(timezone.utc).isoformat(),
            }
        except Exception as exc:
            return {
                "ok": False,
                "error": f"{type(exc).__name__}: {str(exc)}",
                "provider": p,
                "model": model,
            }
