"use client";
import { useEffect, useRef, useState } from 'react';
import { Bot, Send, ShieldCheck, Undo2, ChevronRight, LoaderCircle, Mic, MicOff, Volume2, VolumeX, Save, History, Plus, Trash2 } from 'lucide-react';
import { CONTROL_API,CONTROL_CREDENTIALS,CONTROL_TIMEOUT_MS} from '@/lib/control-endpoint';
import { planAgentActions, type AgentAnswer, type AgentPlan } from '@/lib/studio-agent';
import type { UniversalConfiguration } from '@/lib/universal-contract';
import { controlLabel } from '@/lib/studio-help';
import { useLanguage } from './language-provider';
import ConsoleWindow from './console-window';
import TutorRobot from './tutor-robot';
import HelpButton from './studio-help';
import { eaCatalog } from '@/lib/universal-contract';
import { controlHelp } from '@/lib/studio-help';
import type { TutorMood } from '@/lib/tutor-behavior';
import { useAgentVoice } from './use-agent-voice';
import {assistantBlocker,assistantFailure,assistantJson} from '@/lib/studio-agent-client';
import {strategyPreview,builderExpression} from '@/lib/studio-agent-preview';
import {conversationTitle,saveConversationSchema,savedConversationSchema,conversationListSchema,type ConversationSummary} from '@/lib/studio-conversations';

type Message={role:'user'|'assistant';content:string};
type Status={providers:Record<'local'|'openrouter',{configured:boolean;model:string|null}>};
type Result={wins:number;losses:number;flat:number;open:number;data:number;netR:number;winRate:number|null;maxClosedDrawdownR:number;coverageComplete:boolean};
type Props={credential:string;active:boolean;configuration:UniversalConfiguration;auditWeeks:number;symbol:string|null;jobId:string|null;summary:Result|null;resultIsCurrent:boolean;strategies:UniversalConfiguration[];connectionKey:string;pending:boolean;onMoodChange:(mood:TutorMood)=>void;
 onConfirm:(plan:AgentPlan)=>Promise<void>;onRestore:(configuration:UniversalConfiguration,weeks:number)=>void;};

const errors:Record<string,string>={AI_NOT_CONFIGURED:'The assistant needs a configured model. The rest of your studio still works.',AI_CLOUD_CONSENT_REQUIRED:'Allow sharing this conversation and strategy with the selected cloud provider first.',AI_PROVIDER_UNREACHABLE:'The model is unreachable. No settings were changed.',AI_TIMEOUT:'The model timed out. No settings were changed.',AI_INVALID_PROPOSAL:'The model suggested invalid settings. Nothing was applied; simplify the request and try again.',AI_PROVIDER_FAILED:'The model provider rejected the request. No settings were changed.',AI_BUSY:'The assistant is busy. Try again shortly.',AI_RATE_LIMITED:'Too many requests. Wait a minute and try again.',AI_PROVIDER_RATE_LIMITED:'The provider is rate limited. Try again later.',AI_TRUNCATED_RESPONSE:'The model response was incomplete. Nothing was applied. Request a smaller change.',UNAUTHORIZED:'Sign in again to use your private assistant.',ENTITLEMENT_EXPIRED:'Your demo or subscription is inactive.',STALE_PROPOSAL:'Your draft or connection changed. Ask again before applying this suggestion.'};
const providerErrors:Record<string,string>={
 AI_PROVIDER_AUTH_FAILED:'OpenRouter rejected the API key (401). Update the server key and restart the control service.',
 AI_PROVIDER_CREDITS_REQUIRED:'OpenRouter requires available credits for this model (402). Choose a free model or fund your OpenRouter account.',
 AI_MODEL_UNAVAILABLE:'The configured model is unavailable (404). Update the server model ID.',
 AI_ACCESS_REQUIRED:'Sign in with an active demo or subscription to talk to your private assistant.',
 AI_DESK_BUSY:'A dashboard action is still running. Wait for it to finish before sending a message.',
 AI_STATUS_LOADING:'Checking the assistant connection. Your message has not been sent yet.',
 AI_STATUS_UNAVAILABLE:'The assistant connection could not be checked. Retry the connection; your message has not been sent.',
 AI_CONTROL_UNREACHABLE:'The control service could not be reached. Your message was not answered. Check the local server and try again.',
 AI_INVALID_RESPONSE:'The assistant returned an unreadable response. No settings were changed. Try again.',
 AI_WAITING:'Waiting for the model reply. No settings are being applied.',
 AI_CANCELLED:'The request was cancelled. No settings were changed.',
 AI_TIMEOUT:'The reply timed out. No settings were changed. You can send the message again.',
 AI_INTERNAL_ERROR:'The assistant could not process the request. No settings were changed. Try again.',
};
const display=(v:unknown)=>v===undefined?'—':typeof v==='object'?JSON.stringify(v):String(v);
export default function StudioAgent(props:Props){
 const {t,locale}=useLanguage();
 const [open,setOpen]=useState(false),[provider,setProvider]=useState<'local'|'openrouter'>('openrouter'),[consent,setConsent]=useState(false),[messages,setMessages]=useState<Message[]>([]),[input,setInput]=useState(''),[waiting,setWaiting]=useState(false),[error,setError]=useState(''),[status,setStatus]=useState<Status|null>(null);
 const [statusLoading,setStatusLoading]=useState(false),[statusAttempt,setStatusAttempt]=useState(0),[elapsed,setElapsed]=useState(0);
 const [proposal,setProposal]=useState<{answer:AgentAnswer;plan:AgentPlan;base:string}|null>(null),[undo,setUndo]=useState<{configuration:UniversalConfiguration;weeks:number;after:string}|null>(null);
 const [voiceConsent,setVoiceConsent]=useState(false),[readReplies,setReadReplies]=useState(false),[autoSend,setAutoSend]=useState(false);
 const [chatId,setChatId]=useState<string|null>(null),[chatTitle,setChatTitle]=useState(''),[savedStamp,setSavedStamp]=useState<string|null>(null);
 const [historyOpen,setHistoryOpen]=useState(false),[historyItems,setHistoryItems]=useState<ConversationSummary[]>([]),[historyOffset,setHistoryOffset]=useState(0),[historyMore,setHistoryMore]=useState(false);
 const [historyBusy,setHistoryBusy]=useState<string|null>(null),[historyError,setHistoryError]=useState(''),[historyNotice,setHistoryNotice]=useState('');
 const [replacement,setReplacement]=useState<{id:string|null}|null>(null),[deleteId,setDeleteId]=useState<string|null>(null);
 const historyRequest=useRef<AbortController|null>(null),historyFlight=useRef(false);
 const chatStamp=JSON.stringify({title:chatTitle.trim()||conversationTitle(messages),provider,locale,messages});
 const unsaved=messages.length>0&&chatStamp!==savedStamp;
 const voice=useAgentVoice({locale,active:open&&voiceConsent&&props.active,onTranscript:text=>{setInput(text);if(autoSend)void ask(text);}});
 const snapshot=JSON.stringify({configuration:props.configuration,weeks:props.auditWeeks,connection:props.connectionKey}),current=useRef(snapshot),request=useRef<AbortController|null>(null),inFlight=useRef(false),scroll=useRef<HTMLDivElement|null>(null),trigger=useRef<HTMLButtonElement|null>(null);
 const failureText=(code:string)=>t(providerErrors[code]??errors[code]??'The request failed. No success was assumed. Check your connection or simplify the request.');
 current.current=snapshot;
 useEffect(()=>()=>{request.current?.abort();historyRequest.current?.abort();},[]);
 useEffect(()=>{if(!open){request.current?.abort();historyRequest.current?.abort();voice.stopListening();voice.stopSpeech();}},[open]);
 useEffect(()=>{scroll.current?.scrollTo({top:scroll.current.scrollHeight,behavior:'smooth'});},[messages,waiting,proposal,error]);
 useEffect(()=>{
  if(!waiting){setElapsed(0);return;}
  const started=Date.now(),timer=setInterval(()=>setElapsed(Math.floor((Date.now()-started)/1000)),1000);
  return()=>clearInterval(timer);
 },[waiting]);
 useEffect(()=>{
  if(!open||!props.credential||!props.active)return;
  const controller=new AbortController();let alive=true;setStatus(null);setStatusLoading(true);setError('');
  void fetch(CONTROL_API+'/v1/assistant/status',{headers:{Authorization:`Bearer ${props.credential}`},credentials:CONTROL_CREDENTIALS,cache:'no-store',redirect:'error',signal:AbortSignal.any([controller.signal,AbortSignal.timeout(CONTROL_TIMEOUT_MS)])}).then(r=>assistantJson<Status>(r)).then(data=>{
   if(!data?.providers||['local','openrouter'].some(key=>typeof data.providers[key as 'local'|'openrouter']?.configured!=='boolean'))throw new Error('AI_INVALID_RESPONSE');
   if(alive)setStatus(data);
  }).catch(e=>{if(alive&&!controller.signal.aborted)setError(assistantFailure(e));}).finally(()=>{if(alive)setStatusLoading(false);});
  return()=>{alive=false;controller.abort();};
 },[open,props.credential,props.active,statusAttempt]);
 const blocker=assistantBlocker({credential:props.credential,active:props.active,loading:statusLoading,available:!!status,configured:!!status?.providers[provider].configured,cloud:provider==='openrouter',consent,pending:props.pending});
 const enabled=!blocker;
 async function historyFetch(path:string,body?:unknown){
  const controller=historyRequest.current??new AbortController();historyRequest.current=controller;
  const response=await fetch(CONTROL_API+'/v1/assistant/conversations'+path,{method:body===undefined?'GET':'POST',headers:{Authorization:`Bearer ${props.credential}`,...(body===undefined?{}:{'Content-Type':'application/json'})},credentials:CONTROL_CREDENTIALS,cache:'no-store',redirect:'error',signal:AbortSignal.any([controller.signal,AbortSignal.timeout(CONTROL_TIMEOUT_MS)]),...(body===undefined?{}:{body:JSON.stringify(body)})});
  const data=await assistantJson<unknown>(response);
  if(controller.signal.aborted)throw new DOMException('Aborted','AbortError');
  return data;
 }
 async function historyTask(kind:string,work:()=>Promise<void>){
  if(historyFlight.current||inFlight.current||!props.credential)return;
  historyFlight.current=true;historyRequest.current=new AbortController();setHistoryBusy(kind);setHistoryError('');setHistoryNotice('');
  try{await work();}catch(e){if(!historyRequest.current?.signal.aborted)setHistoryError(assistantFailure(e));}
  finally{historyFlight.current=false;setHistoryBusy(null);}
 }
 async function listHistory(offset=0){
  setHistoryOpen(true);setDeleteId(null);
  await historyTask('list',async()=>{
   const list=conversationListSchema.parse(await historyFetch('/list',{offset}));
   setHistoryItems(list.items);setHistoryOffset(offset);setHistoryMore(list.hasMore);
  });
 }
 async function saveChat(){
  if(!messages.length)return;
  await historyTask('save',async()=>{
   const id=chatId??crypto.randomUUID();setChatId(id);
   const value=saveConversationSchema.safeParse({id,title:chatTitle.trim()||conversationTitle(messages),provider,locale,messages});
   if(!value.success)throw new Error('CONVERSATION_TOO_LARGE');
   const saved=savedConversationSchema.parse(await historyFetch('',value.data));
   if(saved.id!==id)throw new Error('CONVERSATION_SAVE_FAILED');
   setChatTitle(saved.title);setSavedStamp(JSON.stringify({title:saved.title,provider,locale,messages}));
   setHistoryNotice('Conversation saved to your account.');setHistoryOpen(false);
  });
 }
 function resetChat(){
  voice.stopListening();voice.stopSpeech();setMessages([]);setInput('');setChatId(null);setChatTitle('');setSavedStamp(null);
  setProposal(null);setUndo(null);setError('');setReplacement(null);setHistoryNotice('');setHistoryError('');
 }
 async function replaceChat(id:string|null){
  if(id===null){resetChat();return;}
  await historyTask('open',async()=>{
   const saved=savedConversationSchema.parse(await historyFetch('/'+id));
   if(saved.id!==id)throw new Error('CONVERSATION_READ_FAILED');
   resetChat();setMessages(saved.messages);setChatId(saved.id);setChatTitle(saved.title);
   if(saved.provider!==provider){setProvider(saved.provider);setConsent(false);}
   setSavedStamp(JSON.stringify({title:saved.title,provider:saved.provider,locale,messages:saved.messages}));
   setHistoryOpen(false);setHistoryNotice('Conversation opened. Your current strategy settings were not changed.');
  });
 }
 function requestReplacement(id:string|null){
  if(unsaved||input.trim())setReplacement({id});else void replaceChat(id);
 }
 async function deleteChat(id:string){
  await historyTask('delete',async()=>{
   const result=await historyFetch('/'+id+'/delete',{});
   if(!result||typeof result!=='object'||!('deleted' in result)||result.deleted!==true)throw new Error('CONVERSATION_DELETE_FAILED');
   if(chatId===id){setChatId(null);setSavedStamp(null);}
   setDeleteId(null);const offset=historyItems.length===1?Math.max(0,historyOffset-25):historyOffset;
   const list=conversationListSchema.parse(await historyFetch('/list',{offset}));
   setHistoryItems(list.items);setHistoryMore(list.hasMore);setHistoryOffset(offset);setHistoryNotice('Saved conversation deleted.');
  });
 }
 async function ask(text=input){
  if(inFlight.current||historyFlight.current||!text.trim())return;
  if(blocker){setError(blocker);return;}
  const nextMessages=[...messages,{role:'user' as const,content:text.trim()}];
  const conversation=nextMessages.slice(-12).map(m=>({...m,content:m.content.slice(0,2000)}));
  const controller=new AbortController(),base=current.current;request.current=controller;inFlight.current=true;setWaiting(true);setError('');setHistoryNotice('');setMessages(nextMessages);setInput('');
  try{
   const requestId=crypto.randomUUID();
   const response=await fetch(CONTROL_API+'/v1/assistant/chat',{method:'POST',headers:{Authorization:`Bearer ${props.credential}`,'Content-Type':'application/json'},credentials:CONTROL_CREDENTIALS,cache:'no-store',redirect:'error',signal:AbortSignal.any([controller.signal,AbortSignal.timeout(90000)]),body:JSON.stringify({provider,locale,cloudConsent:consent,requestId,conversation,context:{configuration:props.configuration,auditWeeks:props.auditWeeks,jobId:props.jobId,symbol:props.symbol,...(proposal?.base===base?{pendingCalls:proposal.plan.calls}:{})}})});
   const answer=await assistantJson<AgentAnswer>(response);
   if(controller.signal.aborted)return;
   if(answer.requestId!==requestId||current.current!==base)throw new Error('STALE_PROPOSAL');
   const plan=planAgentActions(props.configuration,props.auditWeeks,answer.calls,props.strategies);
   const content=answer.message||t('Review the proposed actions below. Nothing has been applied yet.');
   setMessages(m=>[...m,{role:'assistant',content}]);if(readReplies&&voiceConsent)voice.speak(content);
   if(answer.calls.length)setProposal({answer,plan,base});
  }catch(e){if(!controller.signal.aborted)setError(assistantFailure(e));}
  finally{inFlight.current=false;setWaiting(false);}
 }
 async function confirm(){
  if(!proposal||props.pending||inFlight.current||historyFlight.current)return;
  if(current.current!==proposal.base){setError('STALE_PROPOSAL');return;}
  const before=structuredClone(props.configuration),weeks=props.auditWeeks;setError('');
  inFlight.current=true;setWaiting(true);
  try{
   await props.onConfirm(proposal.plan);
   if(proposal.plan.changes.length)setUndo({configuration:before,weeks,after:JSON.stringify({configuration:proposal.plan.configuration,weeks:proposal.plan.auditWeeks,connection:props.connectionKey})});
   setMessages(m=>[...m,{role:'assistant',content:t(proposal.plan.runAudit?'The confirmed draft was sent to MT5 for an audit. Wait for the terminal result below. Trading was not enabled.':proposal.plan.save?'The confirmed setup was saved. Trading was not enabled.':'The confirmed draft is on your desk. Trading was not enabled.')}]);setProposal(null);if(proposal.plan.show||proposal.plan.reviewTrading)setOpen(false);
  }catch(e){setError(e instanceof Error?e.message:'REQUEST_FAILED');}
  finally{inFlight.current=false;setWaiting(false);}
 }
 const stale=!!proposal&&proposal.base!==snapshot;
 const preview=proposal?strategyPreview(proposal.plan.configuration,proposal.plan.auditWeeks,props.symbol):null;
 const mood:TutorMood=error?'concern':waiting||props.pending?'thinking':voice.speaking?'explaining':voice.listening?'listening':proposal?'curious':input?'listening':messages.length?'attentive':'idle';
 useEffect(()=>{props.onMoodChange(open?mood:'idle');},[mood,open,props.onMoodChange]);
 return <>
  <button ref={trigger} type="button" className="agent-launch secondary-btn" aria-label={t('Talk to your guide')} onClick={()=>setOpen(true)}><TutorRobot mood={mood} speaking={voice.speaking} speechPulse={voice.pulse}/><span>{t('Talk to your guide')}</span><ChevronRight size={17}/></button>
  <ConsoleWindow open={open} onOpenChange={setOpen} returnFocus={trigger} title={t('Your strategy co-pilot')} description={t('Describe your idea. I explain the controls, propose a draft and help you test it. You stay in charge.')} tone="mint">
   <div className="agent-room">
    <aside className="agent-teacher agent-teacher-pinned"><TutorRobot paused={false} mood={mood} speaking={voice.speaking} speechPulse={voice.pulse}/><div><span className="eyebrow">STRATUM GUIDE</span><strong>{t('One idea. One clear next step.')}</strong><span className="agent-mood" role="status">{t(voice.speaking?'Speaking…':mood==='thinking'?'Checking your setup…':mood==='curious'?'Shall we test this idea?':mood==='listening'?'I am listening.':mood==='concern'?'Let us check what went wrong.':'Ready when you are.')}</span></div><span className="agent-presence" data-mood={mood} aria-hidden="true"><i/><i/><i/></span></aside>
    <section className="agent-chat-library" aria-label={t('Saved conversations')}>
     <div className="agent-library-heading"><span className="eyebrow">{t('YOUR PRIVATE CONVERSATIONS')}</span><span>{t(unsaved?'Unsaved changes':savedStamp?'Saved':'Not saved')}</span></div>
     <div className="agent-library-actions"><label htmlFor="agent-chat-title">{t('Conversation title')}<input id="agent-chat-title" maxLength={80} value={chatTitle} placeholder={conversationTitle(messages)} disabled={!!historyBusy||waiting} onChange={e=>{setChatTitle(e.target.value);setHistoryNotice('');}}/></label>
      <button type="button" className="primary-btn" data-action="save-chat" disabled={!props.credential||!messages.length||waiting||!!historyBusy} onClick={()=>void saveChat()}><Save size={17}/>{t('Save conversation')}</button>
      <button type="button" className="secondary-btn" data-action="chat-history" aria-expanded={historyOpen} disabled={!props.credential||waiting||!!historyBusy} onClick={()=>historyOpen?setHistoryOpen(false):void listHistory()}><History size={17}/>{t('Chat history')}</button>
      <button type="button" className="text-btn" data-action="new-chat" disabled={waiting||!!historyBusy} onClick={()=>requestReplacement(null)}><Plus size={17}/>{t('New conversation')}</button>
     </div>
     <p>{t('Only sent messages are saved, and only when you click Save conversation. Draft proposals are not reapplied when you reopen a chat.')}</p>
     {historyBusy&&<p role="status"><LoaderCircle className="agent-history-spinner" size={17}/>{t('Loading your conversations...')}</p>}
     {historyNotice&&<p className="agent-history-notice" role="status">{t(historyNotice)}</p>}
     {historyError&&<p className="uc-error" role="alert" data-history-error={historyError}>{t(historyError==='CONVERSATION_TOO_LARGE'?'This conversation is too large to save (maximum 512 messages / 1 MB). Start a new conversation.':historyError==='CONVERSATION_NOT_FOUND'?'This saved conversation no longer exists. Refresh Chat history.':'The conversation request failed. Nothing was assumed saved. Try again; your messages are still here.')}</p>}
     {replacement&&<div className="agent-history-confirm" role="alert"><strong>{t('This chat has unsaved messages or an unsent draft.')}</strong><p>{t('Save it first, or continue without saving. Your strategy settings will not change.')}</p><div className="uc-row"><button type="button" className="secondary-btn" data-action="discard-chat" disabled={waiting||!!historyBusy} onClick={()=>{const id=replacement.id;setReplacement(null);void replaceChat(id);}}>{t('Continue without saving')}</button><button type="button" className="text-btn" onClick={()=>setReplacement(null)}>{t('Cancel')}</button></div></div>}
     {historyOpen&&<div className="agent-history-list" role="region" aria-label={t('Chat history')}><header><strong>{t('Saved conversations')}</strong><button type="button" className="text-btn" disabled={!!historyBusy} onClick={()=>void listHistory(historyOffset)}>{t('Refresh')}</button></header>
      {!historyItems.length&&!historyBusy&&<p>{t('No saved conversations yet. Save a conversation to find it here later.')}</p>}
      {historyItems.map(item=><article key={item.id} className="agent-history-item"><div><strong>{item.title}</strong><small>{new Date(item.updatedAt).toLocaleString(locale)} · {item.messageCount} {t('messages')} · {item.provider==='openrouter'?'OpenRouter':'Local'}</small></div><button type="button" className="secondary-btn" data-conversation-id={item.id} data-action="open-chat" disabled={!!historyBusy||waiting} onClick={()=>requestReplacement(item.id)}>{t('Open conversation')}</button><button type="button" className="text-btn" aria-label={`${t('Delete conversation')}: ${item.title}`} disabled={!!historyBusy} onClick={()=>setDeleteId(item.id)}><Trash2 size={17}/></button>
       {deleteId===item.id&&<div className="agent-history-confirm"><p>{t('Delete this saved conversation? This cannot be undone.')}</p><button type="button" className="secondary-btn" disabled={!!historyBusy} data-action="delete-chat" onClick={()=>void deleteChat(item.id)}>{t('Delete conversation')}</button><button type="button" className="text-btn" onClick={()=>setDeleteId(null)}>{t('Cancel')}</button></div>}
      </article>)}
      <footer><button type="button" className="text-btn" disabled={!historyOffset||!!historyBusy} onClick={()=>void listHistory(Math.max(0,historyOffset-25))}>{t('Previous')}</button><span>{Math.floor(historyOffset/25)+1}</span><button type="button" className="text-btn" disabled={!historyMore||!!historyBusy} onClick={()=>void listHistory(historyOffset+25)}>{t('Next')}</button></footer>
     </div>}
    </section>
    <p className="agent-capabilities">{t('I can prepare settings, BUY/SELL rules and time filters, save a setup, and request a real MT5 backtest. I cannot change your access rights or enable live trading.')}</p>
    <div className="agent-provider"><label>{t('AI connection')}<select value={provider} onChange={e=>{request.current?.abort();voice.stopListening();voice.stopSpeech();setProvider(e.target.value as typeof provider);setConsent(false);setProposal(null);setUndo(null);setError('');}} disabled={waiting||props.pending||!!historyBusy}><option value="openrouter">OpenRouter / DeepSeek</option><option value="local">{t('Local Qwen / Ollama')}</option></select></label><span className="agent-model">{statusLoading?t('Checking the assistant connection…'):status?.providers[provider].model??t('Not configured')}<small>{t('Model connection is not verified until a request succeeds.')}</small></span><button type="button" className="text-btn" disabled={statusLoading||waiting||!props.credential||!props.active} onClick={()=>setStatusAttempt(n=>n+1)}>{t('Retry connection')}</button></div>
    {provider==='openrouter'?<label className="agent-consent"><input type="checkbox" checked={consent} disabled={waiting} onChange={e=>{setConsent(e.target.checked);setError('');}}/><span>{t('I allow my conversation, draft, strategy names and audit summary to be sent to OpenRouter and its model provider. Never paste passwords or account credentials.')}</span></label>:<p className="agent-privacy"><ShieldCheck size={17}/>{t('The model endpoint is local to the control-service computer. Chat is not stored in your browser. Credentials and account identifiers are not included in model context.')}</p>}
    {!props.credential||!props.active?<p className="guide-blocker">{t('Sign in with an active demo or subscription to talk to your private assistant.')}</p>:status&&!status.providers[provider].configured&&<p className="guide-blocker">{t('The assistant needs a configured model. The rest of your studio still works.')}</p>}
    <section className="agent-voice"><label className="agent-consent"><input type="checkbox" checked={voiceConsent} onChange={e=>setVoiceConsent(e.target.checked)}/><span>{t('Enable browser voice. Recognition may send microphone audio to the browser speech provider; some voices use an online service. The app does not record audio. Text remains available.')}</span></label><div className="agent-voice-actions"><button type="button" className={voice.listening?'agent-mic-active secondary-btn':'secondary-btn'} disabled={!enabled||!voiceConsent||!voice.canListen||waiting||props.pending} aria-pressed={voice.listening} onClick={()=>voice.listening?voice.stopListening(false):voice.listen()}>{voice.listening?<MicOff size={18}/>:<Mic size={18}/>} {t(voice.listening?'Finish dictation':'Speak to your guide')}</button><button type="button" className="text-btn" disabled={!voiceConsent||!voice.canSpeak||!messages.some(m=>m.role==='assistant')} onClick={()=>voice.speaking?voice.stopSpeech():voice.speak(messages.findLast(m=>m.role==='assistant')!.content)}>{voice.speaking?<VolumeX size={18}/>:<Volume2 size={18}/>} {t(voice.speaking?'Stop voice':'Read last answer')}</button></div><div className="agent-voice-options"><label><input type="checkbox" checked={readReplies} disabled={!voiceConsent||!voice.canSpeak} onChange={e=>{setReadReplies(e.target.checked);if(!e.target.checked)voice.stopSpeech();}}/>{t('Read replies aloud')}</label><label><input type="checkbox" checked={autoSend} disabled={!voiceConsent||!voice.canListen} onChange={e=>setAutoSend(e.target.checked)}/>{t('Send when dictation ends')}</label></div><p>{t('Check recognized numbers before applying a proposal. By default, dictation fills the message box for review.')}</p>{voiceConsent&&(!voice.canListen||!voice.canSpeak)&&<p className="guide-blocker">{t('This browser does not support all voice functions. Use text; voice availability is detected, not assumed.')}</p>}{voiceConsent&&voice.canSpeak&&!voice.voiceReady&&<p className="guide-blocker">{t('No voice for this language is installed. Use text or install a matching browser/OS voice.')}</p>}{voice.partial&&<output className="agent-transcript" aria-live="polite">{voice.partial}</output>}{voice.error&&<p className="uc-error" role="alert">{t(voice.error)}</p>}</section>
    <div ref={scroll} className="agent-conversation" role="log" aria-label={t('Conversation')} aria-live="polite">
     {!messages.length&&<div className="agent-intro"><Bot size={25}/><h3>{t('What would you like to try?')}</h3><p>{t('No jargon needed. Tell me the idea and I will ask only for the missing details. A suggestion is not a profit guarantee.')}</p><div className="agent-starters">{['I am new. Help me create my first backtest, one step at a time.','Explain the settings on my desk without changing them.','Explain my latest audit, including costs and missing data.'].map(s=><button key={s} className="secondary-btn" disabled={!enabled||waiting} onClick={()=>void ask(t(s))}>{t(s)}</button>)}</div></div>}
     {messages.map((m,i)=><article key={i} className="agent-message" data-role={m.role}><strong>{t(m.role==='user'?'You':'Studio guide')}</strong><p>{m.content}</p></article>)}
     {waiting&&<div className="agent-thinking" role="status"><LoaderCircle size={18}/><span>{t(props.pending?'Applying your confirmed plan…':'Reading your idea and checking available controls…')}<small>{elapsed}s · {failureText('AI_WAITING')}</small></span>{!props.pending&&<button type="button" className="text-btn" onClick={()=>{request.current?.abort();setError('AI_CANCELLED');}}>{t('Cancel')}</button>}</div>}
     {error&&<p role="alert" className="uc-error agent-chat-error" data-error={error}>{failureText(error)}</p>}
    </div>
    {proposal&&preview&&<section className="agent-proposal"><header><span className="eyebrow">{t('PROPOSED / NOT APPLIED')}</span><h3>{t('Your proposed strategy')}</h3></header>
      <p>{t('These values come from the validated draft. A proposal is not a backtest result. Unchanged settings are preserved.')}</p>
      <dl className="agent-strategy-overview">{preview.rows.map(row=><div key={row.label}><dt>{t(row.label)}</dt><dd>{t(row.value)}</dd></div>)}</dl>
      <details className="agent-full-settings"><summary>{t('All proposed settings, filters and rules')}</summary><div className="agent-change-table"><table><thead><tr><th>{t('Setting')}</th><th>{t('Proposed')}</th></tr></thead><tbody>{preview.settings.map(s=><tr key={`${s.kind}.${s.key}`}><th>{t(s.label)}<small><code>{s.kind}.{s.key}</code> / {t(s.group)}</small></th><td>{t(s.value)}</td></tr>)}</tbody></table></div>
        <h4>{t('Trade hours / broker time')}</h4><p>{t(proposal.plan.configuration.runtime.timeMatrixEnabled?'Use selected trade hours':'Time Matrix is OFF; saved masks are inactive.')}</p><dl className="agent-strategy-overview">{preview.dayHourMasks.map(day=><div key={day.day}><dt>{t(['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'][day.day])}</dt><dd>{day.hours.length===24?t('All hours'):day.hours.length?day.hours.map(h=>`${h}-${h+1}`).join(', '):t('No hours')}</dd></div>)}</dl>
        {preview.selectedPreset&&<><h4>{t('Selected preset rules')}</h4><p><strong>BUY: </strong><code>{preview.selectedPreset.buy}</code></p><p><strong>SELL: </strong><code>{preview.selectedPreset.sell}</code></p><dl className="agent-strategy-overview">{[['Cooldown (candles)',preview.selectedPreset.cooldown],['Maximum hold (candles)',preview.selectedPreset.maxBars],['Maximum hold (minutes)',preview.selectedPreset.maxMinutes]].map(([label,value])=><div key={label}><dt>{t(String(label))}</dt><dd>{String(value)}</dd></div>)}</dl><p><strong>EXIT BUY: </strong><code>{preview.selectedPreset.exitBuy??t('No rules')}</code></p><p><strong>EXIT SELL: </strong><code>{preview.selectedPreset.exitSell??t('No rules')}</code></p><p>{t('Zero holding limit means no limit from that rule. Cooldown is counted after a trade closes. Pip stop and R geometry remain as shown above.')}</p></>}
        {preview.builder&&<><h4>{t('Custom BUY / SELL rules')}</h4><p><strong>BUY: </strong><code>{builderExpression(preview.builder.buy)}</code></p><p><strong>SELL: </strong><code>{builderExpression(preview.builder.sell)}</code></p><p><strong>{t('Builder exit policy')}: </strong><code>{JSON.stringify({edge:preview.builder.edge,exitsEnabled:preview.builder.exitsEnabled,policy:preview.builder.policy,cooldown:preview.builder.cooldown,maxBars:preview.builder.maxBars,maxMinutes:preview.builder.maxMinutes,atrPeriod:preview.builder.atrPeriod,slAtr:preview.builder.slAtr,tpAtr:preview.builder.tpAtr})}</code></p><p><strong>EXIT BUY: </strong><code>{builderExpression(preview.builder.exitBuy)}</code></p><p><strong>EXIT SELL: </strong><code>{builderExpression(preview.builder.exitSell)}</code></p></>}
      </details>
      <details className="agent-full-settings"><summary>{t('Check what will change')} ({proposal.plan.changes.length})</summary><div className="agent-change-table"><table><thead><tr><th>{t('Setting')}</th><th>{t('Now')}</th><th>{t('Proposed')}</th></tr></thead><tbody>{proposal.plan.changes.map(c=>{const kind=c.field.startsWith('inputs.')?'inputs':c.field.startsWith('runtime.')?'runtime':null,key=c.field.replace(/^(inputs|runtime)\./,''),spec=kind?eaCatalog[proposal.plan.configuration.family][kind].find(s=>s.key===key):null;return <tr key={c.field}><th>{t(controlLabel(key))}{spec&&<HelpButton topic={{...controlHelp(spec),currentValue:c.after as string|number|boolean}}/>}</th><td>{display(c.before)}</td><td>{display(c.after)}</td></tr>;})}</tbody></table></div></details>
      <ol className="agent-action-list">{proposal.plan.calls.map((c,i)=><li key={i}><code>{c.name}</code><span>{String(c.arguments.reason)}</span></li>)}</ol>
      {stale&&<p role="alert" className="uc-error">{t(errors.STALE_PROPOSAL)}</p>}<p>{t('Apply changes only your draft unless this plan also requests an audit or save. Trading ON still needs the separate review and confirmation.')}</p>
      <div className="uc-row"><button type="button" className="primary-btn" disabled={stale||props.pending||waiting||!!historyBusy} onClick={()=>void confirm()}>{t(proposal.plan.runAudit?'Apply proposal & run backtest':'Apply proposal')}</button><button type="button" className="secondary-btn" onClick={()=>setProposal(null)}>{t('Discard proposal')}</button></div>
    </section>}
    {undo&&<button className="text-btn" disabled={undo.after!==snapshot||props.pending} onClick={()=>{props.onRestore(undo.configuration,undo.weeks);setUndo(null);setProposal(null);}}><Undo2 size={16}/>{t('Undo draft changes')}<small>{t('Does not cancel a job or revert a saved strategy.')}</small></button>}
    {props.summary&&<section className="agent-real-result"><span className="eyebrow">{t('REAL MT5 AUDIT')}</span><strong>{t(props.resultIsCurrent?'Matches the current desk':'Earlier result / draft or connection changed')}</strong><dl>{[['W / L',`${props.summary.wins} / ${props.summary.losses}`],['Net R',props.summary.netR.toFixed(3)],['Closed drawdown',`${props.summary.maxClosedDrawdownR.toFixed(3)}R`],['Win rate',props.summary.winRate===null?'--':`${props.summary.winRate.toFixed(1)}%`],['DATA',String(props.summary.data)],['OPEN',String(props.summary.open)]].map(([label,value])=><div key={label}><dt>{t(label)}</dt><dd>{value}</dd></div>)}</dl><p>{t(props.summary.coverageComplete?'Inspect the full trade table on your dashboard. Past performance is not a guarantee.':'Coverage is incomplete. Do not treat unknown outcomes as wins or losses.')}</p></section>}
    <form className="agent-compose" onSubmit={e=>{e.preventDefault();void ask();}}><label htmlFor="agent-message">{t('Tell your guide what you want')}</label><textarea id="agent-message" rows={3} maxLength={2000} value={input} onChange={e=>setInput(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.nativeEvent.isComposing){e.preventDefault();void ask();}}} placeholder={t('For example: explain risk first, then help me test an RSI rule.')} aria-describedby="agent-send-status" disabled={waiting||!!historyBusy}/><p id="agent-send-status" className="agent-send-status" role="status" data-blocker={blocker??undefined}>{blocker?failureText(blocker):t('Enter sends your message. Shift+Enter adds a new line.')}</p><div><small>{t('Drafts are reviewed. Backtests use MT5. Live trading stays your decision.')}</small><button type="submit" className="primary-btn" disabled={!enabled||waiting||!!historyBusy||!input.trim()}><Send size={17}/>{t('Send')}</button></div></form>
   </div>
  </ConsoleWindow>
 </>;
}
