"use client";
import { useEffect, useRef, useState } from 'react';
import type { BufferGeometry, NormalBufferAttributes } from 'three';
import { tutorPose, type TutorMood } from '@/lib/tutor-behavior';

// A small, real 3D scene. The guide never reads credentials or sends commands.
export default function TutorRobot({paused=false,allowMotion=false,mood='idle',speaking=false,speechPulse=0}:{paused?:boolean;allowMotion?:boolean;mood?:TutorMood;speaking?:boolean;speechPulse?:number}) {
 const host=useRef<HTMLDivElement>(null),pauseRef=useRef(paused),override=useRef(allowMotion),moodRef=useRef(mood),voiceRef=useRef({speaking,speechPulse}),[fallback,setFallback]=useState(true);
 useEffect(()=>{voiceRef.current={speaking,speechPulse};},[speaking,speechPulse]);
 useEffect(()=>{moodRef.current=mood;},[mood]);
 useEffect(()=>{pauseRef.current=paused;},[paused]);
 useEffect(()=>{override.current=allowMotion;},[allowMotion]);
 useEffect(()=>{
  const element=host.current;if(!element)return;
  let disposed=false,cleanup:(()=>void)|undefined;
  void import('three').then(T=>{
   if(disposed)return;
   let renderer:InstanceType<typeof T.WebGLRenderer>;
   try{renderer=new T.WebGLRenderer({alpha:true,antialias:true,powerPreference:'low-power'});}catch{setFallback(true);return;}
   renderer.setPixelRatio(Math.min(window.devicePixelRatio,1.5));renderer.setClearColor(0,0);
   renderer.outputColorSpace=T.SRGBColorSpace;element.appendChild(renderer.domElement);setFallback(false);
   const scene=new T.Scene(),camera=new T.PerspectiveCamera(32,1,.1,30);
   camera.position.set(0,1.3,8);camera.lookAt(0,.2,0);
   scene.add(new T.HemisphereLight(0xffffff,0x597b86,2.8));
   const key=new T.DirectionalLight(0xffffff,4);key.position.set(-4,6,5);scene.add(key);
   const rim=new T.DirectionalLight(0xffdb88,2);rim.position.set(4,3,-2);scene.add(rim);
   const materials=[new T.MeshStandardMaterial({color:0xdce9ed,metalness:.5,roughness:.3}),
    new T.MeshStandardMaterial({color:0x183e48,metalness:.35,roughness:.35}),
    new T.MeshStandardMaterial({color:0xffca55,metalness:.45,roughness:.32}),
    new T.MeshStandardMaterial({color:0x8ee3c3,emissive:0x286957,emissiveIntensity:.4,roughness:.4})];
   const geometries:InstanceType<typeof T.BufferGeometry>[]=[];
   const robot=new T.Group();scene.add(robot);
   const part=(parent:InstanceType<typeof T.Group>,g:BufferGeometry<NormalBufferAttributes>,m:number,x:number,y:number,z:number)=>{
    geometries.push(g);const mesh=new T.Mesh(g,materials[m]);mesh.position.set(x,y,z);parent.add(mesh);return mesh;
   };
   const body=part(robot,new T.CapsuleGeometry(.48,.53,5,16),0,0,-.2,0);
   const head=new T.Group();head.position.set(0,.91,0);robot.add(head);
   part(head,new T.SphereGeometry(.67,24,16),0,0,0,0).scale.set(1,.76,.82);
   part(head,new T.SphereGeometry(.58,24,16),1,0,.02,.2).scale.set(1,.52,.71);
   const eyes=[-.22,.22].map(x=>part(head,new T.CapsuleGeometry(.068,.10,4,8),3,x,.07,.6));
   const mouth=part(head,new T.BoxGeometry(.18,.03,.035),3,0,-.11,.62);
   part(head,new T.CylinderGeometry(.027,.027,.22,8),1,0,.57,0);
   part(head,new T.SphereGeometry(.09,12,8),2,0,.74,0);
   const badge=part(robot,new T.BoxGeometry(.24,.18,.035),2,0,-.06,.5);badge.rotation.z=-.08;
   const arm=new T.Group();arm.position.set(-.5,.18,0);arm.scale.x=-1;robot.add(arm);
   part(arm,new T.CapsuleGeometry(.12,.4,4,8),0,.13,-.18,0);
   part(arm,new T.SphereGeometry(.15,12,8),2,.15,-.51,0);
   const pointer=part(arm,new T.CylinderGeometry(.022,.022,.82,8),1,.16,-.76,.07);pointer.rotation.z=.16;
   part(robot,new T.CapsuleGeometry(.12,.4,4,8),0,.59,-.12,0).rotation.z=.2;
   part(robot,new T.SphereGeometry(.14,12,8),2,.66,-.43,0);
   for(const x of [-.25,.25])part(robot,new T.SphereGeometry(.22,12,8),1,x,-.91,.12).scale.set(1,.52,1.3);
   const base=part(robot,new T.CylinderGeometry(.82,.85,.08,32),0,0,-1.07,0);
   base.material=materials[0];body.rotation.y=.03;
   let frame=0,last=0,time=0,visible=true,hover=false,needsRender=true,wasMoving=true,lastMood=moodRef.current,lastSpeaking=voiceRef.current.speaking;
   const reduced=window.matchMedia('(prefers-reduced-motion: reduce)');
   const resize=()=>{const w=element.clientWidth,h=element.clientHeight;if(!w||!h)return;camera.aspect=w/h;camera.updateProjectionMatrix();renderer.setSize(w,h);needsRender=true;};
   const ro=new ResizeObserver(resize);ro.observe(element);resize();
   const io=new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;});io.observe(element);
   const enter=()=>{hover=true;},leave=()=>{hover=false;};element.addEventListener('pointerenter',enter);element.addEventListener('pointerleave',leave);
   const render=(now:number)=>{
    frame=requestAnimationFrame(render);
    if(document.hidden||!visible||now-last<50){if(document.hidden||!visible)last=now;return;}
    const dt=Math.min((now-last)/1000,.1);last=now;
    const moving=(!reduced.matches||override.current)&&!pauseRef.current;
    if(moving)time+=dt;
    if(!moving&&!wasMoving&&!needsRender&&lastMood===moodRef.current&&lastSpeaking===voiceRef.current.speaking)return;
    const pose=tutorPose(time,moodRef.current,moving,hover?1:0,voiceRef.current.speaking,voiceRef.current.speechPulse),blend=moving?Math.min(1,dt*7):1;
    const approach=(v:number,target:number)=>v+(target-v)*blend;
    robot.position.y=approach(robot.position.y,pose.float);robot.rotation.y=approach(robot.rotation.y,pose.bodyYaw);
    head.rotation.z=approach(head.rotation.z,pose.headTilt);head.rotation.y=approach(head.rotation.y,pose.headYaw);head.rotation.x=approach(head.rotation.x,pose.headPitch);
    arm.rotation.z=approach(arm.rotation.z,pose.armAngle);arm.position.y=approach(arm.position.y,.18+pose.armLift);arm.position.z=approach(arm.position.z,pose.armForward);pointer.visible=pose.pointer;
    eyes.forEach(eye=>{eye.scale.y=pose.eyeHeight;eye.scale.x=approach(eye.scale.x,pose.eyeWidth);});mouth.scale.x=approach(mouth.scale.x,pose.mouthWidth);mouth.scale.y=approach(mouth.scale.y,pose.mouthHeight);
    renderer.render(scene,camera);
    wasMoving=moving;needsRender=false;lastMood=moodRef.current;lastSpeaking=voiceRef.current.speaking;
   };
   frame=requestAnimationFrame(render);
   cleanup=()=>{cancelAnimationFrame(frame);ro.disconnect();io.disconnect();element.removeEventListener('pointerenter',enter);element.removeEventListener('pointerleave',leave);geometries.forEach(g=>g.dispose());materials.forEach(m=>m.dispose());renderer.dispose();renderer.domElement.remove();};
   if(disposed)cleanup();
  }).catch(()=>{if(!disposed)setFallback(true);});
  return()=>{disposed=true;cleanup?.();};
 },[]);
 return <div className="tutor-robot" data-speaking={speaking} data-mood={mood} data-paused={paused} data-motion-override={allowMotion} aria-hidden="true"><div ref={host} className="tutor-canvas"/>{fallback&&<div className="robot-fallback"><div className="robot-antenna"/><div className="robot-head"><div className="robot-visor"><i/><i/><b/></div></div><div className="robot-body"><b>S</b></div><div className="robot-arm robot-arm-point"><i/></div><div className="robot-arm robot-arm-rest"/><div className="robot-feet"><i/><i/></div><div className="robot-floor"/></div>}</div>;
}
