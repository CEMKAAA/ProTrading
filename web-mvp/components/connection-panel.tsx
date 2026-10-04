"use client";
import { useCallback, useEffect, useState } from "react";
import { ShieldCheck, Link2, RefreshCw, Unplug, Terminal } from "lucide-react";
import { backtestRequestSchema, type BacktestRequest, type BacktestResult, type Progress } from "@/lib/control-contract";
import { exampleRequest } from "@/lib/control-example";

const API = "http://127.0.0.1:4321";
type Installation = { id: string; label: string; state: string };
type Session = { accountId: string; subscriptionActive: boolean; entitlementUntil: number; installations: Installation[]; lease: { installationId: string; expiresAt: number; active: boolean; controlledHere: boolean } | null };
type Summary = { wins: number; losses: number; open: number; data: number; netR: number; maxClosedDrawdownR: number; winRate: number | null; trust: string; coverageComplete: boolean };
type Job = { id: string; state: string; failureCode: string | null; request: BacktestRequest; configurationHash: string; progress: Progress | null; result: (BacktestResult & { summary: Summary }) | null };
type Review = { installationId: string; label: string; fingerprint: string; expiresAt: number };

async function api<T>(path: string, credential: string, body?: unknown): Promise<T> {
  const response = await fetch(API + path, { method: body === undefined ? "GET" : "POST", headers: { Authorization: `Bearer ${credential}`, ...(body === undefined ? {} : { "Content-Type": "application/json" }) }, ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(10000), redirect: "error", credentials: "omit", cache: "no-store" });
  const data = await response.json();
  if (!response.ok) throw new Error(data && typeof data === "object" && "error" in data && typeof data.error === "string" ? data.error : `HTTP_${response.status}`);
  return data as T;
}
const errorText = (error: unknown) => error instanceof Error ? error.message : "CONTROL_SERVICE_UNAVAILABLE";

export default function ConnectionPanel({ credential, onCredential }: { credential: string; onCredential: (value: string) => void }) {
  const [access, setAccess] = useState(credential), [session, setSession] = useState<Session | null>(null);
  const [error, setError] = useState(""), [busy, setBusy] = useState(false), [code, setCode] = useState("");
  const [review, setReview] = useState<Review | null>(null), [selected, setSelected] = useState("");
  const [draft, setDraft] = useState(""), [job, setJob] = useState<Job | null>(null);
  const refresh = useCallback(async () => {
    const current = await api<Session>("/v1/session", credential);
    setSession(current);
    setSelected(value => current.installations.some(i => i.id === value && i.state === "approved") ? value : current.installations.find(i => i.state === "approved")?.id ?? "");
  }, [credential]);
  useEffect(() => {
    if (!credential) { setSession(null); setJob(null); return; }
    let active = true;
    void Promise.all([api<Session>("/v1/session", credential), api<{ jobs: Job[] }>("/v1/jobs", credential)]).then(([current, history]) => {
      if (!active) return;
      setSession(current); setSelected(current.installations.find(i => i.state === "approved")?.id ?? ""); setJob(history.jobs[0] ?? null);
    }).catch(e => { if (active) setError(errorText(e)); });
    const timer = setInterval(() => { if (!document.hidden && active) void refresh().catch(e => { if (active) setError(errorText(e)); }); }, 10000);
    return () => { active = false; clearInterval(timer); };
  }, [credential, refresh]);
  const activeJob = job?.state === "queued" || job?.state === "running";
  useEffect(() => {
    if (!activeJob || !job || !credential) return;
    let active = true;
    const timer = setInterval(() => { if (document.hidden) return; void api<Job>(`/v1/jobs/${job.id}`, credential).then(current => { if (active) setJob(current); }).catch(e => { if (active) setError(errorText(e)); }); }, 1500);
    return () => { active = false; clearInterval(timer); };
  }, [job?.id, activeJob, credential]);
  async function action(work: () => Promise<void>) {
    if (busy) return;
    setBusy(true); setError("");
    try { await work(); } catch (e) { setError(errorText(e)); } finally { setBusy(false); }
  }
  const permitted = session?.lease?.active && session.lease.controlledHere && session.lease.installationId === selected && session.subscriptionActive;
  const progress = job?.progress;
  return <div className="control-panel">
    <div className="control-disclosure"><Terminal size={20}/><div><strong>Connection architecture / local development</strong><p>Pairing and signed jobs are operational. The MT5 execution adapter is not connected; this screen cannot place orders or produce a market backtest yet.</p></div></div>
    <form className="control-access" onSubmit={e => { e.preventDefault(); void action(async () => { await api<Session>("/v1/session", access.trim()); onCredential(access.trim()); }); }}>
      <label htmlFor="control-access">Local development access token</label>
      <div className="control-row"><input id="control-access" type="password" value={access} onChange={e => setAccess(e.target.value)} autoComplete="off" spellCheck={false}/><button className="secondary-btn" disabled={busy || !access.trim()} type="submit">{credential ? "Reconnect" : "Connect"}</button></div>
      <p className="control-help">From <code>web-mvp/control-service/.state/dev-access.json</code>. Stored in memory only, not browser storage. This is not subscriber login.</p>
    </form>
    {error && <div className="control-error" role="alert">{error === "Failed to fetch" ? "Local service is unavailable. Start the control service on port 4321." : error}</div>}
    {session && <>
      <div className="control-session"><ShieldCheck size={19}/><div><strong>Local test identity authenticated</strong><span>{session.subscriptionActive ? "Development entitlement active" : "Entitlement expired"} / live trading disabled</span></div><button className="icon-btn" aria-label="Refresh connection status" disabled={busy} onClick={() => void action(refresh)}><RefreshCw size={18}/></button><button className="icon-btn" aria-label="Disconnect local control session" onClick={() => { onCredential(""); setAccess(""); setReview(null); }}><Unplug size={18}/></button></div>
      <form onSubmit={e => { e.preventDefault(); void action(async () => setReview(await api<Review>("/v1/pairings/review", credential, { code }))); }}>
        <label htmlFor="pair-code">Installation pairing code</label>
        <div className="control-row"><input id="pair-code" value={code} maxLength={9} placeholder="ABCD-1234" onChange={e => { setCode(e.target.value.toUpperCase()); setReview(null); }} spellCheck={false}/><button className="secondary-btn" disabled={busy || !/^[A-F0-9]{4}-[A-F0-9]{4}$/.test(code)} type="submit"><Link2 size={16}/>Review</button></div>
      </form>
      {review && <div className="control-review"><strong>{review.label}</strong><span>Compare this key fingerprint with the installation before approving:</span><code>{review.fingerprint}</code><button className="primary-btn" disabled={busy} onClick={() => void action(async () => { await api("/v1/pairings/approve", credential, { code, fingerprint: review.fingerprint }); setReview(null); setCode(""); await refresh(); })}>Approve installation</button></div>}
      <div className="control-installations"><h3>Approved installations</h3>{session.installations.filter(i => i.state === "approved").length === 0 ? <p>No approved installation. Pairing is required before any job can be dispatched.</p> : session.installations.filter(i => i.state === "approved").map(i => <div className="control-installation" key={i.id}><label><input type="radio" name="installation" checked={selected === i.id} onChange={() => setSelected(i.id)}/><span>{i.label}<small>{i.id}</small></span></label><div className="control-row"><button className="secondary-btn" disabled={busy} onClick={() => void action(async () => { await api(`/v1/installations/${i.id}/activate`, credential, {}); await refresh(); })}>Authorize controller</button><button className="text-btn" disabled={busy} onClick={() => void action(async () => { await api(`/v1/installations/${i.id}/revoke`, credential, {}); await refresh(); })}>Revoke</button></div></div>)}</div>
      <div className="control-job-builder"><h3>Backtest dispatch / protocol test</h3><p>Separate from the synthetic builder. Inspect the exact JSON before dispatch. No proprietary ORB/Sol recipe is included.</p><button className="secondary-btn" disabled={!selected || busy} onClick={() => setDraft(JSON.stringify(exampleRequest(selected, crypto.randomUUID()), null, 2))}>Load editable request example</button>
        <label htmlFor="backtest-request">Immutable request snapshot</label><textarea id="backtest-request" className="mono" value={draft} onChange={e => setDraft(e.target.value)} rows={10} maxLength={100000} spellCheck={false}/>
        <div className="control-row"><button className="primary-btn" disabled={!permitted || !draft || busy || activeJob} onClick={() => void action(async () => { const parsed = backtestRequestSchema.safeParse(JSON.parse(draft)); if (!parsed.success) throw new Error(parsed.error.issues[0]?.message ?? "INVALID_REQUEST"); if (parsed.data.installationId !== selected) throw new Error("Request installation differs from selected installation"); setJob(await api<Job>("/v1/jobs", credential, parsed.data)); })}>Dispatch research job</button>{activeJob && <button className="secondary-btn" disabled={busy} onClick={() => void action(async () => setJob(await api<Job>(`/v1/jobs/${job!.id}/cancel`, credential, {})))}>Cancel job</button>}</div>
        {!permitted && <p className="control-help">Select an installation and authorize this control session. The installation must renew its short-lived lease.</p>}
      </div>
      {job && <div className="control-job" aria-live="polite"><div className="control-row"><strong>Job / {job.state}</strong><span>{job.request.symbol} / {job.request.configuration.timeframe}</span></div><code>{job.id}</code><span>Configuration SHA-256</span><code>{job.configurationHash}</code>{progress && <><span>{progress.phase}: {progress.processed.toLocaleString()} / {progress.total?.toLocaleString() ?? "total not known yet"}</span>{progress.total !== null && progress.total > 0 && <progress aria-label="Reported work completed in current phase" value={progress.processed} max={progress.total}/>}</>}{job.failureCode && <p className="control-error">{job.failureCode}</p>}{job.result && <><p>{job.result.summary.wins} W / {job.result.summary.losses} L / {job.result.summary.open} O / {job.result.summary.data} DATA / {job.result.summary.netR.toFixed(3)} net R</p><p className="control-help">Client-reported result, not independently verified. Coverage: {job.result.summary.coverageComplete ? "reported complete" : "incomplete"}.</p></>}</div>}
    </>}
  </div>;
}
