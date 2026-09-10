import numpy as np
import pytest

from scripts.export_orb_campaign_models import encode_return, predict_return, numeric_hash
from scripts.orb_ml_return_campaign import estimator


def test_decimal_binding_ignores_binary_roundtrip_not_setting_changes():
    assert numeric_hash(['0.8000000000000001']) == numeric_hash(['0.8000000000000002'])
    assert numeric_hash(['0.8']) != numeric_hash(['0.81'])
    assert numeric_hash(['4000']) != numeric_hash(['4001'])


@pytest.mark.parametrize('kind', ['ridge_10', 'hgb_7'])
def test_return_adapter_matches_sklearn_and_detects_corruption(kind):
    rng = np.random.default_rng(17)
    x = rng.normal(size=(220, 50)); y = x[:, 0] * .4 - x[:, 2] * .2
    model = estimator(kind).fit(x, y)
    bundle = dict(model=model, threshold=.05, active=True)
    report = dict(selected=kind, train_label_max=1000, validation_label_max=2000)
    info = dict(config_hash='a'*64, dataset_sha256='b'*64)
    data = encode_return(bundle, report, info)
    scores = predict_return(data, x)
    np.testing.assert_allclose(scores, model.predict(x), atol=1e-12, rtol=1e-12)
    np.testing.assert_array_equal(scores >= .05, model.predict(x) >= .05)
    with pytest.raises(ValueError, match='Checksum'):
        predict_return(data.replace(b'2000', b'2001', 1), x)
