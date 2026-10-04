import Studio from "@/components/studio";
import type { Metadata } from "next";
export const metadata:Metadata={title:"Strategy Studio | Stratum",description:"An interactive strategy-builder prototype using reproducible synthetic data. No live broker connection."};
export default function StudioPage(){return <Studio/>;}
