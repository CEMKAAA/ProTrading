"""
ML Model Factory - Abstract Base Class and Concrete Implementations

Provides a factory pattern for creating different ML model types:
  - XGBoost (default, always available)
  - LightGBM (optional dependency)
  - LSTM (optional, requires PyTorch)
  - 1D-CNN (optional, requires PyTorch)
  - Ensemble (stacking: XGBoost + LightGBM with LogisticRegression meta-learner)

Usage:
    from dashboard.backend.core.ml_model_factory import create_ml_model

    model = create_ml_model("xgboost", {"n_estimators": 300})
    metrics = model.train(X_train, y_train, X_val, y_val)
    probabilities = model.predict_proba(X_test)
    model.save("path/to/model.joblib")
"""

import os
import logging
import numpy as np
from abc import ABC, abstractmethod
from typing import Dict, List, Optional, Any, Tuple

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Check optional dependencies
# ---------------------------------------------------------------------------
HAS_LIGHTGBM = False
try:
    import lightgbm  # noqa: F401
    HAS_LIGHTGBM = True
except ImportError:
    pass

HAS_TORCH = False
try:
    import torch  # noqa: F401
    HAS_TORCH = True
except ImportError:
    pass


# ===========================================================================
# Abstract Base Class
# ===========================================================================

class BaseMLModel(ABC):
    """
    Abstract base class for all ML models used in the trading system.

    Every concrete implementation must support:
      - Training on numpy arrays (X, y)
      - Probability prediction (win probability per sample)
      - Serialization (save/load)
      - Optional feature importance retrieval
    """

    def __init__(self, params: Optional[Dict[str, Any]] = None):
        self.params = params or {}
        self.is_trained = False
        self.feature_names: Optional[List[str]] = None

    @abstractmethod
    def train(
        self,
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: Optional[np.ndarray] = None,
        y_val: Optional[np.ndarray] = None,
    ) -> Dict[str, float]:
        """
        Train the model on the given data.

        Args:
            X_train: Training features, shape (n_samples, n_features)
            y_train: Training labels, shape (n_samples,), binary 0/1
            X_val: Optional validation features
            y_val: Optional validation labels

        Returns:
            Dictionary of training metrics (e.g. train_loss, val_loss, accuracy)
        """
        ...

    @abstractmethod
    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        """
        Predict win probabilities.

        Args:
            X: Features, shape (n_samples, n_features)

        Returns:
            Win probabilities, shape (n_samples,) with values in [0, 1].
            For sequence-based models (LSTM, CNN) the output may be shorter
            than the input when there are not enough preceding samples to
            form a full sequence.
        """
        ...

    @abstractmethod
    def save(self, path: str) -> None:
        """Save model weights / artifacts to *path*."""
        ...

    @abstractmethod
    def load(self, path: str) -> None:
        """Load model weights / artifacts from *path*."""
        ...

    def get_feature_importance(self) -> Optional[Dict[str, float]]:
        """
        Return per-feature importance scores, or None if not supported.

        Keys are feature names (if set) or f"feature_{i}" indices.
        """
        return None


# ===========================================================================
# XGBoost Model
# ===========================================================================

class XGBoostModel(BaseMLModel):
    """
    XGBoost gradient-boosted tree classifier.

    This is the default model type and is always available (xgboost is a
    required project dependency).
    """

    DEFAULT_PARAMS = {
        "n_estimators": 300,
        "max_depth": 3,
        "learning_rate": 0.05,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
        "min_child_weight": 10,
        "gamma": 0.1,
        "reg_alpha": 0.1,
        "reg_lambda": 1.0,
        "eval_metric": "logloss",
        "random_state": 42,
        "verbosity": 0,
    }

    def __init__(self, params: Optional[Dict[str, Any]] = None):
        super().__init__(params)
        from xgboost import XGBClassifier

        merged = {**self.DEFAULT_PARAMS, **(self.params or {})}
        self.model = XGBClassifier(**merged)

    # ---- BaseMLModel interface --------------------------------------------

    def train(
        self,
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: Optional[np.ndarray] = None,
        y_val: Optional[np.ndarray] = None,
    ) -> Dict[str, float]:
        from sklearn.metrics import accuracy_score, roc_auc_score

        logger.info(
            "XGBoost training: %d samples, %d features",
            X_train.shape[0], X_train.shape[1],
        )

        # Auto-balance classes via scale_pos_weight
        n_pos = int(np.sum(y_train == 1))
        n_neg = int(np.sum(y_train == 0))
        if n_pos > 0 and n_neg > 0:
            spw = n_neg / n_pos
            self.model.set_params(scale_pos_weight=spw)
            logger.info("XGBoost scale_pos_weight=%.3f (%d neg / %d pos)", spw, n_neg, n_pos)

        fit_kwargs: Dict[str, Any] = {}
        if X_val is not None and y_val is not None:
            fit_kwargs["eval_set"] = [(X_val, y_val)]
            fit_kwargs["verbose"] = False
            fit_kwargs["early_stopping_rounds"] = 20

        self.model.fit(X_train, y_train, **fit_kwargs)
        self.is_trained = True

        # Compute metrics
        metrics: Dict[str, float] = {}
        train_pred = self.model.predict(X_train)
        train_proba = self.model.predict_proba(X_train)[:, 1]
        metrics["train_accuracy"] = float(accuracy_score(y_train, train_pred))
        if len(np.unique(y_train)) > 1:
            metrics["train_auc"] = float(roc_auc_score(y_train, train_proba))

        if X_val is not None and y_val is not None:
            val_pred = self.model.predict(X_val)
            val_proba = self.model.predict_proba(X_val)[:, 1]
            metrics["val_accuracy"] = float(accuracy_score(y_val, val_pred))
            if len(np.unique(y_val)) > 1:
                metrics["val_auc"] = float(roc_auc_score(y_val, val_proba))

        logger.info("XGBoost training complete: %s", metrics)
        return metrics

    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        proba = self.model.predict_proba(X)
        # Return probability of the positive class (win)
        return proba[:, 1]

    def save(self, path: str) -> None:
        import joblib

        os.makedirs(os.path.dirname(path), exist_ok=True)
        joblib.dump(self.model, path)
        logger.info("XGBoost model saved to %s", path)

    def load(self, path: str) -> None:
        import joblib

        self.model = joblib.load(path)
        self.is_trained = True
        logger.info("XGBoost model loaded from %s", path)

    def get_feature_importance(self) -> Optional[Dict[str, float]]:
        if not self.is_trained:
            return None
        importances = self.model.feature_importances_
        names = self.feature_names or [f"feature_{i}" for i in range(len(importances))]
        return {
            name: round(float(imp), 6)
            for name, imp in sorted(
                zip(names, importances), key=lambda x: x[1], reverse=True
            )
        }


# ===========================================================================
# LightGBM Model
# ===========================================================================

class LightGBMModel(BaseMLModel):
    """
    LightGBM gradient-boosted tree classifier.

    Optional dependency -- if lightgbm is not installed, instantiation
    raises ImportError with a helpful message.
    """

    DEFAULT_PARAMS = {
        "n_estimators": 300,
        "max_depth": 3,
        "learning_rate": 0.05,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
        "min_child_weight": 10,
        "min_split_gain": 0.1,
        "reg_alpha": 0.1,
        "reg_lambda": 1.0,
        "objective": "binary",
        "verbose": -1,
        "random_state": 42,
    }

    def __init__(self, params: Optional[Dict[str, Any]] = None):
        super().__init__(params)
        if not HAS_LIGHTGBM:
            raise ImportError(
                "LightGBM is not installed. Install it with: pip install lightgbm"
            )
        from lightgbm import LGBMClassifier

        merged = {**self.DEFAULT_PARAMS, **(self.params or {})}
        self.model = LGBMClassifier(**merged)

    # ---- BaseMLModel interface --------------------------------------------

    def train(
        self,
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: Optional[np.ndarray] = None,
        y_val: Optional[np.ndarray] = None,
    ) -> Dict[str, float]:
        from sklearn.metrics import accuracy_score, roc_auc_score

        logger.info(
            "LightGBM training: %d samples, %d features",
            X_train.shape[0], X_train.shape[1],
        )

        # Auto-balance classes via scale_pos_weight
        n_pos = int(np.sum(y_train == 1))
        n_neg = int(np.sum(y_train == 0))
        if n_pos > 0 and n_neg > 0:
            spw = n_neg / n_pos
            self.model.set_params(scale_pos_weight=spw)
            logger.info("LightGBM scale_pos_weight=%.3f (%d neg / %d pos)", spw, n_neg, n_pos)

        fit_kwargs: Dict[str, Any] = {}
        if X_val is not None and y_val is not None:
            fit_kwargs["eval_set"] = [(X_val, y_val)]
            fit_kwargs["eval_metric"] = "logloss"
            fit_kwargs["callbacks"] = [lightgbm.early_stopping(20, verbose=False)]

        self.model.fit(X_train, y_train, **fit_kwargs)
        self.is_trained = True

        metrics: Dict[str, float] = {}
        train_pred = self.model.predict(X_train)
        train_proba = self.model.predict_proba(X_train)[:, 1]
        metrics["train_accuracy"] = float(accuracy_score(y_train, train_pred))
        if len(np.unique(y_train)) > 1:
            metrics["train_auc"] = float(roc_auc_score(y_train, train_proba))

        if X_val is not None and y_val is not None:
            val_pred = self.model.predict(X_val)
            val_proba = self.model.predict_proba(X_val)[:, 1]
            metrics["val_accuracy"] = float(accuracy_score(y_val, val_pred))
            if len(np.unique(y_val)) > 1:
                metrics["val_auc"] = float(roc_auc_score(y_val, val_proba))

        logger.info("LightGBM training complete: %s", metrics)
        return metrics

    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        proba = self.model.predict_proba(X)
        return proba[:, 1]

    def save(self, path: str) -> None:
        import joblib

        os.makedirs(os.path.dirname(path), exist_ok=True)
        joblib.dump(self.model, path)
        logger.info("LightGBM model saved to %s", path)

    def load(self, path: str) -> None:
        import joblib

        self.model = joblib.load(path)
        self.is_trained = True
        logger.info("LightGBM model loaded from %s", path)

    def get_feature_importance(self) -> Optional[Dict[str, float]]:
        if not self.is_trained:
            return None
        importances = self.model.feature_importances_
        names = self.feature_names or [f"feature_{i}" for i in range(len(importances))]
        return {
            name: round(float(imp), 6)
            for name, imp in sorted(
                zip(names, importances), key=lambda x: x[1], reverse=True
            )
        }


# ===========================================================================
# LSTM Model (PyTorch)
# ===========================================================================

class LSTMModel(BaseMLModel):
    """
    LSTM-based binary classifier for trade win prediction.

    Converts flat feature rows into sequences of length *sequence_length*
    (sliding window over the time-ordered samples) before feeding them
    through the LSTM.  Because of this, the output of predict_proba will
    have ``n_samples - sequence_length + 1`` rows.

    Requires PyTorch (``pip install torch``).
    """

    DEFAULT_PARAMS = {
        "hidden_size": 64,
        "num_layers": 2,
        "dropout": 0.2,
        "fc_dropout": 0.3,
        "sequence_length": 10,
        "epochs": 50,
        "batch_size": 32,
        "learning_rate": 1e-3,
    }

    def __init__(self, params: Optional[Dict[str, Any]] = None):
        super().__init__(params)
        if not HAS_TORCH:
            raise ImportError(
                "PyTorch is not installed. Install it with: pip install torch"
            )
        merged = {**self.DEFAULT_PARAMS, **(self.params or {})}
        self.hidden_size: int = merged["hidden_size"]
        self.num_layers: int = merged["num_layers"]
        self.dropout: float = merged["dropout"]
        self.fc_dropout: float = merged["fc_dropout"]
        self.sequence_length: int = merged["sequence_length"]
        self.epochs: int = merged["epochs"]
        self.batch_size: int = merged["batch_size"]
        self.lr: float = merged["learning_rate"]
        self._net = None  # Built lazily in train / load
        self._input_size: Optional[int] = None

    # ---- PyTorch network --------------------------------------------------

    def _build_network(self, input_size: int):
        """Construct the LSTM network."""
        import torch
        import torch.nn as nn

        class _LSTMNet(nn.Module):
            def __init__(self, input_size, hidden_size, num_layers, dropout, fc_dropout):
                super().__init__()
                self.lstm = nn.LSTM(
                    input_size=input_size,
                    hidden_size=hidden_size,
                    num_layers=num_layers,
                    dropout=dropout if num_layers > 1 else 0.0,
                    batch_first=True,
                )
                self.fc1 = nn.Linear(hidden_size, 32)
                self.relu = nn.ReLU()
                self.drop = nn.Dropout(fc_dropout)
                self.fc2 = nn.Linear(32, 1)
                self.sigmoid = nn.Sigmoid()

            def forward(self, x):
                # x: (batch, seq_len, input_size)
                lstm_out, _ = self.lstm(x)
                # Take the last time-step output
                last = lstm_out[:, -1, :]
                out = self.fc1(last)
                out = self.relu(out)
                out = self.drop(out)
                out = self.fc2(out)
                out = self.sigmoid(out)
                return out.squeeze(-1)

        self._input_size = input_size
        self._net = _LSTMNet(
            input_size, self.hidden_size, self.num_layers,
            self.dropout, self.fc_dropout,
        )

    # ---- Sequence helpers -------------------------------------------------

    @staticmethod
    def _create_sequences(
        X: np.ndarray, y: Optional[np.ndarray], seq_len: int
    ) -> Tuple[np.ndarray, Optional[np.ndarray]]:
        """
        Convert a 2-D feature matrix into overlapping sequences.

        Args:
            X: (n_samples, n_features)
            y: (n_samples,) or None
            seq_len: window length

        Returns:
            X_seq: (n_samples - seq_len + 1, seq_len, n_features)
            y_seq: labels aligned to the *last* element of each window, or None
        """
        n = X.shape[0]
        if n < seq_len:
            raise ValueError(
                f"Not enough samples ({n}) for sequence_length={seq_len}"
            )
        seqs = np.lib.stride_tricks.sliding_window_view(X, (seq_len, X.shape[1]))
        # sliding_window_view gives shape (n - seq_len + 1, 1, seq_len, n_features)
        seqs = seqs.squeeze(axis=1)  # (n - seq_len + 1, seq_len, n_features)
        y_seq = y[seq_len - 1:] if y is not None else None
        return seqs, y_seq

    # ---- BaseMLModel interface --------------------------------------------

    def train(
        self,
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: Optional[np.ndarray] = None,
        y_val: Optional[np.ndarray] = None,
    ) -> Dict[str, float]:
        import torch
        import torch.nn as nn
        from torch.utils.data import TensorDataset, DataLoader

        logger.info(
            "LSTM training: %d samples, %d features, seq_len=%d",
            X_train.shape[0], X_train.shape[1], self.sequence_length,
        )

        # Build sequences
        X_seq, y_seq = self._create_sequences(X_train, y_train, self.sequence_length)

        # Build network
        input_size = X_train.shape[1]
        self._build_network(input_size)

        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self._net.to(device)

        X_t = torch.tensor(X_seq, dtype=torch.float32).to(device)
        y_t = torch.tensor(y_seq, dtype=torch.float32).to(device)

        dataset = TensorDataset(X_t, y_t)
        # shuffle=False because this is time-series data
        loader = DataLoader(dataset, batch_size=self.batch_size, shuffle=False)

        criterion = nn.BCELoss()
        optimizer = torch.optim.Adam(self._net.parameters(), lr=self.lr)

        # Validation sequences (if provided)
        val_X_t, val_y_t = None, None
        if X_val is not None and y_val is not None:
            X_val_seq, y_val_seq = self._create_sequences(X_val, y_val, self.sequence_length)
            val_X_t = torch.tensor(X_val_seq, dtype=torch.float32).to(device)
            val_y_t = torch.tensor(y_val_seq, dtype=torch.float32).to(device)

        # Training loop
        self._net.train()
        best_val_loss = float("inf")
        metrics: Dict[str, float] = {}

        for epoch in range(self.epochs):
            epoch_loss = 0.0
            n_batches = 0
            for xb, yb in loader:
                optimizer.zero_grad()
                preds = self._net(xb)
                loss = criterion(preds, yb)
                loss.backward()
                optimizer.step()
                epoch_loss += loss.item()
                n_batches += 1

            avg_loss = epoch_loss / max(n_batches, 1)

            if (epoch + 1) % 10 == 0 or epoch == 0:
                msg = f"  Epoch {epoch + 1}/{self.epochs} train_loss={avg_loss:.4f}"
                if val_X_t is not None:
                    self._net.eval()
                    with torch.no_grad():
                        val_preds = self._net(val_X_t)
                        val_loss = criterion(val_preds, val_y_t).item()
                    self._net.train()
                    msg += f"  val_loss={val_loss:.4f}"
                    if val_loss < best_val_loss:
                        best_val_loss = val_loss
                logger.info(msg)

        # Final metrics
        self._net.eval()
        with torch.no_grad():
            train_preds = self._net(X_t).cpu().numpy()
        train_acc = float(np.mean((train_preds >= 0.5).astype(int) == y_seq))
        metrics["train_accuracy"] = train_acc
        metrics["train_loss"] = avg_loss

        if val_X_t is not None:
            with torch.no_grad():
                val_preds_np = self._net(val_X_t).cpu().numpy()
                val_loss_final = criterion(
                    torch.tensor(val_preds_np), val_y_t.cpu()
                ).item()
            val_acc = float(np.mean((val_preds_np >= 0.5).astype(int) == y_val_seq))
            metrics["val_accuracy"] = val_acc
            metrics["val_loss"] = val_loss_final

        self.is_trained = True
        logger.info("LSTM training complete: %s", metrics)
        return metrics

    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        import torch

        if self._net is None:
            raise RuntimeError("Model is not trained or loaded.")

        X_seq, _ = self._create_sequences(X, None, self.sequence_length)
        device = next(self._net.parameters()).device
        X_t = torch.tensor(X_seq, dtype=torch.float32).to(device)

        self._net.eval()
        with torch.no_grad():
            proba = self._net(X_t).cpu().numpy()

        return proba

    def save(self, path: str) -> None:
        import torch
        import json

        os.makedirs(os.path.dirname(path), exist_ok=True)
        torch.save(self._net.state_dict(), path)

        # Save architecture params alongside weights so we can reconstruct
        meta_path = path + ".meta.json"
        meta = {
            "input_size": self._input_size,
            "hidden_size": self.hidden_size,
            "num_layers": self.num_layers,
            "dropout": self.dropout,
            "fc_dropout": self.fc_dropout,
            "sequence_length": self.sequence_length,
        }
        with open(meta_path, "w") as f:
            json.dump(meta, f, indent=2)

        logger.info("LSTM model saved to %s", path)

    def load(self, path: str) -> None:
        import torch
        import json

        meta_path = path + ".meta.json"
        with open(meta_path, "r") as f:
            meta = json.load(f)

        self._input_size = meta["input_size"]
        self.hidden_size = meta["hidden_size"]
        self.num_layers = meta["num_layers"]
        self.dropout = meta["dropout"]
        self.fc_dropout = meta["fc_dropout"]
        self.sequence_length = meta["sequence_length"]

        self._build_network(self._input_size)
        self._net.load_state_dict(
            torch.load(path, map_location=torch.device("cpu"), weights_only=True)
        )
        self._net.eval()
        self.is_trained = True
        logger.info("LSTM model loaded from %s", path)

    def get_feature_importance(self) -> Optional[Dict[str, float]]:
        # LSTM has no native feature importance
        return None


# ===========================================================================
# 1D-CNN Model (PyTorch)
# ===========================================================================

class CNNModel(BaseMLModel):
    """
    1D Convolutional Neural Network for trade win prediction.

    Similar to LSTM, it converts flat features into sequences before
    passing them through 1D convolution layers.

    Requires PyTorch (``pip install torch``).
    """

    DEFAULT_PARAMS = {
        "sequence_length": 10,
        "epochs": 50,
        "batch_size": 32,
        "learning_rate": 1e-3,
        "fc_dropout": 0.3,
    }

    def __init__(self, params: Optional[Dict[str, Any]] = None):
        super().__init__(params)
        if not HAS_TORCH:
            raise ImportError(
                "PyTorch is not installed. Install it with: pip install torch"
            )
        merged = {**self.DEFAULT_PARAMS, **(self.params or {})}
        self.sequence_length: int = merged["sequence_length"]
        self.epochs: int = merged["epochs"]
        self.batch_size: int = merged["batch_size"]
        self.lr: float = merged["learning_rate"]
        self.fc_dropout: float = merged["fc_dropout"]
        self._net = None
        self._input_size: Optional[int] = None

    # ---- PyTorch network --------------------------------------------------

    def _build_network(self, input_size: int):
        import torch.nn as nn

        class _CNN1DNet(nn.Module):
            def __init__(self, input_channels, fc_dropout):
                super().__init__()
                self.conv1 = nn.Conv1d(input_channels, 32, kernel_size=3, padding=1)
                self.relu1 = nn.ReLU()
                self.conv2 = nn.Conv1d(32, 64, kernel_size=3, padding=1)
                self.relu2 = nn.ReLU()
                self.pool = nn.AdaptiveAvgPool1d(1)
                self.fc1 = nn.Linear(64, 32)
                self.relu3 = nn.ReLU()
                self.drop = nn.Dropout(fc_dropout)
                self.fc2 = nn.Linear(32, 1)
                self.sigmoid = nn.Sigmoid()

            def forward(self, x):
                # x: (batch, channels=n_features, seq_len)
                out = self.relu1(self.conv1(x))
                out = self.relu2(self.conv2(out))
                out = self.pool(out)            # (batch, 64, 1)
                out = out.squeeze(-1)           # (batch, 64)
                out = self.fc1(out)
                out = self.relu3(out)
                out = self.drop(out)
                out = self.fc2(out)
                out = self.sigmoid(out)
                return out.squeeze(-1)

        self._input_size = input_size
        self._net = _CNN1DNet(input_size, self.fc_dropout)

    # ---- Sequence helper (shared with LSTM) --------------------------------

    @staticmethod
    def _create_sequences(
        X: np.ndarray, y: Optional[np.ndarray], seq_len: int
    ) -> Tuple[np.ndarray, Optional[np.ndarray]]:
        """Same sliding-window approach as LSTMModel."""
        n = X.shape[0]
        if n < seq_len:
            raise ValueError(
                f"Not enough samples ({n}) for sequence_length={seq_len}"
            )
        seqs = np.lib.stride_tricks.sliding_window_view(X, (seq_len, X.shape[1]))
        seqs = seqs.squeeze(axis=1)  # (n - seq_len + 1, seq_len, n_features)
        y_seq = y[seq_len - 1:] if y is not None else None
        return seqs, y_seq

    # ---- BaseMLModel interface --------------------------------------------

    def train(
        self,
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: Optional[np.ndarray] = None,
        y_val: Optional[np.ndarray] = None,
    ) -> Dict[str, float]:
        import torch
        import torch.nn as nn
        from torch.utils.data import TensorDataset, DataLoader

        logger.info(
            "CNN training: %d samples, %d features, seq_len=%d",
            X_train.shape[0], X_train.shape[1], self.sequence_length,
        )

        X_seq, y_seq = self._create_sequences(X_train, y_train, self.sequence_length)

        input_size = X_train.shape[1]
        self._build_network(input_size)

        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self._net.to(device)

        # Conv1d expects (batch, channels, length) => transpose features and seq
        X_t = torch.tensor(X_seq, dtype=torch.float32).permute(0, 2, 1).to(device)
        y_t = torch.tensor(y_seq, dtype=torch.float32).to(device)

        dataset = TensorDataset(X_t, y_t)
        loader = DataLoader(dataset, batch_size=self.batch_size, shuffle=False)

        criterion = nn.BCELoss()
        optimizer = torch.optim.Adam(self._net.parameters(), lr=self.lr)

        val_X_t, val_y_t, y_val_seq = None, None, None
        if X_val is not None and y_val is not None:
            X_val_seq, y_val_seq = self._create_sequences(X_val, y_val, self.sequence_length)
            val_X_t = torch.tensor(X_val_seq, dtype=torch.float32).permute(0, 2, 1).to(device)
            val_y_t = torch.tensor(y_val_seq, dtype=torch.float32).to(device)

        self._net.train()
        best_val_loss = float("inf")
        metrics: Dict[str, float] = {}
        avg_loss = 0.0

        for epoch in range(self.epochs):
            epoch_loss = 0.0
            n_batches = 0
            for xb, yb in loader:
                optimizer.zero_grad()
                preds = self._net(xb)
                loss = criterion(preds, yb)
                loss.backward()
                optimizer.step()
                epoch_loss += loss.item()
                n_batches += 1

            avg_loss = epoch_loss / max(n_batches, 1)

            if (epoch + 1) % 10 == 0 or epoch == 0:
                msg = f"  Epoch {epoch + 1}/{self.epochs} train_loss={avg_loss:.4f}"
                if val_X_t is not None:
                    self._net.eval()
                    with torch.no_grad():
                        vp = self._net(val_X_t)
                        vl = criterion(vp, val_y_t).item()
                    self._net.train()
                    msg += f"  val_loss={vl:.4f}"
                    if vl < best_val_loss:
                        best_val_loss = vl
                logger.info(msg)

        self._net.eval()
        with torch.no_grad():
            train_preds = self._net(X_t).cpu().numpy()
        train_acc = float(np.mean((train_preds >= 0.5).astype(int) == y_seq))
        metrics["train_accuracy"] = train_acc
        metrics["train_loss"] = avg_loss

        if val_X_t is not None:
            with torch.no_grad():
                val_preds_np = self._net(val_X_t).cpu().numpy()
                val_loss_final = criterion(
                    torch.tensor(val_preds_np), val_y_t.cpu()
                ).item()
            val_acc = float(np.mean((val_preds_np >= 0.5).astype(int) == y_val_seq))
            metrics["val_accuracy"] = val_acc
            metrics["val_loss"] = val_loss_final

        self.is_trained = True
        logger.info("CNN training complete: %s", metrics)
        return metrics

    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        import torch

        if self._net is None:
            raise RuntimeError("Model is not trained or loaded.")

        X_seq, _ = self._create_sequences(X, None, self.sequence_length)

        device = next(self._net.parameters()).device
        # (batch, n_features, seq_len)
        X_t = torch.tensor(X_seq, dtype=torch.float32).permute(0, 2, 1).to(device)

        self._net.eval()
        with torch.no_grad():
            proba = self._net(X_t).cpu().numpy()

        return proba

    def save(self, path: str) -> None:
        import torch
        import json

        os.makedirs(os.path.dirname(path), exist_ok=True)
        torch.save(self._net.state_dict(), path)

        meta_path = path + ".meta.json"
        meta = {
            "input_size": self._input_size,
            "sequence_length": self.sequence_length,
            "fc_dropout": self.fc_dropout,
        }
        with open(meta_path, "w") as f:
            json.dump(meta, f, indent=2)

        logger.info("CNN model saved to %s", path)

    def load(self, path: str) -> None:
        import torch
        import json

        meta_path = path + ".meta.json"
        with open(meta_path, "r") as f:
            meta = json.load(f)

        self._input_size = meta["input_size"]
        self.sequence_length = meta["sequence_length"]
        self.fc_dropout = meta.get("fc_dropout", 0.3)

        self._build_network(self._input_size)
        self._net.load_state_dict(
            torch.load(path, map_location=torch.device("cpu"), weights_only=True)
        )
        self._net.eval()
        self.is_trained = True
        logger.info("CNN model loaded from %s", path)

    def get_feature_importance(self) -> Optional[Dict[str, float]]:
        # CNN has no native feature importance
        return None


# ===========================================================================
# Transformer Model (PyTorch)
# ===========================================================================

class TransformerModel(BaseMLModel):
    """
    Transformer-based binary classifier for trade win prediction.

    Uses a small TransformerEncoder with learnable positional embeddings.
    Converts flat feature rows into sequences (same sliding-window approach
    as LSTM/CNN) before feeding them through the encoder.

    Requires PyTorch (``pip install torch``).
    """

    DEFAULT_PARAMS = {
        "d_model": 64,
        "nhead": 4,
        "num_layers": 2,
        "dim_feedforward": 256,
        "dropout": 0.1,
        "sequence_length": 10,
        "epochs": 50,
        "batch_size": 32,
        "learning_rate": 1e-3,
    }

    def __init__(self, params: Optional[Dict[str, Any]] = None):
        super().__init__(params)
        if not HAS_TORCH:
            raise ImportError(
                "PyTorch is not installed. Install it with: pip install torch"
            )
        merged = {**self.DEFAULT_PARAMS, **(self.params or {})}
        self.d_model: int = merged["d_model"]
        self.nhead: int = merged["nhead"]
        self.num_layers: int = merged["num_layers"]
        self.dim_feedforward: int = merged["dim_feedforward"]
        self.dropout: float = merged["dropout"]
        self.sequence_length: int = merged["sequence_length"]
        self.epochs: int = merged["epochs"]
        self.batch_size: int = merged["batch_size"]
        self.lr: float = merged["learning_rate"]
        self._net = None
        self._input_size: Optional[int] = None

    # ---- PyTorch network --------------------------------------------------

    def _build_network(self, input_size: int):
        """Construct the Transformer network."""
        import torch
        import torch.nn as nn

        d_model = self.d_model
        nhead = self.nhead
        num_layers = self.num_layers
        dim_feedforward = self.dim_feedforward
        dropout = self.dropout
        seq_len = self.sequence_length

        class _TransformerNet(nn.Module):
            def __init__(self):
                super().__init__()
                # Linear projection from feature dim to d_model
                self.input_proj = nn.Linear(input_size, d_model)
                # Learnable positional embedding
                self.pos_embedding = nn.Embedding(seq_len, d_model)
                # Transformer encoder
                encoder_layer = nn.TransformerEncoderLayer(
                    d_model=d_model,
                    nhead=nhead,
                    dim_feedforward=dim_feedforward,
                    dropout=dropout,
                    batch_first=True,
                )
                self.transformer_encoder = nn.TransformerEncoder(
                    encoder_layer, num_layers=num_layers
                )
                # Output head
                self.fc = nn.Linear(d_model, 1)
                self.sigmoid = nn.Sigmoid()

            def forward(self, x):
                # x: (batch, seq_len, input_size)
                batch_size, seq_length, _ = x.shape
                # Project to d_model
                x = self.input_proj(x)  # (batch, seq_len, d_model)
                # Add positional embedding
                positions = torch.arange(seq_length, device=x.device).unsqueeze(0)
                x = x + self.pos_embedding(positions)
                # Transformer encoder
                x = self.transformer_encoder(x)  # (batch, seq_len, d_model)
                # Take last timestep
                last = x[:, -1, :]  # (batch, d_model)
                out = self.fc(last)
                out = self.sigmoid(out)
                return out.squeeze(-1)

        self._input_size = input_size
        self._net = _TransformerNet()

    # ---- BaseMLModel interface --------------------------------------------

    def train(
        self,
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: Optional[np.ndarray] = None,
        y_val: Optional[np.ndarray] = None,
    ) -> Dict[str, float]:
        import torch
        import torch.nn as nn
        from torch.utils.data import TensorDataset, DataLoader

        logger.info(
            "Transformer training: %d samples, %d features, seq_len=%d",
            X_train.shape[0], X_train.shape[1], self.sequence_length,
        )

        # Build sequences (reuse LSTM's static method)
        X_seq, y_seq = LSTMModel._create_sequences(X_train, y_train, self.sequence_length)

        # Build network
        input_size = X_train.shape[1]
        self._build_network(input_size)

        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self._net.to(device)

        X_t = torch.tensor(X_seq, dtype=torch.float32).to(device)
        y_t = torch.tensor(y_seq, dtype=torch.float32).to(device)

        dataset = TensorDataset(X_t, y_t)
        loader = DataLoader(dataset, batch_size=self.batch_size, shuffle=False)

        criterion = nn.BCELoss()
        optimizer = torch.optim.Adam(self._net.parameters(), lr=self.lr)

        # Validation sequences
        val_X_t, val_y_t, y_val_seq = None, None, None
        if X_val is not None and y_val is not None:
            X_val_seq, y_val_seq = LSTMModel._create_sequences(X_val, y_val, self.sequence_length)
            val_X_t = torch.tensor(X_val_seq, dtype=torch.float32).to(device)
            val_y_t = torch.tensor(y_val_seq, dtype=torch.float32).to(device)

        # Training loop
        self._net.train()
        best_val_loss = float("inf")
        metrics: Dict[str, float] = {}
        avg_loss = 0.0

        for epoch in range(self.epochs):
            epoch_loss = 0.0
            n_batches = 0
            for xb, yb in loader:
                optimizer.zero_grad()
                preds = self._net(xb)
                loss = criterion(preds, yb)
                loss.backward()
                optimizer.step()
                epoch_loss += loss.item()
                n_batches += 1

            avg_loss = epoch_loss / max(n_batches, 1)

            if (epoch + 1) % 10 == 0 or epoch == 0:
                msg = f"  Epoch {epoch + 1}/{self.epochs} train_loss={avg_loss:.4f}"
                if val_X_t is not None:
                    self._net.eval()
                    with torch.no_grad():
                        val_preds = self._net(val_X_t)
                        val_loss = criterion(val_preds, val_y_t).item()
                    self._net.train()
                    msg += f"  val_loss={val_loss:.4f}"
                    if val_loss < best_val_loss:
                        best_val_loss = val_loss
                logger.info(msg)

        # Final metrics
        self._net.eval()
        with torch.no_grad():
            train_preds = self._net(X_t).cpu().numpy()
        train_acc = float(np.mean((train_preds >= 0.5).astype(int) == y_seq))
        metrics["train_accuracy"] = train_acc
        metrics["train_loss"] = avg_loss

        if val_X_t is not None:
            with torch.no_grad():
                val_preds_np = self._net(val_X_t).cpu().numpy()
                val_loss_final = criterion(
                    torch.tensor(val_preds_np), val_y_t.cpu()
                ).item()
            val_acc = float(np.mean((val_preds_np >= 0.5).astype(int) == y_val_seq))
            metrics["val_accuracy"] = val_acc
            metrics["val_loss"] = val_loss_final

        self.is_trained = True
        logger.info("Transformer training complete: %s", metrics)
        return metrics

    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        import torch

        if self._net is None:
            raise RuntimeError("Model is not trained or loaded.")

        X_seq, _ = LSTMModel._create_sequences(X, None, self.sequence_length)
        device = next(self._net.parameters()).device
        X_t = torch.tensor(X_seq, dtype=torch.float32).to(device)

        self._net.eval()
        with torch.no_grad():
            proba = self._net(X_t).cpu().numpy()

        return proba

    def save(self, path: str) -> None:
        import torch
        import json

        os.makedirs(os.path.dirname(path), exist_ok=True)
        torch.save(self._net.state_dict(), path)

        meta_path = path + ".meta.json"
        meta = {
            "input_size": self._input_size,
            "d_model": self.d_model,
            "nhead": self.nhead,
            "num_layers": self.num_layers,
            "dim_feedforward": self.dim_feedforward,
            "dropout": self.dropout,
            "sequence_length": self.sequence_length,
        }
        with open(meta_path, "w") as f:
            json.dump(meta, f, indent=2)

        logger.info("Transformer model saved to %s", path)

    def load(self, path: str) -> None:
        import torch
        import json

        meta_path = path + ".meta.json"
        with open(meta_path, "r") as f:
            meta = json.load(f)

        self._input_size = meta["input_size"]
        self.d_model = meta["d_model"]
        self.nhead = meta["nhead"]
        self.num_layers = meta["num_layers"]
        self.dim_feedforward = meta["dim_feedforward"]
        self.dropout = meta["dropout"]
        self.sequence_length = meta["sequence_length"]

        self._build_network(self._input_size)
        self._net.load_state_dict(
            torch.load(path, map_location=torch.device("cpu"), weights_only=True)
        )
        self._net.eval()
        self.is_trained = True
        logger.info("Transformer model loaded from %s", path)

    def get_feature_importance(self) -> Optional[Dict[str, float]]:
        # Transformer has no native feature importance
        return None


# ===========================================================================
# Ensemble Model (Stacking)
# ===========================================================================

class EnsembleModel(BaseMLModel):
    """
    Stacking ensemble: XGBoost + LightGBM (if available) as base learners
    with a LogisticRegression meta-learner.

    Falls back to XGBoost-only if LightGBM is not installed.
    """

    def __init__(self, params: Optional[Dict[str, Any]] = None):
        super().__init__(params)
        self.base_models: List[BaseMLModel] = []
        self.meta_learner = None
        self._base_model_names: List[str] = []

    def _init_base_models(self) -> None:
        """Initialise the base learner list."""
        xgb_params = self.params.get("xgboost", {})
        self.base_models.append(XGBoostModel(xgb_params))
        self._base_model_names.append("xgboost")

        if HAS_LIGHTGBM:
            lgb_params = self.params.get("lightgbm", {})
            self.base_models.append(LightGBMModel(lgb_params))
            self._base_model_names.append("lightgbm")
            logger.info("Ensemble: using XGBoost + LightGBM base learners")
        else:
            logger.warning(
                "Ensemble: LightGBM not installed. Using XGBoost-only base learner."
            )

    # ---- helpers -----------------------------------------------------------

    def _get_base_predictions(self, X: np.ndarray) -> np.ndarray:
        """Stack base-model probabilities into (n_samples, n_base_models)."""
        preds = [m.predict_proba(X).reshape(-1, 1) for m in self.base_models]
        return np.hstack(preds)

    # ---- BaseMLModel interface --------------------------------------------

    def train(
        self,
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: Optional[np.ndarray] = None,
        y_val: Optional[np.ndarray] = None,
    ) -> Dict[str, float]:
        from sklearn.linear_model import LogisticRegression
        from sklearn.metrics import accuracy_score, roc_auc_score

        self._init_base_models()

        logger.info(
            "Ensemble training: %d samples, %d features, %d base models",
            X_train.shape[0], X_train.shape[1], len(self.base_models),
        )

        # 1. Train each base model
        all_metrics: Dict[str, float] = {}
        for name, model in zip(self._base_model_names, self.base_models):
            model.feature_names = self.feature_names
            m = model.train(X_train, y_train, X_val, y_val)
            for k, v in m.items():
                all_metrics[f"{name}_{k}"] = v

        # 2. Get stacked predictions from base models
        stacked_train = self._get_base_predictions(X_train)

        # 3. Train meta-learner
        self.meta_learner = LogisticRegression(
            max_iter=1000, random_state=42, solver="lbfgs"
        )
        self.meta_learner.fit(stacked_train, y_train)
        self.is_trained = True

        # 4. Compute ensemble metrics
        train_proba = self.meta_learner.predict_proba(stacked_train)[:, 1]
        train_pred = (train_proba >= 0.5).astype(int)
        all_metrics["ensemble_train_accuracy"] = float(
            accuracy_score(y_train, train_pred)
        )
        if len(np.unique(y_train)) > 1:
            all_metrics["ensemble_train_auc"] = float(
                roc_auc_score(y_train, train_proba)
            )

        if X_val is not None and y_val is not None:
            stacked_val = self._get_base_predictions(X_val)
            val_proba = self.meta_learner.predict_proba(stacked_val)[:, 1]
            val_pred = (val_proba >= 0.5).astype(int)
            all_metrics["ensemble_val_accuracy"] = float(
                accuracy_score(y_val, val_pred)
            )
            if len(np.unique(y_val)) > 1:
                all_metrics["ensemble_val_auc"] = float(
                    roc_auc_score(y_val, val_proba)
                )

        logger.info("Ensemble training complete: %s", all_metrics)
        return all_metrics

    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        if self.meta_learner is None:
            raise RuntimeError("Model is not trained or loaded.")
        stacked = self._get_base_predictions(X)
        return self.meta_learner.predict_proba(stacked)[:, 1]

    def save(self, path: str) -> None:
        import joblib
        import json

        # Create a directory for all ensemble parts
        ensemble_dir = path + ".ensemble"
        os.makedirs(ensemble_dir, exist_ok=True)

        # Save each base model
        for name, model in zip(self._base_model_names, self.base_models):
            model.save(os.path.join(ensemble_dir, f"base_{name}.joblib"))

        # Save meta-learner
        joblib.dump(
            self.meta_learner,
            os.path.join(ensemble_dir, "meta_learner.joblib"),
        )

        # Save manifest
        manifest = {
            "base_model_names": self._base_model_names,
        }
        with open(os.path.join(ensemble_dir, "manifest.json"), "w") as f:
            json.dump(manifest, f, indent=2)

        logger.info("Ensemble model saved to %s", ensemble_dir)

    def load(self, path: str) -> None:
        import joblib
        import json

        ensemble_dir = path + ".ensemble"
        with open(os.path.join(ensemble_dir, "manifest.json"), "r") as f:
            manifest = json.load(f)

        self._base_model_names = manifest["base_model_names"]
        self.base_models = []

        for name in self._base_model_names:
            if name == "xgboost":
                model = XGBoostModel()
            elif name == "lightgbm":
                if not HAS_LIGHTGBM:
                    logger.warning(
                        "Ensemble was trained with LightGBM but it is not installed. "
                        "Skipping LightGBM base model -- predictions may differ."
                    )
                    continue
                model = LightGBMModel()
            else:
                raise ValueError(f"Unknown base model type: {name}")
            model.load(os.path.join(ensemble_dir, f"base_{name}.joblib"))
            self.base_models.append(model)

        self.meta_learner = joblib.load(
            os.path.join(ensemble_dir, "meta_learner.joblib")
        )
        self.is_trained = True
        logger.info("Ensemble model loaded from %s", ensemble_dir)

    def get_feature_importance(self) -> Optional[Dict[str, float]]:
        """Average feature importances across base models that support it."""
        all_importances: List[Dict[str, float]] = []
        for model in self.base_models:
            imp = model.get_feature_importance()
            if imp is not None:
                all_importances.append(imp)

        if not all_importances:
            return None

        # Collect all feature names
        all_keys = set()
        for imp in all_importances:
            all_keys.update(imp.keys())

        averaged = {}
        for key in all_keys:
            vals = [imp.get(key, 0.0) for imp in all_importances]
            averaged[key] = round(float(np.mean(vals)), 6)

        # Sort descending by importance
        return dict(
            sorted(averaged.items(), key=lambda x: x[1], reverse=True)
        )


# ===========================================================================
# Factory
# ===========================================================================

MODEL_TYPES: Dict[str, type] = {
    "xgboost": XGBoostModel,
    "lightgbm": LightGBMModel,
    "lstm": LSTMModel,
    "cnn": CNNModel,
    "transformer": TransformerModel,
    "ensemble": EnsembleModel,
}


def create_ml_model(
    model_type: str, params: Optional[Dict[str, Any]] = None
) -> BaseMLModel:
    """
    Create an ML model instance by type name.

    Args:
        model_type: One of "xgboost", "lightgbm", "lstm", "cnn", "transformer", "ensemble"
        params: Optional dict of model-specific hyper-parameters

    Returns:
        A BaseMLModel subclass instance, ready for training

    Raises:
        ValueError: If *model_type* is not recognised
        ImportError: If the required library for *model_type* is not installed
    """
    cls = MODEL_TYPES.get(model_type)
    if cls is None:
        available = ", ".join(sorted(MODEL_TYPES.keys()))
        raise ValueError(
            f"Unknown model type '{model_type}'. Available types: {available}"
        )
    return cls(params)
