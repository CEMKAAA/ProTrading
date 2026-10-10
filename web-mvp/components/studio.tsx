"use client";
import { UiText, useLanguage, LanguageSelect } from './language-provider';
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { GitBranch, Library, ShieldCheck, Terminal, LockKeyhole } from "lucide-react";
import { Dialog,DialogContent,DialogTitle,DialogDescription,DialogHeader } from "@/components/ui/dialog";
import { Toaster } from "@/components/ui/sonner";
import { Brand } from "./launch-page";
import StrategyDemo from "./strategy-demo";
import ConnectionPanel from "./connection-panel";
import UniversalDashboard from "./universal-dashboard";
import StudioMarketOrbit from "./studio-market-orbit";
import { CLOUD_SESSION,CONTROL_API,CONTROL_CREDENTIALS,CONTROL_TIMEOUT_MS,storedSession,storeSession } from '@/lib/control-endpoint';
import { restoreStudioSession } from '@/lib/studio-session';
import { authReturn } from '@/lib/auth-return';
import AdminStrategyAccess from './admin-strategy-access';
export default function Studio() {
 const {t}=useLanguage();
 const [connect,setConnect]=useState(false), [credential,setCredential]=useState("");
 const [restoring,setRestoring]=useState(true);
 const credentialRevision=useRef(0);
 const updateCredential=useCallback((value:string)=>{credentialRevision.current++;storeSession(value);setCredential(value);},[]);
 const [confirmation,setConfirmation]=useState<'confirmed'|'failed'|null>(null);
 useEffect(()=>{
  const status=authReturn(window.location.hash);
  if(status){
   window.history.replaceState(null,'',window.location.pathname+window.location.search);
   setConfirmation(status);
  }
  let alive=true;
  const revision=credentialRevision.current;
  const saved=storedSession();
  void restoreStudioSession({cloud:CLOUD_SESSION,saved,
   probe:()=>fetch(CONTROL_API+'/v1/auth/session',{credentials:CONTROL_CREDENTIALS,cache:'no-store',signal:AbortSignal.timeout(CONTROL_TIMEOUT_MS)}),
   isCurrent:()=>alive&&credentialRevision.current===revision,accept:updateCredential
  }).catch(()=>{}).finally(()=>{if(alive)setRestoring(false);});
  return()=>{alive=false;};
 },[updateCredential]);
 return <div className="studio-page">
  <header className="studio-nav"><Brand/><div className="studio-breadcrumb"><span><UiText>{"Personal workspace"}</UiText></span><span><UiText>{"/"}</UiText></span><strong><UiText>{"Strategy studio"}</UiText></strong></div><div className="studio-nav-right"><LanguageSelect/><span className="demo-tag"><UiText>{"PERSONAL MT5"}</UiText></span><Link href="/" className="text-btn"><UiText>{"Back to Stratum"}</UiText></Link></div></header>
   {confirmation&&<p role="status" className="studio-notice"><UiText>{confirmation==='confirmed'
    ?'Email verified. Sign in with your email and password to open your demo workspace.'
    :'This confirmation link is invalid or expired. If you already verified your email, sign in below.'}</UiText></p>}
  <div className="studio-layout">
   <aside className="studio-sidebar"><div><span className="sidebar-caption mono"><UiText>{"WORKSPACE"}</UiText></span><a href="#builder" className="sidebar-active"><GitBranch size={18}/><UiText>{"Engine dashboard"}</UiText></a><a href="#fixture"><Library size={18}/><UiText>{"Synthetic example"}</UiText></a><button onClick={()=>setConnect(true)}><Terminal size={18}/><UiText>{"MT5 connection"}</UiText></button></div><div className="sidebar-bottom"><ShieldCheck size={21}/><strong><UiText>{"Leased authority"}</UiText></strong><p><UiText>{"One authorized terminal."}</UiText><br/><UiText>{"Apply runs research."}</UiText><br/><UiText>{"Trading starts OFF."}</UiText></p><span className="mono"><UiText>{"CONTROL / PERSONAL AUTHORITY"}</UiText></span></div></aside>
   <main className="studio-main" id="builder"><AdminStrategyAccess credential={credential}/><section className="studio-market-stage"><div className="studio-heading"><div><div className="eyebrow"><UiText>{"THE RESEARCH FLOOR / SUBSCRIBER DESK"}</UiText></div><h1><UiText>{"Your edge."}</UiText><br/><span><UiText>{"Your controls."}</UiText></span></h1><p><UiText>{"Build the logic. Test the idea. Own the decision."}</UiText></p><div className="studio-stage-caption mono"><span className="studio-stage-dot"/><UiText>{"FOUR ENGINES / ONE WORKSPACE"}</UiText></div></div></div><StudioMarketOrbit/><span className="studio-orbit-hint mono"><UiText>{"MOVE OVER A COIN TO EXPLORE"}</UiText></span></section><UniversalDashboard key={credential||"signed-out"} credential={credential} restoring={restoring} onCredential={updateCredential} onConnect={()=>setConnect(true)}/><details className="surface" id="fixture"><summary><UiText>{"Synthetic example / isolated from MT5"}</UiText></summary><div className="studio-notice"><LockKeyhole size={14}/><span><UiText>{"This example uses synthetic OHLC data, never broker results or live execution."}</UiText></span></div><StrategyDemo expanded/></details></main>
  </div>
  <Dialog open={connect} onOpenChange={setConnect}><DialogContent className="connection-dialog"><DialogHeader><DialogTitle><UiText>{"One listener. Your authority."}</UiText></DialogTitle><DialogDescription><UiText>{"Approve one installation and one controller. Apply and Trading ON have separate permissions."}</UiText></DialogDescription></DialogHeader><ConnectionPanel key={credential||"signed-out"} credential={credential} onCredential={updateCredential}/></DialogContent></Dialog>
  <Toaster theme="light" position="bottom-right"/>
 </div>;
}

