# MaCrossOver listener review

## Findings and changes

- cTrader listener existed, but lacked ORB's accepted-signal seal guard.
  Added rejection of entries without |ACCEPTED1. Close-only events remain valid
  after channel, symbol, source namespace and timeframe validation.
- A failed cTrader close-only request was marked permanently rejected. It now
  retries with a 10-second throttle while the event remains eligible/current.
  This is not a durable close-command queue: age/newer CSV events still matter.
- No dedicated MaCrossOver NinjaTrader/Quantower adapters existed. Added thin
  adapters over the existing production execution cores; no duplicated core.
- MaCrossOver uses its own namespace, CSV basename, order prefix and audit
  prefixes. The cTrader TF-inclusive scope hash is preserved, not replaced
  with ORB's older scope formula. Existing MaCrossOver ownership is unchanged.

## Files

- macrossover_orb/MaCrossOver_cTrader_Listener.cs
- NinjaTrader/MaCrossOver_NinjaTrader_Listener.cs
- Quantower/MaCrossOver_Quantower_Listener.cs

NinjaTrader also needs ProductionFileBridgeNinjaCore.cs and
TradeDayComplianceNinjaCore.cs. Quantower needs ProductionFileBridgeQuantowerCore.cs.
Use the existing shared files once; do not install duplicate core copies.

## Setup

Bridge path:
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MaCrossOverBridge_Latest.csv

Set Bridge Channel to the EA dashboard channel. Set Source TF Filter to the
EA's effective signal timeframe in minutes (M1=1, M5=5, M15=15, H1=60), NOT
the internal H4 MA confirmation timeframe. Prefer Scoped Latest=true.
Source namespace=MaCrossOver|. Use the MaCrossOver listener, not ORB listener.

MT5 PUB ON enables publishing; NAT controls native orders separately.
Select the destination account and economic-equivalent symbol/contract.
Ninja/Quantower default aliases are JP225/JPN225 variants and default source TF
is 5: for other markets set the aliases/TF appropriately. Default futures
geometry rebases distances to the actual futures entry. Risk/contracts are
computed using the destination account with configured guards.

Scoped example: MaCrossOverBridge_Latest_C1_JP225m_5.csv.
Use the generic path above for automatic channel/scoped resolution.

Netting futures accounts do NOT offer independent hedged positions on the
same contract. Do not run competing pipelines/manual trades on the same
account+contract and assume channels remove broker-level netting. Shared
cores have foreign-exposure checks, but channel identity is not hedging.

## Verification limits

Builds use installed real SDK assemblies. cTrader and Quantower compile with
zero errors/warnings; NinjaTrader with zero errors and 16 CS0436 warnings
because the compile-check project references the existing Custom assembly
while compiling the shared core sources. NinjaScript Editor compilation in
the real target installation is still required.

No live orders, restart-with-open-position test, disconnect test or broker
rejection simulation was run in this review. Sources have not been installed
into the live cTrader/Ninja/Quantower applications by this patch. Do not treat
compilation or reuse of the existing cores as a bug-free production guarantee.
SIM acceptance must cover BUY/SELL, SL/TP, reverse and close-only, restart,
market-closed throttling, duplicate events, wrong channel/TF/source rejection,
and target-account risk sizing before enabling a challenge account.
