import { ControlPlane } from './generated/control-plane.mjs';
import { SupabaseAuth } from './generated/supabase-auth.mjs';
import { controlHttp } from './generated/http.mjs';
import { PostgresStore } from './postgres-store.mjs';
import { hash } from '../crypto.mjs';
import { createStudioAgent } from '../studio-agent.mjs';
import { PUBLIC_STUDIO,PUBLIC_STUDIO_BASE_PATH } from '../api-location.mjs';

async function routingBody(request) {
  const reader=request.clone().body?.getReader();if(!reader)return {};
  const parts=[];let length=0;
  try {while(true){const {done,value}=await reader.read();if(done)break;
    length+=value.length;if(length>16384)throw new Error('ROUTING_BODY_TOO_LARGE');parts.push(value);}}
  finally {void reader.cancel().catch(()=>{});}
  const bytes=new Uint8Array(length);let at=0;for(const part of parts){bytes.set(part,at);at+=part.length;}
  return JSON.parse(new TextDecoder().decode(bytes));
}

export async function cloudRequest(tx,request,path,configuration,artifacts,remoteAddress) {
  const db=new PostgresStore(tx);
  let owner;
  const authorization=request.headers.get('authorization');
  const raw=authorization?.startsWith('Bearer ')?authorization.slice(7):null;
  if(raw)owner=(await db.get('SELECT account_id FROM sessions WHERE token_hash=?',hash(raw)))?.account_id;
  const proof=request.headers.get('x-stratum-proof');
  if(proof&&proof.length<=2048){
    try{const value=JSON.parse(Buffer.from(proof,'base64url').toString());
      owner=(await db.get('SELECT account_id FROM installations WHERE id=?',value.installationId))?.account_id;}catch{/* The canonical handler rejects malformed proofs. */}
  }
  if(!owner&&['/v1/ea/enroll','/v1/auth/login','/v1/auth/register'].includes(path)){
    try{const body=await routingBody(request);
      if(path==='/v1/ea/enroll'&&typeof body.enrollmentToken==='string')owner=(await db.get('SELECT account_id FROM enrollment_tickets WHERE token_hash=?',hash(body.enrollmentToken)))?.account_id;
      else if(typeof body.email==='string')owner=(await db.get('SELECT account_id FROM supabase_accounts WHERE email=?',body.email.toLowerCase()))?.account_id??'email:'+body.email.toLowerCase();
    }catch{/* Malformed requests cannot grant authority. */}
  }
  // Serialize all browser/device mutations for the same account across Edge isolates.
  if(owner)await tx`SELECT pg_advisory_xact_lock(hashtextextended(${owner},0))`;
  const plane=new ControlPlane({db,signingKey:configuration.signingKey,eaSigningKey:configuration.eaSigningKey});
  plane.apiUrl=configuration.apiUrl;plane.studioUrl=configuration.studioUrl;
  plane.artifacts=artifacts;plane.helperFactory=async()=>artifacts?.helper;
  const auth=new SupabaseAuth(plane,{url:configuration.supabaseUrl,publishableKey:configuration.publishableKey,
    encryptionKey:Buffer.from(configuration.encryptionKey,'base64'),studioOrigin:configuration.studioUrl,
    studioBasePath:configuration.studioUrl===PUBLIC_STUDIO?PUBLIC_STUDIO_BASE_PATH:''});
  const agent=createStudioAgent();
  return controlHttp(plane,{origins:[configuration.studioUrl],auth,agent}).fetch(request,path,remoteAddress);
}
