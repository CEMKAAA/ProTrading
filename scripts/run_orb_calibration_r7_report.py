"""CLI adapter: frozen R7 report's __main__ missed pathlib.Path import.

The frozen computation module and pre-test source hashes remain unchanged.
"""
import argparse
from pathlib import Path
from threadpoolctl import threadpool_limits
import orb_calibration_r7_report as report


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path, default=report.r7.ROOT)
    p.add_argument('--draws', type=int, default=20000)
    a = p.parse_args()
    with threadpool_limits(limits=1):
        report.run(a.root, a.draws)
