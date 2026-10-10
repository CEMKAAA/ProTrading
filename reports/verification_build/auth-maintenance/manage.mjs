import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { Decrypter } from 'age-encryption';

const project='uvzhrrqzzdjqtmydpvwo';
const passphrase=readFileSync(0,'utf8').trim();
const decryptor=new Decrypter();decryptor.addPassphrase(passphrase);
const secrets=JSON.parse(await decryptor.decrypt(readFileSync('C:/Users/Cem/.codex/secrets/mcp_oauth.age'),'text'));
let credential;
function find(value){
 if(typeof value==='string'){try{find(JSON.parse(value));}catch{}return;}
 if(!value||typeof value!=='object')return;
 if(value.server_name==='supabase'&&new URL(value.url).searchParams.get('project_ref')===project){credential=value;return;}
 for(const child of Object.values(value))find(child);
}
find(secrets);if(!credential||credential.expires_at<=Date.now())throw new Error('SCOPED_OAUTH_CREDENTIAL_UNAVAILABLE');
const headers={Authorization:'Bearer '+credential.token_response.access_token,'Content-Type':'application/json'};
const endpoint='https://api.supabase.com/v1/projects/'+project;
if(process.argv[2]==='cli'){
 const result=spawnSync('npx --yes supabase functions deploy stratum-control --project-ref '+project+' --no-verify-jwt --use-api',{
  shell:true,cwd:'C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem/web-mvp',
  env:{...process.env,SUPABASE_ACCESS_TOKEN:credential.token_response.access_token},stdio:['ignore','inherit','inherit'],windowsHide:true,
 });
 if(result.status!==0)throw new Error('FUNCTION_DEPLOY_FAILED');process.exit(0);
}
if(process.argv[2]==='deploy'){
 const mcp=credential.url;
 let session;
 const rpc=async body=>{
  const response=await fetch(mcp,{method:'POST',headers:{...headers,Accept:'application/json, text/event-stream',...(session?{'Mcp-Session-Id':session}:{}),'MCP-Protocol-Version':'2025-03-26'},body:JSON.stringify(body),signal:AbortSignal.timeout(120000)});
  session=response.headers.get('Mcp-Session-Id')??session;
  if(!response.ok)throw new Error('MCP_HTTP_STATUS_'+response.status);
  const text=await response.text();
  return JSON.parse(text.startsWith('event:')||text.startsWith('data:')?text.split('\n').filter(x=>x.startsWith('data:')).map(x=>x.slice(5).trim()).join(''):text);
 };
 await rpc({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-03-26',capabilities:{},clientInfo:{name:'stratum-maintenance',version:'1'}}});
 const path='C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem/web-mvp/supabase/functions/stratum-control/';
 const files=['index.mjs','control-bundle.mjs','operator-public-key.mjs','deno.json'].map(name=>({name,content:readFileSync(path+name,'utf8')}));
 const result=await rpc({jsonrpc:'2.0',id:2,method:'tools/call',params:{name:'deploy_edge_function',arguments:{name:'stratum-control',entrypoint_path:'index.mjs',import_map_path:'deno.json',verify_jwt:false,files}}});
 if(result.error||result.result?.isError)throw new Error('MCP_DEPLOY_REJECTED');
 console.log(JSON.stringify(result.result));process.exit(0);
}
const r=await fetch(endpoint+'/config/auth',{headers,signal:AbortSignal.timeout(30000)});
if(!r.ok)throw new Error('MANAGEMENT_AUTH_STATUS_'+r.status);
const config=await r.json();
console.log(JSON.stringify({site_url:config.site_url,uri_allow_list:config.uri_allow_list,mailer_autoconfirm:config.mailer_autoconfirm,external_email_enabled:config.external_email_enabled}));
if(process.argv[2]==='redirects'){
 const destination='https://cemkaaa.github.io/CemkaCapital/studio/';
 const current=(config.uri_allow_list??'').split(',').map(x=>x.trim()).filter(Boolean);
 if(!current.includes(destination)){
  const updated=await fetch(endpoint+'/config/auth',{method:'PATCH',headers,body:JSON.stringify({uri_allow_list:[...current,destination].join(',')}),signal:AbortSignal.timeout(30000)});
  if(!updated.ok)throw new Error('AUTH_CONFIG_UPDATE_STATUS_'+updated.status);
  console.log('Canonical Pages Studio callback added; existing callbacks preserved.');
 }
}
if(process.argv[2]==='deploy'){
 const result=spawnSync('npx --yes supabase functions deploy stratum-control --project-ref '+project+' --no-verify-jwt --use-api',{
  shell:true,cwd:'C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem/web-mvp',
  env:{...process.env,SUPABASE_ACCESS_TOKEN:credential.token_response.access_token},stdio:['ignore','inherit','inherit'],windowsHide:true,
 });
 if(result.status!==0)throw new Error('FUNCTION_DEPLOY_FAILED');
}
