"use client";

import { useEffect, useRef, useState, type RefObject } from "react";
import { motion, useScroll, useTransform } from "motion/react";
import { Pause, Play } from "lucide-react";
import { heroPose, marketPose } from "@/lib/scene-motion";

type Props = { driver: RefObject<HTMLElement | null>; variant?: "hero" | "markets" };

export default function QuantCore({ driver, variant = "hero" }: Props) {
  const host = useRef<HTMLDivElement>(null);
  const [failed, setFailed] = useState(false);
  const [paused, setPaused] = useState(false);
  const { scrollYProgress } = useScroll({ target: driver, offset: ["start end", "end start"] });
  const fallbackRotation = useTransform(scrollYProgress, [0, 1], [-25, 400]);
  const animation = useRef({ paused });
  animation.current = { paused };

  useEffect(() => {
    const element = driver.current;
    if (!element) return;
    // Explicit brief: these two 3D scenes autoplay, independently of reveal motion.
    element.dataset.sceneMotion = "enabled";
    return () => { delete element.dataset.sceneMotion; };
  }, [driver]);

  useEffect(() => {
    let cleanup = () => {};
    let disposed = false;
    async function mount() {
      const T = await import("three");
      const { RoomEnvironment } = await import("three/examples/jsm/environments/RoomEnvironment.js");
      if (disposed || !host.current) return;
      const el = host.current;
      let renderer: InstanceType<typeof T.WebGLRenderer>;
      try { renderer = new T.WebGLRenderer({ antialias: true, alpha: true }); }
      catch { setFailed(true); return; }
      renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.6));
      renderer.setClearColor(0x000000, 0);
      renderer.toneMapping = T.ACESFilmicToneMapping;
      renderer.toneMappingExposure = 1.35;
      renderer.domElement.setAttribute("aria-hidden", "true");
      renderer.domElement.dataset.scene = variant;
      el.appendChild(renderer.domElement);
      const scene = new T.Scene();
      const camera = new T.PerspectiveCamera(36, 1, .1, 60);
      camera.position.set(0, 0, variant === "hero" ? 8.2 : 12.5);
      const pmrem = new T.PMREMGenerator(renderer);
      const room = new RoomEnvironment();
      const env = pmrem.fromScene(room, .02);
      scene.environment = env.texture;
      room.dispose(); pmrem.dispose();
      const gold = new T.MeshStandardMaterial({ color: 0xeab544, metalness: .88, roughness: .23 });
      const face = new T.MeshStandardMaterial({ color: 0xffd477, metalness: .78, roughness: .31 });
      const chrome = new T.MeshStandardMaterial({ color: 0xc9dbe4, metalness: .88, roughness: .22 });
      const ink = new T.MeshStandardMaterial({ color: 0x263b4a, metalness: .55, roughness: .32 });
      const textures: InstanceType<typeof T.Texture>[] = [];
      const matrix = new T.Object3D();

      function coin(label?: string, silver = false) {
        const group = new T.Group();
        const metal = silver ? chrome : gold;
        const addDisk = (radius: number, depth: number, z: number, material = metal) => {
          const mesh = new T.Mesh(new T.CylinderGeometry(radius, radius, depth, 96), material);
          mesh.rotation.x = Math.PI / 2; mesh.position.z = z; group.add(mesh);
        };
        addDisk(1.9, .3, 0);
        for (const sign of [1, -1]) {
          addDisk(1.76, .06, sign * .17, silver ? chrome : face);
          const rim = new T.Mesh(new T.TorusGeometry(1.81, .045, 12, 96), metal);
          rim.position.z = sign * .2; group.add(rim);
          const innerRim = new T.Mesh(new T.TorusGeometry(1.51, .012, 8, 96), metal);
          innerRim.position.z = sign * .215; group.add(innerRim);
          // Instanced engraving keeps each face to one draw call.
          const marks = new T.InstancedMesh(new T.BoxGeometry(.014, .065, .016), ink, 60);
          for (let i = 0; i < 60; i++) {
            const angle = i / 60 * Math.PI * 2;
            matrix.position.set(Math.sin(angle) * 1.64, Math.cos(angle) * 1.64, sign * .208);
            matrix.rotation.set(0, 0, -angle); matrix.updateMatrix(); marks.setMatrixAt(i, matrix.matrix);
          }
          group.add(marks);
          if (!label) {
            const mark = new T.Group();
            for (let i = 0; i < 3; i++) {
              const bar = new T.Mesh(new T.BoxGeometry(i === 1 ? .88 : 1.25, .21, .095), ink);
              bar.position.set(i === 1 ? .19 : 0, .35 - i * .35, 0);
              bar.rotation.z = .16; mark.add(bar);
            }
            mark.position.z = sign * .245;
            if (sign < 0) mark.rotation.y = Math.PI;
            group.add(mark);
          } else {
            const canvas = document.createElement("canvas");
            canvas.width = canvas.height = 512;
            const ctx = canvas.getContext("2d");
            if (ctx) {
              ctx.fillStyle = "#233747"; ctx.textAlign = "center"; ctx.textBaseline = "middle";
              ctx.font = `700 ${label.length > 3 ? 102 : 128}px Manrope Variable, sans-serif`;
              ctx.fillText(label, 256, 263);
              const texture = new T.CanvasTexture(canvas); texture.colorSpace = T.SRGBColorSpace;
              textures.push(texture);
              const text = new T.Mesh(new T.PlaneGeometry(2.4, 2.4), new T.MeshBasicMaterial({ map: texture, transparent: true, depthWrite: false }));
              text.position.z = sign * .224;
              if (sign < 0) text.rotation.y = Math.PI;
              group.add(text);
            }
          }
        }
        const grooves = new T.InstancedMesh(new T.BoxGeometry(.015, .025, .25), metal, 120);
        for (let i = 0; i < 120; i++) {
          const angle = i / 120 * Math.PI * 2;
          matrix.position.set(Math.sin(angle) * 1.906, Math.cos(angle) * 1.906, 0);
          matrix.rotation.set(0, 0, -angle); matrix.updateMatrix(); grooves.setMatrixAt(i, matrix.matrix);
        }
        group.add(grooves);
        return group;
      }

      const coins = variant === "hero" ? [coin()] : [coin("BTC"), coin("EUR", true), coin("GOLD"), coin("JPY", true)];
      coins.forEach(group => { if (variant === "markets") group.scale.setScalar(.5); scene.add(group); });
      const key = new T.DirectionalLight(0xfff5dc, 4); key.position.set(-3, 4, 6); scene.add(key);
      const fill = new T.DirectionalLight(0xd9ecff, 3); fill.position.set(4, -1, 4); scene.add(fill);
      const back = new T.DirectionalLight(0xffffff, 4); back.position.set(2, 2, -5); scene.add(back);
      scene.add(new T.AmbientLight(0xffffff, 1.2));
      let raf = 0, visible = false, pointerX = 0, pointerY = 0, fixedProgress = 0, elapsed = 0, previous = 0, rendered = false, resized = true;
      const observer = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; }); observer.observe(el);
      const resize = new ResizeObserver(() => {
        const { width, height } = el.getBoundingClientRect();
        if (!width || !height) return;
        renderer.setSize(width, height); camera.aspect = width / height;
        camera.position.z = variant === "hero" ? (camera.aspect < .9 ? 10 : 8.2) : (camera.aspect < 1.3 ? 15 : 12.5);
        camera.updateProjectionMatrix(); resized = true;
      }); resize.observe(el);
      const pointer = (event: PointerEvent) => { const b = el.getBoundingClientRect(); pointerX = (event.clientX - b.left) / b.width - .5; pointerY = (event.clientY - b.top) / b.height - .5; };
      const reset = () => { pointerX = pointerY = 0; };
      el.addEventListener("pointermove", pointer); el.addEventListener("pointerleave", reset);
      const frame = (time: number) => {
        raf = requestAnimationFrame(frame);
        const delta = Math.min((time - previous) / 1000, .04); previous = time;
        if (!visible || document.hidden) return;
        const stopped = animation.current.paused;
        if (stopped && rendered && !resized) return;
        if (!stopped) { elapsed += delta; fixedProgress = scrollYProgress.get(); }
        const p = fixedProgress;
        if ((!animation.current.paused || !rendered) && variant === "hero") {
          const pose = heroPose(p, elapsed), group = coins[0];
          group.rotation.y = T.MathUtils.lerp(group.rotation.y, pose.y + (stopped ? 0 : pointerX * .28), .11);
          group.rotation.x = T.MathUtils.lerp(group.rotation.x, pose.x + (stopped ? 0 : pointerY * .2), .11);
          group.rotation.z = pose.z;
          group.position.y = stopped ? 0 : Math.sin(elapsed * .75) * .07;
        } else if ((!animation.current.paused || !rendered) && variant === "markets") coins.forEach((group, index) => {
          const pose = marketPose(index, p, stopped ? 0 : elapsed);
          group.position.set(pose.x, pose.y, pose.z);
          group.rotation.set(-.2 + index * .06, pose.rotation, -.24 + index * .15);
        });
        renderer.domElement.dataset.rotation = coins[0].rotation.y.toFixed(3);
        renderer.render(scene, camera); rendered = true; resized = false;
      }; frame(0);
      cleanup = () => {
        cancelAnimationFrame(raf); observer.disconnect(); resize.disconnect();
        el.removeEventListener("pointermove", pointer); el.removeEventListener("pointerleave", reset);
        const geometries = new Set<InstanceType<typeof T.BufferGeometry>>(), materials = new Set<InstanceType<typeof T.Material>>();
        scene.traverse(obj => { if (obj instanceof T.Mesh) { geometries.add(obj.geometry); (Array.isArray(obj.material) ? obj.material : [obj.material]).forEach(m => materials.add(m)); } });
        geometries.forEach(g => g.dispose()); materials.forEach(m => m.dispose()); textures.forEach(t => t.dispose());
        env.dispose(); renderer.dispose(); renderer.domElement.remove();
      };
    }
    mount().catch(() => { if (!disposed) setFailed(true); });
    return () => { disposed = true; cleanup(); };
  }, [scrollYProgress, variant]);

  return <div className={`coin-visual coin-visual-${variant}`}>
    <div ref={host} className="coin-scene" role="img" aria-label={variant === "hero" ? "A three-dimensional gold Stratum coin rotates through full turns as you scroll" : "Gold and silver market tokens move in a three-dimensional sequence as you scroll"}>
      {failed && <div className="coin-fallback"><motion.div className="fallback-scroll" style={{ rotateY: paused ? -25 : fallbackRotation }}><div className="fallback-token" style={{ animationPlayState: paused ? "paused" : "running" }}><span className="brand-mark"><i /><i /><i /></span></div></motion.div></div>}
    </div>
    <button className="scene-pause icon-btn" onClick={() => setPaused(p => !p)} aria-label={paused ? "Resume 3D animation" : "Pause 3D animation"} aria-pressed={paused}>
      {paused ? <Play size={18} /> : <Pause size={18} />}
    </button>
  </div>;
}
