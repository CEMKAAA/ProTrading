"""Independent scalar translation of Pine's default equations, not TradingView data."""
import csv
import math
import sys


def reference(rows):
    level = slope = cov = pos = neg = velocity = 0.0
    base = rail = None
    p00 = p11 = 0.0
    noise = 1.0
    cooldown = leg = 0
    trend = False
    previous = None
    for i, r in enumerate(rows):
        o, h, l, c = (float(r[k]) for k in ('open', 'high', 'low', 'close'))
        if base is None:
            level = math.log(c)
            pc = o if previous is None else previous
            tr = max(math.log(h)-math.log(l), abs(math.log(h)-math.log(pc)), abs(math.log(l)-math.log(pc)))
            if tr > 0:
                base = max((0.5*tr)**2, 1e-12)
                p00, p11 = base*10, base*0.1
        deviation = conviction = 0.0
        up = down = False
        if base is not None:
            measurement = base*noise
            process = 0.05*measurement
            pred = level+slope
            a = p00+2*cov+p11+process/3
            b = cov+p11+process*0.5
            d = p11+process
            variance = a+measurement
            innovation = math.log(c)-pred
            deviation = math.sqrt(max(variance, 1e-18))
            z = innovation/deviation
            robust = innovation*(1 if abs(z) <= 2.5 else 2.5/abs(z))
            level, slope = pred+a/variance*robust, slope+b/variance*robust
            p00, cov, p11 = a-a/variance*a, b-a/variance*b, d-b/variance*b
            pos, neg = max(0, pos+z-0.5), max(0, neg-z-0.5)
            up, down = pos > 6, neg > 6
            if up or down:
                cooldown, pos, neg = 10, 0, 0
            gain = 0.15 if cooldown > 0 else 0.02
            cooldown = max(0, cooldown-1)
            if i > 10 and variance > 0:
                noise = min(16, max(0.25, noise*math.exp(gain*(min(innovation**2/variance, 9)-1))))
            conviction = abs(slope)/math.sqrt(max(p11, 1e-18))
        if rail is None:
            rail = level
        old = leg
        band = 1.05*deviation
        freeze = 0.15*band
        error = level-rail
        if trend and conviction < 0.35:
            trend = False
        elif not trend and conviction > 1:
            trend = True
        speed = 0.20*deviation
        if leg == 0:
            if error > band or (trend and error > freeze):
                leg, velocity = 1, speed
            elif error < -band or (trend and error < -freeze):
                leg, velocity = -1, speed
        if leg == 1 and error < -band and down:
            leg, velocity = -1, speed
        elif leg == -1 and error > band and up:
            leg, velocity = 1, speed
        if leg == 1:
            rail += min(velocity, max(error, 0))
            if level-rail <= freeze and not trend:
                leg = 0
        elif leg == -1:
            rail -= min(velocity, max(-error, 0))
            if rail-level <= freeze and not trend:
                leg = 0
        signal = leg if i > 0 and leg != 0 and leg != old else 0
        previous = c
        yield math.exp(rail), leg, signal


with open(sys.argv[1], newline='') as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 3000
expected = list(reference(rows))
signals = 0
for i, (r, (rail, state, signal)) in enumerate(zip(rows, expected)):
    assert math.isclose(float(r['rail']), rail, rel_tol=1e-11), (i, 'rail')
    assert int(r['state']) == state, (i, 'state')
    assert int(r['signal']) == signal == int(r['streamSignal']), (i, 'signal')
    assert int(r['flatState']) == 0, (i, 'flat seed')
    signals += signal != 0
for n in (1, 20, 21, 100, 999, 2000):
    assert list(reference(rows[:n])) == expected[:n], ('prefix changed', n)
assert signals > 20
print(f'PASS: 3000 bars, 12000 field checks, 6 causal prefix checks, {signals} transitions. Not TradingView feed parity.')
