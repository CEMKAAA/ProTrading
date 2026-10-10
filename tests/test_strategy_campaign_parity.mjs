import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { compareAudits, compareTrades } from '../scripts/verify_strategy_campaign_parity.mjs';
const row={catalog_id:'a',native_id:'user_a',name:'pilot',symbol:'JP225m',chart_tf:'1',weeks:'2',
 total:'33',wins:'32',losses:'0',open:'1',flat:'0',data:'0',as_of:'1791504000',independent:'1',
 net_r:'0.32',min_cum_r:'0',settings_key:'a'.repeat(64),calendar:'TCAL1=1,0,1,1,1,1,1,0,1,4,10,0',
 status:'AUDITED_OPEN',settings_verified:'1',order_attempts:'0',load_mode:'campaign'};
const direct={...row,load_mode:'dashboard'};
test('identical totals cannot conceal a changed entry, exit or price in the trade trace',()=>{
 const trace=[{entry_time:'1',exit_time:'2',entry:'150',sl:'149',tp:'151',net_r:'1'}];
 assert.deepEqual(compareTrades(trace,structuredClone(trace)),[]);
 for(const field of Object.keys(trace[0]))assert.ok(compareTrades(trace,[{...trace[0],[field]:'bad'}]).length);
 assert.deepEqual(compareTrades(trace,[]),['TRADE_TRACE_COUNT']);
 assert.deepEqual(compareTrades(trace,undefined),['MISSING_TRADE_TRACE']);
});
test('two native load paths must agree on counts, R, MC, endpoint and settings',()=>assert.deepEqual(compareAudits(row,direct),[]));
test('same totals cannot hide changed outcomes or R/MC',()=>{
 for(const field of ['wins','losses','open','net_r','min_cum_r','as_of','settings_key','calendar'])
  assert.ok(compareAudits(row,{...direct,[field]:field==='settings_key'?'b'.repeat(64):'5'}).includes(field));
});
test('empty, unavailable and unverified audits cannot constitute parity proof',()=>{
 assert.deepEqual(compareAudits(row,undefined),['MISSING_PAIR']);
 assert.ok(compareAudits(row,{...direct,status:'DATA_INCOMPLETE'}).includes('dashboard:INCOMPLETE'));
 assert.ok(compareAudits(row,{...direct,settings_verified:'0'}).includes('dashboard:UNVERIFIED'));
});
test('campaign restores the complete calendar and checks the production matcher',()=>{
 const code=readFileSync(new URL('../tests/mql5/StrategyWindowCampaign.mq5.in',import.meta.url),'utf8');
 assert.match(code,/DailyQuotaReadStrategy\(text,loss,win,start\)/);
 assert.match(code,/g_entryDirection=DirectionStrategyMode\(text\)/);
 assert.match(code,/if\(!OrbUserMatches\(p\)\)/);
 assert.match(code,/CampaignDashboardLoad[\s\S]*OrbStrategyPresetApplyValues\(p\)/);
 assert.match(code,/!settingsVerified\)status="SETTINGS_MISMATCH"/);
});
test('three frontiers use one stored identity for both SEARCH and completed audit writes',()=>{
 for(const folder of ['orb','macrossover_orb','entry_engine_lab']) {
  const code=readFileSync(new URL(`../IndicatorCodeExamples/${folder}/OrbStrategyUserMetrics.mqh`,import.meta.url),'utf8');
  assert.match(code,/string key=OrbUserWindowKey\(r\)/);
  assert.match(code,/string windowKey=OrbUserWindowKey\(g_userStrategies\[savedSlot\]\)/);
  assert.match(code,/!OrbUserMatches\(p\)/);
 }
});
