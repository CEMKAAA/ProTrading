import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { heroPose, marketPose, clampProgress } from "../lib/scene-motion.ts";

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
