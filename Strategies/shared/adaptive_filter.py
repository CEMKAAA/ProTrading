"""
Adaptive Filter - Dynamically disables underperforming setup types.

Tracks per-setup-type rolling win rate using a sliding window.
Uses hysteresis thresholds to avoid rapid toggling:
  - Disable at 35% win rate
  - Re-enable at 45% win rate

State is persisted to JSON so it survives restarts.
"""

import json
import logging
from pathlib import Path
from datetime import datetime

logger = logging.getLogger(__name__)

DEFAULT_STATE_FILE = (
    Path(__file__).parent.parent.parent / "dashboard" / "data" / "adaptive_filter_state.json"
)


class AdaptiveFilter:
    """Tracks per-setup-type rolling win rate and disables underperformers."""

    def __init__(
        self,
        state_file=None,
        window_size=30,
        min_trades=10,
        disable_threshold=0.35,
        enable_threshold=0.45,
    ):
        self.state_file = str(state_file or DEFAULT_STATE_FILE)
        self.window_size = window_size
        self.min_trades = min_trades
        self.disable_threshold = disable_threshold
        self.enable_threshold = enable_threshold

    def _load(self) -> dict:
        """Load state from JSON file."""
        try:
            path = Path(self.state_file)
            if path.exists():
                with open(path, 'r') as f:
                    return json.load(f)
        except Exception as e:
            logger.warning(f"AdaptiveFilter._load failed: {e}")
        return {}

    def _save(self, state: dict):
        """Save state to JSON file."""
        try:
            path = Path(self.state_file)
            path.parent.mkdir(parents=True, exist_ok=True)
            with open(path, 'w') as f:
                json.dump(state, f, indent=2)
        except Exception as e:
            logger.warning(f"AdaptiveFilter._save failed: {e}")

    def record_result(self, setup_type: str, won: bool):
        """Record win/loss for a setup type. Maintains rolling window."""
        state = self._load()
        entry = state.setdefault(setup_type, {'results': [], 'disabled': False})
        entry['results'].append(1 if won else 0)
        # Trim to window_size
        entry['results'] = entry['results'][-self.window_size:]
        entry['last_updated'] = datetime.utcnow().isoformat()

        # Check thresholds (only after min_trades)
        if len(entry['results']) >= self.min_trades:
            win_rate = sum(entry['results']) / len(entry['results'])
            if not entry['disabled'] and win_rate < self.disable_threshold:
                entry['disabled'] = True
                entry['disabled_at'] = datetime.utcnow().isoformat()
                logger.info(
                    f"ADAPTIVE FILTER: Disabled '{setup_type}' "
                    f"(WR: {win_rate:.0%} < {self.disable_threshold:.0%})"
                )
            elif entry['disabled'] and win_rate >= self.enable_threshold:
                entry['disabled'] = False
                entry['enabled_at'] = datetime.utcnow().isoformat()
                logger.info(
                    f"ADAPTIVE FILTER: Re-enabled '{setup_type}' "
                    f"(WR: {win_rate:.0%} >= {self.enable_threshold:.0%})"
                )

        self._save(state)

    def should_allow(self, setup_type: str) -> tuple:
        """
        Returns (allowed: bool, info: dict with win_rate, trades, status).
        """
        state = self._load()
        entry = state.get(setup_type)
        if not entry:
            return True, {'win_rate': None, 'trades': 0, 'status': 'new'}

        results = entry.get('results', [])
        win_rate = sum(results) / len(results) if results else 0
        disabled = entry.get('disabled', False)

        return not disabled, {
            'win_rate': win_rate,
            'trades': len(results),
            'disabled': disabled,
            'status': 'blocked' if disabled else 'active',
        }

    def get_state(self) -> dict:
        """Full state for API/UI display."""
        state = self._load()
        result = {}
        for setup_type, entry in state.items():
            results = entry.get('results', [])
            win_rate = sum(results) / len(results) if results else 0
            result[setup_type] = {
                'win_rate': win_rate,
                'trades': len(results),
                'disabled': entry.get('disabled', False),
                'status': 'blocked' if entry.get('disabled', False) else 'active',
                'last_updated': entry.get('last_updated'),
            }
        return result

    def get_config(self) -> dict:
        """Return current configuration."""
        return {
            'window_size': self.window_size,
            'min_trades': self.min_trades,
            'disable_threshold': self.disable_threshold,
            'enable_threshold': self.enable_threshold,
        }

    def update_config(self, window_size=None, min_trades=None,
                      disable_threshold=None, enable_threshold=None):
        """Update filter configuration."""
        if window_size is not None:
            self.window_size = window_size
        if min_trades is not None:
            self.min_trades = min_trades
        if disable_threshold is not None:
            self.disable_threshold = disable_threshold
        if enable_threshold is not None:
            self.enable_threshold = enable_threshold

    def reset(self, setup_type=None):
        """Reset one or all setup types."""
        if setup_type:
            state = self._load()
            if setup_type in state:
                del state[setup_type]
            self._save(state)
        else:
            self._save({})
