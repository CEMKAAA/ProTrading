# Canonical EA Sources

For all future development, edit and compile these files in their own folders:

- ORB: `orb/OrbUltimateEA_StrategyLibrary.mq5`
- MaCross: `macrossover_orb/MaCrossOverOrbEA.mq5`
- Sol Advanced: `SolAdvanced/LiqNarrativeSol_Advanced.mq5`
- Entry Engine Lab: `entry_engine_lab/EntryEngineLabEA.mq5`

This is the default starting point for every subsequent ORB, MaCross, and
Sol Advanced development task. Do not resume work from root-level copies,
DEMO terminal files, archived backups, or generated family mirrors.

Their quoted `.mqh` dependencies live beside the corresponding EA. Never use
the old root-level ORB/Sol Advanced entry points or the legacy `liq` mirror as
the development source. Other root-level EAs are separate legacy variants.
`TradeCalendarMatrix.mqh` is copied into all three family folders and retained
at the root for the standalone test probe; keep the four copies identical.

Run `scripts/validate_time_matrix.ps1 -RunProbe` from the workspace root after
changes to these three EAs. Compiling an `.mqh` file alone is not a valid EA
build. Workspace changes do not automatically update the DEMO terminal; only
deploy a compiled `.ex5` after explicit verification and a deliberate release.
Older one-off installer/research scripts may still assume root-level ORB/Sol
Advanced files. Treat them as historical until their path and dependency
handling is revalidated; do not use them for a production release.

Entry Engine Lab is a separate fourth family cloned from MaCross. Its six
built-in engines remain available, plus `LabEntryBuilder.mqh`,
`LabEntryLogic.mqh`, and `LabParameterizedFeatures.mqh` for custom rules.
Keep its strategy files, terminal keys, bridge filenames and magic isolated
from MaCross. Do not add Lab rules to the three original production EAs.
Run `scripts/validate_entry_engine_lab.ps1` for a normal broker-data probe.
`-OfflineHistory` is a test-only recorded-history fixture, not a relaxation
of production data completeness. Preview mode must never submit entries.
Ten scalper templates in `LabScalperPresets.mqh` use the same rule builder.
`LabPolicyRuntime.mqh` manages their frozen ATR geometry, cooldown and
post-fill rule/time exits. Preserve old LAB2 policy-OFF semantics. These
new policies are native-only until a listener is explicitly verified;
never publish them without their required exit capabilities.

MaCross and Entry Engine Lab Independent MAX SERIES means TOTAL simultaneously
open instance-owned native BUY+SELL positions, not consecutive signals or a
per-direction allowance. Keep their MaIndependentEntries.mqh capacity logic
consistent without merging their storage namespaces. Historical admission uses
actual exit-time occupancy; DATA does not fabricate a released slot. Validate
with scripts/validate_ma_concurrent_capacity.ps1 and the full Entry Lab probe.

All four families have NativeRiskBalance.mqh: optional native percentage-risk
reference balance, 0 preserves the existing account basis. Keep the four core
copies identical. Listener payload budgets must remain on the original account
basis; never substitute the native override into published risk fields.
See NATIVE_BALANCE.md and scripts/validate_native_balance.ps1 for verification.

## Test Storage Policy

The user reports a 180 GB project and prohibits further per-run bulk file
generation. Reuse one existing isolated MT5 worker and a fixed bounded build
directory. Do not create timestamped source/dependency trees, duplicate
terminal installations or history databases, or accumulate release backups.
Do not run older validation scripts unchanged if they create those copies.
Prefer focused tests and small reports; retain large trade traces only when
needed to diagnose a specific issue. Do not request multi-year tick downloads
unnecessarily. Do not add generated workers, history or build artifacts to Git.
Remove only disposable artifacts created by the current task after verification,
with resolved-path safety checks. Existing files, backups and history must not
be deleted without the user's explicit approval. Production isolation and
accuracy checks still apply; minimal necessary test artifacts are permitted.
