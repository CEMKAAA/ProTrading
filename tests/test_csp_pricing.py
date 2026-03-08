import pytest

from dashboard.backend.core.options_edge.csp_pricing import (
    bs_put_delta,
    bs_put_price,
    estimate_pop,
)


def test_bs_put_price_non_negative_and_intrinsic_at_expiry():
    p = bs_put_price(spot=100.0, strike=110.0, years_to_expiry=0.0, rate=0.05, sigma=0.3)
    assert p == 10.0

    p2 = bs_put_price(spot=120.0, strike=110.0, years_to_expiry=0.0, rate=0.05, sigma=0.3)
    assert p2 == 0.0


def test_bs_put_price_monotonic_in_strike_for_fixed_inputs():
    p_low_k = bs_put_price(spot=100.0, strike=90.0, years_to_expiry=30.0 / 365.0, rate=0.04, sigma=0.25)
    p_hi_k = bs_put_price(spot=100.0, strike=110.0, years_to_expiry=30.0 / 365.0, rate=0.04, sigma=0.25)
    assert p_hi_k > p_low_k >= 0.0


def test_bs_put_delta_bounds():
    d = bs_put_delta(spot=100.0, strike=100.0, years_to_expiry=30.0 / 365.0, rate=0.03, sigma=0.30)
    assert -1.0 <= d <= 0.0


def test_estimate_pop_from_delta():
    assert estimate_pop(-0.20) == pytest.approx(0.80)
    assert estimate_pop(-0.80) == pytest.approx(0.20)
    assert estimate_pop(-2.0) == pytest.approx(0.0)
