"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { motion, useScroll } from "motion/react";
import { useMotionPreference } from "@/lib/use-motion-preference";
import { ArrowUpRight, Play, Menu, X, Layers, ShieldCheck, Fingerprint, LockKeyhole, Download, Check, SlidersHorizontal, ScanLine, GitBranch, Zap, Terminal, Globe2 } from "lucide-react";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Toaster } from "@/components/ui/sonner";
import QuantCore from "./quant-core";
import StrategyDemo from "./strategy-demo";

export function Brand() {
  return <a href="/" className="brand" aria-label="Stratum home"><span className="brand-mark" aria-hidden="true"><i /><i /><i /></span><span>stratum<span className="brand-dot">.</span></span></a>;
}

const navigation = [
  { id: "overview", label: "Overview" }, { id: "platform", label: "Studio" },
  { id: "markets", label: "Markets" }, { id: "research", label: "Research" }, { id: "workflow", label: "Process" },
];
const benchmarks = [
  { id: "lab", name: "Entry Lab", market: "XAUUSD / M1", window: "20 weeks", before: 159.453, after: 18.422, speed: "8.66", description: "First audit, cold outcome cache. Existing broker history synchronized." },
  { id: "sol", name: "Sol Advanced", market: "USDJPY / H1", window: "5 years", before: 38.453, after: 7.109, speed: "5.41", description: "First five-year audit, cold outcome cache. Existing broker history synchronized." },
  { id: "ma", name: "MaCross", market: "XAUUSD / M1", window: "20 weeks", before: 149.563, after: 24.671, speed: "6.06", description: "First audit, cold outcome cache. Existing broker history synchronized." },
];

function Reveal({ children, className = "", delay = 0 }: { children: ReactNode; className?: string; delay?: number }) {
  const reduced = useMotionPreference();
  return <motion.div className={className} initial={reduced ? false : { opacity: 0, y: 28 }} animate={reduced ? { opacity: 1, y: 0 } : undefined} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true, amount: .12 }} transition={{ duration: reduced ? 0 : .65, delay: reduced ? 0 : delay, ease: [.16, 1, .3, 1] }}>{children}</motion.div>;
}

export default function LaunchPage() {
  const [mobileMenu, setMobileMenu] = useState(false);
  const [evidenceOpen, setEvidenceOpen] = useState(false);
  const [active, setActive] = useState("overview");
  const hero = useRef<HTMLElement>(null), markets = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll();
  useEffect(() => {
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => { if (entry.isIntersecting) setActive(entry.target.id); });
    }, { rootMargin: "-18% 0px -65% 0px", threshold: 0 });
    document.querySelectorAll("[data-nav-section]").forEach(section => observer.observe(section));
    return () => observer.disconnect();
  }, []);
  useEffect(() => {
    const close = (event: KeyboardEvent) => { if (event.key === "Escape") setMobileMenu(false); };
    document.addEventListener("keydown", close); return () => document.removeEventListener("keydown", close);
  }, []);

  return <>
    <a className="skip-link" href="#main">Skip to content</a>
    <header className="top-nav">
      <div className="wrap nav-inner"><Brand />
        <nav className="nav-links" aria-label="Main navigation">{navigation.map(item => <a key={item.id} href={`#${item.id}`} data-active={active === item.id} aria-current={active === item.id ? "location" : undefined}>{item.label}</a>)}</nav>
        <div className="nav-right"><a className="primary-btn small-btn" href="/studio">Open studio <ArrowUpRight size={18} /></a><button className="menu-btn icon-btn" aria-label="Toggle navigation" aria-controls="mobile-navigation" aria-expanded={mobileMenu} onClick={() => setMobileMenu(!mobileMenu)}>{mobileMenu ? <X size={22} /> : <Menu size={22} />}</button></div>
      </div>
      <motion.div className="nav-progress" style={{ scaleX: scrollYProgress }} aria-hidden="true" />
      {mobileMenu && <nav id="mobile-navigation" className="mobile-nav" aria-label="Mobile navigation">{navigation.map(item => <a href={`#${item.id}`} key={item.id} aria-current={active === item.id ? "location" : undefined} onClick={() => setMobileMenu(false)}>{item.label}<ArrowUpRight size={18} /></a>)}</nav>}
    </header>

    <main id="main">
      <section className="hero" id="overview" ref={hero} data-nav-section aria-labelledby="hero-heading">
        <div className="hero-clouds" aria-hidden="true" />
        <div className="wrap hero-inner">
          <Reveal className="hero-copy"><div className="eyebrow">Independent thinking. Quant precision.</div><h1 id="hero-heading">Your ideas.<br /><span>Your edge.</span></h1><p>Turn the way you see the market into a system you control. No fixed playbook. No rented signals.</p><div className="hero-actions"><a href="/studio" className="primary-btn">Build your first strategy <ArrowUpRight size={20} /></a><a href="#workflow" className="text-btn"><Play size={17} />See how it works</a></div></Reveal>
          <div className="hero-art"><QuantCore driver={hero} /></div>
        </div>
      </section>

      <div className="wrap proof-strip"><p className="proof-label">A year of building.<br /><strong>Evidence to show for it.</strong></p><div className="proof-item"><strong>4</strong><span>specialized execution systems</span></div><button className="proof-item proof-button" onClick={() => setEvidenceOpen(true)}><strong>270,115</strong><span>regression assertions passed*</span></button><button className="proof-item proof-button" onClick={() => setEvidenceOpen(true)}><strong>14,177</strong><span>trade traces matched exactly*</span></button></div>

      <section className="wrap section" id="platform" data-nav-section>
        <Reveal className="section-heading"><h2>Think like a quant.<br /><span>Build like yourself.</span></h2><p>Connect your market conditions. Define your risk. Then inspect what happens, trade by trade.</p></Reveal>
        <Reveal><div className="terminal-shell"><div className="terminal-bar"><div className="terminal-bar-left"><Terminal size={20} /><span>Strategy studio</span></div><span className="demo-tag">Interactive preview</span></div><StrategyDemo /></div></Reveal>
        <div className="workspace-notes"><span><GitBranch size={19} />Your logic, not a rented signal.</span><span><ScanLine size={19} />Every outcome open to inspection.</span><span><SlidersHorizontal size={19} />Risk is a design decision.</span></div>
        <p className="preview-disclosure">This working preview uses synthetic data. It does not place trades or replace the production tick-audit engine.</p>
      </section>

      <section className="markets-section" id="markets" ref={markets} data-nav-section>
        <div className="wrap"><Reveal className="section-heading"><h2>One idea.<br /><span>A world of markets.</span></h2><p>Your tools should give an idea room to grow. Explore different markets without giving up control of your own logic.</p></Reveal>
          <div className="market-scene-stage"><QuantCore driver={markets} variant="markets" /></div>
          <div className="market-list">{[["BTC", "Crypto"], ["EURUSD", "Forex"], ["JP225", "Indices"], ["XAUUSD", "Metals"]].map(([name, category]) => <div className="market-item" key={name}><strong>{name}</strong><span>{category}</span></div>)}</div>
          <div className="market-principles"><span><LockKeyhole size={19} />Keep your strategy private.</span><span><Globe2 size={19} />Keep your broker. Expand your thinking.</span></div>
        </div>
      </section>

      <section className="wrap section research-section" id="research" data-nav-section>
        <Reveal className="section-heading"><div className="eyebrow">Evidence over adjectives</div><h2>Less waiting.<br /><span>More ideas put to the test.</span></h2><p>Measured acceleration in our MT5 research systems. Speed only counts when the results stay correct.</p></Reveal>
        <div className="research-grid"><Reveal className="benchmark-panel surface"><div className="panel-heading"><h3>Measured. Not estimated.</h3><span className="label">Internal MT5 benchmark</span></div><Tabs defaultValue="lab" className="benchmark-tabs"><TabsList className="benchmark-tablist">{benchmarks.map(b => <TabsTrigger value={b.id} key={b.id}>{b.name}</TabsTrigger>)}</TabsList>{benchmarks.map(b => <TabsContent value={b.id} key={b.id}><div className="speed-value"><strong>{b.speed}<small>x</small></strong><div>faster first audit<span>{b.market} / {b.window}</span></div></div><div className="benchmark-comparison"><div><span>Previous engine</span><strong>{b.before.toFixed(2)}<small> seconds</small></strong></div><ArrowUpRight size={26} /><div><span>Accelerated engine</span><strong>{b.after.toFixed(2)}<small> seconds</small></strong></div></div><p className="benchmark-note">{b.description} Download time excluded. Results vary by workload.</p></TabsContent>)}</Tabs></Reveal>
          <Reveal className="integrity-panel" delay={.12}><div className="feature-icon"><ScanLine size={27} /></div><h3>Fast is good.<br />Correct comes first.</h3><p>14,177 trade traces matched the frozen reference byte for byte: fills, price levels, timestamps, outcomes and R.</p><div className="check-list"><span><Check size={18} />No target-PnL substitution</span><span><Check size={18} />No invented wins from missing ticks</span><span><Check size={18} />Regression evidence, not a guarantee</span></div><button className="text-btn evidence-button" onClick={() => setEvidenceOpen(true)}>Read the measurement notes <ArrowUpRight size={18} /></button></Reveal></div>
      </section>

      <section className="workflow-section" id="workflow" data-nav-section><div className="wrap"><Reveal className="section-heading"><h2>An idea isn&apos;t an edge.<br /><span>Until you test it.</span></h2><p>A clear path from a market observation to a defined, testable strategy.</p></Reveal><div className="workflow-grid">{[
        { title: "Express the idea", copy: "Connect conditions. Separate entries from exits. Define what should happen, and when.", icon: GitBranch },
        { title: "Stress the assumptions", copy: "Include costs and position limits. Inspect losing trades, not just the equity curve.", icon: SlidersHorizontal },
        { title: "Test what survives", copy: "Reserve unseen data. Compare regimes. A good backtest is not permission to go live.", icon: Zap },
        { title: "Stay in control", copy: "Set local risk limits. Validate in demo. The planned MT5 connection keeps execution in your hands.", icon: ShieldCheck },
      ].map((step, i) => <Reveal className="workflow-step" key={step.title} delay={i * .07}><div className="step-top"><span>{String(i + 1).padStart(2, "0")}</span><step.icon size={26} /></div><h3>{step.title}</h3><p>{step.copy}</p></Reveal>)}</div></div></section>

      <section className="wrap section security-section"><Reveal className="section-heading"><div className="feature-icon"><Fingerprint size={28} /></div><h2>Your access.<br /><span>Your authority.</span></h2><p>One authorized controller. A session you can revoke. No brokerage credentials in the browser.</p></Reveal><Reveal className="authorization-panel surface"><div className="auth-chain">{[{ title: "Your workspace", copy: "Authenticated user", icon: Fingerprint }, { title: "Authorization", copy: "Signed, scoped commands", icon: ShieldCheck }, { title: "MT5 listener", copy: "Your approved installation", icon: Terminal }].map((item, i) => <div className="chain-step" key={item.title}><span className="chain-icon"><item.icon size={28} /></span><h3>{item.title}</h3><p>{item.copy}</p>{i < 2 && <span className="chain-connector" aria-hidden="true" />}</div>)}</div><p className="security-disclosure">Planned architecture. Live authorization is not connected in this prototype.</p></Reveal></section>

      <section className="wrap section faq-section" id="faq"><div className="section-heading"><h2>Before your<br /><span>next move.</span></h2></div><Accordion type="single" collapsible className="faq-list">{[
        { q: "Is this a bot that guarantees returns?", a: "No. Stratum is a strategy design and research environment. Good test results do not guarantee future returns. Markets, costs, data coverage and execution conditions all matter." },
        { q: "Do I need to code my own strategy?", a: "The intended builder connects features, comparisons and logical operators visually. This preview demonstrates a small part of that workflow. The production builder will support independent entry and exit logic." },
        { q: "Are the numbers on this page real?", a: "Engineering measurements come from the internal MT5 validation report dated 3 October 2026. The interactive chart and browser replay use labeled synthetic data. They are not investment-performance claims." },
        { q: "Does this website place trades or hold my funds?", a: "This prototype does neither. Live MT5 authorization, subscriptions and certified listener delivery are future integration work. Your funds would remain with your broker." },
        { q: "Where does a saved demo strategy go?", a: "Into this browser's local storage only. Load it here or export the configuration as JSON. This is not cloud storage and does not create an account." },
      ].map(({ q, a }) => <AccordionItem key={q} value={q}><AccordionTrigger>{q}</AccordionTrigger><AccordionContent>{a}</AccordionContent></AccordionItem>)}</Accordion></section>

      <section className="closing-section"><div className="wrap"><Reveal><h2>The next edge<br />starts with <span>you.</span></h2><p>Not a signal to follow. A way to explore what you see.</p><a className="primary-btn" href="/studio">Open the strategy studio <ArrowUpRight size={20} /></a></Reveal></div></section>
    </main>

    <footer className="site-footer"><div className="wrap footer-brand-row"><Brand /><nav aria-label="Footer navigation"><a href="#platform">Studio</a><a href="#research">Research</a><a href="#faq">Questions</a></nav><span>Research before conviction.</span></div><div className="wrap footer-legal"><p>Trading involves risk. Historical or simulated performance is not a reliable indicator of future results. No investment advice or return guarantee.</p><p>Stratum is a working brand for this prototype. Not affiliated with Binance or BrightFunded. Saved demo data stays on your device.</p><span>&copy; 2026 Stratum Research</span></div></footer>

    <Dialog open={evidenceOpen} onOpenChange={setEvidenceOpen}><DialogContent className="evidence-dialog"><DialogHeader><DialogTitle>The evidence behind the numbers.</DialogTitle><DialogDescription>Internal MT5 tests. Source: audit_acceleration_20261003.md, 3 October 2026.</DialogDescription></DialogHeader><div className="evidence-stats"><div><strong>270,115</strong><span>assertions / zero failures</span></div><div><strong>14,177</strong><span>matching trade traces</span></div></div><p>The report compares frozen and accelerated source in the same isolated worker. Broker history was already available; downloading it was not part of the timing.</p><ul><li>Exact entry and exit times, fills, SL/TP, outcomes and R were compared.</li><li>The unchanged MaCross repeat was slower in the final rerun. No speed improvement is claimed for that path.</li><li>These tests do not prove correctness for every strategy, broker or instrument, or guarantee profitability.</li></ul><a href="/benchmark-evidence.json" download className="secondary-btn"><Download size={18} />Download benchmark summary</a></DialogContent></Dialog>
    <Toaster theme="light" position="bottom-right" />
  </>;
}
