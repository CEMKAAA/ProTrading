"""CSP pricing utilities (Black-Scholes proxy + helpers).

These functions are used by the CSP lifecycle engine to estimate
option premiums and POP in backtests when full historical option
chains are unavailable.
"""

from __future__ import annotations

import math


def _norm_cdf(x: float) -> float:
    """Standard normal CDF without scipy dependency."""
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))


def bs_put_price(spot: float, strike: float, years_to_expiry: float, rate: float, sigma: float) -> float:
    """Black-Scholes European put price.

    Args:
        spot: Underlying price (S).
        strike: Strike price (K).
        years_to_expiry: Time to expiry in years (T).
        rate: Risk-free rate as decimal (r).
        sigma: Implied volatility as decimal (annualized).
    """
    s = float(spot)
    k = float(strike)
    t = max(0.0, float(years_to_expiry))
    r = float(rate)
    v = max(0.0, float(sigma))

    if s <= 0.0 or k <= 0.0:
        return 0.0
    if t <= 0.0:
        return max(k - s, 0.0)
    if v <= 0.0:
        # Zero-vol limit under risk-neutral discounting.
        return max(k * math.exp(-r * t) - s, 0.0)

    sqrt_t = math.sqrt(t)
    d1 = (math.log(s / k) + (r + 0.5 * v * v) * t) / (v * sqrt_t)
    d2 = d1 - v * sqrt_t
    return k * math.exp(-r * t) * _norm_cdf(-d2) - s * _norm_cdf(-d1)


def bs_put_delta(spot: float, strike: float, years_to_expiry: float, rate: float, sigma: float) -> float:
    """Black-Scholes European put delta (range approximately [-1, 0])."""
    s = float(spot)
    k = float(strike)
    t = max(0.0, float(years_to_expiry))
    r = float(rate)
    v = max(0.0, float(sigma))

    if s <= 0.0 or k <= 0.0:
        return -1.0
    if t <= 0.0:
        return -1.0 if s < k else 0.0
    if v <= 0.0:
        fwd_gap = s - k * math.exp(-r * t)
        return -1.0 if fwd_gap < 0.0 else 0.0

    sqrt_t = math.sqrt(t)
    d1 = (math.log(s / k) + (r + 0.5 * v * v) * t) / (v * sqrt_t)
    return _norm_cdf(d1) - 1.0


def estimate_pop(delta: float) -> float:
    """Estimate probability of profit for short put from delta.

    Heuristic:
        POP ~= 1 - |delta|
    """
    d = abs(float(delta))
    if math.isnan(d) or math.isinf(d):
        return 0.0
    return max(0.0, min(1.0, 1.0 - d))

