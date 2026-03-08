"""
Logging configuration for the trading bot
"""

import logging
from logging.handlers import RotatingFileHandler
import sys
from config import LOG_FILE, LOG_MAX_BYTES, LOG_BACKUP_COUNT


def setup_logger(name='TradingBot'):
    """
    Configure logger with console and rotating file handler
    
    Args:
        name: Logger name
        
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
    
    # Console handler with UTF-8 encoding for emoji support
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)
    console_handler.setStream(sys.stdout)
    
    # Force UTF-8 on Windows console
    if sys.platform == 'win32':
        import io
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
        console_handler.stream = sys.stdout
    
    logger.addHandler(console_handler)
    
    # File handler with rotation and UTF-8 encoding
    file_handler = RotatingFileHandler(
        LOG_FILE,
        maxBytes=LOG_MAX_BYTES,
        backupCount=LOG_BACKUP_COUNT,
        encoding='utf-8'  # Explicitly set UTF-8 for file logging
    )
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    
    return logger


# Global logger instance
logger = setup_logger()
