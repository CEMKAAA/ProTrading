import {createServer} from 'node:http';
import {readFileSync,existsSync,mkdirSync,writeFileSync} from 'node:fs';
import {resolve,sep,extname} from 'node:path';
import {once} from 'node:events';
import {chromium} from 'playwright';

const root=resolve(import.meta.dirname,'../../..');
const out=resolve(root,'output/pdf/STRATUM_Referans_Paketi_20261011');
const assets=resolve(out,'assets');mkdirSync(assets,{recursive:true});
const read=p=>JSON.parse(readFileSync(resolve(root,p),'utf8'));
const catalog=read('reports/admin_catalog/catalog.private.json');
const campaigns=read('reports/admin_campaign/campaign.private.json');
const map=new Map(catalog.map(s=>[s.id,s]));
const cases=campaigns.map(row=>({id:row.id,name:map.get(row.id)?.name??row.id,family:map.get(row.id)?.family??row.id.split('_')[0],symbol:row.campaign.symbol,campaign:row.campaign}));
writeFileSync(resolve(out,'campaign_metrics.json'),JSON.stringify(cases,null,2));
const positive=cases.map(s=>({...s,window:s.campaign.windows.find(w=>w.weeks===260)})).filter(s=>s.window?.available&&s.window.metrics.netR>0&&s.window.metrics.wins+s.window.metrics.losses>=100).sort((a,b)=>b.window.metrics.netR-a.window.metrics.netR);
const examples=[];for(const family of ['orb','macross','sol','entrylab']){const s=positive.find(s=>s.family===family);if(s)examples.push({name:s.name,family:s.family,symbol:s.symbol,asOf:s.campaign.asOf,timeframe:s.campaign.chartTimeframe,mode:s.campaign.independent?'INDEPENDENT':'LEGACY',metrics:s.window.metrics,criterion:'Highest 5Y Net R in family among available windows with >=100 closed trades; retrospective selection.'});}
const recent=read('tmp/universal_connection_validation/canonical-universal-result.json');
const parity=read('tmp/universal_connection_validation/canonical-parity-report.json');
const controls=read('web-mvp/lib/ea-controls.json');
const facts={generatedAt:new Date().toISOString(),controls:Object.fromEntries(Object.entries(controls).map(([k,v])=>[k,{inputs:v.inputs.length,runtime:v.runtime.length}])),catalog:read('reports/admin_campaign/final-db-verification.json'),examples,parity,trace:recent.trades.map(({direction,signalUtc,entryUtc,exitUtc,entryPrice,exitPrice,sl,tp,outcome,exitReason,netR,spreadPrice})=>({direction,signalUtc,entryUtc,exitUtc,entryPrice,exitPrice,sl,tp,outcome,exitReason,netR,spreadPrice})),screenshots:[]};
writeFileSync(resolve(out,'evidence_summary.json'),JSON.stringify(facts,null,2));
const publicRoot=resolve(root,'web-mvp/out');
const types={'.html':'text/html','.js':'text/javascript','.css':'text/css','.woff2':'font/woff2','.svg':'image/svg+xml','.json':'application/json'};
const server=createServer((req,res)=>{const path=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\/CemkaCapital(?=\/|$)/,'');const file=resolve(publicRoot,'.'+path+(path.endsWith('/')?'index.html':''));if(!file.startsWith(publicRoot+sep)||!existsSync(file)){res.writeHead(404);return res.end();}res.writeHead(200,{'Content-Type':types[extname(file)]??'application/octet-stream'});res.end(readFileSync(file));});
server.listen(0,'127.0.0.1');await once(server,'listening');
const base=`http://127.0.0.1:${server.address().port}/CemkaCapital`;
const browser=await chromium.launch({headless:true});
const errors=[];
async function shot(page,selector,name,caption){const locator=selector?page.locator(selector).first():null;if(locator)await locator.scrollIntoViewIfNeeded();await page.waitForTimeout(650);if(locator)await locator.screenshot({path:resolve(assets,name+'.png')});else await page.screenshot({path:resolve(assets,name+'.png')});facts.screenshots.push({id:name,filename:name+'.png',caption,kind:selector?.startsWith('.launch')||name.startsWith('web_home')?'production_frontend_capture':'production_frontend_with_readonly_fixture_api'});console.log('CAPTURE '+name);}
try{
 const home=await browser.newPage({viewport:{width:1600,height:1000}});home.on('pageerror',e=>errors.push(e.message));await home.addInitScript(()=>localStorage.setItem('stratum.language','tr'));await home.goto(base+'/',{waitUntil:'networkidle'});await home.waitForTimeout(1800);await shot(home,null,'web_home','Yayımlanan üretim ön yüzünün yerel build kaydı. Tanıtım/rehber sahneleri sentetiktir.');await shot(home,'#platform','web_builder_chapter','Ana sayfanın builder bölümü; örnek kural görseli, yatırım tavsiyesi değildir.');await shot(home,'#workflow','web_connection_chapter','Ana sayfanın web-MT5 bağlantı anlatımı.');await home.close();
 const context=await browser.newContext({viewport:{width:1600,height:1150}});await context.addInitScript(()=>{localStorage.setItem('stratum.language','tr');localStorage.setItem('stratum.cloud-session.v1','report-fixture-no-authority');sessionStorage.setItem('stratum.cloud-session.v1','report-fixture-no-authority');});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
 const installationId='11111111-1111-4111-8111-111111111111';
 const session=()=>({accountId:'report-user',displayName:'Araştırma Tanıtımı',email:'demo@example.test',subscriptionActive:true,entitlementUntil:Date.now()+30*86400000,accessMode:'demo',trial:{startsAt:Date.now()-86400000,expiresAt:Date.now()+29*86400000,daysRemaining:29},installations:[{id:installationId,label:'Tanıtım bağlantısı / emir yetkisi yok',state:'approved'}],lease:{installationId,active:true,controlledHere:true},trading:{enabled:false,jobId:null},terminalStatuses:[{installationId,symbol:'JP225m',brokerServer:'Demo / görsel önizleme',accountLogin:'DEMO',reportedAt:Date.now(),trading:false,openPositions:0,error:''}]});
 await page.route('https://uvzhrrqzzdjqtmydpvwo.supabase.co/functions/v1/stratum-control/**',route=>{
  const path=new URL(route.request().url()).pathname.split('/stratum-control')[1];
  console.log('FIXTURE '+route.request().method()+' '+path);
  if(path==='/v1/auth/session')return route.fulfill({status:200,json:{accessToken:'report-fixture-no-authority'}});
  if(route.request().method()!=='GET'&&path!=='/v1/session')return route.fulfill({status:403,json:{error:'REPORT_CAPTURE_READ_ONLY'}});
  const value=path==='/v1/session'?session():path==='/v1/strategies'?{strategies:[]}:path==='/v1/library/strategies'?{items:cases}:path==='/v1/jobs'?{jobs:[]}:path.includes('/admin/')?{isAdmin:false}:path.includes('/assistant/status')?{providers:{openrouter:{configured:true,model:'Tanıtım / çağrı yapılmıyor'},local:{configured:false,model:null}}}:{};
  return route.fulfill({status:200,json:value});
 });
 await page.goto(base+'/studio/',{waitUntil:'domcontentloaded'});try{await page.locator('.uc-status-grid').waitFor();}catch(e){console.log((await page.locator('body').innerText()).slice(0,5000));throw e;}await shot(page,'#studio-account','web_account','Gerçek üretim UI; kimlik ve bağlantı durumu yalnızca görsel test verisidir.');
 const expert=page.getByRole('button',{name:/Show expert controls|Uzman.*göster|uzman.*kontrol/i});if(await expert.count())await expert.first().click();
 await shot(page,'.uc-settings','web_control_deck','Gerçek üretim kontrol odası; parametreler varsayılan taslak, Trading OFF.');
 await shot(page,'.uc-module-grid','web_control_modules','Gerçek üretim kontrol odası seçicileri; görsel önizleme, emir yetkisi yok.');
 const library=page.locator('.uc-module').filter({hasText:/Strategy library|Strateji.*kütüphane|Strateji kitaplığı/i});await library.first().click();await page.locator('.shared-strategy-library').waitFor();await shot(page,'.console-window','web_strategy_library','Gerçek UI + doğrulanmış MEGA arşiv metrikleri; API yalnızca görsel yakalama için taklit edilmiştir.');
 await shot(page,'.campaign-library-card','web_strategy_result_card','Gerçek üretim strateji kartı + seçili 5Y MEGA arşiv sonucu. Kimlik/erişim görsel test verisidir; yeni audit çalıştırılmadı.');
 await page.keyboard.press('Escape');
 const builder=page.locator('.uc-module').filter({hasText:/Entry builder|Entry oluşturucu|Giriş.*oluştur|Giriş.*atölye/i});if(await builder.count()){await builder.first().click();const example=page.getByRole('button',{name:/Create example draft|Örnek taslak oluştur/i});if(await example.count())await example.first().click();await shot(page,'.console-window','web_entry_builder','Gerçek üretim builder modalı; RSI(14) için eğitim amaçlı BUY/SELL örnek taslağı. Ayarlar sunucuya uygulanmadı, audit veya canlı emir yok.');await page.keyboard.press('Escape');}
 const nas=page.locator('.uc-module').filter({hasText:'NAS'});if(await nas.count()){await nas.first().click();await shot(page,'.console-window','web_nas_controls','Gerçek üretim NAS parametre odası; hiçbir ayar uygulanmadı.');await page.keyboard.press('Escape');}
 const help=page.locator('.uc-core-controls .help-button');if(await help.count()){await help.first().click();await page.locator('.help-window').waitFor();await shot(page,'.help-window','web_animated_lesson','Ayar etkisini anlatan sentetik mum grafiği ve robot; canlı/backtest verisi değildir.');await page.keyboard.press('Escape');}
 const tutorial=page.locator('.activation-launch');if(await tutorial.count()){await tutorial.first().click();await shot(page,'.console-window','web_activation_guide','Gerçek üretim aktivasyon rehberi; adımlar gösterim amaçlı, eşleştirme yapılmadı.');await page.keyboard.press('Escape');}
 await context.close();
 facts.pageErrors=errors;writeFileSync(resolve(out,'evidence_summary.json'),JSON.stringify(facts,null,2));console.log('DONE '+facts.screenshots.length+' screenshots; '+errors.length+' browser errors');
}finally{await browser.close();server.close();await once(server,'close');}
