# Universal connection EA verification, 2026-10-06

## Direct original-versus-subscriber audit

The saved MaCross strategy `jp225Close/Reverse0.25R` was applied by the original
strategy loader and audited using the unmodified production MaCross source.
Its effective settings were exported and submitted through the actual local
HTTP control service, installation companion and subscriber connection EX5.
No synthetic web demo results were used.

- Symbol: JP225m, Exness-MT5Trial15 demo, M5 signal timeframe.
- Fixed interval: 2026-09-21 00:00:00 UTC through 2026-10-05 00:00:00 UTC.
- Terminal Algo Trading disabled; bridge publication disabled.
- Original source input signature matched the saved strategy signature.
- All 176 source/dependency fingerprints match the canonical bundle manifest.

| Result | Original MaCross | Subscriber EX5 |
|---|---:|---:|
| Trades | 41 | 41 |
| Wins | 25 | 25 |
| Losses | 15 | 15 |
| Open | 1 | 1 |
| DATA / FLAT | 0 / 0 | 0 / 0 |
| Net R | -0.685166666666 | -0.685166666666 |
| Win rate | 62.5% | 62.5% |
| Closed-trade maximum drawdown R | 2.102166666667 | 2.102166666667 |

All 41 raw records matched on signal/entry/exit time, direction, entry price,
SL, TP, closing price, net R, validity, closed state and entry spread. Numeric
tolerance was 1e-10. There were no missing trades or reordered chronology.

The 25 TP records use different names for the same quarter-R target:
`TP025` in the original named architecture versus `TP_R0.25000000` in the web
custom architecture. This exact alias is recorded separately; it is not a
price, execution, outcome or PnL difference. Normalized web records also match.

Evidence: `tmp/universal_connection_validation/canonical-parity-report.json`,
`canonical-macross.txt`, `canonical-configuration.json`,
`canonical-universal-native.txt`, and `canonical-universal-result.json`.

## Repeatability

The test-only files are `tests/mql5/CanonicalMaCrossParity.mq5`, generated
`CanonicalParitySettings.mqh`, `scripts/validate_canonical_parity.ps1`, and
`web-mvp/scripts/prepare-canonical-parity.mjs` /
`web-mvp/scripts/test-canonical-mt5-parity.mjs`. The probe includes original
source rather than calling the universal engine to manufacture a baseline.
Windows text line endings are normalized before configuration parsing.
All artifacts overwrite bounded filenames; broker history is not cloned.

## Other Verification

- Universal EX5: compilation completed with 0 errors, 0 warnings.
- Native RSA/scope/identity probe: 34 passed, 0 failed.
- Control-plane/API/security tests: 43 passed, 0 failed.
- TypeScript check and design contract tests passed.
- Built-client secret scan: 51 client artifacts passed.
- Four-family native audits, subscriber labels, chart coordinates and leased
  authorization transitions passed and are recorded in `roundtrip-report.json`.
  ORB drew 9 trades, MaCross 144, Sol 9 and EntryLab 2,110, with no reported
  chart failures. EntryLab used 64 coordinate samples; the other three were
  checked exhaustively. Permission tests passed for explicit ON/OFF, helper
  loss, stale packet replay, local-key forgery, controller fencing and revoke.
- DEMO copy is gated on both that report and matching direct-parity evidence,
  identical EX5 SHA-256, clean compilation and unchanged compiled sources.
- Deployment completed: 19 hash-verified files under
  `C:\MT5\DEMO\MQL5\Experts\StratumUniversal`. The four original production
  EA source directories were unchanged. Deployment evidence is
  `tmp/universal_connection_validation/deployment-manifest.json`.

## Scope And Limitations

This proves parity for the stated saved strategy/window/build, not all saved
strategies, all brokers, or live fills. No market orders were submitted.
Unavailable canonical closing prices remain unknown; commission/slippage are
not invented. Results are explicitly `client_reported` rather than server
attested. Normalized target labels do not establish equal live fill economics.

Audit calculations are unchanged. The universal adapter currently schedules
audit chunks at a one-second timer cadence; this comparison is not evidence
that it matches the original dashboard's scheduling speed. The original probe
used a faster bounded loop. Performance parity remains a separate task.

Native chart geometry is checked exhaustively up to 150 rows; larger results
draw every record but use at most 64 evenly spaced coordinate samples.
This is not a screenshot-based visual inspection.

The subscriber panel displays greeting, signed subscription state and current
MT5/web health only. The identity certificate cannot grant execution. Public
production release still requires HTTPS deployment, real billing/webhook
verification, protected server keys/rotation, signed installer/updates,
recovery/load tests and an independent security review. Software installation
keys are not hardware attestation. See `web-mvp/docs/MT5_AUTHORIZATION_VERIFICATION.md`.
