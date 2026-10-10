import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFileSync,existsSync,mkdirSync,writeFileSync} from 'node:fs';
import {resolve,sep,extname} from 'node:path';
import {once} from 'node:events';
import {chromium} from 'playwright';
import {CLOUD_CONTROL} from '../control-service/api-location.mjs';
import {defaultConfiguration} from '../lib/universal-contract.ts';

const root=resolve(import.meta.dirname,'../out'),report=resolve(import.meta.dirname,'../../reports/verification_build/audit_progress_20261011');
mkdirSync(report,{recursive:true});
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.woff2':'font/woff2','.svg':'image/svg+xml'};
const server=createServer((request,response)=>{
  const path=decodeURIComponent(new URL(request.url,'http://localhost').pathname).replace(/^\/CemkaCapital(?=\/|$)/,'');
  const file=resolve(root,'.'+path+(path.endsWith('/')?'index.html':''));
  if(!file.startsWith(root+sep)||!existsSync(file)){response.writeHead(404);response.end();return;}
  response.writeHead(200,{'Content-Type':mime[extname(file)]??'application/octet-stream'});response.end(readFileSync(file));
});
server.listen(0,'127.0.0.1');await once(server,'listening');
const browser=await chromium.launch({headless:true}),errors=[],checks=[];
const installationId='a0ca30de-5cc2-4e39-bc41-9420530076c8',jobId='0082b056-f90f-49af-9db2-8949e97c780d';
let job,error='';
const session=()=>({accountId:'qa-progress',displayName:'Progress QA',subscriptionActive:true,accessMode:'paid',entitlementUntil:Date.now()+86400000,trial:null,
  installations:[{id:installationId,label:'QA terminal',state:'approved',createdAt:Date.now()}],
  lease:{installationId,active:true,controlledHere:true},trading:{enabled:false,jobId:null},
  terminalStatuses:[{installationId,reportedAt:Date.now(),symbol:'BTCUSDm',brokerServer:'QA',accountLogin:'123',openPositions:0,trading:false,error}]});
try{
  const context=await browser.newContext({viewport:{width:1440,height:1100}});
  await context.addInitScript(()=>{sessionStorage.setItem('stratum.cloud-session.v1','progress-test-session');localStorage.setItem('stratum.language','en');});
  const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
  await page.route(CLOUD_CONTROL+'/**',async route=>{
    const path=new URL(route.request().url()).pathname.split('/stratum-control')[1],method=route.request().method();
    if(path==='/v1/jobs'&&method==='POST'){
      const request=route.request().postDataJSON(),createdAt=Date.now()-131000;
      job={id:jobId,state:'running',failureCode:null,request,configurationHash:'a'.repeat(64),createdAt,updatedAt:Date.now(),
        progress:{phase:'downloading',processed:0,total:null,detail:'M1 need~20361 bars=5000 oldest=syncing'},result:null};
      await route.fulfill({status:201,json:job});return;
    }
    const value=path==='/v1/session'?session():path==='/v1/jobs/'+jobId?job:path==='/v1/jobs'?{jobs:[]}
      :path==='/v1/strategies'?{strategies:[]}:path.includes('/admin/')?{isAdmin:false}:{};
    await route.fulfill({status:200,json:value});
  });
  await page.goto(`http://127.0.0.1:${server.address().port}/CemkaCapital/studio/`);
  await page.locator('.uc-status-grid').waitFor();
  await page.getByRole('button',{name:'Apply & Run MT5 Audit',exact:true}).click();
  const card=page.locator('#mt5-audit-results .uc-audit-progress'),meter=card.getByRole('progressbar');
  await card.waitFor();
  assert.equal(await meter.getAttribute('aria-valuenow'),null);
  assert.ok((await card.innerText()).includes('Downloading / building broker history'));
  assert.ok((await card.innerText()).includes('Elapsed 02:'));
  assert.ok((await card.innerText()).includes('bars=5000'));
  assert.notEqual(await card.locator('.uc-audit-meter-fill').evaluate(e=>getComputedStyle(e).animationName),'none');
  await card.scrollIntoViewIfNeeded();await card.screenshot({path:resolve(report,'download-progress-desktop.png')});
  checks.push('indeterminate animated history with elapsed time and real diagnostic, no fake percentage');
  job.progress={phase:'replaying',processed:38,total:100};job.updatedAt=Date.now();
  await page.waitForFunction(()=>document.querySelector('#mt5-audit-results [role=progressbar]')?.getAttribute('aria-valuenow')==='38');
  checks.push('actual replay percentage');
  error='AUDIT_AUTHORITY_EXPIRED';
  await card.getByText('Waiting for renewed audit authority',{exact:true}).waitFor();
  assert.equal(await card.locator('.uc-audit-meter-fill').evaluate(e=>getComputedStyle(e).animationPlayState),'paused');
  checks.push('temporary authority pause, not fake success');
  job.state='completed';job.updatedAt=Date.now();job.result={configurationHash:job.configurationHash,trades:[],summary:{wins:7,losses:0,flat:0,open:1,data:0,netR:.07,winRate:100,maxClosedDrawdownR:0,coverageComplete:true}};
  await card.getByText('Audit complete',{exact:true}).waitFor();
  assert.equal(await meter.getAttribute('aria-valuenow'),'100');
  assert.equal(await card.locator('.uc-audit-pause').count(),0);
  checks.push('completed result wins over stale terminal pause / 38% progress');
  await page.setViewportSize({width:390,height:844});
  await card.scrollIntoViewIfNeeded();const bounds=await card.boundingBox();assert.ok(bounds.x>=0&&bounds.x+bounds.width<=391);
  await card.screenshot({path:resolve(report,'completed-progress-mobile.png')});checks.push('mobile width');
  assert.deepEqual(errors,[]);
}finally{await browser.close();server.close();await once(server,'close');}
writeFileSync(resolve(report,'ui-report.json'),JSON.stringify({status:'PASS',mockApi:true,liveBrokerAuditClaimed:false,checks},null,2)+'\n');
console.log(JSON.stringify({status:'PASS',checks}));
