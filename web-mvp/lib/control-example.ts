import { ENGINE_RUNTIME, backtestRequestSchema, type BacktestRequest } from "./control-contract.ts";

const indicator = (name: string, period: number) => ({ kind: "indicator", name, period, lag: 0, source: "close" });
const number = (value: number) => ({ kind: "constant", value });
const compare = (left: object, comparator: string, right: object) => ({ op: "compare", left, comparator, right });

// Research contract example only; not a claimed profitable strategy or an EA execution result.
export function exampleRequest(installationId: string, idempotencyKey: string, now = Date.now()): BacktestRequest {
  const end = new Date(now); end.setUTCHours(0, 0, 0, 0);
  const start = new Date(end.getTime() - 14 * 86400000);
  return backtestRequestSchema.parse({
    version: 1, installationId, idempotencyKey, brokerServer: "Exness-MT5Trial15", symbol: "EURUSDm",
    fromUtc: start.toISOString(), toUtc: end.toISOString(), dataPolicy: "real_ticks_only",
    configuration: {
      version: 1, name: "Connection contract example", timeframe: "M5",
      engine: { kind: "custom", runtime: ENGINE_RUNTIME, signalTiming: "closed_bar",
        buy: { op: "and", args: [compare(indicator("EMA", 12), ">", indicator("EMA", 26)), compare(indicator("RSI", 14), ">", number(55)), compare(indicator("ADX", 14), ">", number(22))] },
        sell: { op: "and", args: [compare(indicator("EMA", 12), "<", indicator("EMA", 26)), compare(indicator("RSI", 14), "<", number(45)), compare(indicator("ADX", 14), ">", number(22))] } },
      geometry: { stopPips: 10, targetR: 1 },
      positions: { mode: "single", maxSameDirectionOpen: 1, reverseExit: { enabled: false, waitMinutes: 0 } },
      brokerTime: { baseUtcOffsetMinutes: 0, dst: "none" },
      timeMatrix: { enabled: false, dayHourMasks: Array(7).fill(0xffffff) },
    },
  });
}
