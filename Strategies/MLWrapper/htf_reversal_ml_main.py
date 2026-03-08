"""HTF Reversal + ML Filter Strategy Entry Point"""

import sys
import os
import traceback

project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, project_root)

print("=" * 60)
print("HTF Reversal + ML Filter Strategy")
print("=" * 60)


def main():
    try:
        from Strategies.HTFReversalStrategy.strategy import HTFReversalStrategy
        from Strategies.shared.ml_wrapper import create_ml_wrapped_strategy

        MLHTFReversalStrategy = create_ml_wrapped_strategy(
            base_class=HTFReversalStrategy,
            ml_strategy_id="htf_reversal_ml_strategy",
            ml_magic_number=777013,
            ml_name="HTF Reversal + ML Filter",
            ml_description="HTF Reversal strategy with ML trade probability filter.",
            base_strategy_id="htf_reversal_strategy",
            min_probability=0.55,
        )

        strategy = MLHTFReversalStrategy()
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
