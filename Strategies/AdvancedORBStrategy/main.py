"""
Advanced Gold ORB Strategy - Entry Point
Production-level trading system with comprehensive fixes
"""

import sys
import signal
import argparse
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from Strategies.AdvancedORBStrategy.strategy import AdvancedGoldORBStrategy
from Strategies.AdvancedORBStrategy.logger import logger
from Strategies.AdvancedORBStrategy.config import STRATEGY_NAME, STRATEGY_VERSION


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    logger.info(f"Received signal {signum}, initiating shutdown...")
    raise KeyboardInterrupt


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description=f'{STRATEGY_NAME} v{STRATEGY_VERSION}'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Run in dry-run mode (no actual trades)'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Enable debug logging'
    )
    args = parser.parse_args()

    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    logger.info("=" * 60)
    logger.info(f"Starting {STRATEGY_NAME} v{STRATEGY_VERSION}")
    logger.info("=" * 60)

    if args.dry_run:
        logger.warning("DRY-RUN MODE: No actual trades will be executed")

    try:
        strategy = AdvancedGoldORBStrategy()

        if args.dry_run:
            # In dry-run mode, just initialize and validate
            if strategy.initialize():
                logger.info("Strategy initialized successfully in dry-run mode")
                logger.info("Dry-run validation complete. Exiting.")
            else:
                logger.error("Strategy initialization failed")
                sys.exit(1)
        else:
            # Full execution mode through BaseStrategy lifecycle (respects stop flag)
            strategy.start()

    except KeyboardInterrupt:
        logger.info("Strategy stopped by user")
    except Exception as e:
        logger.critical(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)
    finally:
        logger.info("Strategy shutdown complete")


if __name__ == "__main__":
    main()
