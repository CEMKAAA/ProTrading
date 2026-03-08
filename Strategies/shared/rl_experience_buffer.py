"""
RL Experience Buffer - Stores (state, action, reward, log_prob, value) from live trades.

Persists to JSON so experiences survive restarts. The buffer accumulates
completed experiences and provides batches for online PPO updates.
"""

import json
import logging
from pathlib import Path
from datetime import datetime
from typing import List, Optional

logger = logging.getLogger(__name__)

DEFAULT_BUFFER_FILE = (
    Path(__file__).parent.parent.parent / "dashboard" / "data" / "rl_experiences.json"
)


class RLExperienceBuffer:
    """Stores (state, action, reward, log_prob, value) from live trades."""

    def __init__(self, buffer_file=None, max_buffer_size=200):
        self.buffer_file = str(buffer_file or DEFAULT_BUFFER_FILE)
        self.max_buffer_size = max_buffer_size
        self.pending = None       # Current open trade experience
        self.completed = []       # Completed experiences ready for training
        self.load()

    def record_entry(self, state, action: int, log_prob: float, value: float):
        """Called when RL agent opens a trade. Stores pending experience."""
        # Convert numpy array to list for JSON serialization
        state_list = state.tolist() if hasattr(state, 'tolist') else list(state)
        self.pending = {
            'state': state_list,
            'action': action,
            'log_prob': log_prob,
            'value': value,
            'timestamp': datetime.utcnow().isoformat(),
        }
        self.save()

    def record_exit(self, reward: float):
        """Called when trade closes. Completes the pending experience."""
        if self.pending:
            self.pending['reward'] = reward
            self.pending['completed_at'] = datetime.utcnow().isoformat()
            self.completed.append(self.pending)
            self.pending = None
            # Keep buffer bounded
            if len(self.completed) > self.max_buffer_size:
                self.completed = self.completed[-self.max_buffer_size:]
            self.save()

    def get_batch(self, min_size=20) -> Optional[List[dict]]:
        """Return completed experiences if >= min_size. Does NOT clear."""
        if len(self.completed) >= min_size:
            return list(self.completed)
        return None

    def clear_batch(self, count: int):
        """Remove oldest N experiences after successful update."""
        self.completed = self.completed[count:]
        self.save()

    def get_status(self) -> dict:
        """Get buffer status for API/UI."""
        return {
            'buffer_size': len(self.completed),
            'max_buffer_size': self.max_buffer_size,
            'has_pending': self.pending is not None,
            'pending_since': self.pending.get('timestamp') if self.pending else None,
        }

    def save(self):
        """Persist buffer to JSON file."""
        try:
            path = Path(self.buffer_file)
            path.parent.mkdir(parents=True, exist_ok=True)
            data = {
                'pending': self.pending,
                'completed': self.completed,
            }
            with open(path, 'w') as f:
                json.dump(data, f)
        except Exception as e:
            logger.warning(f"RLExperienceBuffer.save failed: {e}")

    def load(self):
        """Load buffer from JSON file."""
        try:
            path = Path(self.buffer_file)
            if path.exists():
                with open(path, 'r') as f:
                    data = json.load(f)
                self.pending = data.get('pending')
                self.completed = data.get('completed', [])
        except Exception as e:
            logger.warning(f"RLExperienceBuffer.load failed: {e}")
            self.pending = None
            self.completed = []
