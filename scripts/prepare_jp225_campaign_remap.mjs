import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const jp225Names = ['Legacy_JP225_H2M30_2R', 'Legacy_JP225_H2H1_2R'];
export function remapJp225Manifest(original) {
  const manifest = structuredClone(original);
  for (const name of jp225Names) {
    const jobs = manifest.jobs.filter(job => job.name === name);
    if (jobs.length !== 1) throw Error('JP225_RECORD_NOT_UNIQUE:' + name);
    const job = jobs[0];
    if (job.family !== 'sol' || job.origin !== 'image:' + name
      || !['JP225s', 'JP225m'].includes(job.symbol)
      || (job.symbol === 'JP225m' && job.sourceSymbol !== 'JP225s')) throw Error('JP225_RECORD_MISMATCH:' + name);
    job.sourceSymbol = 'JP225s';
    job.symbol = 'JP225m';
    job.symbolOverride = 'explicit_user_approval_20261009';
  }
  return manifest;
}

if (resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const out = join(root, 'reports/strategy_audit_20261008');
  const frozen = join(out, 'source');
  const source = join(frozen, 'SolAdvanced');
  const staged = join(out, 'jp225-remap/source');
  const build = join(staged, 'SolAdvanced');
  const path = join(out, 'manifest.private.json');
  const original = JSON.parse(readFileSync(path, 'utf8'));
  const manifest = remapJp225Manifest(original);
  mkdirSync(build, { recursive: true });
  const snapshots = [], seen = new Set();
  function stageFile(path) {
    path = resolve(path);
    if (seen.has(path)) return;
    if (!path.startsWith(frozen + '\\')) throw Error('INCLUDE_ESCAPED_FROZEN_SOURCE');
    seen.add(path);
    const name = relative(frozen, path), target = join(staged, name), bytes = readFileSync(path);
    snapshots.push({ name, sha256: createHash('sha256').update(bytes).digest('hex') });
    mkdirSync(dirname(target), { recursive: true });copyFileSync(path, target);
    for (const match of bytes.toString('utf8').matchAll(/^\s*#include\s+"([^"]+)"/gm)) stageFile(join(dirname(path), match[1]));
  }
  stageFile(join(source, 'StrategyWindows_sol.mq5'));
  const header = join(build, 'LiqImagePresets.mqh');
  const before = readFileSync(header, 'utf8');
  const match = 'return i>=0&&i<ArraySize(g_liqImagePresets)&&family==g_liqImagePresets[i].family&&_Symbol==g_liqImagePresets[i].symbol;';
  if (before.split(match).length !== 2) throw Error('IMAGE_COMPATIBILITY_CHANGED');
  const replacement = 'if(i<0||i>=ArraySize(g_liqImagePresets)||family!=g_liqImagePresets[i].family)return false;\n'
    + '   return _Symbol==g_liqImagePresets[i].symbol||(_Symbol=="JP225m"&&g_liqImagePresets[i].symbol=="JP225s");';
  writeFileSync(header, before.replace(match, replacement));
  const script = join(build, 'StrategyWindows_sol_jp225_remap.mq5');
  copyFileSync(join(build, 'StrategyWindows_sol.mq5'), script);
  for (const snapshot of snapshots) {
    const actual = createHash('sha256').update(readFileSync(join(frozen, snapshot.name))).digest('hex');
    if (actual !== snapshot.sha256) throw Error('FROZEN_SOURCE_CHANGED');
  }
  const jobs = manifest.jobs.filter(job => jp225Names.includes(job.name));
  writeFileSync(join(out, 'jp225-remap/authorization.json'), JSON.stringify({
    authorizedAt: new Date().toISOString(), originalEngineHash: manifest.sourceHash,
    sourceSymbol: 'JP225s', auditSymbol: 'JP225m', script, sourceSnapshots: snapshots,
    jobs: jobs.map(job => ({ id: job.id, name: job.name, origin: job.origin, inputsHash: createHash('sha256').update(JSON.stringify(job.inputs)).digest('hex') })),
  }, null, 2));
  writeFileSync(path + '.next', JSON.stringify(manifest, null, 2));
  renameSync(path + '.next', path);
  console.log(JSON.stringify({ script, jobs: jobs.map(job => ({ id: job.id, name: job.name, sourceSymbol: job.sourceSymbol, symbol: job.symbol })) }, null, 2));
}
