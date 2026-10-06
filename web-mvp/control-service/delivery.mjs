import { readFileSync } from 'node:fs';
import { createHash, createPublicKey } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { build } from 'rolldown';
import { signed } from './crypto.mjs';
import { ControlError } from './control-plane.mjs';

const sha = data => createHash('sha256').update(data).digest('hex');
let helper;
async function companion() {
  // One bounded, in-memory build. No user compilation or private EA source export.
  helper ??= build({ input:fileURLToPath(new URL('./personal-setup.mjs',import.meta.url)),platform:'node',
    external:id=>id.startsWith('node:'),write:false,output:{format:'esm',codeSplitting:false},
    onwarn:warning=>{throw new Error(warning.message);} }).then(result=>{
      const chunks=result.output.filter(item=>item.type==='chunk');
      if(chunks.length!==1)throw new Error('COMPANION_BUILD_INVALID');
      return Buffer.from(chunks[0].code);
    }).catch(error=>{helper=undefined;throw error;});
  return helper;
}
export function verifiedArtifacts(plane) {
  try {
    const root=new URL('../../',import.meta.url),dir=new URL('IndicatorCodeExamples/universal/',root);
    const binary=readFileSync(new URL('UniversalConnectionEA.ex5',dir));
    const report=JSON.parse(readFileSync(new URL('tmp/universal_connection_validation/roundtrip-report.json',root)));
    const parity=JSON.parse(readFileSync(new URL('tmp/universal_connection_validation/canonical-parity-report.json',root)));
    if(report.status!=='PASS'||parity.status!=='PASS'||parity.differences.length||report.binarySha256!==sha(binary)||parity.binarySha256!==sha(binary))throw new Error();
    const sources=JSON.parse(readFileSync(new URL('tmp/universal_connection_validation/compile-sources.json',root)));
    for(const item of sources)if(sha(readFileSync(new URL(item.file.replaceAll('\\','/'),dir)))!==item.sha256.toLowerCase())throw new Error();
    const pin=readFileSync(new URL('UniversalAuthorityKey.mqh',dir),'utf8');
    const jwk=createPublicKey(plane.eaSigningKey.publicKey).export({format:'jwk'});
    if(!pin.includes(Buffer.from(jwk.n,'base64url').toString('hex')))throw new Error();
    return {binary,worker:readFileSync(new URL('IndicatorCodeExamples/macrossover_orb/MaCrossOrderFlowWorker.ex5',root))};
  } catch { throw new ControlError('VERIFIED_EA_BUILD_UNAVAILABLE',503); }
}
function crc32(bytes) {
  let crc=0xffffffff;
  for(const byte of bytes){crc^=byte;for(let bit=0;bit<8;bit++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
  return (crc^0xffffffff)>>>0;
}
export function zipFiles(files) {
  const records=[],central=[];let offset=0;
  for(const [path,value] of files){
    if(!/^[a-zA-Z0-9_./-]+$/.test(path)||path.includes('..')||path.startsWith('/'))throw new Error('ZIP_PATH_INVALID');
    const name=Buffer.from(path),bytes=Buffer.isBuffer(value)?value:Buffer.from(value),crc=crc32(bytes);
    const local=Buffer.alloc(30);local.writeUInt32LE(0x04034b50);local.writeUInt16LE(20,4);local.writeUInt16LE(0x800,6);
    local.writeUInt16LE(0x21,12);local.writeUInt32LE(crc,14);local.writeUInt32LE(bytes.length,18);local.writeUInt32LE(bytes.length,22);local.writeUInt16LE(name.length,26);
    const index=Buffer.alloc(46);index.writeUInt32LE(0x02014b50);index.writeUInt16LE(20,4);index.writeUInt16LE(20,6);index.writeUInt16LE(0x800,8);
    index.writeUInt16LE(0x21,14);index.writeUInt32LE(crc,16);index.writeUInt32LE(bytes.length,20);index.writeUInt32LE(bytes.length,24);index.writeUInt16LE(name.length,28);index.writeUInt32LE(offset,42);
    records.push(local,name,bytes);central.push(index,name);offset+=local.length+name.length+bytes.length;
  }
  const directory=Buffer.concat(central),end=Buffer.alloc(22);end.writeUInt32LE(0x06054b50);end.writeUInt16LE(files.length,8);end.writeUInt16LE(files.length,10);end.writeUInt32LE(directory.length,12);end.writeUInt32LE(offset,16);
  return Buffer.concat([...records,directory,end]);
}
export async function personalPackage(plane,accessToken,apiUrl,artifacts=verifiedArtifacts,helperFactory=companion) {
  const actor=plane.browser(accessToken);plane.entitlement(actor.accountId);
  const {binary,worker}=artifacts(plane),code=await helperFactory();
  // Revalidate after the asynchronous build; a session can be revoked meanwhile.
  const ticket=plane.issueEnrollment(accessToken),access=plane.accessState(actor.accountId);
  const files=[['MQL5/Experts/StratumUniversal/UniversalConnectionEA.ex5',binary],
    ['MQL5/Indicators/MaCrossOrderFlowWorker.ex5',worker],['connection.mjs',code],
    ['start_connection.bat','@echo off\r\nsetlocal\r\npushd "%~dp0"\r\nwhere node >nul 2>&1\r\nif errorlevel 1 (\r\n echo Install Node.js 22.13 or newer: https://nodejs.org/en/download\r\n pause\r\n exit /b 1\r\n)\r\nnode connection.mjs\r\nif errorlevel 1 pause\r\npopd\r\n']];
  const payload={version:1,kind:'personal_setup',accountId:actor.accountId,subscriberName:plane.displayName(actor.accountId),
    apiUrl,enrollmentToken:ticket.enrollmentToken,expiresAt:ticket.expiresAt,issuedAt:plane.now(),
    accessMode:access.accessMode,trialExpiresAt:access.trial?.expiresAt??null,
    artifacts:files.map(([name,data])=>({name,sha256:sha(data)}))};
  files.push(['personal-setup.json',JSON.stringify({envelope:signed(payload,plane.signingKey.privateKey),serverPublicKey:plane.signingKey.publicKey},null,2)],
    ['READ_ME.txt',`STRATUM / PERSONAL CONNECTION\r\n\r\n1. Install MetaTrader 5 from your broker or https://www.metatrader5.com/en/download\r\n2. Extract this ZIP into a private folder. Do not share it: its setup ticket is single-use and expires in 30 minutes. Download again if it expires; this never resets your demo.\r\n3. Install Node.js 22.13+ from https://nodejs.org/en/download if needed.\r\n4. Run start_connection.bat. It generates this computer's device key and shows a pairing code and fingerprint.\r\n5. In YOUR Studio account, open Pair / Manage MT5. Review the code and compare the fingerprint, then approve. Only this package's account can approve.\r\n6. In MT5 use File > Open Data Folder. Copy this package's MQL5 folder contents into that folder (not necessarily the MT5 program directory). Refresh Navigator.\r\n7. Attach StratumUniversal/UniversalConnectionEA to the desired chart. Load .state/connection.set under Inputs; or enter the displayed InpInstallationId.\r\n8. Keep the helper running. In Studio choose your installation and Authorize Controller, then Apply & Run MT5 Audit. Trading starts OFF; only explicitly turn ON after inspecting a complete audit.\r\n\r\nDEMO is 30 days from registration, not installation. Expiry stops new research/entries; existing protective position management remains.\r\nThe EX5 is generic and closed-source. User isolation is enforced by server-owned entitlement, owner-bound pairing, local device keys and short-lived signed commands, NOT a name embedded in an EX5.\r\nNo compiler, terminal binaries, broker credentials or server private keys are included.\r\nThis build uses the LOOPBACK LOCAL PILOT service, not a publicly deployed cloud authorization service.\r\n`]);
  return {bytes:zipFiles(files),filename:`Stratum-${actor.accountId.slice(0,8)}.zip`};
}
