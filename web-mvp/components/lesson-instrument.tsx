"use client";
import { motion } from 'motion/react';
import { UiText } from './language-provider';
import { clockKind, lessonCards, lessonStage } from '@/lib/lesson-story';
import type { ChartFrame } from '@/lib/lesson-chart';
import type { HelpTopic } from '@/lib/studio-help';

export default function LessonInstrument({topic,frame,step,still}:{topic:HelpTopic;frame:ChartFrame;step:number;still:boolean}) {
 const stage=lessonStage(topic),cards=lessonCards(topic,frame,step),pulse={duration:still?0:1.8,repeat:still?0:Infinity};
 return <div className="lesson-instrument" data-stage={stage} data-still={still}>
  {stage==='slots'?<><span><UiText>{'Illustrated open-position slots'}</UiText></span><div className="lesson-slots">{Array.from({length:Math.max(1,Math.min(3,Math.floor(Number(topic.currentValue??topic.defaultValue)||2)))},(_,i)=><motion.div key={i} animate={{y:still?0:step>0&&i===1?[0,-4,0]:0}} transition={pulse} data-occupied={step===0?i===0:true}><strong>#{i+1}</strong><span><UiText>{step===0&&i>0?'Available slot':'Open position'}</UiText></span></motion.div>)}</div><small><UiText>{'Closed positions release a slot; a signal sequence is not an open-position count.'}</UiText></small></>:
   stage==='clock'&&clockKind(topic)==='hours'?<><span><UiText>{'Illustrated time eligibility'}</UiText></span><div className="lesson-clock-track">{Array.from({length:24},(_,h)=><motion.i key={h} data-allowed={step===0||h>=9&&h<14} animate={{opacity:step===0||h>=9&&h<14?1:.25,scaleY:!still&&step>0&&h===11?[1,1.18,1]:1}} transition={pulse}><span>{String(h).padStart(2,'0')}</span></motion.i>)}</div><small><UiText>{'Example hours only; the actual strategy uses its saved broker-time day/hour masks.'}</UiText></small></>:
   stage==='profile'?<><span><UiText>{'Illustrated activity at price'}</UiText></span><div className="lesson-price-profile">{frame.activity.map((v,i)=><div key={i}><code>{(99.5+i*.14).toFixed(2)}</code><motion.i initial={false} animate={{width:`${v*100}%`}} transition={{duration:still?0:.7}} data-peak={v===Math.max(...frame.activity)}/></div>)}</div><small><UiText>{'Synthetic weights, not an exchange order book.'}</UiText></small></>:
   <div className="lesson-instrument-cards">{cards.map((card,i)=><motion.div key={card.label} data-tone={card.tone} initial={false} animate={{y:!still&&((stage==='timeline'||stage==='evidence')&&step===i)?[0,-3,0]:0}} transition={pulse}><span><UiText>{card.label}</UiText></span><strong>{card.value}</strong></motion.div>)}</div>}
  {stage==='quotes'&&<div className="lesson-quote-gap"><motion.i animate={{width:step===0?'15%':'55%'}} transition={{duration:still?0:.6}}/><span><UiText>{'Bid/ask gap relative to risk, not guaranteed execution'}</UiText></span></div>}
  {(stage==='gates'||stage==='rules')&&<div className="lesson-gate-rail"><span><UiText>{'Candidate'}</UiText></span><motion.b animate={{rotate:step===2?0:-20,scale:!still&&step===1?[1,1.1,1]:1}} transition={pulse}>{stage==='rules'?'AND / OR':'GATE'}</motion.b><span><UiText>{'Eligible or rejected'}</UiText></span></div>}
 </div>;
}
