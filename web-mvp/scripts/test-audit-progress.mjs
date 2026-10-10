import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {auditProgressModel} from '../lib/audit-progress.ts';
import {build} from 'rolldown';
async function bundled(file){const output=await build({input:new URL(file,import.meta.url).pathname.replace(/^\/([A-Z]:)/,'$1'),platform:'node',write:false,output:{format:'esm',codeSplitting:false}});return import('data:text/javascript;base64,'+Buffer.from(output.output.find(c=>c.type==='chunk').code).toString('base64'));}
const {translate}=await bundled('../lib/messages.ts');
const {friendlyError}=await bundled('../lib/studio-help.ts');

const job = {state: 'running', createdAt: 100000, updatedAt: 220000,
  progress: {phase: 'downloading', processed: 0, total: null}};

test('history activity never fabricates a completion percentage, including estimated counts', () => {
  for (const progress of [job.progress, {phase: 'downloading', processed: 5000, total: 20000}, null]) {
    const m = auditProgressModel({...job, progress}, 231000);
    assert.equal(m.percent, null); assert.equal(m.step, 0); assert.equal(m.elapsed, '02:11');
  }
});

test('actual replay counts drive progress, clamped and finite', () => {
  assert.equal(auditProgressModel({...job, progress: {phase: 'replaying', processed: 38, total: 100}}, 231000).percent, 38);
  assert.equal(auditProgressModel({...job, progress: {phase: 'replaying', processed: 200, total: 100}}, 231000).percent, 100);
  for (const total of [null, 0, NaN, Infinity]) assert.equal(auditProgressModel({...job, progress: {phase: 'replaying', processed: 38, total}}, 231000).percent, null);
});

test('completed server state overrides stale 38% progress; failure never becomes complete', () => {
  const progress = {phase: 'replaying', processed: 38, total: 100};
  const completed = auditProgressModel({...job, state: 'completed', progress}, 500000, 'AUDIT_AUTHORITY_EXPIRED');
  assert.equal(completed.percent, 100); assert.equal(completed.step, 3); assert.equal(completed.paused, false);
  assert.equal(completed.elapsed, '02:00'); assert.equal(completed.label, 'Audit complete');
  const failed = auditProgressModel({...job, state: 'failed', progress}, 500000);
  assert.equal(failed.completed, false); assert.equal(failed.label, 'Audit stopped'); assert.equal(failed.percent, 38);
});

test('temporary authority loss is a research pause, not a fabricated success or result deletion', () => {
  const paused = auditProgressModel(job, 231000, 'AUDIT_AUTHORITY_EXPIRED');
  assert.equal(paused.paused, true); assert.equal(paused.completed, false);
  assert.equal(paused.label, 'Waiting for renewed audit authority');
  assert.equal(auditProgressModel(job, 231000, '').paused, false);
  assert.match(friendlyError('AUDIT_AUTHORITY_EXPIRED'), /paused research/);
  assert.ok(!friendlyError('AUDIT_AUTHORITY_EXPIRED').includes('No success was assumed'));
});

test('new progress labels and authority recovery are bundled in Turkish and German', () => {
  for (const text of ['Downloading / building broker history', 'Audit complete', 'Broker history', 'Trade replay',
    'Result received', 'Elapsed', 'Completion percentage unavailable', friendlyError('AUDIT_AUTHORITY_EXPIRED')]) {
    for (const locale of ['tr', 'de']) assert.notEqual(translate(text, locale), text, locale + ': ' + text);
  }
});

test('native pause only clears on signed matching renewal or a successfully emitted result', () => {
  const source = readFileSync(new URL('../../IndicatorCodeExamples/universal/UniversalRuntime.mqh', import.meta.url), 'utf8');
  const timer = source.split('void UcTimer()')[1];
  const beforeClear = timer.split('&&g_ucError=="AUDIT_AUTHORITY_EXPIRED")g_ucError="";')[0];
  assert.ok(beforeClear.includes('if(UcVerified(packet,body))'));
  for (const field of ['jobId', 'attemptId', 'configurationHash', 'requestHash']) assert.ok(beforeClear.includes(`UcField(body,"${field}")`));
  assert.ok(source.includes('if(GetTickCount64()>=g_ucAuditUntil){g_ucError="AUDIT_AUTHORITY_EXPIRED";return;}'));
  const result = source.split('void UcResult()')[1].split('void UcAuditStep()')[0];
  assert.ok(result.includes('if(g_ucError=="AUDIT_AUTHORITY_EXPIRED")g_ucError="";'));
  assert.ok(result.includes('RESULT_ROW_LIMIT')); assert.ok(source.includes('Preparing native engine and broker history'));
});
