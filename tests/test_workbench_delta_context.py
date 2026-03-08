from dashboard.backend.core.workbench.delta_context import DeltaContextManager, get_delta_manager


def test_delta_first_turn_contains_price_and_balance():
    mgr = DeltaContextManager("s1")
    delta = mgr.compute_delta(
        {
            "last_price": 3050.0,
            "atr_14": 20.0,
            "balance": 10000.0,
            "positions": [{"id": 1}],
            "triggers": [{"id": "t1"}],
        }
    )
    assert delta.get("price") == 3050.0
    assert delta.get("balance") == 10000.0
    assert delta.get("trigger_count") == 1


def test_delta_ignores_small_price_change():
    mgr = DeltaContextManager("s2")
    mgr.compute_delta({"last_price": 100.0, "atr_14": 20.0, "balance": 1.0, "positions": [], "triggers": []})
    delta = mgr.compute_delta({"last_price": 103.0, "atr_14": 20.0, "balance": 1.0, "positions": [], "triggers": []})
    assert "price" not in delta


def test_delta_tracks_open_close_positions():
    mgr = DeltaContextManager("s3")
    mgr.compute_delta({"last_price": 100.0, "atr_14": 20.0, "balance": 1.0, "positions": [], "triggers": []})
    d_open = mgr.compute_delta({"last_price": 110.0, "atr_14": 20.0, "balance": 1.0, "positions": [{"id": 9}], "triggers": []})
    assert d_open.get("positions_opened")
    d_close = mgr.compute_delta({"last_price": 111.0, "atr_14": 20.0, "balance": 1.0, "positions": [], "triggers": []})
    assert 9 in d_close.get("positions_closed_ids", [])


def test_get_delta_manager_same_instance():
    a = get_delta_manager("same")
    b = get_delta_manager("same")
    assert a is b
