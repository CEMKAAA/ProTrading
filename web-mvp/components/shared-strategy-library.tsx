"use client";
import {useEffect,useRef,useState} from 'react';
import {ArrowUpRight,Library,RefreshCw,Search} from 'lucide-react';
import { CONTROL_API,CONTROL_CREDENTIALS,CONTROL_TIMEOUT_MS} from '@/lib/control-endpoint';
import {universalConfigurationSchema,type Family,type UniversalConfiguration} from '@/lib/universal-contract';
import type {SharedLoad,SharedStrategy} from '@/lib/strategy-access';
import {campaignWindows,cycleCampaignSort,rankCampaignStrategies,type CampaignSort} from '@/lib/strategy-campaign';
import StrategyCampaignStats from './strategy-campaign-stats';
import {UiText,useLanguage} from './language-provider';

const families:Record<Family,string>={orb:'ORB',macross:'MA Crossover',sol:'Sol Advanced',entrylab:'Entry Lab'};
const sortOptions:{key:CampaignSort['key'];label:string}[]=[{key:'winRate',label:'Win rate'},{key:'total',label:'Trade count'},{key:'wins',label:'Wins'},{key:'losses',label:'Losses'},{key:'netR',label:'Net R'},{key:'minCumR',label:'MC (MinCum R)'}];
export default function SharedStrategyLibrary({credential,onLoad}:{credential:string;onLoad:(c:UniversalConfiguration,symbol:string)=>void}){
 const {t}=useLanguage();
 const [record,setRecord]=useState<{owner:string;items:SharedStrategy[]}>({owner:'',items:[]});
 const [family,setFamily]=useState<Family>('orb'),[query,setQuery]=useState(''),[error,setError]=useState(''),[loading,setLoading]=useState(true),[pending,setPending]=useState(''),[refresh,setRefresh]=useState(0);
 const [weeks,setWeeks]=useState(260);
 const [sorts,setSorts]=useState<CampaignSort[]>([{key:'winRate',direction:'desc'},{key:'total',direction:'desc'}]);
 const owner=useRef(credential);owner.current=credential;
 useEffect(()=>{
  const abort=new AbortController();setRecord({owner:'',items:[]});setError('');setLoading(true);
  let active=false;
  async function poll(){if(active||!credential)return;active=true;
   try{const response=await fetch(CONTROL_API+'/v1/library/strategies',{headers:{Authorization:'Bearer '+credential},credentials:CONTROL_CREDENTIALS,cache:'no-store',redirect:'error',signal:abort.signal});
    const data=await response.json() as {items:SharedStrategy[];error?:string};if(!response.ok)throw new Error(data.error??'REQUEST_FAILED');
    if(!abort.signal.aborted){setRecord({owner:credential,items:data.items});setError('');}
   }catch(e){if(!abort.signal.aborted){setRecord({owner:credential,items:[]});setError(e instanceof Error?e.message:'REQUEST_FAILED');}}
   finally{active=false;if(!abort.signal.aborted)setLoading(false);}
  }
  void poll();const interval=setInterval(()=>void poll(),10000);return()=>{abort.abort();clearInterval(interval);};
 },[credential,refresh]);
 async function load(item:SharedStrategy){if(pending)return;const token=credential;setPending(item.id);setError('');
  try{const response=await fetch(CONTROL_API+'/v1/library/load',{method:'POST',credentials:CONTROL_CREDENTIALS,cache:'no-store',redirect:'error',signal:AbortSignal.timeout(CONTROL_TIMEOUT_MS),headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({strategyId:item.id})});
   const data=await response.json() as SharedLoad&{error?:string};if(!response.ok)throw new Error(data.error??'REQUEST_FAILED');
   const result=data as SharedLoad;const configuration=universalConfigurationSchema.parse(result.configuration);
   if(owner.current===token)onLoad(configuration,result.symbol);
  }catch(e){if(owner.current===token){setError(e instanceof Error?e.message:'REQUEST_FAILED');setRefresh(n=>n+1);}}
  finally{setPending('');}
 }
 const items=record.owner===credential?record.items:[];
 const visible=rankCampaignStrategies(items.filter(s=>s.family===family&&(s.name+' '+s.symbol).toLowerCase().includes(query.toLowerCase())),weeks,sorts);
 return <section className="shared-strategy-library"><div className="admin-access-heading"><div><h3><UiText>Assigned strategies</UiText></h3><p><UiText>Strategies your administrator has made available to your account. Loading updates your draft only.</UiText></p></div><button className="secondary-btn" disabled={loading||!!pending} onClick={()=>setRefresh(n=>n+1)}><RefreshCw size={16}/><UiText>Refresh</UiText></button></div>
  <nav className="admin-family-tabs" aria-label={t('Assigned EA families')}>{(Object.keys(families) as Family[]).map(f=><button key={f} aria-pressed={f===family} disabled={!!pending} onClick={()=>{setFamily(f);setQuery('');}}>{families[f]} <span>{items.filter(s=>s.family===f).length}</span></button>)}</nav>
  <label className="uc-library-search"><Search size={19}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={t('Search assigned strategies')} aria-label={t('Search assigned strategies')}/></label>
  <div className="campaign-selector"><strong><UiText>Verified MEGA campaign</UiText></strong><nav aria-label={t('Campaign audit window')}>{campaignWindows.map(w=><button type="button" key={w.weeks} aria-pressed={weeks===w.weeks} onClick={()=>setWeeks(w.weeks)}>{w.label}</button>)}</nav></div>
  <div className="campaign-sorting"><div className="uc-row"><strong><UiText>Sort this audit window</UiText></strong><button type="button" className="text-btn" disabled={!sorts.length} onClick={()=>setSorts([])}><UiText>Clear sorting</UiText></button></div>
   <div className="campaign-sort-controls">{sortOptions.map(option=>{const index=sorts.findIndex(s=>s.key===option.key),sort=sorts[index];return <button type="button" key={option.key} aria-pressed={!!sort} onClick={()=>setSorts(s=>cycleCampaignSort(s,option.key))}>
    {sort&&<span className="campaign-sort-priority">{index+1}</span>}<UiText>{option.label}</UiText><small><UiText>{sort?.direction==='desc'?'Highest first':sort?'Lowest first':'Not sorted'}</UiText></small>
   </button>;})}</div>
   <p className="campaign-explanation"><UiText>Combine rankings. Priority follows selection order; ties use the next ranking. Click to cycle highest, lowest, off. Missing results stay last.</UiText></p>
  </div>
  <p className="campaign-explanation"><UiText>Frozen historical results, not a live forecast. Select a window to compare the same recorded audit period.</UiText></p>
  <p className="campaign-explanation"><UiText>W: wins / L: losses / O: open trades. WR excludes open and flat trades.</UiText></p>
  {error&&<p role="alert" className="uc-error">{error}</p>}
  <div className="uc-library-grid" aria-busy={loading}>{visible.map(s=><article className="uc-library-card campaign-library-card" key={s.id}><span><Library size={21}/>{families[s.family]}</span><strong>{s.name}</strong><small>{s.symbol}</small><StrategyCampaignStats campaign={s.campaign} weeks={weeks}/><button type="button" className="secondary-btn campaign-load" disabled={!!pending} onClick={()=>void load(s)}><UiText>{pending===s.id?'Loading...':'Load draft'}</UiText><ArrowUpRight size={18}/></button></article>)}</div>
  {!loading&&!visible.length&&<p className="uc-empty"><UiText>{items.length?'No strategies match that search.':'No shared strategies have been granted to your account yet.'}</UiText></p>}
 </section>;
}
