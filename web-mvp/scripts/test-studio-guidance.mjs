import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync,existsSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runInNewContext} from 'node:vm';
import ts from 'typescript';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {eaCatalog,defaultConfiguration,universalConfigurationSchema} from '../lib/universal-contract.ts';
import {controlHelp,controlGroup,controlLabel,helpTopics,blockedReason,safeConfiguration,starterRules,friendlyError,auditMatchesConnection} from '../lib/studio-help.ts';
import {chartLessonFrame,lessonEffect,effectSteps} from '../lib/lesson-chart.ts';

const root=fileURLToPath(new URL('..',import.meta.url));
const src=path=>readFileSync(resolve(root,path),'utf8');
const require=createRequire(import.meta.url),cache=new Map();
// SSR verification is not browser, canvas, focus-trap or click-through testing.
function load(path){
 const file=resolve(root,path);if(cache.has(file))return cache.get(file);
 const module={exports:{}};cache.set(file,module.exports);
 const result=ts.transpileModule(readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true,target:ts.ScriptTarget.ES2022}}).outputText;
 const local=id=>{
  if(id.startsWith('@/')||id.startsWith('.')){
   const base=id.startsWith('@/')?resolve(root,id.slice(2)):resolve(dirname(file),id);
   const candidate=[base,base+'.tsx',base+'.ts',base+'.json'].find(existsSync);
   if(candidate?.endsWith('.json'))return require(candidate);
   if(candidate)return load(candidate);
  }
  return require(id);
 };
 runInNewContext(result,{module,exports:module.exports,require:local,process,structuredClone,console});
 cache.set(file,module.exports);return module.exports;
}
const ready={signedIn:true,active:true,selected:true,online:true,controller:true,dirty:false,running:false,complete:true,hasData:false,acknowledged:true};

test('all four catalogs receive per-key help and finite, deterministic chart frames without mutation',()=>{
 let controls=0;const kinds=new Set();
 for(const family of Object.keys(eaCatalog))for(const spec of [...eaCatalog[family].runtime,...eaCatalog[family].inputs]){
  const before=JSON.stringify(spec),topic={...controlHelp(spec),currentValue:spec.default};controls++;
  assert.equal(topic.technical,spec.key);assert.ok(controlLabel(spec.key));assert.ok(topic.summary&&topic.example&&topic.caution);
  kinds.add(lessonEffect(topic));assert.equal(effectSteps[lessonEffect(topic)].length,3);
  for(let step=0;step<3;step++){
   const frame=chartLessonFrame(topic,step);assert.equal(frame.badge,spec.key);
   for(const candle of frame.bars){for(const p of Object.values(candle))assert.ok(Number.isFinite(p));assert.ok(candle.high>=Math.max(candle.open,candle.close));assert.ok(candle.low<=Math.min(candle.open,candle.close));}
   for(const line of frame.lines)assert.ok(Number.isFinite(line.price));
   for(const trace of frame.traces)assert.ok(trace.values.every(Number.isFinite));
   assert.ok(frame.note);assert.deepEqual(frame,chartLessonFrame(topic,step));
  }
  assert.equal(JSON.stringify(spec),before);
 }
 assert.ok(controls>700);assert.ok(kinds.size>=20);console.log(`Help/chart coverage: ${controls} catalog entries / ${kinds.size} effect families.`);
});
test('target moves without changing entry/stop or candle history',()=>{
 const topic={...helpTopics.targetR,technical:'targetR',currentValue:1};
 const a=chartLessonFrame(topic,0),b=chartLessonFrame(topic,1);
 assert.deepEqual(a.bars,b.bars);assert.equal(a.lines[0].price,b.lines[0].price);assert.equal(a.lines[1].price,b.lines[1].price);assert.notEqual(a.lines[2].price,b.lines[2].price);
});
test('stop, sizing, position capacity, clock and NAS have distinct illustrations',()=>{
 const topics=['InpPipSlPips','balance','maxOpen','timeMatrixEnabled','nasGate'].map(key=>({...controlHelp({key,type:'double',default:2,group:'Geometry'}),currentValue:2}));
 assert.equal(new Set(topics.map(lessonEffect)).size,5);
 const sizing=chartLessonFrame(topics[1],2),capacity=chartLessonFrame(topics[2],2);
 assert.ok(sizing.size);assert.equal(capacity.marks.filter(m=>!m.rejected).length,2);
 assert.ok(chartLessonFrame(topics[3],2).marks.some(m=>m.rejected));
});
test('regime observer does not demonstrate an entry block',()=>{
 const t=controlHelp({key:'InpRegimeV3Observer',type:'bool',default:true,group:'Regimes'});
 assert.equal(chartLessonFrame(t,2).marks.filter(m=>m.rejected).length,0);
});
test('entry lookback is not depicted as post-entry wait; pre-entry exit event is ineligible',()=>{
 const age=chartLessonFrame({...helpTopics.nasAgeMinutes,technical:'nasAgeMinutes'},2);
 assert.ok(age.bands[0].label.includes('lookback'));assert.ok(age.note.includes('not a waiting duration'));
 const wait=chartLessonFrame({...helpTopics.nasWaitMinutes,technical:'nasWaitMinutes'},2);
 assert.ok(wait.marks.find(m=>m.bar===3)?.rejected);assert.ok(wait.bands[0].label.includes('Waiting'));
});
test('state and flow NAS volume lessons identify separate streams',()=>{
 const state=chartLessonFrame({...helpTopics.nasStateMultiplier,technical:'nasStateMultiplier'},2),flow=chartLessonFrame({...helpTopics.nasFlowMultiplier,technical:'nasFlowMultiplier'},2);
 assert.ok(state.note.includes('state NAS stream'));assert.ok(flow.note.includes('flow NAS stream'));assert.notDeepEqual(state.bands,flow.bands);
});
test('timeframe illustration actually aggregates OHLC, not arrow appearance',()=>{
 const t=controlHelp({key:'InpSignalTimeframe',type:'int',default:5,group:'Entry / Execution'});
 const a=chartLessonFrame(t,0),b=chartLessonFrame(t,1);
 assert.equal(a.bars.length,32);assert.equal(b.bars.length,11);assert.equal(b.bars[0].open,a.bars[0].open);assert.equal(b.bars[0].close,a.bars[2].close);assert.equal(b.bars[0].high,Math.max(...a.bars.slice(0,3).map(c=>c.high)));
});
test('UI HH:MM conversion preserves snapshots; rejects invalid minutes/formats',()=>{
 for(const family of Object.keys(eaCatalog)){
  const c=defaultConfiguration(family),snapshot=JSON.stringify(c);assert.deepEqual(safeConfiguration(c),c);assert.equal(JSON.stringify(c),snapshot);
  c.runtime.reverseWaitMinutes='02:30';c.runtime.nasWaitMinutes='00:25';const converted=universalConfigurationSchema.parse(safeConfiguration(c));
  assert.equal(converted.runtime.reverseWaitMinutes,150);assert.equal(converted.runtime.nasWaitMinutes,25);assert.equal(c.runtime.nasWaitMinutes,'00:25');
  for(const v of ['00:60','-1:00','1:0','nonsense']){c.runtime.nasWaitMinutes=v;assert.throws(()=>safeConfiguration(c));}
 }
});
test('every incomplete authority/research state blocks Trading ON, not just a checkbox',()=>{
 assert.equal(blockedReason(ready,true),null);
 for(const key of ['signedIn','active','selected','online','controller','complete','acknowledged'])assert.ok(blockedReason({...ready,[key]:false},true),key);
 for(const key of ['dirty','running','hasData'])assert.ok(blockedReason({...ready,[key]:true},true),key);
 assert.equal(blockedReason({...ready,dirty:true,complete:false,acknowledged:false}),null,'draft can be audited before it has results');
});
test('audit is bound to selected installation, symbol and broker',()=>{
 const r={installationId:'one',symbol:'EURUSDm',brokerServer:'broker'},t={symbol:'EURUSDm',brokerServer:'broker'};
 assert.ok(auditMatchesConnection(r,'one',t));assert.ok(!auditMatchesConnection(r,'two',t));assert.ok(!auditMatchesConnection(r,'one',{...t,symbol:'BTCUSDm'}));assert.ok(!auditMatchesConnection(r,'one',{...t,brokerServer:'another'}));assert.ok(!auditMatchesConnection(undefined,'one',t));
});
test('custom-rule starter is a valid explicit draft and preserves unrelated settings',()=>{
 const c=defaultConfiguration('entrylab');c.runtime.targetR=.05;c.runtime.balance=30;const before=JSON.stringify(c),draft=starterRules(c);
 assert.ok(universalConfigurationSchema.safeParse(draft).success);assert.equal(draft.inputs.InpMaCrossMode,6);assert.equal(draft.runtime.entryPreset,0);assert.equal(draft.runtime.targetR,.05);assert.equal(draft.runtime.balance,30);assert.equal(draft.builder.buy[0].comparator,0);assert.equal(draft.builder.sell[0].comparator,1);assert.equal(JSON.stringify(c),before);
});
test('errors explain recovery and never present failure as success',()=>{
 assert.ok(friendlyError('UNAUTHORIZED').includes('Sign in'));assert.ok(friendlyError('BILLING_NOT_CONFIGURED').includes('No charge'));assert.ok(friendlyError('SOMETHING_NEW').includes('No success was assumed'));
});
test('SSR shows a guided first run and help on every essential, without raw token setup',()=>{
 const Dashboard=load('components/universal-dashboard.tsx').default;
 const html=renderToStaticMarkup(React.createElement(Dashboard,{credential:'',onCredential:()=>{},onConnect:()=>{}}));
 for(const text of ['One step at a time.','Guided view','Expert view','Show expert controls','Your studio guide','Pause robot','Sign in to your account first.'])assert.ok(html.includes(text),text);
 assert.ok(html.includes('Explain: Profit target in R'));assert.ok(html.includes('Explain: Use a stop measured in pips'));assert.ok(html.includes('Explain: Stop distance in pips'));
 const Connection=load('components/connection-panel.tsx').default;
 const connection=renderToStaticMarkup(React.createElement(Connection,{credential:'',onCredential:()=>{}}));
 assert.ok(connection.includes('You do not need a developer token'));assert.ok(!connection.includes('Local development access token'));assert.ok(connection.includes('start_connection.bat'));
});
test('all chart effect families SSR-render an accessible candle board',()=>{
 const Chart=load('components/lesson-chart.tsx').default;
 const samples=new Map();for(const family of Object.values(eaCatalog))for(const spec of [...family.runtime,...family.inputs]){const t={...controlHelp(spec),currentValue:spec.default};samples.set(lessonEffect(t),t);}
 for(const [effect,topic] of samples){const html=renderToStaticMarkup(React.createElement(Chart,{topic,step:2,still:true}));assert.ok(html.includes('role="img"'));assert.ok(html.includes(`data-effect="${effect}"`));assert.ok(html.includes('SYNTHETIC CANDLES'));assert.ok(html.includes('teaching-candle'));}
});
test('animated lesson uses chart effects, pauses and respects device preferences',()=>{
 const lesson=src('components/studio-help.tsx'),robot=src('components/tutor-robot.tsx'),css=src('app/globals.css');
 assert.ok(lesson.includes('<LessonChart'));assert.ok(!lesson.includes('lesson-pipeline'));assert.ok(lesson.includes('paused||(reduced&&!allowMotion)'));assert.ok(lesson.includes('document.hidden'));assert.ok(lesson.includes('clearInterval'));assert.ok(lesson.includes('Compare with default'));assert.ok(lesson.includes('currentValue===false'));
 assert.ok(robot.includes("import('three')"));assert.ok(robot.includes('renderer.dispose()'));assert.ok(robot.includes('IntersectionObserver'));assert.ok(robot.includes('needsRender'));assert.ok(!/fetch\(|localStorage|sessionStorage/.test(robot));assert.ok(robot.includes('arm.scale.x=-1'));
 assert.ok(css.includes('z-index: 90'));assert.ok(css.includes('z-index: 91'));assert.ok(css.includes('.lesson[data-paused=true]'));assert.ok(css.includes('prefers-reduced-motion:reduce'));
});
