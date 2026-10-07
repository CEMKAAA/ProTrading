"use client";
import { useEffect, useId, useRef, useState, type CSSProperties } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { ArrowRight, Check, GitBranch, Laptop, LockKeyhole, Pause, Play, ShieldCheck, SlidersHorizontal, Terminal, Wifi } from 'lucide-react';
import { useMotionPreference } from '@/lib/use-motion-preference';
import { useLanguage } from './language-provider';

type Stage = 'builder' | 'audit' | 'connection' | 'control';
const stages: Stage[] = ['builder', 'audit', 'connection', 'control'];
const labels = ['Create your rules', 'Test the idea', 'Connect your MT5', 'You decide'];
const icons = [GitBranch, SlidersHorizontal, Terminal, ShieldCheck];
const prices = Array.from({ length: 36 }, (_, i) => {
  const open = 80 + Math.sin(i * .47) * 10 + i * .8, close = open + Math.sin(i * 1.2 + .5) * 7;
  return { open, close, high: Math.max(open, close) + 3, low: Math.min(open, close) - 3 };
});
export function SyntheticTape({ variant = 'audit' }: { variant?: Stage }) {
  const { t } = useLanguage();
  return <div className="product-tape"><svg viewBox="0 0 650 230" role="img" aria-label={t('Animated teaching chart. Not market data.')}>
    {[40,85,130,175].map(y => <line key={y} x1="0" x2="650" y1={y} y2={y} stroke="currentColor" opacity=".12" strokeDasharray="3 6"/>)}
    {prices.map((b, i) => <g key={i} className="product-candle" style={{ '--candle-delay': `${i * .09}s` } as CSSProperties}>
      <line x1={18+i*17.2} x2={18+i*17.2} y1={216-b.high*1.35} y2={216-b.low*1.35} stroke={b.close>b.open?'#14795e':'#b5493c'} strokeWidth="2"/>
      <rect x={13+i*17.2} width="10" y={216-Math.max(b.open,b.close)*1.35} height={Math.max(3,Math.abs(b.open-b.close)*1.35)} rx="2" fill={b.close>b.open?'#14795e':'#b5493c'}/>
    </g>)}
    <path className="product-average" d={prices.map((b,i)=>`${i?'L':'M'}${18+i*17.2},${220-b.open*1.35}`).join(' ')} fill="none" stroke="#a6780a" strokeWidth="3" pathLength="1"/>
    <line className="product-scanner" x1="22" x2="22" y1="12" y2="220" stroke="#a6780a" strokeWidth="2" strokeDasharray="4 5"/>
  </svg><div className="product-chart-tags"><span>{t(variant==='builder'?'Signal conditions':variant==='control'?'Stops and targets':'Inspect every trade')}</span><span>{t('Illustration / not live data')}</span></div></div>;
}
export default function ProductStage({ fixed, compact = false }: { fixed?: Stage; compact?: boolean }) {
  const [index, setIndex] = useState(0), [paused, setPaused] = useState(false), [visible, setVisible] = useState(true);
  const host = useRef<HTMLDivElement>(null), reduced = useMotionPreference(), { t } = useLanguage(), stage = fixed ?? stages[index];
  const prefix=useId().replaceAll(':','');
  useEffect(() => {
    const node = host.current; if (!node) return;
    const observer = new IntersectionObserver(entries => setVisible(entries[0].isIntersecting)); observer.observe(node);
    return () => observer.disconnect();
  }, []);
  useEffect(() => {
    if (fixed || paused || reduced || !visible) return;
    const timer = setInterval(() => { if (!document.hidden) setIndex(i => (i + 1) % 4); }, 6500);
    return () => clearInterval(timer);
  }, [fixed, paused, reduced, visible]);
  return <div ref={host} className={`product-stage${compact?' product-stage-compact':''}`} data-playing={!paused&&!reduced&&visible}>
    <div className="product-stage-bar"><span><i/>{t('YOUR STRATEGY. YOUR TERMINAL.')}</span><span className="product-stage-badge">{t('Product walkthrough')}</span></div>
    {!fixed && <div className="product-stage-tabs" role="tablist" aria-label={t('Explore the workflow')}>{stages.map((s, i) => { const Icon=icons[i]; return <button id={`${prefix}-tab-${s}`} aria-controls={`${prefix}-${s}`} role="tab" aria-selected={index===i} tabIndex={index===i?0:-1} key={s} onClick={()=>{setIndex(i);setPaused(true);}} onKeyDown={e=>{if(['ArrowRight','ArrowLeft','Home','End'].includes(e.key)){e.preventDefault();const next=e.key==='Home'?0:e.key==='End'?3:(i+(e.key==='ArrowRight'?1:3))%4;setIndex(next);setPaused(true);document.getElementById(`${prefix}-tab-${stages[next]}`)?.focus();}}}><Icon size={18}/><span>{t(labels[i])}</span></button>;})}</div>}
    <AnimatePresence mode="wait" initial={false}><motion.div key={stage} id={`${prefix}-${stage}`} role={fixed?undefined:'tabpanel'} aria-labelledby={fixed?undefined:`${prefix}-tab-${stage}`} className={`product-stage-body product-stage-${stage}`} initial={{opacity:0,y:20,rotateX:5}} animate={{opacity:1,y:0,rotateX:0}} exit={{opacity:0,y:-16,scale:.98}} transition={{duration:reduced?0:.45}}>
      {stage==='builder' && <><div className="product-rule-stack"><div className="product-mini-heading"><GitBranch size={20}/><strong>{t('MY FIRST ENGINE')}</strong><span>{t('BUY rules')}</span></div>{[['RSI (14)','>','50'],['EMA (9)','>','EMA (20)'],['Price','inside','FVG zone']].map((row,i)=><div key={i} className="product-rule" style={{'--rule-delay':`${i*.7}s`} as CSSProperties}><span className="product-rule-index">0{i+1}</span><b>{t(row[0])}</b><span>{t(row[1])}</span><strong>{t(row[2])}</strong><span className="product-rule-check"><Check size={17}/></span>{i<2&&<i className="product-rule-gate">{t(i===0?'AND':'OR')}</i>}</div>)}<div className="product-rule-add">+ {t('Add another condition')}</div></div><SyntheticTape variant={stage}/><div className="product-float-label"><GitBranch size={18}/>{t('Separate BUY and SELL logic')}</div></>}
      {stage==='audit' && <><div className="product-audit-top"><div><span>{t('History window')}</span><strong>{t('5 years')}</strong></div><div><span>{t('Real work, real progress')}</span><strong>{t('Reading broker history')}</strong></div></div><SyntheticTape/><div className="product-audit-track"><i/></div><div className="product-audit-footer"><span><Check size={17}/>{t('Entry, stop, target and outcome')}</span><span><Check size={17}/>{t('Costs and data coverage')}</span></div></>}
      {stage==='connection' && <><div className="product-link-scene"><div className="product-device"><Laptop size={46}/><strong>{t('Your web studio')}</strong><span>{t('Rules & settings')}</span></div><div className="product-link-wire"><i/><i/><i/><LockKeyhole size={24}/></div><div className="product-device product-device-mt5"><Terminal size={46}/><strong>{t('Your MT5')}</strong><span>{t('Your personalized EA')}</span></div></div><div className="product-link-receipt"><Wifi size={20}/><div><strong>{t('Approved device connection')}</strong><span>{t('Account-bound. Revocable. Yours.')}</span></div><ShieldCheck size={24}/></div><div className="product-packet"><span>{t('SETTINGS')}</span><ArrowRight size={16}/><span>{t('AUDIT RESULTS')}</span></div></>}
      {stage==='control' && <><div className="product-control-knobs">{['Risk per trade','Stop distance','Maximum open positions','Trade hours'].map((label,i)=><div key={label}><SlidersHorizontal size={20}/><span>{t(label)}</span><strong>{['1%','10 pips','3','09:00–17:00'][i]}</strong></div>)}</div><div className="product-permission"><div><ShieldCheck size={29}/><strong>{t('Research first. Trading stays OFF.')}</strong><span>{t('Only your explicit approval can request new trades.')}</span></div><div className="product-locked-lever"><i/><b>OFF</b></div></div><p className="product-control-note">{t('Your funds stay with your broker.')}</p></>}
    </motion.div></AnimatePresence>
    <div className="product-stage-foot"><span>{t('Illustration only. No orders are sent.')}</span>{!fixed&&<button className="text-btn" onClick={()=>setPaused(p=>!p)} disabled={reduced} aria-label={t(paused?'Resume walkthrough':'Pause walkthrough')}>{paused?<Play size={15}/>:<Pause size={15}/>} {t(paused?'Resume':'Pause')}</button>}</div>
  </div>;
}
