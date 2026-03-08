"""Test bootstrap shims for optional runtime dependencies."""

import sys
import types


if "MetaTrader5" not in sys.modules:
    mt5_stub = types.SimpleNamespace(
        TIMEFRAME_M1=1,
        TIMEFRAME_M5=5,
        TIMEFRAME_M15=15,
        TIMEFRAME_M30=30,
        TIMEFRAME_H1=60,
        TIMEFRAME_H4=240,
        TIMEFRAME_D1=1440,
        TIMEFRAME_W1=10080,
        TIMEFRAME_MN1=43200,
        initialize=lambda *args, **kwargs: False,
        shutdown=lambda *args, **kwargs: None,
        last_error=lambda *args, **kwargs: (0, "MetaTrader5 stub"),
        account_info=lambda *args, **kwargs: None,
        symbol_info=lambda *args, **kwargs: None,
        copy_rates_range=lambda *args, **kwargs: None,
        copy_rates_from_pos=lambda *args, **kwargs: None,
    )
    sys.modules["MetaTrader5"] = mt5_stub
