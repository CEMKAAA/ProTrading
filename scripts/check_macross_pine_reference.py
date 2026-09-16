"""Independent array-based transcription of supplied Pine defaults.

Compares MT5-executed stream outputs, not two calls to the same implementation.
This verifies equations on identical OHLC, not TradingView broker-feed parity.
"""
import argparse
import json
import math
from pathlib import Path


def fixture(n):
    close = [1000 + 40 * math.sin(i * .039) + 12 * math.sin(i * .31) + .001 * i for i in range(n)]
    op = [close[0] - 1] + close[:-1]
    return (op, [max(a, b) + 1 + (i % 7) * .17 for i, (a, b) in enumerate(zip(op, close))],
            [min(a, b) - 1 - (i % 11) * .13 for i, (a, b) in enumerate(zip(op, close))], close)


def ema(a, period):
    result = [a[0]]
    for x in a[1:]:
        result.append(result[-1] + (x - result[-1]) * 2 / (period + 1))
    return result


def wma(a, length):
    result = [None] * len(a)
    for i in range(length - 1, len(a)):
        window = a[i-length+1:i+1]
        if all(v is not None for v in window):
            result[i] = sum((j+1)*v for j, v in enumerate(window)) / (length*(length+1)/2)
    return result


def hma(a, length):
    half, full = wma(a, length//2), wma(a, length)
    return wma([2*x-y if x is not None and y is not None else None for x, y in zip(half, full)], round(math.sqrt(length)))


def atr(hi, lo, cl, period):
    tr = [hi[0]-lo[0]] + [max(hi[i]-lo[i], abs(hi[i]-cl[i-1]), abs(lo[i]-cl[i-1])) for i in range(1, len(cl))]
    result = [None] * len(cl)
    result[period-1] = sum(tr[:period])/period
    for i in range(period, len(cl)):
        result[i] = (result[i-1]*(period-1)+tr[i])/period
    return result


def pivot(a, i, width, high):
    if i < 2*width:
        return None
    p, v = i-width, a[i-width]
    for k in range(i-2*width, i+1):
        if k == p:
            continue
        if (a[k] > v or (k > p and a[k] == v)) if high else (a[k] < v or (k > p and a[k] == v)):
            return None
    return v


def cross(a, b, pa, pb, up):
    if any(x is None for x in (a, b, pa, pb)):
        return False
    return a > b and pa <= pb if up else a < b and pa >= pb


def reference(n):
    op, hi, lo, cl = fixture(n)
    outputs = [[0]*n for _ in range(5)]
    for mode, f, s in [(0, 9, 27), (1, 50, 200)]:
        fast, slow = ema(cl, f), ema(cl, s)
        higher = hma(fixture(400)[3], 200)
        for i in range(1, n):
            d = 1 if cross(fast[i], slow[i], fast[i-1], slow[i-1], True) else -1 if cross(fast[i], slow[i], fast[i-1], slow[i-1], False) else 0
            if mode == 0:
                h = min(399, ((i+1)*300-14400)//14400)
                value = higher[h] if h >= 0 else None
                if value is None or (d > 0 and cl[i] <= value) or (d < 0 and cl[i] >= value):
                    d = 0
            outputs[mode][i] = d
    av = atr(hi, lo, cl, 24)
    upper = lower = sh = sl = pu = pl = None
    for i in range(n):
        ph, pv = pivot(hi, i, 24, True), pivot(lo, i, 24, False)
        if ph is not None:
            upper, sh = ph, av[i]/24*1.6
        elif upper is not None:
            upper -= sh
        if pv is not None:
            lower, sl = pv, av[i]/24*1.6
        elif lower is not None:
            lower += sl
        u = upper-sh*24 if upper is not None else None
        l = lower+sl*24 if lower is not None else None
        if i:
            outputs[2][i] = 1 if cross(cl[i], u, cl[i-1], pu, True) else -1 if cross(cl[i], l, cl[i-1], pl, False) else 0
        pu, pl = u, l
    av = atr(hi, lo, cl, 10)
    center = tup = tdown = None
    trend = 1
    for i in range(n):
        ph, pl = pivot(hi, i, 2, True), pivot(lo, i, 2, False)
        pp = ph if ph is not None else pl
        if pp is not None:
            center = pp if center is None else (center*2+pp)/3
        if center is None or av[i] is None:
            continue
        up, dn = center-3*av[i], center+3*av[i]
        newup = max(up, tup) if tup is not None and cl[i-1] > tup else up
        newdn = min(dn, tdown) if tdown is not None and cl[i-1] < tdown else dn
        newtrend = 1 if tdown is not None and cl[i] > tdown else -1 if tup is not None and cl[i] < tup else trend
        outputs[3][i] = newtrend if newtrend != trend else 0
        tup, tdown, trend = newup, newdn, newtrend
    hc = [(a+b+c+d)/4 for a,b,c,d in zip(op,hi,lo,cl)]
    ho = [(op[0]+cl[0])/2]
    for i in range(1,n):
        ho.append((ho[-1]+hc[i-1])/2)
    hh = [max(a,b,c) for a,b,c in zip(hi,ho,hc)]
    hl = [min(a,b,c) for a,b,c in zip(lo,ho,hc)]
    fast, med, pc, pu, pl = ema(hc,12), ema(hc,200), ema(hc,34), ema(hh,34), ema(hl,34)
    state = 0
    below = above = -10**8
    for i in range(n):
        if hc[i] < pc[i]: below = i
        if hc[i] > pc[i]: above = i
        td = 1 if fast[i]>med[i] and pl[i]>med[i] else -1 if fast[i]<med[i] and pu[i]<med[i] else 0
        buy = td==1 and ho[i]<pu[i] and hc[i]>pu[i] and i-below<=3
        sell = td==-1 and ho[i]>pl[i] and hc[i]<pl[i] and i-above<=3
        old = state
        state = 0 if (old==1 and hc[i]<pc[i]) or (old==-1 and hc[i]>pc[i]) else 1 if old==0 and buy else -1 if old==0 and sell else old
        outputs[4][i] = state if old==0 and state else 0
    return outputs


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directions', type=Path)
    args = parser.parse_args()
    actual = [[0]*12000 for _ in range(5)]
    rows = set()
    for line in args.directions.read_text(encoding='utf-8-sig').splitlines():
        mode, i, value = map(int, line.split(','))
        assert (mode, i) not in rows
        rows.add((mode, i))
        actual[mode][i] = value
    assert len(rows) == 60000, 'Missing output rows'
    expected = reference(12000)
    mismatches = [(m,i,actual[m][i],expected[m][i]) for m in range(5) for i in range(12000) if actual[m][i] != expected[m][i]]
    result = dict(compared=60000, mismatches=len(mismatches), first_mismatches=mismatches[:10], signals=[sum(v!=0 for v in row) for row in actual])
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(mismatches))
