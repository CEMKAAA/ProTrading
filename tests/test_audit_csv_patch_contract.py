"""Source contracts for the dated CSV/TIME MATRIX patch, not market backtests."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "IndicatorCodeExamples"
BASELINE = ROOT / ".tmp/time_matrix_compile_20260930_170236"


def body(text, name):
    match = re.search(r"(?m)^(?:bool|double|HistResult|string) " + name + r"\(", text)
    assert match, name
    # Braces inside MQL comments and strings must not terminate a function.
    tail = text[match.start():]
    tokens = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]', re.S)
    depth = 0
    started = False
    for token in tokens.finditer(tail):
        value = token.group()
        if value == "{":
            depth += 1
            started = True
        elif value == "}":
            depth -= 1
            if started and depth == 0:
                return tail[:token.end()]
    raise AssertionError("Unterminated function " + name)


checks = 0
for directory, entry in (
    ("orb", "OrbUltimateEA_StrategyLibrary.mq5"),
    ("macrossover_orb", "MaCrossOverOrbEA.mq5"),
    ("SolAdvanced", "LiqNarrativeSol_Advanced.mq5"),
):
    current = (SOURCE / directory / entry).read_text(encoding="utf-8-sig")
    previous = (BASELINE / directory / entry).read_text(encoding="utf-8-sig")
    names = ("SimulateSignal",) if directory == "SolAdvanced" else (
        "ResolveExecutionStop", "ResolveHistoricalEntry", "SimulateTradeTicks",
        "SimulateTrade", "SimulateHistoricalLifecycle",
    )
    for name in names:
        assert body(current, name) == body(previous, name), (directory, name)
        checks += 1
    assert "   AxTimer();" in current
    checks += 1
    if directory == "SolAdvanced":
        assert "TCalRecordOutcome(AxEntryAt(g_histSignalEntryTime[i],g_histSignals[i].availableTime),won)" in current
        assert "if(!TCalAllows(AxEntryAt(g_lastSimEntryTime,g_histSignals[i].availableTime)))" in current
        adapter = (SOURCE / directory / "AuditTradeCsvAdapter.mqh").read_text()
        assert 'if(reason=="TIME_MATRIX"||' in adapter
    else:
        assert "TCalRecord(csv.localTime,sim.netR)" in current
        assert "TCalAllows(ServerToSessionLocal(AxEntryAt(sim.entryTime,OrbSignalAvailableTime(entryT))))" in current
        assert "csv.entryClock=AxEntryClock(sim.entryTime,sim.entrySpreadPoints)" in current
        assert "csv.reason=AxExitReason(sim.valid,finalOutcome,sim.invalidReason,sim.outcome)" in current
        assert "TCalAllows(ServerToSessionLocal(OrbSignalAvailableTime(entryT)))" not in current
    checks += 1

for name in ("AuditTradeCsv.mqh", "AuditQuantFeatures.mqh", "AuditKivancExport.mqh"):
    versions = [(SOURCE / folder / name).read_bytes() for folder in ("orb", "macrossover_orb", "SolAdvanced")]
    assert versions[0] == versions[1] == versions[2], name
    checks += 1

print(f"{checks} source contracts passed; execution geometry/lifecycle bodies unchanged")
