"""
Process-wide startup patch for constrained environments with broken system temp dirs.

Python auto-imports ``sitecustomize`` on startup (if present on ``sys.path``).
We use that hook to guarantee a writable temp directory exists before modules
like ``pytest`` initialize capture/tempfile internals.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path


def _is_usable_dir(path: str) -> bool:
    p = Path(path)
    try:
        p.mkdir(parents=True, exist_ok=True)
        probe = p / ".tmp_probe"
        with probe.open("w", encoding="utf-8") as fh:
            fh.write("ok")
        probe.unlink(missing_ok=True)
        return True
    except Exception:
        return False


def _ensure_tempdir() -> None:
    # Respect explicitly configured env if usable.
    for key in ("TMPDIR", "TEMP", "TMP"):
        val = str(os.getenv(key) or "").strip()
        if val and _is_usable_dir(val):
            tempfile.tempdir = val
            return

    # Create a project-local fallback.
    fallback = str((Path(__file__).resolve().parent / ".tmp").resolve())
    if _is_usable_dir(fallback):
        os.environ["TMPDIR"] = fallback
        os.environ["TEMP"] = fallback
        os.environ["TMP"] = fallback
        tempfile.tempdir = fallback


_ensure_tempdir()

