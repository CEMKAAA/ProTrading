# Daily Closed Trade Limits

Canonical EAs: ORB StrategyLibrary, MaCrossOverOrb, Sol Advanced.

Dashboard: `MAX LOSS`, `WIN TARGET`, `START HH:MM`, `APPLY DAY`. Nonnegative whole numbers;
zero disables the individual threshold. Both zero preserve previous behavior.
Settings persist in strategy metadata. Older strategies reset both to zero.

The day begins at the selected broker-server START time (default 00:00),
independently of ORB session conversion. With START 06:00, each quota period runs
from 06:00 inclusive to the next 06:00 exclusive. Older strategies default to 00:00.
Outcomes count on their close day. Only outcomes closed at the proposed entry
timestamp can block that entry. Open, DATA and flat trades do not fill a quota.
Existing open trades are not forcibly closed.

Replay uses a min-heap of admitted exits, O(log n) per exit, without lookahead.
Rejected entries do not contribute to audit results or Time Matrix statistics.
Admitted trades retain their original entry-day/hour bucket even if closed later.
Time Matrix masks are never changed automatically.

Live enforcement rebuilds fully closed symbol/magic-owned native MT5 positions
from history, including commissions, fees and swap. Partial closes count only
after full closure. Mixed netting ownership and history errors fail closed.
Separate native positions count separately, including separate partial-order legs.

Remote listener-only results are not observable by MT5. With nonzero limits,
native trading must be enabled; otherwise new entries/publications are blocked.
Native plus publication uses native outcomes; remote results may differ.
No listener protocol or CSV schema was changed.

Validation (no orders submitted):

```powershell
& scripts/validate_daily_quota.ps1 -CompileEAs
& scripts/validate_time_matrix.ps1 -ProbeOnly
```

The second command needs Common Files write permission. Tests cover causal exit
counting, midnight reset, overlapping exits, missing timestamps, old-strategy reset,
current edit values on Apply, modal isolation, Time Matrix exclusion and actual
strategy save/load.
