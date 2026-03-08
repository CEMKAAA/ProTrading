from datetime import datetime

from dashboard.backend.api import simulation_routes as routes
from dashboard.backend.models.database import SimulationSession, WorkbenchAgentMemoryModel


def test_memory_row_to_dict_exposes_pinned():
    row = WorkbenchAgentMemoryModel(
        id=11,
        scope="GLOBAL",
        memory_type="trader_rule",
        content="Always align entries with HTF trend.",
        metadata_json={"pinned": True},
        importance=0.95,
        source="manual",
        access_count=3,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    out = routes._memory_row_to_dict(row)
    assert out["id"] == 11
    assert out["pinned"] is True
    assert out["memory_type"] == "trader_rule"


def test_memory_row_to_dict_reads_dedicated_pinned_column():
    row = WorkbenchAgentMemoryModel(
        id=12,
        scope="SESSION",
        simulation_session_id=7,
        memory_type="note",
        content="Use M15 confirmation candle.",
        metadata_json={},
        pinned=True,
        importance=0.7,
        source="manual",
        access_count=0,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    out = routes._memory_row_to_dict(row)
    assert out["id"] == 12
    assert out["pinned"] is True
    assert isinstance(out.get("metadata"), dict)
    assert out["metadata"].get("pinned") is True


def test_memory_row_visible_for_session_scope():
    session = SimulationSession(id=7, symbol="XAUUSD", strategy_id="_workbench")
    row_global = WorkbenchAgentMemoryModel(scope="GLOBAL")
    row_session = WorkbenchAgentMemoryModel(scope="SESSION", simulation_session_id=7)
    row_symbol = WorkbenchAgentMemoryModel(scope="SYMBOL", symbol="XAUUSD")
    row_other = WorkbenchAgentMemoryModel(scope="SESSION", simulation_session_id=77)

    assert routes._memory_row_visible_for_session(row=row_global, session=session) is True
    assert routes._memory_row_visible_for_session(row=row_session, session=session) is True
    assert routes._memory_row_visible_for_session(row=row_symbol, session=session) is True
    assert routes._memory_row_visible_for_session(row=row_other, session=session) is False
