import { readFileSync,existsSync,mkdirSync,writeFileSync,renameSync,unlinkSync } from 'node:fs';
import { resolve,dirname,join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes,createHash } from 'node:crypto';
import { keyPair,signed,verifySigned } from './crypto.mjs';
import { runAgent } from './mt5-agent.mjs';
import { DeviceClient } from './device-client.mjs';

export async function setupConnection(packageRoot=dirname(fileURLToPath(import.meta.url)),{commonFiles=join(process.env.APPDATA??'','MetaQuotes/Terminal/Common/Files')}={}) {
  const [major,minor]=process.versions.node.split('.').map(Number);
  if(major<22||(major===22&&minor<13))throw new Error('NODE_22_13_OR_NEWER_REQUIRED');
  const {envelope,serverPublicKey}=JSON.parse(readFileSync(join(packageRoot,'personal-setup.json'),'utf8'));
  if(!verifySigned(envelope,serverPublicKey))throw new Error('PACKAGE_SIGNATURE_INVALID');
  const p=envelope.payload,url=new URL(p.apiUrl);
  if(url.protocol!=='https:'&&!(url.protocol==='http:'&&['127.0.0.1','localhost'].includes(url.hostname)))throw new Error('HTTPS_REQUIRED');
  if(url.origin!==p.apiUrl)throw new Error('API_ORIGIN_REQUIRED');
  for(const artifact of p.artifacts){
    if(!/^[A-Za-z0-9_./-]+$/.test(artifact.name)||artifact.name.includes('..')||artifact.name.startsWith('/'))throw new Error('PACKAGE_PATH_INVALID');
    if(createHash('sha256').update(readFileSync(join(packageRoot,artifact.name))).digest('hex')!==artifact.sha256)throw new Error('PACKAGE_ARTIFACT_CHANGED');
  }
  const state=join(packageRoot,'.state');mkdirSync(state,{recursive:true});
  const configFile=join(state,'installation.json'),keyFile=join(state,'device-key.json');
  if(!existsSync(configFile)){
    if(p.expiresAt<=Date.now())throw new Error('SETUP_TICKET_EXPIRED_DOWNLOAD_AGAIN');
    const keys=existsSync(keyFile)?JSON.parse(readFileSync(keyFile,'utf8')):keyPair();
    if(!existsSync(keyFile))writeFileSync(keyFile,JSON.stringify(keys),{mode:0o600});
    const body={enrollmentToken:p.enrollmentToken,publicKey:keys.publicKey,label:`MT5 / ${p.subscriberName}`.slice(0,80)};
    const res=await fetch(url.origin+'/v1/ea/enroll',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({...body,signature:signed(body,keys.privateKey).signature}),redirect:'error',signal:AbortSignal.timeout(10000)});
    const pair=await res.json();if(!res.ok)throw new Error(pair.error);
    if(pair.accountId!==p.accountId)throw new Error('PACKAGE_OWNER_MISMATCH');
    const folder=join(commonFiles,'Stratum',pair.installationId);mkdirSync(folder,{recursive:true});
    writeFileSync(join(folder,'local.key'),randomBytes(16).toString('hex'),{mode:0o600});
    const config={apiUrl:url.origin,installationId:pair.installationId,pinnedServerPublicKey:serverPublicKey,folder,
      accountId:p.accountId,pairingCode:pair.code,pairingExpiresAt:pair.expiresAt,fingerprint:pair.fingerprint};
    writeFileSync(configFile+'.pending',JSON.stringify(config),{mode:0o600});renameSync(configFile+'.pending',configFile);
    writeFileSync(join(state,'connection.set'),Buffer.concat([Buffer.from([0xff,0xfe]),Buffer.from(`InpInstallationId=${pair.installationId}\r\n`,'utf16le')]),{mode:0o600});
    // The used enrollment secret is no longer needed on disk.
    unlinkSync(join(packageRoot,'personal-setup.json'));writeFileSync(join(state,'owner.json'),JSON.stringify({accountId:p.accountId,subscriberName:p.subscriberName}));
    return {state,config};
  }
  return {state,config:JSON.parse(readFileSync(configFile,'utf8'))};
}
export async function prepareConnection(root,options={}){
  // After first activation, resume using the local device key, never the ticket.
  let value;
  if(existsSync(join(root,'.state/installation.json'))){
    value={state:join(root,'.state'),config:JSON.parse(readFileSync(join(root,'.state/installation.json'),'utf8'))};
  }else value=await setupConnection(root,options);
  const keys=JSON.parse(readFileSync(join(value.state,'device-key.json'),'utf8'));
  const client=new DeviceClient({...value.config,privateKey:keys.privateKey});
  const status=client.verified(await client.request('/v1/device/pairing/refresh',{code:value.config.pairingCode??null}),'pairing_status');
  if(status.accountId!==value.config.accountId||status.fingerprint!==createHash('sha256').update(keys.publicKey).digest('hex'))throw new Error('PACKAGE_OWNER_MISMATCH');
  if(!['pending','approved'].includes(status.state))throw new Error('PAIRING_STATUS_INVALID');
  if(status.state==='pending'&&(!/^[A-F0-9]{4}-[A-F0-9]{4}$/.test(status.pairingCode??'')||status.pairingExpiresAt<=Date.now()))throw new Error('PAIRING_STATUS_INVALID');
  value.config={...value.config,pairingCode:status.pairingCode,pairingExpiresAt:status.pairingExpiresAt,fingerprint:status.fingerprint,pairingState:status.state};
  const configFile=join(value.state,'installation.json');
  writeFileSync(configFile+'.pending',JSON.stringify(value.config),{mode:0o600});renameSync(configFile+'.pending',configFile);
  return value;
}
async function main(){
  const root=dirname(fileURLToPath(import.meta.url));
  const value=await prepareConnection(root);
  const pairing=value.config.pairingState==='approved'?'Device already approved. Select it and authorize this browser in Studio.':
    `Pairing code: ${value.config.pairingCode}\nCode expires: ${new Date(value.config.pairingExpiresAt).toLocaleString()} (5-minute validity)\nApprove in your own Studio account. If the code expires, Ctrl+C and restart this same BAT for a fresh code.`;
  console.log(`\nSTRATUM / PERSONAL MT5 CONNECTION\nStudio: http://127.0.0.1:4310/studio\n${pairing}\nFingerprint: ${value.config.fingerprint}\nInpInstallationId: ${value.config.installationId}\nInputs preset: ${join(value.state,'connection.set')}\nKeep this window open. Ctrl+C stops the helper, not protective SL/TP.\n`);
  await runAgent(['watch','--state',value.state]);
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{console.error(error.message);process.exitCode=1;});
