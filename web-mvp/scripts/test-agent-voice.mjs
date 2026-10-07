import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import ts from 'typescript';
import * as utils from '../lib/voice-utils.ts';
import {tutorPose} from '../lib/tutor-behavior.ts';

// A deterministic hook/speech-service harness, NOT a real browser microphone test.
function harness(){
 let cursor=0;const slots=[],effects=[],transcripts=[],microphones=[],spoken=[],events=new Map(),timers=new Map(),faults=Object.create(null);let timer=0;
 const same=(a,b)=>a&&b&&a.length===b.length&&a.every((v,i)=>Object.is(v,b[i]));
 const react={useState(initial){const i=cursor++;slots[i]??={value:typeof initial==='function'?initial():initial};return [slots[i].value,v=>slots[i].value=typeof v==='function'?v(slots[i].value):v];},useRef(value){const i=cursor++;slots[i]??={current:value};return slots[i];},useCallback(callback,deps){const i=cursor++;if(!slots[i]||!same(slots[i].deps,deps))slots[i]={callback,deps};return slots[i].callback;},useEffect(callback,deps){const i=cursor++;if(!slots[i]||!same(slots[i].deps,deps)){const old=slots[i];slots[i]={deps,cleanup:old?.cleanup};effects.push(()=>{old?.cleanup?.();slots[i].cleanup=callback();});}}};
 class Recognition{constructor(){if(faults.constructor)throw Error('unavailable');microphones.push(this);}start(){if(faults.start)throw Error('unavailable');this.started=true;}abort(){this.aborted=true;}stop(){this.onend?.();}}
 class Utterance{constructor(text){this.text=text;}}
 const voices=[{lang:'tr-TR',localService:true},{lang:'en-US',localService:true},{lang:'de-DE',localService:true}];
 const synth={getVoices:()=>voices,addEventListener(){},removeEventListener(){},speak:u=>{if(faults.speak)throw Error('unavailable');spoken.push(u);},cancel:()=>{synth.cancelled=true;}};
 const window={SpeechRecognition:Recognition,SpeechSynthesisUtterance:Utterance,speechSynthesis:synth};
 const document={hidden:false,addEventListener:(name,fn)=>events.set(name,fn),removeEventListener:name=>events.delete(name)};
 const module={exports:{}};
 const code=ts.transpileModule(readFileSync(new URL('../components/use-agent-voice.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
 runInNewContext(code,{module,exports:module.exports,require:id=>id==='react'?react:id==='@/lib/voice-utils'?utils:assert.fail(id),window,document,SpeechSynthesisUtterance:Utterance,setTimeout:fn=>{timers.set(++timer,fn);return timer;},clearTimeout:id=>timers.delete(id)});
 const render=(active=true,locale='tr')=>{cursor=0;const result=module.exports.useAgentVoice({active,locale,onTranscript:text=>transcripts.push(text)});effects.splice(0).forEach(fn=>fn());return result;};
 const dispose=()=>{for(const s of slots)s?.cleanup?.();};
 return {render,dispose,microphones,spoken,transcripts,voices,document,events,window,synth,faults};
}
test('voice text cleanup is bounded, preserves numbers and removes code/URLs',()=>{
 assert.equal(utils.speechText('**Risk** 0.5% ```ignore code``` https://example.test'),'Risk 0.5%');assert.equal(utils.speechText('a'.repeat(10000)).length,3000);
});
test('matching language is required and local OS voices are preferred',()=>{
 const a={lang:'tr-TR',localService:false},b={lang:'tr-TR',localService:true},c={lang:'en-US',localService:true};assert.equal(utils.selectVoice([a,c,b],'tr-TR'),b);assert.equal(utils.selectVoice([a,c],'de-DE'),undefined);
});
test('no microphone or synthesis starts on mount; inactive consent blocks even direct calls',()=>{
 const h=harness();h.render(false);const v=h.render(false);v.listen();v.speak('Test');assert.equal(h.microphones.length,0);assert.equal(h.spoken.length,0);h.dispose();
});
test('interim speech stays local to the draft; only final transcript is delivered',()=>{
 const h=harness();h.render();let v=h.render();v.listen();const mic=h.microphones[0];assert.ok(mic.started);assert.equal(mic.lang,'tr-TR');assert.equal(mic.continuous,false);
 mic.onresult({resultIndex:0,results:[Object.assign([{transcript:'risk one',confidence:.7}],{isFinal:false})]});assert.equal(h.transcripts.length,0);assert.equal(h.render().partial,'risk one');
 mic.onresult({resultIndex:0,results:[Object.assign([{transcript:'risk 1 percent',confidence:.9}],{isFinal:true})]});mic.onend();assert.deepEqual(h.transcripts,['risk 1 percent']);assert.equal(h.render().listening,false);h.dispose();
});
test('denied/error recognition does not send the partial request',()=>{
 const h=harness();h.render();h.render().listen();const mic=h.microphones[0];mic.onresult({resultIndex:0,results:[Object.assign([{transcript:'risk 1',confidence:.9}],{isFinal:true})]});mic.onerror({error:'not-allowed'});mic.onend();assert.equal(h.transcripts.length,0);assert.ok(h.render().error.includes('permission'));h.dispose();
});
test('robot speaking and boundary pulse follow actual synthesis events, not pending requests',()=>{
 const h=harness();h.render();h.render().speak('Merhaba');assert.equal(h.render().speaking,false);const u=h.spoken[0];assert.equal(u.voice.lang,'tr-TR');u.onstart();assert.equal(h.render().speaking,true);u.onboundary();assert.equal(h.render().pulse,1);u.onend();assert.equal(h.render().speaking,false);assert.equal(h.render().pulse,0);h.dispose();
 const closed=tutorPose(1,'explaining',true,0,false,0),talking=tutorPose(1,'explaining',true,0,true,1);assert.ok(talking.mouthHeight>closed.mouthHeight);assert.equal(tutorPose(1,'idle',true,0,false,0).mouthHeight,1);
});
test('hiding the page or revoking consent stops owned speech and microphone',()=>{
 const h=harness();h.render();h.render().listen();h.document.hidden=true;h.events.get('visibilitychange')();assert.ok(h.microphones[0].aborted);assert.equal(h.render().listening,false);
 h.document.hidden=false;h.render().speak('Hi');h.spoken[0].onstart();assert.equal(h.render().speaking,true);h.render(false);assert.equal(h.render(false).speaking,false);assert.ok(h.synth.cancelled);h.dispose();
});
test('stale async speech callbacks cannot restart voice after chat closes',()=>{
 const h=harness();h.render();const old=h.render();old.speak('Hi');const callback=h.spoken[0].onstart;h.render(false);old.speak('No');callback();assert.equal(h.spoken.length,1);assert.equal(h.render(false).speaking,false);h.dispose();
});
test('missing language voice is surfaced; no accidental wrong-language fallback',()=>{
 const h=harness();h.voices.splice(0,h.voices.length,{lang:'en-US',localService:true});h.render();h.render().speak('Merhaba');assert.equal(h.spoken.length,0);assert.ok(h.render().error.includes('No voice'));h.dispose();
});

test('repeated cumulative final results are not duplicated and retain segment order',()=>{
 const h=harness();h.render();h.render().listen();const mic=h.microphones[0];
 const a=Object.assign([{transcript:'risk one percent',confidence:.9}],{isFinal:true}),b=Object.assign([{transcript:'and stop ten pips',confidence:.9}],{isFinal:true});
 mic.onresult({resultIndex:0,results:[a]});mic.onresult({resultIndex:0,results:[a,b]});mic.onresult({resultIndex:1,results:[a,b]});mic.onend();
 assert.deepEqual(h.transcripts,['risk one percent and stop ten pips']);h.dispose();
});

test('changing language aborts recording/playback and selects the new voice',()=>{
 const h=harness();h.render();h.render().listen();h.render(true,'de');assert.ok(h.microphones[0].aborted);assert.equal(h.transcripts.length,0);
 h.render(true,'de').speak('Hallo');const u=h.spoken[0];assert.equal(u.lang,'de-DE');u.onstart();h.render(true,'en');assert.ok(h.synth.cancelled);assert.equal(h.render(true,'en').speaking,false);h.dispose();
});

test('unsupported browsers retain text fallback without creating speech activity',()=>{
 const h=harness();delete h.window.SpeechRecognition;delete h.window.SpeechSynthesisUtterance;h.render();const v=h.render();assert.equal(v.canListen,false);assert.equal(v.canSpeak,false);v.listen();v.speak('No');assert.equal(h.microphones.length,0);assert.equal(h.spoken.length,0);h.dispose();
});

test('synchronous microphone/synthesis failures become visible errors, not stuck speech states',()=>{
 for(const fault of ['constructor','start']){const h=harness();h.faults[fault]=true;h.render();h.render().listen();assert.equal(h.render().listening,false);assert.ok(h.render().error.includes('could not start'));h.dispose();}
 const h=harness();h.faults.speak=true;h.render();h.render().speak('Hi');assert.equal(h.render().speaking,false);assert.ok(h.render().error.includes('playback failed'));h.dispose();
});

test('finished dictation is delivered once; discard/unmount never auto-send',()=>{
 const h=harness();h.render();h.render().listen();let mic=h.microphones[0];mic.onresult({resultIndex:0,results:[Object.assign([{transcript:'one',confidence:.9}],{isFinal:true})]});h.render().stopListening(false);assert.deepEqual(h.transcripts,['one']);
 h.render().listen();mic=h.microphones[1];mic.onresult({resultIndex:0,results:[Object.assign([{transcript:'two',confidence:.9}],{isFinal:true})]});const ended=mic.onend;h.dispose();ended();assert.deepEqual(h.transcripts,['one']);assert.ok(mic.aborted);
});
