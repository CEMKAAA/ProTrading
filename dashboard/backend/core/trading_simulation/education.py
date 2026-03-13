"""
Beginner strategy education content for guided simulation.
"""

from __future__ import annotations

from typing import Any, Dict


def _generic_guide(strategy_id: str) -> Dict[str, Any]:
    return {
        "strategy_id": strategy_id,
        "what_this_strategy_is": f"{strategy_id.replace('_', ' ').title()} is executed as a rule-based setup with explicit risk.",
        "when_not_to_trade": [
            "When setup conditions are incomplete.",
            "When spread/liquidity is abnormal.",
            "When you cannot define stop loss before entry.",
        ],
        "step_by_step": [
            "Wait for context and setup confirmation.",
            "Define entry, SL, TP before action.",
            "Log paper execution and reason.",
            "Review result and rule adherence.",
        ],
        "common_mistakes": [
            "Entering before confirmation.",
            "Moving stop loss after entry.",
            "Skipping journal notes.",
        ],
        "risk_rules": [
            "One setup at a time in simulation.",
            "Fixed risk per trade.",
            "No live execution from guided simulation.",
        ],
        "example_scenario": "If setup appears but invalidation triggers first, skip and log the reason.",
    }


GUIDES: Dict[str, Dict[str, Any]] = {
    "orb_strategy": {
        "strategy_id": "orb_strategy",
        "what_this_strategy_is": "15-minute Opening Range Breakout: mark NY 09:30-09:45 high/low, then wait for a clean breakout with displacement and FVG confirmation.",
        "when_not_to_trade": [
            "Inside the opening range.",
            "If breakout has no displacement.",
            "If bias is weak/conflicting.",
        ],
        "step_by_step": [
            "Mark first 15m high/low.",
            "Confirm bias strength.",
            "Wait for clean breakout outside range.",
            "Require displacement + FVG confirmation.",
            "Paper execute with predefined SL/TP.",
        ],
        "common_mistakes": [
            "Front-running before breakout confirmation.",
            "Trading every poke of the range.",
            "Oversizing when RR is poor.",
        ],
        "risk_rules": [
            "No entry without SL/TP.",
            "Skip when setup invalidates.",
            "Follow one action per confirmed setup.",
        ],
        "example_scenario": "Price breaks ORB high, displacement + FVG appear, bias is strong -> ACTIONABLE. If price returns inside ORB without follow-through -> BLOCKED.",
    },
    "advanced_orb_strategy": {
        "strategy_id": "advanced_orb_strategy",
        "what_this_strategy_is": "A stricter ORB variant that requires better context quality before breakout entries.",
        "when_not_to_trade": [
            "Bias is weak or neutral.",
            "Range is noisy/unclear.",
            "Break occurs without setup confirmation.",
        ],
        "step_by_step": [
            "Confirm first session range and strong bias.",
            "Wait for qualified breakout signal.",
            "Enter only with predefined SL/TP.",
            "Review execution quality after close.",
        ],
        "common_mistakes": [
            "Treating advanced ORB like basic ORB.",
            "Ignoring invalidation flags.",
            "Taking entries with incomplete risk.",
        ],
        "risk_rules": [
            "No entry without SL/TP.",
            "Skip setups that invalidate before entry.",
            "Journal every completed/ignored setup.",
        ],
        "example_scenario": "Bias is strong but breakout fails quality check, so you skip and preserve capital.",
    },
    "orb_ml_strategy": {
        "strategy_id": "orb_ml_strategy",
        "what_this_strategy_is": "ORB with an ML confidence gate layered on top of the base setup.",
        "when_not_to_trade": [
            "Base ORB setup is incomplete.",
            "ML probability is below threshold.",
            "Invalidation appears before entry.",
        ],
        "step_by_step": [
            "Confirm ORB base setup first.",
            "Check ML probability vs threshold.",
            "Execute only when both pass.",
            "Review model-assisted decisions.",
        ],
        "common_mistakes": [
            "Using ML as prediction instead of a filter.",
            "Ignoring base setup quality.",
            "Entering when ML gate fails.",
        ],
        "risk_rules": [
            "ML pass is required, not optional.",
            "Keep fixed risk regardless of ML score.",
            "Log both ML pass/fail decisions.",
        ],
        "example_scenario": "Setup appears but ML probability is below threshold, so action is blocked.",
    },
    "advanced_orb_ml_strategy": {
        "strategy_id": "advanced_orb_ml_strategy",
        "what_this_strategy_is": "Advanced ORB quality filters plus ML confidence validation.",
        "when_not_to_trade": [
            "Advanced ORB quality checks fail.",
            "ML confidence does not pass threshold.",
            "Risk terms are not fully defined.",
        ],
        "step_by_step": [
            "Validate advanced ORB context.",
            "Wait for clean breakout setup.",
            "Require ML pass confirmation.",
            "Execute paper trade with fixed risk.",
        ],
        "common_mistakes": [
            "Skipping quality checks because ML is high.",
            "Assuming ML replaces risk management.",
            "Not journaling blocked setups.",
        ],
        "risk_rules": [
            "Need both setup and ML gate.",
            "No setup chasing after invalidation.",
            "Review every blocked signal.",
        ],
        "example_scenario": "Breakout triggers but ML gate fails, so no trade is taken.",
    },
    "liquidity_sweep_strategy": {
        "strategy_id": "liquidity_sweep_strategy",
        "what_this_strategy_is": "Looks for stop-hunt sweeps of liquidity levels and trades only after rejection confirmation.",
        "when_not_to_trade": [
            "No sweep event yet.",
            "Sweep happens but no rejection confirmation.",
            "Price keeps running through swept level.",
        ],
        "step_by_step": [
            "Identify active liquidity level.",
            "Wait for sweep event.",
            "Require rejection confirmation.",
            "Paper execute only with fixed SL/TP.",
        ],
        "common_mistakes": [
            "Entering before rejection.",
            "Confusing continuation for reversal.",
            "Ignoring invalidation after sweep.",
        ],
        "risk_rules": [
            "No rejection, no trade.",
            "Always define SL before entry.",
            "Journal sweep + rejection quality.",
        ],
        "example_scenario": "A sweep occurs above a level, rejection confirms, and only then the setup becomes actionable.",
    },
    "htf_fvg_liquidity_reclaim_strategy": {
        "strategy_id": "htf_fvg_liquidity_reclaim_strategy",
        "what_this_strategy_is": "Uses higher-timeframe fair value gaps as the structural anchor, then waits for a lower-timeframe liquidity sweep and reclaim before considering entry.",
        "when_not_to_trade": [
            "No valid HTF FVG is active near price.",
            "Liquidity is swept but the rejection is weak or absent.",
            "Risk is undefined or the setup invalidates before entry.",
        ],
        "step_by_step": [
            "Confirm the active HTF FVG and directional bias.",
            "Wait for liquidity to be taken near the FVG boundary.",
            "Require reclaim or strong rejection after the sweep.",
            "Only paper execute when entry, SL, and TP are fully defined.",
        ],
        "common_mistakes": [
            "Trading the FVG before a real sweep occurs.",
            "Treating a breakdown candle as a sweep rejection.",
            "Ignoring that HTF structure changed before entry.",
        ],
        "risk_rules": [
            "No sweep confirmation, no trade.",
            "Stop loss belongs behind the sweep extreme / invalidation structure.",
            "If the FVG is invalidated first, the setup is dead.",
        ],
        "example_scenario": "Price taps a bullish H4 FVG, sweeps sell-side liquidity below it, reclaims the level, and only then the setup becomes actionable.",
    },
    "keltner_breakout_strategy": {
        "strategy_id": "keltner_breakout_strategy",
        "what_this_strategy_is": "Trades volatility expansion after compression, using Keltner/ADX-style quality checks.",
        "when_not_to_trade": [
            "No squeeze/compression context.",
            "Breakout fires without momentum support.",
            "Trend context is conflicting.",
        ],
        "step_by_step": [
            "Track squeeze state.",
            "Wait for breakout fire.",
            "Confirm trend and momentum quality.",
            "Paper execute with defined risk.",
        ],
        "common_mistakes": [
            "Entering before squeeze release.",
            "Ignoring weak momentum.",
            "Forcing trades in chop.",
        ],
        "risk_rules": [
            "Use fixed risk and predefined exits.",
            "Skip low-quality breakout conditions.",
            "Review momentum/trend agreement post-trade.",
        ],
        "example_scenario": "Squeeze fires but momentum check fails, so the setup is blocked.",
    },
    "macd_ema_strategy": {
        "strategy_id": "macd_ema_strategy",
        "what_this_strategy_is": "Combines trend context from EMAs with MACD timing for entries.",
        "when_not_to_trade": [
            "Trend context is unclear.",
            "Signal is not confirmed.",
            "SL/TP is not defined before entry.",
        ],
        "step_by_step": [
            "Check EMA trend direction.",
            "Wait for MACD setup confirmation.",
            "Define risk and paper enter.",
            "Journal and review the outcome.",
        ],
        "common_mistakes": [
            "Taking counter-trend signals.",
            "Entering on early MACD turns.",
            "Skipping post-trade review.",
        ],
        "risk_rules": [
            "No entry without SL/TP.",
            "Avoid chasing late moves.",
            "Keep position risk fixed.",
        ],
        "example_scenario": "Trend is aligned and setup confirms, then paper execution becomes actionable.",
    },
    "basso_strategy": _generic_guide("basso_strategy"),
    "confluence_zone_strategy": _generic_guide("confluence_zone_strategy"),
    "vwap_reversion_strategy": _generic_guide("vwap_reversion_strategy"),
    "bb_squeeze_strategy": _generic_guide("bb_squeeze_strategy"),
    "b_profile_reversion_strategy": {
        "strategy_id": "b_profile_reversion_strategy",
        "what_this_strategy_is": "A mean-reversion style profile strategy that waits for failed-auction style reversion triggers.",
        "when_not_to_trade": [
            "No structural context.",
            "Trigger is missing/unclear.",
            "Setup invalidates before risk is defined.",
        ],
        "step_by_step": [
            "Confirm profile structure context.",
            "Wait for reversion trigger.",
            "Define entry + SL/TP.",
            "Execute paper trade and journal outcome.",
        ],
        "common_mistakes": [
            "Taking reversions without structure.",
            "Using wide undefined risk.",
            "Ignoring invalidation signals.",
        ],
        "risk_rules": [
            "No trigger, no trade.",
            "Keep risk fixed and explicit.",
            "Document why reversion succeeded/failed.",
        ],
        "example_scenario": "Structure looks favorable but trigger never confirms, so you skip.",
    },
    "earnings_volatility_strategy": {
        "strategy_id": "earnings_volatility_strategy",
        "what_this_strategy_is": "An event-driven volatility setup that is only valid in the right earnings/event window.",
        "when_not_to_trade": [
            "Outside the event timing window.",
            "No volatility setup signal.",
            "Risk parameters are not available.",
        ],
        "step_by_step": [
            "Confirm event-window context.",
            "Wait for valid volatility setup.",
            "Define risk terms and paper execute.",
            "Review post-event result.",
        ],
        "common_mistakes": [
            "Trading outside event windows.",
            "Forcing entries without setup.",
            "Skipping post-event review.",
        ],
        "risk_rules": [
            "Event timing must be valid.",
            "No trade without SL/TP framework.",
            "Always log what changed after event.",
        ],
        "example_scenario": "Setup appears in-window with risk defined, so you paper enter and track post-event behavior.",
    },
}


def get_strategy_guide(strategy_id: str) -> Dict[str, Any]:
    return GUIDES.get(strategy_id, _generic_guide(strategy_id))
