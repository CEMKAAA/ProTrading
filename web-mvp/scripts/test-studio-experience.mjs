import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { createRequire } from 'node:module';
import ts from 'typescript';
import { activationSteps, activationText } from '../lib/activation-guide.ts';
import { teachingCandles, chartLessonFrame, lessonEffect } from '../lib/lesson-chart.ts';
import { lessonStage, lessonCards, clockKind } from '../lib/lesson-story.ts';
import { tutorPose } from '../lib/tutor-behavior.ts';
import { controlHelp } from '../lib/studio-help.ts';
import { eaCatalog } from '../lib/universal-contract.ts';

const source=file=>readFileSync(new URL('../'+file,import.meta.url),'utf8');
function guideHarness(locale='en',ready={signedIn:false,active:false,online:false,authorized:false}) {
 let cursor=0,tree,connectionCalls=0;const slots=[];
 const react={useState(initial){const i=cursor++;slots[i]??={value:initial};return [slots[i].value,v=>slots[i].value=typeof v==='function'?v(slots[i].value):v];},useRef(initial){const i=cursor++;slots[i]??={current:initial};return slots[i];}};
 const jsx=(type,props)=>({type,props});
 const module={exports:{}},imports={react,'react/jsx-runtime':{jsx,jsxs:jsx,Fragment:'Fragment'},'motion/react':{motion:new Proxy({},{get:(_,k)=>'motion.'+String(k)}),AnimatePresence:'AnimatePresence'},'lucide-react':new Proxy({},{get:(_,k)=>String(k)}),'./console-window':{__esModule:true,default:'ConsoleWindow'},'./language-provider':{useLanguage:()=>({locale})},'@/lib/activation-guide':{activationSteps,activationText}};
 const code=ts.transpileModule(source('components/ea-activation-guide.tsx'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true}}).outputText;
 runInNewContext(code,{module,exports:module.exports,require:id=>imports[id]??assert.fail(id)});
 const render=()=>{cursor=0;tree=module.exports.default({...ready,onConnect:()=>connectionCalls++});};
 const nodes=()=>{const all=[];function walk(n){if(Array.isArray(n))return n.forEach(walk);if(!n||typeof n!=='object')return;all.push(n);walk(n.props?.children);walk(n.props?.footer);}walk(tree);return all;};
 const find=predicate=>nodes().find(predicate)??assert.fail('Missing guide node');
 const open=()=>{render();find(n=>n.props?.className==='secondary-btn activation-launch').props.onClick();render();};
 const select=i=>{const nav=find(n=>n.props?.className==='activation-steps');nav.props.children[i].props.onClick();render();};
 return {render,open,select,find,nodes,get connectionCalls(){return connectionCalls;}};
}

test('licensing instructions have eight fully translated stages and exact existing paths',()=>{
 assert.equal(activationSteps.length,8);assert.equal(new Set(activationSteps.map(s=>s.id)).size,8);
 for(const step of activationSteps){assert.ok(step.tasks.length>=3);for(const copy of [step.title,step.summary,step.check,...step.tasks,...(step.warning?[step.warning]:[])]){assert.equal(copy.length,3);for(const text of copy)assert.ok(text.length>3);assert.notEqual(copy[0],copy[1]);assert.notEqual(copy[0],copy[2]);}}
 assert.equal(activationSteps.find(s=>s.id==='attach').path,'.state/connection.set');
 assert.equal(activationSteps.find(s=>s.id==='files').path,'MQL5/Experts/StratumUniversal/UniversalConnectionEA.ex5');
 assert.ok(activationSteps.find(s=>s.id==='package').warning[0].includes('30 minutes'));
 assert.ok(activationSteps.find(s=>s.id==='helper').warning[0].includes('5 minutes'));
 assert.ok(activationSteps.at(-1).summary[0].includes('Trading remains OFF'));
});

test('real guide navigation and playback do not grant entitlement, controller or live trading',()=>{
 const h=guideHarness();h.open();
 assert.equal(h.find(n=>n.type==='ConsoleWindow').props.open,true);
 for(let i=0;i<8;i++){h.select(i);assert.equal(h.find(n=>n.props?.className==='activation-scene').props['data-scene'],activationSteps[i].id);assert.equal(h.nodes().filter(n=>n.props?.['data-ready']===true).length,0);}
 assert.equal(h.connectionCalls,0);
 const footer=h.find(n=>n.props?.className==='activation-navigation');footer.props.children.at(-1).props.onClick();h.render();assert.equal(h.find(n=>n.type==='ConsoleWindow').props.open,false);
 h.open();h.select(3);h.find(n=>n.type==='button'&&n.props?.onClick&&JSON.stringify(n.props.children).includes('Open MT5 connection manager')).props.onClick();h.render();assert.equal(h.connectionCalls,1);assert.equal(h.find(n=>n.type==='ConsoleWindow').props.open,false);
 assert.ok(!/fetch\(|localStorage|sessionStorage|\/activate|\/trading/.test(source('components/ea-activation-guide.tsx')));
});

test('guide shows actual readiness, autoplay and working pause/resume in all three languages',()=>{
 for(const locale of ['en','tr','de']){
  const h=guideHarness(locale,{signedIn:true,active:true,online:true,authorized:true});h.open();
  assert.equal(h.nodes().filter(n=>n.props?.['data-ready']===true).length,3);
  assert.equal(h.find(n=>n.props?.className==='activation-scene').props['data-paused'],false);
  const playback=h.find(n=>n.type==='button'&&n.props?.['aria-pressed']===false);playback.props.onClick();h.render();
  assert.equal(h.find(n=>n.props?.className==='activation-scene').props['data-paused'],true);
  h.find(n=>n.type==='button'&&n.props?.['aria-pressed']===true).props.onClick();h.render();assert.equal(h.find(n=>n.props?.className==='activation-scene').props['data-paused'],false);
 }
});

test('candle scenarios vary by setting, but changing a value does not rewrite the price history',()=>{
 const a=controlHelp({key:'InpMaFastLength',type:'int',default:9,group:'Entry / Execution'}),b=controlHelp({key:'InpMaSlowLength',type:'int',default:200,group:'Entry / Execution'});
 assert.notDeepEqual(chartLessonFrame(a,0).bars,chartLessonFrame(b,0).bars);
 assert.deepEqual(chartLessonFrame({...a,currentValue:9},0).bars,chartLessonFrame({...a,currentValue:250},2).bars);
 assert.deepEqual(teachingCandles('same','ma'),teachingCandles('same','ma'));
 const stages=new Set(),keys=new Set(),histories=new Set();
 for(const family of Object.values(eaCatalog))for(const spec of [...family.inputs,...family.runtime]){
  const topic={...controlHelp(spec),currentValue:spec.default};stages.add(lessonStage(topic));keys.add(spec.key);histories.add(JSON.stringify(teachingCandles(spec.key,lessonEffect(topic))));
  for(let step=0;step<3;step++)for(const card of lessonCards(topic,chartLessonFrame(topic,step),step)){assert.ok(card.label);assert.ok(!card.value.includes('NaN'));}
 }
 assert.ok(stages.size>=10);assert.ok(histories.size>keys.size*.85);console.log(`Distinct teaching histories: ${histories.size} / ${keys.size} settings; ${stages.size} instrument scenes.`);
});

test('clock lessons distinguish timezone conversion, daily counters, day selection and session construction',()=>{
 const topic=key=>controlHelp({key,type:'int',default:0,group:'Session / Timezone'});
 for(const [key,kind] of [['InpBrokerTimezone','zones'],['InpDailyMaxLosses','daily'],['InpTradeMonday','days'],['InpOrbStartNy','session'],['timeMatrixEnabled','hours']])assert.equal(clockKind(topic(key)),kind);
});

test('all teacher moods remain finite with motion, pause and voice; detail meshes are disposed',()=>{
 for(const mood of ['idle','attentive','listening','thinking','curious','explaining','success','concern'])for(const moving of [false,true])for(const time of [0,1,5.9,6.1,10,100]){
  const pose=tutorPose(time,mood,moving,0,true,.5);for(const value of Object.values(pose))assert.ok(typeof value==='boolean'||Number.isFinite(value));assert.ok(pose.eyeHeight>0);assert.ok(pose.breath>.97&&pose.breath<1.03);
  if(!moving)assert.deepEqual(pose,tutorPose(0,mood,false,0,true,.5));
 }
 const robot=source('components/tutor-robot.tsx');for(const detail of ['TorusGeometry','glints','brows','tablet','robot-spectacles','robot-chest'])assert.ok(robot.includes(detail));assert.ok(robot.includes('geometries.forEach(g=>g.dispose())'));assert.ok(robot.includes('materials.forEach(m=>m.dispose())'));
});

test('guidance CSS parses; new styles follow legacy overrides and robot is pinned inside chat',()=>{
 const require=createRequire(import.meta.url),css=source('app/globals.css');assert.doesNotThrow(()=>require('postcss').parse(css));
 assert.ok(css.indexOf('/* A compact teacher stays in view')>css.indexOf('.agent-room{'));
 assert.ok(css.includes('.agent-teacher.agent-teacher-pinned { position:sticky;'));
 for(const selector of ['activation-room','activation-scene','activation-tasks','activation-navigation','lesson-slots','lesson-clock-track','lesson-price-profile','lesson-gate-rail'])assert.ok(css.includes('.'+selector));
 const agent=source('components/studio-agent.tsx');assert.ok(agent.indexOf('<aside className="agent-teacher agent-teacher-pinned"')<agent.indexOf('<section className="agent-chat-library"'));
 assert.ok(source('components/studio-help.tsx').includes('[allowMotion,setAllowMotion]=useState(true)'));
});

test('market coins continuously autoplay without a start button, including mobile fallback',()=>{
 const orbit=source('components/studio-market-orbit.tsx'),css=source('app/globals.css');assert.ok(orbit.includes('activeTime += dt'));assert.ok(orbit.includes('data-autoplay="true"'));assert.ok(!orbit.includes('<button'));assert.ok(!orbit.includes('pausedRef'));assert.ok(orbit.includes('document.hidden'));assert.ok(orbit.includes('cancelAnimationFrame'));
 assert.ok(css.includes('.studio-orbit[data-autoplay=true] .studio-fallback-coin { position:absolute; animation:studio-coin-flow'));
});
