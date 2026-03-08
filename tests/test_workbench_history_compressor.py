from dashboard.backend.core.workbench.history_compressor import compress_history


def test_short_history_no_compress():
    history = [{"role": "user", "content": "hi"}, {"role": "assistant", "content": "hello"}]
    out = compress_history(history, keep_recent=2)
    assert out == history


def test_long_history_compresses_and_keeps_recent():
    history = []
    for i in range(12):
        history.append({"role": "user", "content": f"q{i}"})
        history.append({"role": "assistant", "content": f"a{i}"})
    out = compress_history(history, keep_recent=2, min_messages_to_compress=8)
    assert len(out) == 3
    assert out[0]["role"] == "assistant"
    assert "[Session summary]" in out[0]["content"]
    assert out[-2:] == history[-2:]


def test_summary_role_is_opposite_of_first_recent_turn():
    history = [
        {"role": "assistant", "content": "a0"},
        {"role": "user", "content": "u0"},
        {"role": "assistant", "content": "a1"},
        {"role": "user", "content": "u1"},
        {"role": "assistant", "content": "a2"},
        {"role": "assistant", "content": "a3"},
        {"role": "assistant", "content": "a4"},
        {"role": "assistant", "content": "a5"},
    ]
    out = compress_history(history, keep_recent=2, min_messages_to_compress=6)
    # recent starts with assistant => summary should be user
    assert out[0]["role"] == "user"
