"use client";
import { UiText } from './language-provider';
import { useEffect, useState, type ReactNode } from 'react';
import { Dialog } from 'radix-ui';
import { CircleHelp, Pause, Play, X, ShieldCheck } from 'lucide-react';
import { helpTopics, type HelpTopic } from '@/lib/studio-help';
import { useMotionPreference } from '@/lib/use-motion-preference';
import TutorRobot from './tutor-robot';
import LessonChart from './lesson-chart';
import { effectSteps, lessonEffect } from '@/lib/lesson-chart';
import { useLanguage } from './language-provider';
import { localizedHelp } from '@/lib/localized-help';

export function Lesson({topic}:{topic:HelpTopic}) {
 const [step,setStep]=useState(0),[paused,setPaused]=useState(false),[allowMotion,setAllowMotion]=useState(false),[compareDefault,setCompareDefault]=useState(false),reduced=useMotionPreference(),{t,locale}=useLanguage();
 const copy=localizedHelp(topic,locale);
 const still=paused||(reduced&&!allowMotion);
 const steps=effectSteps[lessonEffect(topic)];
 useEffect(()=>{if(still)return;const id=setInterval(()=>{if(!document.hidden)setStep(n=>(n+1)%3);},3400);return()=>clearInterval(id);},[still]);
 return <div className="lesson" data-paused={still} data-motion-override={allowMotion}>
  {topic.technical&&<section className="lesson-parameter"><div><span>{t('Current draft')}</span><strong>{String(topic.currentValue??topic.defaultValue??'—')}</strong></div><div><span>{t('Original default')}</span><strong>{topic.defaultValue??'—'}</strong></div>{topic.defaultValue!==undefined&&<button type="button" className="secondary-btn" aria-pressed={compareDefault} onClick={()=>{setCompareDefault(v=>!v);setStep(1);setPaused(true);}}>{t(compareDefault?'Show current draft':'Compare with default')}</button>}<code>{topic.technical}</code></section>}
  {topic.currentValue===false&&<p className="lesson-off-notice">{t('This switch is OFF in your draft. The animation illustrates how its enabled rule works; it does not activate it.')}</p>}
  <div className="lesson-scene" aria-label={`${topic.title}: illustrated explanation, not live data`}>
   <div className="lesson-visual"><LessonChart topic={compareDefault?{...topic,currentValue:topic.defaultValue}:topic} step={step} still={still}/></div><div className="lesson-teacher"><p className="lesson-bubble"><UiText>{t(steps[step])}</UiText></p><TutorRobot paused={still} allowMotion={allowMotion} mood="explaining"/><span><UiText>{t('THE STUDIO GUIDE')}</UiText></span></div>
  </div>
  <div className="lesson-steps" aria-label={t("Explanation steps")}>{steps.map((text,i)=><button type="button" key={text} aria-pressed={step===i} onClick={()=>{setStep(i);setPaused(true);}}><span><UiText>{i+1}</UiText></span><UiText>{text}</UiText></button>)}</div>
  <div className="lesson-playback"><span><UiText>{t('Illustration only. No settings or orders are changed.')}</UiText></span><button type="button" className="text-btn" onClick={()=>{if(reduced&&!allowMotion){setAllowMotion(true);setPaused(false);}else setPaused(p=>!p);}}>{still?<Play size={15}/>:<Pause size={15}/>} <UiText>{t(reduced&&!allowMotion?'Play this animation':paused?'Resume':'Pause')}</UiText></button></div>
  <div className="lesson-copy"><h3><UiText>{"For example"}</UiText></h3><p>{copy.example}</p><div className="lesson-caution"><ShieldCheck size={19}/><p>{copy.caution}</p></div></div>
 </div>;
}
export default function HelpButton({topic,children}:{topic:HelpTopic|string;children?:ReactNode}) {
 const {t,locale}=useLanguage();
 const value=typeof topic==='string'?helpTopics[topic]:topic;
 if(!value)return null;
 const copy=localizedHelp(value,locale);
 return <Dialog.Root><Dialog.Trigger asChild><button type="button" className={children?'guide-open secondary-btn':'help-button'} aria-label={`${t('Explain')}: ${copy.title}`}><CircleHelp size={17}/><UiText>{children}</UiText></button></Dialog.Trigger>
  <Dialog.Portal><Dialog.Overlay className="help-overlay"/><Dialog.Content className="help-window">
   <header><div><span className="eyebrow"><UiText>{"A MINUTE WITH YOUR GUIDE"}</UiText></span><Dialog.Title><UiText>{value.title}</UiText></Dialog.Title></div><Dialog.Close className="icon-btn" aria-label={t("Close explanation")}><X size={21}/></Dialog.Close></header>
   <Dialog.Description>{copy.summary}</Dialog.Description><Lesson topic={value}/>
   {value.technical&&<details className="help-technical"><summary><UiText>{"Engine reference & original default"}</UiText></summary><code>{value.technical}</code><span><UiText>{"Original default: "}</UiText><UiText>{value.defaultValue}</UiText></span></details>}
   {locale!=='en'&&<details className="help-technical"><summary>{t('Original engine reference (English)')}</summary><p lang="en">{value.summary}</p><p lang="en">{value.example}</p><p lang="en">{value.caution}</p></details>}
   <footer><Dialog.Close className="primary-btn"><UiText>{"Back to my setup"}</UiText></Dialog.Close></footer>
  </Dialog.Content></Dialog.Portal>
 </Dialog.Root>;
}
