"""Reinforcement Learning Trainer for Trading Strategies."""

import logging
from typing import Dict, Any, Optional, List
import numpy as np
from pathlib import Path

logger = logging.getLogger(__name__)

try:
    import torch
    import torch.nn as nn
    import torch.optim as optim
    from torch.distributions import Categorical
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False


class PolicyNetwork:
    """Actor-Critic network for PPO. Only functional when PyTorch is available."""
    pass


class RLTrainer:
    """PPO trainer for trading RL agent."""
    pass


if HAS_TORCH:
    class PolicyNetwork(nn.Module):
        """Actor-Critic network for PPO."""

        def __init__(self, state_dim: int, action_dim: int, hidden_layers: List[int] = None):
            super().__init__()
            hidden = hidden_layers or [128, 64]

            # Shared feature extractor
            layers = []
            prev_dim = state_dim
            for h in hidden:
                layers.extend([nn.Linear(prev_dim, h), nn.Tanh()])
                prev_dim = h
            self.shared = nn.Sequential(*layers)

            # Actor head (policy)
            self.actor = nn.Linear(prev_dim, action_dim)

            # Critic head (value)
            self.critic = nn.Linear(prev_dim, 1)

        def forward(self, x):
            features = self.shared(x)
            action_logits = self.actor(features)
            value = self.critic(features)
            return action_logits, value

        def get_action(self, state: np.ndarray) -> tuple:
            """Get action, log_prob, value for a state."""
            state_tensor = torch.FloatTensor(state).unsqueeze(0)
            with torch.no_grad():
                logits, value = self.forward(state_tensor)
                dist = Categorical(logits=logits)
                action = dist.sample()
                log_prob = dist.log_prob(action)
            return action.item(), log_prob.item(), value.item()

    class RLTrainer:
        """PPO trainer for trading RL agent."""

        def __init__(self, config: Dict[str, Any] = None):
            self.config = config or {}
            self.state_dim = 28
            self.action_dim = 4  # Hold, Buy, Sell, Close
            self.hidden_layers = self.config.get('hidden_layers', [128, 64])
            self.lr = self.config.get('learning_rate', 0.0003)
            self.gamma = self.config.get('gamma', 0.99)
            self.clip_epsilon = self.config.get('clip_epsilon', 0.2)
            self.epochs_per_update = self.config.get('epochs_per_update', 4)
            self.episodes = self.config.get('episodes_per_fold', 100)

            self.policy = None
            self.optimizer = None

        def train(self, price_data: np.ndarray, progress_callback=None) -> Dict[str, Any]:
            """
            Train PPO agent on price data.

            Args:
                price_data: OHLCV array (n_bars, 5)
                progress_callback: Optional callback(progress_pct, message)

            Returns:
                Training metrics dict
            """
            from .rl_environment import TradingEnvironment

            env = TradingEnvironment(price_data, self.config)

            self.policy = PolicyNetwork(self.state_dim, self.action_dim, self.hidden_layers)
            self.optimizer = optim.Adam(self.policy.parameters(), lr=self.lr)

            best_reward = float('-inf')
            episode_rewards = []
            episode_trades = []

            for episode in range(self.episodes):
                states, actions, rewards, log_probs, values = [], [], [], [], []

                state = env.reset()
                total_reward = 0

                while not env.done:
                    action, log_prob, value = self.policy.get_action(state)
                    next_state, reward, done, info = env.step(action)

                    states.append(state)
                    actions.append(action)
                    rewards.append(reward)
                    log_probs.append(log_prob)
                    values.append(value)

                    state = next_state
                    total_reward += reward

                episode_rewards.append(total_reward)
                episode_trades.append(len(env.trades))

                # PPO update
                if len(states) > 0:
                    self._ppo_update(states, actions, rewards, log_probs, values)

                if total_reward > best_reward:
                    best_reward = total_reward

                if progress_callback and episode % 10 == 0:
                    pct = (episode + 1) / self.episodes * 100
                    progress_callback(pct, f"Episode {episode + 1}/{self.episodes}, reward={total_reward:.2f}")

            # Training metrics
            metrics = {
                'episodes': self.episodes,
                'avg_reward': float(np.mean(episode_rewards[-20:])),
                'best_reward': float(best_reward),
                'avg_trades': float(np.mean(episode_trades[-20:])),
                'final_reward': float(episode_rewards[-1]) if episode_rewards else 0,
            }

            return metrics

        def _ppo_update(self, states, actions, rewards, old_log_probs, old_values):
            """Perform PPO policy update."""
            # Calculate returns and advantages
            returns = []
            G = 0
            for r in reversed(rewards):
                G = r + self.gamma * G
                returns.insert(0, G)

            returns = torch.FloatTensor(returns)
            states_t = torch.FloatTensor(np.array(states))
            actions_t = torch.LongTensor(actions)
            old_log_probs_t = torch.FloatTensor(old_log_probs)
            old_values_t = torch.FloatTensor(old_values)

            advantages = returns - old_values_t
            advantages = (advantages - advantages.mean()) / (advantages.std() + 1e-8)

            for _ in range(self.epochs_per_update):
                logits, values = self.policy(states_t)
                dist = Categorical(logits=logits)
                new_log_probs = dist.log_prob(actions_t)
                entropy = dist.entropy().mean()

                # PPO clipped objective
                ratio = torch.exp(new_log_probs - old_log_probs_t)
                surr1 = ratio * advantages
                surr2 = torch.clamp(ratio, 1 - self.clip_epsilon, 1 + self.clip_epsilon) * advantages

                actor_loss = -torch.min(surr1, surr2).mean()
                critic_loss = nn.MSELoss()(values.squeeze(), returns)
                entropy_loss = -0.01 * entropy

                loss = actor_loss + 0.5 * critic_loss + entropy_loss

                self.optimizer.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(self.policy.parameters(), 0.5)
                self.optimizer.step()

        def save(self, path: str):
            """Save trained policy."""
            if self.policy is not None:
                save_path = Path(path)
                save_path.parent.mkdir(parents=True, exist_ok=True)
                torch.save({
                    'policy_state_dict': self.policy.state_dict(),
                    'config': self.config,
                    'state_dim': self.state_dim,
                    'action_dim': self.action_dim,
                }, path)
                logger.info(f"RL model saved to {path}")

        def load(self, path: str):
            """Load trained policy."""
            checkpoint = torch.load(path, map_location='cpu', weights_only=False)
            self.config = checkpoint.get('config', self.config)
            self.state_dim = checkpoint.get('state_dim', 28)
            self.action_dim = checkpoint.get('action_dim', 4)

            self.policy = PolicyNetwork(
                self.state_dim, self.action_dim,
                self.config.get('hidden_layers', [128, 64])
            )
            self.policy.load_state_dict(checkpoint['policy_state_dict'])
            self.policy.eval()
            logger.info(f"RL model loaded from {path}")

        def online_ppo_update(self, experiences: List[dict],
                              lr_override=0.0001, epochs=2, clip_grad=0.3):
            """
            Mini PPO update from live experiences.
            Uses lower LR + fewer epochs for stability vs full training.

            Args:
                experiences: List of dicts with state, action, reward, log_prob, value
                lr_override: Learning rate (lower than training for stability)
                epochs: PPO epochs per update (fewer for online)
                clip_grad: Gradient clipping norm

            Returns:
                Dict with status and metrics
            """
            if self.policy is None:
                return {'status': 'error', 'message': 'No policy loaded'}

            try:
                # Set training mode with reduced LR
                self.policy.train()
                optimizer = optim.Adam(self.policy.parameters(), lr=lr_override)

                states = [e['state'] for e in experiences]
                actions = [e['action'] for e in experiences]
                rewards = [e['reward'] for e in experiences]
                old_log_probs = [e['log_prob'] for e in experiences]
                old_values = [e['value'] for e in experiences]

                # Calculate returns and advantages
                returns = []
                G = 0
                for r in reversed(rewards):
                    G = r + self.gamma * G
                    returns.insert(0, G)

                returns_t = torch.FloatTensor(returns)
                states_t = torch.FloatTensor(np.array(states))
                actions_t = torch.LongTensor(actions)
                old_log_probs_t = torch.FloatTensor(old_log_probs)
                old_values_t = torch.FloatTensor(old_values)

                advantages = returns_t - old_values_t
                if advantages.std() > 0:
                    advantages = (advantages - advantages.mean()) / (advantages.std() + 1e-8)

                for _ in range(epochs):
                    logits, values = self.policy(states_t)
                    dist = Categorical(logits=logits)
                    new_log_probs = dist.log_prob(actions_t)
                    entropy = dist.entropy().mean()

                    # PPO clipped objective
                    ratio = torch.exp(new_log_probs - old_log_probs_t)
                    surr1 = ratio * advantages
                    surr2 = torch.clamp(
                        ratio, 1 - self.clip_epsilon, 1 + self.clip_epsilon
                    ) * advantages

                    actor_loss = -torch.min(surr1, surr2).mean()
                    critic_loss = nn.MSELoss()(values.squeeze(), returns_t)
                    entropy_loss = -0.01 * entropy

                    loss = actor_loss + 0.5 * critic_loss + entropy_loss

                    optimizer.zero_grad()
                    loss.backward()
                    nn.utils.clip_grad_norm_(self.policy.parameters(), clip_grad)
                    optimizer.step()

                self.policy.eval()

                avg_reward = float(np.mean(rewards))
                logger.info(
                    f"Online PPO update: {len(experiences)} experiences, "
                    f"avg_reward={avg_reward:.3f}"
                )

                return {
                    'status': 'success',
                    'experiences': len(experiences),
                    'avg_reward': avg_reward,
                }

            except Exception as e:
                self.policy.eval()
                logger.error(f"Online PPO update failed: {e}")
                return {'status': 'error', 'message': str(e)}

        def predict(self, state: np.ndarray) -> int:
            """Get action from trained policy."""
            if self.policy is None:
                return 0  # Hold by default

            action, _, _ = self.policy.get_action(state)
            return action

else:
    # Stubs when PyTorch is not available
    class PolicyNetwork:
        """Stub PolicyNetwork when PyTorch is not installed."""

        def __init__(self, *args, **kwargs):
            raise ImportError("PyTorch is required for RL training. Install with: pip install torch")

    class RLTrainer:
        """Stub RLTrainer when PyTorch is not installed."""

        def __init__(self, config: Dict[str, Any] = None):
            self.config = config or {}
            self.policy = None

        def train(self, price_data: np.ndarray, progress_callback=None) -> Dict[str, Any]:
            raise ImportError("PyTorch is required for RL training. Install with: pip install torch")

        def save(self, path: str):
            raise ImportError("PyTorch is required for RL training. Install with: pip install torch")

        def load(self, path: str):
            raise ImportError("PyTorch is required for RL training. Install with: pip install torch")

        def predict(self, state: np.ndarray) -> int:
            return 0  # Hold by default
