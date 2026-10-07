export type TutorMood='idle'|'attentive'|'listening'|'thinking'|'curious'|'explaining'|'success'|'concern';
export function tutorPose(time:number,mood:TutorMood,moving=true,pointer=0,speaking=false,speechPulse=0){
 const t=moving?time:0,focus=mood==='thinking',curious=mood==='curious';
 const cycle=t%6.7,blink=moving&&(cycle>5.8&&cycle<5.94||cycle>6.08&&cycle<6.18)?.06:1;
 const idle=mood==='idle',nod=mood==='success'?Math.sin(t*4)*.10:mood==='listening'?Math.sin(t*2.3)*.04:0;
 return {
  float:moving?Math.sin(t*1.7)*.07:0,
  bodyYaw:idle?Math.sin(t*.45)*.15:-.02,
  headYaw:focus?-.12:idle?Math.sin(t*.7)*.28:pointer*.12,
  headPitch:focus?.10:curious?-.13:nod,
  headTilt:focus?-.15:curious?.12:mood==='concern'?-.09:Math.sin(t*.8)*.035,
  eyeHeight:blink*(focus?.5:curious?1.18:mood==='concern'?.75:1),
  eyeWidth:curious?1.1:focus?.95:1,
  armAngle:focus?1.75:mood==='explaining'?-.95+Math.sin(t*1.7)*.14:curious?-.45:-.20+Math.sin(t*1.2)*.045,
  armLift:focus?.4:0,armForward:focus?.47:0,
  mouthWidth:speaking?1.05+Math.sin(t*8)*.12:mood==='success'?1.25:curious?.65:focus?.7:1,
  mouthHeight:speaking?1.35+Math.max(0,Math.min(1,speechPulse))*1.8+(moving?Math.abs(Math.sin(t*9))*.65:0):curious?1.5:1,
  pointer:mood==='explaining',
 };
}
