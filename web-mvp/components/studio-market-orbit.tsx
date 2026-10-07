"use client";
import { UiText, useLanguage } from './language-provider';
import { useEffect, useRef, useState } from "react";
import { Pause, Play } from "lucide-react";
import { studioCoinPose } from "@/lib/scene-motion";
import { useMotionPreference } from "@/lib/use-motion-preference";

const markets = [
  ["BTCUSD", "BTC", "#e8b650", "#584018"], ["EURUSD", "FX", "#b6d0df", "#27475c"],
  ["XAUUSD", "Au", "#ffcf66", "#674716"], ["USDJPY", "JPY", "#bfded7", "#295c52"],
  ["JP225", "225", "#becadf", "#394969"],
];

export default function StudioMarketOrbit() {
 const {t}=useLanguage();
  const host = useRef<HTMLDivElement>(null), [fallback, setFallback] = useState(false);
  const [paused, setPaused] = useState(false), pausedRef = useRef(false);
  const reduced = useMotionPreference();
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
      const leave = () => { hovered = -1; pointer.set(9, 9); renderer.domElement.style.cursor = "default"; };
      renderer.domElement.addEventListener("pointermove", move); renderer.domElement.addEventListener("pointerleave", leave);
      const render = (now: number) => {
        frame = requestAnimationFrame(render);
        if (document.hidden || !visible || now - lastFrame < 32) { if(document.hidden || !visible)lastFrame=now; return; }
        const dt = Math.min((now-lastFrame)/1000, .1); lastFrame=now;
        if (!motion.matches && !pausedRef.current) activeTime += dt;
        const mobile = width < 500;
        // Re-evaluate a stationary pointer as coins move underneath it.
        if (pointer.x !== 9) {
          raycaster.setFromCamera(pointer, camera);
          let root = raycaster.intersectObjects(coins.map(c => c.coin), true)[0]?.object;
          while (root?.parent && root.parent !== scene) root = root.parent;
          hovered = root?.userData.index ?? -1;
          renderer.domElement.style.cursor = hovered >= 0 ? "grab" : "default";
        }
        coins.forEach((state, i) => {
          const pose = studioCoinPose(i, coins.length, viewWidth, activeTime);
          state.hover += ((i === hovered ? 1 : 0) - state.hover) * (1-Math.exp(-dt*10));
          state.turn += dt * (motion.matches || pausedRef.current ? 0 : i === hovered ? 1.8 : 0);
          state.coin.position.set(pose.x, pose.y, pose.z);
          state.coin.rotation.set(pose.rotationX, pose.rotationY+state.turn+state.hover*.3, pose.rotationZ);
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
  return <div className="studio-orbit" ref={host} data-paused={paused || reduced} aria-label={t("Interactive three-dimensional market coins: BTCUSD, EURUSD, XAUUSD, USDJPY and JP225")}>
    {fallback&&<div className="studio-orbit-fallback">{markets.map(([pair,mark],i)=><div className="studio-fallback-coin" style={{animationDelay:`${-i*8}s`}} key={pair}><strong><UiText>{mark}</UiText></strong><span><UiText>{pair}</UiText></span></div>)}</div>}
    <button type="button" className="studio-orbit-pause" disabled={reduced} aria-label={reduced?"Coin motion disabled by device preference":paused?"Resume coin animation":"Pause coin animation"} onClick={()=>{pausedRef.current=!paused;setPaused(!paused);}}>{paused || reduced?<Play size={13}/>:<Pause size={13}/>}<span><UiText>{reduced?"Motion off":paused?"Resume":"Pause"}</UiText></span></button>
  </div>;
}
