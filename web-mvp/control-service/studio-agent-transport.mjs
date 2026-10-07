import {Agent,request as httpsRequest} from 'node:https';
import {Readable} from 'node:stream';
import {once} from 'node:events';
import {setTimeout as delay} from 'node:timers/promises';

const endpoint='https://openrouter.ai/api/v1/chat/completions';

export function createOpenRouterTransport({request=httpsRequest}={}){
 return (url,init)=>new Promise((resolve,reject)=>{
  if(url!==endpoint||init.method!=='POST'||typeof init.body!=='string'){
   reject(new Error('AI_TRANSPORT_TARGET_INVALID'));return;
  }
  const agent=new Agent({keepAlive:false,maxCachedSessions:0});
  let incoming;
  const failed=error=>{incoming?.destroy(error);agent.destroy();reject(error);};
  try{
   const req=request(endpoint,{agent,method:'POST',headers:init.headers,signal:init.signal,rejectUnauthorized:true},res=>{
    incoming=res;res.once('close',()=>agent.destroy());
    try{
     const headers=new Headers();
     for(const [key,value] of Object.entries(res.headers))if(value!==undefined)headers.set(key,Array.isArray(value)?value.join(','):value);
     resolve(new Response(Readable.toWeb(res),{status:res.statusCode,headers}));
    }catch(error){failed(error);}
   });
   req.once('error',failed);
   req.once('socket',socket=>{
    // Keep TLS verification; bound and pace the pilot's large context upload.
    // No fallback endpoint, plaintext transport or certificate bypass is allowed.
    if(!socket.setMaxSendFragment(4096)){req.destroy(new Error('AI_TLS_FRAGMENT_FAILED'));return;}
    socket.once('secureConnect',()=>void(async()=>{
     const bytes=Buffer.from(init.body);
     for(let offset=0;offset<bytes.length;offset+=4096){
      if(req.destroyed)return;
      init.signal?.throwIfAborted();
      if(!req.write(bytes.subarray(offset,offset+4096)))await once(req,'drain',{signal:init.signal});
      await delay(1,undefined,{signal:init.signal});
     }
     if(!req.destroyed)req.end();
    })().catch(error=>req.destroy(error)));
   });
  }catch(error){failed(error);}
 });
}

const openRouter=createOpenRouterTransport();
export const studioAgentFetch=(url,init)=>url===endpoint?openRouter(url,init):fetch(url,init);
