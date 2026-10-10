"use client";
import { UiText, useLanguage } from './language-provider';
import { useEffect, useState, useCallback, useRef, useId } from "react";
import { Activity, Download, Play, Save, Search, ShieldCheck, Terminal, Square, Library, ArrowUpRight, SlidersHorizontal, ScanLine, Clock3, GitBranch, Gauge, Waves, Layers, Globe2, Wallet, Boxes, Check, LoaderCircle } from "lucide-react";
import { eaCatalog, defaultConfiguration, universalConfigurationSchema, type Control, type Family, type UniversalConfiguration } from "@/lib/universal-contract";
import type { BacktestResult, BacktestRequest } from "@/lib/control-contract";
import LeverSwitch from "./lever-switch";
import ConsoleWindow from "./console-window";
import { CONTROL_API,CONTROL_CREDENTIALS,CONTROL_TIMEOUT_MS} from '@/lib/control-endpoint';
import HelpButton from './studio-help';
import TutorRobot from './tutor-robot';
import { basicKeys, blockedReason, controlGroup, controlHelp, controlLabel, familySummary, helpTopics, safeConfiguration, friendlyError, starterRules, auditMatchesConnection } from '@/lib/studio-help';
import { localizedHelp } from '@/lib/localized-help';
import { useMotionPreference } from '@/lib/use-motion-preference';
import StudioAgent from './studio-agent';
import type { AgentPlan } from '@/lib/studio-agent';
import type { TutorMood } from '@/lib/tutor-behavior';
import {requestEaPackage,downloadEaBlob} from '@/lib/ea-download';
import EaActivationGuide from './ea-activation-guide';
import SharedStrategyLibrary from './shared-strategy-library';
import AuthProgress from './auth-progress';
import AuditProgress from './audit-progress';

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
type TerminalStatus={installationId:string;symbol:string;brokerServer:string;accountLogin:string;reportedAt:number;trading:boolean;openPositions:number;error:string};
type Session={accountId:string;displayName:string;email:string|null;subscriptionActive:boolean;entitlementUntil:number;installations:{id:string;label:string;state:string}[];
  accessMode:"demo"|"paid"|"inactive";trial:{startsAt:number;expiresAt:number;daysRemaining:number}|null;
  lease:{installationId:string;active:boolean;controlledHere:boolean}|null;trading:{enabled:boolean;jobId:string|null};terminalStatuses:TerminalStatus[]};
type Job={id:string;state:string;failureCode:string|null;request:BacktestRequest;configurationHash:string;createdAt?:number;updatedAt?:number;
  progress:{phase:string;processed:number;total:number|null;detail?:string}|null;result:(BacktestResult&{summary:{wins:number;losses:number;flat:number;open:number;data:number;netR:number;winRate:number|null;maxClosedDrawdownR:number;coverageComplete:boolean}})|null};
async function api<T=unknown>(path:string,token:string,body?:unknown):Promise<T>{
  const res=await fetch(API+path,{method:body===undefined?"GET":"POST",headers:{Authorization:`Bearer ${token}`,"Content-Type":"application/json"},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(CONTROL_TIMEOUT_MS),redirect:"error",credentials:CONTROL_CREDENTIALS,cache:"no-store"});
  const data=await res.json() as {error?:string};if(!res.ok)throw new Error(data.error??"SERVICE_UNAVAILABLE");return data as T;
}
const duration=(v:number|string|boolean)=>typeof v==="string"?v:`${String(Math.floor(Number(v)/60)).padStart(2,"0")}:${String(Number(v)%60).padStart(2,"0")}`;
function prepare(c:UniversalConfiguration){
  return universalConfigurationSchema.parse(safeConfiguration(c));
}
function ControlField({spec,value,onChange}:{spec:Control;value:string|number|boolean;onChange:(value:string|number|boolean)=>void}){
 const {t,locale}=useLanguage();
  const id=useId(),name=t(controlLabel(spec.key)),help={...controlHelp(spec),currentValue:value},copy=localizedHelp(help,locale);
  const wait=["nasWaitMinutes","reverseWaitMinutes"].includes(spec.key);
  if(spec.type==="bool")return <div className="uc-field uc-lever-field"><div className="uc-field-heading"><span>{name}</span><HelpButton topic={help}/></div><LeverSwitch label={name} description={copy.summary} checked={!!value} onChange={onChange}/></div>;
  return <div className="uc-field"><div className="uc-field-heading"><label htmlFor={id}><UiText>{name}</UiText></label><HelpButton topic={help}/></div>
    {spec.options?.length?<select id={id} aria-describedby={id+'-hint'} value={String(value)} onChange={e=>onChange(Number(e.target.value))}>{spec.options.map(o=><option key={o.value} value={o.value}><UiText>{o.label==='MA_CROSS_LAB_RULES'?'Custom BUY / SELL rules':o.label.replace(/^(MA_CROSS_|ORB_|ERL_|PERIOD_)/,'').replaceAll('_',' ')}</UiText></option>)}</select>:
      spec.key==="entryPreset"?<select id={id} value={String(value)} onChange={e=>onChange(Number(e.target.value))}>{["Built-in / Custom selection","Slow EMA + ADX","EMA Pullback","RSI 50-Line Momentum","Fast EMA + RSI","Bollinger Mean-Reversion","ATR Micro-Breakout","EMA + RSI Re-entry","Ultra-Fast EMA State","Candle Momentum","Hyperactive Directional Flip"].map((n,i)=><option key={n} value={i}>{t(n)}</option>)}</select>:
      spec.key==="nasGate"||spec.key==="nasExit"?<select id={id} value={String(value)} onChange={e=>onChange(Number(e.target.value))}>{(spec.key==="nasGate"?["OFF","ENTRY GATE","STATE GATE"]:["OFF","OPP EXIT","ADD EXIT"]).map((s,i)=><option key={s} value={i}><UiText>{s}</UiText></option>)}</select>:
      <input id={id} aria-label={name} aria-describedby={id+'-hint'} type={spec.type==="string"||wait?"text":"number"} step={spec.type==="double"?"any":"1"}
        placeholder={wait?'HH:MM':undefined} inputMode={wait?'text':spec.type==='string'?'text':'decimal'}
        value={wait?duration(value):String(value)} onChange={e=>onChange(spec.type==="string"||wait?e.target.value:Number(e.target.value))}/>
    }
    <small id={id+'-hint'} className="uc-field-hint">{copy.summary}</small>
  </div>;
}
const featureNames=["Close","Open","High","Low","RSI 14","ADX 14","ATR 14","EMA 9","EMA 20","EMA 50","EMA 200","HMA 200","Tick volume","Volume / prior 20 avg","Body / range","Range / ATR","RSI change","ADX change","Close - EMA20 / ATR","EMA50 cross above EMA200","EMA50 cross below EMA200","Bull FVG inside","Bear FVG inside","Bull FVG touch","Bear FVG touch","Bull FVG exists","Bear FVG exists","Hour","Weekday","Close change %","Upper wick / range","Lower wick / range","EMA(period)","SMA(period)","RSI(period)","ATR(period)","ADX Wilder(period)","HMA(period)","BB upper 1.5 SD","BB lower 1.5 SD","BB middle","Prior highest high","Prior lowest low","Body / Wilder ATR"];
function Builder({config,onChange}:{config:UniversalConfiguration;onChange:(c:UniversalConfiguration)=>void}){
 const {t}=useLanguage();
  const b=config.builder;
  const add=(side:"buy"|"sell"|"exitBuy"|"exitSell")=>{
    const base=b??{edge:false,buy:[],sell:[],exitBuy:[],exitSell:[],exitsEnabled:true,policy:false,atrPeriod:14,slAtr:1,tpAtr:1,cooldown:0,maxBars:0,maxMinutes:0};
    onChange({...config,builder:{...base,[side]:[...base[side],{feature:34,period:14,comparator:0,threshold:50,gate:0,negate:false,rhsFeature:-1,rhsPeriod:14}]}});
  };
  return <div className="uc-builder"><div className="guide-inline"><p><UiText>{"BUY opens long trades; SELL opens short trades. Start with one comparison, then add conditions. The exit sections close the corresponding position."}</UiText></p><HelpButton topic="builder"/></div>
    <p className="uc-caption"><UiText>{"AND = both true. OR = either true. XOR = exactly one true. NOT = reverse this row. All joins are evaluated left-to-right."}</UiText></p>
    {(["buy","sell","exitBuy","exitSell"] as const).map(side=><section key={side}><div className="uc-row"><h3><UiText>{side.toUpperCase()}</UiText></h3><button className="secondary-btn" onClick={()=>add(side)}><UiText>{"+ Condition"}</UiText></button></div>
      {(b?.[side]??[]).map((r,i)=>{const update=(patch:Partial<typeof r>)=>onChange({...config,builder:{...b!,[side]:b![side].map((row,j)=>i===j?{...row,...patch}:row)}});return <div className="uc-rule-card" key={i}><div className="guide-inline"><strong><UiText>{side.toUpperCase()}</UiText><UiText>{" / condition "}</UiText><UiText>{i+1}</UiText></strong><HelpButton topic="builder"/></div><div className="uc-rule">
        <label><UiText>{"Join"}</UiText><select aria-label={t("Logic gate")} value={r.gate} disabled={i===0} onChange={e=>update({gate:Number(e.target.value)})}>{["AND","OR","XOR"].map((n,i)=><option key={n} value={i}>{t(n)}</option>)}</select></label>
        <LeverSwitch compact label={t("NOT")} accessibleLabel={`${side} condition ${i+1}: NOT`} checked={r.negate} onChange={negate=>update({negate})}/>
        <label><UiText>{"Feature"}</UiText><select aria-label={t("Left feature")} value={r.feature} onChange={e=>update({feature:Number(e.target.value)})}>{featureNames.map((n,i)=><option key={i} value={i}>{t(n)}</option>)}</select></label>
        <label><UiText>{"Period"}</UiText><input aria-label={t("Left period")} type="number" min="1" max="5000" value={r.period} onChange={e=>update({period:Number(e.target.value)})}/></label>
        <label><UiText>{"Compare"}</UiText><select aria-label={t("Comparator")} value={r.comparator} onChange={e=>update({comparator:Number(e.target.value)})}>{[">","<",">=","<=","=","!=","Cross above","Cross below"].map((n,i)=><option key={n} value={i}>{t(n)}</option>)}</select></label>
        <label><UiText>{"With"}</UiText><select aria-label={t("Right feature")} value={r.rhsFeature} onChange={e=>update({rhsFeature:Number(e.target.value)})}><option value={-1}><UiText>{"Constant"}</UiText></option>{featureNames.map((n,i)=><option key={i} value={i}>{t(n)}</option>)}</select></label>
        <label><UiText>{r.rhsFeature===-1?'Value':'Period'}</UiText><input aria-label={r.rhsFeature===-1?"Threshold":"Right period"} type="number" step="any" value={r.rhsFeature===-1?r.threshold:r.rhsPeriod} onChange={e=>update(r.rhsFeature===-1?{threshold:Number(e.target.value)}:{rhsPeriod:Number(e.target.value)})}/></label>
        <button aria-label={t("Remove condition")} className="text-btn" onClick={()=>onChange({...config,builder:{...b!,[side]:b![side].filter((_,j)=>j!==i)}})}><UiText>{"Remove"}</UiText></button>
      </div><p className="uc-caption"><UiText>{r.negate?'NOT ':''}</UiText><UiText>{featureNames[r.feature]}</UiText> <UiText>{r.feature>=32?`(${r.period})`:''}</UiText> {[">","<",">=","<=","=","!=","crosses above","crosses below"][r.comparator]} <UiText>{r.rhsFeature===-1?r.threshold:featureNames[r.rhsFeature]}</UiText><UiText>{r.rhsFeature>=32?` (${r.rhsPeriod})`:''}</UiText><UiText>{i===0?' / first condition: no join needed':''}</UiText></p></div>})}</section>)}
    {b&&<div className="uc-fields"><ControlField spec={{key:"edge",type:"bool",default:false,group:""}} value={b.edge} onChange={v=>onChange({...config,builder:{...b,edge:!!v}})}/><ControlField spec={{key:"exitsEnabled",type:"bool",default:true,group:""}} value={b.exitsEnabled} onChange={v=>onChange({...config,builder:{...b,exitsEnabled:!!v}})}/>
      {(["policy","cooldown","maxBars","maxMinutes"] as const).map(k=><ControlField key={k} spec={{key:k,type:k==="policy"?"bool":"int",default:0,group:""}} value={b[k]} onChange={v=>onChange({...config,builder:{...b,[k]:v}})}/>)}</div>}
  </div>;
}
function Matrix({config,onChange}:{config:UniversalConfiguration;onChange:(c:UniversalConfiguration)=>void}){
 const {t}=useLanguage();
  const set=(day:number,hour:number,enabled:boolean)=>onChange({...config,dayHourMasks:config.dayHourMasks.map((m,i)=>i===day?enabled?m|(1<<hour):m&~(1<<hour):m)});
  return <div className="uc-matrix"><div className="guide-inline"><p><UiText>{"Select allowed entry hours for each day. 9 means 09:00-10:00 in the broker calendar. Selections take effect only when the matrix switch is ON and you Apply."}</UiText></p><HelpButton topic="Time Matrix"/></div>{config.runtime.timeMatrixEnabled&&config.dayHourMasks.every(m=>m===0)&&<p role="alert" className="uc-error"><UiText>{"No hours selected: this filter will block every new entry."}</UiText></p>}<table><thead><tr><th><UiText>{"Day"}</UiText></th>{Array.from({length:24},(_,h)=><th key={h}><UiText>{h}</UiText></th>)}</tr></thead><tbody>{["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"].map((day,d)=><tr key={day}><th><UiText>{day}</UiText></th>{Array.from({length:24},(_,h)=><td key={h}><input aria-label={`${day} ${h}-${h+1}`} type="checkbox" checked={!!(config.dayHourMasks[d]&(1<<h))} onChange={e=>set(d,h,e.target.checked)}/></td>)}</tr>)}</tbody></table>
    <div className="uc-row"><button className="secondary-btn" onClick={()=>onChange({...config,dayHourMasks:Array(7).fill(0xffffff)})}><UiText>{"All Hours"}</UiText></button><button className="secondary-btn" onClick={()=>onChange({...config,dayHourMasks:Array(7).fill(0)})}><UiText>{"Clear Hours"}</UiText></button></div></div>;
}
export default function UniversalDashboard({credential,restoring=false,onCredential,onConnect}:{credential:string;restoring?:boolean;onCredential:(t:string)=>void;onConnect:()=>void}){
 const {t,locale}=useLanguage();
  const [sessionRecord,setSessionRecord]=useState<{credential:string;data:Session}|null>(null),[config,setConfig]=useState(()=>defaultConfiguration("entrylab"));
  const session=sessionRecord?.credential===credential?sessionRecord.data:null;
  const [selected,setSelected]=useState(""),[auditWeeks,setAuditWeeks]=useState(2),[group,setGroup]=useState("Entry / Execution"),[query,setQuery]=useState("");
  const [libraryRecord,setLibraryRecord]=useState<{credential:string;items:UniversalConfiguration[]}>({credential:"",items:[]}),[strategyQuery,setStrategyQuery]=useState(""),[jobRecord,setJobRecord]=useState<{credential:string;data:Job}|null>(null),[applied,setApplied]=useState("");
  const job=jobRecord?.credential===credential?jobRecord.data:null;
  const setJob=useCallback((data:Job|null)=>setJobRecord(data?{credential,data}:null),[credential]);
  const strategies=libraryRecord.credential===credential?libraryRecord.items:[];
  const setStrategies=useCallback((items:UniversalConfiguration[])=>setLibraryRecord({credential,items}),[credential]);
  const [busy,setBusy]=useState(false),[error,setError]=useState(""),[email,setEmail]=useState(""),[password,setPassword]=useState(""),[displayName,setDisplayName]=useState(""),[signup,setSignup]=useState(false),[page,setPage]=useState(0);
  const [pollError,setPollError]=useState('');
  const visibleError=error||pollError;
  const [panel,setPanel]=useState<"library"|"controls"|"builder"|null>(null);
  const [authNotice,setAuthNotice]=useState("");
  const [authPending,setAuthPending]=useState<'login'|'register'|null>(null);
  const authInFlight=useRef(false);
  const [downloadBusy,setDownloadBusy]=useState(false),[downloadError,setDownloadError]=useState('');
  const [downloadRecord,setDownloadRecord]=useState<{credential:string;url:string;filename:string}|null>(null);
  const downloadOwner=useRef(credential);downloadOwner.current=credential;
  useEffect(()=>{setDownloadRecord(null);setDownloadError('');},[credential]);
  useEffect(()=>()=>{if(downloadRecord)URL.revokeObjectURL(downloadRecord.url);},[downloadRecord]);
  async function downloadEa(){
    if(busy||downloadBusy||!session?.subscriptionActive)return;
    const owner=credential,filename=`Stratum-${session.accountId.slice(0,8)}.zip`;
    setBusy(true);setDownloadBusy(true);setDownloadError('');setError('');
    try{
      const blob=await requestEaPackage(owner);
      if(downloadOwner.current!==owner)return;
      const url=downloadEaBlob(blob,filename);setDownloadRecord({credential:owner,url,filename});
    }catch(e){if(downloadOwner.current===owner)setDownloadError(e instanceof Error?e.message:'EA_DOWNLOAD_FAILED');}
    finally{setDownloadBusy(false);setBusy(false);}
  }
  const [windowOpen,setWindowOpen]=useState(false),windowTrigger=useRef<HTMLButtonElement|null>(null);
  const [clock,setClock]=useState(0);
  const [expert,setExpert]=useState(false),[coachPaused,setCoachPaused]=useState(false),[coachMotion,setCoachMotion]=useState(false);
  const reducedMotion=useMotionPreference();
  const [agentMood,setAgentMood]=useState<TutorMood>('idle'),[coachEditing,setCoachEditing]=useState(false),previousDraft=useRef(JSON.stringify(config));
  const draftSignature=JSON.stringify(config);
  useEffect(()=>{if(previousDraft.current===draftSignature)return;previousDraft.current=draftSignature;setCoachEditing(true);const id=setTimeout(()=>setCoachEditing(false),1800);return()=>clearTimeout(id);},[draftSignature]);
  const [familyPending,setFamilyPending]=useState<Family|null>(null),[liveReview,setLiveReview]=useState(false),[liveAcknowledged,setLiveAcknowledged]=useState(false);
  const [appliedWeeks,setAppliedWeeks]=useState(2);
  useEffect(()=>{const id=setInterval(()=>setClock(Date.now()),3000);return()=>clearInterval(id);},[]);
  const openPanel=(next:"library"|"controls"|"builder",trigger:HTMLButtonElement)=>{windowTrigger.current=trigger;setPanel(next);setWindowOpen(true);};
  const refresh=useCallback(async()=>{if(!credential)return;const data=await api<Session>("/v1/session",credential);if(downloadOwner.current!==credential)return;setSessionRecord({credential,data});setPollError('');setClock(Date.now());setSelected(previous=>previous||data.lease?.installationId||data.installations.find((i:{state:string})=>i.state==="approved")?.id||"");},[credential]);
  const action=async(work:()=>Promise<void>)=>{if(busy)return;setBusy(true);setError("");try{await work();}catch(e){setError(e instanceof Error?e.message:"REQUEST_FAILED");}finally{setBusy(false);}};
  async function authenticate(){
    if(busy||authInFlight.current)return;
    const mode=signup?'register':'login';
    const payload={email,password,...(signup?{displayName:displayName.trim()}: {})};
    authInFlight.current=true;setAuthPending(mode);
    try{await action(async()=>{
      setAuthNotice('');
      const result=await api<{accessToken?:string;confirmationRequired?:boolean;message?:string}>(`/v1/auth/${mode}`,'',payload);
      if(result.confirmationRequired){setAuthNotice(result.message??'Confirm your email, then sign in.');setSignup(false);}
      else if(result.accessToken)onCredential(result.accessToken);
      else throw new Error('AUTH_SESSION_INVALID');
      setPassword('');
    });}finally{authInFlight.current=false;setAuthPending(null);}
  }
  useEffect(()=>{setPollError('');if(!credential)return;let alive=true,pending=false;const poll=async()=>{if(!alive||pending)return;pending=true;try{await refresh();}catch(e){if(alive){const message=e instanceof Error?e.message:"CONNECTION_FAILED";setPollError(message);if(["UNAUTHORIZED","SESSION_REVOKED","SESSION_SCOPE_MISMATCH"].includes(message))onCredential("");}}finally{pending=false;}};void poll();const id=setInterval(poll,3000);return()=>{alive=false;clearInterval(id);};},[credential,refresh,onCredential]);
  useEffect(()=>{if(!credential||!session?.subscriptionActive)return;let alive=true;void api<{strategies:UniversalConfiguration[]}>("/v1/strategies",credential).then(d=>{if(alive)setStrategies(d.strategies);}).catch(e=>{if(alive)setError(e.message);});return()=>{alive=false;};},[credential,session?.subscriptionActive,setStrategies]);
  const jobId=job?.id,jobState=job?.state;
  useEffect(()=>{if(!credential||!jobId||!jobState||!["queued","running"].includes(jobState))return;let alive=true,pending=false;const id=setInterval(()=>{if(!alive||pending)return;pending=true;void api<Job>(`/v1/jobs/${jobId}`,credential).then(data=>{if(alive)setJob(data);}).catch(e=>{if(alive)setError(e.message);}).finally(()=>{pending=false;});},1000);return()=>{alive=false;clearInterval(id);};},[credential,jobId,jobState,setJob]);
  const terminal=session?.terminalStatuses.find(t=>t.installationId===selected),online=!!terminal&&terminal.reportedAt>clock-15000&&clock>0;
  const running=job&&["queued","running"].includes(job.state),dirty=JSON.stringify(config)!==applied||auditWeeks!==appliedWeeks;
  const requestedOn=!!session?.trading.enabled, canStop=requestedOn||!!terminal?.trading;
  const permitted=session?.subscriptionActive&&session.lease?.active&&session.lease.controlledHere&&session.lease.installationId===selected&&online;
  const controls=[...eaCatalog[config.family].runtime.map(spec=>({spec:{...spec,group:controlGroup(spec)},kind:"runtime" as const})),...eaCatalog[config.family].inputs.map(spec=>({spec:{...spec,group:controlGroup(spec)},kind:"inputs" as const}))];
  const groups=[...new Set(controls.map(c=>c.spec.group))];
  const visible=controls.filter(c=>query?`${t(controlLabel(c.spec.key))} ${c.spec.key} ${localizedHelp(controlHelp(c.spec),locale).summary}`.toLowerCase().includes(query.toLowerCase()):c.spec.group===group);
  const update=(kind:"inputs"|"runtime",key:string,v:string|number|boolean)=>setConfig(c=>({...c,[kind]:{...c[kind],[key]:v}}));
  const validation=(()=>{try{prepare(config);return '';}catch(e){return e instanceof Error&&'issues' in e?((e as {issues:{message:string}[]}).issues[0]?.message??'Invalid settings'):e instanceof Error?e.message:'Invalid settings';}})();
  const matchingAudit=auditMatchesConnection(job?.request,selected,terminal);
  const readiness={signedIn:!!session,active:!!session?.subscriptionActive,selected:!!selected,online,controller:!!permitted,dirty,running:!!running,complete:matchingAudit&&job?.state==='completed'&&!!job.result?.summary.coverageComplete,hasData:!!job?.result?.summary.data,acknowledged:liveAcknowledged};
  const auditBlock=blockedReason(readiness)|| (validation?`Fix the draft before testing: ${validation}`:null);
  const liveBlock=blockedReason(readiness,true)|| (validation?`Fix the draft: ${validation}`:null);
  const changeFamily=(f:Family)=>{setConfig(defaultConfiguration(f));setGroup('Entry / Execution');setQuery('');setFamilyPending(null);};
  async function apply(configuration=config,window=auditWeeks){const snapshot=prepare(configuration);if(!terminal)throw new Error("TERMINAL_OFFLINE");const toUtc=new Date(Math.floor(Date.now()/1000)*1000).toISOString();
    const request={version:2,installationId:selected,idempotencyKey:crypto.randomUUID(),brokerServer:terminal.brokerServer,symbol:terminal.symbol,
      fromUtc:new Date(Date.parse(toUtc)-window*7*86400000).toISOString(),toUtc,dataPolicy:"existing_audit_semantics",auditWeeks:window,configuration:snapshot};
    setJob(await api<Job>("/v1/jobs",credential,request));setConfig(snapshot);setAuditWeeks(window);setApplied(JSON.stringify(snapshot));setAppliedWeeks(window);setPage(0);await refresh();}
  async function confirmAgent(plan:AgentPlan){
    if(busy)throw new Error('REQUEST_BUSY');
    const snapshot=prepare(plan.configuration);
    if(!session?.subscriptionActive)throw new Error('ENTITLEMENT_EXPIRED');
    if(plan.runAudit){const block=blockedReason(readiness);if(block)throw new Error(block);}
    if(plan.show==='builder'&&snapshot.family!=='entrylab')throw new Error('CUSTOM_RULES_REQUIRE_ENTRYLAB');
    setBusy(true);setError('');
    try{
      if(plan.save){await api('/v1/strategies',credential,snapshot);setStrategies((await api<{strategies:UniversalConfiguration[]}>('/v1/strategies',credential)).strategies);}
      setConfig(snapshot);setAuditWeeks(plan.auditWeeks);
      if(plan.runAudit)await apply(snapshot,plan.auditWeeks);
      if(plan.show){setQuery('');if(plan.show==='library'||plan.show==='builder')setPanel(plan.show);else{setPanel('controls');setGroup(plan.show);setExpert(true);}setWindowOpen(true);}
      if(plan.reviewTrading){setLiveAcknowledged(false);setLiveReview(true);}
    }finally{setBusy(false);}
  }
  const summary=job?.result?.summary;
  return <div className="universal-dashboard">
    <section className="guide-welcome" aria-label={t("Getting started")}>
      <div className="guide-welcome-copy"><span className="eyebrow"><UiText>{"YOUR FIRST RUN, WITHOUT THE GUESSWORK"}</UiText></span><h2><UiText>{"One step at a time."}</UiText></h2><p><UiText>{"Connect MT5. Choose your rules. Test them on history."}</UiText><br/><UiText>{"Trading stays off until you explicitly request it."}</UiText></p><div className="guide-inline"><HelpButton topic="start"><UiText>{"Show me how it works"}</UiText></HelpButton><div className="guide-view" role="group" aria-label={t("Dashboard complexity")}><button type="button" aria-pressed={!expert} onClick={()=>setExpert(false)}><UiText>{"Guided view"}</UiText></button><button type="button" aria-pressed={expert} onClick={()=>setExpert(true)}><UiText>{"Expert view"}</UiText></button></div></div></div>
      <aside className="guide-coach"><TutorRobot paused={coachPaused} allowMotion={coachMotion} mood={busy||running||coachEditing?'thinking':visibleError?'concern':agentMood}/><strong><UiText>{"Your studio guide"}</UiText></strong><StudioAgent key={credential||'anonymous'} credential={credential} active={!!session?.subscriptionActive} configuration={(()=>{try{return prepare(config);}catch{return config;}})()} auditWeeks={auditWeeks} symbol={terminal?.symbol??null} jobId={job?.id??null} summary={summary??null} resultIsCurrent={!!matchingAudit&&!dirty} strategies={strategies} connectionKey={`${selected}/${terminal?.symbol??''}/${terminal?.brokerServer??''}`} pending={busy} onMoodChange={setAgentMood} onConfirm={confirmAgent} onRestore={(c,w)=>{setConfig(structuredClone(c));setAuditWeeks(w);}}/><button type="button" className="text-btn" onClick={()=>{if(reducedMotion&&!coachMotion){setCoachMotion(true);setCoachPaused(false);}else setCoachPaused(p=>!p);}}><UiText>{reducedMotion&&!coachMotion?'Play this animation':coachPaused?'Resume robot':'Pause robot'}</UiText></button></aside>
    </section>
    <nav className="guide-journey" aria-label={t("Setup steps")}>{[
      ['1','Sign in','Your private demo workspace',!!session,'account'],
      ['2','Connect MT5',permitted?'Authorized and online':online?'Authorize this browser':'Download, pair, attach',!!permitted,'connect'],
      ['3','Choose & test','Rules, risk and a history window',job?.state==='completed'&&!dirty,'audit'],
      ['4','Review & decide','Inspect results before live use',!!terminal?.trading,'live']
    ].map(([n,title,hint,done,topic])=><div key={String(n)} data-done={!!done}><span className="guide-step-number">{done?<Check size={18}/>:n}</span><div><strong><UiText>{title}</UiText></strong><small><UiText>{hint}</UiText></small></div><HelpButton topic={String(topic)}/></div>)}</nav>
    {expert&&<div className="uc-workflow mono" aria-label={t("Execution workflow")}><span className="uc-workflow-current"><i/><UiText>{"01 / CONFIGURE"}</UiText></span><b><UiText>{"/"}</UiText></b><span className={running?"uc-workflow-current":""}><UiText>{"02 / "}</UiText><UiText>{running?"AUDIT RUNNING":"RESEARCH"}</UiText></span><b><UiText>{"/"}</UiText></b><span className={terminal?.trading?"uc-workflow-current":""}><UiText>{"03 / "}</UiText><UiText>{terminal?.trading?"LIVE AUTHORIZED":"EXECUTION LOCKED"}</UiText></span><small><UiText>{"EXPLICIT AUTHORITY. ALWAYS."}</UiText></small></div>}
    <div className="uc-authority surface" id="studio-account"><div className="uc-row"><div><span className="eyebrow"><UiText>{"STEP 1 / YOUR ACCOUNT"}</UiText></span><h2><UiText>{session?.displayName?`Hello, ${session.displayName}`:'Start with your own workspace'}</UiText></h2></div><HelpButton topic="account"/></div>
      {restoring||credential&&!session?<AuthProgress restoring={restoring} retrying={!!pollError} onRetry={()=>void action(refresh)}/>:
        !session?<><form className="uc-login" aria-busy={!!authPending} onSubmit={e=>{e.preventDefault();void authenticate();}}>
          {signup&&<label><UiText>{"Subscriber name"}</UiText><input required disabled={!!authPending} value={displayName} maxLength={60} onChange={e=>setDisplayName(e.target.value)} autoComplete="name"/></label>}
          <label><UiText>{"Email"}</UiText><input type="email" required disabled={!!authPending} value={email} onChange={e=>setEmail(e.target.value)} autoComplete="username"/></label>
          <label><UiText>{"Password"}</UiText><input type="password" required disabled={!!authPending} minLength={signup?12:1} value={password} onChange={e=>setPassword(e.target.value)} autoComplete={signup?"new-password":"current-password"}/></label>
          <button type="submit" className="primary-btn" disabled={busy}>
            {authPending&&<LoaderCircle className="uc-auth-spinner" size={18} aria-hidden="true"/>}<UiText>{authPending==='register'?'Creating your account...':authPending==='login'?'Signing you in...':signup?'Create Account':'Sign In'}</UiText>
          </button>
          <button type="button" className="text-btn" disabled={busy} onClick={()=>setSignup(!signup)}><UiText>{signup?"Already registered?":"Create an account"}</UiText></button>
        </form>
        {authPending&&<p role="status" aria-live="polite" className="uc-caption"><UiText>{'Your request is in progress. Please wait; do not submit again.'}</UiText></p>}
        {error&&<p role="alert" className="uc-error"><UiText>{friendlyError(error)}</UiText></p>}
        {authNotice&&<p role="status" className="uc-caption"><UiText>{authNotice}</UiText></p>}</>:
      <><div className="uc-status-grid"><div><small><UiText>{session.accessMode==="demo"?"30-day demo / one time":"Subscription"}</UiText></small><strong><UiText>{session.accessMode==="demo"?"DEMO":session.subscriptionActive?"ACTIVE":"INACTIVE"}</UiText></strong><span><UiText>{session.accessMode==="demo"?`${session.trial?.daysRemaining??0} days remaining / ends ${new Date(session.trial!.expiresAt).toLocaleDateString(locale)}`:session.subscriptionActive?`Until ${new Date(session.entitlementUntil).toLocaleString(locale)}`:"Demo ended. Subscribe to continue research or trading."}</UiText></span></div><div><small><UiText>{"MT5 installation"}</UiText></small><strong><UiText>{online?"CONNECTED":"STANDBY"}</UiText></strong><span><UiText>{terminal?`${terminal.symbol} / ${terminal.brokerServer}`:"Attach the connection EA and pair your device"}</UiText></span></div><div><small><UiText>{"Native positions"}</UiText></small><strong><UiText>{terminal?.openPositions??"--"}</UiText></strong><span><UiText>{"Protective management continues when trading is OFF"}</UiText></span></div></div>
      <div className="uc-row"><button className="secondary-btn" onClick={onConnect}><Terminal size={16}/><UiText>{"Connect / Manage MT5"}</UiText></button><HelpButton topic="connect"/><select aria-label={t("Installation")} value={selected} onChange={e=>setSelected(e.target.value)}><option value=""><UiText>{"Choose your approved connection"}</UiText></option>{session.installations.filter(i=>i.state==="approved").map(i=><option key={i.id} value={i.id}>{i.label}</option>)}</select>
        <button className="secondary-btn" disabled={!selected||busy||!session.subscriptionActive} onClick={()=>void action(async()=>{await api(`/v1/installations/${selected}/activate`,credential,{});await refresh();})}><UiText>{permitted?'This browser is authorized':'Authorize this browser'}</UiText></button><HelpButton topic="controller"/>
        <button className="secondary-btn" disabled={busy} onClick={()=>void action(async()=>{const data=await api<{url:string}>("/v1/subscription/checkout",credential,{});window.location.assign(data.url);})}><UiText>{"Subscription"}</UiText></button>
        <button type="button" className="primary-btn" disabled={busy||!session.subscriptionActive} onClick={()=>void downloadEa()}><Download size={17}/><UiText>{downloadBusy?"Preparing your EA package...":"Download your personalized EA"}</UiText></button>
        <button className="text-btn" onClick={()=>void action(async()=>{await api("/v1/auth/logout",credential,{});onCredential("");setJob(null);})}><UiText>{"Sign Out"}</UiText></button></div></>}
      {session&&downloadBusy&&<p role="status" className="uc-caption"><UiText>{"Preparing and verifying the signed EA package. Stay on this page."}</UiText></p>}
      {session&&downloadError&&<p role="alert" className="uc-error" data-download-error={downloadError}><UiText>{friendlyError(downloadError)}</UiText></p>}
      {session&&downloadRecord?.credential===credential&&<p role="status" className="uc-download-ready"><Check size={18}/><UiText>{"Your ZIP is ready and includes the EX5 and personal setup. If the browser did not start the download, use this link:"}</UiText><a href={downloadRecord.url} download={downloadRecord.filename}><UiText>{"Download ready ZIP"}</UiText></a></p>}
      <p className="uc-caption"><UiText>{"New accounts receive one 30-day demo from registration. The personalized ZIP includes the closed-source EA, companion and a single-use setup ticket. Pair it to this account within 5 minutes of starting the helper. Downloading again never restarts the demo. Need MT5? "}</UiText><a href="https://www.metatrader5.com/en/download" target="_blank" rel="noopener noreferrer"><UiText>{"Official MetaTrader 5 download"}</UiText></a><UiText>{"."}</UiText></p>
      <EaActivationGuide signedIn={!!session} active={!!session?.subscriptionActive} online={!!online} authorized={!!permitted} onConnect={onConnect}/>
    </div>
    <section className="uc-settings surface"><div className="uc-row"><div><span className="eyebrow"><UiText>{"ONE TERMINAL / FOUR ENGINE FAMILIES"}</UiText></span><h2><UiText>{"Build. Audit. Then authorize."}</UiText></h2></div><span className="uc-safe-state"><Square size={12}/><UiText>{terminal?.trading?"TERMINAL TRADING ON":"TRADING OFF"}</UiText></span></div>
      <div className="guide-inline guide-section-intro"><div><strong><UiText>{"Step 3 / Choose your signal engine"}</UiText></strong><p><UiText>{"This decides when a setup appears. Risk, filters and exits are configured separately."}</UiText></p></div><HelpButton topic="engines"/></div>
      <div className="uc-families">{(Object.keys(families) as Family[]).map(f=><button type="button" key={f} aria-pressed={config.family===f} className={config.family===f?"uc-selected":""} onClick={()=>{if(f===config.family)return;if(JSON.stringify(config)!==JSON.stringify(defaultConfiguration(config.family)))setFamilyPending(f);else changeFamily(f);}}><span><UiText>{families[f]}</UiText></span><small><UiText>{familySummary[f]}</UiText></small></button>)}</div>
      <div className="uc-core-controls"><div className="uc-section-heading"><span><UiText>{"Start with the essentials"}</UiText></span><HelpButton topic="Geometry"/></div><div className="uc-fields">{controls.filter(c=>(expert?[...basicKeys,'independent','maxOpen','reverseExit','reverseWaitMinutes','inversion','inverseMaxCostPct']:basicKeys).includes(c.spec.key)).map(({spec,kind})=><ControlField key={`${kind}.${spec.key}`} spec={spec} value={config[kind][spec.key]} onChange={v=>update(kind,spec.key,v)}/>)}</div>
      {!config.inputs.InpPipSlModeDefault&&<p className="uc-caption"><UiText>{"Pip stop is OFF: editing the pip number alone will not activate it. The engine keeps its applicable default stop model."}</UiText></p>}
      <p className="uc-caption"><UiText>{"Changing the view does not change any strategy value. Extra filters and exit rules remain in your draft even when hidden."}</UiText></p></div>
      <div className="uc-deck-heading"><div><span className="mono"><UiText>{"YOUR CONTROL DECK"}</UiText></span><h3><UiText>{"Make it your own."}</UiText></h3></div><span className="uc-loadout"><Library size={16}/>{config.name}</span></div>
      <div className="uc-module-grid">
        <button type="button" className="uc-module" data-tone="gold" onClick={event=>openPanel("library",event.currentTarget)}><span className="uc-module-icon"><Library size={25}/></span><span className="uc-module-copy"><strong><UiText>{"Strategy library"}</UiText></strong><span><UiText>{"Save, search & switch loadouts"}</UiText></span></span><ArrowUpRight size={18}/><small><UiText>{strategies.length}</UiText><UiText>{" SAVED"}</UiText></small></button>
        {groups.filter(g=>expert||['Entry / Execution','Positions','Time Matrix'].includes(g)).map(g=>{const m=moduleStyle[g]??{icon:SlidersHorizontal,tone:"blue",hint:"Fine-tune the engine"};return <button type="button" className="uc-module" data-tone={m.tone} key={g} onClick={event=>{setGroup(g);setQuery("");openPanel("controls",event.currentTarget);}}><span className="uc-module-icon"><m.icon size={25}/></span><span className="uc-module-copy"><strong><UiText>{g}</UiText></strong><span><UiText>{m.hint}</UiText></span></span><ArrowUpRight size={18}/><small>{controls.filter(c=>c.spec.group===g).length}<UiText>{" CONTROLS / HELP INSIDE"}</UiText></small></button>;})}
        {config.family==="entrylab"&&<button type="button" className="uc-module" data-tone="coral" onClick={event=>openPanel("builder",event.currentTarget)}><span className="uc-module-icon"><GitBranch size={25}/></span><span className="uc-module-copy"><strong><UiText>{"Entry builder"}</UiText></strong><span><UiText>{"Wire up your own logic"}</UiText></span></span><ArrowUpRight size={18}/><small><UiText>{"BUY / SELL RULES"}</UiText></small></button>}
      </div>
      {!expert&&<div className="guide-advanced"><div><strong><UiText>{"Need NAS, order flow, regimes or timezone controls?"}</UiText></strong><p><UiText>{"They are all still here. Expert view reveals the full desk without changing your setup."}</UiText></p></div><button type="button" className="secondary-btn" onClick={()=>setExpert(true)}><SlidersHorizontal size={17}/><UiText>{"Show expert controls"}</UiText></button></div>}
      {validation&&<p role="alert" className="uc-error"><UiText>{"Check this draft: "}</UiText><UiText>{validation}</UiText></p>}
      <div className="uc-apply"><div><label><UiText>{"History to test"}</UiText><select aria-label={t("Audit window")} value={auditWeeks} onChange={e=>setAuditWeeks(Number(e.target.value))}>{weeks.map(w=><option key={w} value={w}>{w<52?`${w} weeks`:`${w/52} ${w===52?'year':'years'}`}</option>)}</select></label><small><UiText>{dirty?"Draft not sent yet. Run an audit to apply.":"Current settings were sent to MT5."}</UiText></small></div><HelpButton topic="audit"/><button className="primary-btn" disabled={!!auditBlock||busy} onClick={()=>void action(apply)}>{busy||running?<LoaderCircle className="uc-auth-spinner" size={17}/>:<Activity size={17}/>}<UiText>{busy?"Sending request...":running?"Audit in progress":"Apply & Run MT5 Audit"}</UiText></button>
        {running&&<button className="secondary-btn" disabled={busy} onClick={()=>void action(async()=>setJob(await api<Job>(`/v1/jobs/${job!.id}/cancel`,credential,{})))}><UiText>{"Cancel Audit"}</UiText></button>}
        <button className={canStop?"uc-trading-on":"secondary-btn"} disabled={busy||(!canStop&&(!!validation||!!blockedReason({...readiness,acknowledged:true},true)))} onClick={()=>{if(canStop)void action(async()=>{await api('/v1/trading',credential,{installationId:selected,enabled:false,jobId:job?.id??null});await refresh();});else{setLiveAcknowledged(false);setLiveReview(true);}}}>{canStop?<Square size={15}/>:<Play size={15}/>} <UiText>{canStop?'Stop new entries':'Review Trading ON'}</UiText></button><HelpButton topic="live"/>
      </div><p className="uc-caption"><UiText>{"Apply never turns trading on. Trading OFF stops new entries, not the existing positions' protective SL/TP. Results are terminal-reported, using the existing production audit semantics, not a synthetic web backtest."}</UiText></p>
      {auditBlock&&<p className="guide-blocker" role="status"><ShieldCheck size={18}/><UiText>{auditBlock}</UiText></p>}
    </section>
    {running&&<div className="uc-progress"><strong><UiText>{"Audit request accepted. Trading remains OFF."}</UiText></strong><AuditProgress job={job} now={clock} terminalError={terminal?.error}/><a href="#mt5-audit-results"><UiText>{"View audit progress"}</UiText></a></div>}
    {visibleError&&credential&&<p role="alert" className="uc-error"><UiText>{friendlyError(visibleError)}</UiText></p>}
    {terminal?.error&&<p role="alert" className="uc-error"><UiText>{"MT5: "}</UiText><UiText>{friendlyError(terminal.error,job?.request.installationId===terminal.installationId&&job?.failureCode===terminal.error?job.progress?.detail:undefined)}</UiText></p>}
    <section id="mt5-audit-results" className="uc-results surface" aria-live="polite"><div className="uc-row"><div><span className="eyebrow"><UiText>{"STEP 4 / CHECK WHAT ACTUALLY HAPPENED"}</UiText></span><h2><UiText>{"MT5 Audit / "}</UiText><UiText>{job?.state??"No run yet"}</UiText></h2></div><HelpButton topic="results"/><span className="mono"><UiText>{job?`${job.request.symbol} / ${weekLabel(job.request.version===2?job.request.auditWeeks:2)}`:"WAITING FOR APPLY"}</UiText></span></div>
      {job&&<AuditProgress job={job} now={clock} terminalError={terminal?.error}/>}
      {job?.failureCode&&<p className="uc-error"><UiText>{friendlyError(job.failureCode,job.progress?.detail)}</UiText></p>}
      {summary?<><div className="uc-metrics">{[["Net PnL",`${summary.netR.toFixed(3)}R`],["Win Rate",summary.winRate===null?"--":`${summary.winRate.toFixed(2)}%`],["Closed Drawdown",`${summary.maxClosedDrawdownR.toFixed(3)}R`],["W / L / O",`${summary.wins} / ${summary.losses} / ${summary.open}`],["FLAT / DATA",`${summary.flat} / ${summary.data}`]].map(([k,v])=><div key={k}><div className="guide-inline"><small><UiText>{k}</UiText></small><HelpButton topic={k}/></div><strong>{v}</strong></div>)}</div><p className="uc-caption"><UiText>{"Unknown costs remain unknown. DATA rows are not counted as wins or losses. Closed drawdown is not floating account-equity drawdown."}</UiText></p>
      <div className="uc-trade-table"><table><thead><tr><th><UiText>{"Entry UTC"}</UiText></th><th><UiText>{"Direction"}</UiText></th><th><UiText>{"Entry / SL / TP"}</UiText></th><th><UiText>{"Exit"}</UiText></th><th><UiText>{"Outcome"}</UiText></th><th><UiText>{"Net R"}</UiText></th></tr></thead><tbody>{job!.result!.trades.slice(page*40,page*40+40).map(t=><tr key={t.id}><td><UiText>{t.entryUtc.replace("T"," ").slice(0,19)}</UiText></td><td><UiText>{t.direction}</UiText></td><td className="mono">{t.entryPrice}<UiText>{" / "}</UiText>{t.sl}<UiText>{" / "}</UiText>{t.tp}</td><td><UiText>{t.exitReason}</UiText></td><td><UiText>{t.outcome}</UiText></td><td>{t.netR===null?"--":t.netR.toFixed(4)}</td></tr>)}</tbody></table></div>
      <div className="uc-row"><button className="secondary-btn" disabled={page===0} onClick={()=>setPage(p=>p-1)}><UiText>{"Previous"}</UiText></button><span><UiText>{page+1}</UiText><UiText>{" / "}</UiText><UiText>{Math.max(1,Math.ceil(job!.result!.trades.length/40))}</UiText></span><button className="secondary-btn" disabled={(page+1)*40>=job!.result!.trades.length} onClick={()=>setPage(p=>p+1)}><UiText>{"Next"}</UiText></button></div></>:<p className="uc-empty"><UiText>{"Connect your installation, select the engine and settings, then Apply. Only real terminal results appear here."}</UiText></p>}
    </section>
    <ConsoleWindow open={windowOpen} onOpenChange={setWindowOpen} returnFocus={windowTrigger}
      title={panel==="library"?"Your strategy loadouts":panel==="builder"?"The entry workshop":group}
      tone={panel==="library"?"gold":panel==="builder"?"coral":moduleStyle[group]?.tone??"blue"}
      description={panel==="library"?"Your private saved configurations. Select a loadout to bring its exact settings onto the desk.":"Edits stay in your draft when this window closes. Apply sends the settings to MT5; it never turns trading on."}
      footer={<><span className="console-draft"><i/><UiText>{dirty?"Draft changes / not sent to MT5":"Applied configuration"}</UiText></span><button type="button" className="secondary-btn" onClick={()=>setWindowOpen(false)}><Check size={16}/><UiText>{"Keep & close"}</UiText></button><button type="button" className="primary-btn" disabled={!!auditBlock||busy} onClick={()=>void action(async()=>{await apply();setWindowOpen(false);})}><Activity size={16}/><UiText>{"Apply & audit"}</UiText></button></>}>
      {panel==="library"?<>
        <SharedStrategyLibrary credential={credential} onLoad={(configuration,symbol)=>{setConfig(configuration);setGroup("Entry / Execution");setQuery("");setWindowOpen(false);setAuthNotice(`${t('Loaded for')} ${symbol}. ${t('Attach the connection EA to the matching instrument before running an audit.')}`);}}/>
        <h3><UiText>Your saved setups</UiText></h3>
        <div className="guide-inline guide-section-intro"><p>{localizedHelp(helpTopics.library,locale).summary}<UiText>{" Loading only updates the draft."}</UiText></p><HelpButton topic="library"/></div>
        <div className="uc-library-save"><label><UiText>{"Setup name"}</UiText><input value={config.name} maxLength={70} onChange={e=>setConfig(c=>({...c,name:e.target.value}))}/></label><button type="button" className="primary-btn" disabled={!session?.subscriptionActive||busy||!!validation} onClick={()=>void action(async()=>{const c=prepare(config);await api("/v1/strategies",credential,c);setStrategies((await api<{strategies:UniversalConfiguration[]}>("/v1/strategies",credential)).strategies);})}><Save size={17}/><UiText>{"Save / Update"}</UiText></button></div>
        <label className="uc-library-search"><Search size={19}/><input value={strategyQuery} onChange={e=>setStrategyQuery(e.target.value)} placeholder={t("Find your strategy...")} aria-label={t("Search saved strategies")}/></label>
        <div className="uc-library-grid">{strategies.filter(c=>c.name.toLowerCase().includes(strategyQuery.toLowerCase())).map(c=><button type="button" className="uc-library-card" key={c.name} onClick={()=>{setConfig(structuredClone(c));setGroup("Entry / Execution");setQuery("");setWindowOpen(false);}}><span><Library size={21}/><UiText>{families[c.family]}</UiText></span><strong>{c.name}</strong><small><UiText>{String(c.runtime.targetR)}</UiText><UiText>{"R / "}</UiText><UiText>{c.runtime.independent?"INDEPENDENT":"LEGACY"}</UiText><ArrowUpRight size={18}/></small></button>)}</div>
        {!strategies.length?<div className="uc-window-empty"><Library size={38}/><h3><UiText>{"Your next idea belongs here."}</UiText></h3><p><UiText>{session?.subscriptionActive?"Name your setup above and save its exact settings.":"Sign in with an active subscription to save and load your private strategies."}</UiText></p></div>:!strategies.some(c=>c.name.toLowerCase().includes(strategyQuery.toLowerCase()))&&<p className="uc-empty"><UiText>{"No strategies match that search."}</UiText></p>}
      </>:panel==="builder"?<>
        <div className="uc-fields">{controls.filter(c=>c.spec.key==="InpMaCrossMode"||c.spec.key==="entryPreset").map(({spec,kind})=><ControlField key={spec.key} spec={spec} value={config[kind][spec.key]} onChange={v=>update(kind,spec.key,v)}/>)}</div>
        {config.inputs.InpMaCrossMode===6&&!config.runtime.entryPreset?<Builder config={config} onChange={setConfig}/>:<div className="uc-window-empty"><GitBranch size={38}/><h3><UiText>{"A workshop for your market logic."}</UiText></h3><p><UiText>{"Use the selectors above, or start an editable example: BUY when RSI(14) > 50, SELL when RSI(14) < 50. This is a teaching example, not a recommended trading strategy."}</UiText></p><HelpButton topic="builder"/><button type="button" className="secondary-btn" onClick={()=>setConfig(starterRules(config))}><UiText>{"Create example draft"}</UiText></button></div>}
      </>:<>
        <div className="uc-control-navigation"><nav aria-label={t("Settings groups")}>{groups.map(g=><button type="button" aria-pressed={g===group&&!query} key={g} className={g===group&&!query?"uc-selected":""} onClick={()=>{setGroup(g);setQuery("");}}><UiText>{g}</UiText></button>)}</nav><label><Search size={17}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={t("Find any EA control")} aria-label={t("Search controls")}/></label></div>
        {!query&&helpTopics[group]&&<div className="guide-inline guide-section-intro"><p>{localizedHelp(helpTopics[group],locale).summary}</p><HelpButton topic={group}/></div>}
        <div className="uc-fields">{visible.map(({spec,kind})=><ControlField key={`${kind}.${spec.key}`} spec={spec} value={config[kind][spec.key]} onChange={v=>update(kind,spec.key,v)}/>)}</div>
        {query&&!visible.length&&<p className="uc-empty"><UiText>{"No controls match that search."}</UiText></p>}
        {!query&&group==="Time Matrix"&&<Matrix config={config} onChange={setConfig}/>}
      </>}
      {validation&&<p role="alert" className="uc-error"><UiText>{"Check this draft: "}</UiText><UiText>{validation}</UiText></p>}
      {auditBlock&&<p className="guide-blocker"><UiText>{auditBlock}</UiText></p>}
      {visibleError&&<p role="alert" className="uc-error"><UiText>{friendlyError(visibleError)}</UiText></p>}
    </ConsoleWindow>
    <ConsoleWindow open={!!familyPending} onOpenChange={open=>{if(!open)setFamilyPending(null);}} title={t("Start with another engine?")} description={t("Changing engine families replaces this draft with the new family's defaults. Saved strategies are untouched.")} tone="gold"
      footer={<><button type="button" className="secondary-btn" onClick={()=>setFamilyPending(null)}><UiText>{"Keep my current draft"}</UiText></button><button type="button" className="primary-btn" onClick={()=>{if(familyPending)changeFamily(familyPending);}}><UiText>{"Use "}</UiText><UiText>{familyPending?families[familyPending]:'new engine'}</UiText><UiText>{" defaults"}</UiText></button></>}>
      <p><UiText>{"Your current draft is "}</UiText><strong>{config.name}</strong><UiText>{". Save it in Strategy library first if you want to return to these exact values later."}</UiText></p><HelpButton topic="engines"/>
    </ConsoleWindow>
    <ConsoleWindow open={liveReview} onOpenChange={open=>{setLiveReview(open);if(!open)setLiveAcknowledged(false);}} title={t("Review before Trading ON")} description={t("This requests real MT5 trading permission for the audited setup. The terminal still checks authorization and execution conditions.")} tone="coral"
      footer={<><button type="button" className="secondary-btn" onClick={()=>setLiveReview(false)}><UiText>{"Stay in research"}</UiText></button><button type="button" className="primary-btn" disabled={busy||!!liveBlock} onClick={()=>void action(async()=>{if(liveBlock)throw new Error(liveBlock);await api('/v1/trading',credential,{installationId:selected,enabled:true,jobId:job!.id});await refresh();setLiveReview(false);setLiveAcknowledged(false);})}><Play size={16}/><UiText>{"Confirm Trading ON"}</UiText></button></>}>
      <dl className="guide-review-grid"><div><dt><UiText>{"MT5 account / broker"}</UiText></dt><dd><UiText>{terminal?.accountLogin??'Unknown'}</UiText><UiText>{" / "}</UiText><UiText>{terminal?.brokerServer??'Offline'}</UiText></dd></div><div><dt><UiText>{"Chart instrument"}</UiText></dt><dd><UiText>{terminal?.symbol??'Offline'}</UiText></dd></div><div><dt><UiText>{"Setup / engine"}</UiText></dt><dd>{config.name}<UiText>{" / "}</UiText><UiText>{families[config.family]}</UiText></dd></div><div><dt><UiText>{"Intended risk / target"}</UiText></dt><dd><UiText>{String(config.inputs.InpRiskPerTradePct)}</UiText><UiText>{"% / "}</UiText><UiText>{String(config.runtime.targetR)}</UiText><UiText>{"R"}</UiText></dd></div><div><dt><UiText>{"Stop model"}</UiText></dt><dd><UiText>{config.inputs.InpPipSlModeDefault?`${config.inputs.InpPipSlPips} pips`:'Engine stop model'}</UiText></dd></div><div><dt><UiText>{"Position mode"}</UiText></dt><dd><UiText>{config.runtime.independent?`Independent / max ${config.runtime.maxOpen}`:'Legacy / one position'}</UiText></dd></div></dl>
      <p className="uc-caption"><UiText>{"Percentage risk applies only in the corresponding sizing mode. Broker minimum volume, margin and execution costs can change actual exposure. An audit is not a profit guarantee."}</UiText></p><HelpButton topic="live"/>
      <label className="guide-ack"><input type="checkbox" checked={liveAcknowledged} onChange={e=>setLiveAcknowledged(e.target.checked)}/><span><UiText>{"I checked this account, instrument, sizing and audit. I understand this can open real trades and Trading OFF only stops new entries."}</UiText></span></label>
      {liveBlock&&<p role="status" className="guide-blocker"><UiText>{liveBlock}</UiText></p>}{visibleError&&<p role="alert" className="uc-error"><UiText>{friendlyError(visibleError)}</UiText></p>}
    </ConsoleWindow>
  </div>;
}
