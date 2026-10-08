"use client";
import { useRef, useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { BookOpen, Check, ChevronLeft, ChevronRight, Download, FolderOpen, Monitor, ShieldCheck, Terminal, UserRound, Globe2, BarChart3, ArrowRight, AlertCircle } from 'lucide-react';
import ConsoleWindow from './console-window';
import { useLanguage } from './language-provider';
import { activationSteps, activationText } from '@/lib/activation-guide';

const icons = [UserRound, Download, Terminal, ShieldCheck, FolderOpen, Monitor, Globe2, BarChart3];
export default function EaActivationGuide({signedIn,active,online,authorized,onConnect}:{signedIn:boolean;active:boolean;online:boolean;authorized:boolean;onConnect:()=>void}) {
 const {locale}=useLanguage(),[open,setOpen]=useState(false),[step,setStep]=useState(0),[paused,setPaused]=useState(false),trigger=useRef<HTMLButtonElement>(null);
 const text=(en:string,tr:string,de:string)=>activationText([en,tr,de],locale),current=activationSteps[step],Icon=icons[step],still=paused;
 const title=text('EX5 activation guide','EX5 aktivasyon rehberi','EX5-Aktivierungsanleitung');
 return <>
  <button ref={trigger} type="button" className="secondary-btn activation-launch" onClick={()=>setOpen(true)}><BookOpen size={18}/>{title}<span>8 {text('steps','adım','Schritte')}</span></button>
  <ConsoleWindow open={open} onOpenChange={setOpen} returnFocus={trigger} title={title} description={text('From your personal download to your first MT5 audit. No compiler, serial-number guessing or broker password.','Kişisel indirmeden ilk MT5 auditine. Derleyici, tahmini seri numarası veya broker şifresi gerekmez.','Vom persönlichen Download bis zum ersten MT5-Audit. Ohne Compiler, erratene Seriennummer oder Broker-Passwort.')} tone="mint"
   footer={<div className="activation-navigation"><button type="button" className="secondary-btn" disabled={step===0} onClick={()=>setStep(s=>s-1)}><ChevronLeft size={17}/>{text('Previous','Önceki','Zurück')}</button><span>{step+1} / {activationSteps.length}</span><button type="button" className="primary-btn" onClick={()=>step===activationSteps.length-1?setOpen(false):setStep(s=>s+1)}>{step===activationSteps.length-1?text('Close guide','Rehberi kapat','Anleitung schließen'):text('Next step','Sonraki adım','Nächster Schritt')}<ChevronRight size={17}/></button></div>}>
   <div className="activation-room">
    <nav className="activation-steps" aria-label={text('Activation steps','Aktivasyon adımları','Aktivierungsschritte')}>{activationSteps.map((item,i)=><button key={item.id} type="button" aria-current={step===i?'step':undefined} onClick={()=>setStep(i)}><span>{i+1}</span>{activationText(item.title,locale)}</button>)}</nav>
    <div className="activation-content">
     <div className="activation-live" aria-label={text('Actual connection status','Gerçek bağlantı durumu','Tatsächlicher Verbindungsstatus')}>{[
      [text('Account access','Hesap erişimi','Kontozugang'),signedIn&&active],
      [text('MT5 online','MT5 çevrimiçi','MT5 online'),online],
      [text('Browser control','Tarayıcı yetkisi','Browser-Steuerung'),authorized],
     ].map(([label,ready])=><span key={String(label)} data-ready={!!ready}><i/>{String(label)}: {ready?text('verified','doğrulandı','bestätigt'):text('not verified','doğrulanmadı','nicht bestätigt')}</span>)}</div>
     <AnimatePresence mode="wait" initial={false}><motion.article key={current.id} className="activation-step-content" initial={still?false:{opacity:0,y:12}} animate={{opacity:1,y:0}} exit={{opacity:0,y:still?0:-8}} transition={{duration:still?0:.22}}>
      <div className="activation-scene" data-scene={current.id} data-paused={still} aria-hidden="true">
       <span className="activation-scene-label">{text('SETUP ILLUSTRATION','KURULUM ÖRNEĞİ','EINRICHTUNGSILLUSTRATION')}</span>
       <div className="activation-device"><Icon size={42}/><strong>{activationText(current.title,locale)}</strong></div>
       <motion.div className="activation-transfer" animate={still?{x:0,opacity:1}:{x:[-8,8,-8],opacity:[.4,1,.4]}} transition={{duration:2.4,repeat:still?0:Infinity}}><ArrowRight size={24}/></motion.div>
       <div className="activation-receipt">{current.id==='package'?<><code>UniversalConnectionEA.ex5</code><code>connection.mjs</code><code>personal-setup.json</code></>:current.id==='helper'?<><code>Pairing code: ******</code><code>Fingerprint: ...</code><code>Inputs preset: ...</code></>:current.id==='pair'?<><ShieldCheck size={28}/><span>{text('Compare both fingerprints','İki parmak izini karşılaştır','Beide Fingerabdrücke vergleichen')}</span><div className="activation-fingerprint"><i/><i/><i/><i/><i/><i/></div></>:current.id==='files'?<><code>MQL5 / Experts</code><code>MQL5 / Indicators</code><FolderOpen size={24}/></>:current.id==='attach'?<><code>Inputs / Load</code><code>connection.set</code><span>InpInstallationId</span></>:current.id==='audit'?<><BarChart3 size={30}/><strong>{text('TRADING OFF','TRADING KAPALI','TRADING AUS')}</strong><span>{text('History test first','Önce geçmiş veri testi','Zuerst Historientest')}</span></>:current.id==='authorize'?<><Globe2 size={28}/><span>{text('This browser + your device','Bu tarayıcı + cihazın','Dieser Browser + dein Gerät')}</span></>:<><UserRound size={28}/><span>DEMO / {text('subscription','abonelik','Abonnement')}</span></>}</div>
      </div>
      <header><span className="eyebrow">{text('STEP','ADIM','SCHRITT')} {step+1}</span><h3>{activationText(current.title,locale)}</h3><p>{activationText(current.summary,locale)}</p></header>
      <ol className="activation-tasks">{current.tasks.map((task,i)=><li key={i}><span>{i+1}</span>{activationText(task,locale)}</li>)}</ol>
      {current.path&&<code className="activation-path">{current.path}</code>}
      <div className="activation-expected"><Check size={20}/><div><strong>{text('What you should see','Görmen gereken','Das solltest du sehen')}</strong><p>{activationText(current.check,locale)}</p></div></div>
      {current.warning&&<p className="activation-warning"><AlertCircle size={19}/>{activationText(current.warning,locale)}</p>}
      {(current.id==='pair'||current.id==='authorize')&&<button type="button" className="secondary-btn" onClick={()=>{setOpen(false);onConnect();}}><Terminal size={17}/>{text('Open MT5 connection manager','MT5 bağlantı yöneticisini aç','MT5-Verbindungsverwaltung öffnen')}</button>}
     </motion.article></AnimatePresence>
     <div className="activation-disclaimer"><span>{text('Reading or advancing this guide does not activate a licence or enable trading. Status above comes from Studio, not completed steps.','Bu rehberi okumak veya ilerletmek lisans aktive etmez, trading açmaz. Üstteki durumlar rehber adımlarından değil Studio’dan gelir.','Lesen oder Weiterklicken aktiviert keine Lizenz und keinen Handel. Der Status oben stammt aus Studio, nicht aus abgehakten Schritten.')}</span><button type="button" className="text-btn" aria-pressed={paused} onClick={()=>setPaused(p=>!p)}>{text(paused?'Resume illustration':'Pause illustration',paused?'Görseli oynat':'Görseli duraklat',paused?'Illustration fortsetzen':'Illustration pausieren')}</button></div>
    </div>
   </div>
  </ConsoleWindow>
 </>;
}
