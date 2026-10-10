// Read-only import of native libraries. Never infer settings from strategy names.
import {readFileSync,readdirSync,existsSync,mkdirSync,writeFileSync} from 'node:fs';
import {resolve,join,relative} from 'node:path';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {defaultConfiguration,universalConfigurationSchema,eaCatalog} from '../lib/universal-contract.ts';

const root=resolve(import.meta.dirname,'../..'),base=join(root,'IndicatorCodeExamples');
const common=resolve(process.env.APPDATA,'MetaQuotes/Terminal/Common/Files');
const dirs={orb:'orb',macross:'macrossover_orb',sol:'SolAdvanced',entrylab:'entry_engine_lab'};
const mains={orb:'OrbUltimateEA_StrategyLibrary.mq5',macross:'MaCrossOverOrbEA.mq5',sol:'LiqNarrativeSol_Advanced.mq5',entrylab:'EntryEngineLabEA.mq5'};
const sha=s=>createHash('sha256').update(s).digest('hex');
const clean=s=>s.replace(/\/\*[\s\S]*?\*\//g,'').replace(/\/\/[^\r\n]*/g,'');
function section(text,name){const at=text.indexOf(name+'(');if(at<0)throw Error('FUNCTION_MISSING:'+name);const start=text.indexOf('{',at);let depth=1,i=start+1;for(;depth&&i<text.length;i++){if(text[i]==='{')depth++;if(text[i]==='}')depth--;}return text.slice(start+1,i-1);}
function context(family,archivedSource){
 const source=archivedSource??readFileSync(join(base,dirs[family],mains[family]),'utf8');
 const flat=readFileSync(join(base,'universal/generated',family+'.mqh'),'utf8'),enums={};
 for(const m of flat.matchAll(/^\s*#define\s+(\w+)\s+(-?\d+)\s*$/gm))enums[m[1].replace(new RegExp('^'+family+'_'),'')]=Number(m[2]);
 for(const e of clean(flat).matchAll(/\benum\s+\w+\s*\{([^}]+)\}/g)){let value=-1;for(const raw of e[1].split(',')){const m=raw.trim().match(/^(\w+)\s*(?:=\s*(-?\d+))?$/);if(!m)continue;value=m[2]===undefined?value+1:Number(m[2]);enums[m[1].replace(new RegExp('^'+family+'_'),'')]=value;}}
 for(const group of Object.values(eaCatalog[family]))for(const s of group)for(const o of s.options??[]){enums[o.label]=o.value;enums['PERIOD_'+o.label]=o.value;}
 const value=s=>{s=s.trim().replace(/\([A-Za-z_]\w*\)/g,'').trim();if(s[0]==='"')return JSON.parse(s);if(s==='true'||s==='false')return s==='true';if(s in enums)return enums[s];if(/^[-+]?\d+(?:\.\d+)?$/.test(s))return Number(s);throw Error('UNKNOWN_LITERAL:'+s);};
 const native={};for(const m of source.matchAll(/^\s*input\s+(\w+)\s+(Inp\w+)\s*=\s*([^;]+);/gm)){try{native[m[2]]={type:m[1],value:value(m[3])};}catch{/* Private platform defaults not in the exposed contract remain unresolvable. */}}
 const reset=readFileSync(join(base,'universal/generated',family+'_settings.mqh'),'utf8');
 for(const m of reset.matchAll(new RegExp('if\\(live\\)live_'+family+'_(Inp\\w+)=([^;]+);','g'))){if(native[m[1]])continue;try{const spec=eaCatalog[family].inputs.find(s=>s.key===m[1]);const decl=flat.match(new RegExp('\\b(\\w+)\\s+'+family+'_'+m[1]+'\\b'));native[m[1]]={type:spec?.type??decl?.[1]??'int',value:value(m[2].replaceAll('live_'+family+'_',''))};}catch{/* Unknown private literals cannot validate a profile. */}}
 const direct={};for(const m of source.matchAll(/\b(g_\w+)\s*=\s*(?:\w+\(\s*)?(Inp\w+)\s*[);]/g))direct[m[1]]=m[2];
 Object.assign(direct,{g_rtFilterAtr:'InpUseAtrRangeFilter',g_rtFilterVol:'InpUseVolumeFilter',g_rtFilterDay:'InpUseDayFilter',g_rtSignalTf:'InpSignalTimeframe',g_rtDelayMin:'InpBreakoutDelayMinutes',g_rtPipSlPips:'InpPipSlPips',g_rtSlDistancePct:'InpSlDistancePct',g_rtVolumeMultiplier:'InpVolumeMultiplier',g_rtExitAtrMultiplier:'InpExitAtrMultiplier',g_btSpreadPts:'InpBacktestSpreadPts',g_btSlippagePts:'InpBacktestSlippagePts',g_btCommissionPerLot:'InpBacktestCommissionPerLot',g_orbRfEnabled:'InpOrbRfFilterDefault'});
 Object.assign(direct,{g_rtHalfBeLeg:'InpHalfBeMode',g_rtExitTrailStartLeg:'InpExitTrailStartLeg',g_rtTargetLeg:'InpTargetTpLeg',g_rtNasConfirmation:'InpNasConfirmationDefault',g_rtNasStateGate:'InpNasStateGateDefault',g_rtNasVolumeFilter:'InpNasUseVolumeFilter',g_rtNasVolumeMultiplier:'InpNasVolumeMultiplier',g_rtNasFlowVolumeFilter:'InpNasFlowUseVolumeFilter',g_rtNasFlowVolumeMultiplier:'InpNasFlowVolumeMultiplier',g_rtNasActiveSignalLookbackMinutes:'InpNasActiveSignalLookbackMinutes',g_rtNasExitOnOppositeSignal:'InpNasExitOnOppositeSignalDefault',g_rtNasAdditionalExit:'InpNasAdditionalExitDefault',g_rtNasOppositeExitWaitMinutes:'InpNasOppositeExitWait',g_rtNasSensitivity:'InpNasSensitivity'});
 const contract=family==='sol'?section(source,'LiqLibraryInputContract'):section(readFileSync(join(base,dirs[family],'OrbStrategyUserContract.mqh'),'utf8'),'OrbCustomInputSignature');
 const profiles=[],profileErrors=[],profileInputs={};
 // Hash equality, not a plausible-looking default, is required for saved hidden inputs.
 for(const boolMode of ['words','numbers'])for(const doubleMode of ['plain','integerDecimal',...Array.from({length:16},(_,i)=>'fixed'+(i+1))]){
  try{let text=family==='sol'?'V1':'';
   for(const line of contract.split(/\r?\n/)){const m=line.match(/(?:value|s)\+="(?:\|)?(Inp\w+)[:=]/);if(!m)continue;const p=native[m[1]];if(!p)throw Error('UNKNOWN_INPUT:'+m[1]);let v=p.value;
    if(typeof v==='boolean')v=boolMode==='words'?String(v):v?'1':'0';
    else if(p.type==='double')v=line.includes('DoubleToString')?v.toFixed(16):doubleMode.startsWith('fixed')?v.toFixed(Number(doubleMode.slice(5))):doubleMode==='integerDecimal'&&Number.isInteger(v)?v+'.0':String(v);
    else v=String(v);text+=family==='sol'?'|'+m[1]+'='+v:m[1]+':'+v.length+':'+v+';';
   }const hash=sha(text);profiles.push(hash);profileInputs[hash]=Object.fromEntries(Object.entries(native).map(([k,v])=>[k,v.value]));
  }catch(e){profileErrors.push(e.message);}
 }
 return {source,value,enums,direct,profiles,profileErrors,profileInputs};
}
const contexts=Object.fromEntries(Object.keys(dirs).map(f=>[f,context(f)]));
// A stored SHA cannot reveal its settings. Recover only hash-matching, versioned sources.
const solPath='IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5';
const commits=execFileSync('git',['log','-30','--format=%H','--',solPath],{cwd:root,encoding:'utf8'}).trim().split('\n').filter(Boolean);
for(const commit of commits){try{const archived=context('sol',execFileSync('git',['show',commit+':'+solPath],{cwd:root,encoding:'utf8',maxBuffer:4*1024*1024}));for(const hash of archived.profiles)if(!contexts.sol.profiles.includes(hash)){contexts.sol.profiles.push(hash);contexts.sol.profileInputs[hash]=archived.profileInputs[hash];}}catch{/* Old versions without the saved-contract function are not candidates. */}}
function set(c,key,value){if(Object.hasOwn(c.inputs,key)){const spec=eaCatalog[c.family].inputs.find(s=>s.key===key);c.inputs[key]=spec.type==='bool'?!!value:spec.type==='string'?String(value):Number(value);}}
function clock(n){return String(Math.floor(n/60)).padStart(2,'0')+':'+String(n%60).padStart(2,'0');}
function matrix(c,text){const v=text.slice(6).split(',').map(Number);if(![8,9,11,12].includes(v.length)||v.some(n=>!Number.isInteger(n)))throw Error('INVALID_TIME_MATRIX');c.runtime.timeMatrixEnabled=!!v[0];c.dayHourMasks=v.slice(1,8);set(c,'InpTimeMatrixEnabled',!!v[0]);set(c,'InpEntryDirection',v[8]??0);set(c,'InpDailyMaxLosses',v[9]??0);set(c,'InpDailyTargetWins',v[10]??0);set(c,'InpDailyStart',clock(v[11]??0));}
function effective(c,native){const {direct}=contexts[c.family];for(const [key,v] of Object.entries(native)){if(direct[key])set(c,direct[key],v);}
 const r=c.runtime;
 const map={inversion:'g_rtInvertMode',nasStateVolume:'g_rtNasVolumeFilter',nasFlowVolume:'g_rtNasFlowVolumeFilter',nasStateMultiplier:'g_rtNasVolumeMultiplier',nasFlowMultiplier:'g_rtNasFlowVolumeMultiplier',nasSensitivity:'g_rtNasSensitivity',nasWaitMinutes:'g_rtNasOppositeExitWaitMinutes',nasAgeMinutes:'g_rtNasActiveSignalLookbackMinutes'};
 for(const [k,n] of Object.entries(map))if(n in native)r[k]=native[n];
 if('g_rtNasConfirmation' in native)r.nasGate=native.g_rtNasStateGate?2:native.g_rtNasConfirmation?1:0;
 if('g_rtNasAdditionalExit' in native)r.nasExit=native.g_rtNasAdditionalExit?2:native.g_rtNasExitOnOppositeSignal?1:0;
 if('g_rtUseDelay' in native)set(c,'InpBreakoutDelayMinutes',native.g_rtUseDelay?native.g_rtDelayMin:0);
 if('g_rtNasOppositeExitWaitMinutes' in native)set(c,'InpNasOppositeExitWait',clock(native.g_rtNasOppositeExitWaitMinutes));
 for(const [k,n] of [['InpEntryWindowStartGmt','g_rtEntryWindowStartMin'],['InpEntryWindowEndGmt','g_rtEntryWindowEndMin']])if(n in native)set(c,k,clock(native[n]));
}
function preset(c,p){const contract=readFileSync(join(base,dirs[c.family],'OrbStrategyUserContract.mqh'),'utf8');const native={};
 for(const m of section(contract,'OrbCustomCapturePreset').matchAll(/p\.(\w+)\s*=\s*(g_\w+(?:\[\d+\])?)\s*;/g))if(m[1] in p)native[m[2]]=p[m[1]];
 effective(c,native);
 const regimes=['TrendLowVol','TrendHighVol','RangeLowVol','RangeHighVol','TransitionPending','TransitionFresh'];
 regimes.forEach((k,i)=>{if('regime'+i in p)set(c,'InpRegime'+k+'Allowed',p['regime'+i]);});
 for(let i=1;i<=12;i++)if('rf'+String(i).padStart(2,'0') in p)set(c,'InpOrbRf'+String(i).padStart(2,'0')+'Blocked',p['rf'+String(i).padStart(2,'0')]);
}
function target(c,leg,custom){const e=contexts[c.family].enums,inp=c.inputs;
 if(leg===1000)return Number(custom);
 if(leg>=e.ORB_TARGET_R005&&leg<=e.ORB_TARGET_R045)return .05*(leg-e.ORB_TARGET_R005+1);
 if(leg>=e.ORB_TARGET_R055&&leg<=e.ORB_TARGET_R070)return .55+.05*(leg-e.ORB_TARGET_R055);
 if(leg>=e.ORB_TARGET_R080&&leg<=e.ORB_TARGET_R095)return .8+.05*(leg-e.ORB_TARGET_R080);
 const keys={1:'InpTp1R',2:'InpTp2R',3:'InpTp3R',4:'InpTp4R',5:'InpTp5R',6:'InpTp6R',[e.ORB_TARGET_R075]:'InpTp075R',[e.ORB_TARGET_R350]:'InpTp35R',[e.ORB_TARGET_R400]:'InpTp40R',[e.ORB_TARGET_R450]:'InpTp45R'};
 return Number(inp[keys[leg]??'InpTp50R']);
}
function builder(text){const v=text.split('~');if(!['LAB2','LAB3','LAB4','LAB5'].includes(v[0]))throw Error('UNKNOWN_ENGINE_VERSION');
 const rules=s=>s?s.split(';').map(row=>{const n=row.split(',').map(Number);if(n.length!==8)throw Error('INVALID_RULE');return {feature:n[0],comparator:n[1],threshold:n[2],gate:n[3],negate:!!n[4],period:n[5],rhsFeature:n[6],rhsPeriod:n[7]};}):[];
 const p=v[7]?.split(',').map(Number)??[0,14,1,1,0,0,0];
 return {edge:!!Number(v[2]),buy:rules(v[3]),sell:rules(v[4]),exitBuy:rules(v[5]),exitSell:rules(v[6]),exitsEnabled:v[0]==='LAB5'?!!Number(v[9]):true,policy:!!p[0],atrPeriod:p[1],slAtr:p[2],tpAtr:p[3],cooldown:p[4],maxBars:p[5],maxMinutes:p[6]};
}
function parseOrb(family,text){const v=text.trimEnd().split(/\r?\n/),contract=readFileSync(join(base,dirs[family],'OrbStrategyUserContract.mqh'),'utf8');
 if(sha(v.slice(0,-1).join('\n')+'\n')!==v.at(-1)&&sha(v.slice(0,-1).join('\n'))!==v.at(-1))throw Error('CHECKSUM_MISMATCH');
 const c=defaultConfiguration(family),p={};
 for(const m of section(contract,'OrbCustomPresetRead').matchAll(/p\.(\w+)\s*=\s*(?:\((\w+)\))?([nv])\[(?:start\+)?(\d+)\]/g))p[m[1]]=m[3]==='v'?v[6+Number(m[4])]:m[2]==='bool'?!!Number(v[6+Number(m[4])]):Number(v[6+Number(m[4])]);
 c.name=p.name;preset(c,p);
 const count=Number(contract.match(/ORB_CUSTOM_RUNTIME_TOKENS (\d+)/)[1]),start=64,native={};
 for(const m of section(contract,'OrbCustomRuntimeRead').matchAll(/(g_\w+)\s*=\s*\((\w+)\)n\[(\d+)\]/g)){const raw=v[start+Number(m[3])];if(raw===undefined||!Number.isFinite(Number(raw)))throw Error('INVALID_RUNTIME');native[m[1]]=m[2]==='bool'?!!Number(raw):Number(raw);}
 effective(c,native);c.runtime.targetR=target(c,native.g_rtTargetLeg,v[start+count]);
 c.runtime.independent=false;c.runtime.maxOpen=family==='orb'?10:1;c.runtime.reverseExit=family!=='orb';
 const meta=v[5].split('|');for(const s of meta.slice(1)){
  const [key,raw]=s.split('='),n=raw?.split(',').map(Number);
  switch(key){
   case 'MAENTRY1':c.runtime.independent=!!n[0];c.runtime.maxOpen=n[1];c.runtime.reverseExit=!c.runtime.independent;break;
   case 'MAEXIT2':c.runtime.reverseExit=!!n[0];c.runtime.reverseWaitMinutes=n[1];break;
   case 'MAOF1':['Mode','Lookback','Bins','ValueArea','MinActivity','MinDelta'].forEach((k,i)=>set(c,'InpOrderFlow'+k,n[i]));break;
   case 'TCAL1':matrix(c,s);break;
   case 'MAADV1':if(n[0])c.runtime.inversion=true;break;
   case 'MAADVCOST1':case 'GAP1':c.runtime.inverseMaxCostPct=n[0];break;
   case 'TZ':set(c,'InpBrokerGmtOffsetHours',n[0]);break;
   case 'CLK1':set(c,'InpBrokerTimezone',n[0]);set(c,'InpBrokerClockSeason',n[1]);set(c,'InpExchangeClockSeason',n[2]);set(c,'InpSessionProfile',n[3]);break;
   case 'POS1':Object.assign(c.runtime,{independent:!!n[0],nextDayExit:!!n[1],reverseExit:!!n[2],maxOpen:n[3],reverseWaitMinutes:n[4]});break;
   case 'LABENGINE1':c.builder=builder(raw);if(['LAB4','LAB5'].includes(raw.slice(0,4))){const pip=raw.split('~')[8].split(',').map(Number);
    // Native policy forces pip mode, but replaces its distance only for an explicit engine override.
    if(c.builder.policy)set(c,'InpPipSlModeDefault',true);
    if(c.builder.policy&&pip[0])set(c,'InpPipSlPips',pip[1]);}break;
   default:throw Error('UNKNOWN_METADATA:'+key);
  }
 }
 const verified=contexts[family].profiles.includes(meta[0]);
 return {name:p.name,symbol:v[3],nativeId:p.id,config:c,verified,note:verified?'Native runtime and base-input signature verified.':'Saved base-input hash has no matching source profile. Full native snapshot retained; no silent default substitution.',snapshot:{lines:v,chartTimeframe:Number(v[4]),inputSignature:meta[0]}};
}
function solConfig(name,v){const c=defaultConfiguration('sol');c.name=name;
 c.runtime.reverseExit=!!c.inputs.InpCloseOnReverse;c.runtime.maxOpen=1;
 const capture=section(contexts.sol.source,'LiqLibraryCapture');
 for(const m of capture.matchAll(/v\[(\d+)\]\s*=\s*\(double\)(g_\w+)/g))if(contexts.sol.direct[m[2]])set(c,contexts.sol.direct[m[2]],v[Number(m[1])]);
 const regimes=['TrendLowVol','TrendHighVol','RangeLowVol','RangeHighVol','TransitionPending','TransitionFresh'];regimes.forEach((k,i)=>set(c,'InpMacroRegime'+k+'Allowed',v[23+i]));
 for(let i=1;i<=12;i++)set(c,'InpSolRegimeRf'+String(i).padStart(2,'0')+'Blocked',v[28+i]);
 c.runtime.inversion=!!v[16];c.runtime.inverseMaxCostPct=v[41]??100;c.runtime.targetR=v[3]>=101&&v[3]<=200?(v[3]-100)*.05:.5*(v[3]+1);
 return c;
}
function parseSol(text){const end=text.lastIndexOf('\nSHA256='),payload=text.slice(0,end);if(end<0||sha(payload)!==text.slice(end+8).trim())throw Error('CHECKSUM_MISMATCH');const lines=payload.split('\n');if(lines[1]!=='LiqNarrativeSol_Advanced')return null;
 const count=Number(lines[5]),v=lines.slice(6,6+count).map(Number);if(![41,42].includes(count)||v.some(n=>!Number.isFinite(n)))throw Error('INVALID_SOL_VALUES');
 const baseProfile=contexts.sol.profileInputs[lines[4]];
 const c=solConfig(lines[3],v);if(baseProfile){for(const [key,value] of Object.entries(baseProfile))set(c,key,value);const captured=solConfig(lines[3],v);for(const m of section(contexts.sol.source,'LiqLibraryCapture').matchAll(/v\[(\d+)\]\s*=\s*\(double\)(g_\w+)/g)){const key=contexts.sol.direct[m[2]];if(key&&Object.hasOwn(c.inputs,key))c.inputs[key]=captured.inputs[key];}const regimes=Object.keys(captured.inputs).filter(k=>/^InpMacroRegime|^InpSolRegime/.test(k));for(const key of regimes)c.inputs[key]=captured.inputs[key];}
 const tail=lines.slice(6+count);
 for(const s of tail){if(s.startsWith('LN_NAS_V1|')){const n=s.split('|').slice(1).map(Number);Object.assign(c.runtime,{nasGate:n[0],nasExit:n[1],nasStateVolume:!!n[2],nasFlowVolume:!!n[3],independent:!!n[4],reverseExit:!!n[5],nasStateMultiplier:n[6],nasFlowMultiplier:n[7],nasSensitivity:n[8],nasWaitMinutes:n[9],nasAgeMinutes:n[10],maxOpen:Math.max(1,n[11]),reverseWaitMinutes:n[12]});}else if(s.startsWith('TCAL1='))matrix(c,s);else if(Number.isFinite(Number(s)))c.runtime.targetR=Number(s);else throw Error('UNKNOWN_SOL_METADATA');}
 const verified=contexts.sol.profiles.includes(lines[4]);return {name:lines[3],symbol:lines[2],nativeId:sha(lines[2]+'|'+lines[3]),config:c,verified,note:verified?'Native runtime and base-input signature verified.':'Saved base-input hash has no matching source profile. Full native snapshot retained; no silent default substitution.',snapshot:{lines}};
}
const records=[],failures=[];
function add(family,origin,raw,parsed){if(!parsed)return;const test=universalConfigurationSchema.safeParse(parsed.config),ready=parsed.verified&&test.success;
 records.push({id:family+'_'+sha(parsed.nativeId).slice(0,28),family,name:parsed.name,symbol:parsed.symbol,source_hash:sha(raw),configuration:ready?test.data:null,native_snapshot:{origin,...parsed.snapshot,proposedConfiguration:parsed.config},import_note:!test.success?'Unsupported native setting: '+test.error.issues.map(i=>i.message).join('; ').slice(0,400):parsed.note,active:true});
}
for(const [family,folder] of Object.entries({orb:'OrbStrategyUserLibrary',macross:'MaCrossOrbStrategyLibrary',entrylab:'EntryEngineLabStrategyLibrary'})){
 const path=join(common,folder);if(!existsSync(path))continue;for(const file of readdirSync(path).filter(f=>f.endsWith('.preset'))){const raw=readFileSync(join(path,file),'utf8');try{add(family,folder+'/'+file,raw,parseOrb(family,raw));}catch(e){failures.push({family,file,error:e.message});}}
}
function walk(folder){if(!existsSync(folder))return [];return readdirSync(folder,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(join(folder,e.name)):e.name.endsWith('.lns')?[join(folder,e.name)]:[]);}
for(const path of walk(join(common,'LiqStrategies'))){const raw=readFileSync(path,'utf8').replaceAll('\r\n','\n');try{add('sol',relative(common,path),raw,parseSol(raw));}catch(e){failures.push({family:'sol',file:relative(common,path),error:e.message});}}
// Built-in records are a literal projection of the canonical preset tables.
const src=readFileSync(join(base,'orb/OrbStrategyPresetLibrary.mqh'),'utf8'),ctx=contexts.orb;
function assignments(body,p){for(const m of clean(body).matchAll(/p\.(\w+)\s*=\s*([^;]+);/g)){if(m[1].startsWith('metric'))continue;p[m[1]]=ctx.value(m[2]);}}
const defaults={};assignments(section(src,'OrbPresetDefaults'),defaults);
for(const m of src.matchAll(/case \d+:([\s\S]*?)break;/g)){const p={...defaults},identity=m[1].match(/OrbPresetIdentity\(p,([\s\S]*?)\);/);if(!identity)continue;
 const args=identity[1].match(/"(?:\\.|[^"\\])*"|[^,]+/g).map(s=>ctx.value(s));['id','name','searchTerms','sourceImage','family','signalTf','targetLeg','entryMode','pipSlPips'].forEach((k,i)=>p[k]=args[i]);assignments(m[1],p);
 if(m[1].includes('OrbPresetRfOnly03(p)'))for(let i=1;i<=12;i++)p['rf'+String(i).padStart(2,'0')]=i===3;
 const vol=m[1].match(/OrbPresetLegacyNasVolume\(p,([^,]+),([^\)]+)\)/);if(vol){p.nasStateVolumeFilter=p.nasFlowVolumeFilter=ctx.value(vol[1]);p.nasStateVolumeMultiplier=p.nasFlowVolumeMultiplier=ctx.value(vol[2]);}
 const c=defaultConfiguration('orb');c.name=p.name;preset(c,p);c.runtime.targetR=target(c,p.targetLeg);const symbol={1:'JP225m',2:'USDJPYm',3:'USTECm'}[p.family]??'ANY';add('orb','builtin:'+p.id,JSON.stringify(p),{name:p.name,symbol,nativeId:p.id,config:c,verified:true,note:'Canonical built-in preset. Account risk defaults belong to the receiving user.',snapshot:{preset:p}});
}
const images=readFileSync(join(base,'SolAdvanced/LiqImagePresets.mqh'),'utf8');for(const m of images.matchAll(/\{"([^"]+)","LiqNarrativeSol_Advanced","([^"]+)",([^}]+)\}/g)){
 const n=m[3].split(',').map(Number),v=Array(42).fill(0);[v[0],v[1],v[3],v[15],v[16],v[20],v[21]]=n.slice(0,7);v[2]=5;v[7]=v[13]=v[19]=1;v[17]=100;v[18]=10;v[22]=n[7]??0;for(let i=23;i<41;i++)v[i]=1;for(let i=0;i<6;i++)if((n[8]??0)&(1<<i))v[23+i]=0;for(let i=0;i<12;i++)if((n[9]??0)&(1<<i))v[29+i]=0;v[41]=100;
 add('sol','image:'+m[1],m[0],{name:m[1],symbol:m[2],nativeId:'image_'+m[1],config:solConfig(m[1],v),verified:true,note:'Canonical screenshot-derived preset; hidden inputs use current canonical defaults. Not a claim of historical performance.',snapshot:{values:v}});
}
const outputAt=process.argv.indexOf('--output');
const output=outputAt<0?join(root,'reports/admin_catalog'):resolve(root,process.argv[outputAt+1]);
mkdirSync(output,{recursive:true});writeFileSync(join(output,'catalog.private.json'),JSON.stringify(records,null,2));
const report={counts:Object.fromEntries(Object.keys(dirs).map(f=>[f,{total:records.filter(r=>r.family===f).length,ready:records.filter(r=>r.family===f&&r.configuration).length}])),failures,baseSignatureCandidates:Object.fromEntries(Object.keys(dirs).map(f=>[f,contexts[f].profiles])),profileErrors:Object.fromEntries(Object.keys(dirs).map(f=>[f,contexts[f].profileErrors]))};
writeFileSync(join(output,'import-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({counts:report.counts,failures,unresolved:records.filter(r=>!r.configuration).map(r=>({name:r.name,note:r.import_note}))},null,2));
// Research workers need the original base inputs, not the runtime-overlaid web config.
writeFileSync(join(output,'audit-input-profiles.private.json'),JSON.stringify(Object.fromEntries(Object.entries(contexts).map(([family,c])=>[family,c.profileInputs])),null,2));
