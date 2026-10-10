export type AuditProgressSnapshot = {
  state: string;
  createdAt?: number;
  updatedAt?: number;
  progress: {phase: string; processed: number; total: number | null; detail?: string} | null;
};

export function auditProgressModel(job: AuditProgressSnapshot, now: number, terminalError = '') {
  const active = job.state === 'queued' || job.state === 'running';
  const completed = job.state === 'completed';
  const phase = job.progress?.phase ?? 'preparing';
  const step = completed ? 3 : phase === 'uploading' ? 2 : phase === 'replaying' ? 1 : 0;
  const total = job.progress?.total;
  const processed = job.progress?.processed;
  const measured = Number.isFinite(total) && Number(total) > 0
    && Number.isFinite(processed) && Number(processed) >= 0;
  // Native history preparation has no byte total. Never infer one from elapsed time.
  const percent = completed ? 100 : measured && step > 0
    ? Math.min(100, Math.max(0, Math.round(Number(processed) / Number(total) * 100))) : null;
  const paused = active && terminalError === 'AUDIT_AUTHORITY_EXPIRED';
  const label = completed ? 'Audit complete' : !active ? 'Audit stopped'
    : paused ? 'Waiting for renewed audit authority'
    : job.state === 'queued' ? 'Waiting for MT5'
    : phase === 'downloading' ? 'Downloading / building broker history'
    : phase === 'replaying' ? 'Replaying trades'
    : phase === 'uploading' ? 'Receiving the audit result' : 'Preparing broker history';
  const end = active ? now : job.updatedAt;
  const elapsedMs = Number.isFinite(job.createdAt) && Number.isFinite(end)
    ? Math.max(0, Number(end) - Number(job.createdAt)) : null;
  const elapsed = elapsedMs === null ? '--:--' : `${String(Math.floor(elapsedMs / 60000)).padStart(2, '0')}:${String(Math.floor(elapsedMs / 1000) % 60).padStart(2, '0')}`;
  return {active, completed, phase, step, percent, paused, label, elapsed};
}
