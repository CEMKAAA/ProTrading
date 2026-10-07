import assert from 'node:assert/strict';
import {test} from 'node:test';
import {once} from 'node:events';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {ControlPlane} from '../control-service/control-plane.mjs';
import {controlHttp} from '../control-service/http.mjs';
import {id} from '../control-service/crypto.mjs';
import {saveConversationSchema,savedConversationSchema} from '../lib/studio-conversations.ts';

const draft=()=>({id:id(),title:'USDJPY ORB research',provider:'openrouter',locale:'tr',messages:[{role:'user',content:'0.10R isterim'},{role:'assistant',content:'Research hypothesis, not an applied strategy.'}]});
const forbidden=(fn,code)=>assert.throws(fn,e=>e.code===code);
test('chat contract rejects ownership/tool injection, invalid text, counts and oversized snapshots',()=>{
 const c=draft();assert.ok(saveConversationSchema.safeParse(c).success);
 for(const bad of [{...c,account_id:id()},{...c,configuration:{}},{...c,messages:[{role:'system',content:'execute'}]},{...c,messages:[{role:'user',content:'\0'}]},{...c,title:'bad\ncommand'},{...c,messages:Array.from({length:513},()=>c.messages[0])},{...c,messages:Array.from({length:200},()=>({role:'assistant',content:'x'.repeat(6000)}))}])assert.equal(saveConversationSchema.safeParse(bad).success,false);
 assert.equal(savedConversationSchema.safeParse({...c,messageCount:3,createdAt:new Date().toISOString(),updatedAt:new Date().toISOString()}).success,false);
});
test('manual save survives service restart; updating a chat keeps its id and creation time',()=>{
 const dir=mkdtempSync(join(tmpdir(),'stratum-chat-'));let p;let at=Date.now();
 try{
  p=new ControlPlane({database:join(dir,'control.sqlite'),now:()=>at});const account=p.provisionAccount(),s=p.issueBrowserSession(account),c=draft();
  assert.equal(p.listConversations(s.accessToken,{offset:0}).items.length,0);
  const saved=p.saveConversation(s.accessToken,c);p.close();p=new ControlPlane({database:join(dir,'control.sqlite'),now:()=>at});
  assert.deepEqual(p.readConversation(s.accessToken,c.id),saved);
  at+=1000;c.title='Updated research';c.messages.push({role:'user',content:'Continue'});const updated=p.saveConversation(s.accessToken,c);
  assert.equal(updated.createdAt,saved.createdAt);assert.notEqual(updated.updatedAt,saved.updatedAt);assert.equal(updated.messageCount,3);
  assert.equal(p.listConversations(s.accessToken,{offset:0}).items.length,1);
 }finally{p?.close();rmSync(dir,{recursive:true,force:true});}
});
test('separate owners cannot read, delete or overwrite each other; own data remains available after trial expiry',()=>{
 let at=Date.now();const p=new ControlPlane({now:()=>at});try{
  const a=p.provisionAccount(),b=p.provisionAccount(),sa=p.issueBrowserSession(a).accessToken,sb=p.issueBrowserSession(b).accessToken,c=draft();
  p.saveConversation(sa,c);assert.equal(p.listConversations(sb,{offset:0}).items.length,0);
  forbidden(()=>p.readConversation(sb,c.id),'CONVERSATION_NOT_FOUND');forbidden(()=>p.deleteConversation(sb,c.id),'CONVERSATION_NOT_FOUND');
  p.saveConversation(sb,{...c,title:'B private'});assert.equal(p.readConversation(sa,c.id).title,c.title);
  p.run('UPDATE accounts SET entitlement_until=0 WHERE id=?',a);assert.equal(p.readConversation(sa,c.id).messages.length,2);
  p.logout(sa);forbidden(()=>p.readConversation(sa,c.id),'UNAUTHORIZED');
  assert.deepEqual(p.deleteConversation(sb,c.id),{deleted:true});forbidden(()=>p.readConversation(sb,c.id),'CONVERSATION_NOT_FOUND');
 }finally{p.close();}
});
test('history pages list metadata, not messages, and include every saved chat',()=>{
 let at=Date.now();const p=new ControlPlane({now:()=>at});try{
  const s=p.issueBrowserSession(p.provisionAccount()).accessToken;
  for(let i=0;i<27;i++){at++;p.saveConversation(s,{...draft(),title:'Chat '+i});}
  const first=p.listConversations(s,{offset:0}),second=p.listConversations(s,{offset:25});
  assert.equal(first.items.length,25);assert.equal(first.hasMore,true);assert.equal(second.items.length,2);assert.equal(second.hasMore,false);
  assert.equal(first.items[0].title,'Chat 26');assert.equal(new Set([...first.items,...second.items].map(c=>c.id)).size,27);
  assert.ok(first.items.every(c=>!('messages' in c)));forbidden(()=>p.listConversations(s,{offset:-1}),'INVALID_REQUEST');
 }finally{p.close();}
});
test('HTTP history is authenticated and CSRF guarded; none of its routes start jobs or trading',async()=>{
 const p=new ControlPlane(),a=p.issueBrowserSession(p.provisionAccount()).accessToken,b=p.issueBrowserSession(p.provisionAccount()).accessToken;
 const server=controlHttp(p);server.listen(0,'127.0.0.1');await once(server,'listening');
 const base=`http://127.0.0.1:${server.address().port}`,path='/v1/assistant/conversations',c=draft();
 const headers={Cookie:'stratum_session='+a,Authorization:'Bearer cookie-session',Origin:'http://127.0.0.1:4310','Content-Type':'application/json'};
 const post=(route,body,extras=headers)=>fetch(base+route,{method:'POST',headers:extras,body:JSON.stringify(body)});
 try{
  assert.equal((await post(path,c,{'Content-Type':'application/json'})).status,401);
  assert.equal((await post(path,c,{...headers,Origin:undefined})).status,403);
  assert.equal((await post(path,c,{...headers,Origin:'https://evil.example'})).status,403);
  assert.equal((await post(path,{...c,account_id:id()})).status,400);
  assert.equal((await post(path,c)).status,200);assert.equal((await (await post(path+'/list',{offset:0})).json()).items.length,1);
  assert.equal((await fetch(base+path+'/'+c.id,{headers:{...headers,Cookie:'stratum_session='+b}})).status,404);
  assert.equal((await post(path+'/'+c.id+'/delete',{}, {...headers,Cookie:'stratum_session='+b})).status,404);
  assert.equal((await fetch(base+path+'/'+c.id,{headers})).status,200);
  assert.equal(p.get('SELECT count(*) n FROM jobs').n,0);assert.equal(p.get('SELECT count(*) n FROM trading WHERE enabled=1').n,0);
  assert.equal((await post(path+'/'+c.id+'/delete',{})).status,200);
  assert.equal((await fetch(base+path+'/'+c.id,{headers})).status,404);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));p.close();}
});
