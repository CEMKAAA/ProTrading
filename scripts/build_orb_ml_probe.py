"""Generate a no-orders, tester-only MQL inference/parser regression EA."""
from pathlib import Path
import json
import numpy as np
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import StandardScaler
from scripts.orb_ml_filter import encode_model, FEATURES


def main():
    root = Path(__file__).resolve().parents[1]
    out = root / "tmp" / "orb_ml_probe"
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(42)
    x = rng.normal(size=(200, len(FEATURES)))
    y = (x[:, 0] + x[:, 2] > 0).astype(int)
    scaler = StandardScaler().fit(x)
    model = MLPClassifier(hidden_layer_sizes=(16,), solver="lbfgs", alpha=10,
                          max_iter=3000, tol=1e-3, random_state=42)
    model.fit(scaler.transform(x), y)
    info = {"config_hash": "b" * 64, "dataset_sha256": "c" * 64}
    bundle = encode_model(model, scaler, info, 1700000000, .55).decode()
    check_x = np.r_[x[:32], x[:4] * 100, np.zeros((1, 40))]
    p = model.predict_proba(scaler.transform(check_x))[:, 1]
    core = (root / "IndicatorCodeExamples" / "OrbStrategyMLCore.mqh").read_text()
    lines = ['#property strict', core, 'int OnInit()', '{',
             '   if(!MQLInfoInteger(MQL_TESTER))return INIT_FAILED;',
             '   string text="",reason="";int failures=0;double maxError=0,p=0;',
             '   OrbMlNetwork net;double x[];ArrayResize(x,40);']
    for line in bundle.splitlines():
        lines.append('   text+=' + json.dumps(line + '\n') + ';')
    key = info["config_hash"]
    lines += [f'   if(!OrbMlParseModel(text,"{key}",net,reason)){{Print("ORB_ML_PROBE PARSE_FAIL ",reason);return INIT_FAILED;}}']
    for vector, probability in zip(check_x, p):
        lines += [f'   x[{i}]={float(value):.17g};' for i, value in enumerate(vector)]
        lines += [f'   if(!OrbMlPredict(net,x,p))failures++;else maxError=MathMax(maxError,MathAbs(p-{probability:.17g}));']
    lines += [f'   if(OrbMlParseModel(text,"{"a" * 64}",net,reason)||net.ready)failures++;',
              '   string corrupt=text;StringSetCharacter(corrupt,0,88);',
              f'   if(OrbMlParseModel(corrupt,"{key}",net,reason)||net.ready)failures++;',
              f'   if(OrbMlParseModel(text+"1\\n","{key}",net,reason)||net.ready)failures++;',
              '   double value=0;',
              '   if(OrbMlNumber("nan",value)||OrbMlNumber("1oops",value)||OrbMlNumber("",value))failures++;',
              '   if(!OrbMlNumber("-1.234e-3",value)||MathAbs(value+0.001234)>1e-15)failures++;',
              '   if(maxError>1e-10)failures++;',
              f'   Print("ORB_ML_PROBE ",failures==0?"PASS":"FAIL"," vectors={len(check_x)} failures=",failures," max_error=",DoubleToString(maxError,16));',
              '   return failures==0?INIT_SUCCEEDED:INIT_FAILED;', '}',
              'void OnTick(){TesterStop();}']
    (out / "OrbMLProbe.mq5").write_text("\n".join(lines) + "\n", encoding="ascii")
    print(out / "OrbMLProbe.mq5")


if __name__ == "__main__":
    main()
