"use client";
import {useEffect,useRef,useState} from 'react';
import {ShieldCheck,Search,Users,ArrowLeft,RefreshCw,LockKeyhole} from 'lucide-react';
import ConsoleWindow from './console-window';
import LeverSwitch from './lever-switch';
import {UiText,useLanguage} from './language-provider';
import { CONTROL_API,CONTROL_CREDENTIALS,CONTROL_TIMEOUT_MS} from '@/lib/control-endpoint';
import type {Family} from '@/lib/universal-contract';
import type {AdminUser,CatalogPage,CatalogStrategy} from '@/lib/strategy-access';

const families:Record<Family,string>={orb:'ORB',macross:'MA Crossover',sol:'Sol Advanced',entrylab:'Entry Lab'};
async function request<T>(path:string,token:string,body?:unknown,signal?:AbortSignal):Promise<T>{
 const response=await fetch(CONTROL_API+path,{method:body===undefined?'GET':'POST',credentials:CONTROL_CREDENTIALS,cache:'no-store',redirect:'error',
  headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:signal??AbortSignal.timeout(CONTROL_TIMEOUT_MS)});
 const data=await response.json() as T&{error?:string};if(!response.ok)throw new Error(data.error??'REQUEST_FAILED');return data;
}
export default function AdminStrategyAccess({credential}:{credential:string}){
 const {t}=useLanguage();
 const [authorized,setAuthorized]=useState(''),[open,setOpen]=useState(false),trigger=useRef<HTMLButtonElement|null>(null);
 const [users,setUsers]=useState<{items:AdminUser[];total:number;hasMore:boolean}>({items:[],total:0,hasMore:false});
 const [selected,setSelected]=useState<AdminUser|null>(null),[userQuery,setUserQuery]=useState(''),[userOffset,setUserOffset]=useState(0);
 const [family,setFamily]=useState<Family>('orb'),[query,setQuery]=useState(''),[offset,setOffset]=useState(0);
 const [catalog,setCatalog]=useState<CatalogPage>({items:[],total:0,counts:{},hasMore:false});
 const [loading,setLoading]=useState(false),[pending,setPending]=useState(''),[error,setError]=useState(''),[notice,setNotice]=useState(''),[refresh,setRefresh]=useState(0);
 const owner=useRef(credential);owner.current=credential;
 const target=useRef(selected?.id);target.current=selected?.id;
 useEffect(()=>{setAuthorized('');setOpen(false);setSelected(null);setCatalog({items:[],total:0,counts:{},hasMore:false});if(!credential)return;
  const abort=new AbortController();void request<{isAdmin:boolean}>('/v1/admin/status',credential,undefined,abort.signal)
   .then(r=>{if(!abort.signal.aborted&&r.isAdmin)setAuthorized(credential);}).catch(()=>{});return()=>abort.abort();},[credential]);
 useEffect(()=>{if(!open||authorized!==credential)return;
  const abort=new AbortController();setLoading(true);setError('');setNotice('');
  const timer=setTimeout(()=>{const path=selected?'/v1/admin/catalog':'/v1/admin/users';
   const body=selected?{userId:selected.id,family,query,offset}:{query:userQuery,offset:userOffset};
   void request<CatalogPage|typeof users>(path,credential,body,abort.signal).then(r=>{if(abort.signal.aborted)return;
    if(selected)setCatalog(r as CatalogPage);else setUsers(r as typeof users);}).catch(e=>{if(!abort.signal.aborted)setError(e.message);})
    .finally(()=>{if(!abort.signal.aborted)setLoading(false);});},180);
  return()=>{clearTimeout(timer);abort.abort();};
 },[open,authorized,credential,selected,family,query,offset,userQuery,userOffset,refresh]);
 async function toggle(strategy:CatalogStrategy,enabled:boolean){
  if(!selected||pending||loading||!strategy.ready)return;
  const token=credential,userId=selected.id;setPending(strategy.id);setError('');setNotice('');
  try{const result=await request<{enabled:boolean;revision:number}>('/v1/admin/grant',token,{userId,strategyId:strategy.id,enabled,revision:strategy.revision});
   if(owner.current!==token||target.current!==userId)return;
   setCatalog(c=>({...c,items:c.items.map(s=>s.id===strategy.id?{...s,...result}:s)}));setNotice(t('Access saved.'));
  }catch(e){if(owner.current===token&&target.current===userId){setError(e instanceof Error?e.message:'REQUEST_FAILED');if(e instanceof Error&&e.message==='GRANT_CONFLICT')setRefresh(r=>r+1);}}
  finally{setPending('');}
 }
 if(!credential||authorized!==credential)return null;
 return <><button ref={trigger} className="admin-launch" onClick={()=>setOpen(true)}><ShieldCheck size={19}/><UiText>Admin panel</UiText></button>
  <ConsoleWindow open={open} onOpenChange={setOpen} returnFocus={trigger} title="Strategy access control" description="Select a user, then enable the strategies they can see and load. All access starts disabled." tone="gold"
   footer={<><span className="console-draft"><LockKeyhole size={16}/><UiText>Server-enforced / default denied</UiText></span><button className="secondary-btn" disabled={!!pending} onClick={()=>setOpen(false)}><UiText>Keep & close</UiText></button></>}>
   <div className="admin-access">
    <div className="admin-access-heading"><div><span className="mono"><UiText>{selected?'STEP 2 / STRATEGIES':'STEP 1 / USER'}</UiText></span><h3>{selected?.email??t('Choose a user')}</h3>
     <p>{selected?<><UiText>{selected.displayName}</UiText> / <UiText>{selected.accessMode}</UiText></>:<UiText>No shared strategy is visible until you grant it.</UiText>}</p></div>
     <div className="admin-actions">{selected&&<button className="secondary-btn" disabled={!!pending} onClick={()=>{setSelected(null);setOffset(0);setQuery('');}}><ArrowLeft size={16}/><UiText>Users</UiText></button>}
      <button className="secondary-btn" disabled={loading||!!pending} onClick={()=>setRefresh(r=>r+1)} aria-label={t('Refresh')}><RefreshCw size={16}/><UiText>Refresh</UiText></button></div></div>
    {selected?<>
     <nav className="admin-family-tabs" aria-label={t('EA families')}>{(Object.keys(families) as Family[]).map(f=><button key={f} disabled={!!pending} aria-pressed={f===family} onClick={()=>{setFamily(f);setOffset(0);setQuery('');}}>{families[f]} <span>{catalog.counts[f]??0}</span></button>)}</nav>
     <label className="admin-search"><Search size={18}/><span className="sr-only"><UiText>Search strategies</UiText></span><input value={query} disabled={!!pending} placeholder={t('Search strategies')} onChange={e=>{setQuery(e.target.value);setOffset(0);}}/></label>
     <div className="admin-strategy-list" aria-busy={loading}>{loading?<div className="admin-loading"><UiText>Loading access rules...</UiText></div>:catalog.items.map(s=><div className="admin-strategy-row" key={s.id}>
      <div><strong title={s.importNote}>{s.name}</strong><small>{s.symbol} / {families[s.family]} / {s.id.slice(-6)}</small>{!s.ready&&<span className="admin-import-note" title={s.importNote}><UiText>Source verification required</UiText></span>}</div>
      <div className="admin-row-switch"><fieldset disabled={!!pending||!s.ready}><LeverSwitch compact label={t('Access')} accessibleLabel={`${s.name}: ${t('Access')}`} checked={s.enabled} onChange={value=>void toggle(s,value)}/></fieldset>{pending===s.id&&<small role="status"><UiText>Saving...</UiText></small>}</div>
     </div>)}{!loading&&!catalog.items.length&&<p className="uc-empty"><UiText>No strategies match that search.</UiText></p>}</div>
     <div className="admin-pagination"><button className="secondary-btn" disabled={offset===0||loading||!!pending} onClick={()=>setOffset(n=>Math.max(0,n-50))}><UiText>Previous</UiText></button><span>{offset+1}-{Math.min(offset+50,catalog.total)} / {catalog.total}</span><button className="secondary-btn" disabled={!catalog.hasMore||loading||!!pending} onClick={()=>setOffset(n=>n+50)}><UiText>Next</UiText></button></div>
    </>:<>
     <label className="admin-search"><Search size={18}/><span className="sr-only"><UiText>Search users by email</UiText></span><input value={userQuery} placeholder={t('Search users by email')} onChange={e=>{setUserQuery(e.target.value);setUserOffset(0);}}/></label>
     <div className="admin-user-list" aria-busy={loading}>{loading?<div className="admin-loading"><UiText>Loading users...</UiText></div>:users.items.map(u=><button className="admin-user-row" key={u.id} onClick={()=>{setSelected(u);setOffset(0);setQuery('');}}><Users size={21}/><div><strong>{u.email}</strong><small>{u.displayName||t('New account')}</small></div><span>{u.confirmed?t(u.accessMode):t('Email not confirmed')} / {u.grantedCount} <UiText>granted</UiText></span></button>)}{!loading&&!users.items.length&&<p className="uc-empty"><UiText>No users found.</UiText></p>}</div>
     <div className="admin-pagination"><button className="secondary-btn" disabled={userOffset===0||loading} onClick={()=>setUserOffset(n=>Math.max(0,n-50))}><UiText>Previous</UiText></button><span>{users.total} <UiText>Users</UiText></span><button className="secondary-btn" disabled={!users.hasMore||loading} onClick={()=>setUserOffset(n=>n+50)}><UiText>Next</UiText></button></div>
    </>}
    {error&&<p role="alert" className="uc-error">{error==='GRANT_CONFLICT'?t('Another administrator changed this rule. The list has been refreshed.'):error}</p>}
    {notice&&<p role="status" className="admin-notice">{notice}</p>}
    <p className="admin-disclaimer"><UiText>Grants control the shared library. They do not enable live trading, alter open positions, or erase settings a user has already received.</UiText></p>
   </div>
  </ConsoleWindow>
 </>;
}
