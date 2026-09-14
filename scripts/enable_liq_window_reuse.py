"""Narrow UI-only change: selecting an audit horizon is not a signal edit."""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
FILES=('LiquidityNarrative_MT5_EA.mq5','LiquidityNarrative_Invert_MT5_EA.mq5',
 'LiqNarrativeSolVersion.mq5','LiqNarrativeSol_Advanced.mq5',
 'LiquidityNarrative_MT5_EA_Channel.mq5','LiqNarrativeSolVersion_Channel.mq5',
 'LiqNarrativeSol_Advanced_Channel.mq5')

def main():
    baseline=ROOT/'logs/AuditWindowReuse_20260914/baseline';baseline.mkdir(parents=True,exist_ok=True)
    for name in FILES:
        path=ROOT/'IndicatorCodeExamples'/name;raw=path.read_bytes()
        text=raw.decode('utf-8-sig');newline='\r\n' if '\r\n' in text else '\n'
        text=text.replace('\r\n','\n')
        pattern=r'(if\(Clicked\(sparam, "BTN_AUD_[^"]+"\)\) \{ g_histWeeks = \d+; )RefreshAfterConfigChange\(\);'
        updated,count=re.subn(pattern,r'\1RefreshAfterConfigChange(false);',text)
        if not count:
            if 'g_histWeeks = 52; RefreshAfterConfigChange(false);' in text:continue
            raise ValueError('Unexpected history button structure: '+name)
        if not (baseline/name).exists():(baseline/name).write_bytes(raw)
        encoded=updated.replace('\n',newline).encode('utf-8')
        if raw.startswith(b'\xef\xbb\xbf'):encoded=b'\xef\xbb\xbf'+encoded
        path.write_bytes(encoded);print(name,count)

if __name__=='__main__':main()
