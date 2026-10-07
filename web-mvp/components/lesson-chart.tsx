"use client";
import { UiText, useLanguage } from './language-provider';
import { motion } from 'motion/react';
import { chartLessonFrame, lessonEffect } from '@/lib/lesson-chart';
import type { HelpTopic } from '@/lib/studio-help';
import { useId, type CSSProperties } from 'react';

const colors={mint:'#22836b',coral:'#b5493c',gold:'#a6780a',blue:'#2d739c',muted:'#718797'};
const W=600,H=226,TOP=14,BOTTOM=196;
export default function LessonChart({topic,step,still}:{topic:HelpTopic;step:number;still:boolean}) {
 const {t}=useLanguage();
 const clip=useId().replaceAll(':','');
 const frames=[0,1,2].map(s=>chartLessonFrame(topic,s)),f=frames[step],effect=lessonEffect(topic);
 const prices=frames.flatMap(frame=>[...frame.bars.flatMap(b=>[b.high,b.low]),...frame.lines.map(l=>l.price),...frame.bands.flatMap(b=>[b.low??100,b.high??100])]);
 const max=Math.max(...prices)+.3,min=Math.min(...prices)-.3;
 const y=(p:number)=>TOP+(max-p)/(max-min)*(BOTTOM-TOP),x=(bar:number)=>16+(bar+.5)*(W-32)/f.bars.length;
 const bw=Math.min(11,(W-32)/f.bars.length*.52),end=(bar:number)=>x(Math.min(bar,f.bars.length-1));
 const transition={duration:still?0:.65,ease:'easeInOut' as const};
 return <div className="teaching-chart" data-effect={effect} data-setting={topic.technical??topic.title}>
  <div className="teaching-chart-heading"><strong><UiText>{topic.title}</UiText></strong><span><UiText>{"SYNTHETIC CANDLES"}</UiText></span></div>
  {topic.currentValue!==undefined&&<div className="teaching-setting"><UiText>{"Your draft: "}</UiText><b>{String(topic.currentValue)}</b><span><UiText>{"Explanation only / no edit is applied"}</UiText></span></div>}
  <div className="teaching-plot"><svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`${topic.title}. ${f.note}`} className="teaching-price-chart">
   <defs><clipPath id={clip}><motion.rect x="0" y="0" width={W} height={H} initial={false} animate={{width:still?W:[0,W,W]}} transition={{duration:2.9,times:[0,.82,1],repeat:still?0:Infinity,repeatDelay:.5,ease:'linear'}}/></clipPath></defs>
   {[0,1,2,3,4].map(i=><line key={i} x1="8" x2={W-8} y1={TOP+i*(BOTTOM-TOP)/4} y2={TOP+i*(BOTTOM-TOP)/4} stroke="#c2d8e5" strokeDasharray="3 5"/>)}
   {f.bands.map((b,i)=><motion.rect key={`${b.label}-${i}`} initial={false} animate={{x:x(b.from)-9,y:b.high!==undefined?y(b.high):TOP,width:Math.max(12,end(b.to)-x(b.from)+18),height:b.low!==undefined&&b.high!==undefined?Math.max(5,y(b.low)-y(b.high)):BOTTOM-TOP,opacity:.14}} transition={transition} fill={colors[b.tone]} rx="5"/>)}
   <g clipPath={`url(#${clip})`}>{f.bars.map((b,i)=>{const up=b.close>=b.open,color=up?colors.mint:colors.coral;return <g key={i} className="teaching-candle"><motion.line initial={false} animate={{x1:x(i),x2:x(i),y1:y(b.high),y2:y(b.low)}} transition={transition} stroke={color} strokeWidth="1.5"/><motion.rect initial={{opacity:0}} animate={{x:x(i)-bw/2,y:y(Math.max(b.open,b.close)),height:Math.max(2,Math.abs(y(b.open)-y(b.close))),width:bw,opacity:1}} transition={{...transition,delay:still?0:i*.009}} fill={color} rx="1.5"/></g>;})}</g>
   {!still&&<motion.line initial={false} animate={{x1:[0,W,W],x2:[0,W,W]}} transition={{duration:2.9,times:[0,.82,1],repeat:Infinity,repeatDelay:.5,ease:'linear'}} y1={TOP} y2={BOTTOM} stroke={colors.gold} strokeWidth="2" strokeDasharray="4 4"/>}
   {f.traces.map(t=><motion.polyline key={t.label} initial={{opacity:0,pathLength:0}} animate={{opacity:1,pathLength:1,points:t.values.map((p,i)=>`${x(i)},${y(p)}`).join(' ')}} transition={transition} fill="none" stroke={colors[t.tone]} strokeWidth="2.6"/>)}
   {f.lines.map((l,i)=><motion.line key={i} initial={false} animate={{x1:x(l.from??0),x2:end(l.to??31),y1:y(l.price),y2:y(l.price)}} transition={transition} stroke={colors[l.tone]} strokeWidth="2" strokeDasharray={l.tone==='gold'?'5 3':undefined}/>)}
   {f.marks.map(m=>{const b=f.bars[m.bar];if(!b)return null;const cy=m.side==='buy'?y(b.low)+13:y(b.high)-13;return <motion.g key={m.bar} initial={{opacity:0}} animate={{opacity:1,x:x(m.bar),y:cy}} transition={transition}><title>{t(m.label)}</title>{m.rejected?<><line x1="-5" y1="-5" x2="5" y2="5" stroke={colors.muted} strokeWidth="2.5"/><line x1="-5" y1="5" x2="5" y2="-5" stroke={colors.muted} strokeWidth="2.5"/></>:<path d={m.side==='buy'?'M -6 5 L 0 -5 L 6 5 Z':'M -6 -5 L 0 5 L 6 -5 Z'} fill={colors[m.tone]}/>}</motion.g>;})}
  </svg>{f.lines.slice(0,3).map((l,i)=><span key={i} className="teaching-level-label" style={{top:`${y(l.price)/H*100}%`,color:colors[l.tone]}}><UiText>{l.label}</UiText></span>)}</div>
  {f.activity.length>0&&<div className="teaching-activity" aria-label={effect==='profile'?'Illustrated profile weights':'Illustrated activity, not a measured indicator'}>{f.activity.map((v,i)=><motion.i key={i} initial={false} animate={{height:`${Math.max(8,v*100)}%`}} transition={transition} style={{background:i%3===0?colors.gold:colors.blue}}/>)}</div>}
  {f.indicator&&<div className="teaching-indicator"><strong><UiText>{f.indicator.label}</UiText></strong><span><UiText>{"Teaching threshold: "}</UiText><UiText>{f.indicator.threshold.toFixed(2)}</UiText></span><svg viewBox="0 0 600 70" role="img" aria-label={f.indicator.label}>{(()=>{const indicator=f.indicator!,lo=indicator.label.startsWith('ATR')?Math.min(...indicator.values)*.85:0,hi=indicator.label.startsWith('ATR')?Math.max(...indicator.values)*1.15:100,iy=(v:number)=>64-(v-lo)/(hi-lo)*58;return <><line x1="8" x2="592" y1={iy(indicator.threshold)} y2={iy(indicator.threshold)} stroke={colors.gold} strokeDasharray="5 4"/><motion.polyline initial={false} animate={{points:indicator.values.map((v,i)=>`${x(i)},${iy(v)}`).join(' ')}} transition={transition} fill="none" stroke={colors.blue} strokeWidth="2.8"/></>;})()}</svg></div>}
  <div className="teaching-legend">{f.traces.map(l=><span key={l.label} style={{'--lesson-color':colors[l.tone]} as CSSProperties}><i/><UiText>{l.label}</UiText></span>)}{f.bands.map(l=><span key={l.label} style={{'--lesson-color':colors[l.tone]} as CSSProperties}><i/><UiText>{l.label}</UiText></span>)}{f.marks.filter(m=>m.rejected).length>0&&<span><i style={{background:colors.muted}}/><UiText>{"Crosses = ineligible candidates, not losses"}</UiText></span>}</div>
  {f.size&&<div className="teaching-size" key={f.size}><UiText>{f.size}</UiText></div>}
  <p className="teaching-note" key={`${effect}-${step}`}><UiText>{f.note}</UiText></p>
 </div>;
}
