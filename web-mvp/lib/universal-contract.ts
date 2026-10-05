import { z } from "zod";
import rawCatalog from "./ea-controls.json" with { type: "json" };

export type Family = "orb" | "macross" | "sol" | "entrylab";
export type Control = { key: string; type: string; default: number | string | boolean; group: string; description?: string; options?: { label: string; value: number }[] };
export const eaCatalog = rawCatalog as Record<Family, { inputs: Control[]; runtime: Control[] }>;
export const UNIVERSAL_RUNTIME = "universal-adapter/v2";
const scalar = z.union([z.string().max(200).refine(s => !/[\r\n\x00]/.test(s)), z.number().finite(), z.boolean()]);
const line = z.string().refine(s => !/[\r\n\x00]/.test(s), "Line breaks are not allowed");
const rule = z.object({ feature: z.number().int().min(0).max(43), comparator: z.number().int().min(0).max(7), threshold: z.number().finite(),
  gate: z.number().int().min(0).max(2), negate: z.boolean(), period: z.number().int().min(1).max(5000),
  rhsFeature: z.number().int().min(-1).max(43), rhsPeriod: z.number().int().min(1).max(5000) }).strict();
export const builderSchema = z.object({ edge: z.boolean(), buy: z.array(rule).min(1).max(256), sell: z.array(rule).min(1).max(256),
  exitBuy: z.array(rule).max(256), exitSell: z.array(rule).max(256), exitsEnabled: z.boolean(),
  policy: z.boolean(), atrPeriod: z.number().int().min(1).max(5000), slAtr: z.number().positive(), tpAtr: z.number().positive(),
  cooldown: z.number().int().min(0).max(5000), maxBars: z.number().int().min(0).max(5000), maxMinutes: z.number().int().min(0).max(10080) }).strict();
export const universalConfigurationSchema = z.object({
  version: z.literal(2), name: line.pipe(z.string().trim().min(1).max(70)), family: z.enum(["orb", "macross", "sol", "entrylab"]),
  inputs: z.record(scalar), runtime: z.record(scalar),
  dayHourMasks: z.array(z.number().int().min(0).max(0xffffff)).length(7), builder: builderSchema.nullable(),
}).strict().superRefine((c, ctx) => {
  for (const group of ["inputs", "runtime"] as const) {
    const specs = eaCatalog[c.family][group], keys = Object.keys(c[group]);
    if (keys.length !== specs.length || keys.some(k => !specs.some(s => s.key === k))) {
      ctx.addIssue({ code: "custom", message: `Incomplete or unknown ${group} settings` }); continue;
    }
    for (const s of specs) {
      const v = c[group][s.key];
      const correct = s.type === "bool" ? typeof v === "boolean" : s.type === "string" ? typeof v === "string" : typeof v === "number" && Number.isFinite(v) && (s.type === "double" || Number.isInteger(v));
      if (!correct || (s.options?.length && !s.options.some(o => o.value === v))) ctx.addIssue({ code: "custom", message: `Invalid ${s.key}` });
      if (typeof v === "number" && Math.abs(v) > 1e12) ctx.addIssue({ code: "custom", message: `${s.key} exceeds numeric range` });
    }
  }
  const r = c.runtime;
  for (const k of ["targetR", "nasStateMultiplier", "nasFlowMultiplier"]) if (!(Number(r[k]) > 0)) ctx.addIssue({ code: "custom", message: `${k} must be positive` });
  if (!(Number(r.maxOpen) >= 1 && Number(r.maxOpen) <= 1000)) ctx.addIssue({ code: "custom", message: "MAX OPEN must be 1..1000" });
  if (Number(r.balance) < 0 || Number(r.inverseMaxCostPct) < 0 || Number(r.inverseMaxCostPct) > 100) ctx.addIssue({ code: "custom", message: "Invalid balance or inverse cost limit" });
  for (const k of ["nasGate","nasExit"]) if (![0,1,2].includes(Number(r[k]))) ctx.addIssue({ code: "custom", message: `Invalid ${k}` });
  for (const k of ["nasWaitMinutes","reverseWaitMinutes","nasAgeMinutes"]) if (Number(r[k]) < 0 || Number(r[k]) > 5999) ctx.addIssue({ code: "custom", message: `Invalid ${k}` });
  if (!(Number(r.nasSensitivity) >= 1 && Number(r.nasSensitivity) <= 100)) ctx.addIssue({ code: "custom", message: "Invalid NAS sensitivity" });
  if (c.family === "sol" && (Number(r.nasWaitMinutes)>1440 || Number(r.nasStateMultiplier)>100 || Number(r.nasFlowMultiplier)>100)) ctx.addIssue({ code:"custom", message:"Sol NAS wait must be <=24 hours and volume multipliers <=100" });
  if (c.inputs.InpPipSlModeDefault && !(Number(c.inputs.InpPipSlPips) > 0)) ctx.addIssue({ code: "custom", message: "SL pips must be positive" });
  if (Number(c.inputs.InpRiskPerTradePct) <= 0 || Number(c.inputs.InpRiskPerTradePct) > 100) ctx.addIssue({ code: "custom", message: "Risk must be >0 and <=100%" });
  if (c.family === "entrylab" && !(Number(r.entryPreset)>=0&&Number(r.entryPreset)<=10)) ctx.addIssue({code:"custom",message:"Invalid EntryLab preset"});
  if (c.family === "entrylab" && c.inputs.InpMaCrossMode === 6 && !Number(r.entryPreset) && !c.builder) ctx.addIssue({ code: "custom", message: "Custom engine needs BUY and SELL rules" });
  if (c.family !== "entrylab" && (c.builder || c.inputs.InpMaCrossMode === 6)) ctx.addIssue({ code: "custom", message: "Custom rules belong to EntryLab" });
});
export type UniversalConfiguration = z.infer<typeof universalConfigurationSchema>;
export function defaultConfiguration(family: Family): UniversalConfiguration {
  return { version: 2, family, name: "Untitled setup", inputs: Object.fromEntries(eaCatalog[family].inputs.map(s => [s.key, s.default])),
    runtime: Object.fromEntries(eaCatalog[family].runtime.map(s => [s.key, s.default])), dayHourMasks: Array(7).fill(0xffffff), builder: null };
}
export const universalRequestSchema = z.object({ version: z.literal(2), installationId: z.string().uuid(), idempotencyKey: z.string().uuid(),
  brokerServer: line.pipe(z.string().trim().min(1).max(100)), symbol: z.string().regex(/^[A-Za-z0-9._#-]{1,64}$/),
  fromUtc: z.string().datetime(), toUtc: z.string().datetime(), dataPolicy: z.literal("existing_audit_semantics"),
  auditWeeks: z.union([z.literal(2),z.literal(5),z.literal(10),z.literal(20),z.literal(52),z.literal(104),z.literal(156),z.literal(208),z.literal(260)]),
  configuration: universalConfigurationSchema,
}).strict().superRefine((v,ctx) => {
  if (Date.parse(v.toUtc)-Date.parse(v.fromUtc)!==v.auditWeeks*7*86400000) ctx.addIssue({ code:"custom", message:"Audit bounds must match the selected time window" });
});
