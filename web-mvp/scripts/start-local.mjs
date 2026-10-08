import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, openSync, closeSync } from 'node:fs';
import { createConnection } from 'node:net';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
const logs=join(root,'logs');
const dashboard='http://127.0.0.1:4310/studio/';
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const owned=[];
let stopping=false,shutdown=null,keepAlive=null;

async function stopOwned(){
  if(shutdown)return shutdown;
  stopping=true;
  console.log('\nStopping services started by this launcher...');
  shutdown=(async()=>{
    if(keepAlive)clearInterval(keepAlive);
    for(const child of owned){
      if(child.exitCode!==null||child.signalCode!==null)continue;
      if(child.connected)child.send('stratum-shutdown',()=>{});
      await Promise.race([new Promise(resolve=>child.once('exit',resolve)),delay(4000)]);
      if(child.exitCode===null&&child.signalCode===null){
        if(process.platform==='win32'){
          // Only a still-owned child PID and its descendants, never all Node processes.
          await new Promise(resolve=>{
            const killer=spawn('taskkill.exe',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
            killer.once('error',resolve);killer.once('exit',resolve);
          });
        }else child.kill('SIGTERM');
      }
    }
    console.log('Launcher services stopped. Pre-existing services were left running.');
  })();
  return shutdown;
}
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>stopOwned().then(()=>process.exit(0)));

function listening(port){
  return new Promise((resolve,reject)=>{
    const socket=createConnection({host:'127.0.0.1',port});
    socket.setTimeout(1500);
    socket.once('connect',()=>{socket.destroy();resolve(true);});
    socket.once('error',error=>{
      socket.destroy();if(error.code==='ECONNREFUSED')resolve(false);else reject(error);
    });
    socket.once('timeout',()=>{socket.destroy();reject(new Error(`Port ${port} did not respond.`));});
  });
}

async function ready(service){
  const response=await fetch(service.url,{signal:AbortSignal.timeout(4000),redirect:'error'});
  if(!response.ok)return false;
  if(service.name==='control'){
    const value=await response.json();
    return value.service==='stratum-control'&&value.authMode==='supabase'&&value.liveTradingDefault===false;
  }
  return /<title[^>]*>[^<]*\bStratum\b[^<]*<\/title>/i.test(await response.text());
}

async function start(service){
  if(await listening(service.port)){
    if(!await ready(service))throw new Error(`Port ${service.port} is occupied by an unrecognized/unready service. No process was stopped.`);
    console.log(`${service.name}: already running (${service.port}); not owned by this launcher.`);return;
  }
  const logfile=join(logs,`${service.name}.log`),fd=openSync(logfile,'w');
  let child;
  try{
    child=spawn(process.execPath,['--experimental-strip-types','scripts/local-server.mjs',service.name,...service.args],
      {cwd:root,detached:true,windowsHide:true,stdio:['ignore',fd,fd,'ipc']});
    owned.push(child);
  }finally{closeSync(fd);}
  let failed=null;
  child.once('error',error=>failed=error);
  child.once('exit',code=>{
    failed=new Error(`${service.name} exited (${code}); see ${logfile}`);
    if(keepAlive&&!stopping){console.error(failed.message);stopOwned().then(()=>process.exit(1));}
  });
  const deadline=Date.now()+120000;
  while(Date.now()<deadline){
    if(stopping)throw new Error('Startup cancelled.');
    if(failed)throw failed;
    if(await ready(service).catch(()=>false)){
      console.log(`${service.name}: ready (${service.port}), PID ${child.pid}.`);return;
    }
    await delay(500);
  }
  throw new Error(`${service.name} did not become ready; see ${logfile}.`);
}

async function main(){
  if(process.argv.slice(2).some(a=>a!=='--no-browser'))throw new Error('Only --no-browser is supported.');
  const [major,minor]=process.versions.node.split('.').map(Number);
  if(major<22||major===22&&minor<13)throw new Error('Node.js 22.13 or newer is required.');
  if(process.env.NODE_ENV==='production')throw new Error('This launcher is local-development only. NODE_ENV=production is not allowed.');
  if(!existsSync(join(root,'node_modules/vinext/dist/cli.js')))throw new Error('Web dependencies are missing. Run npm install in web-mvp first.');
  mkdirSync(logs,{recursive:true});
  await start({name:'control',port:4321,url:'http://127.0.0.1:4321/health',
    args:['--supabase']});
  await start({name:'web',port:4310,url:dashboard,
    args:['dev','--host','127.0.0.1','--port','4310']});
  console.log(`Dashboard: ${dashboard}`);
  console.log('MT5 and live trading are NOT started by this launcher.');
  console.log('Keep this window open. Press Ctrl+C to stop its services.');
  keepAlive=setInterval(()=>{},1000);
  if(!process.argv.includes('--no-browser')){
    const browser=spawn('rundll32.exe',['url.dll,FileProtocolHandler',dashboard],
      {detached:true,windowsHide:true,stdio:'ignore'});
    browser.once('error',error=>console.error(`Browser could not open: ${error.message}. Open ${dashboard} manually.`));
    browser.unref();
  }
}
main().catch(async error=>{console.error(`ERROR: ${error.message}`);await stopOwned();process.exitCode=1;});
