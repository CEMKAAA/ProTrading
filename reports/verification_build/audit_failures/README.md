# Audit Failure Repair And Mega Campaign Handoff

Verified engine: `be6a04ce44dbed0ace9dc0f10f9aefe3aa643f2657efd24c45ce3424e6d5175a`.
Audit endpoint: `2026.10.09 19:46:57`, unchanged from the original campaign.

## Fixed Causes

- ORB, MaCross and EntryLab compact tick replay ended at or before the actual fill on M15 and larger timeframes. The replay horizon now starts after the fill and preserves existing expiry caps.
- MaCross and EntryLab recursive signal state could initialize from a partially downloaded history suffix. Broker-origin readiness is now required for cache/live initialization, and changing origins abort incomplete builds instead of publishing inconsistent results. A broker's first bar need not exist at midnight.
- CURRENT metric identities exclude pre-fix results. Historical archive reads retain their old identities; saved strategy parameters are unchanged.

## Evidence

- `parity_verified.json`: six strategies, all four families, 33 native campaign/dashboard window comparisons, no mismatches. Entry/exit times, geometry, outcomes, costs, R and MC are compared trade by trade.
- `failure-regression.json`: all 33 tested windows passed with DATA=0. This is not a claim that every broker provides five years of ticks for every instrument.
- `origin-probe.json`: 18 real broker-history checks passed.
- `boundary-probe.json`: 26 control-flow/readiness checks passed. This fixture is not a substitute for tick-based PnL verification.
- Six latest native calendar/strategy probes: 343 checks, zero failures, run at the original campaign's between-strategy boundary.
- Focused Node tests: 34 passed, zero failures.
- `strategy-preservation.json`: all 188 job configurations and 120 saved native records unchanged.
- `production-compiles.json`: the three changed production EAs compiled with zero errors and zero warnings. Verified binaries were restored to their canonical source folders. The running user DEMO was not modified or stopped.

## Campaign Connection

The full automatic rerun was CANCELLED at the user's request on 2026-10-10. The handoff process was stopped after checking its recorded identity. `repair-cancel.request.json` also prevents an accidental restart. Live status is in `repair-queue.json`.

The original campaign was asked to stop at its next native-verification boundary via `campaign-stop.request.json`. Existing results and the user DEMO terminal are retained. No third full campaign is authorized by this cancellation.

Corrected results go to this report directory, not the original report directory. Every publication requires a matching native dashboard audit. The old engine cannot seal the new verified baseline, and immutable existing archives are never replaced. Only a completed, verified corrected campaign enables the rolling refresh worker. Genuine data gaps remain explicitly unavailable, not fabricated wins/losses.

The corrected 33-window verification remains valid; it is not proof that every previously successful old-engine result is unchanged under the corrected engine. Failed/partial cases need targeted verification before publication. No old successful row is relabeled as new-engine proof.
