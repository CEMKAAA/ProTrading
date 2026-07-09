# ProRenko Basket Daily Target Mode Plan

Purpose: add a new experimental ProRenko execution mode where trades do not use normal per-trade SL/TP/HCBE geometry. Instead, position size is based on a daily target pip distance and account percentage, while protection is handled by daily max loss plus a catastrophic broker SL.

This mode is only for ProRenko. Traditional ProRenko mode must remain unchanged.

## Non-Negotiable Rules

- [x] Do not change ProRenko signal detection math.
- [x] Traditional SL/TP/HCBE mode must remain backward compatible.
- [x] Basket mode must be opt-in and default OFF.
- [x] Invert mode must remain universal and work in both traditional and basket modes.
- [x] MT4 must not send lot size as authority to MT5/cTrader. It sends risk parameters only.
- [x] MT5/cTrader listeners must calculate lot/volume from their own account equity/balance.
- [x] MT5 lot/volume risk calculations must use broker-aware profit math, not naive tick-value formulas.
- [x] Basket mode must always have a catastrophic protection SL.
- [x] Basket mode must have daily target and daily max loss controls.
- [x] All new CSV fields must be backward-compatible; missing fields mean traditional mode.

## Target Behavior

### Traditional Mode

- [x] Existing SL/TP/HCBE behavior remains unchanged.
- [x] Existing ProRenko MT4 execution remains unchanged.
- [x] Existing ProRenko MT5 listener behavior remains unchanged.
- [x] Existing ProRenko cTrader listener behavior remains unchanged.

### Basket Daily Target Mode

- [x] No normal per-trade TP.
- [x] No normal HCBE.
- [x] No normal tight trade SL.
- [x] Broker SL is catastrophic only.
- [x] Position size is calculated from target pips and target account percent.
- [x] Daily realized + floating basket PnL reaching target closes all scoped ProRenko basket trades.
- [x] Daily realized + floating basket PnL reaching max loss closes all scoped ProRenko basket trades.
- [x] After daily target or daily loss is hit, the chart/instance stops opening new basket trades until next reset day.
- [x] Reverse signal closes previous scoped basket trade before opening new direction.
- [x] Session-end close was removed from UI/behavior; use normal Window/NoTrade for start/end control.

## Basket Inputs

Add inputs and dashboard controls to ProRenko MT4:

- [x] `Basket Mode ON/OFF`
- [x] `Basket Target Pips`
- [x] `Basket Target Account %`
- [x] `Basket Max Loss Pips`
- [x] `Basket Catastrophic SL Pips`
- [x] `Basket Close On Reverse ON/OFF`
- [x] `Basket Close At Session End ON/OFF` removed/deprecated; Window/NoTrade is the only session control.
- [x] `Basket Session End Time` removed/deprecated; Window/NoTrade defines end time.
- [x] `Apply Basket` button separate from normal mode apply if needed.

Suggested safe defaults:

```text
Basket Mode: OFF
Target Pips: 500
Target Account %: 0.30
Max Loss Pips: 1000
Catastrophic SL Pips: 2500
Close On Reverse: ON
Close At Session End: OFF
Session End Time: empty
```

## Basket Lot Formula

MT4 displays preview only. MT5/cTrader execute using local account capital.

Target money:

```text
target_money = listener_account_equity_or_balance * basket_target_account_pct / 100
```

Lot/volume:

```text
money_per_1lot_at_target_pips = broker-aware profit value of target_pips for 1 lot
lot = target_money / money_per_1lot_at_target_pips
```

Daily max loss money:

```text
max_loss_money = target_money * (basket_max_loss_pips / basket_target_pips)
```

Catastrophic SL:

```text
BUY catastrophic_sl = entry - catastrophic_sl_pips * pip_size
SELL catastrophic_sl = entry + catastrophic_sl_pips * pip_size
```

Invert mode:

```text
Invert flips BUY/SELL before catastrophic SL is calculated.
Target pips, target %, max loss pips, and catastrophic SL pips do not change.
```

## CSV Schema Extension

Current ProRenko CSV fields stay first and unchanged:

```text
version,written_gmt,source_login,source_symbol,source_tf,event_id,source,direction,signal_time,bridge_entry,sl,tp,half_trigger,half_label,source_build,source_bid,source_ask,risk_pct
```

Append fields:

- [x] `trade_mode`
- [x] `basket_target_pips`
- [x] `basket_target_pct`
- [x] `basket_max_loss_pips`
- [x] `basket_catastrophic_sl_pips`
- [x] `basket_close_on_reverse`
- [x] `basket_close_session_end` kept in CSV for compatibility; MT4 writes `false`.
- [x] `basket_session_end_time` kept in CSV for compatibility; MT4 writes empty.
- [x] `basket_day_key`

Values:

```text
trade_mode=traditional
trade_mode=basket_daily_target
```

Backward compatibility:

- [x] If `trade_mode` is missing, listeners treat signal as `traditional`.
- [x] If `trade_mode=traditional`, listeners ignore basket fields.
- [x] If `trade_mode=basket_daily_target`, listeners use basket fields and ignore normal TP/HCBE logic.

## Implementation Phases

### Phase 1 - Helper Tool

- [x] Create `IndicatorCodeExamples/DrawPipRectangle.mq4`.
- [x] Reuse safe UI patterns from `DrawRiskRectangle.mq4`.
- [x] Draw one draggable rectangle.
- [x] Show rectangle height in pips.
- [x] Show top price, bottom price, symbol pip size.
- [x] Optional: show money value for a user-provided lot.
- [x] No trading functionality.
- [ ] Compile check. (manual MT4 compile pending)

### Phase 2 - ProRenko MT4 Mode Separation

- [x] Add basket input variables to `ProRenkoBridge_MT4_EA.mq4`.
- [x] Add runtime basket variables.
- [x] Add dashboard controls in a separate Basket section.
- [x] Add toggle between `TRADITIONAL` and `BASKET`.
- [x] Ensure traditional controls remain usable in traditional mode.
- [x] Ensure basket controls do not mutate traditional TP/HCBE/SL settings.
- [x] Ensure default mode is traditional.
- [x] Audit dashboard apply events with all basket params.

### Phase 3 - ProRenko MT4 Basket Geometry

- [x] Add basket trade plan builder.
- [x] For basket mode, calculate entry from existing ProRenko execution entry rules.
- [x] Apply invert direction before basket geometry.
- [x] Calculate catastrophic SL from `basket_catastrophic_sl_pips`.
- [x] Set TP to zero/off for local MT4 basket execution.
- [x] Set half trigger to zero/off for basket mode.
- [x] Ensure broker stop guard validates catastrophic SL only.
- [x] Draw basket lines on chart:
  - [x] entry line
  - [x] catastrophic SL line
  - [x] optional daily target/loss text panel
- [x] Keep historical traditional lines unchanged.

### Phase 4 - ProRenko MT4 Basket Execution And Guards

- [x] Open basket trades with catastrophic SL and no TP.
- [x] Close reverse scoped ProRenko basket trades when reverse signal arrives.
- [x] Calculate chart/instance daily realized + floating basket PnL.
- [x] Close all scoped basket trades when daily target money is reached.
- [x] Close all scoped basket trades when daily max loss money is reached.
- [x] Block new basket trades after daily target/loss hit until next reset day.
- [x] Session-end close removed/deprecated; Window/NoTrade handles time end.
- [x] Audit all basket events compactly.

Required audit events:

- [x] `basket_signal_received`
- [x] `basket_order_sent`
- [x] `basket_order_failed`
- [x] `basket_reverse_close`
- [x] `basket_target_hit_close`
- [x] `basket_loss_hit_close`
- [x] `basket_session_close`
- [x] `basket_blocked_day_done`

### Phase 5 - ProRenko MT4 CSV Writer Extension

- [x] Extend `FileBridgeWriteHeader()` with basket fields appended.
- [x] Extend `FileBridgeWriteRow()` with basket values.
- [x] Traditional rows write `trade_mode=traditional`.
- [x] Basket rows write `trade_mode=basket_daily_target`.
- [x] Basket rows send catastrophic SL in `sl` field.
- [x] Basket rows send `tp=0`.
- [x] Basket rows send `half_trigger=0` and basket half label/off label.
- [x] Existing MT5/cTrader listeners must still parse first 18 fields.
- [x] New listeners parse appended fields.

### Phase 6 - MT5 ProRenko Listener Parser

- [x] Extend `BridgeSignal` in `ProRenkoFileBridge_MT5_Executor_EA.mq5`.
- [x] Parse optional basket fields.
- [x] Missing mode defaults to traditional.
- [x] Dashboard/audit shows mode.
- [x] Traditional path unchanged.

New fields in MT5 signal struct:

- [x] `tradeMode`
- [x] `basketTargetPips`
- [x] `basketTargetPct`
- [x] `basketMaxLossPips`
- [x] `basketCatastrophicSlPips`
- [x] `basketCloseOnReverse`
- [x] `basketCloseSessionEnd`
- [x] `basketSessionEndTime`
- [x] `basketDayKey`

### Phase 7 - MT5 Basket Execution

- [x] For basket mode, validate catastrophic SL only.
- [x] Do not require TP.
- [x] Disable HCBE management for basket positions.
- [x] Calculate lot using `OrderCalcProfit()` target-pip value.
- [x] Open trade with catastrophic SL and TP=0.
- [x] Preserve source TF scoping.
- [x] Close reverse scoped basket trades before opening new direction.
- [x] Track daily realized + floating PnL for scoped basket positions.
- [x] Close basket positions on target hit.
- [x] Close basket positions on max loss hit.
- [x] Session-end close removed/deprecated; Window/NoTrade handles time end.
- [x] Block new basket trades after target/loss hit.

Required MT5 audit details:

- [x] `risk_calc=ordercalcprofit`
- [x] `basket_target_pips`
- [x] `basket_target_pct`
- [x] `basket_target_money`
- [x] `basket_max_loss_pips`
- [x] `basket_max_loss_money`
- [x] `basket_catastrophic_sl_pips`
- [x] `actual_risk_to_cat_sl`
- [x] `target_based_lot`

### Phase 8 - cTrader ProRenko Listener Parser

- [x] Extend `BridgeSignal` in `ProRenkoFileBridge_cTrader_Listener.cs`.
- [x] Parse optional basket fields.
- [x] Missing mode defaults to traditional.
- [x] Dashboard/audit shows mode.
- [x] Traditional path unchanged.

### Phase 9 - cTrader Basket Execution

- [x] For basket mode, use `basket_catastrophic_sl_pips` as stop loss pips.
- [x] No take profit.
- [x] No HCBE.
- [x] Volume calculated from target pips + target percent using cTrader local equity/balance.
- [x] Preserve source TF scoping.
- [x] Close reverse scoped basket trades before opening new direction.
- [x] Daily target/loss monitor closes scoped basket positions.
- [x] Session-end close removed/deprecated; Window/NoTrade handles time end.
- [x] Block new basket trades after day done.

### Phase 10 - Validation

- [ ] Compile `DrawPipRectangle.mq4`.
- [ ] Compile `ProRenkoBridge_MT4_EA.mq4`.
- [ ] Compile `ProRenkoFileBridge_MT5_Executor_EA.mq5`.
- [ ] Compile `ProRenkoFileBridge_cTrader_Listener.cs`.
- [ ] Traditional mode smoke test: old behavior unchanged.
- [ ] Basket mode MT4-only smoke test.
- [ ] Basket mode MT4-to-MT5 smoke test.
- [ ] Basket mode MT4-to-cTrader smoke test.
- [ ] Invert basket smoke test.
- [ ] Daily target close test.
- [ ] Daily max loss close test.
- [ ] Reverse signal close/open test.
- [ ] CSV backward compatibility test.
- [ ] Audit compactness check.

## Rollback Notes

The user created a git checkpoint with header:

```text
Checkpoint before the new mode
```

If unexpected behavior appears:

- [ ] Stop live EAs/listeners first.
- [ ] Revert changed files to checkpoint.
- [ ] Recompile and redeploy traditional ProRenko only.

## Implementation Progress Log

Update this section after each implementation step.

- [x] Phase 1 started.
- [x] Phase 1 completed.
- [x] Phase 2 started.
- [x] Phase 2 completed.
- [x] Phase 3 started.
- [x] Phase 3 completed.
- [x] Phase 4 started.
- [x] Phase 4 completed.
- [x] Phase 5 started.
- [x] Phase 5 completed.
- [x] Phase 6 started.
- [x] Phase 6 completed.
- [x] Phase 7 started.
- [x] Phase 7 completed.
- [x] Phase 8 started.
- [x] Phase 8 completed.
- [x] Phase 9 started.
- [x] Phase 9 completed.
- [ ] Phase 10 started.
- [ ] Phase 10 completed.

- [x] 2026-07-08: MT4/MT5/cTrader source implementation completed for Basket Daily Target mode; manual terminal compile/smoke tests remain Phase 10.
- [x] 2026-07-08: Removed ProRenko Basket SESS ON/OFF and SESS END controls. Time boundaries are controlled by normal Window/NoTrade; CSV session fields remain compatibility-only false/empty.

