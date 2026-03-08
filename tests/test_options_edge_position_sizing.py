import asyncio

from dashboard.backend.api.routes import _calculate_position_size, options_edge_position_size
from dashboard.backend.models.schemas import (
    OptionsEdgePositionSizingRequest,
    OptionsEdgePositionTradeInput,
)


def test_calculate_position_size_zero_contracts_when_risk_too_small():
    out = _calculate_position_size(
        account_balance=10_000.0,
        risk_pct=2.0,
        max_loss_per_contract=315.0,
        commission_per_leg=0.65,
        legs_count=2,
    )
    assert out["max_contracts"] == 0
    assert out["skip_reason"] == "max_loss_exceeds_risk_budget"


def test_calculate_position_size_multiple_contracts():
    out = _calculate_position_size(
        account_balance=50_000.0,
        risk_pct=2.0,
        max_loss_per_contract=315.0,
        commission_per_leg=0.65,
        legs_count=2,
    )
    assert out["max_contracts"] == 3
    assert out["total_risk_usd"] > 0
    assert out["skip_reason"] is None


def test_options_edge_position_size_endpoint():
    req = OptionsEdgePositionSizingRequest(
        account_balance=25_000.0,
        risk_pct=1.5,
        commission_per_leg=0.65,
        trades=[
            OptionsEdgePositionTradeInput(
                symbol="AAPL",
                structure_type="put_credit_spread",
                max_loss=150.0,
                legs_count=2,
            ),
            OptionsEdgePositionTradeInput(
                symbol="TSLA",
                structure_type="iron_condor",
                max_loss=350.0,
                legs_count=4,
            ),
        ],
    )
    resp = asyncio.run(options_edge_position_size(req))
    assert resp.ok is True
    assert len(resp.sizing) == 2
    assert resp.portfolio_total_risk_usd >= 0
    assert resp.sizing[0].symbol == "AAPL"

