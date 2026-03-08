"""
Local GPT-OSS 20B sidecar for Options Edge reports.

Runs a tiny HTTP server with:
- GET  /health
- POST /generate   (options_edge_report task)
- POST /chat       (simple chat for testing / general use)

Request example (/generate):
{
  "task": "options_edge_report",
  "input": {
    "scan": {...},
    "candidates": [...],
    "trades": [...],
    "symbol_insights": {...}
  },
  "max_tokens": 850,
  "temperature": 0.2
}

Request example (/chat):
{
  "message": "Hello, how are you?",
  "max_tokens": 256,
  "temperature": 0.7
}
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List


SYSTEM_PROMPT = (
    "You are a quantitative options report assistant. "
    "Output ONLY a single valid JSON object. No markdown, no explanation, no prose. "
    "Start your response with { and end with }."
)

USER_INSTRUCTIONS = (
    "Analyze the options scan data below and return a SINGLE JSON object with these exact keys:\n"
    '{"market_summary":"<1 sentence>","risk_summary":"<1 sentence>",'
    '"candidate_notes":[{"symbol":"SYM","text":"brief note"}],'
    '"trade_decisions":[{"symbol":"SYM","action":"ENTER|WATCH|SKIP",'
    '"structure":"type","confidence":0.0-1.0,'
    '"reasons":["reason"],"scan_evidence":{"score_total":0,"pop_est":0}}],'
    '"warnings":["warning if any"]}\n\n'
    "Rules:\n"
    "- action MUST be ENTER if score_total>=72 AND pop_est>=0.70\n"
    "- action is WATCH if score_total>=67 AND pop_est>=0.64\n"
    "- action is SKIP otherwise\n"
    "- Output ONLY the JSON object, nothing else\n\n"
    "Input data:\n"
)


def _strip_special_tokens(text: str) -> str:
    """Remove harmony/channel tokens and other non-JSON prefixes from model output."""
    import re
    # Strip <|channel|>...<|message|> blocks (GPT-OSS harmony format)
    t = re.sub(r'<\|channel\|>[^<]*', '', text)
    t = re.sub(r'<\|message\|>', '', t)
    # Strip other common special tokens
    for tok in ('<|im_start|>', '<|im_end|>', '<|start|>', '<|end|>',
                '<|assistant|>', '<|user|>', '<|system|>', '<|eot_id|>',
                '<|start_header_id|>', '<|end_header_id|>'):
        t = t.replace(tok, '')
    return t.strip()


def _find_json_end(text: str, start: int) -> int:
    """Walk forward from '{' at *start* tracking brace depth + string state.

    Returns the index of the matching '}' or -1 if the object is truncated.
    Correctly ignores braces inside JSON string literals.
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


def _extract_json_object(text: str) -> Dict[str, Any] | None:
    raw = str(text or "").strip()
    if not raw:
        return None
    # First strip any special tokens that models might emit
    t = _strip_special_tokens(raw)
    if not t:
        return None
    # Direct JSON parse
    try:
        obj = json.loads(t)
        if isinstance(obj, dict):
            return obj
    except Exception:
        pass
    # Try fenced code block
    if "```" in t:
        for part in t.split("```"):
            s = part.strip()
            if s.lower().startswith("json"):
                s = s[4:].strip()
            try:
                obj = json.loads(s)
                if isinstance(obj, dict):
                    return obj
            except Exception:
                continue
    # Brace-depth extraction: find the outermost { ... } respecting strings.
    # This correctly ignores } in trailing reasoning text after the JSON.
    lo = t.find("{")
    if lo >= 0:
        hi = _find_json_end(t, lo)
        if hi > lo:
            try:
                obj = json.loads(t[lo : hi + 1])
                if isinstance(obj, dict):
                    return obj
            except Exception:
                pass
    # Fallback: try on raw text (before stripping) in case tokens were inside JSON strings
    lo = raw.find("{")
    if lo >= 0:
        hi = _find_json_end(raw, lo)
        if hi > lo:
            frag = _strip_special_tokens(raw[lo : hi + 1])
            try:
                obj = json.loads(frag)
                if isinstance(obj, dict):
                    return obj
            except Exception:
                pass
    return None


def _log(msg: str) -> None:
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


class _State:
    model_name: str = "gpt-oss-20b"
    llm: Any = None
    lock = threading.Lock()


class _Handler(BaseHTTPRequestHandler):
    def _send_json(self, code: int, body: Dict[str, Any]) -> None:
        raw = json.dumps(body, ensure_ascii=True).encode("utf-8")
        try:
            ok_flag = body.get("ok") if isinstance(body, dict) else None
            err_flag = body.get("error") if isinstance(body, dict) else None
            extra = f" ok={ok_flag}"
            if err_flag:
                extra += f" error={str(err_flag)[:120]}"
            _log(f"  -> response {code} {self.command} {self.path}{extra}")
        except Exception:
            # Logging must never break response path.
            pass
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
        except (ConnectionAbortedError, ConnectionResetError, BrokenPipeError):
            # Client disconnected before we could send the response (timeout).
            _log(f"  -> client disconnected before response write ({self.command} {self.path})")

    def do_GET(self) -> None:
        _log(f"GET {self.path} from {self.client_address[0]}")
        if self.path.rstrip("/") == "/health":
            return self._send_json(
                200,
                {
                    "ok": True,
                    "model": _State.model_name,
                    "loaded": _State.llm is not None,
                },
            )
        _log(f"  -> 404 not_found")
        self._send_json(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:
        path = self.path.rstrip("/")
        _log(f"POST {path} from {self.client_address[0]}")
        if path == "/chat":
            return self._handle_chat()
        if path != "/generate":
            _log(f"  -> 404 not_found")
            return self._send_json(404, {"ok": False, "error": "not_found"})
        if _State.llm is None:
            _log(f"  -> 500 model_not_loaded")
            return self._send_json(500, {"ok": False, "error": "model_not_loaded"})

        try:
            clen = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(max(0, clen))
            req = json.loads(raw.decode("utf-8"))
        except Exception as e:
            _log(f"  -> 400 bad_json: {e}")
            return self._send_json(400, {"ok": False, "error": f"bad_json: {e}"})

        task = str(req.get("task") or "").strip().lower()
        temperature = float(req.get("temperature", 0.7))
        # Cap max_tokens: 800 is plenty for 5-8 symbol JSON (~400-600 tokens actual).
        # Higher values = proportionally longer inference (2048 took 15 min!).
        max_tokens = min(int(req.get("max_tokens", 800)), 1024)
        payload = req.get("input") if isinstance(req.get("input"), dict) else {}

        n_candidates = len(payload.get("candidates", []))
        n_trades = len(payload.get("trades", []))
        symbols = [str(c.get("symbol", "?")) for c in payload.get("candidates", [])[:8]]
        _log(f"  task={task} max_tokens={max_tokens} temp={temperature}")
        _log(f"  input: {n_candidates} candidates, {n_trades} trades, symbols={symbols}")

        if task != "options_edge_report":
            _log(f"  -> 400 unsupported_task '{task}'")
            return self._send_json(400, {"ok": False, "error": "unsupported_task"})

        # Compact the input: only send fields the model needs for decisions
        compact = self._compact_payload(payload)
        prompt_json = json.dumps(compact, ensure_ascii=True)
        prompt_len = len(prompt_json)
        _log(f"  compact payload size: {prompt_len:,} chars (from {len(json.dumps(payload)):,})")

        # Use text completion (not chat completion) to bypass harmony template.
        # GPT-OSS produces <|channel|>analysis<|message|> tokens with chat mode,
        # which wastes all tokens on internal reasoning instead of JSON output.
        prompt = (
            f"{SYSTEM_PROMPT}\n\n"
            f"{USER_INSTRUCTIONS}{prompt_json}\n\n"
            f"JSON response:\n"
        )
        # Pre-fill with opening brace to force JSON mode
        json_prefix = '{"market_summary":'
        prompt += json_prefix

        t0 = time.time()
        try:
            with _State.lock:
                out = _State.llm.create_completion(
                    prompt=prompt,
                    max_tokens=max_tokens,
                    temperature=temperature,
                    top_p=1.0,
                    top_k=0,
                    repeat_penalty=1.0,
                    stop=["<|channel|>", "<|im_end|>", "<|end|>", "<|eot_id|>", "\n\n\n"],
                )
            elapsed = time.time() - t0
            usage = out.get("usage", {}) if isinstance(out, dict) else {}
            prompt_tokens = usage.get("prompt_tokens", "?")
            completion_tokens = usage.get("completion_tokens", "?")
            _log(f"  inference done in {elapsed:.1f}s (prompt_tokens={prompt_tokens}, completion_tokens={completion_tokens})")

            # Extract completion text and prepend our JSON prefix
            raw_text = str((out.get("choices") or [{}])[0].get("text") or "")
            text = json_prefix + raw_text
            _log(f"  raw output length: {len(text)} chars")
            _log(f"  output preview: {text[:300]}")
            parsed = _extract_json_object(text)
            if not isinstance(parsed, dict):
                _log(f"  -> 200 json_parse_failed! full text: {text[:500]}")
                return self._send_json(
                    200,
                    {
                        "ok": False,
                        "model": _State.model_name,
                        "error": "json_parse_failed",
                        "raw_text": text[:4000],
                    },
                )
            n_decisions = len(parsed.get("trade_decisions", []))
            actions = [str(d.get("action", "?")) for d in parsed.get("trade_decisions", []) if isinstance(d, dict)]
            _log(f"  -> 200 OK: {n_decisions} trade_decisions, actions={actions}")
            return self._send_json(200, {"ok": True, "model": _State.model_name, "result": parsed})
        except Exception as e:
            elapsed = time.time() - t0
            _log(f"  -> 500 inference error after {elapsed:.1f}s: {type(e).__name__}: {str(e)[:200]}")
            return self._send_json(500, {"ok": False, "model": _State.model_name, "error": str(e)[:500]})

    @staticmethod
    def _compact_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
        """Strip verbose fields from scan input to reduce prompt tokens."""
        compact: Dict[str, Any] = {}
        # Only keep essential candidate fields
        candidates = []
        for c in (payload.get("candidates") or [])[:8]:
            candidates.append({
                "symbol": c.get("symbol"),
                "score_total": round(float(c.get("score_total", 0)), 1),
                "score_vol_edge": round(float(c.get("score_vol_edge", 0)), 1),
                "score_liquidity": round(float(c.get("score_liquidity", 0)), 1),
            })
        compact["candidates"] = candidates
        # Only keep essential trade fields
        trades = []
        for t in (payload.get("trades") or [])[:10]:
            trades.append({
                "symbol": t.get("symbol"),
                "structure_type": t.get("structure_type"),
                "pop_est": round(float(t.get("pop_est", 0)), 4),
                "max_profit": round(float(t.get("max_profit", 0)), 2),
                "max_loss": round(float(t.get("max_loss", 0)), 2),
                "proxy": bool(t.get("max_loss_is_proxy")),
            })
        compact["trades"] = trades
        return compact

    def _handle_chat(self) -> None:
        """Simple chat endpoint for testing / general conversation."""
        if _State.llm is None:
            _log(f"  -> 500 model_not_loaded")
            return self._send_json(500, {"ok": False, "error": "model_not_loaded"})
        try:
            clen = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(max(0, clen))
            req = json.loads(raw.decode("utf-8"))
        except Exception as e:
            _log(f"  -> 400 bad_json: {e}")
            return self._send_json(400, {"ok": False, "error": f"bad_json: {e}"})

        message = str(req.get("message") or "").strip()
        if not message:
            _log(f"  -> 400 empty_message")
            return self._send_json(400, {"ok": False, "error": "empty_message"})

        temperature = float(req.get("temperature", 0.7))
        max_tokens = int(req.get("max_tokens", 256))
        system = str(req.get("system", "You are a helpful AI assistant.")).strip()
        _log(f"  chat: max_tokens={max_tokens} temp={temperature} msg_len={len(message)}")

        messages = [
            {"role": "system", "content": system},
            {"role": "user", "content": message},
        ]
        t0 = time.time()
        try:
            with _State.lock:
                out = _State.llm.create_chat_completion(
                    messages=messages,
                    max_tokens=max_tokens,
                    temperature=temperature,
                )
            elapsed = time.time() - t0
            reply = str((((out or {}).get("choices") or [{}])[0].get("message") or {}).get("content") or "")
            _log(f"  -> 200 OK chat reply in {elapsed:.1f}s ({len(reply)} chars)")
            return self._send_json(200, {
                "ok": True,
                "model": _State.model_name,
                "reply": reply.strip(),
            })
        except Exception as e:
            elapsed = time.time() - t0
            _log(f"  -> 500 chat error after {elapsed:.1f}s: {type(e).__name__}: {str(e)[:200]}")
            return self._send_json(500, {"ok": False, "model": _State.model_name, "error": str(e)[:500]})

    def log_message(self, fmt: str, *args: Any) -> None:
        # Suppress default BaseHTTPRequestHandler access logs (we use _log instead).
        pass


def _resolve_model_path(cli_path: str | None, model_dir: str, glob_pat: str) -> Path:
    base_dir = Path(__file__).resolve().parent
    if cli_path:
        p = Path(cli_path)
        if not p.is_absolute():
            p = (base_dir / p).resolve()
        if p.exists():
            return p
    md = Path(model_dir)
    if not md.is_absolute():
        md = (base_dir / md).resolve()
    candidates = sorted(glob.glob(str(md / glob_pat)))
    if not candidates:
        raise FileNotFoundError(f"No GGUF model found in {md} with pattern {glob_pat}")
    return Path(candidates[0])


def _add_windows_dll_dirs(extra_paths: List[str] | None = None) -> List[str]:
    added: List[str] = []
    seen: set[str] = set()
    if os.name != "nt":
        return added
    candidates = [
        r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.1\bin\x64",
        r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.1\bin",
        r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin\x64",
        r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin",
        r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\x64",
        r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin",
        r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4\bin\x64",
        r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4\bin",
        r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.3\bin\x64",
        r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.3\bin",
    ]
    if extra_paths:
        candidates = list(extra_paths) + candidates
    for p in candidates:
        if not p:
            continue
        norm = os.path.normcase(os.path.normpath(p))
        if norm in seen:
            continue
        seen.add(norm)
        if os.path.isdir(p):
            try:
                os.add_dll_directory(p)
            except Exception:
                # Older Python or restricted environment; fallback to PATH only.
                pass
            os.environ["PATH"] = p + os.pathsep + os.environ.get("PATH", "")
            added.append(p)
    return added


def main() -> int:
    parser = argparse.ArgumentParser(description="Run local GPT-OSS 20B sidecar for Options Edge.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8012)
    parser.add_argument("--model-path", default=None)
    parser.add_argument("--model-dir", default=str(Path("models") / "gpt-oss-20b"))
    parser.add_argument("--glob", default="*Q4_K_M*.gguf")
    parser.add_argument("--n-gpu-layers", type=int, default=15)
    parser.add_argument("--n-ctx", type=int, default=4096)
    parser.add_argument(
        "--cuda-dll-path",
        action="append",
        default=[],
        help="Optional CUDA DLL directory to add before loading llama_cpp (can be passed multiple times).",
    )
    args = parser.parse_args()

    added_dirs = _add_windows_dll_dirs(extra_paths=args.cuda_dll_path or [])
    if added_dirs:
        print("Added DLL directories:")
        print("it has started")
        for p in added_dirs:
            print(f"  - {p}")
    else:
        print("No CUDA DLL directory added (Windows only).")

    try:
        from llama_cpp import Llama
    except Exception as e:
        print("Failed to import llama_cpp. This is usually a dependency/DLL issue.")
        print(f"Import error: {e}")
        print("Tip: pass --cuda-dll-path \"C:\\Program Files\\NVIDIA GPU Computing Toolkit\\CUDA\\v13.1\\bin\\x64\"")
        return 2

    model_path = _resolve_model_path(args.model_path, args.model_dir, args.glob)
    _State.model_name = "gpt-oss-20b"
    try:
        _State.llm = Llama(
            model_path=str(model_path),
            n_ctx=int(args.n_ctx),
            n_gpu_layers=int(args.n_gpu_layers),
            verbose=False,
        )
    except Exception as e:
        print(f"Failed to load model: {model_path}")
        print(f"Error: {e}")
        print("Tip: try reducing --n-gpu-layers or check VRAM availability.")
        return 3

    server = ThreadingHTTPServer((args.host, int(args.port)), _Handler)
    print(f"Options-edge GPT-OSS sidecar listening on http://{args.host}:{args.port}")
    print(f"Model: {model_path}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
