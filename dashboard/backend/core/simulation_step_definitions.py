"""
Step Definitions for Trading Simulation
Beginner-friendly step-by-step guides for all 11 strategies.
Each step has a condition that gets evaluated by the simulation engine.
"""

from typing import Optional, Dict, Any


def get_step_definitions(strategy_id: str) -> Optional[Dict[str, Any]]:
    """Get step definitions for a strategy."""
    return STRATEGY_STEPS.get(strategy_id)


def get_all_strategy_steps() -> Dict[str, Dict[str, Any]]:
    """Get all strategy step definitions."""
    return STRATEGY_STEPS


STRATEGY_STEPS: Dict[str, Dict[str, Any]] = {
    # ──────────────────────────────────────────────────
    # 1. ORB Strategy
    # ──────────────────────────────────────────────────
    "orb_strategy": {
        "name": "ORB Strategy",
        "description": "Opening Range Breakout with ICT concepts",
        "steps": [
            {
                "id": "orb_1",
                "title": "Mark the Opening Range",
                "description": "Wait for the first 15 minutes (9:30-9:45 NY time). The HIGH and LOW of this window become your ORB range. Everything revolves around these two lines.",
                "condition": "has_day_context",
                "icon": "bi-rulers",
                "chart_action": "rectangle",
            },
            {
                "id": "orb_2",
                "title": "Read the Bias",
                "description": "Is the market leaning UP or DOWN? The system compares price to yesterday's high/low and the Asian session range. Green arrow = bullish, Red arrow = bearish. You need a score of 40+ to trade.",
                "condition": "bias_strong",
                "threshold": 40,
                "icon": "bi-compass",
                "chart_action": "bias_arrow",
            },
            {
                "id": "orb_3",
                "title": "Wait for Breakout",
                "description": "Watch for a BIG candle that pushes PAST the ORB line. The candle must have a large body and tiny wicks - this shows strong conviction (displacement).",
                "condition": "strategy_setup_detected",
                "icon": "bi-lightning-charge",
                "chart_action": "highlight_candle",
            },
            {
                "id": "orb_4",
                "title": "Confirm the FVG",
                "description": "Look for a 3-candle 'gap' pattern after the breakout. The middle candle's body creates an imbalance. This is where institutions placed their big orders.",
                "condition": "strategy_setup_detected",
                "icon": "bi-layers",
                "chart_action": "fvg_zone",
            },
            {
                "id": "orb_5",
                "title": "Execute the Trade",
                "description": "Click BUY (if bullish breakout above ORB) or SELL (if bearish breakout below ORB). Your Stop Loss is pre-set at the FVG boundary. Take Profit targets 2-3x your risk.",
                "condition": "has_open_position",
                "icon": "bi-cursor",
                "chart_action": "entry_lines",
            },
            {
                "id": "orb_6",
                "title": "Manage & Learn",
                "description": "Watch your trade play out. Green line = your Target. Red line = your Stop Loss. Whether you win or lose, the market is teaching you something. Review what happened.",
                "condition": "position_closed",
                "icon": "bi-mortarboard",
                "chart_action": "exit_marker",
            },
        ],
        "info": {
            "what": "The ORB strategy waits for the first 15 minutes of the New York session to form a price range (Opening Range). Then it looks for strong breakouts from this range, confirmed by ICT concepts like Fair Value Gaps and displacement candles. It trades in the direction of the daily bias.",
            "best_conditions": "Works best during high-volatility NY session opens on Gold (XAUUSD). Avoid on low-volume days and Fridays after 2pm.",
            "common_mistakes": [
                "Trading before the ORB range is fully formed (be patient!)",
                "Ignoring the bias score - a weak bias means weak conviction",
                "Entering without displacement - a small candle crossing ORB is NOT a breakout",
                "Moving your stop loss to 'give it more room' - trust the FVG boundary",
            ],
            "glossary": {
                "ORB": "Opening Range Breakout - the high/low of the first 15 minutes",
                "FVG": "Fair Value Gap - a 3-candle pattern showing institutional orders",
                "Displacement": "A large-bodied candle with tiny wicks showing strong momentum",
                "Bias": "The overall market direction based on session levels and price action",
            },
        },
    },

    # ──────────────────────────────────────────────────
    # 2. Advanced ORB Strategy
    # ──────────────────────────────────────────────────
    "advanced_orb_strategy": {
        "name": "Advanced ORB Strategy",
        "description": "ORB with stricter filters for higher-quality setups",
        "steps": [
            {
                "id": "aorb_1",
                "title": "Mark the Opening Range",
                "description": "Same as basic ORB: wait for 9:30-9:45 NY. The HIGH and LOW form your range. But now we'll be MUCH pickier about what counts as a valid breakout.",
                "condition": "has_day_context",
                "icon": "bi-rulers",
            },
            {
                "id": "aorb_2",
                "title": "Check Strong Bias",
                "description": "Bias score must be 40+ (same as basic). But Advanced ORB adds extra session level checks for a more reliable directional read.",
                "condition": "bias_strong",
                "threshold": 40,
                "icon": "bi-compass",
            },
            {
                "id": "aorb_3",
                "title": "Wait for STRONG Breakout",
                "description": "The breakout candle must be in the 85th percentile of recent candle sizes. AND the opposing wick must be less than 32% of the candle. Only the strongest moves pass this filter.",
                "condition": "strategy_setup_detected",
                "icon": "bi-lightning-charge-fill",
            },
            {
                "id": "aorb_4",
                "title": "Confirm FVG",
                "description": "A Fair Value Gap must form in the breakout direction. This gap is where institutions left unfilled orders - it acts as your entry and stop loss level.",
                "condition": "strategy_setup_detected",
                "icon": "bi-layers-fill",
            },
            {
                "id": "aorb_5",
                "title": "Execute the Trade",
                "description": "Enter with SL at FVG boundary. TP targets the next significant level at 2-3x risk. The strict filters mean fewer trades but higher quality.",
                "condition": "has_open_position",
                "icon": "bi-cursor",
            },
            {
                "id": "aorb_6",
                "title": "Manage & Review",
                "description": "Watch P&L. Review whether the strict filters helped avoid false breakouts. Advanced ORB should have a higher win rate than basic ORB.",
                "condition": "position_closed",
                "icon": "bi-mortarboard",
            },
        ],
        "info": {
            "what": "Advanced ORB adds stricter displacement and wick filters to the base ORB strategy. Fewer trades but higher conviction setups.",
            "best_conditions": "Same instruments as ORB (Gold, NAS100). Best when volatility is moderate - too low means no displacement, too high means wider stops.",
            "common_mistakes": [
                "Getting impatient because fewer setups pass the strict filters",
                "Lowering the displacement threshold to get more trades (defeats the purpose)",
                "Not comparing results with basic ORB to see if the stricter filters actually help",
            ],
            "glossary": {
                "Displacement Percentile": "How strong a candle is compared to recent history (85th = top 15%)",
                "Wick Ratio": "Opposing wick / total candle size. Low = strong conviction. Max 0.32 for Advanced ORB",
            },
        },
    },

    # ──────────────────────────────────────────────────
    # 3. ORB + ML Strategy
    # ──────────────────────────────────────────────────
    "orb_ml_strategy": {
        "name": "ORB + ML Filter",
        "description": "ORB strategy with machine learning probability filter",
        "steps": [
            {
                "id": "oml_1", "title": "Mark the Opening Range",
                "description": "Same 15-minute ORB window. The ML model will score each setup AFTER the pattern forms.",
                "condition": "has_day_context", "icon": "bi-rulers",
            },
            {
                "id": "oml_2", "title": "Read the Bias",
                "description": "Check the directional bias. The ML model uses bias strength as one of its 35 features.",
                "condition": "bias_strong", "threshold": 40, "icon": "bi-compass",
            },
            {
                "id": "oml_3", "title": "Wait for Breakout + FVG",
                "description": "Standard ORB breakout + FVG confirmation. Same as basic ORB steps 3-4.",
                "condition": "strategy_setup_detected", "icon": "bi-lightning-charge",
            },
            {
                "id": "oml_4", "title": "ML Confidence Check",
                "description": "The AI model scores this trade 0-100%. Green (60%+) = the model agrees this is a good trade. Red (<40%) = the model says SKIP. Yellow = borderline.",
                "condition": "strategy_setup_detected", "icon": "bi-robot",
            },
            {
                "id": "oml_5", "title": "Execute the Trade",
                "description": "Only enter if ML score is above your threshold. The model has seen thousands of past trades and knows which setups have the best odds.",
                "condition": "has_open_position", "icon": "bi-cursor",
            },
            {
                "id": "oml_6", "title": "Review ML Accuracy",
                "description": "After the trade closes, check: did the ML model's prediction match the outcome? Track ML accuracy over time.",
                "condition": "position_closed", "icon": "bi-graph-up",
            },
        ],
        "info": {
            "what": "Adds a machine learning filter on top of ORB. The ML model uses 35 features (volatility, trend, session levels, etc.) to predict win probability.",
            "best_conditions": "Requires a trained ML model. Works best when the model has been trained on 200+ trades from backtesting.",
            "common_mistakes": [
                "Trading without a trained model (the score will be meaningless)",
                "Ignoring ML rejections because 'the chart looks good' - trust the data",
                "Not retraining the model periodically as market conditions change",
            ],
            "glossary": {
                "ML Filter": "Machine learning model that predicts trade win probability",
                "Feature Vector": "35 market measurements fed to the model (bias, volatility, trend, etc.)",
                "AUC-ROC": "Model quality metric: 0.5 = random, 0.7+ = useful, 0.8+ = excellent",
            },
        },
    },

    # ──────────────────────────────────────────────────
    # 4. Advanced ORB + ML Strategy
    # ──────────────────────────────────────────────────
    "advanced_orb_ml_strategy": {
        "name": "Advanced ORB + ML Filter",
        "description": "Strictest ORB variant with ML confidence filter",
        "steps": [
            {
                "id": "aoml_1", "title": "Mark the Opening Range",
                "description": "15-minute ORB window with Advanced ORB's strict breakout filters + ML scoring.",
                "condition": "has_day_context", "icon": "bi-rulers",
            },
            {
                "id": "aoml_2", "title": "Check Strong Bias",
                "description": "Bias 40+ with Advanced ORB's additional session level checks.",
                "condition": "bias_strong", "threshold": 40, "icon": "bi-compass",
            },
            {
                "id": "aoml_3", "title": "Wait for Strong Breakout + FVG",
                "description": "85th percentile displacement + wick ratio <0.32 + FVG confirmation.",
                "condition": "strategy_setup_detected", "icon": "bi-lightning-charge-fill",
            },
            {
                "id": "aoml_4", "title": "ML Confidence Check",
                "description": "Even with perfect chart setup, the ML model must agree. This double filter produces the highest-quality trades.",
                "condition": "strategy_setup_detected", "icon": "bi-robot",
            },
            {
                "id": "aoml_5", "title": "Execute",
                "description": "Enter only if BOTH Advanced ORB criteria AND ML confidence pass. Fewer trades, maximum precision.",
                "condition": "has_open_position", "icon": "bi-cursor",
            },
            {
                "id": "aoml_6", "title": "Track & Compare",
                "description": "Compare results vs basic ORB and ORB+ML. Does the extra filtering improve your win rate?",
                "condition": "position_closed", "icon": "bi-bar-chart",
            },
        ],
        "info": {
            "what": "The strictest ORB variant combining Advanced ORB's pattern filters with ML probability scoring.",
            "best_conditions": "Requires trained ML model AND produces very few trades. Best for traders who prefer quality over quantity.",
            "common_mistakes": [
                "Expecting many trades - this combo is VERY selective",
                "Not having enough backtest data to train a reliable ML model",
            ],
            "glossary": {
                "Double Filter": "Both chart pattern (Advanced ORB) AND ML model must agree",
            },
        },
    },

    # ──────────────────────────────────────────────────
    # 5. MACD + EMA Trend-Following
    # ──────────────────────────────────────────────────
    "macd_ema_strategy": {
        "name": "MACD + EMA Trend-Following",
        "description": "Ride strong trends using EMA alignment and MACD crossovers",
        "steps": [
            {
                "id": "macd_1",
                "title": "Check EMA Stack",
                "description": "Three colored lines should be stacked in order. For BUYING: green (fast EMA9) on top > blue (mid EMA21) > orange (slow EMA50). This means a clear uptrend. Reverse for selling.",
                "condition": "ema_aligned_bull",
                "icon": "bi-bar-chart-steps",
            },
            {
                "id": "macd_2",
                "title": "Verify Trend Strength",
                "description": "The ADX indicator (bottom panel) must be above 25. This means the trend has POWER behind it. Below 25 = the market is choppy and indecisive - skip!",
                "condition": "adx_above",
                "threshold": 25,
                "icon": "bi-speedometer2",
            },
            {
                "id": "macd_3",
                "title": "Wait for MACD Cross",
                "description": "Watch the MACD panel below the chart. When the blue MACD line crosses ABOVE the orange signal line = BUY signal. Crosses BELOW = SELL signal.",
                "condition": "strategy_setup_detected",
                "icon": "bi-intersect",
            },
            {
                "id": "macd_4",
                "title": "Confirm Growing Histogram",
                "description": "The MACD histogram bars must be GROWING in your direction for 2+ bars. Growing green bars = strong bullish momentum. Growing red = strong bearish.",
                "condition": "strategy_setup_detected",
                "icon": "bi-bar-chart-fill",
            },
            {
                "id": "macd_5",
                "title": "Execute Trade",
                "description": "Enter at the next candle's open. Stop Loss goes below EMA50 (orange line). Take Profit at 2.5x your risk distance.",
                "condition": "has_open_position",
                "icon": "bi-cursor",
            },
        ],
        "info": {
            "what": "A trend-following strategy that uses three EMAs to confirm trend direction, ADX to confirm trend strength, and MACD crossovers for entry timing. It only trades when all three conditions align.",
            "best_conditions": "Trending markets. Works on Gold and indices when ADX > 25. Avoid in ranging/choppy conditions.",
            "common_mistakes": [
                "Trading when ADX is below 25 - the trend isn't strong enough",
                "Entering before the MACD cross confirms - EMAs alone aren't enough",
                "Holding through EMA crosses - if EMAs flip, the trend may be over",
                "Using on ranging markets - this strategy NEEDS trends to work",
            ],
            "glossary": {
                "EMA": "Exponential Moving Average - weighted toward recent prices",
                "MACD": "Moving Average Convergence Divergence - momentum indicator",
                "ADX": "Average Directional Index - measures trend strength (25+ = trending)",
                "EMA Stack": "When EMAs are ordered by speed (fast > mid > slow = uptrend)",
            },
        },
    },

    # ──────────────────────────────────────────────────
    # 6. Basso Mean Reversion
    # ──────────────────────────────────────────────────
    "basso_strategy": {
        "name": "Basso Mean Reversion",
        "description": "Trade the snap-back when price stretches too far from average",
        "steps": [
            {
                "id": "basso_1",
                "title": "Find the Average",
                "description": "The blue SMA(20) line shows the 'average' price over 20 bars. Price ALWAYS wants to return to this line - like a rubber band that's been stretched.",
                "condition": "always",
                "icon": "bi-dash-lg",
            },
            {
                "id": "basso_2",
                "title": "Spot Overextension",
                "description": "Price is now 2+ ATR away from the SMA. The rubber band is STRETCHED to its limit. Look at the shaded bands - price should be outside them.",
                "condition": "overextended",
                "icon": "bi-arrow-bar-up",
            },
            {
                "id": "basso_3",
                "title": "Confirm RSI Extreme",
                "description": "RSI below 30 = oversold (buy opportunity). RSI above 70 = overbought (sell opportunity). This confirms the overextension from another angle.",
                "condition": "rsi_extreme",
                "icon": "bi-thermometer-half",
            },
            {
                "id": "basso_4",
                "title": "Spot Reversal Candle",
                "description": "Look for a hammer, pin bar, or engulfing candle. These patterns signal that the snap-back is starting. The long wick shows rejection of extreme prices.",
                "condition": "strategy_setup_detected",
                "icon": "bi-pin-angle",
            },
            {
                "id": "basso_5",
                "title": "Trade the Snap-Back",
                "description": "Buy the bounce (or sell the drop). Target: the SMA line itself. Stop Loss: beyond the extreme. The rubber band is snapping back to the average.",
                "condition": "has_open_position",
                "icon": "bi-cursor",
            },
        ],
        "info": {
            "what": "Mean reversion strategy that enters when price stretches too far from its average (SMA20). Uses RSI and reversal candle patterns for confirmation.",
            "best_conditions": "Ranging/oscillating markets. Gold and FX pairs that tend to revert. Avoid during strong news events.",
            "common_mistakes": [
                "Trying to catch falling knives - wait for the reversal candle FIRST",
                "Trading in strong trends - if ADX > 30, the 'rubber band' might not snap back",
                "Setting TP beyond the SMA - the average IS the target",
                "Ignoring RSI - price can stay overextended longer than you think",
            ],
            "glossary": {
                "Mean Reversion": "The tendency for price to return to its average over time",
                "SMA": "Simple Moving Average - the 'average' price line",
                "ATR": "Average True Range - measures typical price movement per bar",
                "RSI": "Relative Strength Index - measures if price is overbought (>70) or oversold (<30)",
                "Pin Bar": "A candle with a long wick showing rejection of a price level",
            },
        },
    },

    # ──────────────────────────────────────────────────
    # 7. Confluence Zone Strategy
    # ──────────────────────────────────────────────────
    "confluence_zone_strategy": {
        "name": "Multi-TF Confluence Zone",
        "description": "Find super-strong support/resistance where multiple levels cluster",
        "steps": [
            {
                "id": "conf_1",
                "title": "Draw All Levels",
                "description": "The chart shows EMA50, EMA200, session highs/lows, and round numbers ($2800, $2850, etc.). Each of these is a price 'magnet' where the market tends to react.",
                "condition": "has_day_context",
                "icon": "bi-grid-3x3",
            },
            {
                "id": "conf_2",
                "title": "Find the Cluster",
                "description": "When 3+ levels are within 1 ATR of each other, you've found a 'confluence zone' - a SUPER strong support/resistance area. Look for the shaded zone on the chart.",
                "condition": "strategy_setup_detected",
                "icon": "bi-bullseye",
            },
            {
                "id": "conf_3",
                "title": "Wait for Approach",
                "description": "Price is moving toward the zone. Be patient - wait for price to actually reach the zone before making any decisions.",
                "condition": "strategy_setup_detected",
                "icon": "bi-sign-turn-right",
            },
            {
                "id": "conf_4",
                "title": "Spot Reversal at Zone",
                "description": "At the zone, look for reversal candles: pin bars, engulfing patterns, hammers. The zone acts like a wall - price should bounce off it.",
                "condition": "strategy_setup_detected",
                "icon": "bi-shield-check",
            },
            {
                "id": "conf_5",
                "title": "Trade the Bounce",
                "description": "Enter the reversal. Stop Loss goes on the other side of the zone. Take Profit at 2.5x risk toward the next significant level.",
                "condition": "has_open_position",
                "icon": "bi-cursor",
            },
        ],
        "info": {
            "what": "Identifies areas where multiple technical levels cluster together (EMA, session levels, round numbers). These 'confluence zones' are extremely strong support/resistance.",
            "best_conditions": "Any market with clear levels. Best when price approaches a zone for the first time. The more levels that cluster, the stronger the zone.",
            "common_mistakes": [
                "Trading at a single level instead of a ZONE (need 3+ levels clustered)",
                "Not waiting for a reversal candle at the zone",
                "Ignoring that zones can break if momentum is extreme",
                "Setting stop loss too tight - put it on the OTHER side of the entire zone",
            ],
            "glossary": {
                "Confluence": "Multiple technical factors pointing to the same price area",
                "Support": "A price floor where buying pressure tends to push price up",
                "Resistance": "A price ceiling where selling pressure tends to push price down",
                "Round Number": "Psychologically significant prices ($2800, $2850, etc.)",
            },
        },
    },

    # ──────────────────────────────────────────────────
    # 8. Liquidity Sweep Reversal
    # ──────────────────────────────────────────────────
    "liquidity_sweep_strategy": {
        "name": "Liquidity Sweep Reversal",
        "description": "Trade when big money 'sweeps' stop-loss clusters then reverses",
        "steps": [
            {
                "id": "liq_1",
                "title": "Mark Session Levels",
                "description": "Draw lines at yesterday's high/low and Asian session high/low. Retail traders put their stop-losses here - and big money HUNTS these stops for liquidity.",
                "condition": "has_day_context",
                "icon": "bi-rulers",
            },
            {
                "id": "liq_2",
                "title": "Watch for the Sweep",
                "description": "A candle pokes THROUGH a session level (the wick goes beyond it). This is big money grabbing all those stop-loss orders. The wick must penetrate by at least 0.3 ATR.",
                "condition": "strategy_setup_detected",
                "icon": "bi-exclamation-triangle",
            },
            {
                "id": "liq_3",
                "title": "Confirm Rejection",
                "description": "Within 5 bars, price must close back INSIDE the level. The sweep FAILED to sustain - big money grabbed the stops and is now reversing direction.",
                "condition": "strategy_setup_detected",
                "icon": "bi-arrow-return-left",
            },
            {
                "id": "liq_4",
                "title": "Check for FVG (Optional)",
                "description": "A Fair Value Gap forming in the reversal direction adds extra confidence that institutions are turning around. Not required but makes the trade stronger.",
                "condition": "strategy_setup_detected",
                "icon": "bi-layers",
            },
            {
                "id": "liq_5",
                "title": "Trade the Reversal",
                "description": "Enter OPPOSITE to the sweep direction. If they swept the high (and failed), SELL. If they swept the low (and failed), BUY. SL beyond the sweep wick. TP at 3x risk.",
                "condition": "has_open_position",
                "icon": "bi-cursor",
            },
        ],
        "info": {
            "what": "Identifies when institutional traders 'sweep' retail stop-loss clusters at session levels, then reverse. You trade the reversal after the sweep fails.",
            "best_conditions": "NAS100 on M15 timeframe (proven in backtesting). Works during session transitions when liquidity pools form at session extremes.",
            "common_mistakes": [
                "Trading every wick that pokes through a level - it must be a REAL sweep (0.3+ ATR penetration)",
                "Not waiting for rejection - the sweep must FAIL (price closes back inside)",
                "Trading in the sweep direction instead of the reversal",
                "Ignoring the 5-bar window - if rejection takes too long, the setup is invalid",
            ],
            "glossary": {
                "Liquidity Sweep": "A quick move through a level to trigger stop-losses before reversing",
                "Stop Hunt": "When price deliberately moves to levels where stops are clustered",
                "Session Levels": "Previous day high/low, Asian high/low - natural stop-loss placement areas",
                "Rejection": "When price fails to sustain beyond a level and closes back inside",
            },
        },
    },

    # ──────────────────────────────────────────────────
    # 9. VWAP Mean Reversion
    # ──────────────────────────────────────────────────
    "vwap_reversion_strategy": {
        "name": "VWAP Mean Reversion",
        "description": "Trade back to VWAP when price deviates 2+ standard deviations",
        "steps": [
            {
                "id": "vwap_1",
                "title": "Draw VWAP Line",
                "description": "VWAP (blue line) = the Volume-Weighted Average Price. Institutions use this as their 'fair value' benchmark. The bands show 2\u03c3 and 3\u03c3 deviations.",
                "condition": "always",
                "icon": "bi-water",
            },
            {
                "id": "vwap_2",
                "title": "Confirm Ranging Market",
                "description": "ADX must be BELOW 30. This strategy only works when the market is going SIDEWAYS (ranging). If ADX > 30, the market is trending - don't trade this!",
                "condition": "adx_below",
                "threshold": 30,
                "icon": "bi-arrows-collapse",
            },
            {
                "id": "vwap_3",
                "title": "Detect 2-Sigma Move",
                "description": "Price has touched or crossed the outer band (2 standard deviations from VWAP). This is an extreme move in a ranging market - a snap-back is likely.",
                "condition": "vwap_deviation",
                "icon": "bi-arrow-up-right-circle",
            },
            {
                "id": "vwap_4",
                "title": "Check RSI Confirmation",
                "description": "RSI below 35 (oversold = buy) or above 65 (overbought = sell) confirms the extreme. Two indicators agreeing = stronger signal.",
                "condition": "rsi_extreme",
                "icon": "bi-thermometer-half",
            },
            {
                "id": "vwap_5",
                "title": "Spot Reversal Candle",
                "description": "A reversal candle near the band signals the snap-back is starting. Look for pin bars, hammers, or engulfing patterns.",
                "condition": "strategy_setup_detected",
                "icon": "bi-pin-angle",
            },
            {
                "id": "vwap_6",
                "title": "Trade Toward VWAP",
                "description": "Target = the VWAP line (blue). Stop Loss = the 3-sigma band. Minimum 2:1 reward-to-risk. You're betting price returns to 'fair value'.",
                "condition": "has_open_position",
                "icon": "bi-cursor",
            },
        ],
        "info": {
            "what": "Uses VWAP (Volume-Weighted Average Price) as an anchor for 'fair value'. When price deviates 2+ standard deviations in a ranging market, trades the reversion back to VWAP.",
            "best_conditions": "Gold (XAUUSD) in ranging conditions (ADX < 30). Best during midday when volatility settles after the session open.",
            "common_mistakes": [
                "Trading when ADX > 30 - the market is TRENDING and won't revert",
                "Not waiting for reversal candle confirmation near the band",
                "Setting TP beyond VWAP - the average IS your target",
                "Using this near news events - volatility can push through all bands",
            ],
            "glossary": {
                "VWAP": "Volume-Weighted Average Price - institutional 'fair value' line",
                "Standard Deviation (\u03c3)": "Measure of how spread out prices are from average",
                "2\u03c3 Band": "Price is ~95% likely to be within this range - touching it is extreme",
                "Ranging Market": "Market moving sideways without a clear trend (ADX < 30)",
            },
        },
    },

    # ──────────────────────────────────────────────────
    # 10. Keltner Channel Breakout
    # ──────────────────────────────────────────────────
    "keltner_breakout_strategy": {
        "name": "Keltner Channel Breakout",
        "description": "Trade the volatility explosion when Bollinger Bands squeeze inside Keltner Channels",
        "steps": [
            {
                "id": "kelt_1",
                "title": "Draw the Channels",
                "description": "Two sets of bands: Keltner Channels (solid, wider) and Bollinger Bands (dashed, inner). When BB is INSIDE KC = volatility is being compressed.",
                "condition": "always",
                "icon": "bi-distribute-vertical",
            },
            {
                "id": "kelt_2",
                "title": "Detect Squeeze",
                "description": "Red dots below the chart = SQUEEZE ON! Bollinger Bands are inside Keltner Channels. The market is a coiled spring, ready to EXPLODE in one direction.",
                "condition": "squeeze_on",
                "icon": "bi-record-circle",
            },
            {
                "id": "kelt_3",
                "title": "Wait for FIRE",
                "description": "Green dot = SQUEEZE FIRED! The spring is releasing. Bollinger Bands are expanding past Keltner Channels. A big move is starting NOW.",
                "condition": "squeeze_fired",
                "icon": "bi-bullseye",
            },
            {
                "id": "kelt_4",
                "title": "Confirm ADX > 20",
                "description": "ADX above 20 confirms the breakout has real trend power behind it, not just random noise.",
                "condition": "adx_above",
                "threshold": 20,
                "icon": "bi-speedometer2",
            },
            {
                "id": "kelt_5",
                "title": "Check ROC Direction",
                "description": "Rate of Change confirms the direction. Positive ROC = buy the breakout upward. Negative ROC = sell the breakout downward.",
                "condition": "strategy_setup_detected",
                "icon": "bi-graph-up-arrow",
            },
            {
                "id": "kelt_6",
                "title": "Trade the Breakout",
                "description": "Enter when price breaks the Keltner Channel band. SL at the opposite band. TP at 2.5x risk. The coiled spring is unwinding!",
                "condition": "has_open_position",
                "icon": "bi-cursor",
            },
        ],
        "info": {
            "what": "Uses the TTM Squeeze concept: when Bollinger Bands contract inside Keltner Channels, volatility is at a minimum. The subsequent expansion produces powerful breakout moves.",
            "best_conditions": "Gold (XAUUSD) on M15. The squeeze works best after periods of consolidation. Avoid during lunch hours when volume is low.",
            "common_mistakes": [
                "Entering during the squeeze (BEFORE it fires) - wait for the green dot!",
                "Ignoring ADX - a squeeze can fire but produce a weak, directionless move",
                "Not checking ROC for direction - the squeeze tells WHEN, ROC tells WHICH WAY",
                "Trading on instruments where Keltner doesn't work (NAS100 showed -$1,718 in testing)",
            ],
            "glossary": {
                "Keltner Channel": "Bands based on ATR (volatility) around an EMA",
                "Bollinger Bands": "Bands based on standard deviation around an SMA",
                "TTM Squeeze": "When BB is inside KC - volatility at minimum, breakout imminent",
                "ROC": "Rate of Change - measures momentum direction and speed",
            },
        },
    },

    # ──────────────────────────────────────────────────
    # 11. BB Squeeze Breakout
    # ──────────────────────────────────────────────────
    "bb_squeeze_strategy": {
        "name": "Bollinger Squeeze Breakout",
        "description": "Trade when Bollinger Band width hits a 120-bar low and price breaks out",
        "steps": [
            {
                "id": "bb_1",
                "title": "Draw Bollinger Bands",
                "description": "The bands show volatility. NARROW bands = quiet market. WIDE bands = active market. Watch the band width - it tells you when a big move is brewing.",
                "condition": "always",
                "icon": "bi-distribute-horizontal",
            },
            {
                "id": "bb_2",
                "title": "Find BandWidth Low",
                "description": "BandWidth is at or near a 120-bar minimum. Volatility is at ROCK BOTTOM. History shows: after extreme quiet comes extreme movement. A big move is brewing!",
                "condition": "strategy_setup_detected",
                "icon": "bi-graph-down",
            },
            {
                "id": "bb_3",
                "title": "Wait for Breakout",
                "description": "Price closes OUTSIDE the Bollinger Band! Upper band break = bullish breakout. Lower band break = bearish breakout. The quiet period is OVER.",
                "condition": "price_beyond_band",
                "icon": "bi-box-arrow-up-right",
            },
            {
                "id": "bb_4",
                "title": "Confirm Momentum",
                "description": "Linear regression slope confirms the direction. Positive and rising = bullish momentum. Negative and falling = bearish momentum.",
                "condition": "strategy_setup_detected",
                "icon": "bi-arrow-up-right",
            },
            {
                "id": "bb_5",
                "title": "Check Volume Spike",
                "description": "Volume must spike to 1.3x the average. High volume confirms REAL participation - not just a fake move. Low volume breakouts often fail.",
                "condition": "strategy_setup_detected",
                "icon": "bi-bar-chart",
            },
            {
                "id": "bb_6",
                "title": "Trade the Breakout",
                "description": "Enter the breakout direction. SL at BB middle line (SMA20). TP at 2x the band spread. Ride the volatility expansion!",
                "condition": "has_open_position",
                "icon": "bi-cursor",
            },
        ],
        "info": {
            "what": "Identifies periods of extremely low volatility (BandWidth at 120-bar minimum) and trades the subsequent breakout when price escapes the narrow Bollinger Bands.",
            "best_conditions": "Gold, GBPUSD, EURUSD on M15. Works best when volatility has been compressing for an extended period. The longer the squeeze, the bigger the breakout.",
            "common_mistakes": [
                "Entering before the breakout candle closes outside the band - wait for confirmation!",
                "Not checking volume - low volume breakouts are often fake",
                "Setting stop loss too far from BB middle - that's your invalidation level",
                "Trading BandWidth that isn't near a 120-bar minimum - it needs to be EXTREME compression",
            ],
            "glossary": {
                "BandWidth": "Measures how wide/narrow the Bollinger Bands are (volatility proxy)",
                "120-bar minimum": "BandWidth at its lowest in 120 bars - extreme compression",
                "Linear Regression": "Statistical line showing price direction and momentum",
                "Volume Spike": "Volume 1.3x above average - confirms real market participation",
            },
        },
    },
}
