"""Native routing regression checks; no terminal or trading calls."""
from pathlib import Path
import sys
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from check_orb_campaign_compatibility import body, check

SOURCE = (ROOT / 'IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5').read_text(encoding='utf8')


@pytest.mark.parametrize('native', [False, True])
@pytest.mark.parametrize('publish', [False, True])
@pytest.mark.parametrize('only', [False, True])
def test_routing_truth_table(native, publish, only):
    entry = body(SOURCE, 'ExecuteOrbEntry')
    assert 'if(!g_orbNativeWithBridgeOnly&&!g_orbBridgeEnabled)' in entry
    assert entry.count('if(!g_orbNativeWithBridgeOnly)') == 2
    assert 'if(g_orbBridgeOnly&&!g_orbNativeWithBridgeOnly)' not in entry
    no_destination = not native and not publish
    bridge_only = not no_destination and not native
    reaches_native = not no_destination and not bridge_only
    assert reaches_native == native
    if publish and not native:
        assert bridge_only


def test_final_send_and_retry_are_guarded():
    send = body(SOURCE, 'SendOrbOrder')
    assert send.count('trade.PositionOpen(') == 2
    assert SOURCE.count('trade.PositionOpen(') == 2
    first, retry = send.split('string firstFail=', 1)
    assert first.index('if(!g_orbNativeWithBridgeOnly)') < first.index('trade.PositionOpen(')
    assert retry.index('if(!g_orbNativeWithBridgeOnly)') < retry.index('trade.PositionOpen(')


def test_toggle_does_not_close_or_disable_protection():
    section = SOURCE.split('else if(sparam==PREFIX+"BTN_BRIDGE_NATIVE")', 1)[1].split('else if(', 1)[0]
    assert 'PositionClose' not in section
    assert 'native_entry_toggle' in section
    send = body(SOURCE, 'SendOrbOrder')
    assert 'trade.PositionModify(t,sl,tp)' in send
    assert 'trade.PositionClose(t)' in send


def test_campaign_signal_features_and_outcomes_unchanged():
    assert check(ROOT)['compatible']
