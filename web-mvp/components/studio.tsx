"use client";
import { useState } from "react";
import { Layers, GitBranch, Library, ShieldCheck, Terminal, LockKeyhole } from "lucide-react";
import { Dialog,DialogContent,DialogTitle,DialogDescription,DialogHeader } from "@/components/ui/dialog";
import { Toaster } from "@/components/ui/sonner";
import { Brand } from "./launch-page";
import StrategyDemo from "./strategy-demo";
import ConnectionPanel from "./connection-panel";
export default function Studio() {
 const [connect,setConnect]=useState(false), [credential,setCredential]=useState("");
 return <div className="studio-page">
  <header className="studio-nav"><Brand/><div className="studio-breadcrumb"><span>Personal workspace</span><span>/</span><strong>Strategy studio</strong></div><div className="studio-nav-right"><span className="demo-tag">LOCAL DEMO</span><a href="/" className="text-btn">Back to Stratum</a></div></header>
  <div className="studio-layout">
   <aside className="studio-sidebar"><div><span className="sidebar-caption mono">WORKSPACE</span><a href="#builder" className="sidebar-active"><GitBranch size={18}/>Engine builder</a><a href="#local-save"><Library size={18}/>Local strategies</a><button onClick={()=>setConnect(true)}><Terminal size={18}/>MT5 connection</button></div><div className="sidebar-bottom"><ShieldCheck size={21}/><strong>Research mode</strong><p>Local development.<br/>No live orders.<br/>MT5 runner not connected.</p><span className="mono">CONTROL / LOCAL</span></div></aside>
   <main className="studio-main" id="builder"><div className="studio-heading"><div><div className="eyebrow">Strategy studio</div><h1>Put your idea to the test.</h1><p>Start with a hypothesis. Change a rule. Look at what changes.</p></div><button className="secondary-btn" onClick={()=>setConnect(true)}><Terminal size={15}/>MT5 connection</button></div><div className="studio-notice"><LockKeyhole size={14}/><span>Prototype workspace. Charts and backtests use synthetic OHLC data. They are not the production audit engine.</span></div><div className="terminal-shell" id="local-save"><div className="terminal-bar"><div className="terminal-bar-left"><Layers size={15}/><span className="terminal-path">CUSTOM ENGINE / EMA + RSI + ADX</span></div><span className="demo-tag">EDITABLE</span></div><StrategyDemo expanded/></div><div className="studio-footer"><span>Save locally or export JSON to keep your experiment.</span><span className="mono">NO BROKER DATA / NO LIVE EXECUTION</span></div></main>
  </div>
  <Dialog open={connect} onOpenChange={setConnect}><DialogContent className="connection-dialog"><DialogHeader><DialogTitle>One listener. Your authority.</DialogTitle><DialogDescription>Approve one installation and one controller. Research jobs carry signed, immutable settings; live execution remains disabled.</DialogDescription></DialogHeader><ConnectionPanel credential={credential} onCredential={setCredential}/></DialogContent></Dialog>
  <Toaster theme="light" position="bottom-right"/>
 </div>;
}
