# ORB native fixed-amount risk

Applies to OrbUltimateEA, OrbUltimateEA_Channel and OrbUltimateEA_StrategyLibrary.
Signal, SL/TP geometry and listener CSV schema are unchanged.

## Dashboard

1. In RISK % mode, enter the percentage intended for publishing and APPLY RISK.
2. Click RISK % to select MONEY.
3. Enter the native risk amount and APPLY RISK. Native trading still requires NAT ON.

Example: PUB 0.30%, NAT 50 USD. Editing the MONEY value leaves PUB at 0.30%.
To edit the publishing percentage, temporarily switch to RISK %, apply the
percentage, then switch back to MONEY. The two values are retained separately.
The dashboard shows NAT and PUB values together. Mode/value are persisted per
account/chart. This does not change existing open-position SL/TP or resize them.

Inputs: InpMoneyRiskDefault and InpMoneyRiskAmount. Default money mode is OFF.
Amounts are in account currency, not converted USD on non-USD accounts.
For example, a EUR account shows EUR.

## Limits

APPLY rejects nonpositive amounts and amounts above current ACCOUNT_BALANCE.
Decimal point and decimal comma are supported; malformed text is rejected.
At entry, the effective money budget is min(requested amount, current balance).
If balance subsequently falls, the effective budget falls to that balance cap;
the saved requested amount itself remains unchanged.

Existing sizing uses OrderCalcProfit, volume constraints and margin guards.
An allowed minimum lot that already exceeds the money budget is rejected.
The existing fixed-reference post-fill check is also used for MONEY, with zero
configured budget overshoot tolerance. It attempts to close on excess risk.
This is planned gross SL risk, NOT a guaranteed maximum net loss: commission,
gaps, slippage and failed close requests can increase realized loss.

## Publishing isolation

INIT, entry, close and retry snapshots use dedicated BridgeRiskPerTradePct and
BridgeRiskBudgetMoney functions. Neither reads the native money-mode flag or
amount. Existing percentage capital-basis settings are preserved. Applying a
native money amount does not rewrite the bridge INIT marker. Listener code and
CSV columns were not changed. No listener rebuild is required for this patch.

## Verification

OrbNativeMoneyRiskProbe includes the actual StrategyLibrary EA with trading
callbacks renamed and account balance/equity mocked. It tests budget caps,
native/bridge separation, zero native budget, changing balance, parser errors
and return to percentage mode. It does not submit orders or test broker fills.
The deployment script also rejects native-budget function calls in the publisher.
Run scripts/validate_orb_timezone.ps1 -InstallDemo to compile, test and deploy.
