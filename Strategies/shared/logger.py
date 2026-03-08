"""
Shared logging configuration for all live trading strategies.
"""

import logging
from logging.handlers import RotatingFileHandler
import sys
import os
from pathlib import Path


LOG_MAX_BYTES = 5 * 1024 * 1024  # 5MB
LOG_BACKUP_COUNT = 5


def setup_logger(name: str, log_dir: str = None) -> logging.Logger:
    """
    Configure logger with console and rotating file handler.

    Args:
        name: Logger name (e.g., 'MACDEMAStrategy')
        log_dir: Directory for log files. If None, uses strategy's own logs/ dir.

    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)

    # Avoid duplicate handlers
    if logger.handlers:
        return logger

    formatter = logging.Formatter(
        '%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

    # Console handler with UTF-8 encoding
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)

    # Force UTF-8 on Windows console
    if sys.platform == 'win32':
        import io
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
        console_handler.stream = sys.stdout

    logger.addHandler(console_handler)

    # File handler with rotation
    if log_dir is None:
        log_dir = Path(__file__).parent / "logs"
    else:
        log_dir = Path(log_dir)

    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"{name.lower()}.log"

    file_handler = RotatingFileHandler(
        str(log_file),
        maxBytes=LOG_MAX_BYTES,
        backupCount=LOG_BACKUP_COUNT,
        encoding='utf-8'
    )
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    return logger
