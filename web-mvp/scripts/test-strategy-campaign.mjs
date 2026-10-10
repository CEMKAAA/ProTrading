import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync,existsSync} from 'node:fs';
import {resolve} from 'node:path';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {campaignRecord,campaignWeeks,importCampaign,uploadSql} from './import-strategy-campaign.mjs';
import {loadUi} from './ui-ssr-loader.mjs';

const hash='a'.repeat(64),manifest={sourceHash:hash,templateHash:hash,generatorHash:hash};
const job={id:'orb_test',family:'orb',name:'Test',symbol:'USDJPYm',nativeSourceHash:hash,chartTf:5,windows:campaignWeeks};
const catalog={id:job.id,source_hash:hash,family:job.family,name:job.name,symbol:job.symbol};
const rows=()=>campaignWeeks.map(weeks=>({catalog_id:job.id,native_id:'test',name:job.name,symbol:job.symbol,chart_tf:'5',weeks:String(weeks),
 total:'12',wins:'8',losses:'2',open:'1',flat:'1',data:'0',net_r:'3.123456789012',min_cum_r:'-2.25',as_of:'1791575217',
 elapsed_ms:'1',status:'AUDITED_OPEN',metrics_saved:'1',independent:'1',order_attempts:'0',settings_verified:'1',native_parity_verified:'1',
 settings_key:hash,engine_hash:hash,template_hash:hash,generator_hash:hash,trade_trace_hash:hash,unavailable_parity_verified:'0'}));
const record=r=>campaignRecord(job,r,manifest,catalog,1791575217);

test('nine exact windows, W/L/O, R, MC and mode survive; open trades never raise WR',()=>{
 const result=record(rows());assert.equal(result.campaign.windows.length,9);assert.equal(result.campaign.independent,true);
 const m=result.campaign.windows[0].metrics;assert.equal(m.winRate,80);assert.equal(m.netR,3.123456789012);assert.equal(m.minCumR,-2.25);
 assert.deepEqual([m.total,m.wins,m.losses,m.open,m.flat],[12,8,2,1,1]);
});
test('confirmed unavailable window has null metrics, not a fabricated 0W/0L result',()=>{
 const r=rows();Object.assign(r[8],{status:'HISTORY_UNAVAILABLE',metrics_saved:'0',unavailable_parity_verified:'1',detail:'First quote after requested start'});
 const w=record(r).campaign.windows[8];assert.equal(w.available,false);assert.equal(w.metrics,null);assert.match(w.detail,/First quote/);
});
test('mismatched fingerprints, missing/duplicate windows and unconfirmed evidence are rejected',()=>{
 assert.throws(()=>campaignRecord(job,rows(),manifest,{...catalog,source_hash:'b'.repeat(64)},1791575217),/CATALOG_SNAPSHOT/);
 assert.throws(()=>record(rows().slice(1)),/WINDOW_COUNT/);
 const duplicate=rows();duplicate[8]=duplicate[7];assert.throws(()=>record(duplicate),/WINDOW_COUNT/);
 const unverified=rows();unverified[0].native_parity_verified='0';assert.throws(()=>record(unverified),/UNVERIFIED/);
 const r=rows();Object.assign(r[8],{status:'DATA_INCOMPLETE',metrics_saved:'0',unavailable_parity_verified:'0'});
 assert.throws(()=>record(r),/UNVERIFIED/);
 const epoch=rows();epoch[0].as_of='1791575218';assert.throws(()=>record(epoch),/EPOCH_OR_SETTINGS/);
});
test('symbol aliases require captured explicit approval and retain the actual audited symbol',()=>{
 assert.throws(()=>campaignRecord(job,rows(),manifest,{...catalog,symbol:'USDJPY'},1791575217),/CATALOG_SNAPSHOT/);
 const alias={...job,sourceSymbol:'USDJPY',symbolOverride:'explicit_user_approval_20261009'};
 assert.equal(campaignRecord(alias,rows(),manifest,{...catalog,symbol:'USDJPY'},1791575217).campaign.symbol,'USDJPYm');
});
test('zero closed trades shows undefined WR rather than 100%',()=>{
 const r=rows();r.forEach(r=>Object.assign(r,{total:'1',wins:'0',losses:'0',flat:'0',net_r:'0',min_cum_r:'0'}));
 assert.equal(record(r).campaign.windows[0].metrics.winRate,null);
});
test('upload only changes campaign metrics and binds the existing strategy fingerprint',()=>{
 const sql=uploadSql([record(rows())]);assert.ok(sql.includes("c.source_hash=p->>'sourceHash'"));
 assert.ok(sql.includes('CAMPAIGN_CATALOG_MISMATCH'));assert.ok(sql.includes('CAMPAIGN_BASELINE_IS_NEWER'));
 assert.ok(!/insert into|set configuration|set enabled|strategy_grants/i.test(sql));
});

const Stats=loadUi('components/strategy-campaign-stats.tsx').default;
const SharedLibrary=loadUi('components/shared-strategy-library.tsx').default;
const {LanguageProvider}=loadUi('components/language-provider.tsx');
const {translate}=loadUi('lib/messages.ts');
const render=(node,locale='en')=>renderToStaticMarkup(React.createElement(LanguageProvider,{locale},node));
for(const locale of ['en','tr','de'])test(`cards and all nine window selectors render in ${locale}`,()=>{
 const html=render(React.createElement(Stats,{campaign:record(rows()).campaign,weeks:2}),locale);
 assert.ok(html.includes('80%'));assert.ok(html.includes('INDEPENDENT'));
 assert.ok(html.includes(new Intl.NumberFormat(locale,{maximumFractionDigits:4}).format(3.123456789012)+'R'));
 assert.ok(html.includes(translate('Audit cutoff (broker time)',locale)));
 assert.ok(html.includes('2026-10-09 19:46:57'));
 const library=render(React.createElement(SharedLibrary,{credential:'',onLoad:()=>{}}),locale);
 for(const label of ['2W','5W','10W','20W','1Y','2Y','3Y','4Y','5Y'])assert.ok(library.includes('>'+label+'</button>'));
 assert.ok(library.includes(translate('Verified MEGA campaign',locale)));
});
test('missing data card shows no numeric results and no hidden winner',()=>{
 const c=record(rows()).campaign;c.windows[8]={weeks:260,status:'DATA_INCOMPLETE',available:false,metrics:null};
 const html=render(React.createElement(Stats,{campaign:c,weeks:260}));
 assert.ok(html.includes('Data unavailable'));assert.ok(!html.includes('campaign-metrics'));assert.ok(!html.includes('80%'));
});

const root=resolve(import.meta.dirname,'../..'),baseline=resolve(root,'reports/verification_build/audit_failures/mega-baseline');
test('sealed real campaign imports exactly 188 strategies, 1616 valid and 76 unavailable windows',{skip:!existsSync(baseline)},()=>{
 const catalog=JSON.parse(readFileSync(resolve(root,'reports/admin_catalog/catalog.private.json'),'utf8'));
 const records=importCampaign(baseline,catalog);assert.equal(records.length,188);
 assert.equal(records.flatMap(r=>r.campaign.windows).filter(w=>w.available).length,1616);
 assert.equal(records.flatMap(r=>r.campaign.windows).filter(w=>!w.available).length,76);
});
