"use client";
import {useCallback,useEffect,useRef,useState} from 'react';
import {speechLocale,selectVoice,speechText} from '@/lib/voice-utils';
import type {Locale} from '@/lib/messages';

type RecognitionEvent={resultIndex:number;results:ArrayLike<ArrayLike<{transcript:string;confidence:number}>&{isFinal:boolean}>};
type Recognition={lang:string;continuous:boolean;interimResults:boolean;onresult:((event:RecognitionEvent)=>void)|null;onerror:((event:{error:string})=>void)|null;onend:(()=>void)|null;start:()=>void;stop:()=>void;abort:()=>void};
type VoiceWindow=Window&{SpeechRecognition?:new()=>Recognition;webkitSpeechRecognition?:new()=>Recognition};

// Only browser speech services: no microphone/voice endpoint is added to the control authority.
export function useAgentVoice({locale,active,onTranscript}:{locale:Locale;active:boolean;onTranscript:(text:string)=>void}){
 const [canListen,setCanListen]=useState(false),[canSpeak,setCanSpeak]=useState(false),[listening,setListening]=useState(false),[speaking,setSpeaking]=useState(false),[partial,setPartial]=useState(''),[error,setError]=useState(''),[pulse,setPulse]=useState(0),[voiceReady,setVoiceReady]=useState(false);
 const recognition=useRef<Recognition|null>(null),utterance=useRef<SpeechSynthesisUtterance|null>(null),decay=useRef<ReturnType<typeof setTimeout>|null>(null),callback=useRef(onTranscript),alive=useRef(true),speechEpoch=useRef(0),activeRef=useRef(active),localeRef=useRef(locale);
 callback.current=onTranscript;
 activeRef.current=active;localeRef.current=locale;
 const stopSpeech=useCallback(()=>{speechEpoch.current++;if(utterance.current){utterance.current.onstart=null;utterance.current.onend=null;utterance.current.onerror=null;utterance.current.onboundary=null;utterance.current=null;window.speechSynthesis?.cancel();}if(decay.current)clearTimeout(decay.current);setSpeaking(false);setPulse(0);},[]);
 const stopListening=useCallback((discard=true)=>{const instance=recognition.current;if(instance){if(discard){instance.onresult=null;instance.onend=null;instance.onerror=null;instance.abort();recognition.current=null;setPartial('');}else instance.stop();}setListening(false);},[]);
 useEffect(()=>{
  alive.current=true;const w=window as VoiceWindow;setCanListen(!!(w.SpeechRecognition||w.webkitSpeechRecognition));setCanSpeak('speechSynthesis' in w&&'SpeechSynthesisUtterance' in w);
  const voices=()=>setVoiceReady(!!selectVoice(window.speechSynthesis?.getVoices()??[],speechLocale[locale]));voices();window.speechSynthesis?.addEventListener('voiceschanged',voices);
  const hidden=()=>{if(document.hidden){stopListening();stopSpeech();}};document.addEventListener('visibilitychange',hidden);
  return()=>{alive.current=false;window.speechSynthesis?.removeEventListener('voiceschanged',voices);document.removeEventListener('visibilitychange',hidden);stopListening();stopSpeech();};
 },[locale,stopListening,stopSpeech]);
 useEffect(()=>{if(!active){stopListening();stopSpeech();}},[active,stopListening,stopSpeech]);
 function listen(){
  if(!activeRef.current||!canListen||recognition.current)return;
  stopSpeech();setError('');setPartial('');const Constructor=(window as VoiceWindow).SpeechRecognition??(window as VoiceWindow).webkitSpeechRecognition;
  if(!Constructor)return;let instance:Recognition;
  try{instance=new Constructor();}catch{setError('Microphone could not start. Try again or use text.');return;}
  recognition.current=instance;instance.lang=speechLocale[localeRef.current];instance.continuous=false;instance.interimResults=true;
  // Results are cumulative. Replace by index, rather than appending a repeated final segment.
  const finalSegments=new Map<number,string>();let failed=false;
  const finalText=()=>[...finalSegments.entries()].sort(([a],[b])=>a-b).map(([,text])=>text).join(' ').trim();
  instance.onresult=event=>{if(recognition.current!==instance||!alive.current||!activeRef.current||failed)return;let interim='';for(let i=event.resultIndex;i<event.results.length;i++){const row=event.results[i];if(row.isFinal)finalSegments.set(i,row[0].transcript);else interim+=row[0].transcript+' ';}setPartial((finalText()+' '+interim).trim().slice(0,2000));};
  instance.onerror=e=>{if(recognition.current!==instance)return;failed=true;finalSegments.clear();setPartial('');setListening(false);setError(e.error==='not-allowed'?'Microphone permission was denied. Use text or enable microphone access in your browser.':e.error==='no-speech'?'No speech was detected. Try again or use text.':'Speech recognition failed. No spoken request was sent. Use text and check browser support.');};
  instance.onend=()=>{if(recognition.current!==instance||!alive.current)return;recognition.current=null;setListening(false);setPartial('');const text=finalText();if(activeRef.current&&!failed&&text)callback.current(text.slice(0,2000));};
  try{instance.start();setListening(true);}catch{instance.onresult=null;instance.onend=null;instance.onerror=null;recognition.current=null;setError('Microphone could not start. Try again or use text.');}
 }
 function speak(text:string){
  if(!activeRef.current||!canSpeak)return;stopSpeech();stopListening();setError('');
  const voice=selectVoice(window.speechSynthesis.getVoices(),speechLocale[localeRef.current]);if(!voice){setError('No voice for this language is installed. Use text or install a matching browser/OS voice.');return;}
  const content=speechText(text);if(!content)return;
  const epoch=speechEpoch.current;let spoken:SpeechSynthesisUtterance;
  try{spoken=new SpeechSynthesisUtterance(content);}catch{setError('Voice playback failed. The full answer is still available as text.');return;}
  spoken.lang=speechLocale[localeRef.current];spoken.voice=voice;spoken.rate=1;spoken.pitch=1.05;utterance.current=spoken;
  const current=()=>alive.current&&speechEpoch.current===epoch&&utterance.current===spoken;
  spoken.onstart=()=>{if(current()){setSpeaking(true);setPulse(.5);}};
  spoken.onboundary=()=>{if(!current())return;setPulse(1);if(decay.current)clearTimeout(decay.current);decay.current=setTimeout(()=>{if(current())setPulse(.35);},130);};
  spoken.onend=()=>{if(current()){setSpeaking(false);setPulse(0);utterance.current=null;}};
  spoken.onerror=()=>{if(current()){setSpeaking(false);setPulse(0);utterance.current=null;setError('Voice playback failed. The full answer is still available as text.');}};
  try{window.speechSynthesis.speak(spoken);}catch{stopSpeech();setError('Voice playback failed. The full answer is still available as text.');}
 }
 return {canListen,canSpeak,voiceReady,listening,speaking,partial,error,pulse,listen,speak,stopSpeech,stopListening};
}
