from dashboard.backend.api import simulation_routes as routes


def test_memory_overlap_scores_semantic_synonym_boost_for_fvg():
    lexical, semantic, char_sim = routes._memory_overlap_scores(
        "fair value gap mitigation",
        "Look for FVG mitigation on HTF before entry.",
    )
    assert semantic > 0.0
    assert char_sim >= 0.0
    assert semantic >= lexical


def test_memory_overlap_scores_semantic_synonym_boost_for_timeframe_alias():
    lexical, semantic, _ = routes._memory_overlap_scores(
        "higher timeframe trend",
        "HTF trend alignment is mandatory for entries.",
    )
    assert semantic > 0.0
    assert semantic >= lexical

