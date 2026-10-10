# MT5 History Capacity Diagnostic

## Cause

The actual BTCUSDm MA MTF requests failed at the local chart bar limit,
not a proven broker tick-history gap. The 2W job copied 100,000 bars,
reported max=100000, and its first returned candle was 40 minutes later
than the required signal-state origin. The 5W job reported the same
capacity issue (35 minutes missing). The adapter correctly refused to
fabricate an audit using incomplete signal state, but the web explanation
did not identify the terminal setting.

After the user increased the terminal limit, cloud job
4765a6cb-be84-44a3-806f-6d8ab8cbeaa8 completed with terminal-reported
9W / 0L / 1O, +0.09R, DATA=0 and coverageComplete=true. This is the user's
successful live workflow, not an independently reproduced broker test.

## Change

- Added a strict, presentation-only recognizer for the native capacity diagnostic.
- Passed matching job detail to terminal and audit error explanations.
- Added actionable English, Turkish and German MT5 setup instructions.
- Kept the original native failure code and full diagnostic intact.
- No EA source, binary, signal mathematics, strategy values or authorization changed in this fix.

## Verification

- 15 unit/protocol/progress tests passed, including the actual 2W/5W diagnostics,
  incomplete downloads, malformed dates, unrelated failures and Unicode translations.
- TypeScript: no errors.
- GitHub Pages production build and public-artifact checks passed.
- Headless browser against the real exported frontend with mock API: Turkish
  instructions, native detail, matching terminal error, no fake results or
  completion percentage, and mobile width passed.
- Public files were compared byte-for-byte against staged Git blobs before push.
- Public frontend commit: 839afe5725881e6b7185334a21ba96a444ad0ffd.

An increased limit is not a guarantee of history availability for every broker
or audit window. Real broker data gaps retain their original explanation.
