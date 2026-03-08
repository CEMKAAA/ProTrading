"""
Quick Test Script - Verify bot components without trading

Run this to test:
- MT5 connection
- Data retrieval
- Session analysis
- ICT pattern detection

No trades will be executed.

Can be run standalone (python test_bot.py) or via pytest.
"""

import MetaTrader5 as mt5
from datetime import datetime, timezone
import pytz

from logger import logger
from config import TARGET_SYMBOL
from data_manager import DataManager
from session_analyzer import SessionAnalyzer
from ict_analyzer import ICTAnalyzer


def test_mt5_connection():
    """Test MT5 connection"""
    logger.info("=" * 60)
    logger.info("TESTING MT5 CONNECTION")
    logger.info("=" * 60)

    assert mt5.initialize(), "MT5 initialization failed"
    logger.info("MT5 initialized")

    assert mt5.symbol_select(TARGET_SYMBOL, True), f"Symbol {TARGET_SYMBOL} not available"
    logger.info(f"Symbol {TARGET_SYMBOL} selected")

    tick = mt5.symbol_info_tick(TARGET_SYMBOL)
    assert tick is not None, "No tick data"
    logger.info(f"Current price: Bid={tick.bid} Ask={tick.ask}")

    account = mt5.account_info()
    if account:
        logger.info(f"Account: {account.login}")
        logger.info(f"   Balance: ${account.balance:.2f}")
        logger.info(f"   Equity: ${account.equity:.2f}")


def test_data_retrieval():
    """Test data manager"""
    logger.info("")
    logger.info("=" * 60)
    logger.info("TESTING DATA RETRIEVAL")
    logger.info("=" * 60)

    tick = mt5.symbol_info_tick(TARGET_SYMBOL)
    broker_time = datetime.fromtimestamp(tick.time)
    utc_time = datetime.fromtimestamp(tick.time, tz=timezone.utc).replace(tzinfo=None)
    offset_minutes = int((broker_time - utc_time).total_seconds() / 60)
    broker_tz = pytz.FixedOffset(offset_minutes)
    ny_tz = pytz.timezone('America/New_York')

    logger.info(f"Broker TZ: UTC{'+' if offset_minutes >= 0 else ''}{offset_minutes // 60}")

    dm = DataManager(TARGET_SYMBOL, broker_tz, ny_tz)
    df = dm.get_data(bars=100)

    assert not df.empty, "No data retrieved"
    logger.info(f"Retrieved {len(df)} bars")
    logger.info(f"   First bar: {df.index[0]}")
    logger.info(f"   Last bar: {df.index[-1]}")
    logger.info(f"   Current close: {df.iloc[-1].close:.2f}")


def test_session_analysis():
    """Test session analyzer"""
    logger.info("")
    logger.info("=" * 60)
    logger.info("TESTING SESSION ANALYSIS")
    logger.info("=" * 60)

    tick = mt5.symbol_info_tick(TARGET_SYMBOL)
    broker_time = datetime.fromtimestamp(tick.time)
    utc_time = datetime.fromtimestamp(tick.time, tz=timezone.utc).replace(tzinfo=None)
    offset_minutes = int((broker_time - utc_time).total_seconds() / 60)
    broker_tz = pytz.FixedOffset(offset_minutes)
    ny_tz = pytz.timezone('America/New_York')

    dm = DataManager(TARGET_SYMBOL, broker_tz, ny_tz)
    sa = SessionAnalyzer(dm)

    broker_now = datetime.fromtimestamp(tick.time).replace(tzinfo=broker_tz)
    ny_now = broker_now.astimezone(ny_tz)
    current_date = ny_now.date()

    sa.analyze_premarket(current_date)

    assert sa.bias is not None, "Bias not computed"
    logger.info(f"Bias: {sa.bias.upper()}")
    if sa.next_liquidity:
        logger.info(f"   Next liquidity: ${sa.next_liquidity:.2f}")
    logger.info(f"   Trending: {sa.is_trending}")


def test_ict_patterns():
    """Test ICT analyzer"""
    logger.info("")
    logger.info("=" * 60)
    logger.info("TESTING ICT PATTERN DETECTION")
    logger.info("=" * 60)

    tick = mt5.symbol_info_tick(TARGET_SYMBOL)
    broker_time = datetime.fromtimestamp(tick.time)
    utc_time = datetime.fromtimestamp(tick.time, tz=timezone.utc).replace(tzinfo=None)
    offset_minutes = int((broker_time - utc_time).total_seconds() / 60)
    broker_tz = pytz.FixedOffset(offset_minutes)
    ny_tz = pytz.timezone('America/New_York')

    dm = DataManager(TARGET_SYMBOL, broker_tz, ny_tz)
    ict = ICTAnalyzer()

    df = dm.get_data(bars=200)
    assert not df.empty, "No data for ICT analysis"

    fvg_bull = ict.find_fvg(df, 'bullish')
    if fvg_bull:
        logger.info(f"Bullish FVG detected, Size: ${fvg_bull['size']:.2f}")
    else:
        logger.info("No bullish FVG in recent data")

    fvg_bear = ict.find_fvg(df, 'bearish')
    if fvg_bear:
        logger.info(f"Bearish FVG detected, Size: ${fvg_bear['size']:.2f}")
    else:
        logger.info("No bearish FVG in recent data")

    ob_bull = ict.find_order_block(df, 'bullish')
    if ob_bull:
        logger.info(f"Bullish OB: {ob_bull['low']:.2f} - {ob_bull['high']:.2f}")
    else:
        logger.info("No bullish OB in recent data")

    ob_bear = ict.find_order_block(df, 'bearish')
    if ob_bear:
        logger.info(f"Bearish OB: {ob_bear['low']:.2f} - {ob_bear['high']:.2f}")
    else:
        logger.info("No bearish OB in recent data")

    liquidity = ict.find_liquidity_levels(df)
    assert liquidity is not None, "Liquidity detection failed"
    logger.info(f"Liquidity Highs: {[f'{h:.2f}' for h in liquidity['highs'][:3]]}")
    logger.info(f"Liquidity Lows: {[f'{l:.2f}' for l in liquidity['lows'][:3]]}")


def main():
    """Run all tests (standalone mode)"""
    logger.info("")
    logger.info("STARTING BOT COMPONENT TESTS")
    logger.info("")

    tests = [
        ("MT5 connection", test_mt5_connection),
        ("Data retrieval", test_data_retrieval),
        ("Session analysis", test_session_analysis),
        ("ICT patterns", test_ict_patterns),
    ]

    passed = 0
    failed = 0
    for name, func in tests:
        try:
            func()
            passed += 1
        except Exception as e:
            logger.error(f"FAILED: {name} - {e}")
            failed += 1

    logger.info("")
    logger.info("=" * 60)
    if failed == 0:
        logger.info(f"ALL {passed} TESTS PASSED - Bot is ready to run")
        logger.info("To start trading: python main.py")
    else:
        logger.info(f"{failed} TESTS FAILED, {passed} passed - Check logs above")
        logger.info("Fix issues before running bot")
    logger.info("=" * 60)

    mt5.shutdown()


if __name__ == "__main__":
    main()
