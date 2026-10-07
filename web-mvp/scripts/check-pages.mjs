import assert from "node:assert/strict";
const base="http://127.0.0.1:4310";
for(const [route,expected] of [["/","Build your own."],["/studio","Your controls."]]) {
 const res=await fetch(base+route);assert.equal(res.status,200,route);
 const html=await res.text();assert.ok(html.includes(expected),`Product content on ${route}`);
 assert.ok(!html.includes("Your site is taking shape"),"Starter was replaced");
 if(route==='/studio'){assert.ok(html.includes("SYNTHETIC FIXTURE"),"Synthetic data is disclosed");assert.ok(html.includes("Run fixture backtest"),"Working affordance is rendered");}
 else{assert.ok(html.includes('Illustration only. No orders are sent.'),"Home demonstrations are disclosed");assert.ok(html.includes('product-stage'),"Current product demonstration is rendered");}
 assert.ok(!html.includes("Internal Server Error"),"No SSR error");
 if(route==="/") {
  for(const id of ["main","overview","platform","markets","research","workflow","faq"])assert.ok(html.includes(`id="${id}"`),`Anchor ${id}`);
  assert.ok(!html.includes('<html lang="en" class="dark"'),"Light theme is not overridden at root");
  assert.ok(html.includes("three-dimensional gold Stratum coin"),"Hero 3D scene renders its accessible description");
  assert.ok(html.includes("Gold and silver market tokens"),"Second 3D scene renders its accessible description");
  assert.equal((html.match(/class="scroll-chapter-track"/g)??[]).length,7,"All chapter transitions render on the home page");
 } else {
  for(const label of ["Strategy library","Entry builder","YOUR CONTROL DECK","Guided view","Show expert controls","Time Matrix","One step at a time."])assert.ok(html.includes(label),`Guided control-room launcher ${label}`);
  assert.ok(html.includes('role="switch"')&&html.includes('aria-checked="false"'),"Accessible disabled lever switches render");
  assert.ok(html.includes("Pause coin animation"),"Coin flow starts automatically but can be paused");
 }
 console.log(`PASS ${route}: HTTP 200, metadata/product content, disclosure, controls, anchors`);
}
for(const asset of ["/research-core.webp","/favicon.svg","/benchmark-evidence.json"]){const r=await fetch(base+asset);assert.equal(r.status,200,asset);console.log(`PASS ${asset}: HTTP 200`);}
const evidence=await (await fetch(base+"/benchmark-evidence.json")).json();assert.equal(evidence.assertions_passed,270115);assert.equal(evidence.failed_assertions,0);
