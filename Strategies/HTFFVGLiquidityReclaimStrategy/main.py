"""
HTF FVG + Liquidity Reclaim live strategy entry point.
"""

import os
import sys
import traceback

project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, project_root)

print("=" * 60)
print("HTF FVG + Liquidity Reclaim Strategy")
print("=" * 60)


def main():
    try:
        from Strategies.HTFFVGLiquidityReclaimStrategy.strategy import (
            HTFFVGLiquidityReclaimLiveStrategy,
        )

        strategy = HTFFVGLiquidityReclaimLiveStrategy()
        strategy.start()
    except ImportError as exc:
        print(f"\n[ERROR] Import error: {exc}")
        traceback.print_exc()
    except Exception as exc:
        print(f"\n[ERROR] Fatal error: {exc}")
        traceback.print_exc()
        try:
            import MetaTrader5 as mt5

            mt5.shutdown()
        except Exception:
            pass
    finally:
        print("\nStrategy stopped. Press Enter to close...")
        input()


if __name__ == "__main__":
    main()
