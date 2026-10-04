"use client";

import { useSyncExternalStore } from "react";

const query = "(prefers-reduced-motion: reduce)";
const serverSnapshot = () => false;
const browserSnapshot = () => window.matchMedia(query).matches;
function subscribe(notify: () => void) {
  const media = window.matchMedia(query);
  media.addEventListener("change", notify);
  return () => media.removeEventListener("change", notify);
}

// The hydration snapshot must match SSR; read the device preference afterwards.
export function useMotionPreference() {
  return useSyncExternalStore(subscribe, browserSnapshot, serverSnapshot);
}
