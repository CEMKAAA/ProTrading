import {chromium} from 'playwright';
import {readFileSync,readdirSync,mkdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'../../..');
const assets=resolve(root,'output/pdf/STRATUM_Referans_Paketi_20261011/assets');
const render=resolve(import.meta.dirname,'template-render');
mkdirSync(render,{recursive:true});
const browser=await chromium.launch({headless:true});
const page=await browser.newPage({viewport:{width:1920,height:1080}});
const checked=[];
try{
  for(const file of readdirSync(assets).filter(f=>/^T\d\d_.*\.svg$/.test(f))){
    await page.setContent('<style>body{margin:0}</style>'+readFileSync(resolve(assets,file),'utf8'));
    await page.screenshot({path:resolve(render,file.replace('.svg','.png'))});
    const issues=await page.locator('svg text').evaluateAll(nodes=>nodes.map(n=>({text:n.textContent,box:n.getBBox()})).filter(({box})=>box.x<0||box.y<0||box.x+box.width>1920||box.y+box.height>1080));
    checked.push({file,issues});
  }
  writeFileSync(resolve(import.meta.dirname,'templates_check.json'),JSON.stringify(checked,null,2));
  console.log(JSON.stringify(checked));
}finally{await browser.close();}
