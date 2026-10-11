import assert from 'node:assert/strict';
import { test } from 'node:test';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { ControlPlane } from '../control-service/control-plane.mjs';
import { SupabaseAuth } from '../control-service/supabase-auth.mjs';
import { controlHttp } from '../control-service/http.mjs';
import { id,keyPair,signed,hash,makeProof } from '../control-service/crypto.mjs';
import { defaultConfiguration } from '../lib/universal-contract.ts';
import { authReturn } from '../lib/auth-return.ts';

const DAY=86400000;
function fixture(){
 let at=Date.now(),calls=0,refreshes=0,offline=false,revoked=false,confirmation=false,admin=false,shared=defaultConfiguration('orb');
 const account=id(),sid=id(),jwt='verified-provider-jwt-not-a-browser-secret',refresh='private-refresh-token-never-in-ea';
 const state={accountId:account,sessionId:sid,email:'demo@example.com',displayName:'Cem Quant',disabled:false,
  accessActive:true,accessMode:'demo',paidUntil:0,serverNow:at,trial:{startsAt:at,expiresAt:at+30*DAY}};
 const rows=[],requests=[],chats=new Map();
 const p=new ControlPlane({now:()=>at});
 const fetcher=async(url,options)=>{
  calls++;requests.push({url,options});if(offline)throw new Error('offline');const path=new URL(url).pathname,body=options.body?JSON.parse(options.body):{};
  const reply=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json'}});
  if(path==='/auth/v1/signup')return reply(confirmation?{user:{id:account}}:{access_token:jwt,refresh_token:refresh,expires_at:Math.floor(at/1000)+3600});
  if(path==='/auth/v1/token'){
   if(new URL(url).searchParams.get('grant_type')==='refresh_token')refreshes++;
   else if(body.password!=='a-long-private-password')return reply({error_code:'invalid_credentials'},400);
   return reply({access_token:jwt,refresh_token:refresh,expires_at:Math.floor(at/1000)+3600});
  }
  if(path==='/auth/v1/logout'){revoked=true;return new Response(null,{status:204});}
  if(options.headers.Authorization!=='Bearer '+jwt)return reply({error:'bad JWT'},401);
  if(path==='/rest/v1/rpc/stratum_access_state')return revoked?reply({message:'STRATUM_SESSION_INVALID'},401):reply({...state,serverNow:at});
  if(path==='/rest/v1/rpc/stratum_admin_status')return reply({isAdmin:admin});
  if(path.startsWith('/rest/v1/rpc/stratum_admin_'))return admin?reply({items:[],total:0,hasMore:false,enabled:body.p_enabled,revision:(body.p_revision??0)+1}):reply({message:'STRATUM_ADMIN_REQUIRED'},403);
  if(path==='/rest/v1/rpc/stratum_available_strategies')return reply({items:[]});
  if(path==='/rest/v1/rpc/stratum_load_strategy')return reply({id:body.p_strategy_id,symbol:'USDJPYm',sourceHash:'a'.repeat(64),configuration:shared});
  if(path==='/rest/v1/stratum_strategies'){
   if(options.method==='POST'){assert.equal(body.account_id,account);rows.splice(0,rows.length,{configuration:body.configuration});return new Response(null,{status:204});}
   return reply(rows);
  }
  if(path==='/rest/v1/stratum_conversations'){
   const query=new URL(url).searchParams;
   if(options.method==='POST'){
    assert.equal(body.account_id,account);const old=chats.get(body.id),row={...body,message_count:body.messages.length,created_at:old?.created_at??new Date(at).toISOString(),updated_at:new Date(at).toISOString()};
    assert.equal(options.headers.Prefer,'resolution=merge-duplicates,return=representation');chats.set(body.id,row);return reply([row]);
   }
   assert.equal(query.get('account_id'),'eq.'+account);
   const rowId=query.get('id')?.slice(3);
   if(options.method==='DELETE'){const row=chats.get(rowId);chats.delete(rowId);return reply(row?[{id:row.id}]:[]);}
   if(rowId)return reply(chats.has(rowId)?[chats.get(rowId)]:[]);
   assert.equal(query.get('limit'),'26');assert.ok(!query.get('select').includes('messages'));
   return reply([...chats.values()].sort((a,b)=>b.updated_at.localeCompare(a.updated_at)).slice(Number(query.get('offset')),Number(query.get('offset'))+26));
  }
  throw new Error('unexpected request '+path);
 };
 const auth=new SupabaseAuth(p,{url:'https://testproject.supabase.co',publishableKey:'sb_publishable_test',encryptionKey:randomBytes(32),fetcher});
 const login=()=>auth.login({email:state.email,password:'a-long-private-password'});
 return {p,auth,state,account,jwt,refresh,login,requests,advance:ms=>at+=ms,calls:()=>calls,refreshes:()=>refreshes,now:()=>at,admin:v=>admin=v,shared:v=>shared=v,
  offline:v=>offline=v,revoke:()=>revoked=true,confirmation:v=>confirmation=v};
}
const rejects=(fn,code)=>assert.rejects(fn,e=>e.code===code);

test('admin/library RPCs use the verified owner JWT, reject forged arguments, and validate loaded settings',async()=>{
 const f=fixture(),s=await f.login();
 try{
  assert.deepEqual(await f.auth.adminStatus(s.accessToken),{isAdmin:false});
  await rejects(()=>f.auth.adminUsers(s.accessToken,{query:'',offset:0}),'ADMIN_REQUIRED');
  const input={userId:id(),strategyId:'orb_test',enabled:true,revision:0};
  await rejects(()=>f.auth.adminGrant(s.accessToken,{...input,isAdmin:true}),'INVALID_REQUEST');
  await rejects(()=>f.auth.adminCatalog(s.accessToken,{userId:input.userId,family:'orb',query:'',offset:-1}),'INVALID_REQUEST');
  f.admin(true);assert.equal((await f.auth.adminStatus(s.accessToken)).isAdmin,true);
  assert.equal((await f.auth.adminGrant(s.accessToken,input)).revision,1);
  assert.deepEqual(await f.auth.sharedStrategies(s.accessToken),{items:[]});
  const loaded=await f.auth.loadSharedStrategy(s.accessToken,{strategyId:'orb_test'});assert.equal(loaded.configuration.family,'orb');
  f.shared({version:2,family:'orb'});await assert.rejects(()=>f.auth.loadSharedStrategy(s.accessToken,{strategyId:'orb_test'}));
  const calls=f.requests.filter(r=>new URL(r.url).pathname.includes('/rpc/stratum_admin_')||new URL(r.url).pathname.includes('/rpc/stratum_load_strategy'));
  assert.ok(calls.every(r=>r.options.headers.Authorization==='Bearer '+f.jwt));
  assert.ok(!JSON.stringify(loaded).includes(f.jwt));
 }finally{f.p.close();}
});

test('signed device can renew stale Supabase authority, but provider revocation still denies it',async()=>{
 const f=fixture(),s=await f.login(),keys=keyPair(),ticket=f.p.issueEnrollment(s.accessToken);
 const payload={enrollmentToken:ticket.enrollmentToken,publicKey:keys.publicKey,label:'Authority refresh QA'};
 const pair=f.p.enrollInstallation({...payload,signature:signed(payload,keys.privateKey).signature});f.p.approvePairing(s.accessToken,pair.code,pair.fingerprint);f.p.activate(s.accessToken,pair.installationId);
 const server=controlHttp(f.p,{auth:f.auth});server.listen(0,'127.0.0.1');await once(server,'listening');const agent=id();
 async function device(path){const proof=makeProof(pair.installationId,'POST',path,{},keys.privateKey,f.now(),agent);return fetch(`http://127.0.0.1:${server.address().port}`+path,{method:'POST',headers:{'Content-Type':'application/json','X-Stratum-Proof':Buffer.from(JSON.stringify(proof)).toString('base64url')},body:'{}'});}
 try{assert.equal((await device('/v1/device/connect')).status,200);f.advance(11000);
  assert.equal(f.p.accessState(f.account).accessActive,false);
  const heartbeat=await device('/v1/device/heartbeat');assert.equal(heartbeat.status,200,JSON.stringify(await heartbeat.json()));
  f.revoke();f.advance(4000);assert.equal((await device('/v1/device/heartbeat')).status,401);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));f.p.close();}
});

test('Supabase chat uses the owner JWT and server-bound ownership; updates persist and expiry does not hide own data',async()=>{
 const f=fixture(),s=await f.login(),v={id:id(),title:'ORB research',provider:'openrouter',locale:'tr',messages:[{role:'user',content:'0.10R'}]};
 try{
  await rejects(()=>f.auth.saveConversation(s.accessToken,{...v,account_id:id()}),'INVALID_REQUEST');
  const saved=await f.auth.saveConversation(s.accessToken,v);f.advance(1000);
  const updated=await f.auth.saveConversation(s.accessToken,{...v,title:'Edited',messages:[...v.messages,{role:'assistant',content:'Hypothesis only'}]});
  assert.equal(updated.createdAt,saved.createdAt);assert.notEqual(updated.updatedAt,saved.updatedAt);assert.equal(updated.messageCount,2);
  f.state.accessMode='inactive';f.state.accessActive=false;await f.auth.forBrowser(s.accessToken);
  const list=await f.auth.listConversations(s.accessToken,{offset:0});assert.equal(list.items.length,1);assert.equal(list.hasMore,false);assert.ok(!('messages' in list.items[0]));
  assert.equal((await f.auth.readConversation(s.accessToken,v.id)).title,'Edited');await rejects(()=>f.auth.readConversation(s.accessToken,id()),'CONVERSATION_NOT_FOUND');
  const calls=f.requests.filter(r=>new URL(r.url).pathname==='/rest/v1/stratum_conversations');
  assert.ok(calls.every(r=>r.options.headers.Authorization==='Bearer '+f.jwt));assert.ok(!JSON.stringify(list).includes(f.jwt));
  assert.deepEqual(await f.auth.deleteConversation(s.accessToken,v.id),{deleted:true});await rejects(()=>f.auth.readConversation(s.accessToken,v.id),'CONVERSATION_NOT_FOUND');
  f.revoke();await rejects(()=>f.auth.forBrowser(s.accessToken),'SESSION_REVOKED');await rejects(()=>f.auth.listConversations(s.accessToken,{offset:0}),'UNAUTHORIZED');
 }finally{f.p.close();}
});

test('Supabase authority, not local trial or editable metadata, grants the demo',async()=>{
 const f=fixture(),s=await f.login(),actor=f.p.browser(s.accessToken);
 assert.equal(actor.accountId,f.account);assert.equal(f.p.sessionInfo(s.accessToken).accessMode,'demo');
 assert.equal(f.p.sessionInfo(s.accessToken).trial.daysRemaining,30);
 assert.equal(f.p.get('SELECT count(*) n FROM identities').n,0);
 const row=f.p.get('SELECT sealed_tokens FROM supabase_sessions');
 assert.ok(!row.sealed_tokens.includes(f.jwt));assert.ok(!row.sealed_tokens.includes(f.refresh));
 f.p.provisionAccount(f.account,Date.now()+365*DAY);await f.auth.forBrowser(s.accessToken);
 assert.equal(f.p.sessionInfo(s.accessToken).accessMode,'demo');assert.equal(f.p.get('SELECT entitlement_until FROM accounts').entitlement_until,0);f.p.close();
});
test('email confirmation cannot create a local browser session or local demo',async()=>{
 const f=fixture();f.confirmation(true);const result=await f.auth.register({email:f.state.email,password:'a-long-private-password',displayName:'Cem'});
 assert.equal(result.confirmationRequired,true);assert.equal(f.p.get('SELECT count(*) n FROM sessions').n,0);
 assert.equal(f.p.get('SELECT count(*) n FROM account_trials').n,0);f.p.close();
});
test('signup pins the email return to Studio, not Supabase localhost:3000 fallback',async()=>{
 const f=fixture();f.confirmation(true);
 await f.auth.register({email:f.state.email,password:'a-long-private-password'});
 const request=f.requests.find(r=>new URL(r.url).pathname==='/auth/v1/signup');
 assert.equal(new URL(request.url).searchParams.get('redirect_to'),'http://127.0.0.1:4310/studio');
 await rejects(()=>f.auth.register({email:f.state.email,password:'a-long-private-password',redirectTo:'https://evil.example'}),'INVALID_REQUEST');
 assert.equal(f.requests.length,1);f.p.close();
});
test('operator Studio origin accepts HTTPS or loopback only, without embedded credentials or redirects',()=>{
 const p=new ControlPlane(),config={url:'https://testproject.supabase.co',publishableKey:'sb_publishable_test',encryptionKey:randomBytes(32)};
 try{
  const auth=new SupabaseAuth(p,{...config,studioOrigin:'https://studio.example.com'});
  assert.equal(auth.confirmationUrl,'https://studio.example.com/studio');
  const pages=new SupabaseAuth(p,{...config,studioOrigin:'https://cemkaaa.github.io',studioBasePath:'/CemkaCapital'});
  assert.equal(pages.confirmationUrl,'https://cemkaaa.github.io/CemkaCapital/studio/');
  for(const studioBasePath of ['/../evil','//evil.example','/CemkaCapital?next=evil','/%2e%2e','https://evil.example','/CemkaCapital/'])
   assert.throws(()=>new SupabaseAuth(p,{...config,studioBasePath}));
  for(const studioOrigin of ['http://evil.example','https://user:secret@studio.example.com','https://studio.example.com/?next=https://evil.example','https://studio.example.com/other','javascript:alert(1)'])
   assert.throws(()=>new SupabaseAuth(p,{...config,studioOrigin}));
 }finally{p.close();}
});
test('email-return tokens are not adopted as a browser session and unsafe error descriptions are not displayed',()=>{
 assert.equal(authReturn(''),null);
 assert.equal(authReturn('#builder'),null);
 assert.equal(authReturn('#access_token=private&refresh_token=also-private&type=signup'),'confirmed');
 assert.equal(authReturn('#error=access_denied&error_description=%3Cscript%3Eevil%3C/script%3E'),'failed');
 assert.equal(authReturn('#access_token=private&error_code=otp_expired'),'failed');
});
test('expiry, renewed login and paid entitlement follow the immutable database timestamps',async()=>{
 const f=fixture();let s=await f.login();const until=f.state.trial.expiresAt;f.advance(10*DAY);s=await f.login();
 assert.equal(f.p.sessionInfo(s.accessToken).trial.daysRemaining,20);assert.equal(f.p.sessionInfo(s.accessToken).trial.expiresAt,Math.floor(until));
 f.advance(20*DAY);f.state.accessMode='inactive';f.state.accessActive=false;s=await f.login();
 assert.equal(f.p.sessionInfo(s.accessToken).subscriptionActive,false);assert.throws(()=>f.p.issueEnrollment(s.accessToken),e=>e.code==='ENTITLEMENT_EXPIRED');
 f.state.paidUntil=f.state.trial.expiresAt+30*DAY;f.state.accessMode='paid';f.state.accessActive=true;await f.auth.forBrowser(s.accessToken);
 assert.equal(f.p.sessionInfo(s.accessToken).accessMode,'paid');assert.equal(f.p.sessionInfo(s.accessToken).trial.expiresAt,Math.floor(until));f.p.close();
});
test('Supabase outage fails closed instead of using a previously cached paid/demo grant',async()=>{
 const f=fixture(),s=await f.login();f.offline(true);
 await rejects(()=>f.auth.forBrowser(s.accessToken),'AUTH_PROVIDER_UNAVAILABLE');
 assert.equal(f.p.sessionInfo(s.accessToken).subscriptionActive,false);
 assert.throws(()=>f.p.issueEnrollment(s.accessToken),e=>e.code==='ENTITLEMENT_EXPIRED');f.p.close();
});
test('temporary provider failure preserves the browser session and recovers without another login',async()=>{
 const f=fixture(),s=await f.login(),actor=f.p.browser(s.accessToken);
 try{
  f.advance(3550000);f.offline(true);
  await rejects(()=>f.auth.forBrowser(s.accessToken),'AUTH_PROVIDER_UNAVAILABLE');
  assert.equal(f.p.browser(s.accessToken).sessionId,actor.sessionId);
  assert.equal(f.p.accessState(f.account).accessActive,false);
  f.offline(false);await f.auth.forBrowser(s.accessToken);
  assert.equal(f.p.browser(s.accessToken).sessionId,actor.sessionId);
  assert.equal(f.p.sessionInfo(s.accessToken).subscriptionActive,true);
 }finally{f.p.close();}
});
test('hourly JWT refreshes keep the same login for seven days and enforce the exact expiry boundary',async()=>{
 const f=fixture(),s=await f.login(),actor=f.p.browser(s.accessToken);
 try{
  assert.equal(s.expiresAt-f.p.now(),7*DAY);
  for(let hour=1;hour<168;hour++){
   f.advance(3600000);await f.auth.forBrowser(s.accessToken);
   assert.equal(f.p.browser(s.accessToken).sessionId,actor.sessionId);
  }
  assert.equal(f.refreshes(),167);
  f.advance(3600000);await rejects(()=>f.auth.forBrowser(s.accessToken),'UNAUTHORIZED');
 }finally{f.p.close();}
});
test('external logout deletes local controller/session/tickets; old JWT cannot restore authority',async()=>{
 const f=fixture(),s=await f.login();f.p.issueEnrollment(s.accessToken);f.revoke();
 await rejects(()=>f.auth.forBrowser(s.accessToken),'SESSION_REVOKED');
 assert.equal(f.p.get('SELECT count(*) n FROM sessions').n,0);assert.equal(f.p.get('SELECT count(*) n FROM enrollment_tickets').n,0);
 assert.equal(f.p.accessState(f.account).accessActive,false);f.p.close();
});
test('single-flight refresh rotates once and encrypted tokens are bound to local session ID',async()=>{
 const f=fixture(),s=await f.login(),actor=f.p.browser(s.accessToken);f.advance(3550000);
 await Promise.all([f.auth.forBrowser(s.accessToken),f.auth.forBrowser(s.accessToken),f.auth.forBrowser(s.accessToken)]);
 assert.equal(f.refreshes(),1);const sealed=f.p.get('SELECT sealed_tokens FROM supabase_sessions').sealed_tokens;
 assert.throws(()=>f.auth.unseal(sealed,id()));assert.equal(f.auth.unseal(sealed,actor.sessionId).jwt,f.jwt);f.p.close();
});
test('incorrect provider session/account scope and stale authority cannot authorize',async()=>{
 const f=fixture(),s=await f.login();f.state.sessionId=id();
 await rejects(()=>f.auth.forBrowser(s.accessToken),'SESSION_SCOPE_MISMATCH');assert.equal(f.p.accessState(f.account).accessActive,false);f.p.close();
 const g=fixture();await g.login();g.advance(10001);assert.equal(g.p.accessState(g.account).accessActive,false);g.p.close();
});
test('private strategies are stored through authenticated Supabase RLS requests',async()=>{
 const f=fixture(),s=await f.login(),c=defaultConfiguration('entrylab');c.name='Cem exact strategy';c.runtime.maxOpen=20;
 await f.auth.saveStrategy(s.accessToken,c);assert.deepEqual(await f.auth.strategies(s.accessToken),[c]);
 assert.equal(f.p.get('SELECT count(*) n FROM strategies').n,0);f.p.close();
});
test('HTTP login returns only an HttpOnly cookie handle; cookie CSRF and developer bypass blocked',async()=>{
 const f=fixture(),server=controlHttp(f.p,{auth:f.auth});server.listen(0,'127.0.0.1');await once(server,'listening');
 const base=`http://127.0.0.1:${server.address().port}`,origin='http://127.0.0.1:4310';
 const post=(path,body,headers={})=>fetch(base+path,{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(body)});
 try{
  const response=await post('/v1/auth/login',{email:f.state.email,password:'a-long-private-password'},{Origin:origin});assert.equal(response.status,200);
  const data=await response.json();assert.equal(data.accessToken,'cookie-session');const cookie=response.headers.get('set-cookie');
  assert.ok(cookie.includes('HttpOnly'));assert.ok(cookie.includes('SameSite=Strict'));assert.ok(!cookie.includes(f.jwt));
  assert.ok(cookie.includes('Max-Age=604800'));assert.equal(data.expiresAt-f.p.now(),7*DAY);
  const headers={Cookie:cookie.split(';')[0],Authorization:'Bearer cookie-session',Origin:origin};
  const session=await (await fetch(base+'/v1/session',{headers})).json();assert.equal(session.accountId,f.account);assert.equal(session.accessMode,'demo');
  assert.equal((await post('/v1/trading',{}, {Cookie:headers.Cookie})).status,403);
  assert.equal((await post('/v1/ea/package',{}, {...headers,Origin:'https://evil.example'})).status,403);
  const local=f.p.issueBrowserSession(f.p.provisionAccount());
  assert.equal((await fetch(base+'/v1/session',{headers:{Authorization:'Bearer '+local.accessToken}})).status,401);
  const logout=await post('/v1/auth/logout',{},headers);assert.equal(logout.status,200);
  assert.ok(logout.headers.get('set-cookie').includes('Max-Age=0'));
  assert.equal((await fetch(base+'/v1/session',{headers})).status,401);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));f.p.close();}
});
test('owner-bound EA setup ticket uses fresh Supabase authority; native demo certificate stays signed',async()=>{
 const f=fixture(),s=await f.login(),keys=keyPair(),t=f.p.issueEnrollment(s.accessToken);
 const payload={enrollmentToken:t.enrollmentToken,publicKey:keys.publicKey,label:'Cem MT5'},pair=f.p.enrollInstallation({...payload,signature:signed(payload,keys.privateKey).signature});
 f.p.approvePairing(s.accessToken,pair.code,pair.fingerprint);const install=f.p.get('SELECT * FROM installations WHERE id=?',pair.installationId);
 await f.auth.forDevice(install,'/v1/device/identity');
 const certificate=f.p.eaIdentity(install,{symbol:'JP225m',brokerServer:'Exness-MT5Trial15',accountLogin:'123'}).payload.certificate;
 assert.ok(certificate.includes('accessMode=demo'));assert.ok(certificate.includes('subscriberName=Cem Quant'));
 f.revoke();f.advance(4000);await rejects(()=>f.auth.forDevice(install,'/v1/device/heartbeat'),'SESSION_REVOKED');
 assert.equal(f.p.get('SELECT used FROM enrollment_tickets WHERE token_hash=?',hash(t.enrollmentToken)).used,1);f.p.close();
});
