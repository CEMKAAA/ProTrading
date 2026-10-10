"use client";
import { UiText, useLanguage } from './language-provider';
import { useCallback, useEffect, useState } from "react";
import { ShieldCheck, Link2, RefreshCw, Unplug, Terminal } from "lucide-react";
import type { BacktestRequest, BacktestResult, Progress } from "@/lib/control-contract";
import { CONTROL_API,CONTROL_CREDENTIALS,CONTROL_TIMEOUT_MS} from '@/lib/control-endpoint';
import HelpButton from './studio-help';
import { friendlyError } from '@/lib/studio-help';

const API = CONTROL_API;
type Installation = { id: string; label: string; state: string };
type Session = { accountId: string; accessMode:"demo"|"paid"|"inactive";trial:{daysRemaining:number}|null;subscriptionActive: boolean; entitlementUntil: number; trading: { enabled: boolean }; installations: Installation[]; lease: { installationId: string; expiresAt: number; active: boolean; controlledHere: boolean } | null };
type Summary = { wins: number; losses: number; open: number; data: number; netR: number; maxClosedDrawdownR: number; winRate: number | null; trust: string; coverageComplete: boolean };
type Job = { id: string; state: string; failureCode: string | null; request: BacktestRequest; configurationHash: string; progress: Progress | null; result: (BacktestResult & { summary: Summary }) | null };
type Review = { installationId: string; label: string; fingerprint: string; expiresAt: number };

async function api<T>(path: string, credential: string, body?: unknown): Promise<T> {
  const response = await fetch(API + path, { method: body === undefined ? "GET" : "POST", headers: { Authorization: `Bearer ${credential}`, ...(body === undefined ? {} : { "Content-Type": "application/json" }) }, ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(CONTROL_TIMEOUT_MS), redirect: "error", credentials:CONTROL_CREDENTIALS, cache: "no-store" });
  const data = await response.json();
  if (!response.ok) throw new Error(data && typeof data === "object" && "error" in data && typeof data.error === "string" ? data.error : `HTTP_${response.status}`);
  return data as T;
}
const errorText = (error: unknown) => error instanceof Error ? error.message : "CONTROL_SERVICE_UNAVAILABLE";

export default function ConnectionPanel({ credential, onCredential }: { credential: string; onCredential: (value: string) => void }) {
 const {t,locale}=useLanguage();
  const [session, setSession] = useState<Session | null>(null);
  const [error, setError] = useState(""), [busy, setBusy] = useState(false), [code, setCode] = useState("");
  const [pollError,setPollError]=useState('');
  const [review, setReview] = useState<Review | null>(null), [selected, setSelected] = useState("");
  const [fingerprintChecked, setFingerprintChecked] = useState(false);
  const [job, setJob] = useState<Job | null>(null);
  const refresh = useCallback(async () => {
    const current = await api<Session>("/v1/session", credential);
    setSession(current);
    setPollError('');
    setSelected(value => current.installations.some(i => i.id === value && i.state === "approved") ? value : current.installations.find(i => i.state === "approved")?.id ?? "");
  }, [credential]);
  useEffect(() => {
    if (!credential) return; // The parent remounts this panel when the credential changes.
    let active = true,pending=true;
    void Promise.all([api<Session>("/v1/session", credential), api<{ jobs: Job[] }>("/v1/jobs", credential)]).then(([current, history]) => {
      if (!active) return;
      setSession(current); setPollError(''); setSelected(current.installations.find(i => i.state === "approved")?.id ?? ""); setJob(history.jobs[0] ?? null);
    }).catch(e => { if (active) setPollError(errorText(e)); }).finally(()=>{pending=false;});
    const timer = setInterval(() => { if (document.hidden || !active || pending) return; pending = true; void refresh().catch(e => { if (active) setPollError(errorText(e)); }).finally(() => { pending = false; }); }, 10000);
    return () => { active = false; clearInterval(timer); };
  }, [credential, refresh]);
  const activeJob = job?.state === "queued" || job?.state === "running";
  const jobId = job?.id;
  useEffect(() => {
    if (!activeJob || !jobId || !credential) return;
    let active = true, pending = false;
    const timer = setInterval(() => { if (document.hidden || !active || pending) return; pending = true; void api<Job>(`/v1/jobs/${jobId}`, credential).then(current => { if (active) setJob(current); }).catch(e => { if (active) setError(errorText(e)); }).finally(() => { pending = false; }); }, 1500);
    return () => { active = false; clearInterval(timer); };
  }, [jobId, activeJob, credential]);
  async function action(work: () => Promise<void>) {
    if (busy) return;
    setBusy(true); setError("");
    try { await work(); } catch (e) { setError(errorText(e)); } finally { setBusy(false); }
  }
  const permitted = session?.lease?.active && session.lease.controlledHere && session.lease.installationId === selected && session.subscriptionActive;
  const progress = job?.progress;
  return <div className="control-panel">
    <div className="control-disclosure"><Terminal size={20}/><div><strong><UiText>{"Your computer does the research"}</UiText></strong><p><UiText>{"The website sends settings to your own MT5. Keep MT5 and the companion running while you use the studio."}</UiText></p></div><HelpButton topic="connect"/></div>
    <ol className="guide-connect-steps"><li><strong><UiText>{"Download & extract"}</UiText></strong><span><UiText>{"Get your personalized EA ZIP from the main dashboard. Node.js 22.13+ and MT5 are required for this local pilot."}</UiText></span></li><li><strong><UiText>{"Start & pair"}</UiText></strong><span><UiText>{"Run "}</UiText><code><UiText>{"start_connection.bat"}</UiText></code><UiText>{" from the extracted ZIP. Enter its pairing code below and compare the complete fingerprint."}</UiText></span></li><li><strong><UiText>{"Attach & authorize"}</UiText></strong><span><UiText>{"Copy the ZIP's MQL5 files to MT5's data folder. Attach the connection EA and load "}</UiText><code><UiText>{".state/connection.set"}</UiText></code><UiText>{". Authorize this browser below, then return to the dashboard to audit."}</UiText></span></li></ol>
    {!credential&&<p className="guide-blocker"><UiText>{"Close this window and sign in on the dashboard first. You do not need a developer token."}</UiText></p>}
    {(error||pollError) && <div className="control-error" role="alert"><UiText>{friendlyError(error||pollError)}</UiText></div>}
    {session && <>
      <div className="control-session"><ShieldCheck size={19}/><div><strong><UiText>{"Signed in securely"}</UiText></strong><span><UiText>{session.accessMode==="demo"?`DEMO / ${session.trial?.daysRemaining??0} days remaining`:session.subscriptionActive ? "Entitlement active" : "Entitlement expired"}</UiText><UiText>{" / Trading "}</UiText><UiText>{session.trading.enabled ? "ON requested" : "OFF"}</UiText></span></div><button className="icon-btn" aria-label={t("Refresh connection status")} disabled={busy} onClick={() => void action(refresh)}><RefreshCw size={18}/></button><button className="icon-btn" aria-label={t("Sign out and revoke this control session")} disabled={busy} onClick={() => void action(async () => { await api("/v1/auth/logout", credential, {}); onCredential(""); setReview(null); })}><Unplug size={18}/></button></div>
      <form onSubmit={e => { e.preventDefault(); void action(async () => {setReview(null);setFingerprintChecked(false);setReview(await api<Review>("/v1/pairings/review", credential, { code }));}); }}>
        <div className="guide-inline"><label htmlFor="pair-code"><UiText>{"Pairing code from your companion"}</UiText></label><HelpButton topic="pairing"/></div>
        <div className="control-row"><input id="pair-code" value={code} maxLength={9} placeholder={t("ABCD-1234")} onChange={e => { setCode(e.target.value.toUpperCase()); setReview(null);setFingerprintChecked(false); }} spellCheck={false}/><button className="secondary-btn" disabled={busy || !session.subscriptionActive || !/^[A-F0-9]{4}-[A-F0-9]{4}$/.test(code)} type="submit"><Link2 size={16}/><UiText>{"Review device"}</UiText></button></div>
      </form>
      {review && <div className="control-review"><strong>{review.label}</strong><span><UiText>{"Compare this entire key fingerprint with the one printed by your companion:"}</UiText></span><code><UiText>{review.fingerprint}</UiText></code><label className="guide-ack"><input type="checkbox" checked={fingerprintChecked} onChange={e=>setFingerprintChecked(e.target.checked)}/><span><UiText>{"The full fingerprint matches my own companion."}</UiText></span></label><button className="primary-btn" disabled={busy||!fingerprintChecked||!session.subscriptionActive} onClick={() => void action(async () => { await api("/v1/pairings/approve", credential, { code, fingerprint: review.fingerprint }); setReview(null);setFingerprintChecked(false); setCode(""); await refresh(); })}><UiText>{"Approve my device"}</UiText></button></div>}
      <div className="control-installations"><div className="guide-inline"><h3><UiText>{"Your approved devices"}</UiText></h3><HelpButton topic="controller"/></div>{session.installations.filter(i => i.state === "approved").length === 0 ? <p><UiText>{"No device approved yet. Complete pairing above first."}</UiText></p> : session.installations.filter(i => i.state === "approved").map(i => <div className="control-installation" key={i.id}><label><input type="radio" name="installation" checked={selected === i.id} onChange={() => setSelected(i.id)}/><span>{i.label}<small>{i.id}</small></span></label><div className="control-row"><button className="secondary-btn" disabled={busy||!session.subscriptionActive} onClick={() => void action(async () => { await api(`/v1/installations/${i.id}/activate`, credential, {}); await refresh(); })}><UiText>{"Authorize this browser"}</UiText></button><button className="text-btn" disabled={busy} onClick={() => void action(async () => { await api(`/v1/installations/${i.id}/revoke`, credential, {}); await refresh(); })}><UiText>{"Revoke device"}</UiText></button></div></div>)}</div>
      <div className="control-job-builder"><h3><UiText>{"Native MT5 research"}</UiText></h3><p><UiText>{"Close this window and use Apply & Run MT5 Audit on the main control desk. Its four engine configurations replace the old protocol-only request example."}</UiText></p>
        {activeJob && <button className="secondary-btn" disabled={busy} onClick={() => void action(async () => setJob(await api<Job>(`/v1/jobs/${job!.id}/cancel`, credential, {})))}><UiText>{"Cancel job"}</UiText></button>}
        {!permitted && <p className="control-help"><UiText>{"Select an installation and authorize this control session. The installation must renew its short-lived lease."}</UiText></p>}
      </div>
      {job && <div className="control-job" aria-live="polite"><div className="control-row"><strong><UiText>{"Job / "}</UiText><UiText>{job.state}</UiText></strong><span>{job.request.symbol}<UiText>{" / "}</UiText><UiText>{job.request.configuration.version===1?job.request.configuration.timeframe:job.request.configuration.family}</UiText></span></div><code>{job.id}</code><span><UiText>{"Configuration SHA-256"}</UiText></span><code><UiText>{job.configurationHash}</UiText></code>{progress && <><span><UiText>{progress.phase}</UiText><UiText>{": "}</UiText><UiText>{progress.processed.toLocaleString(locale)}</UiText><UiText>{" / "}</UiText><UiText>{progress.total?.toLocaleString(locale) ?? "total not known yet"}</UiText></span>{progress.total !== null && progress.total > 0 && <progress aria-label={t("Reported work completed in current phase")} value={progress.processed} max={progress.total}/>}</>}{job.failureCode && <p className="control-error"><UiText>{job.failureCode}</UiText></p>}{job.result && <><p><UiText>{job.result.summary.wins}</UiText><UiText>{" W / "}</UiText><UiText>{job.result.summary.losses}</UiText><UiText>{" L / "}</UiText><UiText>{job.result.summary.open}</UiText><UiText>{" O / "}</UiText><UiText>{job.result.summary.data}</UiText><UiText>{" DATA / "}</UiText><UiText>{job.result.summary.netR.toFixed(3)}</UiText><UiText>{" net R"}</UiText></p><p className="control-help"><UiText>{"Client-reported result, not independently verified. Coverage: "}</UiText><UiText>{job.result.summary.coverageComplete ? "reported complete" : "incomplete"}</UiText><UiText>{"."}</UiText></p></>}</div>}
    </>}
  </div>;
}
