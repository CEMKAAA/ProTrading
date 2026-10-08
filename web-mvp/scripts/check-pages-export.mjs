import { existsSync,writeFileSync,readdirSync,readFileSync } from 'node:fs';
import { resolve } from 'node:path';
const root=resolve(import.meta.dirname,'../out');
for(const path of ['index.html','studio/index.html'])if(!existsSync(resolve(root,path)))throw new Error('STATIC_PAGE_MISSING: '+path);
function check(dir){for(const item of readdirSync(dir,{withFileTypes:true})){
 const path=resolve(dir,item.name);if(item.isDirectory()){if(/\.state|control-service|IndicatorCodeExamples/.test(item.name))throw new Error('PRIVATE_DIRECTORY_IN_EXPORT');check(path);}
 else if(/\.(ex5|mq5|mqh|pem|sqlite|env)$/.test(item.name)||item.name==='personal-setup.json')throw new Error('PRIVATE_ARTIFACT_IN_EXPORT');
 else if(/\.(html|js|json)$/.test(item.name)&&/BEGIN (?:RSA |EC |)PRIVATE KEY|sb_secret_|service_role/.test(readFileSync(path,'utf8')))throw new Error('SECRET_MARKER_IN_EXPORT');
}}
check(root);writeFileSync(resolve(root,'.nojekyll'),'');console.log('Static export checked: homepage, Studio and no private EA/server artifacts.');
