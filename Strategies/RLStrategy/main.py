"""
RL Strategy Entry Point
Run this file to start the Reinforcement Learning Trading Strategy
"""

import sys
import os
import traceback

project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, project_root)

print("=" * 60)
print("Reinforcement Learning Trading Strategy")
print("=" * 60)


def main():
    try:
        from Strategies.RLStrategy.strategy import RLLiveStrategy
        strategy = RLLiveStrategy()
        strategy.start()
    except ImportError as e:
        print(f"\n[ERROR] Import error: {e}")
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
        print("\nStrategy stopped. Press Enter to close...")
        input()


if __name__ == "__main__":
    main()
