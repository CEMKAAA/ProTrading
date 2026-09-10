"""Build-time gate for reusing frozen weights after UI-only code changes."""
import hashlib
import json
import re
from pathlib import Path


def body(text, name):
    match = re.search(r'^\w+\s+'+re.escape(name)+r'\s*\(', text, re.M)
    if not match:
        raise ValueError('Function missing: '+name)
    start = text.index('{', match.start()); depth = 0
    # Mask strings/comments while preserving offsets, including braces in log text.
    masked = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/', lambda m: ' '*len(m[0]), text)
    for end in range(start, len(text)):
        depth += (masked[end] == '{') - (masked[end] == '}')
        if depth == 0:
            return text[start:end+1]
    raise ValueError('Unclosed function')


def check(root):
    src = root/'IndicatorCodeExamples'; snap = root/'logs/OrbMLCampaign_20260909_v3/compiled_sources'
    if not snap.exists():
        return dict(compatible=False, reason='Campaign source snapshot absent')
    mismatches = []
    for name in ['OrbStrategyPresetLibrary.mqh','OrbStrategyUserContract.mqh','OrbStrategyMLCore.mqh',
                 'NasUltimate_Core.mqh','LiqNarrativeSol_RegimeV3.mqh','OrbAdvancedAuditEngine.mqh']:
        if (src/name).read_text(encoding='utf8') != (snap/name).read_text(encoding='utf8'):
            mismatches.append(name)
    current = (src/'OrbUltimateEA_StrategyLibrary.mq5').read_text(encoding='utf8')
    old = (snap/'OrbMLCampaign.mq5').read_text(encoding='utf8')
    validator = (root/'scripts/validate_orb_strategy_library.ps1').read_text(encoding='utf8')
    names = re.findall(r'"([A-Za-z0-9_]+)"', validator.split('$sacredFunctions = @(',1)[1].split('\n)',1)[0])
    # Exact observer hooks leave the unfiltered export and outcome math intact.
    # Do not ignore other body changes when reusing frozen model weights.
    hooks = {
        'ProcessHistoricalCalcDay': '      if(!OrbMlHistoryAllow(sigT,dir,hi,lo,oe,sim)){g_histFiltered++;return;}\n',
        'FinalizeHistoricalAudit': '   g_histStatLine+=" | "+OrbMlHistorySummary();\n',
    }
    for name in names:
        actual = body(current,name)
        if name in hooks:
            actual = actual.replace(hooks[name], '', 1)
        if actual != body(old,name):
            mismatches.append(name)
    if body((src/'OrbStrategyMLPipeline.mqh').read_text(encoding='utf8'),'OrbMlFeatures') != body((snap/'OrbStrategyMLPipeline.mqh').read_text(encoding='utf8'),'OrbMlFeatures'):
        mismatches.append('OrbMlFeatures')
    return dict(compatible=not mismatches, mismatches=mismatches, functions=len(names))


if __name__ == '__main__':
    print(json.dumps(check(Path(__file__).resolve().parents[1])))
