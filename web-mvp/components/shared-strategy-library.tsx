"use client";
import {useEffect,useRef,useState} from 'react';
import {ArrowUpRight,Library,RefreshCw,Search} from 'lucide-react';
import { CONTROL_API,CONTROL_CREDENTIALS,CONTROL_TIMEOUT_MS} from '@/lib/control-endpoint';
import {universalConfigurationSchema,type Family,type UniversalConfiguration} from '@/lib/universal-contract';
import type {SharedLoad,SharedStrategy} from '@/lib/strategy-access';
import {UiText,useLanguage} from './language-provider';

const families:Record<Family,string>={orb:'ORB',macross:'MA Crossover',sol:'Sol Advanced',entrylab:'Entry Lab'};
export default function SharedStrategyLibrary({credential,onLoad}:{credential:string;onLoad:(c:UniversalConfiguration,symbol:string)=>void}){
 const {t}=useLanguage();
 const [record,setRecord]=useState<{owner:string;items:SharedStrategy[]}>({owner:'',items:[]});
 const [family,setFamily]=useState<Family>('orb'),[query,setQuery]=useState(''),[error,setError]=useState(''),[loading,setLoading]=useState(true),[pending,setPending]=useState(''),[refresh,setRefresh]=useState(0);
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
 const visible=items.filter(s=>s.family===family&&(s.name+' '+s.symbol).toLowerCase().includes(query.toLowerCase()));
 return <section className="shared-strategy-library"><div className="admin-access-heading"><div><h3><UiText>Assigned strategies</UiText></h3><p><UiText>Strategies your administrator has made available to your account. Loading updates your draft only.</UiText></p></div><button className="secondary-btn" disabled={loading||!!pending} onClick={()=>setRefresh(n=>n+1)}><RefreshCw size={16}/><UiText>Refresh</UiText></button></div>
  <nav className="admin-family-tabs" aria-label={t('Assigned EA families')}>{(Object.keys(families) as Family[]).map(f=><button key={f} aria-pressed={f===family} disabled={!!pending} onClick={()=>{setFamily(f);setQuery('');}}>{families[f]} <span>{items.filter(s=>s.family===f).length}</span></button>)}</nav>
  <label className="uc-library-search"><Search size={19}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={t('Search assigned strategies')} aria-label={t('Search assigned strategies')}/></label>
  {error&&<p role="alert" className="uc-error">{error}</p>}
  <div className="uc-library-grid" aria-busy={loading}>{visible.map(s=><button type="button" className="uc-library-card" disabled={!!pending} key={s.id} onClick={()=>void load(s)}><span><Library size={21}/>{families[s.family]}</span><strong>{s.name}</strong><small>{s.symbol} / <UiText>{pending===s.id?'Loading...':'Load draft'}</UiText><ArrowUpRight size={18}/></small></button>)}</div>
  {!loading&&!visible.length&&<p className="uc-empty"><UiText>{items.length?'No strategies match that search.':'No shared strategies have been granted to your account yet.'}</UiText></p>}
 </section>;
}
