"use client";

import { useRef, type ReactNode } from "react";
import { motion, useScroll, useTransform } from "motion/react";
import { useMotionPreference } from "@/lib/use-motion-preference";
import { chapterPose } from "@/lib/scene-motion";

export default function ScrollChapter({ children, tone = "paper" }: { children: ReactNode; tone?: "paper" | "sky" | "ice" }) {
  const track = useRef<HTMLDivElement>(null);
  const reduced = useMotionPreference();
  // Measure the untransformed track so the animation cannot alter its own progress.
  const { scrollYProgress } = useScroll({ target: track, offset: ["start end", "end start"] });
  const y = useTransform(scrollYProgress, p => chapterPose(p).y);
  const scale = useTransform(scrollYProgress, p => chapterPose(p).scale);
  const borderRadius = useTransform(scrollYProgress, p => {
    const radius = chapterPose(p).radius;
    return `${radius}px ${radius}px 0 0`;
  });
  return <div ref={track} className="scroll-chapter-track" data-tone={tone}>
    <motion.div className="scroll-chapter-sheet" style={reduced ? undefined : { y, scale, borderRadius }}>
      {children}
    </motion.div>
  </div>;
}
