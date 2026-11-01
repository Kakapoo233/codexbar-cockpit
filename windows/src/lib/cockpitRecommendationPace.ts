import { localCalendarDay, type CockpitDailyPlanStatus } from "./cockpitDailyPlan";

/** Today's observed use against the current automatic full-day recommendation.
 * Values are percentage points of weekly quota, not a daily utilization ratio.
 * The caller must first match the local Codex main pool and account/cycle.
 */
export interface CockpitRecommendationPace {
  suggestedPercent: number;
  observedUsedPercent: number;
  expectedUsedPercent: number;
  deltaPercent: number;
  elapsedDayFraction: number;
  /** True use may be greater than recorded; a negative bound cannot prove a reserve. */
  isLowerBound: boolean;
}

/** Port of CodexBarCore/CockpitRecommendationPace (MIT).
 * The comfort curve sets the full-day target; elapsed local time advances its
 * reference without reducing that target. This is not an account exhaustion ETA.
 */
export function buildCockpitRecommendationPace(
  status: CockpitDailyPlanStatus | null | undefined,
  now: Date | number,
  accountResetAt: string | null | undefined,
  timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone,
): CockpitRecommendationPace | null {
  const timestamp = now instanceof Date ? now.getTime() : now;
  const reset = accountResetAt ? Date.parse(accountResetAt) : Number.NaN;
  if (!status || !Number.isFinite(timestamp) || status.isStale
    || status.coverage === "unavailable"
    || status.suggestedPercent === null || !Number.isFinite(status.suggestedPercent) || status.suggestedPercent < 0
    || status.usedPercent === null || !Number.isFinite(status.usedPercent) || status.usedPercent < 0
    || !Number.isFinite(reset) || reset <= timestamp
    || status.timeZoneIdentifier !== timeZone) return null;

  if (status.planningResetWindow) {
    const horizon = Date.parse(status.planningResetWindow.resetsAt);
    if (!Number.isFinite(horizon) || horizon <= timestamp) return null;
  }

  // A malformed or obsolete zone must not turn an unavailable plan into a new reference.
  let day: ReturnType<typeof localCalendarDay>;
  try { day = localCalendarDay(timestamp, timeZone); } catch { return null; }
  const duration = day.end - day.start;
  if (status.localDateKey !== day.localDateKey || !Number.isFinite(duration) || duration <= 0) return null;
  const elapsedDayFraction = Math.min(1, Math.max(0, (timestamp - day.start) / duration));
  const expectedUsedPercent = status.suggestedPercent * elapsedDayFraction;
  const deltaPercent = status.usedPercent - expectedUsedPercent;
  if (!Number.isFinite(expectedUsedPercent) || !Number.isFinite(deltaPercent)) return null;
  return {
    suggestedPercent: status.suggestedPercent,
    observedUsedPercent: status.usedPercent,
    expectedUsedPercent,
    deltaPercent,
    elapsedDayFraction,
    isLowerBound: status.coverage !== "complete" || status.suggestionIsPartial,
  };
}
