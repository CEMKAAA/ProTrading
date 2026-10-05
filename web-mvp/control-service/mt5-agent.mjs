// One companion handles asymmetric server proofs; the EX5 owns all market math.
import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync, unlinkSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { DeviceClient } from "./device-client.mjs";
import { keyPair, hash } from "./crypto.mjs";
import { universalConfigurationSchema, UNIVERSAL_RUNTIME } from "../lib/universal-contract.ts";

export function packet(body,key){return body+"\nHMAC="+createHmac("sha256",key).update(body).digest("hex");}
export function unpack(text,key){
  const at=text.lastIndexOf("\nHMAC=");if(at<0)throw new Error("LOCAL_PROOF_MISSING");
  const body=text.slice(0,at),signature=text.slice(at+6),expected=createHmac("sha256",key).update(body).digest();
  if(!/^[a-f0-9]{64}$/.test(signature)||!timingSafeEqual(expected,Buffer.from(signature,"hex")))throw new Error("LOCAL_PROOF_INVALID");
  return {body,fields:Object.fromEntries(body.split("\n").filter(l=>l.includes("=")).map(l=>[l.slice(0,l.indexOf("=")),l.slice(l.indexOf("=")+1)]))};
}
export function commandBody(kind,ticket,expiresAt=Date.now()+15000){
  const c=universalConfigurationSchema.parse(ticket.request.configuration),r=ticket.request;
  const rows=[`command=${kind}`,`issued=${Math.floor(Date.now()/1000)}`,`expires=${Math.floor(Math.min(expiresAt,Date.now()+15000)/1000)}`,
    `family=${c.family}`,`name=${c.name}`,`symbol=${r.symbol}`,`brokerServer=${r.brokerServer}`,`configurationHash=${ticket.configurationHash}`,
    `requestHash=${ticket.requestHash??hash(r)}`,`jobId=${ticket.jobId??""}`,`attemptId=${ticket.attemptId??""}`,`from=${Date.parse(r.fromUtc)/1000}`,`to=${Date.parse(r.toUtc)/1000}`,`weeks=${r.auditWeeks}`];
  for(const [k,v] of Object.entries(c.inputs))rows.push(`i.${k}=${v}`);
  for(const [k,v] of Object.entries(c.runtime))rows.push(`r.${k}=${v}`);
  c.dayHourMasks.forEach((mask,i)=>rows.push(`m.${i}=${mask}`));
  if(c.builder){for(const [k,v] of Object.entries(c.builder)){
    if(!Array.isArray(v))rows.push(`b.${k}=${v}`);
    else {rows.push(`b.${k}.count=${v.length}`);v.forEach((r,i)=>rows.push(`b.${k}.${i}=${[r.feature,r.comparator,r.threshold,r.gate,r.negate,r.period,r.rhsFeature,r.rhsPeriod].join(",")}`));}
  }}
  return rows.join("\n");
}
const iso=seconds=>new Date(Number(seconds)*1000).toISOString();
export function parseResult(text,key,ticket){
  const {body,fields:f}=unpack(text,key);
  if(f.jobId!==ticket.jobId||f.attemptId!==ticket.attemptId)throw new Error("LOCAL_STALE_RESULT");
  if(f.error)throw new Error(f.error);
  if(f.configurationHash!==ticket.configurationHash||f.requestHash!==ticket.requestHash)throw new Error("LOCAL_CONFIG_MISMATCH");
  const tradeText=body.split("\nTRADES\n")[1];if(tradeText===undefined)throw new Error("LOCAL_RESULT_FORMAT");
  const from=Date.parse(ticket.request.fromUtc),to=Date.parse(ticket.request.toUtc);
  const rows=tradeText.trim()?tradeText.trimEnd().split("\n"):[];
  if(rows.length!==Number(f.rows)||rows.length>10000)throw new Error("LOCAL_ROW_COUNT_MISMATCH");
  const missing=[];
  const trades=rows.map((row,i)=>{
    const v=row.split("|");if(v.length!==13)throw new Error("LOCAL_RESULT_FORMAT");
    const valid=v[9]==="1",closed=v[10]==="1",netR=Number(v[8]),entryUtc=iso(v[1]);
    if(!valid)missing.push({fromUtc:new Date(from).toISOString(),toUtc:new Date(to).toISOString()});
    const outcome=!valid?"DATA":!closed?"OPEN":netR>0?"WIN":netR<0?"LOSS":"FLAT";
    let exitReason=outcome==="DATA"?"DATA":outcome==="OPEN"?"OPEN":/nas/i.test(v[11])?"NAS":/reverse/i.test(v[11])?"REVERSE":/TP/i.test(v[11])?"TP":/SL|stop/i.test(v[11])?"SL":/time|eod/i.test(v[11])?"TIME":"OTHER";
    return {id:String(i+1),direction:Number(v[3])>0?"BUY":"SELL",signalUtc:iso(v[0]),entryUtc,
      exitUtc:valid&&closed?iso(v[2]):null,entryPrice:Number(v[4]),sl:Number(v[5]),tp:Number(v[6]),exitPrice:valid&&closed?Number(v[7]):null,
      outcome,exitReason,netR:valid&&closed?netR:null,spreadPrice:v[12]===""?null:Number(v[12]),slippagePrice:null,commission:null,swap:null};
  });
  return {jobId:ticket.jobId,attemptId:ticket.attemptId,configurationHash:ticket.configurationHash,requestHash:ticket.requestHash,
    engineRuntime:UNIVERSAL_RUNTIME,auditBuild:"canonical-bundle/v1",brokerServer:ticket.request.brokerServer,symbol:ticket.request.symbol,
    coverage:{datasetFingerprint:hash(tradeText),realTicks:0,generatedTicks:0,mode:"existing_audit",missingIntervals:missing},trades};
}
function atomic(path,text){writeFileSync(path+".partial",text);renameSync(path+".partial",path);}
export async function runAgent(argv=process.argv.slice(2)){
  const mode=argv[0],value=name=>{const i=argv.indexOf(name);return i>=0?argv[i+1]:null;};
  const state=resolve(value("--state")??fileURLToPath(new URL("./.state/agent",import.meta.url)));
  mkdirSync(state,{recursive:true});
  const configFile=join(state,"installation.json"),keyFile=join(state,"device-key.json");
  const common=resolve(value("--common-files")??join(process.env.APPDATA??"", "MetaQuotes/Terminal/Common/Files"));
  if(mode==="pair"){
    if(existsSync(configFile))throw new Error("INSTALLATION_ALREADY_PAIRED");
    const api=new URL(value("--api")??"http://127.0.0.1:4321");
    if(api.protocol!=="https:"&&!(api.protocol==="http:"&&["localhost","127.0.0.1"].includes(api.hostname)))throw new Error("HTTPS_REQUIRED");
    const serverKey=readFileSync(resolve(value("--server-key")??fileURLToPath(new URL("./.state/server-public.pem",import.meta.url))),"utf8");
    const keys=keyPair();
    const res=await fetch(api.origin+"/v1/pairings",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({publicKey:keys.publicKey,label:value("--label")??"MT5 universal terminal"}),redirect:"error",signal:AbortSignal.timeout(10000)});
    const pair=await res.json();if(!res.ok)throw new Error(pair.error);
    const folder=join(common,"Stratum",pair.installationId);mkdirSync(folder,{recursive:true});
    const localKey=randomBytes(16).toString("hex");writeFileSync(join(folder,"local.key"),localKey,{mode:0o600});
    writeFileSync(keyFile,JSON.stringify(keys),{mode:0o600});
    writeFileSync(configFile,JSON.stringify({apiUrl:api.origin,installationId:pair.installationId,pinnedServerPublicKey:serverKey,folder},null,2),{mode:0o600});
    console.log(JSON.stringify({installationId:pair.installationId,pairingCode:pair.code,fingerprint:pair.fingerprint,eaInput:"InpInstallationId",pairingExpiresAt:pair.expiresAt},null,2));return;
  }
  if(mode!=="watch")throw new Error("Use pair or watch");
  const config=JSON.parse(readFileSync(configFile,"utf8")),keys=JSON.parse(readFileSync(keyFile,"utf8"));
  const client=new DeviceClient({...config,privateKey:keys.privateKey}),key=readFileSync(join(config.folder,"local.key"),"utf8");
  let active=null,lastProgress="",lastPhase="preparing",phaseDone=0,stopping=false;
  const stopPacket=()=>packet(`command=stop\nissued=${Math.floor(Date.now()/1000)}\nexpires=${Math.floor(Date.now()/1000)+10}`,key);
  process.on("SIGINT",()=>{stopping=true;});process.on("SIGTERM",()=>{stopping=true;});
  console.log("MT5 agent watching. Apply performs research only. No Trading ON is requested by this process.");
  while(!stopping){
    try{
      await client.heartbeat();
      const statusFile=join(config.folder,"status.txt");
      if(existsSync(statusFile)){
        const f=unpack(readFileSync(statusFile,"utf8"),key).fields;
        if(Number(f.at)*1000<Date.now()-15000)throw new Error("TERMINAL_OFFLINE");
        await client.request("/v1/device/status",{symbol:f.symbol,brokerServer:f.brokerServer,accountLogin:f.accountLogin,runtime:UNIVERSAL_RUNTIME,build:"canonical-bundle/v1",
          openPositions:Number(f.openPositions),trading:f.trading==="true",configurationHash:f.configurationHash,error:f.error});
      }else throw new Error("ATTACH_CONNECTION_EA");
      if(active&&active.generation!==client.lease.generation)active=null;
      if(!active){active=await client.claim();lastProgress="";lastPhase="preparing";phaseDone=0;}
      if(active){
        if(active.request.version!==2){await client.request("/v1/device/failure",{jobId:active.jobId,attemptId:active.attemptId,code:"UNSUPPORTED_V1_CONFIG"});active=null;}
        else{
          const resultFile=join(config.folder,"result.txt");
          let resultText=existsSync(resultFile)?readFileSync(resultFile,"utf8"):null;
          if(resultText&&unpack(resultText,key).fields.jobId===active.jobId){
            try {const result=parseResult(resultText,key,active);await client.request("/v1/device/result",result);}
            catch(error){if(!/STALE_JOB|LEASE|ENTITLEMENT/.test(error.message))await client.request("/v1/device/failure",{jobId:active.jobId,attemptId:active.attemptId,code:/^[A-Z0-9_]{1,80}$/.test(error.message)?error.message:"RESULT_VALIDATION_FAILED"});else throw error;}
            unlinkSync(resultFile);active=null;
          }else{
            atomic(join(config.folder,"command.txt"),packet(commandBody("audit",active,client.lease.expiresAt),key));
            const progressFile=join(config.folder,"progress.txt");let phase="preparing",processed=0,total=null;
            if(existsSync(progressFile)){
              const p=unpack(readFileSync(progressFile,"utf8"),key).fields;
              if(p.jobId===active.jobId&&p.attemptId===active.attemptId){phase=p.phase;processed=Number(p.processed);total=Number(p.total)||null;}
            }
            // Download retries may return to a preparation stage; do not lie by
            // resetting monotonic replay progress or publishing a fake percentage.
            const order=["preparing","downloading","replaying","uploading"];
            if(order.indexOf(phase)<order.indexOf(lastPhase)){phase=lastPhase;processed=phaseDone;total=phase==="replaying"?100:null;}
            if(phase===lastPhase)processed=Math.max(processed,phaseDone);else phaseDone=0;
            await client.request("/v1/device/progress",{jobId:active.jobId,attemptId:active.attemptId,phase,processed,total});
            lastPhase=phase;phaseDone=processed;lastProgress=phase;
          }
        }
      }
      if(!active){const operation=await client.operation();atomic(join(config.folder,"command.txt"),operation.liveTradingAllowed?packet(commandBody("live",operation,operation.expiresAt),key):stopPacket());}
    }catch(error){
      atomic(join(config.folder,"command.txt"),stopPacket());
      if(/STALE_JOB|CONTROLLER|ENTITLEMENT|PAIRING|CONFIG_MISMATCH/.test(error.message))active=null;
      console.error("Connection standby:",error.message);
    }
    await new Promise(r=>setTimeout(r,2000));
  }
  atomic(join(config.folder,"command.txt"),stopPacket());
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))runAgent().catch(e=>{console.error(e.message);process.exitCode=1;});
