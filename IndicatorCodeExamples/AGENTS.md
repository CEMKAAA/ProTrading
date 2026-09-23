# Canonical EA Sources

For all future development, edit and compile these files in their own folders:

- ORB: `orb/OrbUltimateEA_StrategyLibrary.mq5`
- MaCross: `macrossover_orb/MaCrossOverOrbEA.mq5`
- Sol Advanced: `SolAdvanced/LiqNarrativeSol_Advanced.mq5`

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
