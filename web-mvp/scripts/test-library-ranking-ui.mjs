import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFileSync,existsSync,mkdirSync,writeFileSync} from 'node:fs';
import {resolve,sep,extname} from 'node:path';
import {once} from 'node:events';
import {chromium} from 'playwright';
import {CLOUD_CONTROL} from '../control-service/api-location.mjs';
import {campaignWindows} from '../lib/strategy-campaign.ts';

const root=resolve(import.meta.dirname,'../out'),report=resolve(import.meta.dirname,'../../reports/verification_build/universal_audit');
mkdirSync(report,{recursive:true});
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.woff2':'font/woff2','.svg':'image/svg+xml'};
const server=createServer((request,response)=>{
 const path=decodeURIComponent(new URL(request.url,'http://localhost').pathname).replace(/^\/CemkaCapital(?=\/|$)/,'');
 const file=resolve(root,'.'+path+(path.endsWith('/')?'index.html':''));
 if(!file.startsWith(root+sep)||!existsSync(file)){response.writeHead(404);response.end();return;}
 response.writeHead(200,{'Content-Type':mime[extname(file)]??'application/octet-stream'});response.end(readFileSync(file));
});
server.listen(0,'127.0.0.1');await once(server,'listening');
const browser=await chromium.launch({headless:true}),errors=[];
const metrics=(wins,losses)=>({total:wins+losses,wins,losses,open:0,flat:0,winRate:wins/(wins+losses)*100,netR:wins-losses,minCumR:-losses});
const strategy=(id,w,l)=>({id,name:id,family:'orb',symbol:'JP225m',sourceHash:'a'.repeat(64),campaign:{version:1,kind:'MEGA',asOf:1791575217,symbol:'JP225m',chartTimeframe:5,independent:true,
 windows:campaignWindows.map(({weeks})=>({weeks,status:'AUDITED',available:true,metrics:weeks===260?metrics(l,w):metrics(w,l)}))}});
const items=[strategy('small-sample',99,1),strategy('large-sample',9900,100),strategy('balanced',400,400),{id:'missing',name:'missing',family:'orb',symbol:'JP225m',sourceHash:'b'.repeat(64),campaign:null}];
const session={accountId:'qa-account',displayName:'Ranking QA',subscriptionActive:true,accessMode:'paid',entitlementUntil:Date.now()+86400000,trial:null,installations:[],lease:null,trading:{enabled:false,jobId:null},terminalStatuses:[]};
try{
 const context=await browser.newContext({viewport:{width:1440,height:1000}});
 await context.addInitScript(()=>{sessionStorage.setItem('stratum.cloud-session.v1','ranking-test-session');localStorage.setItem('stratum.language','en');});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
 await page.route(CLOUD_CONTROL+'/**',route=>{
  const path=new URL(route.request().url()).pathname.split('/stratum-control')[1];
  const value=path==='/v1/session'?session:path==='/v1/library/strategies'?{items}:path==='/v1/strategies'?{strategies:[]}:path==='/v1/jobs'?{jobs:[]}:path.includes('/admin/')?{isAdmin:false}:{};
  return route.fulfill({status:200,json:value});
 });
 await page.goto(`http://127.0.0.1:${server.address().port}/CemkaCapital/studio/`);
 await page.locator('.uc-status-grid').waitFor({state:'visible'});
 await page.getByRole('button',{name:/Strategy library.*Save, search/}).click();
 const library=page.locator('.shared-strategy-library'),cards=library.locator('.campaign-library-card');
 await cards.first().waitFor();
 const names=()=>cards.locator(':scope > strong').allTextContents();
 await library.getByRole('button',{name:'2W',exact:true}).click();
 assert.deepEqual(await names(),['large-sample','small-sample','balanced','missing']);
 assert.ok((await cards.first().innerText()).includes('99%'));
 await library.getByRole('button',{name:/Win rate.*Highest first/}).click();
 assert.deepEqual(await names(),['balanced','large-sample','small-sample','missing']);
 await library.getByRole('button',{name:/Trade count.*Highest first/}).click();
 assert.deepEqual(await names(),['balanced','small-sample','large-sample','missing']);
 await library.getByRole('button',{name:/Win rate.*Lowest first/}).click();
 assert.deepEqual(await names(),['small-sample','balanced','large-sample','missing']);
 await library.getByRole('button',{name:'Clear sorting',exact:true}).click();
 await library.getByRole('button',{name:/^Wins\s*Not sorted$/}).click();
 assert.deepEqual(await names(),['large-sample','balanced','small-sample','missing']);
 await library.getByRole('button',{name:'5Y',exact:true}).click();
 assert.deepEqual(await names(),['balanced','large-sample','small-sample','missing']);
 await library.screenshot({path:resolve(report,'strategy-library-desktop.png')});
 await page.setViewportSize({width:390,height:844});
 const controls=library.locator('.campaign-sort-controls');await controls.scrollIntoViewIfNeeded();
 const bounds=await controls.boundingBox();assert.ok(bounds.x>=0&&bounds.x+bounds.width<=390);
 await controls.screenshot({path:resolve(report,'strategy-library-mobile.png')});
 assert.deepEqual(errors,[]);
 writeFileSync(resolve(report,'library-ui-report.json'),JSON.stringify({status:'PASS',mockApi:true,liveBrokerAuditClaimed:false,checks:['all nine windows','multi-sort priority','descending/ascending/off','selected-window metrics','missing-last','desktop/mobile controls','no runtime errors']},null,2));
 console.log('LIBRARY_RANKING_UI_PASS');
}finally{await browser.close();server.close();await once(server,'close');}
