import { z } from "zod";
import { universalRequestSchema, UNIVERSAL_RUNTIME } from "./universal-contract.ts";

export const PROTOCOL_VERSION = 1;
export const ENGINE_RUNTIME = "entrylab-adapter/v1";
export const identifier = z.string().uuid();
export const digest = z.string().regex(/^[a-f0-9]{64}$/);
const finite = z.number().finite();
const positive = finite.positive();
const integer = z.number().int().nonnegative();
const period = z.number().int().min(1).max(5000);
const lag = z.number().int().min(0).max(5000);

const operand = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("constant"), value: finite }).strict(),
  z.object({ kind: z.literal("price"), field: z.enum(["open", "high", "low", "close", "tick_volume"]), lag }).strict(),
  z.object({ kind: z.literal("indicator"), name: z.enum(["EMA", "SMA", "RSI", "ADX", "ATR", "HMA"]), period, lag, source: z.enum(["close", "open", "high", "low"]) }).strict(),
]);
export type Operand = z.infer<typeof operand>;
export type Expression =
  | { op: "compare"; comparator: ">" | "<" | ">=" | "<=" | "==" | "!=" | "cross_above" | "cross_below"; left: Operand; right: Operand }
  | { op: "and" | "or" | "xor"; args: Expression[] }
  | { op: "not"; arg: Expression };

// Bound the raw tree before recursive validation; a hostile request must not exhaust the stack.
function boundedTree(value: unknown): boolean {
  const work: [unknown, number][] = [[value, 0]];
  let count = 0;
  while (work.length) {
    const [node, depth] = work.pop()!;
    if (++count > 256 || depth > 16 || !node || typeof node !== "object" || Array.isArray(node)) return false;
    const row = node as Record<string, unknown>;
    if (row.op === "not") work.push([row.arg, depth + 1]);
    if (["and", "or", "xor"].includes(String(row.op))) {
      if (!Array.isArray(row.args) || row.args.length < 2 || row.args.length > 32) return false;
      for (const child of row.args) work.push([child, depth + 1]);
    }
  }
  return true;
}
const recursiveExpression: z.ZodType<Expression> = z.lazy(() => z.union([
  z.object({ op: z.literal("compare"), comparator: z.enum([">", "<", ">=", "<=", "==", "!=", "cross_above", "cross_below"]), left: operand, right: operand }).strict(),
  z.object({ op: z.enum(["and", "or", "xor"]), args: z.array(recursiveExpression).min(2).max(32) }).strict(),
  z.object({ op: z.literal("not"), arg: recursiveExpression }).strict(),
]));
const expression = z.unknown().refine(boundedTree, "Expression exceeds depth/node limits").pipe(recursiveExpression);

export const configurationSchema = z.object({
  version: z.literal(PROTOCOL_VERSION),
  name: z.string().trim().min(1).max(70),
  engine: z.object({ kind: z.literal("custom"), runtime: z.literal(ENGINE_RUNTIME), signalTiming: z.literal("closed_bar"), buy: expression, sell: expression }).strict(),
  timeframe: z.enum(["M1", "M5", "M15", "M30", "H1", "H4", "D1"]),
  geometry: z.object({ stopPips: positive, targetR: positive }).strict(),
  positions: z.object({ mode: z.enum(["single", "independent"]), maxSameDirectionOpen: z.number().int().min(1).max(100), reverseExit: z.object({ enabled: z.boolean(), waitMinutes: z.number().int().min(0).max(10080) }).strict() }).strict(),
  brokerTime: z.object({ baseUtcOffsetMinutes: z.number().int().min(-840).max(840).multipleOf(15), dst: z.enum(["none", "us", "eu", "sydney", "auckland"]) }).strict(),
  timeMatrix: z.object({ enabled: z.boolean(), dayHourMasks: z.array(z.number().int().min(0).max(0xffffff)).length(7) }).strict(),
}).strict();
export type Configuration = z.infer<typeof configurationSchema>;

const legacyBacktestRequestSchema = z.object({
  version: z.literal(PROTOCOL_VERSION),
  installationId: identifier,
  idempotencyKey: identifier,
  brokerServer: z.string().trim().min(1).max(100),
  symbol: z.string().regex(/^[A-Za-z0-9._#-]{1,64}$/),
  fromUtc: z.string().datetime(),
  toUtc: z.string().datetime(),
  dataPolicy: z.literal("real_ticks_only"),
  configuration: configurationSchema,
}).strict().superRefine((v, ctx) => {
  const start = Date.parse(v.fromUtc), end = Date.parse(v.toUtc);
  if (end <= start || end - start > 3660 * 86400000) ctx.addIssue({ code: "custom", message: "Date range must be positive and at most ten years" });
});
export type BacktestRequest = z.infer<typeof backtestRequestSchema>;
export const backtestRequestSchema = z.union([legacyBacktestRequestSchema, universalRequestSchema]);

export const pairingRequestSchema = z.object({ publicKey: z.string().min(50).max(1024), label: z.string().trim().min(1).max(80) }).strict();
export const pairingCodeSchema = z.string().regex(/^[A-F0-9]{4}-[A-F0-9]{4}$/);
export const deviceProofSchema = z.object({
  version: z.literal(PROTOCOL_VERSION), installationId: identifier, method: z.enum(["GET", "POST"]),
  path: z.string().regex(/^\/v1\/device\/[a-z0-9/-]+$/), bodyHash: digest,
  issuedAt: integer, nonce: identifier, signature: z.string().regex(/^[A-Za-z0-9_-]{86}$/),
}).strict();
export type DeviceProof = z.infer<typeof deviceProofSchema>;

export const progressSchema = z.object({
  jobId: identifier, attemptId: identifier,
  phase: z.enum(["preparing", "downloading", "replaying", "uploading"]),
  processed: integer, total: integer.nullable(),
}).strict().refine(v => v.total === null || v.processed <= v.total, "Processed work exceeds total");
export type Progress = z.infer<typeof progressSchema>;

const tradeSchema = z.object({
  id: z.string().min(1).max(80), direction: z.enum(["BUY", "SELL"]),
  signalUtc: z.string().datetime(), entryUtc: z.string().datetime(), exitUtc: z.string().datetime().nullable(),
  entryPrice: positive, exitPrice: positive.nullable(), sl: positive, tp: positive,
  outcome: z.enum(["WIN", "LOSS", "FLAT", "OPEN", "DATA"]),
  exitReason: z.enum(["TP", "SL", "REVERSE", "NAS", "TIME", "OTHER", "OPEN", "DATA"]),
  netR: finite.nullable(), spreadPrice: finite.nonnegative().nullable(),
  slippagePrice: finite.nullable(), commission: finite.nullable(), swap: finite.nullable(),
}).strict().superRefine((v, ctx) => {
  if (Date.parse(v.entryUtc) < Date.parse(v.signalUtc) || (v.exitUtc !== null && Date.parse(v.exitUtc) < Date.parse(v.entryUtc))) ctx.addIssue({ code: "custom", message: "Invalid trade chronology" });
  if ((v.outcome === "WIN" && !(v.netR !== null && v.netR > 0)) || (v.outcome === "LOSS" && !(v.netR !== null && v.netR < 0)) || (v.outcome === "FLAT" && v.netR !== 0)) ctx.addIssue({ code: "custom", message: "Outcome must reflect net PnL after reported costs" });
  if (["WIN", "LOSS", "FLAT"].includes(v.outcome) && (!v.exitUtc || v.exitPrice === null || ["OPEN", "DATA"].includes(v.exitReason))) ctx.addIssue({ code: "custom", message: "Closed trade requires a known exit" });
  if (["OPEN", "DATA"].includes(v.outcome) && v.netR !== null) ctx.addIssue({ code: "custom", message: "Unknown/unclosed outcome cannot be assigned realized R" });
  if (v.outcome === "OPEN" && (v.exitUtc !== null || v.exitPrice !== null || v.exitReason !== "OPEN")) ctx.addIssue({ code: "custom", message: "Open trade cannot have a final exit" });
});
export const resultSchema = z.object({
  jobId: identifier, attemptId: identifier, configurationHash: digest, requestHash: digest,
  engineRuntime: z.enum([ENGINE_RUNTIME, UNIVERSAL_RUNTIME]), auditBuild: z.string().min(1).max(100),
  brokerServer: z.string().min(1).max(100), symbol: z.string().min(1).max(64),
  coverage: z.object({ datasetFingerprint: digest, realTicks: integer, generatedTicks: z.literal(0),
    mode:z.enum(["real_ticks","existing_audit"]).optional(),
    missingIntervals: z.array(z.object({ fromUtc: z.string().datetime(), toUtc: z.string().datetime() }).strict().refine(v => Date.parse(v.fromUtc) < Date.parse(v.toUtc))).max(1000) }).strict(),
  trades: z.array(tradeSchema).max(10000),
}).strict().superRefine((v, ctx) => {
  if (new Set(v.trades.map(t => t.id)).size !== v.trades.length) ctx.addIssue({ code: "custom", message: "Duplicate trade ids" });
});
export type BacktestResult = z.infer<typeof resultSchema>;

export function summarizeResult(result: BacktestResult) {
  let wins = 0, losses = 0, flat = 0, open = 0, data = 0, netR = 0, cumulative = 0, peak = 0, maxClosedDrawdownR = 0;
  const closed = result.trades.filter(t => ["WIN", "LOSS", "FLAT"].includes(t.outcome)).sort((a, b) => Date.parse(a.exitUtc!) - Date.parse(b.exitUtc!) || a.id.localeCompare(b.id));
  for (const trade of result.trades) {
    if (trade.outcome === "WIN") wins++; else if (trade.outcome === "LOSS") losses++; else if (trade.outcome === "FLAT") flat++; else if (trade.outcome === "OPEN") open++; else data++;
  }
  for (const trade of closed) { netR += trade.netR!; cumulative += trade.netR!; peak = Math.max(peak, cumulative); maxClosedDrawdownR = Math.max(maxClosedDrawdownR, peak - cumulative); }
  return { wins, losses, flat, open, data, netR, maxClosedDrawdownR, winRate: wins + losses ? wins / (wins + losses) * 100 : null,
    trust: "client_reported" as const, coverageComplete: result.coverage.missingIntervals.length === 0 };
}
