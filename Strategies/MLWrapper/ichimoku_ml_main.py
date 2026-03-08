"""Ichimoku + ML Filter Strategy Entry Point"""

import sys
import os
import traceback

project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, project_root)

print("=" * 60)
print("Ichimoku + ML Filter Strategy")
print("=" * 60)


def main():
    try:
        from Strategies.IchimokuStrategy.strategy import IchimokuLiveStrategy
        from Strategies.shared.ml_wrapper import create_ml_wrapped_strategy

        MLIchimokuStrategy = create_ml_wrapped_strategy(
            base_class=IchimokuLiveStrategy,
            ml_strategy_id="ichimoku_ml_strategy",
            ml_magic_number=777015,
            ml_name="Ichimoku + ML Filter",
            ml_description="Ichimoku Retracement strategy with ML trade probability filter.",
            base_strategy_id="ichimoku_strategy",
            min_probability=0.55,
        )

        strategy = MLIchimokuStrategy()
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
        except Exception:
            pass
    finally:
        print("\nStrategy stopped. Press Enter to close...")
        input()


if __name__ == "__main__":
    main()
