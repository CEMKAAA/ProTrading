from dashboard.backend.core.workbench.circuit_breaker import ProviderCircuitBreaker


def test_circuit_breaker_opens_after_failures():
    cb = ProviderCircuitBreaker(fail_threshold=2, window_sec=60, open_sec=30, fallback_map={"claude": "local_gptoss_http"})
    assert cb.get_fallback("claude") is None
    assert cb.is_open("claude") is False
    cb.record_failure("claude")
    assert cb.get_fallback("claude") is None
    cb.record_failure("claude")
    assert cb.get_fallback("claude") == "local_gptoss_http"
    assert cb.is_open("claude") is True


def test_circuit_breaker_success_resets():
    cb = ProviderCircuitBreaker(fail_threshold=1, window_sec=60, open_sec=30, fallback_map={"claude": "local_gptoss_http"})
    cb.record_failure("claude")
    assert cb.get_fallback("claude") == "local_gptoss_http"
    cb.record_success("claude")
    assert cb.get_fallback("claude") is None
    assert cb.is_open("claude") is False
