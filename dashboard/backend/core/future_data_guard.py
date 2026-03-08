"""
FutureDataGuard: Prevents strategy lookahead bias.

Wraps a pandas DataFrame with bounds checking so that strategies
cannot accidentally access bars beyond the allowed boundary.
Used by the backtest engine to enforce signal/execution separation.

Architecture: Composition-based proxy (not a DataFrame subclass).
Holds a pre-sliced view and delegates attribute access to it.
Intercepts .iloc[] to catch out-of-bounds integer access.
"""

import pandas as pd


class LookaheadError(Exception):
    """Raised when a strategy attempts to access future data."""
    pass


class _GuardedIloc:
    """Intercepts .iloc[] to catch integer access beyond boundary."""

    __slots__ = ('_view', '_max_idx')

    def __init__(self, view: pd.DataFrame, max_idx: int):
        self._view = view
        self._max_idx = max_idx

    def __getitem__(self, key):
        if isinstance(key, int):
            if key >= 0 and key >= self._max_idx:
                raise LookaheadError(
                    f"Strategy attempted to access bar at index {key}, "
                    f"but only bars 0..{self._max_idx - 1} are allowed "
                    f"(accessing future data is prohibited)"
                )
        elif isinstance(key, slice):
            stop = key.stop
            if stop is not None and isinstance(stop, int) and stop > self._max_idx:
                raise LookaheadError(
                    f"Strategy attempted to slice up to index {stop}, "
                    f"but only bars 0..{self._max_idx - 1} are allowed"
                )
        return self._view.iloc[key]


class FutureDataGuard:
    """
    Wraps a pandas DataFrame to prevent access beyond max_allowed_idx.

    Strategies receive this instead of a raw DataFrame during signal
    detection (find_setup) and day initialization (initialize_day).
    All normal pandas operations work transparently on the allowed slice.

    This is a thin proxy (no data copy) for performance.
    Created once per bar in find_setup(), overhead is negligible.
    """

    __slots__ = ('_df', '_max_idx', '_view')

    def __init__(self, df: pd.DataFrame, max_allowed_idx: int):
        object.__setattr__(self, '_df', df)
        object.__setattr__(self, '_max_idx', max_allowed_idx)
        # Pre-sliced view (pandas iloc returns a view, not a copy)
        object.__setattr__(self, '_view', df.iloc[:max_allowed_idx])

    # --- Delegate all attribute access to the pre-sliced view ---

    def __getattr__(self, name):
        return getattr(self._view, name)

    def __getitem__(self, key):
        return self._view[key]

    def __len__(self):
        return len(self._view)

    def __iter__(self):
        return iter(self._view)

    def __contains__(self, item):
        return item in self._view

    def __repr__(self):
        return f"FutureDataGuard(max_idx={self._max_idx}, rows={len(self._view)})"

    # --- Properties that strategies commonly access ---

    @property
    def iloc(self):
        return _GuardedIloc(self._view, self._max_idx)

    @property
    def loc(self):
        # Label-based access is safe since the view is already sliced
        return self._view.loc

    @property
    def index(self):
        return self._view.index

    @property
    def columns(self):
        return self._view.columns

    @property
    def shape(self):
        return self._view.shape

    @property
    def values(self):
        return self._view.values

    @property
    def dtypes(self):
        return self._view.dtypes

    @property
    def empty(self):
        return self._view.empty
