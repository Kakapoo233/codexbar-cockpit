/** Current fork's full-local-day planner. Port of CodexBarCore/Cockpit (MIT).
 * Only official, explicitly account-scoped quota observations enter this model.
 * Token totals and unscoped upstream history never establish quota consumption.
 */
import type { ResetForecast } from "../types";
export type CockpitCoverage = "complete" | "partial" | "unavailable";
export interface CockpitQuotaObservation {
  providerID: string;
  accountID: string;
  capturedAt: string;
  remainingPercent: number;
  resetsAt: string;
  windowDurationSeconds?: number;
  coverage: CockpitCoverage;
}
export interface CockpitCalendarDay {
  localDateKey: string;
  timeZoneIdentifier: string;
  start: number;
  end: number;
  isWeekend: boolean;
}
export interface CockpitResetSignal {
  /** Parsed status feed, not free-form website watch text. */
  status?: {
    generatedAt: string;
    scheduled?: { status: string; kind: string; announcedAt: string; resetsAt: string | null } | null;
    watch?: { level: string; observedAt: string; expiresAt: string; riskPercent: number | null } | null;
    latestRegularResetAt?: string | null;
  } | null;
  forecast?: { resetsAt: string; anchorAt: string; generatedAt: string; fetchedAt: string } | null;
}
export interface CockpitComfortObservation {
  providerID: string;
  accountID: string;
  localDateKey: string;
  timeZoneIdentifier: string;
  recordedAt: string;
  usedPercent: number | null;
  feeling: "overloaded" | "comfortable" | "light";
  coverage: CockpitCoverage;
}
export interface CockpitDailyPlanInput {
  providerID: string;
  accountID: string | null | undefined;
  now: Date | number;
  snapshots: readonly CockpitQuotaObservation[];
  /** Pass only a cap explicitly set for this account and local date. */
  personalCapPercent?: number | null;
  comfortKneePercent?: number;
  comfortRecords?: readonly CockpitComfortObservation[];
  resetSignal?: CockpitResetSignal;
  timeZone?: string;
}
export interface CockpitDailyPlanStatus {
  localDateKey: string;
  timeZoneIdentifier: string;
  suggestedPercent: number | null;
  manualCapPercent: number | null;
  effectiveCapPercent: number | null;
  usedPercent: number | null;
  coverage: CockpitCoverage;
  sampleCount: number;
  remainingPercent: number | null;
  remainingSuggestedPercent: number | null;
  remainingDailyBudgetPercent: number | null;
  isStale: boolean;
  suggestionIsPartial: boolean;
  planningResetWindow: { resetsAt: string; source: "account" | "announced" | "estimated" } | null;
  comfortAdvice: {
    kneePercent: number;
    softCapPercent: number;
    baseDailyPercent: number;
    riskBonusPercent: number;
    riskProbability: number;
    riskSource: "assumed" | "announced" | "estimated";
    isWeekend: boolean;
  } | null;
}
const DAY = 86_400_000;
const MAX_GAP = 1_800_000;
const numberIn = (value: unknown, low: number, high: number): value is number =>
  typeof value === "number" && Number.isFinite(value) && value >= low && value <= high;
const round = (value: number) => Math.round(value * 100) / 100;
const at = (value: string | null | undefined) => value ? Date.parse(value) : Number.NaN;
const goodScope = (value: unknown): value is string => typeof value === "string"
  && value.trim().length > 0 && value.length <= 256 && !["unidentified", "local-machine"].includes(value);

/** Validate and compact persisted observations without assigning legacy data to today's account. */
export function normalizeCockpitQuotaObservations(value: unknown, limit = 8192): CockpitQuotaObservation[] {
  if (!Array.isArray(value)) return [];
  const unique = new Map<string, CockpitQuotaObservation>();
  for (const item of value) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const row = item as Record<string, unknown>;
    if (!goodScope(row.providerID) || !goodScope(row.accountID)
      || typeof row.capturedAt !== "string" || typeof row.resetsAt !== "string"
      || !numberIn(row.remainingPercent, 0, 100)
      || !["complete", "partial"].includes(String(row.coverage))) continue;
    const captured = at(row.capturedAt), reset = at(row.resetsAt);
    const duration = row.windowDurationSeconds ?? 604800;
    if (!Number.isFinite(captured) || !Number.isFinite(reset) || !numberIn(duration, 0.001, Number.MAX_SAFE_INTEGER)
      || reset <= captured || reset - captured > (duration + 300) * 1000) continue;
    const candidate: CockpitQuotaObservation = {
      providerID: row.providerID, accountID: row.accountID,
      capturedAt: new Date(captured).toISOString(), resetsAt: new Date(reset).toISOString(),
      remainingPercent: row.remainingPercent, windowDurationSeconds: duration,
      coverage: row.coverage as CockpitCoverage,
    };
    const key = `${candidate.providerID}\u001f${candidate.accountID}\u001f${captured}`;
    const previous = unique.get(key);
    // Same-time rebounds cannot erase an already observed high-water usage mark.
    if (!previous || previous.remainingPercent > candidate.remainingPercent) unique.set(key, candidate);
  }
  const count = Number.isFinite(limit) ? Math.max(0, Math.min(8192, Math.floor(limit))) : 8192;
  return count === 0 ? [] : [...unique.values()].sort((a, b) => at(a.capturedAt) - at(b.capturedAt)).slice(-count);
}

/** Adapt parsed upstream metadata. A descriptive forecast window is never an exact reset date. */
export function cockpitResetSignal(forecast: ResetForecast | null | undefined): CockpitResetSignal | undefined {
  if (!forecast) return undefined;
  const watch = forecast.activeWatch;
  return { status: {
    generatedAt: forecast.watchCheckedAt ?? forecast.fetchedAt,
    scheduled: forecast.resetAnnounced ? {
      status: "scheduled", kind: "regular", announcedAt: forecast.fetchedAt,
      resetsAt: forecast.resetAt ?? null,
    } : null,
    watch: watch ? { level: watch.level, observedAt: watch.observedAt, expiresAt: watch.expiresAt, riskPercent: watch.resetChancePercent } : null,
  } };
}

function calendarParts(timestamp: number, timeZone: string) {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" }).formatToParts(timestamp);
  const get = (type: string) => Number(parts.find(part => part.type === type)?.value);
  return { year: get("year"), month: get("month"), day: get("day"), hour: get("hour"), minute: get("minute"), second: get("second") };
}
function midnight(year: number, month: number, day: number, zone: string): number {
  const target = Date.UTC(year, month - 1, day);
  let candidate = target;
  for (let pass = 0; pass < 5; pass += 1) {
    const p = calendarParts(candidate, zone);
    const offset = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - candidate;
    const corrected = target - offset;
    if (corrected === candidate) break;
    candidate = corrected;
  }
  return candidate;
}
/** Personal planning uses local natural days, independently of the team's Shanghai day. */
export function localCalendarDay(now: Date | number, timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone): CockpitCalendarDay {
  const timestamp = now instanceof Date ? now.getTime() : now;
  if (!Number.isFinite(timestamp)) throw new RangeError("Invalid planning date");
  const p = calendarParts(timestamp, timeZone);
  const date = new Date(Date.UTC(p.year, p.month - 1, p.day));
  const tomorrow = new Date(Date.UTC(p.year, p.month - 1, p.day + 1));
  return {
    localDateKey: `${p.year}-${String(p.month).padStart(2, "0")}-${String(p.day).padStart(2, "0")}`,
    timeZoneIdentifier: timeZone,
    start: midnight(p.year, p.month, p.day, timeZone),
    end: midnight(tomorrow.getUTCFullYear(), tomorrow.getUTCMonth() + 1, tomorrow.getUTCDate(), timeZone),
    isWeekend: [0, 6].includes(date.getUTCDay()),
  };
}
interface Segment { points: CockpitQuotaObservation[]; latestReset: number; observedReset: boolean; drift: boolean }
function segments(points: readonly CockpitQuotaObservation[]): Segment[] {
  if (!points.length) return [];
  const result: Segment[] = [];
  let previous = points[0];
  let current: Segment = { points: [previous], latestReset: at(previous.resetsAt), observedReset: false, drift: false };
  for (const point of points.slice(1)) {
    const captured = at(point.capturedAt), reset = at(point.resetsAt);
    const cycleStart = reset - (point.windowDurationSeconds ?? 604800) * 1000;
    if (reset - current.latestReset > 60000 && (captured >= current.latestReset || (cycleStart > at(previous.capturedAt) && cycleStart <= captured))) {
      result.push(current);
      current = { points: [point], latestReset: reset, observedReset: true, drift: false };
    } else {
      current.drift ||= point.resetsAt !== previous.resetsAt || point.windowDurationSeconds !== previous.windowDurationSeconds;
      current.points.push(point);
      current.latestReset = Math.max(current.latestReset, reset);
    }
    previous = point;
  }
  return [...result, current];
}
function observed(segment: Segment, day: CockpitCalendarDay) {
  const first = segment.points[0];
  const beginsToday = at(first.capturedAt) > day.start && at(first.resetsAt) - (first.windowDurationSeconds ?? 604800) * 1000 >= day.start;
  const baseline = segment.observedReset || beginsToday ? 0 : 100 - first.remainingPercent;
  return {
    percent: Math.max(0, Math.max(...segment.points.map(point => 100 - point.remainingPercent)) - baseline),
    known: segment.observedReset || beginsToday || segment.points.length > 1 || at(first.capturedAt) === day.start,
  };
}
function fresh(timestamp: string | undefined, now: number, maxAge: number) {
  const age = now - at(timestamp);
  return age >= -300000 && age <= maxAge;
}
function resetPolicy(providerID: string, accountReset: number, now: number, signal?: CockpitResetSignal) {
  let reset = accountReset, source: "account" | "announced" | "estimated" = "account";
  let probability = providerID === "codex" ? 0.1 : 0;
  let riskSource: "assumed" | "announced" | "estimated" = "assumed";
  if (providerID !== "codex" || !signal) return { reset, source, probability, riskSource };
  const status = signal.status;
  const scheduled = status?.scheduled;
  const pending = scheduled?.status === "scheduled" && scheduled.kind === "regular" && at(scheduled.announcedAt) <= now + 300000;
  const statusFresh = status && fresh(status.generatedAt, now, 900000);
  if (statusFresh && pending) {
    const deadline = at(scheduled.resetsAt);
    if (deadline > now && deadline < accountReset) {
      reset = deadline; source = "announced";
      if (deadline - now <= DAY) { probability = 1; riskSource = "announced"; }
    }
    // Even an undated announcement blocks a conflicting historical estimate/watch probability.
    return { reset, source, probability, riskSource };
  }
  const forecast = signal.forecast;
  if (!(pending && !statusFresh) && forecast
    && fresh(forecast.generatedAt, now, DAY) && fresh(forecast.fetchedAt, now, 1800000)
    && at(forecast.anchorAt) <= now && at(forecast.resetsAt) > now && at(forecast.resetsAt) < accountReset
    && !(status?.latestRegularResetAt && at(status.latestRegularResetAt) > at(forecast.anchorAt))) {
    reset = at(forecast.resetsAt); source = "estimated";
  }
  const watch = status?.watch;
  if (statusFresh && watch && ["elevated", "strong"].includes(watch.level)
    && at(watch.observedAt) <= now + 300000 && at(watch.expiresAt) > now && numberIn(watch.riskPercent, 0, 100)) {
    probability = watch.riskPercent / 100; riskSource = "estimated";
  }
  return { reset, source, probability, riskSource };
}

export function cockpitComfortScore(usedPercent: number, kneePercent = 25): number {
  if (!numberIn(usedPercent, 0, Number.MAX_VALUE) || !Number.isFinite(kneePercent)) return 0;
  const knee = Math.min(100, Math.max(0.1, kneePercent)) / 100;
  const shoulder = (input: number) => { const v = (input - knee) / 0.02; return 0.02 * (v > 30 ? v : Math.log1p(Math.exp(v))); };
  const response = (input: number) => Math.exp(-4.3 * input ** 1.5);
  const low = response(shoulder(0)), high = response(shoulder(1));
  if (Math.abs(low - high) < 1e-12) return 0.2;
  return Math.min(1, Math.max(0.2, 0.2 + 0.8 * (response(shoulder(usedPercent / 100)) - high) / (low - high)));
}
/** Fixed subjective scores and 14-day recency weighting, scoped to provider/account/timezone. */
export function fitCockpitComfortKnee(records: readonly CockpitComfortObservation[], providerID: string, accountID: string, now: Date | number, timeZone?: string): number {
  const day = localCalendarDay(now, timeZone), timestamp = now instanceof Date ? now.getTime() : now;
  const unique = new Map<string, CockpitComfortObservation>();
  for (const record of records) {
    if (record.providerID !== providerID || record.accountID !== accountID || record.timeZoneIdentifier !== day.timeZoneIdentifier
      || !Number.isFinite(at(record.recordedAt)) || at(record.recordedAt) > timestamp) continue;
    const prior = unique.get(record.localDateKey);
    if (!prior || at(prior.recordedAt) < at(record.recordedAt)) unique.set(record.localDateKey, record);
  }
  const todayIndex = Date.parse(`${day.localDateKey}T00:00:00Z`) / DAY;
  const observations = [...unique.values()].sort((a, b) => a.localDateKey.localeCompare(b.localDateKey)).slice(-90).flatMap(record => {
    const date = Date.parse(`${record.localDateKey}T00:00:00Z`), age = todayIndex - date / DAY;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(record.localDateKey) || !Number.isFinite(date)
      || new Date(date).toISOString().slice(0, 10) !== record.localDateKey || age < 0
      || !numberIn(record.usedPercent, 0, 10000) || record.coverage === "unavailable") return [];
    const score = { overloaded: 0.25, comfortable: 0.8, light: 1 }[record.feeling];
    if (!Number.isFinite(score)) return [];
    return [{ used: record.usedPercent, score, weight: (record.coverage === "complete" ? 1 : 0.75) * 2 ** (-age / 14) }];
  });
  if (!observations.length) return 25;
  let best = -Infinity, knee = 25;
  for (let step = 1; step <= 1000; step += 1) {
    const candidate = step / 10;
    const score = -observations.reduce((sum, item) => sum + item.weight * (cockpitComfortScore(item.used, candidate) - item.score) ** 2, 0) / (2 * 0.15 ** 2);
    if (score > best + 1e-10 || (Math.abs(score - best) <= 1e-10 && Math.abs(candidate - 25) < Math.abs(knee - 25))) { best = score; knee = candidate; }
  }
  return knee;
}

export function buildCockpitDailyPlan(input: CockpitDailyPlanInput): CockpitDailyPlanStatus {
  const now = input.now instanceof Date ? input.now.getTime() : input.now;
  const day = localCalendarDay(now, input.timeZone);
  const empty: CockpitDailyPlanStatus = {
    localDateKey: day.localDateKey, timeZoneIdentifier: day.timeZoneIdentifier,
    suggestedPercent: null, manualCapPercent: null, effectiveCapPercent: null, usedPercent: null,
    coverage: "unavailable", sampleCount: 0, remainingPercent: null, remainingSuggestedPercent: null,
    remainingDailyBudgetPercent: null, isStale: true, suggestionIsPartial: false,
    planningResetWindow: null, comfortAdvice: null,
  };
  if (!goodScope(input.providerID) || !goodScope(input.accountID)) return empty;
  const points = normalizeCockpitQuotaObservations(input.snapshots).filter(point => point.providerID === input.providerID
    && point.accountID === input.accountID && at(point.capturedAt) <= now);
  const today = points.filter(point => at(point.capturedAt) >= day.start && at(point.capturedAt) < day.end);
  const groups = segments(today);
  let used = 0, known = false;
  let complete = today.length > 0 && at(today[0].capturedAt) === day.start && now - at(today[today.length - 1].capturedAt) <= MAX_GAP;
  let previous = today[0];
  for (const point of today) {
    if (at(point.capturedAt) - at(previous.capturedAt) > MAX_GAP || point.coverage !== "complete") complete = false;
    previous = point;
  }
  for (const group of groups) {
    const usage = observed(group, day); used += usage.percent; known ||= usage.known;
    if (group.drift) complete = false;
  }
  const usedPercent = known ? round(used) : null;
  const coverage: CockpitCoverage = !today.length ? "unavailable" : complete ? "complete" : "partial";
  const latest = points[points.length - 1];
  const usable = latest && at(latest.resetsAt) > now ? latest : null;
  const manual = numberIn(input.personalCapPercent, 0, 100) ? input.personalCapPercent : null;
  const policy = usable ? resetPolicy(input.providerID, at(usable.resetsAt), now, input.resetSignal) : null;
  const knee = numberIn(input.comfortKneePercent, 0.1, 100) ? input.comfortKneePercent
    : fitCockpitComfortKnee(input.comfortRecords ?? [], input.providerID, input.accountID, now, day.timeZoneIdentifier);
  const currentCycleUsed = groups.length ? round(observed(groups[groups.length - 1], day).percent) : 0;
  const priorCycleUsed = Math.max(0, (usedPercent ?? 0) - currentCycleUsed);
  const pool = usable ? Math.min(100, usable.remainingPercent + currentCycleUsed) : 0;
  const share = policy ? pool * Math.min(1, (day.end - day.start) / (policy.reset - now)) : 0;
  const advice: CockpitDailyPlanStatus["comfortAdvice"] = policy ? {
    kneePercent: knee,
    softCapPercent: knee * (1 + 1.5 * policy.probability) * (day.isWeekend ? 0.75 : 1),
    baseDailyPercent: priorCycleUsed + share,
    riskBonusPercent: (pool - share) * policy.probability ** 2,
    riskProbability: policy.probability, riskSource: policy.riskSource, isWeekend: day.isWeekend,
  } : null;
  const suggested = advice ? round(Math.min(advice.softCapPercent, advice.baseDailyPercent + advice.riskBonusPercent)) : null;
  const effective = manual ?? suggested;
  const available = effective !== null && usedPercent !== null && usable ? Math.min(usable.remainingPercent, Math.max(0, effective - usedPercent)) : null;
  const daily = available !== null && effective !== null ? effective > 0 ? round(Math.min(100, Math.max(0, available / effective * 100))) : 0 : null;
  return {
    ...empty, suggestedPercent: suggested, manualCapPercent: manual, effectiveCapPercent: effective,
    usedPercent, coverage, sampleCount: today.length, remainingPercent: usable?.remainingPercent ?? null,
    remainingSuggestedPercent: available, remainingDailyBudgetPercent: daily,
    isStale: usable ? now - at(usable.capturedAt) > MAX_GAP : true,
    suggestionIsPartial: suggested !== null && (usedPercent === null || coverage !== "complete"),
    planningResetWindow: policy ? { resetsAt: new Date(policy.reset).toISOString(), source: policy.source } : null,
    comfortAdvice: advice,
  };
}
