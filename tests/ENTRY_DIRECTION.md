# Entry Direction (2026-09-26)

Applies to the canonical ORB Strategy Library, MaCrossOverOrb and Sol Advanced.

- Dashboard button cycles BOTH -> BUY ONLY -> SELL ONLY -> BOTH.
- Direction means the actual execution direction after inversion.
- Loss BUY + Loss SELL follows the same classification as the headline L count.
- Open, invalid and filtered signals are not included in the loss split.
- Filter changes cancel/rebuild the audit and participate in preparation cache keys.
- Native entry and bridge publication share the same final direction check.
- This is an entry filter, not a command to close existing positions. Existing
  NAS/reverse/SL/TP exit rules remain active.
- Strategy records carry the direction as an optional ninth TCAL1 field. Old
  eight-field records explicitly restore BOTH, preventing selection leakage.
- Chart settings use the existing double-buffered chart/account/symbol storage.
- CSV schema, listeners, risk and geometry are unchanged.

Validation: `scripts/validate_entry_direction.ps1`. The isolated contract probe
tests permissions, malformed records, legacy defaults, restart persistence,
loss counters, audit invalidation and modal click interception. It sends no orders.
Compilation/contract validation is not a live broker execution test.
