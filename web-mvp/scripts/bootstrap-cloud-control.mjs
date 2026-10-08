import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash,randomBytes } from 'node:crypto';
import { request as httpsRequest } from 'node:https';
import { setTimeout as delay } from 'node:timers/promises';
import { once } from 'node:events';
import { signed } from '../control-service/crypto.mjs';
import { verifiedArtifacts,companion } from '../control-service/delivery.mjs';
import { CLOUD_CONTROL,PUBLIC_STUDIO } from '../control-service/api-location.mjs';

const state=resolve(import.meta.dirname,'../control-service/.state');
const signingKey=JSON.parse(readFileSync(resolve(state,'signing-key.json'),'utf8'));
const eaSigningKey=JSON.parse(readFileSync(resolve(state,'ea-signing-key.json'),'utf8'));
const binaries=verifiedArtifacts({signingKey,eaSigningKey}),helper=await companion();
const artifacts={'UniversalConnectionEA.ex5':binaries.binary,'MaCrossOrderFlowWorker.ex5':binaries.worker,'connection.mjs':helper};
const digests=Object.fromEntries(Object.entries(artifacts).map(([k,b])=>[k,createHash('sha256').update(b).digest('hex')]));
const configuration={signingKey,eaSigningKey,encryptionKey:randomBytes(32).toString('base64'),
 apiUrl:CLOUD_CONTROL,studioUrl:PUBLIC_STUDIO,supabaseUrl:'https://uvzhrrqzzdjqtmydpvwo.supabase.co',
 publishableKey:'sb_publishable_4yCgr706ZuZL8N7_Wci2HA_DoV--QRE',artifacts:digests};
const payload=()=>({apiUrl:CLOUD_CONTROL,issuedAt:Date.now(),expiresAt:Date.now()+120000});
async function requestOnce(path,options){
 const bytes=options.body===undefined?null:Buffer.from(options.body);
 return new Promise((resolve,reject)=>{
  const req=httpsRequest(CLOUD_CONTROL+path,{agent:false,method:options.method??'GET',headers:{...options.headers,...(bytes?{'Content-Length':bytes.length}:{})},signal:AbortSignal.timeout(90000),rejectUnauthorized:true},res=>{
   const chunks=[];res.on('data',b=>chunks.push(b));res.on('error',reject);res.on('end',()=>{
    try{const data=JSON.parse(Buffer.concat(chunks).toString());if(res.statusCode<200||res.statusCode>=300)throw new Error('CLOUD_DEPLOYMENT: '+(data.error??res.statusCode));resolve(data);}catch(e){reject(e);}
   });
  });
  req.on('error',reject);req.once('socket',socket=>{
   socket.setMaxSendFragment(4096);socket.once('secureConnect',()=>void(async()=>{
    if(bytes)for(let i=0;i<bytes.length;i+=16384){if(!req.write(bytes.subarray(i,i+16384)))await once(req,'drain');await delay(5);}
    req.end();
   })().catch(reject));
  });
 });
}
async function request(path,options){
 for(let attempt=0;attempt<4;attempt++){
  try{return await requestOnce(path,options);}catch(error){
   if(attempt===3||error.message.startsWith('CLOUD_DEPLOYMENT:'))throw error;
   await delay(1000*(attempt+1));
  }
 }
}
if(!process.argv.includes('--artifacts-only')){
 const envelope=signed({...payload(),kind:'bootstrap',configuration},signingKey.privateKey);
 await request('/operator/bootstrap',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(envelope)});
 console.log('Owner-signed cloud configuration installed. Private values are not logged.');
}
for(const [name,bytes]of Object.entries(artifacts)){
 const count=Math.ceil(bytes.length/65536);
 const start=name==='UniversalConnectionEA.ex5'?Math.max(0,Number(process.env.STRATUM_UPLOAD_START??0)):0;
 for(let index=start;index<count;index++){
  const chunk=bytes.subarray(index*65536,(index+1)*65536);
  const envelope=signed({...payload(),kind:'artifact_chunk',name,sha256:digests[name],index,count,chunkHash:createHash('sha256').update(chunk).digest('hex')},signingKey.privateKey);
  await request('/operator/artifact/'+name,{method:'POST',headers:{'Content-Type':'application/octet-stream','X-Stratum-Proof':Buffer.from(JSON.stringify(envelope)).toString('base64url')},body:chunk});
  if(index%16===0)console.log('Uploading '+name+': '+(index+1)+'/'+count);
 }
 const envelope=signed({...payload(),kind:'artifact_complete',name,sha256:digests[name],count},signingKey.privateKey);
 const result=await request('/operator/artifact/'+name,{method:'POST',headers:{'Content-Type':'application/octet-stream','X-Stratum-Proof':Buffer.from(JSON.stringify(envelope)).toString('base64url')},body:Buffer.alloc(0)});
 console.log('Verified private artifact uploaded: '+result.name);
}
console.log(JSON.stringify(await request('/health',{})));
