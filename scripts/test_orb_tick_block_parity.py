import random


BLOCK = 256


def run(ticks, cfg, indexed):
    is_buy = cfg["buy"]
    entry = cfg["entry"]
    risk = cfg["risk"]
    eff_sl = cfg["sl"]
    tps = cfg["tps"]
    target = cfg["target"]
    fixed = cfg["fixed"]
    hc = cfg["hc"]
    forced = cfg["forced"]
    time_at = cfg["time_at"]
    time_min_r = cfg["time_min_r"]
    scheduled = cfg["scheduled"]
    broker_at = cfg["broker_at"]
    max_tp = 0
    be = False
    i = 0
    while i < len(ticks):
        if indexed and i > 0 and i % BLOCK == 0 and i + BLOCK <= len(ticks):
            block = ticks[i : i + BLOCK]
            valid = [x for x in block if x[1] is not None]
            can_skip = not valid
            if valid:
                times = [x[0] for x in valid]
                closes = [x[1] for x in valid]
                lo, hi = min(closes), max(closes)
                can_skip = True
                if forced is not None and max(times) >= forced:
                    can_skip = False
                if scheduled is not None and max(times) >= scheduled:
                    can_skip = False
                if broker_at is not None and max(times) >= broker_at:
                    can_skip = False
                if (is_buy and lo <= eff_sl) or ((not is_buy) and hi >= eff_sl):
                    can_skip = False
                for tp in tps[max_tp:]:
                    if (is_buy and hi >= tp) or ((not is_buy) and lo <= tp):
                        can_skip = False
                if fixed and ((is_buy and hi >= target) or ((not is_buy) and lo <= target)):
                    can_skip = False
                if time_at is not None and max(times) >= time_at:
                    threshold = entry + time_min_r * risk if is_buy else entry - time_min_r * risk
                    if (is_buy and lo < threshold) or ((not is_buy) and hi > threshold):
                        can_skip = False
            if can_skip:
                i += BLOCK
                continue

        at, close = ticks[i]
        if close is None:
            i += 1
            continue
        if forced is not None and at >= forced:
            if (is_buy and close <= eff_sl) or ((not is_buy) and close >= eff_sl):
                return ("BE" if be else "SL", i, round(eff_sl, 9), max_tp)
            if fixed and ((is_buy and close >= target) or ((not is_buy) and close <= target)):
                return ("TARGET", i, round(target, 9), max_tp)
            hit = sum(1 for tp in tps if (close >= tp if is_buy else close <= tp))
            max_tp = max(max_tp, hit)
            if hc and max_tp >= hc and not be:
                eff_sl, be = entry, True
            return ("FORCED", i, round(close, 9), max_tp)
        if time_at is not None and at >= time_at:
            progress = (close - entry) / risk if is_buy else (entry - close) / risk
            if progress < time_min_r:
                return ("TIME", i, round(close, 9), max_tp)
        if scheduled is not None and at >= scheduled:
            return ("EOD", i, round(close, 9), max_tp)
        if broker_at is not None and at >= broker_at:
            return ("BROKER", i, round(close, 9), max_tp)
        if (is_buy and close <= eff_sl) or ((not is_buy) and close >= eff_sl):
            return ("BE" if be else "SL", i, round(eff_sl, 9), max_tp)
        hit = sum(1 for tp in tps if (close >= tp if is_buy else close <= tp))
        max_tp = max(max_tp, hit)
        if hc and max_tp >= hc and not be:
            eff_sl, be = entry, True
        if fixed and ((is_buy and close >= target) or ((not is_buy) and close <= target)):
            return ("TARGET", i, round(target, 9), max_tp)
        i += 1
    return ("OPEN", len(ticks), 0.0, max_tp)


def main():
    rng = random.Random(9152026)
    for case in range(3000):
        buy = bool(rng.getrandbits(1))
        entry = 100.0
        risk = rng.uniform(0.25, 4.0)
        sign = 1 if buy else -1
        ticks = []
        price = entry
        count = rng.randint(300, 5000)
        for i in range(count):
            price += rng.gauss(0.0, risk * 0.025)
            ticks.append((i, None if rng.random() < 0.002 else price))
        cfg = {
            "buy": buy,
            "entry": entry,
            "risk": risk,
            "sl": entry - sign * risk,
            "tps": [entry + sign * risk * r for r in (0.5, 1, 1.5, 2, 2.5, 3)],
            "target": entry + sign * risk * rng.choice((0.35, 0.5, 0.75, 1, 2, 3)),
            "fixed": bool(rng.getrandbits(1)),
            "hc": rng.choice((0, 1, 2, 3)),
            "forced": rng.choice((None, rng.randint(1, count - 1))),
            "time_at": rng.choice((None, rng.randint(1, count - 1))),
            "time_min_r": rng.choice((-0.25, 0.0, 0.25, 0.5)),
            "scheduled": rng.choice((None, count - 1)),
            "broker_at": rng.choice((None, count - 1)),
        }
        baseline = run(ticks, cfg, False)
        indexed = run(ticks, cfg, True)
        if baseline != indexed:
            raise AssertionError(f"case={case} baseline={baseline} indexed={indexed} cfg={cfg}")
    print("ORB exact tick-block parity passed: 3000 randomized chronological paths")


if __name__ == "__main__":
    main()
