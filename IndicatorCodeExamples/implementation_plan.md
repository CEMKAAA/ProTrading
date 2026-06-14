# ERL→IRL Higher Timeframe Swing Model EA

## Strategy Algoritmization

### Core Concept
```
ERL sweep → Reclaim → HTF FVG forms → Price taps FVG on entry TF → ENTRY
```

### Layer 1: Swing Level Detection (ERL = External Range Liquidity)
```
Swing High(N): bar[i].high > max(bar[i-N..i-1].high) AND bar[i].high > max(bar[i+1..i+N].high)
Swing Low(N):  bar[i].low  < min(bar[i-N..i-1].low)  AND bar[i].low  < min(bar[i+1..i+N].low)
```
- HTF: H4/D1 bars, N=5 (configurable)
- Store last `MaxSwings=20` significant highs/lows

### Layer 2: FVG Detection (IRL = Internal Range Liquidity)
```
Bullish FVG: bar[i-1].high < bar[i+1].low  → zone = [bar[i-1].high, bar[i+1].low]
Bearish FVG: bar[i-1].low  > bar[i+1].high → zone = [bar[i+1].high, bar[i-1].low]
```
- Minimum FVG size filter: `fvgSize > ATR * MinFvgPct / 100`
- Only FVGs that form AFTER a sweep+reclaim carry weight

### Layer 3: Liquidity Sweep + Reclaim Detection
```
Bullish Sweep (of low):
  1. bar[j].low < swingLow[k]              (sweep)
  2. bar[j].close > swingLow[k]            (reclaim on same bar)
  OR bar[j+1].close > swingLow[k]          (reclaim on next bar)

Bearish Sweep (of high):
  1. bar[j].high > swingHigh[k]             (sweep)
  2. bar[j].close < swingHigh[k]            (reclaim on same bar)
  OR bar[j+1].close < swingHigh[k]          (reclaim on next bar)
```

### Layer 4: Signal Generation
```
After bullish sweep+reclaim on HTF:
  1. Scan HTF bars after reclaim for FVG
  2. If bullish FVG found → this is the "draw" target
  3. Drop to entry TF (M15/M30/H1)
  4. Wait for price to tap the FVG zone (low enters FVG)
  5. ENTRY = close of the bar that taps FVG
  6. SL = FVG candle low (bar[i-1].high for bullish) - buffer
  7. TP = entry + risk * R:R
```

### Layer 5: Weekly Bias Filter (Optional)
```
Bullish bias: Weekly close > Weekly open (previous completed week)
Bearish bias: Weekly close < Weekly open
Signal must align with bias (sweep low = bullish setup → needs bullish bias)
```

---

## Backtest Combinations

| Dimension | Options | Count |
|---|---|---|
| HTF Structure | H4, D1 | 2 |
| Entry TF | M15, M30, H1 | 3 |
| Swing Lookback | 3, 5, 8 | 3 |
| R:R | 1.0, 1.5, 2.0 | 3 |
| HC+BE (for ≥1.5R) | ON/OFF | 2 |
| Weekly Bias Filter | ON/OFF | 2 |
| **Total** | | **216** |

> [!IMPORTANT]
> HC+BE only applies when R:R ≥ 1.5. For R:R=1.0, HC=OFF always → 2×3×3×(1 + 2×2) = 2×3×3×5 = 90... 
> Actually: for RR=1.0 → 1 HC option, for RR=1.5 → 2, for RR=2.0 → 2 = 5 per (HTF,EntryTF,Swing) = 2×3×3×2×5 = 180 combos

---

## File: `ERL_IRL_SwingModel_EA.mq5`

### Structure (~1400 lines)

```
1.  Header + #include + enums + inputs          (~80 lines)
2.  State variables + structs                    (~80 lines)
3.  Utility functions                            (~40 lines)
4.  Swing Level Detection                        (~60 lines)
5.  FVG Detection                                (~60 lines)
6.  ERL Sweep + Reclaim Detection                (~70 lines)
7.  Signal Pipeline (combines layers 1-4)        (~100 lines)
8.  Trade Simulation (for backtesting)           (~80 lines)
9.  Historical Signal Drawing                    (~80 lines)
10. Trade Execution (live)                       (~80 lines)
11. Position Management + TP/SL watchdog         (~60 lines)
12. Audit Engine (Trade CSV + Probe + HistScan)  (~120 lines)
13. Brute-Force Backtest Engine                  (~180 lines)
14. Dashboard (700×580)                          (~200 lines)
15. Event Handlers                               (~100 lines)
```

### Dashboard Layout
```
┌─ ERL→IRL SWING MODEL v1.0 ──────────────────────────────┐
│ EA ON | NQ100 | Structure: H4 | Entry: M30 | Swing: 5   │
├─ ▸ CONTROLS ─────────────────────────────────────────────┤
│ HTF:  [H4] [D1]                                          │
│ ENTRY:[M15] [M30] [H1]                                   │
│ SWING:[3] [5] [8]                                        │
│ R:R:  [1:1R] [1:1.5R] [1:2R]                             │
│ HC+BE:[HC@TP1: OFF]   BIAS:[ON]                          │
├─ ▸ SIGNAL AUDIT ─────────────────────────────────────────┤
│ 14D: 8 sig | 5W 2L 1O | WR 62.5% | Net 3.2R | PF 2.1   │
│ ██████████████████░░░░░ WR 62.5%                         │
├─ ▸ EXECUTION ────────────────────────────────────────────┤
│ Status: READY | Spread: GOOD 12pts                       │
│ Last: BUY sweep@18420 FVG@18380-18395 Entry@18392        │
├─ ▸ BACKTEST ENGINE ──────────────────────────────────────┤
│ Weeks: [__4__] [▶ RUN BACKTEST] [■ STOP]   180 combos   │
│ ██████████████░░░░░░  96/180 (53%)  4.2s                 │
│ H4 M30 Sw=5 1:1.5R HC BE → 5W 2L WR=71.4% Net=2.8R     │
└──────────────────────────────────────────────────────────┘
```

### CSV Output (Backtest)
`ERL_IRL_BruteBacktest_YYYYMMDD_HHmmss.csv`
```
timestamp, htf, entry_tf, swing_lookback, rr, hc_tp1, bias_filter,
weeks, total, wins, losses, win_rate, net_r, won_r, lost_r, pf, avg_r
```

### CSV Output (Audit)
`ERL_IRL_TradeAudit_YYYYMMDD.csv` — Signatics pattern, 25+ columns
`ERL_IRL_PositionProbe_YYYYMMDD.csv` — 30s interval

---

## Verification
- 0 compile errors
- Historical signals visible on chart with arrows + text
- Dashboard interactive (all toggles work)
- Backtest produces CSV with 180 rows
- Audit CSVs generated in MQL5/Files/
