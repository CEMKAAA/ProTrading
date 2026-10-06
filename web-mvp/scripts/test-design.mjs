import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { heroPose, marketPose, clampProgress, studioCoinPose, chapterPose } from "../lib/scene-motion.ts";
import { createRequire } from "node:module";
import { runInNewContext } from "node:vm";
import ts from "typescript";
import { renderToStaticMarkup } from "react-dom/server";

assert.equal(clampProgress(-1),0);
assert.equal(clampProgress(2),1);
assert.ok(heroPose(1).y-heroPose(0).y>2*Math.PI,"Scroll produces more than a complete turn, not a small tilt");
assert.ok(heroPose(0,3).y>heroPose(0,0).y,"Hero autoplays before the visitor scrolls");
assert.ok(marketPose(0,.5,3).rotation>marketPose(0,.5,0).rotation,"Market tokens also autoplay");
for(let i=0;i<4;i++) {
 const a=marketPose(i,.2,0), b=marketPose(i,.8,0);
 assert.notDeepEqual(a,b,"Each token moves through scroll, independent of elapsed animation time");
 for(const v of Object.values(a))assert.ok(Number.isFinite(v));
}
assert.notDeepEqual(marketPose(0,.5,0),marketPose(1,.5,0),"Tokens have staggered positions");
const css=readFileSync(new URL("../app/globals.css",import.meta.url),"utf8");
assert.ok(css.includes("color-scheme: light"));
assert.ok(css.includes("--type-caption: .875rem"),"Minimum UI type is 14px at default root size");
assert.ok(css.includes("--type-body: 1.125rem"),"Body type uses the shared 18px token");
assert.ok(css.includes("prefers-reduced-motion"));
const heroRules=[...css.matchAll(/\.hero(?:-inner)?\s*\{([^}]+)\}/g)].map(match=>match[1]);
assert.ok(heroRules.length>=2);
for(const rule of heroRules) {
 assert.ok(!/position:\s*(?:sticky|fixed)/.test(rule),"The intro must scroll with the page, not stay pinned");
 assert.ok(!/\b1[1-9]\d(?:d?vh)\b/.test(rule),"No oversized intro spacer holds up the first scroll");
}
assert.ok(!/font-size:\s*(?:[0-9]|1[01])px/.test(css),"No ant-sized 8-11px UI overrides");
const coin=readFileSync(new URL("../components/quant-core.tsx",import.meta.url),"utf8");
assert.ok(coin.includes("InstancedMesh"));
assert.ok(coin.includes("document.hidden"));
assert.ok(!coin.includes("window.scrollY"),"Motion owns continuous scroll progress");
assert.ok(coin.includes('offset: ["start end", "end start"]'),"Rotation follows the scene through the viewport without a pinned scroll phase");
assert.ok(!coin.includes("Enable 3D motion"),"No enable button is needed for autoplay");
assert.ok(coin.includes('element.dataset.sceneMotion = "enabled"'),"Requested scene autoplay is explicit");
assert.ok(!coin.includes("!reduced && <button"),"Device preference does not change the server/client element tree");
const preference=readFileSync(new URL("../lib/use-motion-preference.ts",import.meta.url),"utf8");
assert.ok(preference.includes("useSyncExternalStore"));
assert.ok(preference.includes("serverSnapshot = () => false"),"First hydration snapshot matches SSR");
function luminance(hex) {
 const rgb=hex.match(/[a-f0-9]{2}/gi).map(v=>parseInt(v,16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);
 return .2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2];
}
for(const [foreground,background] of [["#536777","#f6faff"],["#536777","#e4f2fc"],["#8b6000","#e4f2fc"],["#182c3d","#ffce51"]]) {
 const a=luminance(foreground),b=luminance(background);
 assert.ok((Math.max(a,b)+.05)/(Math.min(a,b)+.05)>=4.5,"Shared UI colors meet AA text contrast");
}
console.log("PASS: scroll rotation, staggered market poses, shared light tokens, readable type scale, reduced motion, instanced geometry, AA token contrast.");

for (const viewWidth of [9, 16, 24]) {
 const count = 5;
 for (let i=0;i<count;i++) {
  for (let t=0;t<100;t+=.25) {
   const a=studioCoinPose(i,count,viewWidth,t),b=studioCoinPose(i,count,viewWidth,t+.01);
   if(b.x<a.x)assert.ok(Math.abs(a.x)>viewWidth/2+2 && Math.abs(b.x)>viewWidth/2+2,"Coins wrap outside the visible camera");
   else assert.ok(Math.abs(b.x-a.x-.0072)<1e-10,"Coins travel continuously at constant speed, not in a bobbing loop");
   assert.ok(b.rotationY>a.rotationY,"Coin rotation also continues without scrolling");
   for(const v of Object.values(a))assert.ok(Number.isFinite(v));
  }
 }
}
assert.ok(chapterPose(0).y>chapterPose(.3).y,"Incoming section rises into position");
assert.equal(chapterPose(.3).scale,1,"In-view section is full-size and legible");
assert.equal(chapterPose(.3).radius,0);
assert.ok(chapterPose(1).scale<chapterPose(.5).scale,"Outgoing section recedes");
const leverSource=readFileSync(new URL("../components/lever-switch.tsx",import.meta.url),"utf8");
const compiled=ts.transpileModule(leverSource,{compilerOptions:{module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
const exports={};runInNewContext(compiled,{exports,require:createRequire(import.meta.url)});
for(const checked of [false,true]) {
 let change=null;
 const element=exports.default({label:"Reverse signal exit",checked,onChange:value=>{change=value;}});
 const html=renderToStaticMarkup(element);
 assert.ok(html.includes('role="switch"'));
 assert.ok(html.includes(`aria-checked="${checked}"`));
 assert.ok(html.includes('aria-label="Reverse signal exit"'));
 assert.ok(html.includes(checked?"Enabled":"Disabled"));
 assert.equal(element.props.type,"button","Switches never accidentally submit an auth form");
 element.props.onClick();assert.equal(change,!checked,"Switch forwards a real boolean configuration edit");
}
const consoleSource=readFileSync(new URL("../components/console-window.tsx",import.meta.url),"utf8");
assert.ok(consoleSource.includes("<Dialog.Overlay")&&consoleSource.includes("<Dialog.Content"),"Modal uses focus-trapped primitives and a blocking overlay");
assert.ok(consoleSource.includes("onCloseAutoFocus")&&consoleSource.includes("returnFocus.current.focus()"),"Closing restores focus to the launch control");
assert.ok(css.includes("console-window-out")&&css.includes("console-window-in"),"Both directions of the window transition exist");
assert.ok(css.includes("rotateZ(180deg)")&&css.includes("rotateZ(0deg)"),"Lever has distinct physical down and up positions");
const launch=readFileSync(new URL("../components/launch-page.tsx",import.meta.url),"utf8");
assert.equal((launch.match(/<ScrollChapter(?: |>|\n)/g)??[]).length,7,"All post-hero chapters use the scroll transition");
assert.equal((launch.match(/<\/ScrollChapter>/g)??[]).length,7);
console.log("PASS: continuous five-market flow, offscreen wrapping, chapter progression, real boolean lever edits, accessible modal close and focus restoration.");
