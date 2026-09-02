"""Parity test for ORB's advanced minute-index event search.

The reference walks every executable quote. The indexed implementation uses
the same min/max proof as OrbAdvancedAuditEngine.mqh, descends a segment tree,
and opens only candidate minutes. Any mismatch is a correctness failure.
"""

from __future__ import annotations

from dataclasses import dataclass
import random
import time


@dataclass(frozen=True)
class Tick:
    second: int
    bid: float
    ask: float


@dataclass
class State:
    outcome: str = "open"
    exit_second: int = -1
    exit_price: float = 0.0
    max_tp: int = 0
    effective_sl: float = 0.0
    be_applied: bool = False


@dataclass(frozen=True)
class Config:
    is_buy: bool
    entry: float
    sl: float
    tps: tuple[float, ...]
    target: float
    hc_leg: int
    forced_second: int
    time_exit_second: int
    min_progress_r: float
    eod_second: int
    broker_second: int


@dataclass(frozen=True)
class Node:
    left: int
    right: int
    first_second: int
    last_second: int
    min_bid: float
    max_bid: float
    min_ask: float
    max_ask: float


def apply_tick(state: State, cfg: Config, tick: Tick) -> None:
    close = tick.bid if cfg.is_buy else tick.ask
    risk = abs(cfg.entry - cfg.sl)
    if cfg.forced_second >= 0 and tick.second >= cfg.forced_second:
        sl_hit = close <= state.effective_sl if cfg.is_buy else close >= state.effective_sl
        target_hit = close >= cfg.target if cfg.is_buy else close <= cfg.target
        if sl_hit:
            state.outcome = "BE" if state.be_applied else "SL"
            state.exit_price = state.effective_sl
        elif target_hit:
            state.outcome = "TARGET"
            state.exit_price = cfg.target
        else:
            hit = 0
            for index, target in enumerate(cfg.tps, 1):
                if close >= target if cfg.is_buy else close <= target:
                    hit = index
            state.max_tp = max(state.max_tp, hit)
            if cfg.hc_leg and state.max_tp >= cfg.hc_leg and not state.be_applied:
                state.effective_sl = cfg.entry
                state.be_applied = True
            state.outcome = "FORCED"
            state.exit_price = close
        state.exit_second = tick.second
        return

    if cfg.time_exit_second >= 0 and tick.second >= cfg.time_exit_second:
        progress = (close - cfg.entry) / risk if cfg.is_buy else (cfg.entry - close) / risk
        if progress < cfg.min_progress_r:
            state.outcome = "TIME_EXIT"
            state.exit_second = tick.second
            state.exit_price = close
            return
    if cfg.eod_second >= 0 and tick.second >= cfg.eod_second:
        state.outcome = "EOD_EXIT"
        state.exit_second = tick.second
        state.exit_price = close
        return
    if cfg.broker_second >= 0 and tick.second >= cfg.broker_second:
        state.outcome = "BROKER_TIME_EXIT"
        state.exit_second = tick.second
        state.exit_price = close
        return

    sl_hit = close <= state.effective_sl if cfg.is_buy else close >= state.effective_sl
    if sl_hit:
        state.outcome = "BE" if state.be_applied else "SL"
        state.exit_second = tick.second
        state.exit_price = state.effective_sl
        return
    hit = 0
    for index, target in enumerate(cfg.tps, 1):
        if close >= target if cfg.is_buy else close <= target:
            hit = index
    state.max_tp = max(state.max_tp, hit)
    if cfg.hc_leg and state.max_tp >= cfg.hc_leg and not state.be_applied:
        state.effective_sl = cfg.entry
        state.be_applied = True
    target_hit = close >= cfg.target if cfg.is_buy else close <= cfg.target
    if target_hit:
        state.outcome = "TARGET"
        state.exit_second = tick.second
        state.exit_price = cfg.target


def reference(ticks: list[Tick], cfg: Config) -> tuple[State, int]:
    state = State(effective_sl=cfg.sl)
    visited = 0
    for tick in ticks:
        visited += 1
        apply_tick(state, cfg, tick)
        if state.outcome != "open":
            break
    return state, visited


def minute_groups(ticks: list[Tick]) -> list[list[Tick]]:
    groups: list[list[Tick]] = []
    minute = -1
    for tick in ticks:
        current = tick.second // 60
        if current != minute:
            groups.append([])
            minute = current
        groups[-1].append(tick)
    return groups


def summarize(group: list[Tick], left: int, right: int) -> Node:
    return Node(
        left,
        right,
        group[0].second,
        group[-1].second,
        min(t.bid for t in group),
        max(t.bid for t in group),
        min(t.ask for t in group),
        max(t.ask for t in group),
    )


def merge(a: Node, b: Node) -> Node:
    return Node(
        a.left,
        b.right,
        a.first_second,
        b.last_second,
        min(a.min_bid, b.min_bid),
        max(a.max_bid, b.max_bid),
        min(a.min_ask, b.min_ask),
        max(a.max_ask, b.max_ask),
    )


def build_tree(groups: list[list[Tick]]) -> list[Node | None]:
    tree: list[Node | None] = [None] * (len(groups) * 4 + 8)

    def build(node: int, left: int, right: int) -> None:
        if left == right:
            tree[node] = summarize(groups[left], left, right)
            return
        middle = (left + right) // 2
        build(node * 2, left, middle)
        build(node * 2 + 1, middle + 1, right)
        tree[node] = merge(tree[node * 2], tree[node * 2 + 1])  # type: ignore[arg-type]

    build(1, 0, len(groups) - 1)
    return tree


def can_skip(node: Node, state: State, cfg: Config) -> bool:
    if cfg.forced_second >= 0 and node.last_second >= cfg.forced_second:
        return False
    if cfg.eod_second >= 0 and node.last_second >= cfg.eod_second:
        return False
    if cfg.broker_second >= 0 and node.last_second >= cfg.broker_second:
        return False
    min_close = node.min_bid if cfg.is_buy else node.min_ask
    max_close = node.max_bid if cfg.is_buy else node.max_ask
    if min_close <= state.effective_sl if cfg.is_buy else max_close >= state.effective_sl:
        return False
    for target in cfg.tps[state.max_tp :]:
        if max_close >= target if cfg.is_buy else min_close <= target:
            return False
    if max_close >= cfg.target if cfg.is_buy else min_close <= cfg.target:
        return False
    if cfg.time_exit_second >= 0 and node.last_second >= cfg.time_exit_second:
        threshold = (
            cfg.entry + cfg.min_progress_r * abs(cfg.entry - cfg.sl)
            if cfg.is_buy
            else cfg.entry - cfg.min_progress_r * abs(cfg.entry - cfg.sl)
        )
        if min_close < threshold if cfg.is_buy else max_close > threshold:
            return False
    return True


def indexed(ticks: list[Tick], cfg: Config) -> tuple[State, int, int]:
    groups = minute_groups(ticks)
    tree = build_tree(groups)
    state = State(effective_sl=cfg.sl)
    visited = 0
    skipped = 0
    cursor = 0

    def find(node_index: int, query_left: int) -> int:
        nonlocal skipped
        node = tree[node_index]
        assert node is not None
        if node.right < query_left:
            return -1
        if query_left <= node.left and can_skip(node, state, cfg):
            skipped += node.right - node.left + 1
            return -1
        if node.left == node.right:
            return node.left
        found = find(node_index * 2, query_left)
        return found if found >= 0 else find(node_index * 2 + 1, query_left)

    while cursor < len(groups) and state.outcome == "open":
        candidate = find(1, cursor)
        if candidate < 0:
            break
        for tick in groups[candidate]:
            visited += 1
            apply_tick(state, cfg, tick)
            if state.outcome != "open":
                break
        cursor = candidate + 1
    return state, visited, skipped


def make_case(rng: random.Random) -> tuple[list[Tick], Config]:
    is_buy = bool(rng.getrandbits(1))
    entry = 100.0
    risk = rng.choice((0.4, 0.8, 1.2, 2.0))
    sl = entry - risk if is_buy else entry + risk
    ratios = (0.05, 0.15, 0.5, 1.0, 2.0, 3.0)
    tps = tuple(entry + risk * r if is_buy else entry - risk * r for r in ratios)
    target = rng.choice(tps)
    minutes = rng.randint(20, 420)
    per_minute = rng.randint(3, 15)
    price = entry
    ticks: list[Tick] = []
    for minute in range(minutes):
        for offset in range(per_minute):
            price += rng.gauss(0.0, risk / 35.0)
            spread = rng.uniform(0.005, 0.035)
            ticks.append(Tick(minute * 60 + offset * max(1, 59 // per_minute), price, price + spread))
    horizon = ticks[-1].second
    forced = rng.choice((-1, -1, -1, rng.randint(60, horizon)))
    time_exit = rng.choice((-1, -1, rng.randint(60, horizon)))
    eod = rng.choice((-1, -1, -1, rng.randint(60, horizon)))
    broker = rng.choice((-1, -1, -1, rng.randint(60, horizon)))
    cfg = Config(
        is_buy,
        entry,
        sl,
        tps,
        target,
        rng.randint(0, 5),
        forced,
        time_exit,
        rng.choice((-0.25, 0.0, 0.25, 0.5)),
        eod,
        broker,
    )
    return ticks, cfg


def main() -> None:
    rng = random.Random(0x0BADC0DE)
    cases = 1200
    legacy_visited = 0
    indexed_visited = 0
    skipped_minutes = 0
    started = time.perf_counter()
    for case in range(cases):
        ticks, cfg = make_case(rng)
        expected, ref_count = reference(ticks, cfg)
        actual, adv_count, skipped = indexed(ticks, cfg)
        if actual != expected:
            raise AssertionError(
                f"case={case} mismatch\nexpected={expected}\nactual={actual}\nconfig={cfg}"
            )
        legacy_visited += ref_count
        indexed_visited += adv_count
        skipped_minutes += skipped
    elapsed = time.perf_counter() - started
    reduction = 100.0 * (1.0 - indexed_visited / max(1, legacy_visited))
    print(
        "ORB advanced segment-tree parity passed: "
        f"{cases} randomized bid/ask paths, visited {indexed_visited}/{legacy_visited} "
        f"ticks ({reduction:.2f}% reduction), skipped_minutes={skipped_minutes}, elapsed={elapsed:.3f}s"
    )


if __name__ == "__main__":
    main()
