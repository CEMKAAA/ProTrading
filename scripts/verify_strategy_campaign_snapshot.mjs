import { resolve, join, relative } from 'node:path';
import { readFileSync, writeFileSync, existsSync, renameSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { verifiedSnapshot } from './watch_strategy_window_refresh.mjs';
const sha = file => createHash('sha256').update(readFileSync(file)).digest('hex');

// An already running campaign executes frozen staged binaries, not newly edited
// production sources. This exception is bound to that coordinator only; rolling
// refresh and new campaigns still require canonical-source reverification.
export function checkFrozenCoordinator(proof, processRecord, parentPid) {
  if (proof.pid !== parentPid || processRecord.pid !== parentPid
      || proof.startedUtc !== processRecord.startedUtc) throw Error('FROZEN_COORDINATOR_CHANGED');
}
export function frozenSnapshot(out, parentPid) {
  const proof = JSON.parse(readFileSync(join(out, 'active-frozen-snapshot.json'), 'utf8'));
  const processRecord = JSON.parse(readFileSync(join(out, 'campaign-process.json'), 'utf8'));
  checkFrozenCoordinator(proof, processRecord, parentPid);
  for (const file of proof.files) {
    const path = resolve(out, file.name);
    if (!path.startsWith(resolve(out) + '\\') || sha(path) !== file.sha256)
      throw Error('FROZEN_ENGINE_CHANGED');
  }
  const manifest = JSON.parse(readFileSync(join(out, 'manifest.private.json'), 'utf8'));
  if (manifest.sourceHash !== proof.sourceHash) throw Error('FROZEN_IDENTITY_CHANGED');
  return manifest;
}

if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) {
  const root = resolve(import.meta.dirname, '..'), out = resolve(process.argv[2]);
  if (process.argv.includes('--capture-active')) {
    const manifest = verifiedSnapshot(root, out);
    const record = JSON.parse(readFileSync(join(out, 'campaign-process.json'), 'utf8'));
    const files = [...manifest.sources.map(s => join(out, 'source', s.file)),
      ...manifest.compiles.flatMap(c => [c.source, c.source.replace(/\.mq5$/, '.ex5')]),
      join(out, 'manifest.private.json'), join(out, 'parity_verified.json')];
    const target = join(out, 'active-frozen-snapshot.json');
    if (existsSync(target)) throw Error('FROZEN_SNAPSHOT_ALREADY_CAPTURED');
    writeFileSync(target, JSON.stringify({ pid: record.pid, startedUtc: record.startedUtc,
      sourceHash: manifest.sourceHash, files: [...new Set(files)].map(f => ({ name: relative(out, f), sha256: sha(f) })) }, null, 2));
  } else if (existsSync(join(out, 'active-frozen-snapshot.json'))) {
    frozenSnapshot(out, process.ppid);
    const stopPath = join(out, 'campaign-stop.request.json');
    if (existsSync(stopPath)) {
      const request = JSON.parse(readFileSync(stopPath, 'utf8').replace(/^\uFEFF/, ''));
      const record = JSON.parse(readFileSync(join(out, 'campaign-process.json'), 'utf8'));
      if (request.pid === process.ppid && request.startedUtc === record.startedUtc)
        throw Error('CAMPAIGN_STOP_REQUESTED_BY_USER: saved results retained');
    }
    // A one-shot verification can borrow the existing worker BETWEEN strategies.
    // The coordinator waits here; no active audit or user terminal is stopped.
    const queued = join(out, 'boundary-verification.ps1');
    if (existsSync(queued)) {
      const claimed = join(out, 'boundary-verification.running.ps1'); renameSync(queued, claimed);
      const result = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', claimed],
        { cwd: root, windowsHide: true, stdio: 'inherit' });
      renameSync(claimed, queued + (result.status === 0 ? '.done' : '.failed'));
      // Diagnostics do not abort the original frozen campaign on test failure.
      if (result.status !== 0) console.error('BOUNDARY_VERIFICATION_FAILED: see diagnostic report');
      frozenSnapshot(out, process.ppid);
    }
  } else verifiedSnapshot(root, out);
}
