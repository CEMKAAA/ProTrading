"""
Hyperparameter Optimization for ML Models using Optuna

Automatically tunes XGBoost and LightGBM hyperparameters to maximize
out-of-sample ROC AUC score for trade win/loss classification.

Usage:
    from dashboard.backend.core.ml_hpo import optimize_model

    best_params = optimize_model(
        model_type="xgboost",
        X_train=X_train, y_train=y_train,
        X_val=X_val, y_val=y_val,
        n_trials=30,
        progress_callback=lambda trial, total, score: print(f"{trial}/{total} best={score:.4f}")
    )
"""

import logging
from typing import Dict, Optional, Callable

logger = logging.getLogger(__name__)


def optimize_xgboost(
    X_train,
    y_train,
    X_val,
    y_val,
    n_trials: int = 30,
    progress_callback: Optional[Callable[[int, int, float], None]] = None,
) -> Dict:
    """
    Use Optuna to find optimal XGBoost hyperparameters.

    Searches over tree depth, learning rate, regularization, and sampling
    parameters. Objective is to maximize ROC AUC on the validation set.

    Args:
        X_train: Training feature matrix (numpy array or pandas DataFrame)
        y_train: Training binary labels (1=win, 0=loss)
        X_val: Validation feature matrix
        y_val: Validation binary labels
        n_trials: Number of Optuna trials to run (default 30)
        progress_callback: Optional callback(trial_number, total_trials, best_score)

    Returns:
        Dict of best hyperparameters, or empty dict if optimization fails.
    """
    try:
        import optuna
    except ImportError:
        logger.warning(
            "optuna is not installed. Install it with: pip install optuna. "
            "Returning empty params (default hyperparameters will be used)."
        )
        return {}

    try:
        from xgboost import XGBClassifier
    except ImportError:
        logger.warning(
            "xgboost is not installed. Install it with: pip install xgboost. "
            "Cannot run XGBoost HPO."
        )
        return {}

    try:
        from sklearn.metrics import roc_auc_score
    except ImportError:
        logger.warning("scikit-learn is not installed. Cannot compute ROC AUC.")
        return {}

    # Suppress Optuna's verbose trial logging
    optuna.logging.set_verbosity(optuna.logging.WARNING)

    best_score_so_far = [0.0]

    def objective(trial: optuna.Trial) -> float:
        """Single Optuna trial: train XGBoost with sampled params, return val AUC."""
        try:
            params = {
                "n_estimators": trial.suggest_int("n_estimators", 50, 300),
                "max_depth": trial.suggest_int("max_depth", 2, 6),
                "learning_rate": trial.suggest_float("learning_rate", 0.01, 0.2, log=True),
                "subsample": trial.suggest_float("subsample", 0.6, 1.0),
                "colsample_bytree": trial.suggest_float("colsample_bytree", 0.6, 1.0),
                "min_child_weight": trial.suggest_int("min_child_weight", 1, 10),
                "reg_alpha": trial.suggest_float("reg_alpha", 0.001, 1.0, log=True),
                "reg_lambda": trial.suggest_float("reg_lambda", 0.1, 5.0),
                "eval_metric": "logloss",
                "random_state": 42,
                "verbosity": 0,
            }

            model = XGBClassifier(**params)
            model.fit(X_train, y_train)

            y_proba = model.predict_proba(X_val)[:, 1]
            auc = roc_auc_score(y_val, y_proba)

            # Track best score for callback
            if auc > best_score_so_far[0]:
                best_score_so_far[0] = auc

            # Progress callback
            if progress_callback:
                progress_callback(trial.number + 1, n_trials, best_score_so_far[0])

            logger.debug(
                f"XGBoost trial {trial.number + 1}/{n_trials}: "
                f"AUC={auc:.4f} (best={best_score_so_far[0]:.4f})"
            )

            return auc

        except Exception as e:
            logger.warning(f"XGBoost trial {trial.number + 1} failed: {e}")
            # Return a low score so the study continues
            if progress_callback:
                progress_callback(trial.number + 1, n_trials, best_score_so_far[0])
            return 0.0

    try:
        logger.info(f"Starting XGBoost HPO with {n_trials} trials...")

        study = optuna.create_study(direction="maximize")
        study.optimize(objective, n_trials=n_trials)

        best_params = study.best_params
        best_value = study.best_value

        logger.info(
            f"XGBoost HPO complete. Best AUC: {best_value:.4f}. "
            f"Best params: {best_params}"
        )

        return best_params

    except Exception as e:
        logger.error(f"XGBoost HPO failed: {e}")
        return {}


def optimize_lightgbm(
    X_train,
    y_train,
    X_val,
    y_val,
    n_trials: int = 30,
    progress_callback: Optional[Callable[[int, int, float], None]] = None,
) -> Dict:
    """
    Use Optuna to find optimal LightGBM hyperparameters.

    Searches over tree depth, learning rate, regularization, leaf count,
    and sampling parameters. Objective is to maximize ROC AUC on validation set.

    Args:
        X_train: Training feature matrix (numpy array or pandas DataFrame)
        y_train: Training binary labels (1=win, 0=loss)
        X_val: Validation feature matrix
        y_val: Validation binary labels
        n_trials: Number of Optuna trials to run (default 30)
        progress_callback: Optional callback(trial_number, total_trials, best_score)

    Returns:
        Dict of best hyperparameters, or empty dict if optimization fails.
    """
    try:
        import optuna
    except ImportError:
        logger.warning(
            "optuna is not installed. Install it with: pip install optuna. "
            "Returning empty params (default hyperparameters will be used)."
        )
        return {}

    try:
        from lightgbm import LGBMClassifier
    except ImportError:
        logger.warning(
            "lightgbm is not installed. Install it with: pip install lightgbm. "
            "Cannot run LightGBM HPO."
        )
        return {}

    try:
        from sklearn.metrics import roc_auc_score
    except ImportError:
        logger.warning("scikit-learn is not installed. Cannot compute ROC AUC.")
        return {}

    # Suppress Optuna's verbose trial logging
    optuna.logging.set_verbosity(optuna.logging.WARNING)

    best_score_so_far = [0.0]

    def objective(trial: optuna.Trial) -> float:
        """Single Optuna trial: train LightGBM with sampled params, return val AUC."""
        try:
            params = {
                "n_estimators": trial.suggest_int("n_estimators", 50, 300),
                "max_depth": trial.suggest_int("max_depth", 2, 8),
                "learning_rate": trial.suggest_float("learning_rate", 0.01, 0.2, log=True),
                "subsample": trial.suggest_float("subsample", 0.6, 1.0),
                "colsample_bytree": trial.suggest_float("colsample_bytree", 0.6, 1.0),
                "min_child_weight": trial.suggest_int("min_child_weight", 1, 10),
                "reg_alpha": trial.suggest_float("reg_alpha", 0.001, 1.0, log=True),
                "reg_lambda": trial.suggest_float("reg_lambda", 0.1, 5.0),
                "num_leaves": trial.suggest_int("num_leaves", 15, 63),
                "random_state": 42,
                "verbosity": -1,
            }

            model = LGBMClassifier(**params)
            model.fit(X_train, y_train)

            y_proba = model.predict_proba(X_val)[:, 1]
            auc = roc_auc_score(y_val, y_proba)

            # Track best score for callback
            if auc > best_score_so_far[0]:
                best_score_so_far[0] = auc

            # Progress callback
            if progress_callback:
                progress_callback(trial.number + 1, n_trials, best_score_so_far[0])

            logger.debug(
                f"LightGBM trial {trial.number + 1}/{n_trials}: "
                f"AUC={auc:.4f} (best={best_score_so_far[0]:.4f})"
            )

            return auc

        except Exception as e:
            logger.warning(f"LightGBM trial {trial.number + 1} failed: {e}")
            if progress_callback:
                progress_callback(trial.number + 1, n_trials, best_score_so_far[0])
            return 0.0

    try:
        logger.info(f"Starting LightGBM HPO with {n_trials} trials...")

        study = optuna.create_study(direction="maximize")
        study.optimize(objective, n_trials=n_trials)

        best_params = study.best_params
        best_value = study.best_value

        logger.info(
            f"LightGBM HPO complete. Best AUC: {best_value:.4f}. "
            f"Best params: {best_params}"
        )

        return best_params

    except Exception as e:
        logger.error(f"LightGBM HPO failed: {e}")
        return {}


def optimize_model(
    model_type: str,
    X_train,
    y_train,
    X_val,
    y_val,
    n_trials: int = 30,
    progress_callback: Optional[Callable[[int, int, float], None]] = None,
) -> Dict:
    """
    Dispatch function: run hyperparameter optimization for the given model type.

    Routes to the appropriate optimizer based on model_type. For model types
    that do not support HPO (lstm, cnn, ensemble), returns an empty dict
    so that default parameters are used.

    Args:
        model_type: One of "xgboost", "lightgbm", "lstm", "cnn", "ensemble"
        X_train: Training feature matrix
        y_train: Training binary labels
        X_val: Validation feature matrix
        y_val: Validation binary labels
        n_trials: Number of Optuna trials (default 30)
        progress_callback: Optional callback(trial_number, total_trials, best_score)

    Returns:
        Dict of best hyperparameters, or empty dict if HPO is not
        available/applicable for the given model type.
    """
    # Check optuna availability upfront
    try:
        import optuna  # noqa: F401
    except ImportError:
        logger.warning(
            "optuna is not installed. Hyperparameter optimization is disabled. "
            "Install it with: pip install optuna"
        )
        return {}

    model_type_lower = model_type.lower().strip()

    if model_type_lower == "xgboost":
        logger.info("Dispatching to XGBoost hyperparameter optimization...")
        return optimize_xgboost(
            X_train, y_train, X_val, y_val,
            n_trials=n_trials,
            progress_callback=progress_callback,
        )

    elif model_type_lower == "lightgbm":
        logger.info("Dispatching to LightGBM hyperparameter optimization...")
        return optimize_lightgbm(
            X_train, y_train, X_val, y_val,
            n_trials=n_trials,
            progress_callback=progress_callback,
        )

    elif model_type_lower in ("lstm", "cnn", "ensemble", "transformer"):
        logger.info(
            f"HPO not implemented for model type '{model_type}'. "
            f"Using default hyperparameters."
        )
        return {}

    else:
        logger.warning(
            f"Unknown model type '{model_type}'. "
            f"Supported types: xgboost, lightgbm, lstm, cnn, ensemble. "
            f"Returning empty params."
        )
        return {}
