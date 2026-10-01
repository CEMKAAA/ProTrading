# Open Capacity Verification: 2026-10-01

Build: MaCrossORB-0.15-OpenCapacity.
Stage: `.tmp/ma_capacity_20261001_190353`.
Production EA and both before/after probes: 0 errors, 0 warnings.

The same frozen USDJPYm M5 5W Legacy fixture produced 138 trades before and
after. Counts, signal/entry/exit timestamps, direction, geometry and net R
matched exactly:
`ee3fac005a2c32fc1194e1aa3f0d4a3d226cff4762cfb565208a464d66f44101`.
After-change probe: 35 checks, 0 failures.

Independent MAX=10 produced 10 trades/10O; MAX=3 produced 3 trades/3O with
deliberately wide stops. Mixed directions did not reset the total capacity.
Reverse-close and warm/cold audit checks passed; closed slots could be reused
without exceeding the simultaneous limit.

The native OPEN counter reads only positions owned by this symbol/magic.
It updates from timer/trade events and shows the applied limit, not unapplied
edit contents. No real orders were submitted: live broker fills, latency and
all filter combinations are not verified by these regression tests.
Existing over-limit positions are not force-closed. Unknown audit exit times
retain capacity through the cutoff rather than inventing a close.

Changed production sources: MaCrossOverOrbEA.mq5, MaIndependentEntries.mqh,
OrbStrategyUserMetrics.mqh. Independent metric metadata was versioned so old
series-based results are not reused. Strategy schema and Legacy metric keys
are unchanged. No ORB, Sol Advanced or listener/protocol changes.
