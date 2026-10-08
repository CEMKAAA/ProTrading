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
   camera.position.set(0,1.1,6.6);camera.lookAt(0,.25,0);
   scene.add(new T.HemisphereLight(0xffffff,0x597b86,2.8));
   const key=new T.DirectionalLight(0xffffff,4);key.position.set(-4,6,5);scene.add(key);
   const rim=new T.DirectionalLight(0xffdb88,2);rim.position.set(4,3,-2);scene.add(rim);
   const materials=[new T.MeshStandardMaterial({color:0xdce9ed,metalness:.5,roughness:.3}),
    new T.MeshStandardMaterial({color:0x183e48,metalness:.35,roughness:.35}),
    new T.MeshStandardMaterial({color:0xffca55,metalness:.45,roughness:.32}),
    new T.MeshStandardMaterial({color:0x8ee3c3,emissive:0x286957,emissiveIntensity:.4,roughness:.4}),
    new T.MeshStandardMaterial({color:0xffffff,roughness:.28}),
    new T.MeshStandardMaterial({color:0x62a8c9,emissive:0x193d58,emissiveIntensity:.35,roughness:.35})];
   const geometries:InstanceType<typeof T.BufferGeometry>[]=[];
   const robot=new T.Group();scene.add(robot);
   const part=(parent:InstanceType<typeof T.Group>,g:BufferGeometry<NormalBufferAttributes>,m:number,x:number,y:number,z:number)=>{
    geometries.push(g);const mesh=new T.Mesh(g,materials[m]);mesh.position.set(x,y,z);parent.add(mesh);return mesh;
   };
   const body=part(robot,new T.CapsuleGeometry(.48,.53,5,16),0,0,-.2,0);
   part(robot,new T.CylinderGeometry(.18,.21,.16,16),1,0,.46,0);
   part(robot,new T.TorusGeometry(.22,.035,6,20),2,0,.45,0).rotation.x=Math.PI/2;
   const head=new T.Group();head.position.set(0,.91,0);robot.add(head);
   part(head,new T.SphereGeometry(.67,24,16),0,0,0,0).scale.set(1,.76,.82);
   part(head,new T.SphereGeometry(.58,24,16),1,0,.02,.2).scale.set(1,.52,.71);
   const eyes=[-.22,.22].map(x=>part(head,new T.CapsuleGeometry(.068,.10,4,8),3,x,.07,.6));
   const glints=[-.22,.22].map(x=>part(head,new T.SphereGeometry(.022,8,6),4,x-.023,.105,.673));
   const brows=[-.22,.22].map(x=>{const brow=part(head,new T.CapsuleGeometry(.016,.14,3,8),2,x,.245,.61);brow.rotation.z=Math.PI/2;return brow;});
   for(const x of [-.22,.22])part(head,new T.TorusGeometry(.165,.015,6,20),2,x,.065,.65).scale.y=.83;
   part(head,new T.BoxGeometry(.12,.026,.028),2,0,.085,.65);
   for(const x of [-.64,.64]){
    part(head,new T.CylinderGeometry(.13,.13,.12,12),1,x,0,.03).rotation.z=Math.PI/2;
    part(head,new T.SphereGeometry(.065,10,8),2,x*1.11,.02,.04);
    part(head,new T.SphereGeometry(.043,10,8),5,x*.56,-.11,.61).scale.set(1,.52,.3);
   }
   const mouth=part(head,new T.BoxGeometry(.18,.03,.035),3,0,-.11,.62);
   part(head,new T.CylinderGeometry(.027,.027,.22,8),1,0,.57,0);
   part(head,new T.SphereGeometry(.09,12,8),2,0,.74,0);
   const badge=part(robot,new T.BoxGeometry(.12,.14,.035),2,-.28,.05,.43);badge.rotation.z=-.08;
   part(robot,new T.BoxGeometry(.34,.26,.048),1,.015,-.14,.485);
   part(robot,new T.BoxGeometry(.29,.20,.02),5,.015,-.14,.514);
   for(let i=0;i<5;i++)part(robot,new T.BoxGeometry(.026,.04+i*.024,.018),3,-.09+i*.047,-.205+i*.012,.533);
   for(const x of [-.19,.19])part(robot,new T.SphereGeometry(.018,8,6),2,x,-.37,.43);
   for(const x of [-.24,.24])part(robot,new T.BoxGeometry(.09,.025,.02),1,x,-.49,.4);
   const arm=new T.Group();arm.position.set(-.5,.18,0);arm.scale.x=-1;robot.add(arm);
   part(arm,new T.CapsuleGeometry(.12,.4,4,8),0,.13,-.18,0);
   part(arm,new T.SphereGeometry(.14,10,8),1,.07,.02,0);
   part(arm,new T.SphereGeometry(.15,12,8),2,.15,-.51,0);
   const pointer=part(arm,new T.CylinderGeometry(.022,.022,.82,8),1,.16,-.76,.07);pointer.rotation.z=.16;
   const restArm=new T.Group();restArm.position.set(.5,.16,0);robot.add(restArm);
   part(restArm,new T.SphereGeometry(.14,10,8),1,.07,.02,0);
   part(restArm,new T.CapsuleGeometry(.12,.4,4,8),0,.13,-.18,0).rotation.z=.2;
   part(restArm,new T.SphereGeometry(.14,12,8),2,.17,-.49,.11);
   const tablet=new T.Group();tablet.position.set(.32,-.32,.5);tablet.rotation.z=-.16;robot.add(tablet);
   part(tablet,new T.BoxGeometry(.31,.39,.045),1,0,0,0);
   part(tablet,new T.BoxGeometry(.25,.29,.012),5,0,.015,.032);
   for(let i=0;i<3;i++)part(tablet,new T.BoxGeometry(.16-i*.03,.016,.014),4,-i*.013,.08-i*.055,.045);
   part(tablet,new T.SphereGeometry(.018,8,6),2,0,-.15,.032);
   for(const x of [-.25,.25]){
    part(robot,new T.CylinderGeometry(.1,.1,.13,10),0,x,-.76,.04);
    part(robot,new T.SphereGeometry(.22,12,8),1,x,-.91,.12).scale.set(1,.52,1.3);
    part(robot,new T.BoxGeometry(.11,.018,.032),2,x,-.88,.37);
   }
   const base=part(robot,new T.CylinderGeometry(.82,.85,.08,32),0,0,-1.07,0);
   base.material=materials[0];body.rotation.y=.03;
   part(robot,new T.TorusGeometry(.76,.025,6,32),3,0,-1.02,0).rotation.x=Math.PI/2;
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
    restArm.rotation.z=approach(restArm.rotation.z,pose.restArmAngle);body.scale.y=pose.breath;
    brows.forEach((brow,i)=>brow.rotation.z=approach(brow.rotation.z,Math.PI/2+(i===0?1:-1)*pose.browTilt));
    glints.forEach((glint,i)=>{glint.visible=pose.eyeHeight>.1;glint.position.x=(i===0?-.22:.22)-.023+pose.gazeX;});
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
 return <div className="tutor-robot" data-speaking={speaking} data-mood={mood} data-paused={paused} data-motion-override={allowMotion} aria-hidden="true"><div ref={host} className="tutor-canvas"/>{fallback&&<div className="robot-fallback"><div className="robot-antenna"/><div className="robot-head"><span className="robot-ear robot-ear-left"/><span className="robot-ear robot-ear-right"/><div className="robot-visor"><i/><i/><b/><span className="robot-spectacles"/></div></div><div className="robot-collar"/><div className="robot-body"><b>S</b><span className="robot-chest"><i/><i/><i/><i/></span></div><div className="robot-arm robot-arm-point"><i/></div><div className="robot-arm robot-arm-rest"/><div className="robot-tablet"><i/><i/><i/></div><div className="robot-feet"><i/><i/></div><div className="robot-floor"/></div>}</div>;
}
