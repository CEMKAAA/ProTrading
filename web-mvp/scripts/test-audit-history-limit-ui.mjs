import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFileSync, existsSync, mkdirSync, writeFileSync, renameSync} from 'node:fs';
import {resolve, sep, extname} from 'node:path';
import {once} from 'node:events';
import {chromium} from 'playwright';
import {CLOUD_CONTROL} from '../control-service/api-location.mjs';

const root = resolve(import.meta.dirname, '../out');
const report = resolve(import.meta.dirname, '../../reports/verification_build/audit_max_bars_20261011');
mkdirSync(report, {recursive:true});
const server = createServer((req, res) => {
  const path = new URL(req.url, 'http://localhost').pathname.replace(/^\/CemkaCapital(?=\/|$)/, '');
  const file = resolve(root, '.' + path + (path.endsWith('/') ? 'index.html' : ''));
  if (!file.startsWith(root + sep) || !existsSync(file)) {res.writeHead(404);res.end();return;}
  res.writeHead(200, {'Content-Type':{'.html':'text/html', '.js':'text/javascript', '.css':'text/css'}[extname(file)] ?? 'application/octet-stream'});
  res.end(readFileSync(file));
});
server.listen(0, '127.0.0.1');await once(server, 'listening');
const browser = await chromium.launch({headless:true}), errors = [], checks = [];
const installationId = 'a0ca30de-5cc2-4e39-bc41-9420530076c8';
const detail = 'MA HISTORY BLOCKED / signal CopyRates copied=100000 error=0 seed=2025.10.28 14:45 first=2025.10.28 15:25 bars=100009 max=100000';
let job;
try {
  const context = await browser.newContext({viewport:{width:1440,height:1000}});
  await context.addInitScript(() => {sessionStorage.setItem('stratum.cloud-session.v1','max-bars-qa');localStorage.setItem('stratum.language','tr');});
  const page = await context.newPage();page.on('pageerror', e => errors.push(e.message));
  await page.route(CLOUD_CONTROL + '/**', async route => {
    const path = new URL(route.request().url()).pathname.split('/stratum-control')[1];
    let value = {};
    if (path === '/v1/session') value = {accountId:'qa',displayName:'QA',subscriptionActive:true,accessMode:'paid',entitlementUntil:Date.now()+86400000,trial:null,
      installations:[{id:installationId,label:'QA',state:'approved',createdAt:Date.now()}],lease:{installationId,active:true,controlledHere:true},trading:{enabled:false,jobId:null},
      terminalStatuses:[{installationId,reportedAt:Date.now(),symbol:'BTCUSDm',brokerServer:'QA',accountLogin:'123',openPositions:0,trading:false,error:job?'AUDIT_HISTORY_BLOCKED':''}]};
    else if (path === '/v1/jobs' && route.request().method() === 'POST') {
      job = {id:'max-bars-job',state:'failed',failureCode:'AUDIT_HISTORY_BLOCKED',request:route.request().postDataJSON(),configurationHash:'a'.repeat(64),createdAt:Date.now()-12000,updatedAt:Date.now(),progress:{phase:'downloading',processed:0,total:null,detail},result:null};
      await route.fulfill({status:201,json:job});return;
    } else if (path === '/v1/jobs/max-bars-job') value = job;
    else if (path === '/v1/jobs') value = {jobs:[]};
    else if (path === '/v1/strategies') value = {strategies:[]};
    else if (path.includes('/admin/')) value = {isAdmin:false};
    await route.fulfill({status:200,json:value});
  });
  await page.goto(`http://127.0.0.1:${server.address().port}/CemkaCapital/studio/`);
  await page.locator('.uc-status-grid').waitFor();
  await page.getByRole('button',{name:'Uygula ve MT5 auditini çalıştır',exact:true}).click();
  const results = page.locator('#mt5-audit-results');
  await results.getByText(/MT5, grafikteki maksimum bar sınırına takıldı/).waitFor();
  assert.ok((await results.innerText()).includes('1.000.000'));
  assert.ok((await results.innerText()).includes('.state'));
  assert.ok((await results.innerText()).includes(detail));
  assert.equal(await results.locator('.uc-metrics').count(),0);
  assert.equal(await results.getByRole('progressbar').getAttribute('aria-valuenow'), null);
  checks.push('real native diagnostic maps to Turkish terminal-limit instructions, retaining detail and no fabricated result');
  await page.waitForFunction(() => [...document.querySelectorAll('p.uc-error')].some(e => e.textContent.startsWith('MT5: ') && e.textContent.includes('maksimum bar sınırına')));
  checks.push('terminal status error receives only the matching installation/job diagnostic');
  await page.setViewportSize({width:390,height:844});await results.scrollIntoViewIfNeeded();
  const bounds = await results.boundingBox();assert.ok(bounds.x>=0&&bounds.x+bounds.width<=391);
  checks.push('mobile width');assert.deepEqual(errors,[]);
} finally {await browser.close();server.close();await once(server,'close');}
const file = resolve(report,'ui-report.json');
writeFileSync(file+'.pending',JSON.stringify({status:'PASS',mockApi:true,liveBrokerAuditClaimed:false,checks},null,2)+'\n');renameSync(file+'.pending',file);
console.log(JSON.stringify({status:'PASS',checks}));
