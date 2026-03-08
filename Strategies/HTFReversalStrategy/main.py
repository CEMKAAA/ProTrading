"""
HTF Reversal Strategy Entry Point
Run this file to start the Multi-Timeframe Key Level Reversal Strategy
"""

import sys
import os
import traceback

# Add parent paths for imports
project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, project_root)

print("=" * 60)
print("HTF Reversal Strategy - Multi-Timeframe Key Level Trading")
print("=" * 60)
print(f"Python: {sys.executable}")
print(f"Project Root: {project_root}")
print("=" * 60)


def main():
    """Entry point"""
    try:
        print("\nInitializing strategy...")
        from Strategies.HTFReversalStrategy.strategy import HTFReversalStrategy

        strategy = HTFReversalStrategy()
        print("Strategy initialized successfully!")
        print("Starting trading loop...\n")
        strategy.start()

    except ImportError as e:
        print(f"\n[ERROR] Import error: {e}")
        print("\nThis usually means a required package is not installed.")
        print("Try: pip install MetaTrader5 pandas numpy")
        traceback.print_exc()

    except Exception as e:
        print(f"\n[ERROR] Fatal error: {e}")
        traceback.print_exc()

        try:
            import MetaTrader5 as mt5
            mt5.shutdown()
        except:
            pass

    finally:
        print("\n" + "=" * 60)
        print("Strategy stopped. Press Enter to close...")
        input()


if __name__ == "__main__":
    main()
