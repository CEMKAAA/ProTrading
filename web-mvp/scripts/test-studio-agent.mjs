import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID,createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {Readable} from 'node:stream';
import {defaultConfiguration,eaCatalog,universalConfigurationSchema} from '../lib/universal-contract.ts';
import {planAgentActions,agentRequestSchema,modelTools} from '../lib/studio-agent.ts';
import {createStudioAgent,savedStrategyEvidence} from '../control-service/studio-agent.mjs';
import {controlHttp} from '../control-service/http.mjs';
import {ControlError} from '../control-service/control-plane.mjs';
import {tutorPose} from '../lib/tutor-behavior.ts';
import {strategyPreview,builderExpression,entryPresetNames,entryPresetGuide,builderFeatureNames,presetReferenceSha256} from '../lib/studio-agent-preview.ts';

const actor={accountId:'private-account',sessionId:'private-session'};
const env={STRATUM_AI_LOCAL_MODEL:'qwen3.5:9b',STRATUM_AI_OPENROUTER_MODEL:'owner-configured/model-id',STRATUM_AI_OPENROUTER_KEY:'secret-provider-key-not-for-browser'};
const request=(provider='openrouter')=>({provider,locale:'tr',cloudConsent:true,requestId:randomUUID(),conversation:[{role:'user',content:'Explain my current settings.'}],context:{configuration:defaultConfiguration('entrylab'),auditWeeks:2,jobId:null,symbol:'EURUSDm'}});
const call=(name,args={})=>({name,arguments:{reason:'Requested by the user',...args}});
const reply=(calls=[],text='Here is a proposal.')=>new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:text,tool_calls:calls.map(c=>({type:'function',function:{name:c.name,arguments:JSON.stringify(c.arguments)}}))}}]}),{status:200});
const forbidden=(promise,code)=>assert.rejects(promise,e=>e instanceof ControlError&&e.code===code);

test('all 742 current controls are addressable without modifying source configurations',()=>{
 let count=0;
 for(const family of Object.keys(eaCatalog))for(const kind of ['inputs','runtime'])for(const spec of eaCatalog[family][kind]){
  const base=defaultConfiguration(family),before=JSON.stringify(base),plan=planAgentActions(base,2,[call('edit_settings',{[kind]:{[spec.key]:spec.default}})]);
  assert.ok(universalConfigurationSchema.safeParse(plan.configuration).success);assert.equal(plan.changes.length,0);assert.equal(JSON.stringify(base),before);count++;
 }
 assert.equal(count,742);
});
test('risk, pips, wait and day/hour changes are one schema-checked draft',()=>{
 const c=defaultConfiguration('entrylab');const p=planAgentActions(c,2,[call('edit_settings',{inputs:{InpRiskPerTradePct:.5,InpPipSlModeDefault:true,InpPipSlPips:10},runtime:{targetR:1,maxOpen:10,independent:true,reverseWaitMinutes:300,timeMatrixEnabled:true},dayHourMasks:[0,1<<6,1<<13,0,0,0,0],auditWeeks:52})]);
 assert.equal(p.auditWeeks,52);assert.equal(p.configuration.runtime.reverseWaitMinutes,300);assert.equal(p.configuration.dayHourMasks[1],64);assert.equal(p.configuration.dayHourMasks[2],8192);assert.equal(c.runtime.reverseWaitMinutes,0);
});
test('unrecognized controls, wrong units and authority-changing tool calls fail closed',()=>{
 for(const calls of [[call('enable_trading')],[call('eval',{code:'evil'})],[call('edit_settings',{runtime:{accessToken:'evil'}})],[call('edit_settings',{runtime:{nasWaitMinutes:'05:00'}})],[call('edit_settings',{inputs:{InpRiskPerTradePct:101}})],[call('edit_settings',{runtime:{targetR:0}})],[call('edit_settings',{runtime:{maxOpen:0}})]])assert.throws(()=>planAgentActions(defaultConfiguration('entrylab'),2,calls));
 assert.ok(!modelTools.some(t=>/enable|subscribe|auth|execute|filesystem|http/.test(t.function.name)));
});
test('family/library replacements precede edits, never inherit previous values',()=>{
 const c=defaultConfiguration('entrylab');c.runtime.targetR=500;
 const p=planAgentActions(c,2,[call('select_engine',{family:'sol'})]);assert.deepEqual(p.configuration,defaultConfiguration('sol'));assert.equal(c.runtime.targetR,500);
 assert.throws(()=>planAgentActions(c,2,[call('edit_settings',{runtime:{targetR:1}}),call('select_engine',{family:'orb'})]));
 const saved=defaultConfiguration('orb');saved.name='Private ORB';saved.runtime.targetR=.5;
 const load=planAgentActions(c,2,[call('load_strategy',{name:saved.name})],[saved]);assert.deepEqual(load.configuration,saved);
 assert.throws(()=>planAgentActions(c,2,[call('load_strategy',{name:'Someone else'})],[saved]));
});

test('ORB and 0.10R are composed in one proposal without applying or running anything',()=>{
 const base=defaultConfiguration('entrylab'),before=structuredClone(base);
 const p=planAgentActions(base,2,[call('select_engine',{family:'orb'}),call('edit_settings',{runtime:{targetR:.1}})]);
 assert.equal(p.configuration.family,'orb');assert.equal(p.configuration.runtime.targetR,.1);
 assert.equal(p.configuration.inputs.InpRiskPerTradePct,defaultConfiguration('orb').inputs.InpRiskPerTradePct);
 assert.equal(p.runAudit,false);assert.equal(p.save,false);assert.equal(p.reviewTrading,false);assert.deepEqual(base,before);
 const rows=Object.fromEntries(strategyPreview(p.configuration,2,null).rows.map(r=>[r.label,r.value]));
 assert.equal(rows['Profit target (R)'],'0.1R');assert.equal(rows['Entry engine'],'Opening Range');
});

test('pending review is separately validated; neither current settings nor evidence are overwritten',async()=>{
 let sent;const agent=createStudioAgent({env,fetcher:async(url,init)=>{sent=JSON.parse(init.body);return reply([], 'This is still an unapplied proposal.');}});
 const r=request();r.context.symbol=null;r.context.pendingCalls=[call('select_engine',{family:'orb'}),call('edit_settings',{runtime:{targetR:.1}})];
 const answer=await agent.chat(r,{actor});assert.equal(answer.calls.length,0);
 const ctx=JSON.parse(sent.messages[1].content.slice(sent.messages[1].content.indexOf('{')));
 assert.equal(ctx.configuration.family,'entrylab');assert.equal(ctx.configuration.runtime.targetR,1);
 assert.equal(ctx.pendingProposal.state,'pending_review');assert.equal(ctx.pendingProposal.configuration.runtime.targetR,.1);
 assert.equal(ctx.pendingProposal.configuration.family,'orb');assert.equal(ctx.audit,null);assert.equal(ctx.connection.canDownloadPersonalizedEA,true);assert.equal(ctx.connection.chartKnown,false);
 for(const phrase of ['NOT the ORB range','personalized downloadable','SAME response','pendingProposal'])assert.ok(sent.messages[0].content.includes(phrase));
 let network=0;const invalid=createStudioAgent({env,fetcher:async()=>{network++;return reply();}});
 r.context.pendingCalls=[call('enable_trading')];await forbidden(invalid.chat(r,{actor}),'AI_INVALID_REQUEST');assert.equal(network,0);
 r.context.pendingCalls=[call('load_strategy',{name:'Other account strategy'})];await forbidden(invalid.chat(r,{actor}),'AI_INVALID_REQUEST');assert.equal(network,0);
});
test('custom BUY/SELL builder and policy are validated together, preserving exact feature IDs',()=>{
 const rule={feature:34,period:14,comparator:0,threshold:50,gate:0,negate:false,rhsFeature:-1,rhsPeriod:14};
 const builder={edge:false,buy:[rule],sell:[{...rule,comparator:1}],exitBuy:[],exitSell:[],exitsEnabled:false,policy:true,atrPeriod:14,slAtr:1,tpAtr:1,cooldown:5,maxBars:10,maxMinutes:0};
 const p=planAgentActions(defaultConfiguration('entrylab'),2,[call('edit_settings',{inputs:{InpMaCrossMode:6},runtime:{entryPreset:0},builder})]);assert.equal(p.configuration.builder.buy[0].feature,34);assert.equal(p.configuration.builder.cooldown,5);
 assert.throws(()=>planAgentActions(defaultConfiguration('macross'),2,[call('edit_settings',{builder})]));
});
test('calls are bounded and cannot sneak extra arguments or duplicate jobs',()=>{
 assert.throws(()=>planAgentActions(defaultConfiguration('entrylab'),2,Array(9).fill(call('run_audit'))));
 assert.throws(()=>planAgentActions(defaultConfiguration('entrylab'),2,[call('run_audit'),call('run_audit')]));
 assert.throws(()=>planAgentActions(defaultConfiguration('entrylab'),2,[call('review_trading',{enabled:true})]));
 const p=planAgentActions(defaultConfiguration('entrylab'),2,[call('review_trading')]);assert.equal(p.reviewTrading,true);assert.equal(p.runAudit,false);
});
test('provider selection is explicit; configuration/key never leaks through status',async()=>{
 const agent=createStudioAgent({env,fetcher:async()=>reply()});const status=agent.status();
 assert.ok(status.providers.openrouter.configured);assert.ok(status.providers.local.configured);assert.ok(!JSON.stringify(status).includes(env.STRATUM_AI_OPENROUTER_KEY));
 assert.equal(createStudioAgent({env:{}}).status().providers.openrouter.configured,false);
 for(const url of ['https://evil.example/v1','http://localhost:11434/v1','http://127.0.0.1:11434/v1?redirect=evil','http://user:pass@127.0.0.1:11434/v1'])assert.equal(createStudioAgent({env:{...env,STRATUM_AI_LOCAL_URL:url}}).status().providers.local.configured,false);
 await forbidden(agent.chat({...request(),cloudConsent:false},{actor}),'AI_CLOUD_CONSENT_REQUIRED');
});
test('cloud context uses real server summaries and excludes account/device secrets and raw trades',async()=>{
 let sent,options;
 const c=defaultConfiguration('entrylab');c.name='My private strategy';
 const job={state:'completed',request:{configuration:c,symbol:'EURUSDm',auditWeeks:2,fromUtc:'2026-09-01T00:00:00.000Z',toUtc:'2026-09-15T00:00:00.000Z',brokerServer:'private-broker',accountLogin:'secret-login'},result:{summary:{wins:10,losses:3,flat:1,open:0,data:0,netR:7.4,winRate:1000/13,maxClosedDrawdownR:2,coverageComplete:true,accountId:'must-not-leak'},trades:[{secret:'raw-trade-secret'}]}};
 const agent=createStudioAgent({env,fetcher:async(url,init)=>{assert.equal(url,'https://openrouter.ai/api/v1/chat/completions');options=init;sent=JSON.parse(init.body);return reply([call('edit_settings',{runtime:{targetR:2}})]);}});
 const r=request();r.context.configuration=c;const answer=await agent.chat(r,{actor,job,jobs:[job],strategies:[c]});
 assert.equal(answer.requestId,r.requestId);assert.equal(answer.calls[0].name,'edit_settings');assert.equal(options.redirect,'error');assert.equal(sent.tools.length,7);
 const raw=JSON.stringify(sent);for(const s of ['private-account','private-session','secret-login','private-broker','must-not-leak','raw-trade-secret',env.STRATUM_AI_OPENROUTER_KEY])assert.ok(!raw.includes(s),s);
 const ctx=JSON.parse(sent.messages[1].content.slice(sent.messages[1].content.indexOf('{')));assert.equal(ctx.audit.summary.netR,7.4);assert.equal(ctx.recentSavedAudits.length,1);assert.equal(ctx.recentSavedAudits[0].name,c.name);assert.equal(ctx.locale,'tr');assert.equal(ctx.audit.draftMatches,true);
 assert.ok(ctx.catalog.operationGuide.NAS.summary);assert.equal(ctx.catalog.entryPresets.length,11);assert.ok(ctx.catalog.controls['runtime.maxOpen'][0].definition.guide.summary.includes('simultaneously open positions'));
 assert.ok(Buffer.byteLength(options.body)<160000,'provider context remains bounded for the default draft');
});
test('local provider follows the same validated protocol; no manufactured fallback answer',async()=>{
 const agent=createStudioAgent({env,fetcher:async(url,options)=>{assert.equal(url,'http://127.0.0.1:11434/v1/chat/completions');assert.ok(!options.headers.Authorization);return reply();}});assert.equal((await agent.chat(request('local'),{actor})).provider,'local');
 await forbidden(createStudioAgent({env,fetcher:async()=>{throw new Error('offline');}}).chat(request(),{actor}),'AI_PROVIDER_UNREACHABLE');
 await forbidden(createStudioAgent({env:{},fetcher:async()=>{assert.fail('must not call provider');}}).chat(request(),{actor}),'AI_NOT_CONFIGURED');
});

test('strategy review is derived from the validated full draft, not model prose or only the diff',()=>{
 const base=defaultConfiguration('entrylab');
 const plan=planAgentActions(base,2,[call('edit_settings',{name:'Research example',inputs:{InpMaCrossMode:1,InpSignalTimeframe:1,InpPipSlModeDefault:true,InpPipSlPips:10},runtime:{entryPreset:4,targetR:.5,independent:true,maxOpen:3,nasGate:2,reverseExit:true,reverseWaitMinutes:300,timeMatrixEnabled:true},dayHourMasks:[0,1<<6,1<<13,0,0,0,0],auditWeeks:52})]);
 const preview=strategyPreview(plan.configuration,plan.auditWeeks,'EURUSDm'),rows=Object.fromEntries(preview.rows.map(r=>[r.label,r.value]));
 assert.equal(rows['Entry engine'],'Entry Lab / Fast EMA + RSI');assert.equal(rows['Audit window'],'1Y / 52W');assert.equal(rows['Profit target (R)'],'0.5R');assert.equal(rows['Stop model'],'10 pips');assert.equal(rows['Position mode'],'INDEPENDENT / 3');assert.equal(rows['Close on reverse signal'],'ON / 05:00');
 assert.equal(rows['NAS entry gate'],'STATE GATE');assert.deepEqual(preview.dayHourMasks[1].hours,[6]);assert.deepEqual(preview.dayHourMasks[2].hours,[13]);
 assert.equal(preview.settings.length,eaCatalog.entrylab.inputs.length+eaCatalog.entrylab.runtime.length);
 assert.ok(preview.settings.some(s=>s.key==='InpRiskPerTradePct'&&s.value==='1'));
 assert.equal(base.runtime.targetR,1);assert.equal(base.runtime.entryPreset,0);
 for(const family of Object.keys(eaCatalog)){const c=defaultConfiguration(family);assert.equal(strategyPreview(c,2,null).settings.length,eaCatalog[family].inputs.length+eaCatalog[family].runtime.length);}
 assert.equal(builderFeatureNames.length,44);assert.equal(entryPresetNames.length,11);
});

test('builder review preserves period, RHS feature, NOT and left-to-right AND/OR/XOR semantics',()=>{
 const row={feature:32,period:12,comparator:0,threshold:50,gate:0,negate:false,rhsFeature:32,rhsPeriod:26};
 const expression=builderExpression([row,{...row,feature:34,period:14,rhsFeature:-1,threshold:55,gate:1,negate:true},{...row,feature:36,period:14,threshold:22,rhsFeature:-1,gate:2}]);
 assert.equal(expression,'(((EMA(12) > EMA(26)) OR NOT (RSI(14) > 55)) XOR (ADX Wilder(14) > 22))');
});

test('preset descriptions are pinned to the reviewed native rules and exit-policy values',()=>{
 const source=readFileSync(new URL('../../IndicatorCodeExamples/entry_engine_lab/LabScalperPresets.mqh',import.meta.url));
 assert.equal(createHash('sha256').update(source).digest('hex'),presetReferenceSha256,'Native preset changed: re-review the assistant reference before releasing.');
 assert.deepEqual(entryPresetGuide.map(p=>p.cooldown),[5,3,2,1,1,1,1,0,0,0]);
 assert.deepEqual(entryPresetGuide.map(p=>p.maxBars),[0,0,0,10,0,8,0,6,4,3]);
 assert.equal(entryPresetGuide[6].maxMinutes,12);assert.equal(entryPresetGuide[2].exitBuy,'RSI(7)<48');assert.equal(entryPresetGuide[7].exitSell,'EMA(3)>EMA(8)');
 assert.ok(entryPresetGuide[5].buy.includes('current bar excluded'));assert.ok(entryPresetGuide[4].buy.includes('1.5 population SD'));
});
test('malformed, truncated, oversized and unsafe model output never becomes a plan',async()=>{
 for(const [response,code] of [[reply([call('enable_trading')]),'AI_INVALID_PROPOSAL'],[new Response('broken'),'AI_INVALID_RESPONSE'],[new Response(JSON.stringify({choices:[{finish_reason:'length',message:{content:'partial'}}]})),'AI_TRUNCATED_RESPONSE'],[new Response('x'.repeat(200000)),'AI_RESPONSE_TOO_LARGE'],[reply([],''),'AI_EMPTY_RESPONSE'],[new Response('{}',{status:429}),'AI_PROVIDER_RATE_LIMITED']])await forbidden(createStudioAgent({env,fetcher:async()=>response}).chat(request(),{actor}),code);
});
test('one in-flight request per account; rate budget is bounded and expires',async()=>{
 let finish;const agent=createStudioAgent({env,fetcher:()=>new Promise(resolve=>finish=()=>resolve(reply()))});
 const first=agent.chat(request(),{actor});await forbidden(agent.chat(request(),{actor}),'AI_BUSY');finish();await first;
 let time=0;const rated=createStudioAgent({env,now:()=>time,fetcher:async()=>reply()});for(let i=0;i<12;i++)await rated.chat(request(),{actor});await forbidden(rated.chat(request(),{actor}),'AI_RATE_LIMITED');time=60001;await rated.chat(request(),{actor});
});

test('credential, credits and model failures are distinct and cannot become a successful answer',async()=>{
 for(const [status,code] of [[401,'AI_PROVIDER_AUTH_FAILED'],[402,'AI_PROVIDER_CREDITS_REQUIRED'],[404,'AI_MODEL_UNAVAILABLE'],[503,'AI_PROVIDER_FAILED']])
  await forbidden(createStudioAgent({env,fetcher:async()=>new Response('{}',{status})}).chat(request(),{actor}),code);
});

test('early connection resets get one fresh-connection retry, without applying any action',async()=>{
 let sent=0;const events=[];
 const reset=()=>Object.assign(new TypeError('secret-provider-key-not-for-browser'),{cause:Object.assign(new Error('private conversation'),{code:'ECONNRESET'})});
 const agent=createStudioAgent({env,report:e=>events.push(e),fetcher:async(url,options)=>{
  assert.equal(options.headers.Connection,'close');if(++sent===1)throw reset();return reply([], 'Merhaba');
 }});
 const answer=await agent.chat(request(),{actor});assert.equal(sent,2);assert.equal(answer.message,'Merhaba');assert.equal(answer.calls.length,0);
 assert.equal(events[0].event,'assistant_transport_retry');assert.equal(events[1].event,'assistant_success');
 for(const secret of [env.STRATUM_AI_OPENROUTER_KEY,'private conversation',actor.accountId,actor.sessionId])assert.ok(!JSON.stringify(events).includes(secret));
 sent=0;const failing=createStudioAgent({env,fetcher:async()=>{sent++;throw reset();}});
 await forbidden(failing.chat(request(),{actor}),'AI_PROVIDER_UNREACHABLE');assert.equal(sent,2);
});

test('HTTP failures, partial responses, timeouts and cancellation are never retried',async()=>{
 for(const mode of ['http','body','timeout','cancel']){
  let sent=0;const parent=new AbortController();
  const agent=createStudioAgent({env,fetcher:async()=>{
   sent++;
   if(mode==='http')return new Response('{}',{status:503});
   if(mode==='body')return new Response(new ReadableStream({start(c){c.error(Object.assign(new Error('reset body'),{code:'ECONNRESET'}));}}));
   if(mode==='cancel')parent.abort();
   throw new DOMException('interrupted',mode==='timeout'?'TimeoutError':'AbortError');
  }});
  await forbidden(agent.chat(request(),{actor,signal:parent.signal}),mode==='http'?'AI_PROVIDER_FAILED':mode==='body'?'AI_PROVIDER_UNREACHABLE':mode==='timeout'?'AI_TIMEOUT':'AI_CANCELLED');
  assert.equal(sent,1);
 }
});

test('a record-integrity connection failure has one retry; certificate validation failures have none',async()=>{
 for(const code of ['ERR_SSL_SSLV3_ALERT_BAD_RECORD_MAC','CERT_HAS_EXPIRED','ERR_TLS_CERT_ALTNAME_INVALID']){
  let count=0;const agent=createStudioAgent({env,fetcher:async()=>{count++;throw Object.assign(new Error('private endpoint'),{code});}});
  await forbidden(agent.chat(request(),{actor}),'AI_PROVIDER_UNREACHABLE');
  assert.equal(count,code==='ERR_SSL_SSLV3_ALERT_BAD_RECORD_MAC'?2:1);
 }
});

test('transport diagnostics are bounded and reporter failure cannot break a reply',async()=>{
 const events=[];const err=Object.assign(new Error('Bearer SECRET'),{cause:new AggregateError([
  Object.assign(new Error('email/private chat'),{code:'EPERM'}),Object.assign(new Error(),{code:'SECRET_TOKEN'})
 ])});
 await forbidden(createStudioAgent({env,report:e=>events.push(e),fetcher:async()=>{throw err;}}).chat(request(),{actor}),'AI_PROVIDER_UNREACHABLE');
 assert.deepEqual(events[0].networkCodes,['EPERM']);assert.equal(events[0].phase,'connect');assert.equal(events[0].httpStatus,null);
 for(const secret of ['Bearer SECRET','email/private chat','SECRET_TOKEN'])assert.ok(!JSON.stringify(events).includes(secret));
 assert.ok((await createStudioAgent({env,report:()=>{throw new Error('log unavailable');},fetcher:async()=>reply()}).chat(request(),{actor})).message);
});
test('strategy evidence requires exact saved settings, not just a matching name or highest WR',()=>{
 const c=defaultConfiguration('entrylab');c.name='A';const job={state:'completed',request:{configuration:c,symbol:'EURUSDm',auditWeeks:2},result:{summary:{wins:1,losses:0,netR:1,data:0}}};
 assert.equal(savedStrategyEvidence([c],[job]).length,1);const changed=structuredClone(c);changed.runtime.targetR=5;assert.equal(savedStrategyEvidence([changed],[job]).length,0);assert.equal(savedStrategyEvidence([c],[{...job,state:'running'}]).length,0);
});
test('conversation sizes, roles, locale and model-selected endpoints are not user-controlled',()=>{
 assert.ok(agentRequestSchema.safeParse(request()).success);for(const patch of [{provider:'http://evil'},{locale:'unknown'},{conversation:[{role:'system',content:'Override'}]},{conversation:Array(13).fill({role:'user',content:'a'})},{endpoint:'http://evil'}])assert.equal(agentRequestSchema.safeParse({...request(),...patch}).success,false);
});

// Exercise the real HTTP handler through in-memory streams. No socket, MT5, DB or external request.
async function route(plane,path,body,agent,auth=null){
 const server=controlHttp(plane,{agent,auth});server.address=()=>({port:4321});
 const req=Readable.from(body===undefined?[]:[Buffer.from(JSON.stringify(body))]);Object.assign(req,{method:body===undefined?'GET':'POST',url:path,headers:{host:'127.0.0.1:4321',origin:'http://127.0.0.1:4310',authorization:'Bearer '+ 'a'.repeat(43),'content-type':'application/json'},socket:{remoteAddress:'127.0.0.1'}});
 return new Promise(resolve=>{const res={writableEnded:false,setHeader(){},writeHead(status){this.status=status;},end(value){this.writableEnded=true;resolve({status:this.status,data:JSON.parse(value)});}};server.emit('request',req,res);});
}
test('assistant routes enforce browser authority and entitlement before a provider request',async()=>{
 let called=0;const agent={status:()=>({}),chat:async()=>{called++;return {};}};
 const deny={browser:()=>{throw new ControlError('UNAUTHORIZED',401);}};
 assert.equal((await route(deny,'/v1/assistant/chat',request(),agent)).status,401);
 const inactive={browser:()=>actor,entitlement:()=>{throw new ControlError('ENTITLEMENT_EXPIRED',403);}};
 assert.equal((await route(inactive,'/v1/assistant/chat',request(),agent)).status,403);assert.equal(called,0);
 const plane={browser:()=>actor,entitlement:()=>{},strategies:()=>[],listJobs:()=>[],readJob:()=>{throw new ControlError('JOB_NOT_FOUND',404);}};
 assert.equal((await route(plane,'/v1/assistant/chat',request(),agent)).status,200);assert.equal(called,1);
 const foreign=request();foreign.context.jobId=randomUUID();assert.equal((await route(plane,'/v1/assistant/chat',foreign,agent)).status,404);assert.equal(called,1);
 const auth={forBrowser:async()=>{throw new ControlError('SESSION_REVOKED',401);}};assert.equal((await route(plane,'/v1/assistant/status',undefined,agent,auth)).status,401);
});
test('robot expressions are distinct, blink, look around and focus without non-finite motion',()=>{
 const idle=tutorPose(1,'idle'),other=tutorPose(5,'idle'),thinking=tutorPose(1,'thinking'),curious=tutorPose(1,'curious');assert.notEqual(idle.headYaw,other.headYaw);assert.ok(thinking.eyeHeight<idle.eyeHeight);assert.ok(thinking.armLift>0);assert.ok(curious.headPitch<0);assert.ok(tutorPose(5.86,'idle').eyeHeight<.1);
 for(const mood of ['idle','attentive','listening','thinking','curious','explaining','success','concern'])for(const moving of [false,true])for(const t of [0,1,7,300])for(const v of Object.values(tutorPose(t,mood,moving)))assert.ok(typeof v==='boolean'||Number.isFinite(v));
 assert.equal(tutorPose(1,'explaining').pointer,true);assert.equal(tutorPose(1,'thinking').pointer,false);assert.equal(tutorPose(5.86,'idle',false).eyeHeight,1);
});
