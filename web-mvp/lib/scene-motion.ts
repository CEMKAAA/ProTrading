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

// The wrap occurs beyond the camera edges, never in the visible coin lane.
export function studioCoinPose(index: number, count: number, viewWidth: number, seconds: number) {
  const loop = Math.max(viewWidth + 4.8, count * 2.85);
  const travel = index * loop / count + seconds * .72;
  return {
    x: ((travel % loop) + loop) % loop - loop / 2,
    y: Math.sin(seconds * .5 + index * .9) * .55 + Math.cos(index * 1.7) * .3,
    z: Math.cos(seconds * .35 + index) * .3,
    rotationX: Math.sin(seconds * .4 + index) * .17,
    rotationY: seconds * .34 + index * .6,
    rotationZ: Math.sin(seconds * .3 + index) * .1,
  };
}

export function chapterPose(progress: number) {
  const p = clampProgress(progress);
  const entrance = clampProgress(p / .22);
  const departure = clampProgress((p - .75) / .25);
  const ease = 1 - (1 - entrance) ** 3;
  return { y: (1 - ease) * 145 - departure * 36, scale: .92 + ease * .08 - departure * .035,
    radius: (1 - ease) * 86 + departure * 32, tilt: (1 - ease) * 7 - departure * 2 };
}
