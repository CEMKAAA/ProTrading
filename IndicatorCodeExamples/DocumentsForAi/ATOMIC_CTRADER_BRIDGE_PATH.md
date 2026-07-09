# Atomic cTrader Bridge Path

For the cTrader `AtomicFileBridge_cTrader_Listener` robot, set this input:

```text
Bridge Latest Path = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\AtomicFileBridge_Latest.csv
```

This is the MT4 Common Files bridge output written by `AtomicBridge_MT4_EA.mq4`:

```text
InpFileBridgeLatestFile = AtomicFileBridge_Latest.csv
InpFileBridgeUseCommonFiles = true
```

Notes:
- Use the full absolute path in cTrader.
- This path is shared across MT4/MT5/cTrader through MetaQuotes `Terminal\Common\Files`.
- For XAUUSD M1 Atomic instances, the same latest file is used; symbol/timeframe filtering is handled by the listener/event contents, not by changing this path.
