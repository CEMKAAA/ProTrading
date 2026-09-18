# ADV audit optimization checkpoint

Goal: improve campaign throughput without changing execution outcomes.
The legacy/default replay engine and the signal kernels were not edited.

## Implemented

An eight-slot, per-audit-run completed-day RAM cache in OrbAdvancedAuditEngine.
It retains minute bid/ask bounds and the already-built segment tree together.
On repeat access it avoids disk read, checksum decoding and tree rebuilding.
Account server, symbol and date participate in lookup. The current trading
day is excluded; all slots are cleared when a new audit starts or ADV toggles.
Allocation/copy failure falls back to the existing loading path. No tick
ordering, price, cost, SL/TP, half-close, or forced-exit calculations changed.

Root ORB and MA previously contained identical ADV headers. The new header is
currently deployed only for ORB ADV. MA test compilation hit repeated EX5 write errors; its ADV header was restored to the previous version and its DEMO installation was not changed. Default mode is unchanged.

## Checks

- MT5 actual-code cache probe: 1,002 checks, zero failures, including 1,000
  alternating cached-day loads with exact content checks and run-reset cleanup.
- Existing independent bid/ask reference test: 1,200 synthetic paths passed.
  19,605 versus 436,391 visited ticks (95.51% fewer) describes the existing
  segment-tree algorithm, NOT incremental speedup from this new cache.
- ORB compile/timezone/native-risk checks also pass.
- No full 1Y/5Y runtime speedup has been established for this patch.

## Next measurements

Benchmark identical settings/data in cold and warm terminal states separately.
Record data synchronization, signal computation, index I/O, exact minute replay,
result aggregation and chart rendering. Compare netR, timestamps, exit reasons,
entry/SL/TP and complete trade counts, not merely aggregate WR.

The new cache helps overlapping trade horizons and revisited days. A workload
that visits each day only once can see little benefit or some copy overhead.
Measure that case before increasing cache size or claiming 4-5x overall gains.
The next candidate is bounded exact-minute tick reuse; it must preserve snapshot
boundaries and include history revision invalidation. Full-result memoization
must continue invalidating for every strategy/exit/filter/cost change.
