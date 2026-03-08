"""
Tests for FutureDataGuard — lookahead bias protection framework.

Verifies that:
- Normal pandas operations work transparently through the guard
- .iloc[] access beyond the allowed boundary raises LookaheadError
- Slice access beyond the boundary raises LookaheadError
- Negative indexing works (relative to the guarded view)
- len(), shape, empty, columns work correctly
- Column operations return only allowed data
"""

import pytest
import pandas as pd
import numpy as np

from dashboard.backend.core.future_data_guard import FutureDataGuard, LookaheadError


@pytest.fixture
def sample_df():
    """Create a 100-row DataFrame mimicking OHLCV candle data."""
    np.random.seed(42)
    dates = pd.date_range("2024-01-01", periods=100, freq="5min")
    return pd.DataFrame(
        {
            "open": np.random.uniform(2000, 2010, 100),
            "high": np.random.uniform(2010, 2020, 100),
            "low": np.random.uniform(1990, 2000, 100),
            "close": np.random.uniform(2000, 2010, 100),
            "volume": np.random.randint(100, 1000, 100),
        },
        index=dates,
    )


class TestFutureDataGuardBasicAccess:
    """Tests for transparent data access through the guard."""

    def test_column_access(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        close = guard["close"]
        assert len(close) == 50
        assert (close.values == sample_df["close"].iloc[:50].values).all()

    def test_len(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        assert len(guard) == 50

    def test_shape(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        assert guard.shape == (50, 5)

    def test_columns(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        assert list(guard.columns) == ["open", "high", "low", "close", "volume"]

    def test_empty_false(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        assert not guard.empty

    def test_empty_true(self, sample_df):
        guard = FutureDataGuard(sample_df, 0)
        assert guard.empty

    def test_index(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        expected = sample_df.index[:50]
        assert (guard.index == expected).all()

    def test_values(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        assert guard.values.shape == (50, 5)

    def test_dtypes(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        assert (guard.dtypes == sample_df.dtypes).all()

    def test_repr(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        assert "FutureDataGuard" in repr(guard)
        assert "max_idx=50" in repr(guard)


class TestFutureDataGuardPandasOps:
    """Tests for pandas operations that strategies commonly use."""

    def test_rolling_mean(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        result = guard["close"].rolling(20).mean()
        expected = sample_df["close"].iloc[:50].rolling(20).mean()
        pd.testing.assert_series_equal(result, expected)

    def test_ewm(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        result = guard["close"].ewm(span=20).mean()
        expected = sample_df["close"].iloc[:50].ewm(span=20).mean()
        pd.testing.assert_series_equal(result, expected)

    def test_tail(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        result = guard.tail(5)
        expected = sample_df.iloc[:50].tail(5)
        pd.testing.assert_frame_equal(result, expected)

    def test_head(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        result = guard.head(5)
        expected = sample_df.iloc[:50].head(5)
        pd.testing.assert_frame_equal(result, expected)

    def test_loc_label_access(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        ts = sample_df.index[10]
        result = guard.loc[ts]
        expected = sample_df.loc[ts]
        pd.testing.assert_series_equal(result, expected)

    def test_contains(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        assert "close" in guard
        assert "nonexistent" not in guard

    def test_iter(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        cols = list(guard)
        assert cols == ["open", "high", "low", "close", "volume"]


class TestFutureDataGuardIlocBounds:
    """Tests for .iloc[] boundary enforcement."""

    def test_iloc_within_bounds(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        bar = guard.iloc[49]  # Last allowed index
        assert bar["close"] == sample_df.iloc[49]["close"]

    def test_iloc_at_boundary_raises(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        with pytest.raises(LookaheadError, match="bar at index 50"):
            guard.iloc[50]

    def test_iloc_beyond_boundary_raises(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        with pytest.raises(LookaheadError, match="bar at index 99"):
            guard.iloc[99]

    def test_iloc_negative_indexing_works(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        # Negative indexing is relative to the view, so -1 = index 49
        bar = guard.iloc[-1]
        assert bar["close"] == sample_df.iloc[49]["close"]

    def test_iloc_slice_within_bounds(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        result = guard.iloc[40:50]
        expected = sample_df.iloc[40:50]
        pd.testing.assert_frame_equal(result, expected)

    def test_iloc_slice_beyond_boundary_raises(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        with pytest.raises(LookaheadError, match="slice up to index 60"):
            guard.iloc[0:60]

    def test_iloc_zero_index_ok(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        bar = guard.iloc[0]
        assert bar["close"] == sample_df.iloc[0]["close"]

    def test_iloc_slice_no_stop_ok(self, sample_df):
        guard = FutureDataGuard(sample_df, 50)
        # iloc[:] should work (stop is None)
        result = guard.iloc[:]
        assert len(result) == 50
