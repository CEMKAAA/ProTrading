"""
IBKR Historical Data Provider
Fetches historical price data from Interactive Brokers TWS/Gateway via ib_async.
Supports auto-detection of Gold contract type (CASH/CFD/Futures).
"""

import logging
import time
from datetime import datetime, timedelta
from typing import Optional, Callable, Dict, List, Tuple

import pandas as pd

logger = logging.getLogger(__name__)

# Initialize ib_async event loop for synchronous/threaded usage
try:
    from ib_async import util
    util.startLoop()
except ImportError:
    pass

# Chunk sizes per timeframe (IBKR pacing limits)
CHUNK_SIZES = {
    "M1": timedelta(days=1),
    "M5": timedelta(days=7),
    "M15": timedelta(days=14),
    "H1": timedelta(days=30),
    "H4": timedelta(days=90),
    "D1": timedelta(days=365),
}

# IBKR barSizeSetting mapping
BAR_SIZES = {
    "M1": "1 min",
    "M5": "5 mins",
    "M15": "15 mins",
    "H1": "1 hour",
    "H4": "4 hours",
    "D1": "1 day",
}

# IBKR durationStr max per request
DURATION_STRINGS = {
    "M1": "1 D",
    "M5": "7 D",
    "M15": "14 D",
    "H1": "30 D",
    "H4": "90 D",
    "D1": "1 Y",
}


class IBKRContractResolver:
    """Auto-detects the correct contract type for a given symbol on IBKR."""

    # Standard forex pairs on IBKR
    FOREX_PAIRS = {"EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "USDCHF", "NZDUSD"}

    @staticmethod
    def _is_valid_contract(contract) -> bool:
        """Check if a qualified contract is actually valid (not None, has conId)."""
        return contract is not None and getattr(contract, 'conId', 0) > 0

    @staticmethod
    def resolve_contract(ib, symbol: str):
        """
        Try to find a valid contract for the given symbol.
        For Gold (XAUUSD): tries Forex CASH → CFD → Futures GC
        For standard Forex: uses Forex CASH on IDEALPRO
        Returns (contract, whatToShow) tuple or raises ValueError.
        """
        from ib_async import Forex, CFD, Contract

        if symbol.upper() in IBKRContractResolver.FOREX_PAIRS:
            contract = Forex(symbol.upper())
            qualified = ib.qualifyContracts(contract)
            c = qualified[0] if qualified else None
            if IBKRContractResolver._is_valid_contract(c):
                logger.info(f"Resolved {symbol} as Forex CASH on IDEALPRO (conId={c.conId})")
                return c, "MIDPOINT"
            raise ValueError(f"Cannot qualify Forex contract for {symbol}")

        # Gold / XAUUSD - try multiple contract types
        if symbol.upper() in ("XAUUSD", "GOLD"):
            attempts = []

            # 1. Try Forex CASH (XAU/USD on IDEALPRO)
            try:
                contract = Forex("XAUUSD")
                qualified = ib.qualifyContracts(contract)
                c = qualified[0] if qualified else None
                if IBKRContractResolver._is_valid_contract(c):
                    logger.info(f"Resolved XAUUSD as Forex CASH on IDEALPRO (conId={c.conId})")
                    return c, "MIDPOINT"
                attempts.append("Forex CASH: not qualified (no conId)")
            except Exception as e:
                attempts.append(f"Forex CASH: {e}")

            # 2. Try CFD on SMART
            try:
                contract = CFD("XAUUSD")
                qualified = ib.qualifyContracts(contract)
                c = qualified[0] if qualified else None
                if IBKRContractResolver._is_valid_contract(c):
                    logger.info(f"Resolved XAUUSD as CFD on SMART (conId={c.conId})")
                    return c, "MIDPOINT"
                attempts.append("CFD: not qualified (no conId)")
            except Exception as e:
                attempts.append(f"CFD: {e}")

            # 3. Try Gold Futures (GC on COMEX) - front month via reqContractDetails
            try:
                contract = Contract(secType='FUT', symbol='GC', exchange='COMEX', currency='USD')
                details = ib.reqContractDetails(contract)
                if details:
                    # Pick the front-month contract (earliest expiry)
                    details.sort(key=lambda d: d.contract.lastTradeDateOrContractMonth)
                    front = details[0].contract
                    qualified = ib.qualifyContracts(front)
                    c = qualified[0] if qualified else None
                    if IBKRContractResolver._is_valid_contract(c):
                        logger.info(f"Resolved Gold as Futures GC on COMEX "
                                   f"(conId={c.conId}, expiry={c.lastTradeDateOrContractMonth})")
                        return c, "TRADES"
                attempts.append("Futures GC: not qualified")
            except Exception as e:
                attempts.append(f"Futures GC: {e}")

            raise ValueError(
                f"Cannot find Gold contract on IBKR. Tried:\n" +
                "\n".join(f"  - {a}" for a in attempts)
            )

        raise ValueError(f"Unsupported symbol: {symbol}. Supported: XAUUSD, {', '.join(IBKRContractResolver.FOREX_PAIRS)}")


class IBKRDataProvider:
    """
    Fetches historical data from IBKR TWS/Gateway.
    Uses chunked fetching with automatic retry on pacing violations.
    """

    def __init__(self):
        self._ib = None
        self._connected = False

    def connect(self, host: str = "127.0.0.1", port: int = 7497, client_id: int = 99) -> bool:
        """Connect to TWS/Gateway. Returns True on success."""
        try:
            from ib_async import IB
            self._ib = IB()
            self._ib.connect(host, port, clientId=client_id, timeout=15)
            self._connected = True
            logger.info(f"Connected to IBKR TWS at {host}:{port}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to IBKR TWS at {host}:{port}: {e}")
            self._connected = False
            raise ConnectionError(f"Cannot connect to TWS at {host}:{port}. Is TWS/Gateway running? Error: {e}")

    def disconnect(self):
        """Disconnect from TWS."""
        if self._ib and self._connected:
            try:
                self._ib.disconnect()
            except Exception:
                pass
            self._connected = False
            logger.info("Disconnected from IBKR TWS")

    def test_connection(self, host: str = "127.0.0.1", port: int = 7497) -> Dict:
        """Test TWS connectivity and return account info."""
        try:
            from ib_async import IB
            ib = IB()
            ib.connect(host, port, clientId=98, timeout=10)

            accounts = ib.managedAccounts()
            server_version = ib.client.serverVersion()

            result = {
                "connected": True,
                "accounts": accounts,
                "server_version": server_version,
                "host": host,
                "port": port,
            }

            ib.disconnect()
            return result

        except Exception as e:
            return {
                "connected": False,
                "error": str(e),
                "host": host,
                "port": port,
            }

    def fetch_historical_data(
        self,
        symbol: str,
        timeframe: str,
        start_date: datetime,
        end_date: datetime,
        progress_callback: Optional[Callable[[float, str], None]] = None,
    ) -> pd.DataFrame:
        """
        Fetch historical data from IBKR in chunks.

        Args:
            symbol: Trading symbol (e.g., "XAUUSD")
            timeframe: Timeframe string (e.g., "M1", "H1")
            start_date: Start of data range
            end_date: End of data range
            progress_callback: Optional callback(percent: float, message: str)

        Returns:
            DataFrame with columns: open, high, low, close, volume, spread, real_volume
            Index: DatetimeIndex in America/New_York timezone
        """
        if not self._connected:
            raise RuntimeError("Not connected to IBKR. Call connect() first.")

        if timeframe not in BAR_SIZES:
            raise ValueError(f"Unsupported timeframe: {timeframe}. Supported: {list(BAR_SIZES.keys())}")

        # Ensure dates are timezone-aware (US/Eastern) for consistent comparison
        import pytz
        ny_tz = pytz.timezone("America/New_York")
        if start_date.tzinfo is None:
            start_date = ny_tz.localize(start_date)
        if end_date.tzinfo is None:
            end_date = ny_tz.localize(end_date)

        # Resolve contract
        if progress_callback:
            progress_callback(0.0, f"Resolving {symbol} contract...")

        contract, what_to_show = IBKRContractResolver.resolve_contract(self._ib, symbol)

        # Fetch in chunks
        bar_size = BAR_SIZES[timeframe]
        duration_str = DURATION_STRINGS[timeframe]
        chunk_delta = CHUNK_SIZES[timeframe]

        all_bars = []
        current_end = end_date
        chunk_count = 0

        # Estimate total chunks for progress
        total_days = (end_date - start_date).days
        chunk_days = chunk_delta.days
        estimated_chunks = max(1, total_days // chunk_days + 1)

        while current_end > start_date:
            chunk_count += 1
            pct = min(95.0, (chunk_count / estimated_chunks) * 95.0)

            if progress_callback:
                progress_callback(pct, f"Fetching chunk {chunk_count}/{estimated_chunks} "
                                      f"(ending {current_end.strftime('%Y-%m-%d %H:%M')})...")

            bars = self._request_with_retry(
                contract=contract,
                end_datetime=current_end,
                duration_str=duration_str,
                bar_size=bar_size,
                what_to_show=what_to_show,
            )

            if not bars:
                logger.warning(f"No data for chunk ending {current_end}. May have reached data limit.")
                # Move back one chunk and try again
                current_end -= chunk_delta
                continue

            all_bars.extend(bars)

            # Move to before the earliest bar we received
            earliest_bar_time = min(b.date for b in bars)
            if hasattr(earliest_bar_time, 'timestamp'):
                # It's a datetime - ensure tz-aware
                if earliest_bar_time.tzinfo is None:
                    earliest_bar_time = ny_tz.localize(earliest_bar_time)
                current_end = earliest_bar_time - timedelta(seconds=1)
            else:
                # It's a date object (for daily bars)
                current_end = ny_tz.localize(
                    datetime.combine(earliest_bar_time, datetime.min.time())
                ) - timedelta(seconds=1)

            # Pacing: 1 second between requests (IBKR requirement)
            time.sleep(1.0)

        if not all_bars:
            raise ValueError(f"No data received from IBKR for {symbol} {timeframe} "
                           f"({start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')})")

        if progress_callback:
            progress_callback(96.0, "Processing data...")

        df = self._bars_to_dataframe(all_bars)

        # Filter to requested range (already tz-aware from top of method)
        df = df[(df.index >= start_date) & (df.index <= end_date)]
        df = df.sort_index()
        df = df[~df.index.duplicated(keep='first')]

        if progress_callback:
            progress_callback(100.0, f"Done! {len(df)} bars fetched.")

        logger.info(f"Fetched {len(df)} bars for {symbol} {timeframe} from IBKR "
                    f"({df.index.min()} to {df.index.max()})")

        return df

    def _request_with_retry(
        self,
        contract,
        end_datetime: datetime,
        duration_str: str,
        bar_size: str,
        what_to_show: str,
        max_retries: int = 5,
    ) -> list:
        """
        Make a historical data request with exponential backoff on pacing violations.
        Retry delays: 10s, 20s, 40s, 80s, 160s
        """
        # ib_async expects either '' (now) or a datetime object, NOT a formatted string
        end_dt = end_datetime

        for attempt in range(max_retries):
            try:
                bars = self._ib.reqHistoricalData(
                    contract,
                    endDateTime=end_dt,
                    durationStr=duration_str,
                    barSizeSetting=bar_size,
                    whatToShow=what_to_show,
                    useRTH=False,  # Include extended hours for Asian session
                    formatDate=1,
                    timeout=30,
                )
                return bars

            except Exception as e:
                error_str = str(e).lower()
                is_pacing = any(kw in error_str for kw in [
                    "pacing", "162", "historical data", "too many requests",
                    "rate limit", "query returned no data",
                ])

                if is_pacing and attempt < max_retries - 1:
                    delay = 10 * (2 ** attempt)  # 10, 20, 40, 80, 160
                    logger.warning(f"Pacing violation (attempt {attempt+1}/{max_retries}), "
                                  f"waiting {delay}s: {e}")
                    time.sleep(delay)
                elif "no data" in error_str or "query returned no data" in error_str:
                    logger.info(f"No data available for {end_dt_str}: {e}")
                    return []
                else:
                    logger.error(f"IBKR request failed: {e}")
                    raise

        return []

    def _bars_to_dataframe(self, bars: list) -> pd.DataFrame:
        """
        Convert ib_async BarData list to a standard DataFrame.
        Output columns: open, high, low, close, volume, spread, real_volume
        Index: DatetimeIndex in America/New_York timezone
        """
        import pytz
        ny_tz = pytz.timezone("America/New_York")

        records = []
        for bar in bars:
            dt = bar.date
            # Ensure datetime (not date)
            if not hasattr(dt, 'hour'):
                dt = datetime.combine(dt, datetime.min.time())

            # Localize if needed
            if dt.tzinfo is None:
                dt = ny_tz.localize(dt)
            else:
                dt = dt.astimezone(ny_tz)

            records.append({
                'time': dt,
                'open': float(bar.open),
                'high': float(bar.high),
                'low': float(bar.low),
                'close': float(bar.close),
                'volume': int(bar.volume) if bar.volume >= 0 else 0,
                'spread': 0,
                'real_volume': 0,
            })

        df = pd.DataFrame(records)
        if df.empty:
            return df

        df = df.set_index('time')
        df = df.sort_index()
        df = df[~df.index.duplicated(keep='first')]

        return df
