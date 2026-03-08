"""Background worker for async workbench copilot LLM jobs."""

from __future__ import annotations

import logging
import threading
import time
from datetime import datetime
from typing import Any, Dict, List, Optional

from ..models.database import SessionLocal, WorkbenchCopilotJobModel
from ..core.workbench_copilot.advice_engine import generate_advices
from ..core.workbench_copilot.llm_advisor import generate_advices_with_provider_chain
from .workbench_copilot_runtime import get_runtime as get_copilot_runtime


logger = logging.getLogger(__name__)


def _safe_int(v: Any, default: int = 0) -> int:
    try:
        if v is None:
            return int(default)
        return int(v)
    except Exception:
        return int(default)


class WorkbenchCopilotWorkerService:
    """Processes queued copilot advice jobs without blocking replay endpoints."""

    def __init__(self, poll_interval_sec: float = 0.5) -> None:
        self.poll_interval_sec = max(0.1, float(poll_interval_sec))
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, name="workbench-copilot-worker", daemon=True)
        self._thread.start()
        logger.info("Workbench copilot worker started")

    def stop(self) -> None:
        self._stop.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        logger.info("Workbench copilot worker stopped")

    def _claim_next_job(self) -> Optional[int]:
        db = SessionLocal()
        try:
            row = (
                db.query(WorkbenchCopilotJobModel)
                .filter(WorkbenchCopilotJobModel.status == "PENDING")
                .order_by(WorkbenchCopilotJobModel.priority.desc(), WorkbenchCopilotJobModel.id.asc())
                .first()
            )
            if row is None:
                return None
            job_id = int(row.id)
            attempts = _safe_int(row.attempts, 0) + 1
            updated = (
                db.query(WorkbenchCopilotJobModel)
                .filter(WorkbenchCopilotJobModel.id == job_id)
                .filter(WorkbenchCopilotJobModel.status == "PENDING")
                .update(
                    {
                        "status": "RUNNING",
                        "started_at": datetime.utcnow(),
                        "attempts": attempts,
                    },
                    synchronize_session=False,
                )
            )
            db.commit()
            if int(updated or 0) != 1:
                return None
            return job_id
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def _process_job(self, job_id: int) -> None:
        db = SessionLocal()
        try:
            job = db.query(WorkbenchCopilotJobModel).get(int(job_id))
            if job is None or str(job.status or "").upper() != "RUNNING":
                return

            payload = job.payload_json if isinstance(job.payload_json, dict) else {}
            snapshot = payload.get("snapshot") if isinstance(payload.get("snapshot"), dict) else {}
            events = payload.get("events") if isinstance(payload.get("events"), list) else []
            mode = str(payload.get("mode") or "ADVISE")
            provider = str(payload.get("provider") or "deterministic")
            model_label = str(payload.get("model_label") or "")
            config = payload.get("config") if isinstance(payload.get("config"), dict) else {}
            runtime_cfg = get_copilot_runtime(int(job.copilot_session_id))
            if runtime_cfg:
                config = {**config, **runtime_cfg}

            deterministic_advices = generate_advices(
                snapshot=snapshot,
                events=events,
                mode=mode,
                config=config,
            )
            advices, provider_meta = generate_advices_with_provider_chain(
                snapshot=snapshot,
                events=events,
                mode=mode,
                provider=provider,
                model_label=model_label,
                config=config,
                deterministic_advices=deterministic_advices,
            )
            job.result_json = {
                "advices": advices,
                "provider_meta": provider_meta,
                "events_count": len(events),
            }
            job.status = "COMPLETED"
            job.error = None
            job.finished_at = datetime.utcnow()
            db.commit()
        except Exception as exc:
            db.rollback()
            try:
                job = db.query(WorkbenchCopilotJobModel).get(int(job_id))
                if job is not None:
                    job.status = "FAILED"
                    job.error = f"{type(exc).__name__}: {str(exc)[:400]}"
                    job.finished_at = datetime.utcnow()
                    db.commit()
            except Exception:
                db.rollback()
            logger.warning("Workbench copilot job %s failed: %s", job_id, exc)
        finally:
            db.close()

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                job_id = self._claim_next_job()
                if job_id is None:
                    time.sleep(self.poll_interval_sec)
                    continue
                self._process_job(job_id)
            except Exception as exc:
                logger.warning("Workbench copilot worker loop warning: %s", exc)
                time.sleep(self.poll_interval_sec)
