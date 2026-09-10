import ast
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from evaluate_orb_ml_prior_five import compare_settings


def test_backward_evaluator_cannot_fit_or_choose_thresholds():
    source=(ROOT/'scripts/evaluate_orb_ml_prior_five.py').read_text()
    tree=ast.parse(source)
    calls=[n.func.attr for n in ast.walk(tree) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute)]
    assert not {'fit','partial_fit','fit_transform'}.intersection(calls)
    assert 'selected[ident]==family' in source
    assert '2018-01-01' in source and '2021-09-09' in source
    assert 'period.exit_at_broker.max()>=trained.features_at_broker.min()' in source
    assert 'digest(model_path)!=before' in source


def test_identical_settings_required(tmp_path):
    a=tmp_path/'a.txt';b=tmp_path/'b.txt'
    prefix='name\nUSDJPYm\n5\ninput_hash\n'
    a.write_text(prefix+'0.8000000000000001\n2\n')
    b.write_text(prefix+'0.8000000000000002\n2\n')
    compare_settings(a,b)
    b.write_text(prefix+'0.8\n3\n')
    import pytest
    with pytest.raises(ValueError): compare_settings(a,b)


def test_generated_script_changes_only_isolated_clock_and_namespace():
    frozen=(ROOT/'logs/OrbMLCampaign_20260909_v3/compiled_sources/OrbMLCampaign.mq5').read_text()
    actual=(ROOT/'.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLPriorFive/OrbMLPriorFive.mq5').read_text()
    expected=frozen.replace('OrbMLCampaign_20260909_v3','OrbMLPriorFive_20260910')
    expected=expected.replace("D'2026.09.09 00:00:00'","D'2021.09.09 00:00:00'")
    expected=expected.replace('CopyRates(_Symbol,tf,0,MathMax(20,barsToCopy),rates)',"CopyRates(_Symbol,tf,D'2021.09.09 00:00:00',MathMax(20,barsToCopy),rates)")
    expected=expected.replace('frozen cutoff 2026.09.09 00:00 broker','frozen cutoff 2021.09.09 00:00 broker; density-valid results require separate coverage mask')
    expected=expected.replace('   g_rtEaEnabled=false;g_auditRuntime=false;g_mlEnabled=false;','   if(_Symbol!="USDJPYm")return; g_rtEaEnabled=false;g_auditRuntime=false;g_mlEnabled=false;')
    assert actual==expected
