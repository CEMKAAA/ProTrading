import json
import numpy as np
from threadpoolctl import threadpool_limits
from scripts import orb_ml_return_campaign as campaign
from scripts.orb_ml_filter import temporal_split
from tests.test_orb_ml_filter import dataset_frame


def test_features_never_include_outcomes():
    a = dataset_frame(500)
    b = a.copy()
    b['net_r'] *= -100
    b['label_win'] = 1-b.label_win
    np.testing.assert_array_equal(campaign.design(a), campaign.design(b))
    assert campaign.design(a).shape[1] == 50


def test_final_test_cannot_change_frozen_selection(tmp_path):
    frame = dataset_frame(600)
    _, _, test = temporal_split(frame)
    changed = frame.copy()
    changed.loc[test.index, 'net_r'] *= -20
    changed['label_win'] = (changed.net_r > 0).astype(int)
    with threadpool_limits(limits=1):
        a = campaign.fit(frame, tmp_path/'a')
        b = campaign.fit(changed, tmp_path/'b')
    assert json.loads((tmp_path/'a/frozen_selection.json').read_text()) == json.loads((tmp_path/'b/frozen_selection.json').read_text())
    assert a['standardized_coefficients'] == b['standardized_coefficients']
    assert not a['published'] and not b['published']
    assert a['validation_label_max'] < a['test_start']-86400


def test_family_diagnostic_no_gain_and_negative_gain():
    frame = dataset_frame(300)
    assert not campaign.family_uncertainty(frame, np.ones(len(frame), dtype=bool), draws=1000)['passed']
    frame['net_r'] = 1.
    assert not campaign.family_uncertainty(frame, np.zeros(len(frame), dtype=bool), draws=1000)['passed']
