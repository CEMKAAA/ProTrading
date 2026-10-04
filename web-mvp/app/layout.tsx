import type { Metadata } from "next";
import "./globals.css";
import "@fontsource-variable/manrope";
import "@fontsource/ibm-plex-mono/400.css";

export const metadata: Metadata = {
  title: "Stratum | Your ideas. Your rules. Your edge.",
  description: "An independent quant research workspace. Build your own trading logic, test every assumption, and keep control of your strategy.",
  other: {
    "theme-color": "#eef7fd",
  },
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
