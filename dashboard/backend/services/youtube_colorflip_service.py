from __future__ import annotations

import logging
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional


logger = logging.getLogger(__name__)


def _to_bool(value: str, default: bool = False) -> bool:
    raw = str(value or "").strip().lower()
    if not raw:
        return bool(default)
    return raw in {"1", "true", "yes", "on"}


class YouTubeColorFlipService:
    """
    Optional subprocess runner for scripts/youtube_colorflip_watcher.py.

    Env-gated to avoid affecting existing deployments unless explicitly enabled.
    """

    def __init__(
        self,
        *,
        profile: str = "PRIMARY",
        default_url: str = "https://www.youtube.com/watch?v=fFrLWCCUY68",
        default_right_symbol: str = "BTCUSDm",
        default_left_symbol: str = "ETHUSDm",
        default_right_label: str = "BTC",
        default_left_label: str = "ETH",
    ) -> None:
        self._profile = str(profile or "PRIMARY").strip().upper() or "PRIMARY"
        self._default_url = str(default_url or "").strip()
        self._default_right_symbol = str(default_right_symbol or "").strip()
        self._default_left_symbol = str(default_left_symbol or "").strip()
        self._default_right_label = str(default_right_label or "").strip()
        self._default_left_label = str(default_left_label or "").strip()
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._lock = threading.RLock()
        self._proc: Optional[subprocess.Popen] = None

    def _variant_key(self, base_key: str) -> Optional[str]:
        key = str(base_key or "").strip().upper()
        if self._profile == "PRIMARY":
            return None
        if not key.startswith("YT_COLORFLIP_"):
            return None
        suffix = key[len("YT_COLORFLIP_") :].strip()
        if not suffix:
            return None
        return f"YT_COLORFLIP_{self._profile}_{suffix}"

    def _cfg(self, key: str, default: str = "", *, fallback_base: bool = True) -> str:
        vkey = self._variant_key(key)
        if vkey:
            vv = str(self._get_env_value(vkey, "") or "").strip()
            if vv:
                return vv
            if not fallback_base:
                return str(default or "")
        return str(self._get_env_value(key, default) or "").strip()

    @staticmethod
    def _get_env_value(name: str, default: str = "") -> str:
        # Reuse Telegram bridge env resolution so profile-scoped vars also work.
        try:
            from .telegram_bridge_service import TelegramBridgeService

            return str(TelegramBridgeService._get_env_value(name, default) or "").strip()
        except Exception:
            return str(default or "").strip()

    def _enabled(self) -> bool:
        if self._profile == "PRIMARY":
            return _to_bool(self._cfg("YT_COLORFLIP_SERVICE_ENABLED", "1"), default=True)
        return _to_bool(self._cfg("YT_COLORFLIP_SERVICE_ENABLED", "1", fallback_base=False), default=True)

    def _restart_delay_sec(self) -> float:
        try:
            raw = float(self._cfg("YT_COLORFLIP_RESTART_DELAY_SEC", "5"))
        except Exception:
            raw = 5.0
        return max(1.0, min(120.0, raw))

    @staticmethod
    def _repo_root() -> Path:
        return Path(__file__).resolve().parents[3]

    def _build_command(self) -> Optional[List[str]]:
        repo_root = self._repo_root()
        script_path = repo_root / "scripts" / "youtube_colorflip_watcher.py"
        if not script_path.exists():
            logger.warning("YouTube colorflip watcher script not found: %s", str(script_path))
            return None

        token = self._cfg("TELEGRAM_BOT_TOKEN", "")
        chat_id = self._cfg("TELEGRAM_ALLOWED_CHAT_ID", "")
        if not token or not chat_id:
            logger.warning("YouTube colorflip service disabled: TELEGRAM_BOT_TOKEN / TELEGRAM_ALLOWED_CHAT_ID missing")
            return None

        youtube_url = self._cfg(
            "YT_COLORFLIP_YOUTUBE_URL",
            str(self._default_url),
        )
        if not youtube_url:
            logger.warning("YouTube colorflip service disabled: YT_COLORFLIP_YOUTUBE_URL missing")
            return None

        cmd: List[str] = [
            str(sys.executable),
            "-u",
            str(script_path),
            "--youtube-url",
            str(youtube_url),
            "--telegram-bot-token",
            str(token),
            "--telegram-chat-id",
            str(chat_id),
            "--ffmpeg-path",
            str(self._cfg("YT_COLORFLIP_FFMPEG_PATH", "ffmpeg")),
            "--ffmpeg-fps",
            str(self._cfg("YT_COLORFLIP_FFMPEG_FPS", "5")),
            "--sample-every-n",
            str(self._cfg("YT_COLORFLIP_SAMPLE_EVERY_N", "1")),
            "--min-color-ratio",
            str(self._cfg("YT_COLORFLIP_MIN_COLOR_RATIO", "0.008")),
            "--row-peak-weight",
            str(self._cfg("YT_COLORFLIP_ROW_PEAK_WEIGHT", "1.35")),
            "--flip-color-source",
            str(self._cfg("YT_COLORFLIP_FLIP_COLOR_SOURCE", "hybrid")),
            "--line-score-band-px",
            str(self._cfg("YT_COLORFLIP_LINE_SCORE_BAND_PX", "2")),
            "--line-edge-columns",
            str(self._cfg("YT_COLORFLIP_LINE_EDGE_COLUMNS", "40")),
            "--line-edge-dominance",
            str(self._cfg("YT_COLORFLIP_LINE_EDGE_DOMINANCE", "1.08")),
            "--line-edge-min-presence",
            str(self._cfg("YT_COLORFLIP_LINE_EDGE_MIN_PRESENCE", "0.05")),
            "--line-min-score",
            str(self._cfg("YT_COLORFLIP_LINE_MIN_SCORE", "0.52")),
            "--line-min-coverage",
            str(self._cfg("YT_COLORFLIP_LINE_MIN_COVERAGE", "0.45")),
            "--line-min-points",
            str(self._cfg("YT_COLORFLIP_LINE_MIN_POINTS", "120")),
            "--debounce-seconds",
            str(self._cfg("YT_COLORFLIP_DEBOUNCE_SECONDS", "0.4")),
            "--min-emit-gap-seconds",
            str(self._cfg("YT_COLORFLIP_MIN_EMIT_GAP_SECONDS", "1.5")),
            "--edge-focus-px",
            str(self._cfg("YT_COLORFLIP_EDGE_FOCUS_PX", "16")),
            "--edge-weight",
            str(self._cfg("YT_COLORFLIP_EDGE_WEIGHT", "0.9")),
            "--continuity-tol-px",
            str(self._cfg("YT_COLORFLIP_CONTINUITY_TOL_PX", "0")),
            "--line-max-height-px",
            str(self._cfg("YT_COLORFLIP_LINE_MAX_HEIGHT_PX", "0")),
            "--line-max-area-px",
            str(self._cfg("YT_COLORFLIP_LINE_MAX_AREA_PX", "0")),
            "--transition-seed-ratio",
            str(self._cfg("YT_COLORFLIP_TRANSITION_SEED_RATIO", "0")),
            "--flip-dominance-margin",
            str(self._cfg("YT_COLORFLIP_FLIP_DOMINANCE_MARGIN", "1.08")),
            "--log-every-seconds",
            str(self._cfg("YT_COLORFLIP_LOG_EVERY_SECONDS", "5")),
            "--trade-timeframe",
            str(self._cfg("YT_COLORFLIP_TRADE_TIMEFRAME", "M5")),
            "--btc-symbol",
            str(self._cfg("YT_COLORFLIP_BTC_SYMBOL", str(self._default_right_symbol))),
            "--eth-symbol",
            str(self._cfg("YT_COLORFLIP_ETH_SYMBOL", str(self._default_left_symbol))),
            "--right-label",
            str(self._cfg("YT_COLORFLIP_RIGHT_LABEL", str(self._default_right_label))),
            "--left-label",
            str(self._cfg("YT_COLORFLIP_LEFT_LABEL", str(self._default_left_label))),
        ]

        if _to_bool(self._cfg("YT_COLORFLIP_FORCE_FFMPEG", "1"), default=True):
            cmd.append("--force-ffmpeg")
        if _to_bool(self._cfg("YT_COLORFLIP_NOTIFY_CANDIDATES", "0"), default=False):
            cmd.append("--notify-candidates")
        if _to_bool(self._cfg("YT_COLORFLIP_NOTIFY_YELLOW_CANDIDATES", "1"), default=True):
            cmd.append("--notify-yellow-candidates")
        if _to_bool(self._cfg("YT_COLORFLIP_NOTIFY_RED_ONLY", "0"), default=False):
            cmd.append("--notify-red-only")
        if _to_bool(self._cfg("YT_COLORFLIP_NOTIFY_TRANSIENT_RED_PROBE", "1"), default=True):
            cmd.append("--notify-transient-red-probe")
            cmd.extend(
                [
                    "--transient-probe-min-frames",
                    str(self._cfg("YT_COLORFLIP_TRANSIENT_PROBE_MIN_FRAMES", "1")),
                    "--transient-probe-min-edge-red-ratio",
                    str(self._cfg("YT_COLORFLIP_TRANSIENT_PROBE_MIN_EDGE_RED_RATIO", "0.10")),
                    "--transient-probe-cooldown-seconds",
                    str(self._cfg("YT_COLORFLIP_TRANSIENT_PROBE_COOLDOWN_SECONDS", "8.0")),
                ]
            )
        cmd.extend(
            [
                "--candidate-gap-seconds",
                str(self._cfg("YT_COLORFLIP_CANDIDATE_GAP_SECONDS", "10")),
            ]
        )

        if _to_bool(self._cfg("YT_COLORFLIP_DEBUG_LINE_EXTRACT", "0"), default=False):
            cmd.append("--debug-line-extract")
            cmd.extend(
                [
                    "--debug-line-json-file",
                    str(
                        self._cfg(
                            "YT_COLORFLIP_DEBUG_LINE_JSON_FILE",
                            str((repo_root / "dashboard" / "data" / "yt_line_debug.json").resolve()),
                        )
                    ),
                    "--debug-line-every-seconds",
                    str(self._cfg("YT_COLORFLIP_DEBUG_LINE_EVERY_SECONDS", "2.0")),
                    "--debug-line-min-columns",
                    str(self._cfg("YT_COLORFLIP_DEBUG_LINE_MIN_COLUMNS", "30")),
                    "--debug-line-smooth-window",
                    str(self._cfg("YT_COLORFLIP_DEBUG_LINE_SMOOTH_WINDOW", "7")),
                    "--debug-line-max-gap-columns",
                    str(self._cfg("YT_COLORFLIP_DEBUG_LINE_MAX_GAP_COLUMNS", "14")),
                ]
            )

        roi_file_raw = self._cfg("YT_COLORFLIP_ROI_FILE", "")
        if roi_file_raw:
            roi_path = Path(roi_file_raw)
            if not roi_path.is_absolute():
                roi_path = repo_root / roi_path
            if roi_path.exists():
                cmd.extend(["--roi-file", str(roi_path)])
            else:
                logger.warning("YT_COLORFLIP_ROI_FILE not found: %s (falling back to auto panels)", str(roi_path))
                cmd.append("--auto-two-panels")
        else:
            cmd.append("--auto-two-panels")
        return cmd

    @staticmethod
    def _mask_command(cmd: List[str]) -> str:
        out: List[str] = []
        skip_next = False
        secret_flags = {"--telegram-bot-token", "--telegram-chat-id"}
        for i, tok in enumerate(cmd):
            if skip_next:
                skip_next = False
                continue
            if tok in secret_flags and i + 1 < len(cmd):
                out.append(tok)
                out.append("***")
                skip_next = True
            else:
                out.append(tok)
        return " ".join(out)

    def _terminate_proc(self, timeout_sec: float = 5.0) -> None:
        with self._lock:
            proc = self._proc
        if proc is None:
            return
        try:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=float(max(0.5, timeout_sec)))
        except Exception:
            try:
                if proc.poll() is None:
                    proc.kill()
            except Exception:
                pass
        finally:
            with self._lock:
                self._proc = None

    def _loop(self) -> None:
        logger.info("YouTube colorflip service loop started (profile=%s)", str(self._profile))
        while not self._stop.is_set():
            cmd = self._build_command()
            if not cmd:
                self._stop.wait(5.0)
                continue
            logger.info("Starting YouTube colorflip watcher (profile=%s): %s", str(self._profile), self._mask_command(cmd))
            try:
                proc = subprocess.Popen(
                    cmd,
                    cwd=str(self._repo_root()),
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                with self._lock:
                    self._proc = proc
            except Exception as exc:
                logger.warning("YouTube colorflip watcher failed to start: %s", str(exc)[:220])
                self._stop.wait(self._restart_delay_sec())
                continue

            while not self._stop.is_set():
                with self._lock:
                    p = self._proc
                if p is None:
                    break
                rc = p.poll()
                if rc is not None:
                    logger.warning("YouTube colorflip watcher exited (profile=%s) code=%s; restarting", str(self._profile), str(rc))
                    with self._lock:
                        self._proc = None
                    break
                self._stop.wait(1.0)

            if self._stop.is_set():
                break
            self._stop.wait(self._restart_delay_sec())
        self._terminate_proc(timeout_sec=3.0)
        logger.info("YouTube colorflip service loop stopped (profile=%s)", str(self._profile))

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        if not self._enabled():
            logger.info("YouTube colorflip service disabled (profile=%s)", str(self._profile))
            return
        self._stop.clear()
        th_name = "yt-colorflip-service" if self._profile == "PRIMARY" else f"yt-colorflip-service-{str(self._profile).lower()}"
        self._thread = threading.Thread(target=self._loop, daemon=True, name=str(th_name))
        self._thread.start()
        logger.info("YouTube colorflip service started (profile=%s)", str(self._profile))

    def stop(self) -> None:
        self._stop.set()
        self._terminate_proc(timeout_sec=3.0)
        th = self._thread
        if th and th.is_alive():
            th.join(timeout=5.0)
        self._thread = None
        logger.info("YouTube colorflip service stopped (profile=%s)", str(self._profile))
