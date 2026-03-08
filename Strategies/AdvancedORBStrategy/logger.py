"""
Logging configuration for Advanced ORB Strategy
"""

import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
from .config import get_config

# Create logs directory
LOG_DIR = Path(__file__).parent.parent.parent / "logs"
LOG_DIR.mkdir(exist_ok=True)


def setup_logger(name: str = "advanced_orb") -> logging.Logger:
    """
    Set up and return a configured logger.

    Args:
        name: Logger name

    Returns:
        Configured logger instance
    """
    cfg = get_config()
    logger = logging.getLogger(name)

    # Avoid duplicate handlers
    if logger.handlers:
        return logger

    logger.setLevel(logging.DEBUG)

    # File handler with rotation
    log_path = LOG_DIR / cfg.log_file
    file_handler = RotatingFileHandler(
        log_path,
        maxBytes=cfg.log_max_bytes,
        backupCount=cfg.log_backup_count
    )
    file_handler.setLevel(logging.DEBUG)

    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)

    # Formatter
    formatter = logging.Formatter(
        '%(asctime)s | %(levelname)-8s | %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(formatter)
    console_handler.setFormatter(formatter)

    logger.addHandler(file_handler)
    logger.addHandler(console_handler)

    return logger


# Default logger instance
logger = setup_logger()
