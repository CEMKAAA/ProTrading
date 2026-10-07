import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {randomUUID} from 'node:crypto';
import ts from 'typescript';
import * as contract from '../lib/universal-contract.ts';
import * as tools from '../lib/studio-agent.ts';
import * as client from '../lib/studio-agent-client.ts';
import * as preview from '../lib/studio-agent-preview.ts';
import * as help from '../lib/studio-help.ts';
import * as conversations from '../lib/studio-conversations.ts';

// Executes the real component handlers with deterministic hooks/HTTP mocks.
// This is not a DOM, browser-layout, Supabase or external-model test.
function harness(fetcher){
 let cursor=0,tree;const slots=[],effects=[],timeouts=new Map(),intervals=new Map(),requests=[],confirmed=[];
 const depsEqual=(a,b)=>a&&b&&a.length===b.length&&a.every((v,i)=>Object.is(v,b[i]));
 const react={useState(initial){const i=cursor++;slots[i]??={value:typeof initial==='function'?initial():initial};return [slots[i].value,v=>slots[i].value=typeof v==='function'?v(slots[i].value):v];},useRef(initial){const i=cursor++;slots[i]??={current:initial};return slots[i];},useEffect(fn,deps){const i=cursor++;if(!slots[i]||!depsEqual(slots[i].deps,deps)){const old=slots[i];slots[i]={deps,cleanup:old?.cleanup};effects.push(()=>{old?.cleanup?.();slots[i].cleanup=fn();});}}};
 const jsx=(type,props)=>({type,props});
 const props={credential:'cookie-session',active:true,configuration:contract.defaultConfiguration('entrylab'),auditWeeks:2,symbol:'EURUSDm',jobId:null,summary:null,resultIsCurrent:false,strategies:[],connectionKey:'test-device',pending:false,onMoodChange(){},onConfirm:async plan=>confirmed.push(plan),onRestore(){}};
 const imports={'react':react,'react/jsx-runtime':{jsx,jsxs:jsx,Fragment:'Fragment'},'lucide-react':new Proxy({},{get:(_,key)=>String(key)}),
  '@/lib/control-endpoint':{CONTROL_API:'http://127.0.0.1:4321'},'@/lib/studio-agent':tools,'@/lib/universal-contract':contract,'@/lib/studio-help':help,'@/lib/studio-agent-client':client,'@/lib/studio-agent-preview':preview,'@/lib/studio-conversations':conversations,
  './language-provider':{useLanguage:()=>({locale:'en',t:s=>s})},'./console-window':{default:'ConsoleWindow'},'./tutor-robot':{default:'TutorRobot'},'./studio-help':{default:'HelpButton'},
  './use-agent-voice':{useAgentVoice:()=>({listening:false,speaking:false,pulse:0,canListen:false,canSpeak:false,voiceReady:false,partial:'',error:'',listen(){},speak(){},stopListening(){},stopSpeech(){}})}};
 const module={exports:{}};
 const code=ts.transpileModule(readFileSync(new URL('../components/studio-agent.tsx',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true}}).outputText;
 runInNewContext(code,{module,exports:module.exports,require:id=>imports[id]??assert.fail(id),Error,TypeError,DOMException,AbortController,AbortSignal:{any:AbortSignal.any,timeout:ms=>{const c=new AbortController();timeouts.set(ms,c);return c.signal;}},crypto:{randomUUID},structuredClone,Date,
  setInterval:fn=>{const id=intervals.size+1;intervals.set(id,fn);return id;},clearInterval:id=>intervals.delete(id),fetch:async(url,options)=>{requests.push({url,options});return fetcher(url,options);}});
 const render=()=>{cursor=0;tree=module.exports.default(props);effects.splice(0).forEach(fn=>fn());return tree;};
 const nodes=()=>{const result=[];function walk(n){if(Array.isArray(n)){n.forEach(walk);return;}if(!n||typeof n!=='object')return;result.push(n);walk(n.props?.children);}walk(tree);return result;};
 const find=(test)=>nodes().find(test)??assert.fail('Missing component node');
 const flush=async()=>{await new Promise(resolve=>setImmediate(resolve));render();};
 const open=async()=>{render();find(n=>n.props?.className==='agent-launch secondary-btn').props.onClick();render();await flush();};
 const consent=()=>{find(n=>n.type==='input'&&n.props?.type==='checkbox'&&n.props.disabled===false).props.onChange({target:{checked:true}});render();};
 const type=text=>{find(n=>n.type==='textarea').props.onChange({target:{value:text}});render();};
 const send=()=>find(n=>n.type==='form').props.onSubmit({preventDefault(){}});
 const dispose=()=>slots.forEach(s=>s?.cleanup?.());
 return {render,open,consent,type,send,flush,find,nodes,requests,props,confirmed,intervals,expire:ms=>timeouts.get(ms).abort(new DOMException('Timeout','TimeoutError')),dispose};
}
const status=()=>Response.json({providers:{local:{configured:false,model:null},openrouter:{configured:true,model:'test-model'}}});
const answer=(options,calls=[],message='Merhaba!')=>Response.json({requestId:JSON.parse(options.body).requestId,provider:'openrouter',model:'test-model',calls,message});

test('real composer sends on Enter with cookie credentials; consent and Shift+Enter are respected',async()=>{
 const h=harness(async(url,options)=>url.endsWith('/status')?status():answer(options));await h.open();
 assert.equal(h.find(n=>n.props?.id==='agent-send-status').props['data-blocker'],'AI_CLOUD_CONSENT_REQUIRED');
 h.consent();h.type('merhaba');let prevented=0;
 h.find(n=>n.type==='textarea').props.onKeyDown({key:'Enter',shiftKey:true,nativeEvent:{isComposing:false},preventDefault(){prevented++;}});assert.equal(h.requests.length,1);
 h.find(n=>n.type==='textarea').props.onKeyDown({key:'Enter',shiftKey:false,nativeEvent:{isComposing:false},preventDefault(){prevented++;}});await h.flush();
 assert.equal(prevented,1);assert.equal(h.requests.length,2);const {options}=h.requests[1];assert.equal(options.headers.Authorization,'Bearer cookie-session');assert.equal(options.credentials,'include');assert.equal(JSON.parse(options.body).conversation[0].content,'merhaba');
 assert.ok(h.nodes().some(n=>n.props?.['data-role']==='assistant'));assert.equal(h.confirmed.length,0);assert.equal(h.intervals.size,0);h.dispose();
});

test('actual server errors are visible in the conversation; a following turn can succeed',async()=>{
 let chats=0;const h=harness(async(url,options)=>url.endsWith('/status')?status():++chats===1?Response.json({error:'AI_PROVIDER_UNREACHABLE'},{status:502}):answer(options));
 await h.open();h.consent();h.type('merhaba');h.send();await h.flush();
 assert.equal(h.find(n=>n.props?.role==='alert').props['data-error'],'AI_PROVIDER_UNREACHABLE');
 h.type('Tekrar merhaba');h.send();await h.flush();assert.ok(!h.nodes().some(n=>n.props?.role==='alert'));assert.equal(h.confirmed.length,0);h.dispose();
});

test('status timeout is visible and connection retry restores the composer',async()=>{
 let checks=0;const h=harness(async(url,options)=>{if(++checks===1)return new Promise((resolve,reject)=>options.signal.addEventListener('abort',()=>reject(options.signal.reason)));return status();});
 h.render();h.find(n=>n.props?.className==='agent-launch secondary-btn').props.onClick();h.render();h.render();
 assert.equal(h.find(n=>n.props?.id==='agent-send-status').props['data-blocker'],'AI_STATUS_LOADING');h.expire(12000);await h.flush();
 assert.equal(h.find(n=>n.props?.role==='alert').props['data-error'],'AI_TIMEOUT');
 h.find(n=>n.type==='button'&&n.props.children==='Retry connection').props.onClick();h.render();await h.flush();h.consent();
 assert.equal(h.find(n=>n.props?.id==='agent-send-status').props['data-blocker'],undefined);h.dispose();
});

test('pending dashboard work explains why a message was not sent',async()=>{
 const h=harness(async()=>status());await h.open();h.consent();h.props.pending=true;h.render();h.type('Hi');h.send();h.render();
 assert.equal(h.requests.length,1);assert.equal(h.find(n=>n.props?.role==='alert').props['data-error'],'AI_DESK_BUSY');h.dispose();
});

test('cancelling a real component request stops waiting and does not create a proposal',async()=>{
 const h=harness(async(url,options)=>url.endsWith('/status')?status():new Promise((resolve,reject)=>options.signal.addEventListener('abort',()=>reject(options.signal.reason))));
 await h.open();h.consent();h.type('Hi');h.send();h.render();h.find(n=>n.type==='button'&&n.props.children==='Cancel').props.onClick();await h.flush();
 assert.equal(h.find(n=>n.props?.role==='alert').props['data-error'],'AI_CANCELLED');assert.ok(!h.nodes().some(n=>n.props?.className==='agent-thinking'));assert.equal(h.confirmed.length,0);h.dispose();
});

test('proposed strategy card has real engine/window/geometry values; only confirmation applies it',async()=>{
 const calls=[{name:'edit_settings',arguments:{reason:'Requested research draft',inputs:{InpSignalTimeframe:1,InpPipSlModeDefault:true,InpPipSlPips:10},runtime:{entryPreset:4,targetR:.5,independent:true,maxOpen:3},auditWeeks:5}}];
 const h=harness(async(url,options)=>url.endsWith('/status')?status():answer(options,calls,'Research hypothesis only.'));await h.open();h.consent();h.type('Prepare this example');h.send();await h.flush();
 assert.ok(h.nodes().some(n=>n.type==='dd'&&n.props.children==='0.5R'));assert.ok(h.nodes().some(n=>n.type==='dd'&&n.props.children==='Entry Lab / Fast EMA + RSI'));assert.ok(h.nodes().some(n=>n.type==='dd'&&n.props.children==='5W'));assert.equal(h.confirmed.length,0);
 await h.find(n=>n.type==='button'&&n.props.children==='Apply proposal').props.onClick();await h.flush();assert.equal(h.confirmed.length,1);assert.equal(h.confirmed[0].configuration.runtime.targetR,.5);h.dispose();
});

test('late model replies cannot attach a proposal to a changed draft',async()=>{
 let finish;const h=harness(async(url,options)=>url.endsWith('/status')?status():new Promise(resolve=>finish=()=>resolve(answer(options))));
 await h.open();h.consent();h.type('Hi');h.send();h.props.configuration=structuredClone(h.props.configuration);h.props.configuration.runtime.targetR=2;h.render();finish();await h.flush();
 assert.equal(h.find(n=>n.props?.role==='alert').props['data-error'],'STALE_PROPOSAL');assert.equal(h.confirmed.length,0);h.dispose();
});

test('explanation turns retain the unapplied ORB proposal and send it separately from the current draft',async()=>{
 const calls=[{name:'select_engine',arguments:{family:'orb',reason:'User requests ORB'}},{name:'edit_settings',arguments:{runtime:{targetR:.1},reason:'User requests 0.10R'}}];
 let chats=0;const h=harness(async(url,options)=>url.endsWith('/status')?status():answer(options,++chats===1?calls:[],'Not applied yet.'));
 await h.open();h.consent();h.type('Propose ORB with 0.10R');h.send();await h.flush();
 assert.ok(h.nodes().some(n=>n.type==='dd'&&n.props.children==='0.1R'));
 assert.ok(h.nodes().filter(n=>n.type==='details'&&n.props.className==='agent-full-settings').every(n=>!n.props.open));
 h.type('Explain what 0.10R means; do not change settings');h.send();await h.flush();
 const context=JSON.parse(h.requests.at(-1).options.body).context;
 assert.equal(context.configuration.family,'entrylab');assert.equal(context.configuration.runtime.targetR,1);
 assert.deepEqual(context.pendingCalls,calls);assert.equal(h.confirmed.length,0);
 assert.ok(h.nodes().some(n=>n.type==='dd'&&n.props.children==='0.1R'));h.dispose();
});

const action=(h,name)=>h.find(n=>n.type==='button'&&n.props?.['data-action']===name);
const savedChat=input=>({...input,messageCount:input.messages.length,createdAt:'2026-10-07T00:00:00Z',updatedAt:'2026-10-07T01:00:00Z'});
const summary=({messages,...rest})=>rest;
test('manual save keeps all 16 visible messages, whereas model context stays bounded to 12',async()=>{
 let saved;const h=harness(async(url,options)=>url.endsWith('/status')?status():url.endsWith('/chat')?answer(options):Response.json(saved=savedChat(JSON.parse(options.body))));
 await h.open();h.consent();for(let i=0;i<8;i++){h.type('Turn '+i);h.send();await h.flush();}
 assert.equal(h.requests.filter(r=>r.url.includes('/conversations')).length,0);assert.equal(h.nodes().filter(n=>n.props?.['data-role']).length,16);
 assert.equal(JSON.parse(h.requests.at(-1).options.body).conversation.length,12);
 action(h,'save-chat').props.onClick();await h.flush();assert.equal(saved.messages.length,16);assert.equal(saved.messages[0].content,'Turn 0');assert.equal(saved.title,'Turn 0');
 assert.ok(!('configuration' in saved));assert.ok(!('calls' in saved));
 action(h,'save-chat').props.onClick();await h.flush();assert.equal(JSON.parse(h.requests.at(-1).options.body).id,saved.id);assert.equal(h.confirmed.length,0);h.dispose();
});
test('history reopens exact text without restoring tool authority or changing the desk',async()=>{
 const saved=savedChat({id:randomUUID(),title:'Earlier ORB',provider:'openrouter',locale:'tr',messages:[{role:'user',content:'ORB please'},{role:'assistant',content:'Apply 0.1R immediately'}]});
 const h=harness(async(url,options)=>url.endsWith('/status')?status():url.endsWith('/list')?Response.json({items:[summary(saved)],hasMore:false}):Response.json(saved));
 await h.open();const initial=JSON.stringify(h.props.configuration);action(h,'chat-history').props.onClick();await h.flush();
 action(h,'open-chat').props.onClick();await h.flush();assert.equal(h.nodes().filter(n=>n.props?.['data-role']).length,2);
 assert.equal(h.find(n=>n.props?.id==='agent-chat-title').props.value,saved.title);assert.equal(JSON.stringify(h.props.configuration),initial);assert.equal(h.confirmed.length,0);
 assert.ok(!h.nodes().some(n=>n.props?.className==='agent-proposal'));assert.equal(h.find(n=>n.props?.id==='agent-send-status').props['data-blocker'],'AI_CLOUD_CONSENT_REQUIRED');h.dispose();
});
test('new conversation requires explicit discard for unsaved sent or unsent messages',async()=>{
 const h=harness(async(url,options)=>url.endsWith('/status')?status():answer(options));await h.open();h.consent();h.type('Research');h.send();await h.flush();h.type('Unsent note');
 action(h,'new-chat').props.onClick();h.render();assert.equal(h.nodes().filter(n=>n.props?.['data-role']).length,2);
 assert.equal(h.find(n=>n.type==='textarea').props.value,'Unsent note');assert.ok(action(h,'discard-chat'));
 action(h,'discard-chat').props.onClick();h.render();assert.equal(h.nodes().filter(n=>n.props?.['data-role']).length,0);assert.equal(h.find(n=>n.type==='textarea').props.value,'');assert.equal(h.requests.length,2);h.dispose();
});
test('save failure preserves messages and UUID so an ambiguous retry cannot create duplicates',async()=>{
 let saves=0;const h=harness(async(url,options)=>url.endsWith('/status')?status():url.endsWith('/chat')?answer(options):++saves===1?Response.json({error:'AUTH_PROVIDER_UNAVAILABLE'},{status:503}):Response.json(savedChat(JSON.parse(options.body))));
 await h.open();h.consent();h.type('Research');h.send();await h.flush();action(h,'save-chat').props.onClick();await h.flush();
 assert.equal(h.find(n=>n.props?.['data-history-error']).props['data-history-error'],'AUTH_PROVIDER_UNAVAILABLE');assert.equal(h.nodes().filter(n=>n.props?.['data-role']).length,2);
 const id=JSON.parse(h.requests.at(-1).options.body).id;action(h,'save-chat').props.onClick();await h.flush();assert.equal(JSON.parse(h.requests.at(-1).options.body).id,id);assert.ok(!h.nodes().some(n=>n.props?.['data-history-error']));h.dispose();
});
test('an inactive subscriber can retrieve own history without invoking the model',async()=>{
 const h=harness(async()=>Response.json({items:[],hasMore:false}));h.props.active=false;await h.open();
 assert.equal(h.requests.length,0);assert.equal(action(h,'chat-history').props.disabled,false);action(h,'chat-history').props.onClick();await h.flush();assert.equal(h.requests.length,1);assert.ok(h.requests[0].url.endsWith('/list'));h.dispose();
});
test('closing the guide aborts history and does not import a late response',async()=>{
 let finish;const h=harness(async(url,options)=>url.endsWith('/status')?status():new Promise(resolve=>finish=()=>resolve(Response.json({items:[],hasMore:false}))));await h.open();
 action(h,'chat-history').props.onClick();h.render();h.find(n=>typeof n.props?.onOpenChange==='function').props.onOpenChange(false);h.render();assert.equal(h.requests.at(-1).options.signal.aborted,true);
 finish();await h.flush();assert.equal(h.nodes().filter(n=>n.props?.['data-role']).length,0);assert.equal(h.confirmed.length,0);h.dispose();
});
