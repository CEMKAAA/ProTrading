#!/usr/bin/env python3
"""
YouTube livestream color-flip watcher for two panels (e.g. BTC + ETH).

What it does:
- Resolves a direct stream URL from a YouTube live link (yt-dlp).
- Reads frames with OpenCV.
- Tracks dominant line color inside two ROI boxes (BTC/ETH).
- Emits stable RED<->YELLOW flip events with debounce.
- Optionally sends flip alerts to Telegram.

Usage examples:
  python scripts/youtube_colorflip_watcher.py ^
    --youtube-url "https://www.youtube.com/watch?v=fFrLWCCUY68" ^
    --calibrate --show-preview --save-roi-file scripts/yt_rois.json

  python scripts/youtube_colorflip_watcher.py ^
    --youtube-url "https://www.youtube.com/watch?v=fFrLWCCUY68" ^
    --roi-file scripts/yt_rois.json ^
    --telegram-bot-token "<TOKEN>" --telegram-chat-id "<CHAT_ID>"
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import requests


def _import_cv2_or_exit():
    try:
        import cv2  # type: ignore
    except Exception as exc:
        print(f"[ERR] OpenCV import failed: {exc}")
        print("[HINT] Install with: pip install opencv-python")
        sys.exit(1)
    return cv2


def _import_yt_dlp_or_exit():
    try:
        import yt_dlp  # type: ignore
    except Exception as exc:
        print(f"[ERR] yt-dlp import failed: {exc}")
        print("[HINT] Install with: pip install yt-dlp")
        sys.exit(1)
    return yt_dlp


@dataclass
class ROI:
    x: int
    y: int
    w: int
    h: int

    def clamp(self, frame_w: int, frame_h: int) -> "ROI":
        x = max(0, min(self.x, max(0, frame_w - 1)))
        y = max(0, min(self.y, max(0, frame_h - 1)))
        w = max(1, min(self.w, frame_w - x))
        h = max(1, min(self.h, frame_h - y))
        return ROI(x=x, y=y, w=w, h=h)


@dataclass
class PanelState:
    stable_color: str = "unknown"
    pending_color: str = "unknown"
    pending_since: float = 0.0
    last_emit_ts: float = 0.0
    last_line_y: float = -1.0
    last_candidate_emit_ts: float = 0.0
    transient_red_streak: int = 0
    last_transient_red_emit_ts: float = 0.0


class TelegramNotifier:
    def __init__(self, token: str, chat_id: str, timeout_s: float = 5.0) -> None:
        self.token = str(token or "").strip()
        self.chat_id = str(chat_id or "").strip()
        self.timeout_s = float(timeout_s)

    @property
    def enabled(self) -> bool:
        return bool(self.token and self.chat_id)

    def send(self, text: str) -> None:
        if not self.enabled:
            return
        url = f"https://api.telegram.org/bot{self.token}/sendMessage"
        payload = {"chat_id": self.chat_id, "text": text}
        try:
            requests.post(url, json=payload, timeout=self.timeout_s)
        except Exception as exc:
            print(f"[WARN] Telegram send failed: {exc}")


def parse_roi(s: str) -> ROI:
    raw = [x.strip() for x in str(s or "").split(",")]
    if len(raw) != 4:
        raise ValueError("ROI must be x,y,w,h")
    x, y, w, h = (int(v) for v in raw)
    return ROI(x=x, y=y, w=w, h=h)


def load_roi_file(path: str) -> Dict[str, ROI]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    out: Dict[str, ROI] = {}
    for k in ("btc", "eth"):
        if k not in data:
            raise ValueError(f"Missing '{k}' in roi file")
        item = data[k]
        out[k] = ROI(
            x=int(item["x"]),
            y=int(item["y"]),
            w=int(item["w"]),
            h=int(item["h"]),
        )
    return out


def save_roi_file(path: str, rois: Dict[str, ROI]) -> None:
    payload = {
        "btc": {"x": rois["btc"].x, "y": rois["btc"].y, "w": rois["btc"].w, "h": rois["btc"].h},
        "eth": {"x": rois["eth"].x, "y": rois["eth"].y, "w": rois["eth"].w, "h": rois["eth"].h},
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=True, indent=2)
    print(f"[OK] ROI config saved: {path}")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _to_float_or_none(v: Any) -> Optional[float]:
    try:
        f = float(v)
    except Exception:
        return None
    if not np.isfinite(f):
        return None
    return float(f)


def resolve_youtube_stream(youtube_url: str) -> Tuple[str, str]:
    yt_dlp = _import_yt_dlp_or_exit()
    opts = {
        "quiet": True,
        "skip_download": True,
        "noplaylist": True,
        "format": "best",
        # Force direct connection; avoids broken local proxy envs.
        "proxy": "",
    }
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(youtube_url, download=False)
    stream_url = str(info.get("url") or "").strip()
    title = str(info.get("title") or "").strip()
    if not stream_url:
        raise RuntimeError("Could not resolve stream URL from YouTube link")
    return stream_url, title


def classify_red_yellow(
    roi_bgr: np.ndarray,
    *,
    min_ratio: float,
    edge_focus_px: int = 0,
    edge_weight: float = 0.85,
    row_peak_weight: float = 1.25,
) -> Tuple[str, float, float, Optional[float], Optional[float], float, float, float, float]:
    if roi_bgr.size <= 0:
        return "unknown", 0.0, 0.0
    cv2 = _import_cv2_or_exit()
    hsv = cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2HSV)

    # Red split in HSV (wrap-around at 0/180).
    red1 = cv2.inRange(hsv, (0, 70, 70), (10, 255, 255))
    red2 = cv2.inRange(hsv, (160, 70, 70), (180, 255, 255))
    red_mask = cv2.bitwise_or(red1, red2)
    yellow_mask = cv2.inRange(hsv, (15, 70, 70), (40, 255, 255))

    total = float(roi_bgr.shape[0] * roi_bgr.shape[1])
    red_ratio = float(np.count_nonzero(red_mask)) / total
    yellow_ratio = float(np.count_nonzero(yellow_mask)) / total

    red_eff = float(red_ratio)
    yellow_eff = float(yellow_ratio)
    edge_px = int(max(0, edge_focus_px))
    red_y: Optional[float] = None
    yellow_y: Optional[float] = None
    red_h: float = 0.0
    yellow_h: float = 0.0
    red_area: float = 0.0
    yellow_area: float = 0.0
    edge_w = float(max(0.0, min(1.0, edge_weight)))
    def _row_peak(mask: np.ndarray) -> float:
        if mask.size <= 0 or mask.shape[1] <= 0:
            return 0.0
        row_counts = np.count_nonzero(mask, axis=1).astype(float)
        if row_counts.size <= 0:
            return 0.0
        return float(np.max(row_counts) / max(1.0, float(mask.shape[1])))

    if edge_px > 0 and roi_bgr.shape[1] > 1:
        edge_px = min(edge_px, int(roi_bgr.shape[1]))
        edge_crop = roi_bgr[:, roi_bgr.shape[1] - edge_px :]
        edge_hsv = cv2.cvtColor(edge_crop, cv2.COLOR_BGR2HSV)
        edge_red1 = cv2.inRange(edge_hsv, (0, 70, 70), (10, 255, 255))
        edge_red2 = cv2.inRange(edge_hsv, (160, 70, 70), (180, 255, 255))
        edge_red_mask = cv2.bitwise_or(edge_red1, edge_red2)
        edge_yellow_mask = cv2.inRange(edge_hsv, (15, 70, 70), (40, 255, 255))
        edge_total = float(edge_crop.shape[0] * edge_crop.shape[1])
        edge_red_ratio = float(np.count_nonzero(edge_red_mask)) / max(1.0, edge_total)
        edge_yellow_ratio = float(np.count_nonzero(edge_yellow_mask)) / max(1.0, edge_total)
        edge_red_row_peak = _row_peak(edge_red_mask)
        edge_yellow_row_peak = _row_peak(edge_yellow_mask)
        red_eff = max(
            red_ratio,
            (1.0 - edge_w) * red_ratio + edge_w * edge_red_ratio,
            float(edge_red_row_peak) * float(max(0.0, row_peak_weight)),
        )
        yellow_eff = max(
            yellow_ratio,
            (1.0 - edge_w) * yellow_ratio + edge_w * edge_yellow_ratio,
            float(edge_yellow_row_peak) * float(max(0.0, row_peak_weight)),
        )

        def _best_component(mask: np.ndarray) -> Tuple[Optional[float], float, float]:
            n, _, stats, cents = cv2.connectedComponentsWithStats(mask, connectivity=8)
            if n <= 1:
                return None, 0.0, 0.0
            best_idx = -1
            best_area = 0.0
            for idx in range(1, n):
                area = float(stats[idx, cv2.CC_STAT_AREA])
                if area > best_area:
                    best_area = area
                    best_idx = idx
            if best_idx < 0:
                return None, 0.0, 0.0
            h = float(stats[best_idx, cv2.CC_STAT_HEIGHT])
            cy = float(cents[best_idx][1])
            return cy, h, best_area

        red_y, red_h, red_area = _best_component(edge_red_mask)
        yellow_y, yellow_h, yellow_area = _best_component(edge_yellow_mask)

    if edge_px <= 0 or roi_bgr.shape[1] <= 1:
        red_row_peak = _row_peak(red_mask)
        yellow_row_peak = _row_peak(yellow_mask)
        red_eff = max(red_eff, float(red_row_peak) * float(max(0.0, row_peak_weight)))
        yellow_eff = max(yellow_eff, float(yellow_row_peak) * float(max(0.0, row_peak_weight)))

    if red_eff < min_ratio and yellow_eff < min_ratio:
        return "unknown", red_ratio, yellow_ratio, red_y, yellow_y, red_h, yellow_h, red_area, yellow_area
    if red_eff > yellow_eff:
        return "red", red_ratio, yellow_ratio, red_y, yellow_y, red_h, yellow_h, red_area, yellow_area
    return "yellow", red_ratio, yellow_ratio, red_y, yellow_y, red_h, yellow_h, red_area, yellow_area


def _build_red_yellow_masks(roi_bgr: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    cv2 = _import_cv2_or_exit()
    hsv = cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2HSV)
    red1 = cv2.inRange(hsv, (0, 70, 70), (10, 255, 255))
    red2 = cv2.inRange(hsv, (160, 70, 70), (180, 255, 255))
    red_mask = cv2.bitwise_or(red1, red2)
    yellow_mask = cv2.inRange(hsv, (15, 70, 70), (40, 255, 255))
    return red_mask, yellow_mask


def extract_trend_line_points(
    roi_bgr: np.ndarray,
    *,
    color_name: str,
    min_columns: int = 30,
    smooth_window: int = 7,
    max_gap_columns: int = 14,
) -> Dict[str, Any]:
    """
    Extract an approximate full trend-line polyline inside ROI.
    This is debug-only and must not affect flip detection decisions.
    """
    if roi_bgr.size <= 0:
        return {"ok": False, "reason": "empty_roi", "points": []}
    h, w = roi_bgr.shape[:2]
    if h < 2 or w < 2:
        return {"ok": False, "reason": "tiny_roi", "points": []}

    red_mask, yellow_mask = _build_red_yellow_masks(roi_bgr)
    cname = str(color_name or "").strip().lower()
    if cname == "red":
        mask = red_mask
    elif cname == "yellow":
        mask = yellow_mask
    else:
        return {"ok": False, "reason": "invalid_color", "points": []}

    ys = np.full(w, np.nan, dtype=float)
    for x in range(w):
        rows = np.flatnonzero(mask[:, x] > 0)
        if rows.size > 0:
            ys[x] = float(np.median(rows))

    valid = np.isfinite(ys)
    valid_count = int(np.count_nonzero(valid))
    if valid_count < int(max(2, min_columns)):
        return {
            "ok": False,
            "reason": "insufficient_columns",
            "points": [],
            "valid_columns": valid_count,
            "width": int(w),
        }

    # Fill short gaps by linear interpolation.
    x_all = np.arange(w, dtype=float)
    x_valid = x_all[valid]
    y_valid = ys[valid]
    ys_interp = np.interp(x_all, x_valid, y_valid)

    # Re-mask long gaps so line doesn't bridge disconnected regions.
    gap_start = None
    for i in range(w):
        if not valid[i] and gap_start is None:
            gap_start = i
        if valid[i] and gap_start is not None:
            gap_len = i - int(gap_start)
            if gap_len > int(max_gap_columns):
                ys_interp[int(gap_start):i] = np.nan
            gap_start = None
    if gap_start is not None:
        gap_len = w - int(gap_start)
        if gap_len > int(max_gap_columns):
            ys_interp[int(gap_start):w] = np.nan

    # Smooth with simple moving average ignoring NaNs.
    win = int(max(1, smooth_window))
    if win > 1:
        half = win // 2
        ys_smooth = ys_interp.copy()
        for i in range(w):
            a = max(0, i - half)
            b = min(w, i + half + 1)
            seg = ys_interp[a:b]
            seg = seg[np.isfinite(seg)]
            if seg.size > 0:
                ys_smooth[i] = float(np.mean(seg))
        ys_interp = ys_smooth

    points: List[Dict[str, float]] = []
    finite = np.isfinite(ys_interp)
    for i in range(w):
        if finite[i]:
            points.append({"x": float(i), "y": float(ys_interp[i])})

    if len(points) < int(max(2, min_columns)):
        return {
            "ok": False,
            "reason": "insufficient_points_after_gap_filter",
            "points": [],
            "valid_columns": valid_count,
            "width": int(w),
        }

    x1 = float(points[0]["x"])
    y1 = float(points[0]["y"])
    x2 = float(points[-1]["x"])
    y2 = float(points[-1]["y"])
    slope = float((y2 - y1) / max(1.0, (x2 - x1)))
    return {
        "ok": True,
        "color": cname,
        "points": points,
        "valid_columns": valid_count,
        "coverage": float(valid_count / max(1.0, float(w))),
        "slope_px_per_col": slope,
        "start": {"x": x1, "y": y1},
        "end": {"x": x2, "y": y2},
    }


def _line_points_score(mask: np.ndarray, points: List[Dict[str, float]], band_px: int = 2) -> float:
    if mask.size <= 0 or not isinstance(points, list) or len(points) < 8:
        return 0.0
    h, w = mask.shape[:2]
    b = int(max(0, band_px))
    hit = 0
    tot = 0
    for p in points:
        try:
            x = int(round(float(p.get("x", 0.0))))
            y = int(round(float(p.get("y", 0.0))))
        except Exception:
            continue
        if x < 0 or x >= w:
            continue
        y0 = max(0, y - b)
        y1 = min(h - 1, y + b)
        seg = mask[y0 : y1 + 1, x]
        tot += int(seg.size)
        hit += int(np.count_nonzero(seg > 0))
    if tot <= 0:
        return 0.0
    return float(hit) / float(tot)


def detect_line_local_edge_color(
    roi_bgr: np.ndarray,
    *,
    min_columns: int,
    smooth_window: int,
    max_gap_columns: int,
    score_band_px: int,
    edge_columns: int,
    edge_dominance: float,
    edge_min_presence: float,
    min_line_score: float,
    min_line_coverage: float,
    min_line_points: int,
) -> Dict[str, Any]:
    """
    Detect line color from the extracted trend-line itself (not whole-ROI area).
    """
    out: Dict[str, Any] = {
        "ok": False,
        "color": "unknown",
        "confidence": 0.0,
        "edge_red_ratio": 0.0,
        "edge_yellow_ratio": 0.0,
        "line_end_y": None,
        "reason": "init",
    }
    if roi_bgr.size <= 0:
        out["reason"] = "empty_roi"
        return out
    h, w = roi_bgr.shape[:2]
    if h < 4 or w < 8:
        out["reason"] = "tiny_roi"
        return out

    red_mask, yellow_mask = _build_red_yellow_masks(roi_bgr)
    line_y = extract_trend_line_points(
        roi_bgr,
        color_name="yellow",
        min_columns=int(min_columns),
        smooth_window=int(smooth_window),
        max_gap_columns=int(max_gap_columns),
    )
    line_r = extract_trend_line_points(
        roi_bgr,
        color_name="red",
        min_columns=int(min_columns),
        smooth_window=int(smooth_window),
        max_gap_columns=int(max_gap_columns),
    )
    y_ok = bool(line_y.get("ok")) and float(line_y.get("coverage") or 0.0) >= float(min_line_coverage) and len(line_y.get("points") or []) >= int(min_line_points)
    r_ok = bool(line_r.get("ok")) and float(line_r.get("coverage") or 0.0) >= float(min_line_coverage) and len(line_r.get("points") or []) >= int(min_line_points)
    if not y_ok and not r_ok:
        out["reason"] = "line_not_ok"
        return out

    y_score = _line_points_score(yellow_mask, list(line_y.get("points") or []), band_px=int(score_band_px)) if y_ok else 0.0
    r_score = _line_points_score(red_mask, list(line_r.get("points") or []), band_px=int(score_band_px)) if r_ok else 0.0
    out["yellow_line_score"] = float(y_score)
    out["red_line_score"] = float(r_score)

    # choose dominant extracted line
    if y_score >= r_score:
        base_line = line_y if y_ok else line_r
        base_color = "yellow" if y_ok else "red"
        base_score = y_score if y_ok else r_score
    else:
        base_line = line_r if r_ok else line_y
        base_color = "red" if r_ok else "yellow"
        base_score = r_score if r_ok else y_score
    if not bool(base_line.get("ok")):
        out["reason"] = "base_line_not_ok"
        return out
    points = list(base_line.get("points") or [])
    if len(points) < int(min_line_points):
        out["reason"] = "base_line_short"
        return out
    if float(base_score) < float(min_line_score):
        out["reason"] = "line_score_low"
        out["confidence"] = float(base_score)
        return out

    edge_cols = int(max(8, min(int(w), int(edge_columns))))
    x_cut = int(w - edge_cols)
    e_red = 0
    e_yel = 0
    e_tot = 0
    band = int(max(0, score_band_px))
    edge_pts = 0
    end_y = None
    for p in points:
        try:
            x = int(round(float(p.get("x", 0.0))))
            y = int(round(float(p.get("y", 0.0))))
        except Exception:
            continue
        if x < x_cut:
            continue
        if x < 0 or x >= w or y < 0 or y >= h:
            continue
        y0 = max(0, y - band)
        y1 = min(h - 1, y + band)
        e_red += int(np.count_nonzero(red_mask[y0 : y1 + 1, x] > 0))
        e_yel += int(np.count_nonzero(yellow_mask[y0 : y1 + 1, x] > 0))
        e_tot += int((y1 - y0 + 1))
        edge_pts += 1
        end_y = float(y)
    if e_tot <= 0 or edge_pts < 5:
        out["reason"] = "edge_not_enough"
        out["confidence"] = float(base_score)
        return out
    edge_red_ratio = float(e_red) / float(e_tot)
    edge_yellow_ratio = float(e_yel) / float(e_tot)
    out["edge_red_ratio"] = float(edge_red_ratio)
    out["edge_yellow_ratio"] = float(edge_yellow_ratio)
    out["line_end_y"] = end_y

    dom = float(max(1.0, edge_dominance))
    minp = float(max(0.0, edge_min_presence))
    color = "unknown"
    if edge_yellow_ratio >= minp and edge_yellow_ratio >= dom * max(1e-9, edge_red_ratio):
        color = "yellow"
    elif edge_red_ratio >= minp and edge_red_ratio >= dom * max(1e-9, edge_yellow_ratio):
        color = "red"
    else:
        # fallback to dominant line color if edge signal weak but line fit strong
        color = str(base_color)
    out["ok"] = True
    out["color"] = str(color)
    out["confidence"] = float(base_score)
    out["reason"] = "ok"
    return out


def maybe_commit_flip(
    name: str,
    state: PanelState,
    raw_color: str,
    raw_y: Optional[float],
    raw_h: float,
    raw_area: float,
    same_frame_red_ratio: float,
    same_frame_yellow_ratio: float,
    *,
    debounce_s: float,
    min_emit_gap_s: float,
    continuity_tol_px: float,
    line_max_height_px: float,
    line_max_area_px: float,
    transition_seed_ratio: float,
    flip_dominance_margin: float,
    notifier: TelegramNotifier,
    notify_red_only: bool,
) -> Optional[str]:
    tnow = time.time()
    if raw_color not in {"red", "yellow"}:
        return None

    # Candle-body rejection: optional (<=0 disables this gate).
    if float(line_max_height_px) > 0.0 and float(line_max_area_px) > 0.0:
        if float(raw_h) > float(line_max_height_px) or float(raw_area) > float(line_max_area_px):
            return None

    # Continuity gate: optional (<=0 disables this gate).
    if float(continuity_tol_px) > 0.0:
        if raw_y is not None and state.last_line_y >= 0 and raw_color != state.stable_color:
            if abs(float(raw_y) - float(state.last_line_y)) > float(continuity_tol_px):
                return None

    # Transition seed: optional (<=0 disables this gate).
    if float(transition_seed_ratio) > 0.0:
        if raw_color != state.stable_color and state.stable_color in {"red", "yellow"}:
            opp_ratio = float(same_frame_yellow_ratio) if raw_color == "red" else float(same_frame_red_ratio)
            if opp_ratio < float(transition_seed_ratio):
                return None

    # Lightweight anti-cross gate: on flip, require slight color dominance.
    if raw_color != state.stable_color and state.stable_color in {"red", "yellow"}:
        margin = float(max(1.0, flip_dominance_margin))
        rr = float(same_frame_red_ratio)
        yr = float(same_frame_yellow_ratio)
        if raw_color == "red":
            if rr < (margin * max(1e-9, yr)):
                return None
        elif raw_color == "yellow":
            if yr < (margin * max(1e-9, rr)):
                return None

    if state.stable_color == "unknown":
        state.stable_color = raw_color
        state.pending_color = "unknown"
        state.pending_since = 0.0
        if raw_y is not None:
            state.last_line_y = float(raw_y)
        print(f"[INIT] {name.upper()} stable={raw_color} at {now_iso()}")
        return None

    if raw_color == state.stable_color:
        state.pending_color = "unknown"
        state.pending_since = 0.0
        if raw_y is not None:
            if state.last_line_y < 0:
                state.last_line_y = float(raw_y)
            else:
                state.last_line_y = (0.8 * float(state.last_line_y)) + (0.2 * float(raw_y))
        return None

    if state.pending_color != raw_color:
        state.pending_color = raw_color
        state.pending_since = tnow
        return None

    if (tnow - state.pending_since) < debounce_s:
        return None
    if (tnow - state.last_emit_ts) < min_emit_gap_s:
        return None

    prev = state.stable_color
    state.stable_color = raw_color
    state.pending_color = "unknown"
    state.pending_since = 0.0
    state.last_emit_ts = tnow
    if raw_y is not None:
        state.last_line_y = float(raw_y)

    hint = "line_like"
    rr = float(same_frame_red_ratio)
    yr = float(same_frame_yellow_ratio)
    if raw_color == "red" and rr > (2.2 * max(1e-6, yr)):
        hint = "red_dominant_possible_candle_overlap"
    elif raw_color == "yellow" and yr > (2.2 * max(1e-6, rr)):
        hint = "yellow_dominant"
    msg = (
        f"{name.upper()} color flip: {prev.upper()} -> {raw_color.upper()} | "
        f"r={rr:.4f} y={yr:.4f} hint={hint} | {now_iso()}"
    )
    print(f"[FLIP] {msg}")
    if (not notify_red_only) or raw_color == "red":
        notifier.send(msg)
    return msg


def maybe_emit_red_candidate(
    name: str,
    state: PanelState,
    raw_color: str,
    *,
    red_ratio: float,
    yellow_ratio: float,
    notifier: TelegramNotifier,
    enabled: bool,
    candidate_gap_s: float,
) -> None:
    if not enabled:
        return
    if state.stable_color != "yellow" or raw_color != "red":
        return
    tnow = time.time()
    if (tnow - float(state.last_candidate_emit_ts)) < float(max(1.0, candidate_gap_s)):
        return
    state.last_candidate_emit_ts = tnow
    msg = (
        f"{name.upper()} RED candidate: YELLOW -> RED (pending) | "
        f"r={float(red_ratio):.4f} y={float(yellow_ratio):.4f} | {now_iso()}"
    )
    print(f"[CAND] {msg}")
    notifier.send(msg)


def maybe_emit_transient_red_probe(
    name: str,
    state: PanelState,
    *,
    decision_color: str,
    stable_color: str,
    line_edge: Dict[str, Any],
    notifier: TelegramNotifier,
    enabled: bool,
    min_frames: int,
    min_edge_red_ratio: float,
    cooldown_s: float,
) -> None:
    if not enabled:
        return
    color_now = str(decision_color or "").strip().lower()
    stable_now = str(stable_color or "").strip().lower()
    if stable_now not in {"yellow", "red", "unknown"}:
        stable_now = "unknown"
    edge_ok = bool((line_edge or {}).get("ok"))
    edge_red_ratio = float(_to_float_or_none((line_edge or {}).get("edge_red_ratio")) or 0.0)
    confidence = float(_to_float_or_none((line_edge or {}).get("confidence")) or 0.0)

    is_probe_red = bool(color_now == "red" and edge_ok and edge_red_ratio >= float(max(0.0, min_edge_red_ratio)))
    if not is_probe_red:
        state.transient_red_streak = 0
        return
    # Probe is valuable when stable state is still yellow (pre-flip micro red dot).
    if stable_now != "yellow":
        return

    state.transient_red_streak = int(state.transient_red_streak) + 1
    if int(state.transient_red_streak) < int(max(1, min_frames)):
        return

    tnow = time.time()
    if (tnow - float(state.last_transient_red_emit_ts)) < float(max(0.5, cooldown_s)):
        return
    state.last_transient_red_emit_ts = tnow

    msg = (
        f"{name.upper()} transient RED probe (pre-close) | "
        f"stable={stable_now.upper()} edge_red={edge_red_ratio:.4f} conf={confidence:.3f} | {now_iso()}"
    )
    print(f"[PROBE] {msg}")
    notifier.send(msg)


def grab_first_valid_frame(cap, retries: int, sleep_s: float):
    cv2 = _import_cv2_or_exit()
    for _ in range(max(1, retries)):
        ok, frame = cap.read()
        if ok and frame is not None and isinstance(frame, np.ndarray) and frame.size > 0:
            return frame
        time.sleep(sleep_s)
    raise RuntimeError("Could not read initial frame from stream")


def parse_scale(spec: str) -> Tuple[int, int]:
    raw = str(spec or "").strip().lower()
    if "x" not in raw:
        return 1280, 720
    try:
        w_s, h_s = raw.split("x", 1)
        w = max(64, int(w_s))
        h = max(64, int(h_s))
        return w, h
    except Exception:
        return 1280, 720


def open_ffmpeg_pipe(
    *,
    ffmpeg_path: str,
    input_url: str,
    width: int,
    height: int,
    fps: float,
) -> subprocess.Popen:
    cmd = [
        str(ffmpeg_path),
        "-hide_banner",
        "-loglevel",
        "quiet",
        "-nostdin",
        "-i",
        str(input_url),
        "-vf",
        f"scale={int(width)}:{int(height)}",
        "-r",
        str(float(max(0.2, fps))),
        "-f",
        "rawvideo",
        "-pix_fmt",
        "bgr24",
        "pipe:1",
    ]
    env = os.environ.copy()
    for k in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"):
        env[k] = ""
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=10**8,
        env=env,
    )
    return proc


def read_ffmpeg_frame(proc: subprocess.Popen, width: int, height: int) -> Optional[np.ndarray]:
    if proc.stdout is None:
        return None
    need = int(width * height * 3)
    buf = proc.stdout.read(need)
    if not buf or len(buf) != need:
        return None
    frame = np.frombuffer(buf, dtype=np.uint8).reshape((height, width, 3))
    return frame


def grab_first_valid_frame_ffmpeg(proc: subprocess.Popen, width: int, height: int, retries: int, sleep_s: float) -> np.ndarray:
    for _ in range(max(1, retries)):
        frame = read_ffmpeg_frame(proc, width, height)
        if frame is not None and frame.size > 0:
            return frame
        time.sleep(sleep_s)
    raise RuntimeError("Could not read initial frame from ffmpeg pipe")


def calibrate_rois(frame: np.ndarray) -> Dict[str, ROI]:
    cv2 = _import_cv2_or_exit()
    print("[CAL] Select BTC ROI, then press ENTER/SPACE.")
    r1 = cv2.selectROI("Select BTC ROI", frame, showCrosshair=True, fromCenter=False)
    cv2.destroyWindow("Select BTC ROI")
    print("[CAL] Select ETH ROI, then press ENTER/SPACE.")
    r2 = cv2.selectROI("Select ETH ROI", frame, showCrosshair=True, fromCenter=False)
    cv2.destroyWindow("Select ETH ROI")
    btc = ROI(x=int(r1[0]), y=int(r1[1]), w=max(1, int(r1[2])), h=max(1, int(r1[3])))
    eth = ROI(x=int(r2[0]), y=int(r2[1]), w=max(1, int(r2[2])), h=max(1, int(r2[3])))
    return {"btc": btc, "eth": eth}


def build_auto_two_panel_rois(
    frame_w: int,
    frame_h: int,
    *,
    panel_pad_pct: float,
    y_top_pct: float,
    y_bottom_pct: float,
) -> Dict[str, ROI]:
    pad_x = int(max(0, min(frame_w * 0.2, frame_w * max(0.0, panel_pad_pct))))
    y1 = int(max(0, min(frame_h - 2, frame_h * max(0.0, min(1.0, y_top_pct)))))
    y2 = int(max(y1 + 1, min(frame_h, frame_h * max(0.0, min(1.0, y_bottom_pct)))))
    usable_h = max(1, y2 - y1)
    half = frame_w // 2

    # User said: left-for-user/right-for-assistant is BTC, so BTC is right panel.
    left_roi = ROI(x=pad_x, y=y1, w=max(1, half - (2 * pad_x)), h=usable_h).clamp(frame_w, frame_h)
    right_roi = ROI(x=half + pad_x, y=y1, w=max(1, frame_w - half - (2 * pad_x)), h=usable_h).clamp(frame_w, frame_h)
    return {"btc": right_roi, "eth": left_roi}


def draw_debug(
    frame: np.ndarray,
    rois: Dict[str, ROI],
    raw_colors: Dict[str, str],
    stable_colors: Dict[str, str],
    ratios: Dict[str, Tuple[float, float]],
    line_debug: Optional[Dict[str, Dict[str, Any]]] = None,
) -> np.ndarray:
    cv2 = _import_cv2_or_exit()
    out = frame.copy()
    for name in ("btc", "eth"):
        roi = rois[name]
        x1, y1 = roi.x, roi.y
        x2, y2 = roi.x + roi.w, roi.y + roi.h
        cv2.rectangle(out, (x1, y1), (x2, y2), (200, 200, 200), 2)
        rr, yr = ratios.get(name, (0.0, 0.0))
        txt = (
            f"{name.upper()} raw={raw_colors.get(name,'?')} stable={stable_colors.get(name,'?')} "
            f"red={rr:.3f} yel={yr:.3f}"
        )
        cv2.putText(out, txt, (x1, max(20, y1 - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
        if isinstance(line_debug, dict):
            ldbg = line_debug.get(name) or {}
            if isinstance(ldbg, dict) and bool(ldbg.get("ok")) and isinstance(ldbg.get("points"), list):
                pts = []
                for p in ldbg.get("points", []):
                    try:
                        px = int(round(float(p.get("x", 0.0)))) + int(x1)
                        py = int(round(float(p.get("y", 0.0)))) + int(y1)
                        pts.append((px, py))
                    except Exception:
                        continue
                if len(pts) >= 2:
                    col = (0, 255, 255) if str(ldbg.get("color", "")).lower() == "yellow" else (0, 0, 255)
                    cv2.polylines(out, [np.array(pts, dtype=np.int32)], isClosed=False, color=col, thickness=2)
    return out


def run(args: argparse.Namespace) -> int:
    cv2 = _import_cv2_or_exit()
    stream_url, title = resolve_youtube_stream(args.youtube_url)
    print(f"[OK] Stream resolved. title={title!r}")

    reader_mode = "opencv"
    cap = None
    ffmpeg_proc: Optional[subprocess.Popen] = None
    ff_w, ff_h = parse_scale(args.ffmpeg_scale)

    if not bool(args.force_ffmpeg):
        cap = cv2.VideoCapture(stream_url)
    if cap is not None and cap.isOpened():
        first = grab_first_valid_frame(cap, retries=60, sleep_s=0.25)
    else:
        if cap is not None:
            try:
                cap.release()
            except Exception:
                pass
        if not bool(args.ffmpeg_fallback):
            print("[ERR] Could not open stream capture.")
            return 2
        reader_mode = "ffmpeg"
        ffmpeg_proc = open_ffmpeg_pipe(
            ffmpeg_path=args.ffmpeg_path,
            input_url=stream_url,
            width=ff_w,
            height=ff_h,
            fps=float(args.ffmpeg_fps),
        )
        first = grab_first_valid_frame_ffmpeg(ffmpeg_proc, ff_w, ff_h, retries=80, sleep_s=0.25)
        print(f"[OK] Using ffmpeg fallback reader ({ff_w}x{ff_h})")

    fh, fw = first.shape[:2]
    print(f"[OK] First frame size: {fw}x{fh}")

    rois: Dict[str, ROI]
    if args.roi_file:
        rois = load_roi_file(args.roi_file)
    elif args.btc_roi and args.eth_roi:
        rois = {"btc": parse_roi(args.btc_roi), "eth": parse_roi(args.eth_roi)}
    elif bool(args.auto_two_panels):
        rois = build_auto_two_panel_rois(
            fw,
            fh,
            panel_pad_pct=float(args.auto_panel_pad_pct),
            y_top_pct=float(args.auto_y_top_pct),
            y_bottom_pct=float(args.auto_y_bottom_pct),
        )
    elif args.calibrate:
        rois = calibrate_rois(first)
    else:
        print(
            "[ERR] You must provide ROI settings: --roi-file OR --btc-roi/--eth-roi OR "
            "--auto-two-panels OR --calibrate"
        )
        return 3

    rois = {
        "btc": rois["btc"].clamp(fw, fh),
        "eth": rois["eth"].clamp(fw, fh),
    }
    print(f"[ROI] BTC={rois['btc']} ETH={rois['eth']}")
    if args.save_roi_file:
        save_roi_file(args.save_roi_file, rois)

    notifier = TelegramNotifier(
        token=str(args.telegram_bot_token or "").strip(),
        chat_id=str(args.telegram_chat_id or "").strip(),
    )
    if notifier.enabled:
        notifier.send(f"YT colorflip watcher started | title={title}")

    states = {"btc": PanelState(), "eth": PanelState()}
    frame_idx = 0
    last_debug = 0.0
    started_ts = time.time()
    flips_count = {"btc": 0, "eth": 0}
    sample_count = {"btc": 0, "eth": 0}
    last_line_debug_ts = 0.0
    line_debug_latest: Dict[str, Dict[str, Any]] = {"btc": {}, "eth": {}}

    try:
        while True:
            if float(args.max_seconds) > 0 and (time.time() - started_ts) >= float(args.max_seconds):
                print(f"[OK] max_seconds reached ({float(args.max_seconds):.1f}s), stopping.")
                break

            frame = None
            if reader_mode == "opencv":
                ok, raw_frame = cap.read() if cap is not None else (False, None)
                frame = raw_frame if ok else None
            else:
                frame = read_ffmpeg_frame(ffmpeg_proc, ff_w, ff_h) if ffmpeg_proc is not None else None
            if frame is None:
                print("[WARN] Frame read failed, attempting reconnect...")
                time.sleep(1.0)
                if reader_mode == "opencv":
                    try:
                        if cap is not None:
                            cap.release()
                    except Exception:
                        pass
                    cap = cv2.VideoCapture(stream_url)
                else:
                    try:
                        if ffmpeg_proc is not None:
                            ffmpeg_proc.kill()
                    except Exception:
                        pass
                    ffmpeg_proc = open_ffmpeg_pipe(
                        ffmpeg_path=args.ffmpeg_path,
                        input_url=stream_url,
                        width=ff_w,
                        height=ff_h,
                        fps=float(args.ffmpeg_fps),
                    )
                continue

            frame_idx += 1
            if args.sample_every_n > 1 and (frame_idx % args.sample_every_n) != 0:
                continue

            fh, fw = frame.shape[:2]
            btc_roi = rois["btc"].clamp(fw, fh)
            eth_roi = rois["eth"].clamp(fw, fh)
            rois["btc"] = btc_roi
            rois["eth"] = eth_roi

            btc_crop = frame[btc_roi.y : btc_roi.y + btc_roi.h, btc_roi.x : btc_roi.x + btc_roi.w]
            eth_crop = frame[eth_roi.y : eth_roi.y + eth_roi.h, eth_roi.x : eth_roi.x + eth_roi.w]

            (
                btc_raw,
                btc_r,
                btc_y,
                btc_red_y,
                btc_yel_y,
                btc_red_h,
                btc_yel_h,
                btc_red_area,
                btc_yel_area,
            ) = classify_red_yellow(
                btc_crop,
                min_ratio=args.min_color_ratio,
                edge_focus_px=int(args.edge_focus_px),
                edge_weight=float(args.edge_weight),
                row_peak_weight=float(args.row_peak_weight),
            )
            (
                eth_raw,
                eth_r,
                eth_y,
                eth_red_y,
                eth_yel_y,
                eth_red_h,
                eth_yel_h,
                eth_red_area,
                eth_yel_area,
            ) = classify_red_yellow(
                eth_crop,
                min_ratio=args.min_color_ratio,
                edge_focus_px=int(args.edge_focus_px),
                edge_weight=float(args.edge_weight),
                row_peak_weight=float(args.row_peak_weight),
            )
            sample_count["btc"] += 1
            sample_count["eth"] += 1

            need_line = bool(args.debug_line_extract) or str(args.flip_color_source).strip().lower() in {"line", "hybrid"}
            line_edge_btc: Dict[str, Any] = {}
            line_edge_eth: Dict[str, Any] = {}
            if need_line:
                line_debug_latest["btc"] = extract_trend_line_points(
                    btc_crop,
                    color_name=btc_raw if btc_raw in {"red", "yellow"} else states["btc"].stable_color,
                    min_columns=int(args.debug_line_min_columns),
                    smooth_window=int(args.debug_line_smooth_window),
                    max_gap_columns=int(args.debug_line_max_gap_columns),
                )
                line_debug_latest["eth"] = extract_trend_line_points(
                    eth_crop,
                    color_name=eth_raw if eth_raw in {"red", "yellow"} else states["eth"].stable_color,
                    min_columns=int(args.debug_line_min_columns),
                    smooth_window=int(args.debug_line_smooth_window),
                    max_gap_columns=int(args.debug_line_max_gap_columns),
                )
                line_edge_btc = detect_line_local_edge_color(
                    btc_crop,
                    min_columns=int(args.debug_line_min_columns),
                    smooth_window=int(args.debug_line_smooth_window),
                    max_gap_columns=int(args.debug_line_max_gap_columns),
                    score_band_px=int(args.line_score_band_px),
                    edge_columns=int(args.line_edge_columns),
                    edge_dominance=float(args.line_edge_dominance),
                    edge_min_presence=float(args.line_edge_min_presence),
                    min_line_score=float(args.line_min_score),
                    min_line_coverage=float(args.line_min_coverage),
                    min_line_points=int(args.line_min_points),
                )
                line_edge_eth = detect_line_local_edge_color(
                    eth_crop,
                    min_columns=int(args.debug_line_min_columns),
                    smooth_window=int(args.debug_line_smooth_window),
                    max_gap_columns=int(args.debug_line_max_gap_columns),
                    score_band_px=int(args.line_score_band_px),
                    edge_columns=int(args.line_edge_columns),
                    edge_dominance=float(args.line_edge_dominance),
                    edge_min_presence=float(args.line_edge_min_presence),
                    min_line_score=float(args.line_min_score),
                    min_line_coverage=float(args.line_min_coverage),
                    min_line_points=int(args.line_min_points),
                )

            source_mode = str(args.flip_color_source).strip().lower()

            def _pick_color(
                raw_color: str,
                red_ratio: float,
                yellow_ratio: float,
                line_edge: Dict[str, Any],
            ) -> Tuple[str, Optional[float], float, float]:
                lc = str((line_edge or {}).get("color") or "unknown").lower()
                lok = bool((line_edge or {}).get("ok"))
                ly = _to_float_or_none((line_edge or {}).get("line_end_y"))
                ler = float(_to_float_or_none((line_edge or {}).get("edge_red_ratio")) or 0.0)
                ley = float(_to_float_or_none((line_edge or {}).get("edge_yellow_ratio")) or 0.0)
                if source_mode == "line":
                    if lok and lc in {"red", "yellow"}:
                        return lc, ly, ler, ley
                    return raw_color, None, float(red_ratio), float(yellow_ratio)
                if source_mode == "hybrid":
                    if lok and lc in {"red", "yellow"}:
                        return lc, ly, ler, ley
                    return raw_color, None, float(red_ratio), float(yellow_ratio)
                return raw_color, None, float(red_ratio), float(yellow_ratio)

            btc_decision_color, btc_decision_y, btc_decision_r, btc_decision_yel = _pick_color(
                btc_raw,
                btc_r,
                btc_y,
                line_edge_btc,
            )
            eth_decision_color, eth_decision_y, eth_decision_r, eth_decision_yel = _pick_color(
                eth_raw,
                eth_r,
                eth_y,
                line_edge_eth,
            )

            maybe_emit_transient_red_probe(
                "btc",
                states["btc"],
                decision_color=btc_decision_color,
                stable_color=states["btc"].stable_color,
                line_edge=line_edge_btc,
                notifier=notifier,
                enabled=bool(args.notify_transient_red_probe),
                min_frames=int(args.transient_probe_min_frames),
                min_edge_red_ratio=float(args.transient_probe_min_edge_red_ratio),
                cooldown_s=float(args.transient_probe_cooldown_seconds),
            )
            maybe_emit_transient_red_probe(
                "eth",
                states["eth"],
                decision_color=eth_decision_color,
                stable_color=states["eth"].stable_color,
                line_edge=line_edge_eth,
                notifier=notifier,
                enabled=bool(args.notify_transient_red_probe),
                min_frames=int(args.transient_probe_min_frames),
                min_edge_red_ratio=float(args.transient_probe_min_edge_red_ratio),
                cooldown_s=float(args.transient_probe_cooldown_seconds),
            )

            btc_flip = maybe_commit_flip(
                "btc",
                states["btc"],
                btc_decision_color,
                (btc_decision_y if btc_decision_y is not None else (btc_red_y if btc_raw == "red" else btc_yel_y)),
                (btc_red_h if btc_decision_color == btc_raw and btc_raw == "red" else btc_yel_h if btc_decision_color == btc_raw and btc_raw == "yellow" else 0.0),
                (btc_red_area if btc_decision_color == btc_raw and btc_raw == "red" else btc_yel_area if btc_decision_color == btc_raw and btc_raw == "yellow" else 0.0),
                same_frame_red_ratio=btc_decision_r,
                same_frame_yellow_ratio=btc_decision_yel,
                debounce_s=args.debounce_seconds,
                min_emit_gap_s=args.min_emit_gap_seconds,
                continuity_tol_px=args.continuity_tol_px,
                line_max_height_px=args.line_max_height_px,
                line_max_area_px=args.line_max_area_px,
                transition_seed_ratio=args.transition_seed_ratio,
                flip_dominance_margin=args.flip_dominance_margin,
                notifier=notifier,
                notify_red_only=bool(args.notify_red_only),
            )
            eth_flip = maybe_commit_flip(
                "eth",
                states["eth"],
                eth_decision_color,
                (eth_decision_y if eth_decision_y is not None else (eth_red_y if eth_raw == "red" else eth_yel_y)),
                (eth_red_h if eth_decision_color == eth_raw and eth_raw == "red" else eth_yel_h if eth_decision_color == eth_raw and eth_raw == "yellow" else 0.0),
                (eth_red_area if eth_decision_color == eth_raw and eth_raw == "red" else eth_yel_area if eth_decision_color == eth_raw and eth_raw == "yellow" else 0.0),
                same_frame_red_ratio=eth_decision_r,
                same_frame_yellow_ratio=eth_decision_yel,
                debounce_s=args.debounce_seconds,
                min_emit_gap_s=args.min_emit_gap_seconds,
                continuity_tol_px=args.continuity_tol_px,
                line_max_height_px=args.line_max_height_px,
                line_max_area_px=args.line_max_area_px,
                transition_seed_ratio=args.transition_seed_ratio,
                flip_dominance_margin=args.flip_dominance_margin,
                notifier=notifier,
                notify_red_only=bool(args.notify_red_only),
            )
            maybe_emit_red_candidate(
                "btc",
                states["btc"],
                btc_decision_color,
                red_ratio=btc_decision_r,
                yellow_ratio=btc_decision_yel,
                notifier=notifier,
                enabled=bool(args.notify_candidates),
                candidate_gap_s=float(args.candidate_gap_seconds),
            )
            maybe_emit_red_candidate(
                "eth",
                states["eth"],
                eth_decision_color,
                red_ratio=eth_decision_r,
                yellow_ratio=eth_decision_yel,
                notifier=notifier,
                enabled=bool(args.notify_candidates),
                candidate_gap_s=float(args.candidate_gap_seconds),
            )
            if btc_flip:
                flips_count["btc"] += 1
            if eth_flip:
                flips_count["eth"] += 1

            if args.show_preview:
                dbg = draw_debug(
                    frame,
                    rois,
                    raw_colors={"btc": btc_raw, "eth": eth_raw},
                    stable_colors={
                        "btc": states["btc"].stable_color,
                        "eth": states["eth"].stable_color,
                    },
                    ratios={"btc": (btc_r, btc_y), "eth": (eth_r, eth_y)},
                    line_debug=line_debug_latest if bool(args.debug_line_extract) else None,
                )
                cv2.imshow("YT ColorFlip Watcher (press q to quit)", dbg)
                key = cv2.waitKey(1) & 0xFF
                if key == ord("q"):
                    break
            else:
                now_t = time.time()
                if now_t - last_debug >= max(1.0, args.log_every_seconds):
                    last_debug = now_t
                    print(
                        "[STATE] "
                        f"BTC raw={btc_raw} dec={btc_decision_color} stable={states['btc'].stable_color} r={btc_r:.3f} y={btc_y:.3f} | "
                        f"ETH raw={eth_raw} dec={eth_decision_color} stable={states['eth'].stable_color} r={eth_r:.3f} y={eth_y:.3f}"
                    )
                    if bool(args.debug_line_extract):
                        bdbg = line_debug_latest.get("btc") or {}
                        edbg = line_debug_latest.get("eth") or {}
                        def _fmt(d: Dict[str, Any]) -> str:
                            if not bool(d.get("ok")):
                                return f"nok:{str(d.get('reason') or '-')}"
                            return (
                                f"ok cov={float(d.get('coverage') or 0.0):.2f} "
                                f"slope={float(d.get('slope_px_per_col') or 0.0):.4f} "
                                f"pts={len(d.get('points') or [])}"
                            )
                        print(f"[LINE] BTC {_fmt(bdbg)} edge={str((line_edge_btc or {}).get('color') or 'unknown')} conf={float((line_edge_btc or {}).get('confidence') or 0.0):.3f} | ETH {_fmt(edbg)} edge={str((line_edge_eth or {}).get('color') or 'unknown')} conf={float((line_edge_eth or {}).get('confidence') or 0.0):.3f}")

            if bool(args.debug_line_extract) and str(args.debug_line_json_file or "").strip():
                now_t = time.time()
                if (now_t - float(last_line_debug_ts)) >= float(max(0.5, args.debug_line_every_seconds)):
                    last_line_debug_ts = now_t
                    payload = {
                        "ts_utc": now_iso(),
                        "btc": line_debug_latest.get("btc") or {},
                        "eth": line_debug_latest.get("eth") or {},
                    }
                    try:
                        with open(str(args.debug_line_json_file), "w", encoding="utf-8") as f:
                            json.dump(payload, f, ensure_ascii=True, indent=2)
                    except Exception as exc:
                        print(f"[WARN] debug line json write failed: {exc}")
    except KeyboardInterrupt:
        pass
    finally:
        try:
            if cap is not None:
                cap.release()
        except Exception:
            pass
        try:
            if ffmpeg_proc is not None:
                ffmpeg_proc.kill()
        except Exception:
            pass
        try:
            cv2.destroyAllWindows()
        except Exception:
            pass

    if notifier.enabled:
        notifier.send("YT colorflip watcher stopped.")
    elapsed = max(0.1, time.time() - started_ts)
    print(
        "[SUMMARY] "
        f"elapsed={elapsed:.1f}s "
        f"samples(BTC/ETH)={sample_count['btc']}/{sample_count['eth']} "
        f"flips(BTC/ETH)={flips_count['btc']}/{flips_count['eth']}"
    )
    print("[OK] watcher stopped")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Track RED/YELLOW line flips in a YouTube livestream.")
    p.add_argument("--youtube-url", required=True, help="YouTube livestream URL")
    p.add_argument("--roi-file", default="", help="Path to ROI json with keys: btc, eth")
    p.add_argument("--save-roi-file", default="", help="Save selected ROI config to json")
    p.add_argument("--btc-roi", default="", help="BTC ROI as x,y,w,h")
    p.add_argument("--eth-roi", default="", help="ETH ROI as x,y,w,h")
    p.add_argument("--auto-two-panels", action="store_true", help="Auto-build 2 panel ROI (BTC=right, ETH=left)")
    p.add_argument("--auto-panel-pad-pct", type=float, default=0.02, help="Auto ROI horizontal padding ratio")
    p.add_argument("--auto-y-top-pct", type=float, default=0.18, help="Auto ROI top ratio")
    p.add_argument("--auto-y-bottom-pct", type=float, default=0.86, help="Auto ROI bottom ratio")
    p.add_argument("--calibrate", action="store_true", help="Interactively pick BTC and ETH ROI boxes")
    p.add_argument("--show-preview", action="store_true", help="Show live debug window with ROI overlays")
    p.add_argument("--sample-every-n", type=int, default=3, help="Process every Nth frame")
    p.add_argument("--ffmpeg-fallback", action="store_true", default=True, help="Use ffmpeg rawvideo fallback if OpenCV capture fails")
    p.add_argument("--force-ffmpeg", action="store_true", help="Force ffmpeg reader (skip OpenCV capture)")
    p.add_argument("--ffmpeg-path", default="ffmpeg", help="ffmpeg executable path")
    p.add_argument("--ffmpeg-scale", default="1280x720", help="ffmpeg output frame size WxH")
    p.add_argument("--ffmpeg-fps", type=float, default=4.0, help="ffmpeg output FPS for analysis")
    p.add_argument("--debounce-seconds", type=float, default=0.5, help="Required stable duration for flip commit")
    p.add_argument("--min-emit-gap-seconds", type=float, default=2.0, help="Minimum seconds between emitted flips")
    p.add_argument("--min-color-ratio", type=float, default=0.02, help="Minimum mask ratio to accept a color")
    p.add_argument("--edge-focus-px", type=int, default=16, help="Right-edge strip width (px) for tiny flip-dot emphasis")
    p.add_argument("--edge-weight", type=float, default=0.9, help="Weight of right-edge strip [0..1]")
    p.add_argument("--row-peak-weight", type=float, default=1.25, help="Weight for horizontal line-density score (higher reduces candle bias)")
    p.add_argument("--flip-color-source", default="hybrid", choices=["raw", "line", "hybrid"], help="Flip color source: raw area, line-local edge, or hybrid fallback")
    p.add_argument("--line-score-band-px", type=int, default=2, help="Band radius used while scoring line-local color")
    p.add_argument("--line-edge-columns", type=int, default=40, help="Right-edge columns used for line endpoint color decision")
    p.add_argument("--line-edge-dominance", type=float, default=1.08, help="Required dominance factor for edge color decision")
    p.add_argument("--line-edge-min-presence", type=float, default=0.05, help="Minimum edge color presence ratio for decisive edge color")
    p.add_argument("--line-min-score", type=float, default=0.52, help="Minimum line score to accept line-local color")
    p.add_argument("--line-min-coverage", type=float, default=0.45, help="Minimum extracted line coverage ratio")
    p.add_argument("--line-min-points", type=int, default=120, help="Minimum extracted line points")
    p.add_argument("--continuity-tol-px", type=float, default=0.0, help="Max y-distance from previous line for new color commit (0=disabled)")
    p.add_argument("--line-max-height-px", type=float, default=0.0, help="Reject components taller than this (candle-body filter, 0=disabled)")
    p.add_argument("--line-max-area-px", type=float, default=0.0, help="Reject components larger than this (candle-body filter, 0=disabled)")
    p.add_argument("--transition-seed-ratio", type=float, default=0.0, help="Require opposite color context ratio on flip (0=disabled)")
    p.add_argument("--flip-dominance-margin", type=float, default=1.08, help="On flip, require new color ratio to dominate old color by this factor")
    p.add_argument("--notify-red-only", action="store_true", help="Send Telegram only for flips ending in RED")
    p.add_argument("--notify-candidates", action="store_true", help="Send Telegram for YELLOW->RED pending candidates")
    p.add_argument("--candidate-gap-seconds", type=float, default=20.0, help="Min seconds between candidate notifications per panel")
    p.add_argument("--notify-transient-red-probe", action="store_true", help="Send pre-close transient red-dot alerts while stable color is still yellow")
    p.add_argument("--transient-probe-min-frames", type=int, default=1, help="Consecutive red-probe frames required before alert")
    p.add_argument("--transient-probe-min-edge-red-ratio", type=float, default=0.10, help="Minimum line-edge red ratio for transient probe alerts")
    p.add_argument("--transient-probe-cooldown-seconds", type=float, default=8.0, help="Cooldown for transient probe alerts per panel")
    p.add_argument("--max-seconds", type=float, default=0.0, help="Stop automatically after N seconds (0=run forever)")
    p.add_argument("--log-every-seconds", type=float, default=5.0, help="State log interval in headless mode")
    p.add_argument("--debug-line-extract", action="store_true", help="Extract and debug full red/yellow trend polyline (does not affect flip logic)")
    p.add_argument("--debug-line-json-file", default="", help="Write latest extracted BTC/ETH line payload to this json path")
    p.add_argument("--debug-line-every-seconds", type=float, default=2.0, help="Debug line json write interval")
    p.add_argument("--debug-line-min-columns", type=int, default=30, help="Minimum color columns to accept extracted line")
    p.add_argument("--debug-line-smooth-window", type=int, default=7, help="Smoothing window for extracted line points")
    p.add_argument("--debug-line-max-gap-columns", type=int, default=14, help="Max column gap to bridge during interpolation")
    p.add_argument("--telegram-bot-token", default="", help="Telegram bot token")
    p.add_argument("--telegram-chat-id", default="", help="Telegram chat id")
    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(run(args))


if __name__ == "__main__":
    raise SystemExit(main())
