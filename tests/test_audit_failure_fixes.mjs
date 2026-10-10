import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { checkFrozenCoordinator } from '../scripts/verify_strategy_campaign_snapshot.mjs';
const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8');
const names = {orb:'OrbUltimateEA_StrategyLibrary.mq5',macrossover_orb:'MaCrossOverOrbEA.mq5',entry_engine_lab:'EntryEngineLabEA.mq5'};
for (const [folder, name] of Object.entries(names)) {
  test(`${folder}: compact tick horizon follows the fill, not the signal open`, () => {
    const code = read(`IndicatorCodeExamples/${folder}/${name}`);
    assert.match(code, /firstEnd=BarCloseTime\(RuntimeEntryTf\(\),entryTime\)/);
    assert.match(code, /firstEnd\+=ORB_HIST_TICK_PREFETCH_MINUTES\*60/);
    assert.doesNotMatch(code, /firstEnd=entryTime\+ORB_HIST_TICK_PREFETCH_MINUTES\*60/);
    for (const seconds of [60,300,900,1800,3600,14400]) {
      const signal=1791000000, fill=signal+seconds, end=fill+15*60;
      assert.ok(end>fill);
    }
    assert.match(read(`IndicatorCodeExamples/${folder}/OrbStrategyUserMetrics.mqh`), /AUDIT_FILL_HORIZON2/);
  });
}
for (const folder of ['macrossover_orb','entry_engine_lab']) {
  test(`${folder}: incomplete suffix cannot initialize or seal recursive state`, () => {
    const core=read(`IndicatorCodeExamples/${folder}/MaCrossSignalCore.mqh`);
    assert.match(core, /PERIOD_M1,SERIES_SERVER_FIRSTDATE/);
    assert.match(core, /McHistoryReady\(symbol,tf,first/);
    const cache=read(`IndicatorCodeExamples/${folder}/MaCrossAuditCache.mqh`);
    assert.match(cache, /McHistoryReady\(symbol,tf,seed/);
    assert.match(cache, /signal origin changed during build/);
    const code=read(`IndicatorCodeExamples/${folder}/${names[folder]}`);
    assert.match(code, /if\(!MaCrossAuditOriginStable\(\)\)/);
    assert.match(code, /if\(g_maCrossAuditPending\)g_maCacheFailedAttempts=0/);
  });
}
test('Lab retains custom engine identity and label', () => {
  const core=read('IndicatorCodeExamples/entry_engine_lab/MaCrossSignalCore.mqh');
  assert.match(core,/string key=LabEngineIdentity\(\)\+symbol/);
  assert.match(core,/mode==MA_CROSS_LAB_RULES/);
});
test('archives retain old identities but CURRENT never accepts pre-fix calculations',()=>{
  for(const folder of Object.keys(names)) {
    const code=read(`IndicatorCodeExamples/${folder}/OrbStrategyUserMetrics.mqh`);
    assert.match(code,/bool currentSchema=true/);
    assert.match(code,/key=OrbUserWindowKey\(r\)/);
    assert.match(code,/g_swFrozen&&SwReadView\([^\n]+OrbUserWindowKey\(r,false\)/);
    assert.match(code,/windowKey=OrbUserWindowKey\(g_userStrategies\[savedSlot\]\)/);
    assert.match(code,/currentSchema\?"\|AUDIT_FILL_HORIZON2/);
  }
});
test('running campaign exemption rejects any other coordinator', () => {
  const proof={pid:123,startedUtc:'2026-10-09'},record={...proof};
  checkFrozenCoordinator(proof,record,123);
  assert.throws(()=>checkFrozenCoordinator(proof,record,124),/FROZEN_COORDINATOR_CHANGED/);
  assert.throws(()=>checkFrozenCoordinator(proof,{...record,startedUtc:'2026-10-10'},123),/FROZEN_COORDINATOR_CHANGED/);
});

test('corrected mega handoff preserves original settings and refuses interrupted runs',()=>{
  const queue=read('scripts/resume_fixed_strategy_campaign.ps1');
  assert.match(queue,/Original strategy inventory\/settings changed/);
  assert.match(queue,/ORIGINAL_INTERRUPTED_NOT_RESTARTED/);
  assert.match(queue,/ORIGINAL_PROCESS_CHANGED_NOT_RESTARTED/);
  assert.match(queue,/\$epoch\.asOf/);
  assert.match(queue,/HistoryMaxBars 5000000/);
  assert.doesNotMatch(queue,/Stop-Process|taskkill|Remove-Item/);
  const seal=read('scripts/seal_strategy_window_campaign.mjs');
  assert.match(seal,/if \(!process\.argv\.includes\('--legacy'\)\) verifiedSnapshot/);
});
