"use client";
import { useState } from "react";
import { Layers, GitBranch, Library, ShieldCheck, Terminal, LockKeyhole } from "lucide-react";
import { Dialog,DialogContent,DialogTitle,DialogDescription,DialogHeader } from "@/components/ui/dialog";
import { Toaster } from "@/components/ui/sonner";
import { Brand } from "./launch-page";
import StrategyDemo from "./strategy-demo";
import ConnectionPanel from "./connection-panel";
import UniversalDashboard from "./universal-dashboard";
import StudioMarketOrbit from "./studio-market-orbit";
export default function Studio() {
 const [connect,setConnect]=useState(false), [credential,setCredential]=useState("");
 return <div className="studio-page">
  <header className="studio-nav"><Brand/><div className="studio-breadcrumb"><span>Personal workspace</span><span>/</span><strong>Strategy studio</strong></div><div className="studio-nav-right"><span className="demo-tag">LOCAL MT5 PILOT</span><a href="/" className="text-btn">Back to Stratum</a></div></header>
  <div className="studio-layout">
   <aside className="studio-sidebar"><div><span className="sidebar-caption mono">WORKSPACE</span><a href="#builder" className="sidebar-active"><GitBranch size={18}/>Engine dashboard</a><a href="#fixture"><Library size={18}/>Synthetic example</a><button onClick={()=>setConnect(true)}><Terminal size={18}/>MT5 connection</button></div><div className="sidebar-bottom"><ShieldCheck size={21}/><strong>Leased authority</strong><p>One authorized terminal.<br/>Apply runs research.<br/>Trading starts OFF.</p><span className="mono">CONTROL / LOCAL PILOT</span></div></aside>
   <main className="studio-main" id="builder"><section className="studio-market-stage"><div className="studio-heading"><div><div className="eyebrow">THE RESEARCH FLOOR / SUBSCRIBER DESK</div><h1>Your edge.<br/><span>Your controls.</span></h1><p>Build the logic. Test the idea. Own the decision.</p><div className="studio-stage-caption mono"><span className="studio-stage-dot"/>FOUR ENGINES / ONE WORKSPACE</div></div></div><StudioMarketOrbit/><span className="studio-orbit-hint mono">MOVE OVER A COIN TO EXPLORE</span></section><UniversalDashboard credential={credential} onCredential={setCredential} onConnect={()=>setConnect(true)}/><details className="surface" id="fixture"><summary>Synthetic example / isolated from MT5</summary><div className="studio-notice"><LockKeyhole size={14}/><span>This example uses synthetic OHLC data, never broker results or live execution.</span></div><StrategyDemo expanded/></details></main>
  </div>
  <Dialog open={connect} onOpenChange={setConnect}><DialogContent className="connection-dialog"><DialogHeader><DialogTitle>One listener. Your authority.</DialogTitle><DialogDescription>Approve one installation and one controller. Apply and Trading ON have separate permissions.</DialogDescription></DialogHeader><ConnectionPanel credential={credential} onCredential={setCredential}/></DialogContent></Dialog>
  <Toaster theme="light" position="bottom-right"/>
 </div>;
}
