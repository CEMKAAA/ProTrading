export const clampProgress = (value: number) => Math.min(1, Math.max(0, value));

export function heroPose(progress: number, seconds = 0) {
  const p = clampProgress(progress);
  return { x: -.12 + p * .18, y: -.48 + p * Math.PI * 2.35 + seconds * .22, z: -.2 + p * .15 };
}

export function marketPose(index: number, progress: number, seconds: number) {
  const p = clampProgress(progress);
  const stagger = index * .65;
  return {
    x: (index - 1.5) * 1.7 + Math.sin(p * Math.PI + stagger) * .3,
    y: Math.sin(stagger + p * Math.PI * 1.7) * .8 + Math.sin(seconds * .5 + stagger) * .09,
    z: Math.cos(stagger + p * Math.PI) * .7,
    rotation: -.5 + p * Math.PI * 2 + stagger + seconds * .18,
  };
}
