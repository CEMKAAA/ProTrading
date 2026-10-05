"use client";
import { useEffect, useRef, useState } from "react";

const markets = [
  ["BTCUSD", "BTC", "#e8b650", "#584018"], ["EURUSD", "FX", "#b6d0df", "#27475c"],
  ["XAUUSD", "Au", "#ffcf66", "#674716"], ["USDJPY", "JPY", "#bfded7", "#295c52"],
  ["JP225", "225", "#becadf", "#394969"],
];

export default function StudioMarketOrbit() {
  const host = useRef<HTMLDivElement>(null), [fallback, setFallback] = useState(false);
  useEffect(() => {
    const element = host.current; if (!element) return;
    let disposed = false, cleanup: (() => void) | undefined;
    void import("three").then(T => {
      if (disposed) return;
      let renderer: InstanceType<typeof T.WebGLRenderer>;
      try { renderer = new T.WebGLRenderer({ alpha: true, antialias: true, powerPreference: "low-power" }); }
      catch { setFallback(true); return; }
      renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
      renderer.outputColorSpace = T.SRGBColorSpace; renderer.setClearColor(0, 0);
      element.appendChild(renderer.domElement);
      const scene = new T.Scene(), camera = new T.OrthographicCamera(-8, 8, 3, -3, .1, 40);
      camera.position.set(0, 0, 14); scene.add(new T.HemisphereLight(0xffffff, 0x5e8198, 3));
      const key = new T.DirectionalLight(0xffffff, 4); key.position.set(-3, 5, 9); scene.add(key);
      const rim = new T.DirectionalLight(0xffe4ad, 2.5); rim.position.set(7, -3, 5); scene.add(rim);
      const raycaster = new T.Raycaster(), pointer = new T.Vector2(9, 9);
      const resources: { dispose: () => void }[] = [];
      const metalGeo = new T.CylinderGeometry(1, 1, .18, 64), diskGeo = new T.CircleGeometry(.95, 64), ringGeo = new T.TorusGeometry(.91, .028, 8, 64);
      resources.push(metalGeo, diskGeo, ringGeo);
      const coins = markets.map(([pair, mark, color, ink], index) => {
        const coin = new T.Group(), metal = new T.MeshStandardMaterial({ color, metalness: .65, roughness: .29 });
        const body = new T.Mesh(metalGeo, metal); body.rotation.x = Math.PI / 2; coin.add(body);
        const canvas = document.createElement("canvas"); canvas.width = canvas.height = 512;
        const ctx = canvas.getContext("2d")!, gradient = ctx.createLinearGradient(0, 0, 512, 512);
        gradient.addColorStop(0, "#ffffff"); gradient.addColorStop(.25, color); gradient.addColorStop(1, color);
        ctx.fillStyle = gradient; ctx.fillRect(0, 0, 512, 512); ctx.strokeStyle = ink; ctx.globalAlpha = .22; ctx.lineWidth = 2;
        for (const r of [212, 223, 231]) { ctx.beginPath(); ctx.arc(256, 256, r, 0, Math.PI * 2); ctx.stroke(); }
        ctx.globalAlpha = 1; ctx.textAlign = "center"; ctx.fillStyle = ink;
        ctx.font = "600 27px monospace"; ctx.fillText("STRATUM / " + String(index + 1).padStart(2, "0"), 256, 130);
        ctx.font = "700 100px sans-serif"; ctx.fillText(mark, 256, 275);
        ctx.font = "700 42px monospace"; ctx.fillText(pair, 256, 350);
        ctx.font = "400 22px monospace"; ctx.fillText("RESEARCH / EXECUTION", 256, 393);
        const texture = new T.CanvasTexture(canvas); texture.colorSpace = T.SRGBColorSpace;
        const faceMaterial = new T.MeshStandardMaterial({ map: texture, metalness: .3, roughness: .5 });
        const face = new T.Mesh(diskGeo, faceMaterial); face.position.z = .095; coin.add(face);
        const back = new T.Mesh(diskGeo, faceMaterial); back.position.z = -.095; back.rotation.y = Math.PI; coin.add(back);
        for (const z of [-.11, .11]) { const ring = new T.Mesh(ringGeo, metal); ring.position.z = z; coin.add(ring); }
        resources.push(metal, faceMaterial, texture); coin.userData.index = index; scene.add(coin);
        return { coin, hover: 0, turn: 0 };
      });
      let width = 1, viewWidth = 16, frame = 0, lastFrame = 0, activeTime = 0, hovered = -1, visible = true;
      const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
      const resize = () => {
        width = element.clientWidth; const height = element.clientHeight; if (!width || !height) return;
        viewWidth = Math.max(9, width / height * 6); camera.left = -viewWidth / 2; camera.right = viewWidth / 2;
        camera.updateProjectionMatrix(); renderer.setSize(width, height);
      };
      const observer = new ResizeObserver(resize); observer.observe(element); resize();
      const intersection = new IntersectionObserver(entries => { visible = entries[0].isIntersecting; }); intersection.observe(element);
      const move = (event: PointerEvent) => {
        const rect = renderer.domElement.getBoundingClientRect(); pointer.set((event.clientX - rect.left) / rect.width * 2 - 1, -(event.clientY - rect.top) / rect.height * 2 + 1);
        raycaster.setFromCamera(pointer, camera); let root = raycaster.intersectObjects(coins.map(c => c.coin), true)[0]?.object;
        while (root?.parent && root.parent !== scene) root = root.parent;
        hovered = root?.userData.index ?? -1; renderer.domElement.style.cursor = hovered >= 0 ? "grab" : "default";
      };
      const leave = () => { hovered = -1; };
      renderer.domElement.addEventListener("pointermove", move); renderer.domElement.addEventListener("pointerleave", leave);
      const render = (now: number) => {
        frame = requestAnimationFrame(render);
        if (document.hidden || !visible || now - lastFrame < 32) { if(document.hidden || !visible)lastFrame=now; return; }
        const dt = Math.min((now-lastFrame)/1000, .05); lastFrame=now; if (!motion.matches) activeTime += dt;
        const mobile = width < 500, count = mobile ? 3 : coins.length;
        coins.forEach((state, i) => {
          state.coin.visible = i < count; const step = (viewWidth - 2.7) / Math.max(1, count-1), t = activeTime*.38 + i*1.8;
          state.hover += ((i === hovered ? 1 : 0) - state.hover) * .1;
          state.turn += dt * (motion.matches ? 0 : i === hovered ? 2.2 : .08);
          state.coin.position.set(-viewWidth/2+1.35+i*step+Math.sin(t)*.28, Math.sin(t*.85)*.65+(i%2?.35:-.25), Math.cos(t)*.3);
          state.coin.rotation.set(Math.sin(t)*.19, Math.sin(t*.7)*.33+Math.sin(state.turn)*.2+state.hover*.5, Math.sin(t)*.13);
          state.coin.scale.setScalar((mobile?.75:.92)*(1+state.hover*.1));
        });
        renderer.render(scene, camera);
      };
      frame=requestAnimationFrame(render);
      cleanup=()=>{cancelAnimationFrame(frame);observer.disconnect();intersection.disconnect();renderer.domElement.removeEventListener("pointermove",move);renderer.domElement.removeEventListener("pointerleave",leave);resources.forEach(r=>r.dispose());renderer.dispose();renderer.domElement.remove();};
      if(disposed)cleanup();
    }).catch(()=>{if(!disposed)setFallback(true);});
    return()=>{disposed=true;cleanup?.();};
  },[]);
  return <div className="studio-orbit" ref={host} aria-label="Interactive three-dimensional market coins: BTCUSD, EURUSD, XAUUSD, USDJPY and JP225">
    {fallback&&<div className="studio-orbit-fallback">{markets.slice(0,3).map(([pair,mark])=><div className="studio-fallback-coin" key={pair}><strong>{mark}</strong><span>{pair}</span></div>)}</div>}
  </div>;
}
