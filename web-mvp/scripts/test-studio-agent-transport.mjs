import assert from 'node:assert/strict';
import {test} from 'node:test';
import {EventEmitter} from 'node:events';
import {Readable} from 'node:stream';
import {createOpenRouterTransport} from '../control-service/studio-agent-transport.mjs';

const endpoint='https://openrouter.ai/api/v1/chat/completions';
function fixture({backpressure=false,status=200,abort=null}={}){
 const chunks=[];let options,started=false,fragment,connections=0;
 const send=createOpenRouterTransport({request:(url,init,onResponse)=>{
  connections++;assert.equal(url,endpoint);options=init;
  const req=new EventEmitter(),socket=new EventEmitter();
  socket.setMaxSendFragment=size=>{fragment=size;return true;};
  req.write=chunk=>{assert.equal(started,true,'no upload before verified handshake');chunks.push(Buffer.from(chunk));if(backpressure){setImmediate(()=>req.emit('drain'));return false;}return true;};
  req.destroy=error=>{setImmediate(()=>req.emit('error',error));return req;};
  req.end=()=>{
   const res=Readable.from([Buffer.from('{"ok":true}')]);res.statusCode=status;res.headers={'content-type':'application/json'};onResponse(res);
  };
  setImmediate(()=>{
   req.emit('socket',socket);
   if(abort){abort.abort();req.destroy(abort.signal.reason);return;}
   started=true;socket.emit('secureConnect');
  });
  return req;
 }});
 return {send,chunks,get options(){return options;},get fragment(){return fragment;},get connections(){return connections;}};
}

test('fixed provider transport keeps TLS verification and exact UTF-8 bytes with bounded records/backpressure',async()=>{
 const f=fixture({backpressure:true}),controller=new AbortController();
 const body=JSON.stringify({test:'\u00fc\ud83e\udd16'.repeat(12000)});
 const response=await f.send(endpoint,{method:'POST',body,headers:{'Content-Type':'application/json'},signal:controller.signal});
 assert.deepEqual(await response.json(),{ok:true});assert.ok(f.chunks.length>10);
 assert.ok(f.chunks.every(c=>c.byteLength<=4096));assert.equal(Buffer.concat(f.chunks).toString('utf8'),body);
 assert.equal(f.fragment,4096);assert.equal(f.options.rejectUnauthorized,true);assert.equal(f.options.signal,controller.signal);
 assert.equal(f.options.agent.options.keepAlive,false);assert.equal(f.options.agent.maxCachedSessions,0);
 assert.equal(f.options.maxVersion,undefined);assert.equal(f.options.checkServerIdentity,undefined);
});

test('provider transport cannot address arbitrary URLs or change method',async()=>{
 const f=fixture();
 for(const [url,method] of [['http://openrouter.ai/api/v1/chat/completions','POST'],['https://evil.example/','POST'],[endpoint,'GET']]){
  await assert.rejects(f.send(url,{method,body:'{}'}),/AI_TRANSPORT_TARGET_INVALID/);
 }
 assert.equal(f.connections,0);
});

test('HTTP failures are returned without redirect following or manufactured success',async()=>{
 for(const status of [302,401,402,429,503]){
  const f=fixture({status});const response=await f.send(endpoint,{method:'POST',body:'{}'});
  assert.equal(response.status,status);assert.equal(response.ok,false);assert.equal(f.connections,1);await response.body.cancel();
 }
});

test('cancellation before handshake cannot start upload',async()=>{
 const c=new AbortController(),f=fixture({abort:c});
 await assert.rejects(f.send(endpoint,{method:'POST',body:'private draft',signal:c.signal}),e=>e.name==='AbortError');
 assert.equal(f.chunks.length,0);assert.equal(f.connections,1);
});
