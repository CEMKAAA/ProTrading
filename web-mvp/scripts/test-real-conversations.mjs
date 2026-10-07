import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {savedConversationSchema,conversationListSchema} from '../lib/studio-conversations.ts';

// Uses the existing ignored QA account only; never prints passwords or cookies.
// Creates and removes exactly one synthetic conversation, not user conversations.
if(process.argv[2]!=='--live')throw new Error('Use --live for the running Supabase-backed control service.');
const stateFile=new URL('../control-service/.state/real-demo-qa.json',import.meta.url);
const account=JSON.parse(readFileSync(stateFile,'utf8')),api='http://127.0.0.1:4321';
const call=async(path,body)=>{
 const response=await fetch(api+path,{method:body===undefined?'GET':'POST',headers:{Origin:'http://127.0.0.1:4310',...(account.cookie?{Cookie:account.cookie}:{}),...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(30000),redirect:'error'});
 const data=await response.json();return {response,data};
};
let session=await call('/v1/auth/session');
if(session.response.status===401){
 const login=await call('/v1/auth/login',{email:account.email,password:account.password});
 assert.equal(login.response.status,200,login.data.error);account.cookie=login.response.headers.get('set-cookie').split(';')[0];
 writeFileSync(stateFile,JSON.stringify(account),{mode:0o600});session=await call('/v1/auth/session');
}
assert.equal(session.response.status,200,session.data.error);
const path='/v1/assistant/conversations',id=randomUUID(),draft={id,title:'QA: saved conversation smoke test',provider:'local',locale:'en',messages:[{role:'user',content:'Research only; no trades.'},{role:'assistant',content:'Synthetic saved chat, not a model response.'}]};
let created=false;
try{
 const save=await call(path,draft);assert.equal(save.response.status,200,save.data.error);created=true;
 const first=savedConversationSchema.parse(save.data);assert.equal(first.id,id);assert.deepEqual(first.messages,draft.messages);
 const update=await call(path,{...draft,title:'QA: updated chat',messages:[...draft.messages,{role:'user',content:'Continue later'}]});assert.equal(update.response.status,200,update.data.error);
 const edited=savedConversationSchema.parse(update.data);assert.equal(edited.createdAt,first.createdAt);assert.equal(edited.messageCount,3);
 const list=await call(path+'/list',{offset:0});assert.equal(list.response.status,200,list.data.error);const items=conversationListSchema.parse(list.data).items;
 assert.equal(items.filter(c=>c.id===id).length,1);assert.ok(items.every(c=>!('messages' in c)));
 const read=await call(path+'/'+id);assert.equal(read.response.status,200,read.data.error);assert.deepEqual(savedConversationSchema.parse(read.data),edited);
 const forged=await call(path,{...draft,account_id:randomUUID()});assert.equal(forged.response.status,400);
 const removed=await call(path+'/'+id+'/delete',{});assert.equal(removed.response.status,200,removed.data.error);created=false;
 assert.equal((await call(path+'/'+id)).response.status,404);
 console.log(JSON.stringify({result:'PASS',backend:'real Supabase',checks:['save','update same chat','immutable creation time','list metadata','reopen exact messages','ownership input rejected','delete']}));
}finally{if(created){const cleanup=await call(path+'/'+id+'/delete',{});assert.equal(cleanup.response.status,200,'QA cleanup failed');}}
