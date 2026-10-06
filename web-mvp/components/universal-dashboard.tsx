"use client";
import { useEffect, useState, useCallback, useRef } from "react";
import { Activity, Download, Play, Save, Search, ShieldCheck, Terminal, Square, Library, ArrowUpRight, SlidersHorizontal, ScanLine, Clock3, GitBranch, Gauge, Waves, Layers, Globe2, Wallet, Boxes, Check } from "lucide-react";
import { eaCatalog, defaultConfiguration, universalConfigurationSchema, type Control, type Family, type UniversalConfiguration } from "@/lib/universal-contract";
import type { BacktestResult, BacktestRequest } from "@/lib/control-contract";
import LeverSwitch from "./lever-switch";
import ConsoleWindow from "./console-window";
import { CONTROL_API } from '@/lib/control-endpoint';

const API=CONTROL_API;
const families:Record<Family,string>={entrylab:"Entry Lab",macross:"MA Crossover",orb:"Opening Range",sol:"Liquidity Narrative"};
const weeks=[2,5,10,20,52,104,156,208,260];
const weekLabel=(n:number)=>n<52?`${n}W`:`${n/52}Y`;
const moduleStyle:Record<string,{icon:typeof Activity;tone:string;hint:string}>={
  "Entry / Execution":{icon:GitBranch,tone:"blue",hint:"Choose the signal engine"},
  Geometry:{icon:SlidersHorizontal,tone:"gold",hint:"Stops, targets and R"},
  Positions:{icon:Boxes,tone:"coral",hint:"Independent / reverse exits"},
  NAS:{icon:Waves,tone:"mint",hint:"Entry gates and signal exits"},
  "Order Flow":{icon:ScanLine,tone:"mint",hint:"Activity, delta and pressure"},
  Regimes:{icon:Layers,tone:"blue",hint:"Market-state permissions"},
  Filters:{icon:Gauge,tone:"coral",hint:"Qualify the setup"},
  Risk:{icon:Wallet,tone:"gold",hint:"Balance and exposure"},
  Audit:{icon:Activity,tone:"blue",hint:"Research engine controls"},
  "Session / Timezone":{icon:Globe2,tone:"mint",hint:"Broker and exchange clocks"},
  "Time Matrix":{icon:Clock3,tone:"gold",hint:"Your days. Your hours."},
};
type TerminalStatus={installationId:string;symbol:string;brokerServer:string;reportedAt:number;trading:boolean;openPositions:number;error:string};
type Session={accountId:string;displayName:string;email:string|null;subscriptionActive:boolean;entitlementUntil:number;installations:{id:string;label:string;state:string}[];
  accessMode:"demo"|"paid"|"inactive";trial:{startsAt:number;expiresAt:number;daysRemaining:number}|null;
  lease:{installationId:string;active:boolean;controlledHere:boolean}|null;trading:{enabled:boolean;jobId:string|null};terminalStatuses:TerminalStatus[]};
type Job={id:string;state:string;failureCode:string|null;request:BacktestRequest;configurationHash:string;
  progress:{phase:string;processed:number;total:number|null}|null;result:(BacktestResult&{summary:{wins:number;losses:number;flat:number;open:number;data:number;netR:number;winRate:number|null;maxClosedDrawdownR:number;coverageComplete:boolean}})|null};
async function api<T=unknown>(path:string,token:string,body?:unknown):Promise<T>{
  const res=await fetch(API+path,{method:body===undefined?"GET":"POST",headers:{Authorization:`Bearer ${token}`,"Content-Type":"application/json"},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000),redirect:"error",credentials:"include",cache:"no-store"});
  const data=await res.json() as {error?:string};if(!res.ok)throw new Error(data.error??"SERVICE_UNAVAILABLE");return data as T;
}
const duration=(v:number|string|boolean)=>typeof v==="string"?v:`${String(Math.floor(Number(v)/60)).padStart(2,"0")}:${String(Number(v)%60).padStart(2,"0")}`;
function prepare(c:UniversalConfiguration){
  const copy=structuredClone(c);
  for(const k of ["reverseWaitMinutes","nasWaitMinutes"]){
    if(typeof copy.runtime[k]==="string"){
      const m=/^(\d{2}):(\d{2})$/.exec(String(copy.runtime[k]));if(!m||Number(m[2])>59)throw new Error("Wait requires HH:MM");
      copy.runtime[k]=Number(m[1])*60+Number(m[2]);
    }
  }
  return universalConfigurationSchema.parse(copy);
}
function label(key:string){
  const names:Record<string,string>={independent:"Independent positions",inversion:"Inverse direction",reverseExit:"Reverse signal exit",advancedAudit:"Advanced audit",nasStateVolume:"NAS state volume",nasFlowVolume:"NAS flow volume",InpPipSlModeDefault:"Pip-based stop loss"};
  return names[key]??key.replace(/^Inp/,'').replace(/([a-z0-9])([A-Z])/g,'$1 $2').replace(/Default$/,'').replace(/Minutes$/,' HH:MM');
}
function ControlField({spec,value,onChange}:{spec:Control;value:string|number|boolean;onChange:(value:string|number|boolean)=>void}){
  const wait=["nasWaitMinutes","reverseWaitMinutes"].includes(spec.key);
  if(spec.type==="bool")return <div className="uc-field uc-lever-field"><LeverSwitch label={label(spec.key)} description={spec.description??spec.key} checked={!!value} onChange={onChange}/></div>;
  return <label className="uc-field" title={spec.description??spec.key}>
    <span>{label(spec.key)}</span>
    {spec.options?.length?<select value={String(value)} onChange={e=>onChange(Number(e.target.value))}>{spec.options.map(o=><option key={o.value} value={o.value}>{o.label.replace(/^(MA_CROSS_|ORB_|ERL_|PERIOD_)/,'').replaceAll('_',' ')}</option>)}</select>:
      spec.key==="entryPreset"?<select value={String(value)} onChange={e=>onChange(Number(e.target.value))}>{["Built-in / Custom selection","Slow EMA + ADX","EMA Pullback","RSI 50-Line Momentum","Fast EMA + RSI","Bollinger Mean-Reversion","ATR Micro-Breakout","EMA + RSI Re-entry","Ultra-Fast EMA State","Candle Momentum","Hyperactive Directional Flip"].map((n,i)=><option key={n} value={i}>{n}</option>)}</select>:
      spec.key==="nasGate"||spec.key==="nasExit"?<select value={String(value)} onChange={e=>onChange(Number(e.target.value))}>{(spec.key==="nasGate"?["OFF","ENTRY GATE","STATE GATE"]:["OFF","OPP EXIT","ADD EXIT"]).map((s,i)=><option key={s} value={i}>{s}</option>)}</select>:
      <input aria-label={label(spec.key)} type={spec.type==="string"||wait?"text":"number"} step={spec.type==="double"?"any":"1"}
        value={wait?duration(value):String(value)} onChange={e=>onChange(spec.type==="string"||wait?e.target.value:Number(e.target.value))}/>
    }
  </label>;
}
const featureNames=["Close","Open","High","Low","RSI 14","ADX 14","ATR 14","EMA 9","EMA 20","EMA 50","EMA 200","HMA 200","Tick volume","Volume / prior 20 avg","Body / range","Range / ATR","RSI change","ADX change","Close - EMA20 / ATR","EMA50 cross above EMA200","EMA50 cross below EMA200","Bull FVG inside","Bear FVG inside","Bull FVG touch","Bear FVG touch","Bull FVG exists","Bear FVG exists","Hour","Weekday","Close change %","Upper wick / range","Lower wick / range","EMA(period)","SMA(period)","RSI(period)","ATR(period)","ADX Wilder(period)","HMA(period)","BB upper 1.5 SD","BB lower 1.5 SD","BB middle","Prior highest high","Prior lowest low","Body / Wilder ATR"];
function Builder({config,onChange}:{config:UniversalConfiguration;onChange:(c:UniversalConfiguration)=>void}){
  const b=config.builder;
  const add=(side:"buy"|"sell"|"exitBuy"|"exitSell")=>{
    const base=b??{edge:false,buy:[],sell:[],exitBuy:[],exitSell:[],exitsEnabled:true,policy:false,atrPeriod:14,slAtr:1,tpAtr:1,cooldown:0,maxBars:0,maxMinutes:0};
    onChange({...config,builder:{...base,[side]:[...base[side],{feature:34,period:14,comparator:0,threshold:50,gate:0,negate:false,rhsFeature:-1,rhsPeriod:14}]}});
  };
  return <div className="uc-builder"><p>Closed-bar rules. BUY and SELL are independent. Gates are evaluated left-to-right, exactly as in EntryLab.</p>
    {(["buy","sell","exitBuy","exitSell"] as const).map(side=><section key={side}><div className="uc-row"><h3>{side.toUpperCase()}</h3><button className="secondary-btn" onClick={()=>add(side)}>+ Condition</button></div>
      {(b?.[side]??[]).map((r,i)=>{const update=(patch:Partial<typeof r>)=>onChange({...config,builder:{...b!,[side]:b![side].map((row,j)=>i===j?{...row,...patch}:row)}});return <div className="uc-rule" key={i}>
        <select aria-label="Logic gate" value={r.gate} disabled={i===0} onChange={e=>update({gate:Number(e.target.value)})}>{["AND","OR","XOR"].map((n,i)=><option key={n} value={i}>{n}</option>)}</select>
        <LeverSwitch compact label="NOT" accessibleLabel={`${side} condition ${i+1}: NOT`} checked={r.negate} onChange={negate=>update({negate})}/>
        <select aria-label="Left feature" value={r.feature} onChange={e=>update({feature:Number(e.target.value)})}>{featureNames.map((n,i)=><option key={i} value={i}>{n}</option>)}</select>
        <input aria-label="Left period" type="number" min="1" max="5000" value={r.period} onChange={e=>update({period:Number(e.target.value)})}/>
        <select aria-label="Comparator" value={r.comparator} onChange={e=>update({comparator:Number(e.target.value)})}>{[">","<",">=","<=","=","!=","Cross above","Cross below"].map((n,i)=><option key={n} value={i}>{n}</option>)}</select>
        <select aria-label="Right feature" value={r.rhsFeature} onChange={e=>update({rhsFeature:Number(e.target.value)})}><option value={-1}>Constant</option>{featureNames.map((n,i)=><option key={i} value={i}>{n}</option>)}</select>
        <input aria-label={r.rhsFeature===-1?"Threshold":"Right period"} type="number" step="any" value={r.rhsFeature===-1?r.threshold:r.rhsPeriod} onChange={e=>update(r.rhsFeature===-1?{threshold:Number(e.target.value)}:{rhsPeriod:Number(e.target.value)})}/>
        <button aria-label="Remove condition" className="text-btn" onClick={()=>onChange({...config,builder:{...b!,[side]:b![side].filter((_,j)=>j!==i)}})}>Remove</button>
      </div>})}</section>)}
    {b&&<div className="uc-fields"><ControlField spec={{key:"edge",type:"bool",default:false,group:""}} value={b.edge} onChange={v=>onChange({...config,builder:{...b,edge:!!v}})}/><ControlField spec={{key:"exitsEnabled",type:"bool",default:true,group:""}} value={b.exitsEnabled} onChange={v=>onChange({...config,builder:{...b,exitsEnabled:!!v}})}/>
      {(["policy","atrPeriod","slAtr","tpAtr","cooldown","maxBars","maxMinutes"] as const).map(k=><ControlField key={k} spec={{key:k,type:k==="policy"?"bool":"double",default:0,group:""}} value={b[k]} onChange={v=>onChange({...config,builder:{...b,[k]:v}})}/>)}</div>}
  </div>;
}
function Matrix({config,onChange}:{config:UniversalConfiguration;onChange:(c:UniversalConfiguration)=>void}){
  const set=(day:number,hour:number,enabled:boolean)=>onChange({...config,dayHourMasks:config.dayHourMasks.map((m,i)=>i===day?enabled?m|(1<<hour):m&~(1<<hour):m)});
  return <div className="uc-matrix"><p>Broker-calendar hours; each day has its own independent hour mask.</p><table><thead><tr><th>Day</th>{Array.from({length:24},(_,h)=><th key={h}>{h}</th>)}</tr></thead><tbody>{["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"].map((day,d)=><tr key={day}><th>{day}</th>{Array.from({length:24},(_,h)=><td key={h}><input aria-label={`${day} ${h}-${h+1}`} type="checkbox" checked={!!(config.dayHourMasks[d]&(1<<h))} onChange={e=>set(d,h,e.target.checked)}/></td>)}</tr>)}</tbody></table>
    <div className="uc-row"><button className="secondary-btn" onClick={()=>onChange({...config,dayHourMasks:Array(7).fill(0xffffff)})}>All Hours</button><button className="secondary-btn" onClick={()=>onChange({...config,dayHourMasks:Array(7).fill(0)})}>Clear Hours</button></div></div>;
}
export default function UniversalDashboard({credential,onCredential,onConnect}:{credential:string;onCredential:(t:string)=>void;onConnect:()=>void}){
  const [sessionRecord,setSessionRecord]=useState<{credential:string;data:Session}|null>(null),[config,setConfig]=useState(()=>defaultConfiguration("entrylab"));
  const session=sessionRecord?.credential===credential?sessionRecord.data:null;
  const [selected,setSelected]=useState(""),[auditWeeks,setAuditWeeks]=useState(2),[group,setGroup]=useState("Entry / Execution"),[query,setQuery]=useState("");
  const [libraryRecord,setLibraryRecord]=useState<{credential:string;items:UniversalConfiguration[]}>({credential:"",items:[]}),[strategyQuery,setStrategyQuery]=useState(""),[jobRecord,setJobRecord]=useState<{credential:string;data:Job}|null>(null),[applied,setApplied]=useState("");
  const job=jobRecord?.credential===credential?jobRecord.data:null;
  const setJob=useCallback((data:Job|null)=>setJobRecord(data?{credential,data}:null),[credential]);
  const strategies=libraryRecord.credential===credential?libraryRecord.items:[];
  const setStrategies=useCallback((items:UniversalConfiguration[])=>setLibraryRecord({credential,items}),[credential]);
  const [busy,setBusy]=useState(false),[error,setError]=useState(""),[email,setEmail]=useState(""),[password,setPassword]=useState(""),[displayName,setDisplayName]=useState(""),[signup,setSignup]=useState(false),[page,setPage]=useState(0);
  const [panel,setPanel]=useState<"library"|"controls"|"builder"|null>(null);
  const [authNotice,setAuthNotice]=useState("");
  const [windowOpen,setWindowOpen]=useState(false),windowTrigger=useRef<HTMLButtonElement|null>(null);
  const [clock,setClock]=useState(0);
  useEffect(()=>{const id=setInterval(()=>setClock(Date.now()),3000);return()=>clearInterval(id);},[]);
  const openPanel=(next:"library"|"controls"|"builder",trigger:HTMLButtonElement)=>{windowTrigger.current=trigger;setPanel(next);setWindowOpen(true);};
  const refresh=useCallback(async()=>{if(!credential)return;const data=await api<Session>("/v1/session",credential);setSessionRecord({credential,data});setClock(Date.now());setSelected(previous=>previous||data.lease?.installationId||data.installations.find((i:{state:string})=>i.state==="approved")?.id||"");},[credential]);
  const action=async(work:()=>Promise<void>)=>{setBusy(true);setError("");try{await work();}catch(e){setError(e instanceof Error?e.message:"REQUEST_FAILED");}finally{setBusy(false);}};
  useEffect(()=>{if(!credential)return;let alive=true;const poll=async()=>{try{await refresh();}catch(e){if(alive){const message=e instanceof Error?e.message:"CONNECTION_FAILED";setError(message);if(["UNAUTHORIZED","SESSION_REVOKED","SESSION_SCOPE_MISMATCH"].includes(message))onCredential("");}}};void poll();const id=setInterval(poll,3000);return()=>{alive=false;clearInterval(id);};},[credential,refresh,onCredential]);
  useEffect(()=>{if(!credential||!session?.subscriptionActive)return;let alive=true;void api<{strategies:UniversalConfiguration[]}>("/v1/strategies",credential).then(d=>{if(alive)setStrategies(d.strategies);}).catch(e=>{if(alive)setError(e.message);});return()=>{alive=false;};},[credential,session?.subscriptionActive,setStrategies]);
  const jobId=job?.id,jobState=job?.state;
  useEffect(()=>{if(!credential||!jobId||!jobState||!["queued","running"].includes(jobState))return;let alive=true;const id=setInterval(()=>{void api<Job>(`/v1/jobs/${jobId}`,credential).then(data=>{if(alive)setJob(data);}).catch(e=>{if(alive)setError(e.message);});},1000);return()=>{alive=false;clearInterval(id);};},[credential,jobId,jobState,setJob]);
  const terminal=session?.terminalStatuses.find(t=>t.installationId===selected),online=!!terminal&&terminal.reportedAt>clock-15000&&clock>0;
  const running=job&&["queued","running"].includes(job.state),dirty=JSON.stringify(config)!==applied;
  const requestedOn=!!session?.trading.enabled, canStop=requestedOn||!!terminal?.trading;
  const permitted=session?.subscriptionActive&&session.lease?.active&&session.lease.controlledHere&&session.lease.installationId===selected&&online;
  const controls=[...eaCatalog[config.family].runtime.map(spec=>({spec,kind:"runtime" as const})),...eaCatalog[config.family].inputs.map(spec=>({spec,kind:"inputs" as const}))];
  const groups=[...new Set(controls.map(c=>c.spec.group))];
  const visible=controls.filter(c=>query?`${c.spec.key} ${c.spec.description??""}`.toLowerCase().includes(query.toLowerCase()):c.spec.group===group);
  const update=(kind:"inputs"|"runtime",key:string,v:string|number|boolean)=>setConfig(c=>({...c,[kind]:{...c[kind],[key]:v}}));
  async function apply(){const snapshot=prepare(config);if(!terminal)throw new Error("TERMINAL_OFFLINE");const toUtc=new Date(Math.floor(Date.now()/1000)*1000).toISOString();
    const request={version:2,installationId:selected,idempotencyKey:crypto.randomUUID(),brokerServer:terminal.brokerServer,symbol:terminal.symbol,
      fromUtc:new Date(Date.parse(toUtc)-auditWeeks*7*86400000).toISOString(),toUtc,dataPolicy:"existing_audit_semantics",auditWeeks,configuration:snapshot};
    setJob(await api<Job>("/v1/jobs",credential,request));setConfig(snapshot);setApplied(JSON.stringify(snapshot));setPage(0);await refresh();}
  const summary=job?.result?.summary;
  return <div className="universal-dashboard">
    <div className="uc-workflow mono" aria-label="Execution workflow"><span className="uc-workflow-current"><i/>01 / CONFIGURE</span><b>/</b><span className={running?"uc-workflow-current":""}>02 / {running?"AUDIT RUNNING":"RESEARCH"}</span><b>/</b><span className={terminal?.trading?"uc-workflow-current":""}>03 / {terminal?.trading?"LIVE AUTHORIZED":"EXECUTION LOCKED"}</span><small>EXPLICIT AUTHORITY. ALWAYS.</small></div>
    <div className="uc-authority surface"><div className="uc-row"><div><span className="eyebrow">CONTROL AUTHORITY</span><h2>{session?.email??"Your research desk"}</h2></div><ShieldCheck size={26}/></div>
      {!session?<><form className="uc-login" onSubmit={e=>{e.preventDefault();void action(async()=>{setAuthNotice("");const result=await api<{accessToken?:string;confirmationRequired?:boolean;message?:string}>(`/v1/auth/${signup?"register":"login"}`,"",{email,password,...(signup?{displayName:displayName.trim()}: {})});if(result.confirmationRequired){setAuthNotice(result.message??"Confirm your email, then sign in.");setSignup(false);}else if(result.accessToken)onCredential(result.accessToken);else throw new Error("AUTH_SESSION_INVALID");setPassword("");});}}>{signup&&<label>Subscriber name<input required value={displayName} maxLength={60} onChange={e=>setDisplayName(e.target.value)} autoComplete="name"/></label>}<label>Email<input type="email" required value={email} onChange={e=>setEmail(e.target.value)} autoComplete="username"/></label><label>Password<input type="password" required minLength={signup?12:1} value={password} onChange={e=>setPassword(e.target.value)} autoComplete={signup?"new-password":"current-password"}/></label><button className="primary-btn" disabled={busy}>{signup?"Create Account":"Sign In"}</button><button type="button" className="text-btn" onClick={()=>setSignup(!signup)}>{signup?"Already registered?":"Create an account"}</button></form>{authNotice&&<p role="status" className="uc-caption">{authNotice}</p>}</>:
      <><div className="uc-status-grid"><div><small>{session.accessMode==="demo"?"30-day demo / one time":"Subscription"}</small><strong>{session.accessMode==="demo"?"DEMO":session.subscriptionActive?"ACTIVE":"INACTIVE"}</strong><span>{session.accessMode==="demo"?`${session.trial?.daysRemaining??0} days remaining / ends ${new Date(session.trial!.expiresAt).toLocaleDateString()}`:session.subscriptionActive?`Until ${new Date(session.entitlementUntil).toLocaleString()}`:"Demo ended. Subscribe to continue research or trading."}</span></div><div><small>MT5 installation</small><strong>{online?"CONNECTED":"STANDBY"}</strong><span>{terminal?`${terminal.symbol} / ${terminal.brokerServer}`:"Attach the connection EA and pair your device"}</span></div><div><small>Native positions</small><strong>{terminal?.openPositions??"--"}</strong><span>Protective management continues when trading is OFF</span></div></div>
      <div className="uc-row"><button className="secondary-btn" onClick={onConnect}><Terminal size={16}/>Pair / Manage MT5</button><select aria-label="Installation" value={selected} onChange={e=>setSelected(e.target.value)}><option value="">Choose installation</option>{session.installations.filter(i=>i.state==="approved").map(i=><option key={i.id} value={i.id}>{i.label}</option>)}</select>
        <button className="secondary-btn" disabled={!selected||busy||!session.subscriptionActive} onClick={()=>void action(async()=>{await api(`/v1/installations/${selected}/activate`,credential,{});await refresh();})}>Authorize Controller</button>
        <button className="secondary-btn" disabled={busy} onClick={()=>void action(async()=>{const data=await api<{url:string}>("/v1/subscription/checkout",credential,{});window.location.assign(data.url);})}>Subscription</button>
        <button className="primary-btn" disabled={busy||!session.subscriptionActive} onClick={()=>void action(async()=>{const response=await fetch(API+"/v1/ea/package",{method:"POST",headers:{Authorization:`Bearer ${credential}`,"Content-Type":"application/json"},body:"{}",signal:AbortSignal.timeout(60000),cache:"no-store",redirect:"error",credentials:"include"});if(!response.ok)throw new Error(((await response.json()) as {error:string}).error);const url=URL.createObjectURL(await response.blob());const a=document.createElement("a");a.href=url;a.download=`Stratum-${session.accountId.slice(0,8)}.zip`;a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);})}><Download size={17}/>Download your personalized EA</button>
        <button className="text-btn" onClick={()=>void action(async()=>{await api("/v1/auth/logout",credential,{});onCredential("");setJob(null);})}>Sign Out</button></div></>}
      <p className="uc-caption">New accounts receive one 30-day demo from registration. The personalized ZIP includes the closed-source EA, companion and a single-use setup ticket. Pair it to this account within 5 minutes of starting the helper. Downloading again never restarts the demo. Need MT5? <a href="https://www.metatrader5.com/en/download" target="_blank" rel="noopener noreferrer">Official MetaTrader 5 download</a>.</p>
    </div>
    <section className="uc-settings surface"><div className="uc-row"><div><span className="eyebrow">ONE TERMINAL / FOUR ENGINE FAMILIES</span><h2>Build. Audit. Then authorize.</h2></div><span className="uc-safe-state"><Square size={12}/>{terminal?.trading?"TERMINAL TRADING ON":"TRADING OFF"}</span></div>
      <div className="uc-families">{(Object.keys(families) as Family[]).map(f=><button key={f} aria-pressed={config.family===f} className={config.family===f?"uc-selected":""} onClick={()=>{setConfig(defaultConfiguration(f));setGroup("Entry / Execution");setQuery("");}}><span>{families[f]}</span><small>{eaCatalog[f].inputs.length+eaCatalog[f].runtime.length} controls</small></button>)}</div>
      <div className="uc-core-controls"><div className="uc-section-heading"><span className="mono">GEOMETRY / EXPOSURE</span><small>Shared controls. Exact engine semantics.</small></div><div className="uc-fields">{["targetR","balance","independent","maxOpen","reverseExit","reverseWaitMinutes","inversion","inverseMaxCostPct"].map(key=>{const spec=eaCatalog[config.family].runtime.find(s=>s.key===key);return spec?<ControlField key={key} spec={spec} value={config.runtime[key]} onChange={v=>update("runtime",key,v)}/>:null;})}{["InpPipSlModeDefault","InpPipSlPips","InpRiskPerTradePct"].map(key=>{const spec=eaCatalog[config.family].inputs.find(s=>s.key===key);return spec?<ControlField key={key} spec={spec} value={config.inputs[key]} onChange={v=>update("inputs",key,v)}/>:null;})}</div></div>
      <div className="uc-deck-heading"><div><span className="mono">YOUR CONTROL DECK</span><h3>Make it your own.</h3></div><span className="uc-loadout"><Library size={16}/>{config.name}</span></div>
      <div className="uc-module-grid">
        <button type="button" className="uc-module" data-tone="gold" onClick={event=>openPanel("library",event.currentTarget)}><span className="uc-module-icon"><Library size={25}/></span><span className="uc-module-copy"><strong>Strategy library</strong><span>Save, search & switch loadouts</span></span><ArrowUpRight size={18}/><small>{strategies.length} SAVED</small></button>
        {groups.map(g=>{const m=moduleStyle[g]??{icon:SlidersHorizontal,tone:"blue",hint:"Fine-tune the engine"};return <button type="button" className="uc-module" data-tone={m.tone} key={g} onClick={event=>{setGroup(g);setQuery("");openPanel("controls",event.currentTarget);}}><span className="uc-module-icon"><m.icon size={25}/></span><span className="uc-module-copy"><strong>{g}</strong><span>{m.hint}</span></span><ArrowUpRight size={18}/><small>{controls.filter(c=>c.spec.group===g).length} CONTROLS</small></button>;})}
        {config.family==="entrylab"&&<button type="button" className="uc-module" data-tone="coral" onClick={event=>openPanel("builder",event.currentTarget)}><span className="uc-module-icon"><GitBranch size={25}/></span><span className="uc-module-copy"><strong>Entry builder</strong><span>Wire up your own logic</span></span><ArrowUpRight size={18}/><small>BUY / SELL RULES</small></button>}
      </div>
      <div className="uc-apply"><div><label>Audit window<select aria-label="Audit window" value={auditWeeks} onChange={e=>setAuditWeeks(Number(e.target.value))}>{weeks.map(w=><option key={w} value={w}>{weekLabel(w)}</option>)}</select></label><small>{dirty?"Unapplied changes. Trading ON is unavailable.":"Applied settings snapshot"}</small></div><button className="primary-btn" disabled={!permitted||busy||!!running} onClick={()=>void action(apply)}><Activity size={17}/>Apply & Run MT5 Audit</button>
        {running&&<button className="secondary-btn" disabled={busy} onClick={()=>void action(async()=>setJob(await api<Job>(`/v1/jobs/${job!.id}/cancel`,credential,{})))}>Cancel Audit</button>}
        <button className={canStop?"uc-trading-on":"secondary-btn"} disabled={busy||(!canStop&&(!permitted||dirty||job?.state!=="completed"||!!summary?.data||!summary?.coverageComplete))} onClick={()=>void action(async()=>{await api("/v1/trading",credential,{installationId:selected,enabled:!canStop,jobId:job?.id??null});await refresh();})}>{canStop?<Square size={15}/>:<Play size={15}/>}Trading {canStop?terminal?.trading?"ON: Turn OFF":"ON requested: Cancel / OFF":"OFF: Turn ON"}</button>
      </div><p className="uc-caption">Apply never turns trading on. Trading OFF stops new entries, not the existing positions&apos; protective SL/TP. Results are terminal-reported, using the existing production audit semantics, not a synthetic web backtest.</p>
    </section>
    {error&&<p role="alert" className="uc-error">{error==="BILLING_NOT_CONFIGURED"?"Payment provider not configured. This is a local pilot; no payment or subscription activation was fabricated.":error}</p>}
    {terminal?.error&&<p role="alert" className="uc-error">MT5: {terminal.error}</p>}
    <section className="uc-results surface" aria-live="polite"><div className="uc-row"><h2>MT5 Audit / {job?.state??"No run yet"}</h2><span className="mono">{job?`${job.request.symbol} / ${weekLabel(job.request.version===2?job.request.auditWeeks:2)}`:"WAITING FOR APPLY"}</span></div>
      {job?.progress&&<div className="uc-progress"><span>{job.progress.phase} / {job.progress.processed} {job.progress.total===null?"/ total unknown":`/ ${job.progress.total}`}</span>{job.progress.total!==null&&job.progress.total>0?<progress value={job.progress.processed} max={job.progress.total}/>:<p>Waiting for real broker history. No cosmetic completion estimate.</p>}</div>}
      {job?.failureCode&&<p className="uc-error">{job.failureCode}</p>}
      {summary?<><div className="uc-metrics">{[["Net PnL",`${summary.netR.toFixed(3)}R`],["Win Rate",summary.winRate===null?"--":`${summary.winRate.toFixed(2)}%`],["Closed Drawdown",`${summary.maxClosedDrawdownR.toFixed(3)}R`],["W / L / O",`${summary.wins} / ${summary.losses} / ${summary.open}`],["FLAT / DATA",`${summary.flat} / ${summary.data}`]].map(([k,v])=><div key={k}><small>{k}</small><strong>{v}</strong></div>)}</div><p className="uc-caption">Unknown costs remain unknown. DATA rows are not counted as wins or losses. Closed drawdown is not floating account-equity drawdown.</p>
      <div className="uc-trade-table"><table><thead><tr><th>Entry UTC</th><th>Direction</th><th>Entry / SL / TP</th><th>Exit</th><th>Outcome</th><th>Net R</th></tr></thead><tbody>{job!.result!.trades.slice(page*40,page*40+40).map(t=><tr key={t.id}><td>{t.entryUtc.replace("T"," ").slice(0,19)}</td><td>{t.direction}</td><td className="mono">{t.entryPrice} / {t.sl} / {t.tp}</td><td>{t.exitReason}</td><td>{t.outcome}</td><td>{t.netR===null?"--":t.netR.toFixed(4)}</td></tr>)}</tbody></table></div>
      <div className="uc-row"><button className="secondary-btn" disabled={page===0} onClick={()=>setPage(p=>p-1)}>Previous</button><span>{page+1} / {Math.max(1,Math.ceil(job!.result!.trades.length/40))}</span><button className="secondary-btn" disabled={(page+1)*40>=job!.result!.trades.length} onClick={()=>setPage(p=>p+1)}>Next</button></div></>:<p className="uc-empty">Connect your installation, select the engine and settings, then Apply. Only real terminal results appear here.</p>}
    </section>
    <ConsoleWindow open={windowOpen} onOpenChange={setWindowOpen} returnFocus={windowTrigger}
      title={panel==="library"?"Your strategy loadouts":panel==="builder"?"The entry workshop":group}
      tone={panel==="library"?"gold":panel==="builder"?"coral":moduleStyle[group]?.tone??"blue"}
      description={panel==="library"?"Your private saved configurations. Select a loadout to bring its exact settings onto the desk.":"Edits stay in your draft when this window closes. Apply sends the settings to MT5; it never turns trading on."}
      footer={<><span className="console-draft"><i/>{dirty?"Draft changes / not sent to MT5":"Applied configuration"}</span><button type="button" className="secondary-btn" onClick={()=>setWindowOpen(false)}><Check size={16}/>Keep & close</button><button type="button" className="primary-btn" disabled={!permitted||busy||!!running} onClick={()=>void action(async()=>{await apply();setWindowOpen(false);})}><Activity size={16}/>Apply & audit</button></>}>
      {panel==="library"?<>
        <div className="uc-library-save"><label>Setup name<input value={config.name} maxLength={70} onChange={e=>setConfig(c=>({...c,name:e.target.value}))}/></label><button type="button" className="primary-btn" disabled={!session?.subscriptionActive||busy} onClick={()=>void action(async()=>{const c=prepare(config);await api("/v1/strategies",credential,c);setStrategies((await api<{strategies:UniversalConfiguration[]}>("/v1/strategies",credential)).strategies);})}><Save size={17}/>Save / Update</button></div>
        <label className="uc-library-search"><Search size={19}/><input value={strategyQuery} onChange={e=>setStrategyQuery(e.target.value)} placeholder="Find your strategy..." aria-label="Search saved strategies"/></label>
        <div className="uc-library-grid">{strategies.filter(c=>c.name.toLowerCase().includes(strategyQuery.toLowerCase())).map(c=><button type="button" className="uc-library-card" key={c.name} onClick={()=>{setConfig(structuredClone(c));setGroup("Entry / Execution");setQuery("");setWindowOpen(false);}}><span><Library size={21}/>{families[c.family]}</span><strong>{c.name}</strong><small>{String(c.runtime.targetR)}R / {c.runtime.independent?"INDEPENDENT":"LEGACY"}<ArrowUpRight size={18}/></small></button>)}</div>
        {!strategies.length?<div className="uc-window-empty"><Library size={38}/><h3>Your next idea belongs here.</h3><p>{session?.subscriptionActive?"Name your setup above and save its exact settings.":"Sign in with an active subscription to save and load your private strategies."}</p></div>:!strategies.some(c=>c.name.toLowerCase().includes(strategyQuery.toLowerCase()))&&<p className="uc-empty">No strategies match that search.</p>}
      </>:panel==="builder"?<>
        <div className="uc-fields">{controls.filter(c=>c.spec.key==="InpMaCrossMode"||c.spec.key==="entryPreset").map(({spec,kind})=><ControlField key={spec.key} spec={spec} value={config[kind][spec.key]} onChange={v=>update(kind,spec.key,v)}/>)}</div>
        {config.inputs.InpMaCrossMode===6&&!config.runtime.entryPreset?<Builder config={config} onChange={setConfig}/>:<div className="uc-window-empty"><GitBranch size={38}/><h3>A workshop for your market logic.</h3><p>Built-in engines stay intact. Choose Custom in signal mode and Built-in / Custom selection in presets to edit independent BUY and SELL conditions.</p></div>}
      </>:<>
        <div className="uc-control-navigation"><nav aria-label="Settings groups">{groups.map(g=><button type="button" aria-pressed={g===group&&!query} key={g} className={g===group&&!query?"uc-selected":""} onClick={()=>{setGroup(g);setQuery("");}}>{g}</button>)}</nav><label><Search size={17}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Find any EA control" aria-label="Search controls"/></label></div>
        <div className="uc-fields">{visible.map(({spec,kind})=><ControlField key={`${kind}.${spec.key}`} spec={spec} value={config[kind][spec.key]} onChange={v=>update(kind,spec.key,v)}/>)}</div>
        {query&&!visible.length&&<p className="uc-empty">No controls match that search.</p>}
        {!query&&group==="Time Matrix"&&<Matrix config={config} onChange={setConfig}/>}
      </>}
      {error&&<p role="alert" className="uc-error">{error}</p>}
    </ConsoleWindow>
  </div>;
}
