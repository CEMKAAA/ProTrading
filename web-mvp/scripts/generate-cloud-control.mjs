import ts from 'typescript';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';

const root=resolve(import.meta.dirname,'..'), out=resolve(root,'control-service/cloud/generated');
mkdirSync(out,{recursive:true});
const sources={};
const pure=new Set(['now','ticket','viewJob','conversationSummary','seal','unseal','conversationRow','fetcher']);

// Mechanically preserve the already-tested policy; only the database boundary becomes async.
function convert(file, replacements=[], pureThis=pure, receivers=['this','p','plane']) {
  let code=readFileSync(resolve(root,'control-service',file),'utf8');
  sources[file]=createHash('sha256').update(code).digest('hex');
  for(const [before,after] of replacements){
    if(!code.includes(before))throw new Error('CLOUD_GENERATOR_DRIFT: '+file+' / '+before.slice(0,65));
    code=code.replace(before,after);
  }
  const sf=ts.createSourceFile(file,code,ts.ScriptTarget.Latest,true,ts.ScriptKind.JS);
  const result=ts.transform(sf,[ctx=>{
    const f=ctx.factory;
    const hasOwnAwait=n=>{
      let found=false;
      const walk=x=>{if(x!==n&&ts.isFunctionLike(x))return;if(ts.isAwaitExpression(x))found=true;ts.forEachChild(x,walk);};
      walk(n);return found;
    };
    const asyncModifiers=m=>m?.some(x=>x.kind===ts.SyntaxKind.AsyncKeyword)?m:[...(m??[]),f.createModifier(ts.SyntaxKind.AsyncKeyword)];
    function visit(n){
      let v=ts.visitEachChild(n,visit,ctx);
      if(ts.isCallExpression(v)&&ts.isPropertyAccessExpression(v.expression)){
        const member=v.expression.name.text,receiver=n.expression.expression.getText(sf);
        const target=receivers.includes(receiver)||receiver==='this.plane'||receiver==='this.db';
        if(target&&!pureThis.has(member))v=f.createParenthesizedExpression(f.createAwaitExpression(v));
      }
      if(ts.isArrowFunction(v)&&hasOwnAwait(v.body))v=f.updateArrowFunction(v,asyncModifiers(v.modifiers),v.typeParameters,v.parameters,v.type,v.equalsGreaterThanToken,v.body);
      if(ts.isFunctionExpression(v)&&hasOwnAwait(v.body))v=f.updateFunctionExpression(v,asyncModifiers(v.modifiers),v.asteriskToken,v.name,v.typeParameters,v.parameters,v.type,v.body);
      if(ts.isMethodDeclaration(v)&&hasOwnAwait(v.body))v=f.updateMethodDeclaration(v,asyncModifiers(v.modifiers),v.asteriskToken,v.name,v.questionToken,v.typeParameters,v.parameters,v.type,v.body);
      return v;
    }
    return n=>ts.visitNode(n,visit);
  }]);
  const text='// Generated from canonical policy. Run scripts/generate-cloud-control.mjs; do not edit.\n'+ts.createPrinter().printFile(result.transformed[0]);
  result.dispose();writeFileSync(resolve(out,file),text);
}

convert('control-plane.mjs',[
  ['import { DatabaseSync } from "node:sqlite";',''],
  ['import { readFileSync } from "node:fs";',''],
  ['constructor({ database = ":memory:",','constructor({ db,'],
  ['this.db = new DatabaseSync(database);\n    this.db.exec(readFileSync(new URL("./schema.sql", import.meta.url), "utf8"));','this.db = db;'],
  ['return this.db.prepare(sql).get(...args);','return this.db.get(sql,...args);'],
  ['return this.db.prepare(sql).all(...args);','return this.db.all(sql,...args);'],
  ['return this.db.prepare(sql).run(...args);','return this.db.run(sql,...args);'],
  ['this.db.exec("BEGIN IMMEDIATE");\n    try { const result = work(); this.db.exec("COMMIT"); return result; }\n    catch (error) { this.db.exec("ROLLBACK"); throw error; }','return this.db.atomic(work);'],
  ['this.db.close();','return;'],
  ['rowid DESC','id DESC']
]);
convert('supabase-auth.mjs');
convert('http.mjs',[
  ['import { createServer } from "node:http";','import { createServer } from "../fetch-http.mjs";'],
  ['import { personalPackage,verifiedArtifacts } from "./delivery.mjs";','import { personalPackage,verifiedArtifacts } from "./delivery.mjs";'],
  ['["http://127.0.0.1:4310", "http://localhost:4310"]','["https://cemkaaa.github.io"]'],
  ['if (!["127.0.0.1", "localhost", "[::1]"].some(h => req.headers.host === `${h}:${expected}`)) throw new ControlError("INVALID_HOST", 403);',''],
  ["if(auth&&result.accessToken){cookie(result.accessToken);return reply(path.endsWith('register')?201:200,{accessToken:'cookie-session',expiresAt:result.expiresAt});}",''],
  ["auth?'cookie-session':browserToken()",'browserToken()'],
  ['`http://127.0.0.1:${expected}`','plane.apiUrl,verifiedArtifacts,plane.helperFactory,plane.studioUrl'],
  ['const device = () => {','const device = async () => {'],
  ['device()', '(await device())'],
  ['if (method === "POST" && path === "/v1/pairings") return reply(201, plane.beginPairing(body));','if (method === "POST" && path === "/v1/pairings") throw new ControlError("PERSONAL_PACKAGE_REQUIRED",403);'],
  ["res.setHeader('Set-Cookie',`stratum_session=${value}; Path=/v1; HttpOnly; SameSite=Strict; Max-Age=${maxAge}`)",'undefined']
],pure,['plane']);
// device() occurs at several sites: the initial replacement intentionally replaces only one.
let http=readFileSync(resolve(out,'http.mjs'),'utf8');
http=http.replace(/(?<!await )\bdevice\(\)/g,'(await device())');
writeFileSync(resolve(out,'http.mjs'),http);

convert('delivery.mjs',[
  ["import { readFileSync } from 'node:fs';",''],
  ["import { fileURLToPath } from 'node:url';",''],
  ["import { build } from 'rolldown';",''],
  [readFileSync(resolve(root,'control-service/delivery.mjs'),'utf8').split('const verificationJson=')[1].split('function crc32')[0], "undefined;\nexport async function companion(){throw new ControlError('CLOUD_ARTIFACTS_UNAVAILABLE',503);}\nexport function verifiedArtifacts(plane){return plane.artifacts;}\n"],
  ["'This build uses the LOOPBACK LOCAL PILOT service, not a publicly deployed cloud authorization service.'", "'Cloud authorization is managed by Supabase.'"]
].filter(([s])=>!s.startsWith("'This build")),pure,['plane']);

// Imports into lib move two levels relative to the generated directory.
for(const file of Object.keys(sources)){
  const path=resolve(out,file);let code=readFileSync(path,'utf8');
  code=code.replaceAll('../lib/','../../../lib/');
  code=code.replaceAll('"./crypto.mjs"','"../../crypto.mjs"').replaceAll("'./crypto.mjs'","'../../crypto.mjs'");
  code=code.replaceAll('"./ea-authority.mjs"','"../../ea-authority.mjs"');
  code=code.replaceAll("'./api-location.mjs'","'../../api-location.mjs'");
  code=code.replaceAll("'./studio-agent.mjs'","'../../studio-agent.mjs'");
  code=code.replaceAll('"./subscription-provider.mjs"','"../billing-disabled.mjs"');
  writeFileSync(path,code);
}
writeFileSync(resolve(out,'sources.json'),JSON.stringify(sources,null,2)+'\n');
console.log('Generated cloud control policy from '+Object.keys(sources).length+' canonical modules.');
