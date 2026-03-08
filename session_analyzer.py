"""
Session analysis: Premarket levels, bias, trend detection
"""

import MetaTrader5 as mt5
import pandas as pd
from datetime import timedelta
from logger import logger
from config import (
    ORB_START_TIME, ORB_END_TIME, TRADE_END_TIME,
    ASIAN_START, ASIAN_END, LONDON_START, LONDON_END,
    MIN_ADR_FOR_TREND, ADR_PERIOD
)


class SessionAnalyzer:
    """Analyzes trading sessions and market structure"""
    
    def __init__(self, data_manager):
        self.data_manager = data_manager
        
        # Levels
        self.pd_high = None
        self.pd_low = None
        self.asian_high = None
        self.asian_low = None
        self.london_high = None
        self.london_low = None
        self.orb_high = None
        self.orb_low = None
        
        # Analysis
        self.bias = 'neutral'
        self.next_liquidity = None
        self.is_trending = False
        
    def analyze_premarket(self, current_date):
        """
        Calculate previous day and overnight session levels
        
        Args:
            current_date: date object for today
        """
        yesterday = current_date - timedelta(days=1)
        
        # Previous Day Session (9:30 AM - 4:00 PM yesterday)
        pd_data = self.data_manager.get_session_data(
            ORB_START_TIME, 
            TRADE_END_TIME, 
            yesterday
        )
        
        if not pd_data.empty:
            self.pd_high = pd_data['high'].max()
            self.pd_low = pd_data['low'].min()
            logger.info(f"📊 PD High={self.pd_high:.2f} | Low={self.pd_low:.2f}")
        else:
            logger.warning("⚠️ No previous day data")
        
        # Asian Session (8pm yesterday to 2am today)
        df_full = self.data_manager.get_data()
        asian_start_dt = pd.Timestamp.combine(
            yesterday, 
            ASIAN_START
        ).tz_localize(self.data_manager.ny_tz)
        asian_end_dt = pd.Timestamp.combine(
            current_date, 
            ASIAN_END
        ).tz_localize(self.data_manager.ny_tz)
        
        asian_data = df_full[(df_full.index >= asian_start_dt) & 
                             (df_full.index < asian_end_dt)]
        
        if not asian_data.empty:
            self.asian_high = asian_data['high'].max()
            self.asian_low = asian_data['low'].min()
            logger.info(f"🌏 Asian High={self.asian_high:.2f} | Low={self.asian_low:.2f}")
        else:
            logger.warning("⚠️ No Asian session data")
        
        # London Session (3am - 12pm today)
        london_data = self.data_manager.get_session_data(
            LONDON_START,
            LONDON_END,
            current_date
        )
        
        if not london_data.empty:
            self.london_high = london_data['high'].max()
            self.london_low = london_data['low'].min()
            logger.info(f"🇬🇧 London High={self.london_high:.2f} | Low={self.london_low:.2f}")
        
        # Determine bias
        self._calculate_bias()
        
        # Check trend
        self._check_trending_week()
    
    def _calculate_bias(self):
        """
        Calculate session bias from price structure
        
        Logic:
        - If London swept Asian low then rallied → Bullish
        - If London swept Asian high then dropped → Bearish
        - If PD high broken + Asian high broken → Strong Bullish
        - If PD low broken + Asian low broken → Strong Bearish
        - Otherwise → Neutral
        """
        if None in [self.pd_high, self.pd_low, self.asian_high, self.asian_low]:
            self.bias = 'neutral'
            logger.info("📈 Bias: NEUTRAL (insufficient data)")
            return
        
        df = self.data_manager.get_data(bars=100)
        if df.empty:
            self.bias = 'neutral'
            return
        
        current_price = df.iloc[-1].close
        
        # Strong bullish: both PD and Asian highs broken
        if (current_price > self.pd_high and 
            current_price > self.asian_high):
            self.bias = 'bullish'
            self.next_liquidity = self.pd_high + 2.0  # Target above
            logger.info(f"📈 Bias: BULLISH (broke PD & Asian highs) | Target: {self.next_liquidity:.2f}")
        
        # Strong bearish: both PD and Asian lows broken
        elif (current_price < self.pd_low and 
              current_price < self.asian_low):
            self.bias = 'bearish'
            self.next_liquidity = self.pd_low - 2.0  # Target below
            logger.info(f"📉 Bias: BEARISH (broke PD & Asian lows) | Target: {self.next_liquidity:.2f}")
        
        # Asian range expansion
        elif current_price > self.asian_high:
            self.bias = 'bullish'
            self.next_liquidity = self.pd_high
            logger.info(f"📈 Bias: BULLISH (above Asian high) | Target: {self.next_liquidity:.2f}")
        
        elif current_price < self.asian_low:
            self.bias = 'bearish'
            self.next_liquidity = self.pd_low
            logger.info(f"📉 Bias: BEARISH (below Asian low) | Target: {self.next_liquidity:.2f}")
        
        else:
            # Within range - check London bias
            if self.london_high and self.london_low:
                london_range_mid = (self.london_high + self.london_low) / 2
                
                if current_price > london_range_mid:
                    self.bias = 'bullish'
                    self.next_liquidity = self.asian_high
                else:
                    self.bias = 'bearish'
                    self.next_liquidity = self.asian_low
                
                logger.info(f"📊 Bias: {self.bias.upper()} (London bias) | Target: {self.next_liquidity:.2f}")
            else:
                self.bias = 'neutral'
                logger.info("📊 Bias: NEUTRAL (ranging)")
    
    def _check_trending_week(self):
        """
        Determine if market is trending based on ADR
        
        Trending = Average Daily Range > threshold
        """
        # Get daily data
        daily_rates = mt5.copy_rates_from_pos(
            self.data_manager.symbol, 
            mt5.TIMEFRAME_D1, 
            0, 
            ADR_PERIOD + 2
        )
        
        if daily_rates is None or len(daily_rates) < ADR_PERIOD:
            logger.warning("⚠️ Insufficient daily data for trend filter")
            self.is_trending = True  # Default allow trading
            return
        
        daily_df = pd.DataFrame(daily_rates)
        daily_ranges = daily_df['high'] - daily_df['low']
        avg_range = daily_ranges.tail(ADR_PERIOD).mean()
        
        self.is_trending = avg_range > MIN_ADR_FOR_TREND
        
        status = "TRENDING ✅" if self.is_trending else "RANGING ⛔"
        logger.info(f"📈 {ADR_PERIOD}D ADR: ${avg_range:.2f} | {status}")
    
    def calculate_orb(self, current_date):
        """
        Calculate Opening Range Breakout levels
        
        Args:
            current_date: date object for today
            
        Returns:
            bool indicating if ORB is ready
        """
        orb_data = self.data_manager.get_session_data(
            ORB_START_TIME,
            ORB_END_TIME,
            current_date
        )
        
        if orb_data.empty or len(orb_data) < 5:
            return False
        
        self.orb_high = orb_data['high'].max()
        self.orb_low = orb_data['low'].min()
        
        orb_range = self.orb_high - self.orb_low
        logger.info(f"🎯 ORB SET | High={self.orb_high:.2f} | Low={self.orb_low:.2f} | Range=${orb_range:.2f}")
        
        return True
    
    def is_orb_valid(self):
        """Check if ORB range is tradeable (not too tight)"""
        if self.orb_high is None or self.orb_low is None:
            return False
        
        orb_range = self.orb_high - self.orb_low
        return orb_range >= 0.50  # Minimum $0.50 range
    
    def reset(self):
        """Reset all session data (call on new day)"""
        self.pd_high = None
        self.pd_low = None
        self.asian_high = None
        self.asian_low = None
        self.london_high = None
        self.london_low = None
        self.orb_high = None
        self.orb_low = None
        self.bias = 'neutral'
        self.next_liquidity = None
        logger.debug("Session analyzer reset")
