# Advanced Gold ORB Trading Bot

A professional-grade algorithmic trading bot for Gold (XAUUSD) using ICT (Inner Circle Trader) concepts and Opening Range Breakout strategy.

## 🎯 Features

### ICT Concepts Implemented
- **Fair Value Gaps (FVG)**: Detects 3-candle imbalances with displacement validation
- **Order Blocks (OB)**: Identifies institutional supply/demand zones
- **Liquidity Detection**: Tracks sweeps and liquidity pools
- **Multi-Session Analysis**: Asian, London, NY sessions for bias determination

### Risk Management
- Dynamic position sizing (% of account balance)
- Daily loss limits with automatic shutdown
- Maximum concurrent risk exposure control
- Spread filtering for optimal execution
- Adaptive stop-loss validation (min/max constraints)

### Trade Management
- Automatic breakeven stops at 1R profit
- ATR-based trailing stops for trend following
- Dynamic risk-reward ratios (2R for tight stops, 1R for wider)
- Retry logic for requotes and slippage
- Friday auto-close for weekend risk

## 📁 Project Structure

```
├── main.py                 # Main bot orchestrator
├── config.py              # Centralized configuration
├── logger.py              # Logging setup
├── data_manager.py        # MT5 data handling & caching
├── session_analyzer.py    # Session levels & bias
├── ict_analyzer.py        # ICT pattern recognition
├── risk_manager.py        # Position sizing & limits
├── trade_executor.py      # Order execution & management
└── requirements.txt       # Python dependencies
```

## 🚀 Installation

### Prerequisites
- Python 3.8+
- MetaTrader 5 terminal installed
- Active MT5 broker account

### Setup

1. **Clone or download files**
   ```bash
   cd /path/to/bot
   ```

2. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure bot**
   Edit `config.py` to adjust:
   - Risk parameters (`RISK_PERCENT`, `MAX_DAILY_LOSS_USD`)
   - Trading hours (`ORB_START_TIME`, `TRADE_START_TIME`)
   - ICT thresholds (`MIN_FVG_GAP`, `DISPLACEMENT_PERCENTILE`)
   - News windows (`NO_TRADE_WINDOWS`)

4. **Ensure MT5 is running**
   - Open MetaTrader 5
   - Login to your trading account
   - Enable algo trading (Tools → Options → Expert Advisors)

## ▶️ Usage

### Run the bot
```bash
python main.py
```

### What happens:
1. Connects to MT5 and detects broker timezone
2. Waits for market open (9:30 AM NY)
3. Calculates premarket levels (Previous Day, Asian, London)
4. Determines session bias (bullish/bearish/neutral)
5. Establishes Opening Range (9:30-9:45 AM)
6. Scans for FVG + Order Block setups on ORB breakout
7. Executes trades with risk management
8. Trails stops automatically
9. Closes all positions on Friday 3:30 PM

### Stop the bot
- Press `Ctrl+C` in terminal
- Or close the terminal window

## ⚙️ Configuration Guide

### Risk Settings (`config.py`)

```python
RISK_PERCENT = 1.0              # Risk per trade (1% recommended)
MAX_DAILY_LOSS_USD = -150.0     # Stop after losing $150
MAX_TOTAL_RISK_USD = 200.0      # Max concurrent exposure
```

### ICT Parameters

```python
MIN_FVG_GAP = 0.30              # Minimum FVG size ($0.30)
DISPLACEMENT_PERCENTILE = 75    # Body must exceed 75th percentile
OB_MIN_BODY_PERCENT = 60        # Order block body > 60% of range
```

### Trading Hours (NY Time)

```python
ORB_START_TIME = time(9, 30)    # ORB calculation start
ORB_END_TIME = time(9, 45)      # ORB calculation end
TRADE_START_TIME = time(9, 45)  # Begin trading
TRADE_END_TIME = time(16, 0)    # Stop trading
```

### News Filter

Add high-impact events to avoid:

```python
from datetime import datetime
import pytz

ny_tz = pytz.timezone('America/New_York')

NO_TRADE_WINDOWS = [
    # FOMC example
    (datetime(2026, 3, 19, 14, 0, tzinfo=ny_tz), 
     datetime(2026, 3, 19, 15, 0, tzinfo=ny_tz)),
    
    # NFP example
    (datetime(2026, 4, 3, 8, 0, tzinfo=ny_tz),
     datetime(2026, 4, 3, 9, 30, tzinfo=ny_tz)),
]
```

## 📊 Trading Logic

### Entry Conditions

**Bullish Entry:**
1. Session bias = Bullish (Asian/PD levels broken to upside)
2. Price closes above ORB high
3. Bullish FVG detected (3-candle gap with displacement)
4. Optional: Bullish order block for confluence
5. Stop loss: Below FVG or Order Block

**Bearish Entry:**
1. Session bias = Bearish (Asian/PD levels broken to downside)
2. Price closes below ORB low
3. Bearish FVG detected
4. Optional: Bearish order block for confluence
5. Stop loss: Above FVG or Order Block

### Exit Management

1. **Breakeven**: Move SL to entry when profit reaches 1R
2. **Trailing**: After breakeven, trail by ATR × 1.5
3. **Target**: 
   - 2R if SL < $3
   - 1R if SL ≥ $3

## 🧪 Backtesting Recommendations

This bot is **NOT backtested**. Before live trading:

1. **Forward test on demo** for 2-4 weeks
2. **Track metrics**:
   - Win rate
   - Average R multiple
   - Max drawdown
   - Profit factor
3. **Optimize parameters** for your broker's spread/slippage
4. **Start with minimum lot sizes** in live environment

### Key Metrics to Monitor

```
Win Rate: Target 40-50% (with 2R targets)
Profit Factor: Target > 1.5
Max Drawdown: Stay under 20%
Trade Frequency: 1-3 trades/day
```

## 🛠️ Troubleshooting

### Bot won't connect to MT5
- Ensure MT5 is running and logged in
- Check that algo trading is enabled
- Verify Python version (3.8+)

### No trades executing
- Check logs: `orb_bot.log`
- Verify you're in trading hours (9:45 AM - 4:00 PM NY)
- Check daily limit hasn't been hit
- Ensure bias is not 'neutral'
- Verify market is trending (ADR > $20)

### Spread errors
- Increase `MAX_SPREAD_USD` in config
- Avoid trading during high-volatility news
- Check broker spreads in MT5

### Missing data
- Reduce `DATA_CACHE_BARS` if memory issues
- Verify MT5 has historical data (5000+ M1 bars)

## 📈 Performance Optimization

### Parameter Tuning

Adjust these based on your results:

```python
# Tighter FVG filter for quality trades
MIN_FVG_GAP = 0.40  # Increase from 0.30

# More aggressive displacement
DISPLACEMENT_PERCENTILE = 80  # Increase from 75

# Wider stops for volatility
MAX_SL_USD = 15.00  # Increase from 10.00
```

### Reduce Trade Frequency

```python
# Only trade stronger trends
MIN_ADR_FOR_TREND = 25.0  # Increase from 20.0

# Require larger ORB range
# In session_analyzer.py, increase min range from 0.50
```

## ⚠️ Disclaimers

- **Trading involves risk**: You can lose money
- **Not financial advice**: Do your own research
- **Test thoroughly**: Never trade live without demo testing
- **Monitor regularly**: Bots can malfunction
- **No guarantees**: Past performance ≠ future results

## 🔄 Updates & Maintenance

### Weekly Tasks
- Review trade logs
- Update `NO_TRADE_WINDOWS` with upcoming news
- Check broker connectivity

### Monthly Tasks
- Analyze performance metrics
- Optimize parameters if needed
- Update MT5 and Python packages

## 📞 Support

For issues:
1. Check `orb_bot.log` for errors
2. Review configuration settings
3. Verify MT5 connection and data

## 📝 License

This is educational software. Use at your own risk.

---

**Version**: 2.0  
**Last Updated**: February 2026  
**Compatible MT5 Build**: 3770+
