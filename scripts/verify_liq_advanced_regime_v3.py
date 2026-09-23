#!/usr/bin/env python3
"""Verify SolVersion signal parity and the optional V3 filter contract."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STAR = ROOT / "IndicatorCodeExamples" / "LiqNarrativeSolVersion.mq5"
ADVANCED = ROOT / "IndicatorCodeExamples" / "SolAdvanced" / "LiqNarrativeSol_Advanced.mq5"
REGIME = ROOT / "IndicatorCodeExamples" / "LiqNarrativeSol_RegimeV3.mqh"
LISTENER = ROOT / "IndicatorCodeExamples" / "LiquidityNarrative_cTrader_Listener.cs"
COMPILE_LOG = ROOT / "logs" / "compile_liq_advanced_regime_filter_5680_exit_only.log"

FUNCTION_PATTERN = re.compile(
    r"(?m)^(?:bool|int|double|string|void|datetime|ENUM_TIMEFRAMES|ERL_RR_MODE)"
    r"\s+([A-Za-z_]\w*)\s*\([^;]*?\)\s*\{"
)


def functions(text: str) -> dict[str, list[str]]:
    output: dict[str, list[str]] = {}
    for match in FUNCTION_PATTERN.finditer(text):
        cursor = match.end() - 1
        depth = 0
        end = cursor
        while end < len(text):
            if text[end] == "{":
                depth += 1
            elif text[end] == "}":
                depth -= 1
                if depth == 0:
                    end += 1
                    break
            end += 1
        output.setdefault(match.group(1), []).append(text[match.start() : end])
    return output


def reachable(function_map: dict[str, list[str]], roots: list[str]) -> set[str]:
    seen: set[str] = set()
    stack = list(roots)
    while stack:
        name = stack.pop()
        if name in seen:
            continue
        seen.add(name)
        body = "\n".join(function_map.get(name, []))
        for candidate in function_map:
            if candidate not in seen and re.search(rf"\b{re.escape(candidate)}\s*\(", body):
                stack.append(candidate)
    return seen


def input_declarations(text: str) -> dict[str, str]:
    output: dict[str, str] = {}
    for line in text.splitlines():
        match = re.match(r"\s*input\s+.+?\s+(Inp\w+)\s*=\s*(.+?);\s*(?://.*)?$", line)
        if match:
            output[match.group(1)] = re.sub(r"\s+", " ", line.strip())
    return output


def main() -> None:
    star_text = STAR.read_text(encoding="utf-8-sig")
    advanced_text = ADVANCED.read_text(encoding="utf-8-sig")
    regime_text = REGIME.read_text(encoding="utf-8-sig")
    listener_text = LISTENER.read_text(encoding="utf-8-sig")
    star_functions = functions(star_text)
    advanced_functions = functions(advanced_text)

    roots = [
        "BuildSignals",
        "ApplyRuntimeSlDistance",
        "DirectionalStopGuard",
        "SelectedTarget",
        "HalfTrigger",
        "EffectiveTargetMode",
        "TargetR",
    ]
    signal_functions = reachable(star_functions, roots)
    mismatches = sorted(
        name for name in signal_functions if star_functions.get(name) != advanced_functions.get(name)
    )
    assert not mismatches, f"signal function mismatch: {mismatches}"

    signal_body = "\n".join("\n".join(star_functions[name]) for name in signal_functions)
    signal_inputs = sorted(set(re.findall(r"\bInp[A-Za-z0-9_]+\b", signal_body)))
    star_inputs = input_declarations(star_text)
    advanced_inputs = input_declarations(advanced_text)
    input_mismatches = [
        name for name in signal_inputs if star_inputs.get(name) != advanced_inputs.get(name)
    ]
    assert not input_mismatches, f"signal input mismatch: {input_mismatches}"

    forbidden_tap_tokens = [
        "ERL_SOL_TAP_ROUTE",
        "InpSolTap",
        "SolTapReactionFlips",
        "SolTapBodyFlips",
        "SolRouterShouldFlip",
        "tapOpen",
        "tapClose",
    ]
    assert not [token for token in forbidden_tap_tokens if token in advanced_text]

    # Regime logic must not alter the star's raw signal or geometry functions.
    build_signals_body = "\n".join(advanced_functions["BuildSignals"])
    assert "RegimeV3" not in build_signals_body
    assert "SolRegimeFilter" not in build_signals_body
    assert not re.search(r"\bRF(?:0[1-9]|1[0-2])\b", build_signals_body)

    default_filter = re.search(
        r"input\s+bool\s+InpSolRegimeFilterDefault\s*=\s*false\s*;",
        advanced_text,
    )
    assert default_filter, "regime filter must remain opt-in/default-off"

    for rule_number in range(1, 13):
        assert f"RF{rule_number:02d}_" in advanced_text, f"missing RF{rule_number:02d}"

    required_advanced_tokens = [
        "ApplySolRegimeFilter(g_histSignals);",
        "ApplySolRegimeFilter(signals);",
        "NextOppositeSignalTime",
        "CopySignalArray",
        "FileBridgeWriteRegimeCloseOnly",
        "RegimeFilterCloseOnly",
        "HandleRegimeRejectedSignal",
        "SolRegimeFilterDecision",
        'g_solRegimeFilterEnabled ? "FILTER ON" : "FILTER OFF"',
    ]
    missing_advanced = [token for token in required_advanced_tokens if token not in advanced_text]
    assert not missing_advanced, f"missing filter lifecycle tokens: {missing_advanced}"

    historical_filter_pos = advanced_text.index("ApplySolRegimeFilter(g_histSignals);")
    historical_raw_exit_pos = advanced_text.rfind(
        "CopySignalArray(g_histSignals, exitSignals);", 0, historical_filter_pos
    )
    assert historical_raw_exit_pos >= 0, "historical raw exit stream is not preserved"

    backtest_filter_pos = advanced_text.rfind("ApplySolRegimeFilter(signals);")
    backtest_raw_exit_pos = advanced_text.rfind(
        "CopySignalArray(signals, exitSignals);", 0, backtest_filter_pos
    )
    assert backtest_raw_exit_pos >= 0, "backtest raw exit stream is not preserved"

    assert "g_solRegimeFilterUnclassified++" in advanced_text
    assert "return ArraySize(signals);" in "\n".join(
        advanced_functions["ApplySolRegimeFilter"]
    ), "unknown regime must fail open"

    required_listener_tokens = [
        '[Parameter("Enable Close-Only Signals", DefaultValue = true)]',
        "IsCloseOnlySignal",
        "CloseSameDirectionPositions",
    ]
    missing_listener = [token for token in required_listener_tokens if token not in listener_text]
    assert not missing_listener, f"listener close-only contract missing: {missing_listener}"

    required_timeline_tokens = [
        "g_regimeV3Timeline",
        "RegimeV3EnsureTimeline",
        "RegimeV3SnapshotAt",
        ".availableTime <= availableTime",
    ]
    missing_timeline = [token for token in required_timeline_tokens if token not in regime_text]
    assert not missing_timeline, f"causal regime timeline missing: {missing_timeline}"

    assert advanced_text.count("RegimeV3Update(true);") == 1
    assert advanced_text.count("RegimeV3Update(false);") == 1
    assert "MARKET REGIME V3" in advanced_text
    assert "#include \"LiqNarrativeSol_RegimeV3.mqh\"" in advanced_text

    expected_constants = {
        "REGIME_V3_TREND_ENTER": "0.62",
        "REGIME_V3_TREND_EXIT": "0.42",
        "REGIME_V3_TREND_DECISIVE_HIGH": "0.76",
        "REGIME_V3_TREND_DECISIVE_LOW": "0.28",
        "REGIME_V3_VOL_ENTER": "0.62",
        "REGIME_V3_VOL_EXIT": "0.42",
        "REGIME_V3_VOL_DECISIVE_HIGH": "0.76",
        "REGIME_V3_VOL_DECISIVE_LOW": "0.28",
        "REGIME_V3_FAST_CONFIRM": "3",
        "REGIME_V3_NORMAL_CONFIRM": "5",
        "REGIME_V3_DIRECTION_ENTER_Z": "0.35",
        "REGIME_V3_DIRECTION_DECISIVE_Z": "0.75",
    }
    for name, value in expected_constants.items():
        assert re.search(rf"#define\s+{name}\s+{re.escape(value)}\b", regime_text), name

    compile_text = COMPILE_LOG.read_text(encoding="utf-16", errors="ignore")
    if "Result: 0 errors, 0 warnings" not in compile_text:
        compile_text = COMPILE_LOG.read_text(encoding="utf-8-sig", errors="ignore")
    assert "Result: 0 errors, 0 warnings" in compile_text

    print("Liq Advanced Regime V3 optional-filter verification: PASS")
    print(f"signal_functions={len(signal_functions)} signal_inputs={len(signal_inputs)}")
    print("filter_default=OFF rules=12 raw_reverse_exit=PRESERVED close_only=READY")
    print("causal_timeline=PASS compile=0_errors_0_warnings")


if __name__ == "__main__":
    main()
