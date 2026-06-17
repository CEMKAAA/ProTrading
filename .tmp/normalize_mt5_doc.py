from pathlib import Path
p = Path('docs/MT5_EVENT_VALIDATION_PIPELINE.md')
s = p.read_text(encoding='utf-8')
repl = {
    '\u0131':'i','\u0130':'I','\u011f':'g','\u011e':'G','\u00fc':'u','\u00dc':'U',
    '\u015f':'s','\u015e':'S','\u00f6':'o','\u00d6':'O','\u00e7':'c','\u00c7':'C',
    '\u00e2':'a','\u00c2':'A','\u00ee':'i','\u00ce':'I','\u00fb':'u','\u00db':'U',
    '\u2019':"'",'\u2018':"'",'\u201c':'"','\u201d':'"','\u2013':'-','\u2014':'-'
}
for k, v in repl.items():
    s = s.replace(k, v)
p.write_text(s, encoding='utf-8')
