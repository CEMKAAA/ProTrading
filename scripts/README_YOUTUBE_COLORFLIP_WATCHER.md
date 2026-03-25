# YouTube ColorFlip Watcher (BTC/ETH)

This script tracks RED/YELLOW line flips from a YouTube livestream using ROI detection.

File:
- `scripts/youtube_colorflip_watcher.py`

## Install

```bash
pip install yt-dlp opencv-python requests
```

## First run (calibrate ROI)

```bash
python scripts/youtube_colorflip_watcher.py \
  --youtube-url "https://www.youtube.com/watch?v=fFrLWCCUY68" \
  --calibrate \
  --show-preview \
  --save-roi-file scripts/yt_rois.json
```

Steps:
1. Select BTC line box.
2. Select ETH line box.
3. Press `q` in preview window to exit.

## Run with saved ROI

```bash
python scripts/youtube_colorflip_watcher.py \
  --youtube-url "https://www.youtube.com/watch?v=fFrLWCCUY68" \
  --roi-file scripts/yt_rois.json \
  --show-preview
```

## Quick test without manual ROI (auto panels)

BTC is assumed on right panel, ETH on left panel.

```bash
python scripts/youtube_colorflip_watcher.py \
  --youtube-url "https://www.youtube.com/watch?v=fFrLWCCUY68" \
  --auto-two-panels \
  --max-seconds 120
```

## Tiny edge flip-dot sensitivity

Use right-edge emphasis:
- `--edge-focus-px 16` (or 20/24)
- `--edge-weight 0.9`

Example:

```bash
python scripts/youtube_colorflip_watcher.py \
  --youtube-url "https://www.youtube.com/watch?v=fFrLWCCUY68" \
  --roi-file scripts/yt_rois.json \
  --edge-focus-px 20 \
  --edge-weight 0.92 \
  --debounce-seconds 1.2
```

## Telegram alerts (optional)

```bash
python scripts/youtube_colorflip_watcher.py \
  --youtube-url "https://www.youtube.com/watch?v=fFrLWCCUY68" \
  --roi-file scripts/yt_rois.json \
  --telegram-bot-token "<TOKEN>" \
  --telegram-chat-id "<CHAT_ID>"
```

## Notes

- This is video-based detection, not broker/feed-native signal.
- Compression and stream lag can produce false flips.
- Tune these parameters for stability:
  - `--debounce-seconds`
  - `--min-emit-gap-seconds`
  - `--min-color-ratio`
  - `--sample-every-n`
