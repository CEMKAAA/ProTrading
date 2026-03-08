"""Confluence Zone + ML Filter Strategy Entry Point"""

import sys
import os
import traceback

project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, project_root)

print("=" * 60)
print("Confluence Zone + ML Filter Strategy")
print("=" * 60)


def main():
    try:
        from Strategies.ConfluenceZoneStrategy.strategy import ConfluenceZoneLiveStrategy
        from Strategies.shared.ml_wrapper import create_ml_wrapped_strategy

        MLConfluenceZoneStrategy = create_ml_wrapped_strategy(
            base_class=ConfluenceZoneLiveStrategy,
            ml_strategy_id="confluence_zone_ml_strategy",
            ml_magic_number=777017,
            ml_name="Confluence Zone + ML Filter",
            ml_description="Multi-TF Confluence Zone strategy with ML trade probability filter.",
            base_strategy_id="confluence_zone_strategy",
            min_probability=0.55,
        )

        strategy = MLConfluenceZoneStrategy()
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
