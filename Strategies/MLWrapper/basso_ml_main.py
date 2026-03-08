"""Basso + ML Filter Strategy Entry Point"""

import sys
import os
import traceback

project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, project_root)

print("=" * 60)
print("Basso Mean Reversion + ML Filter Strategy")
print("=" * 60)


def main():
    try:
        from Strategies.BassoStrategy.strategy import BassoLiveStrategy
        from Strategies.shared.ml_wrapper import create_ml_wrapped_strategy

        MLBassoStrategy = create_ml_wrapped_strategy(
            base_class=BassoLiveStrategy,
            ml_strategy_id="basso_ml_strategy",
            ml_magic_number=777016,
            ml_name="Basso + ML Filter",
            ml_description="Basso Mean Reversion strategy with ML trade probability filter.",
            base_strategy_id="basso_strategy",
            min_probability=0.55,
        )

        strategy = MLBassoStrategy()
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
