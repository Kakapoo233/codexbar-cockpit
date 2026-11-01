import { describe, expect, it } from "vitest";
import { buildCockpitDailyPlan, localCalendarDay, type CockpitDailyPlanStatus, type CockpitQuotaObservation } from "./cockpitDailyPlan";
import { buildCockpitRecommendationPace } from "./cockpitRecommendationPace";

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const NOW = Date.parse("2026-11-02T12:00:00Z");
const RESET = new Date(NOW + 6 * DAY).toISOString();

function status(overrides: Partial<CockpitDailyPlanStatus> = {}, now = NOW, timeZone = "UTC"): CockpitDailyPlanStatus {
  return {
    ...buildCockpitDailyPlan({ providerID: "codex", accountID: "synthetic-owner", now, timeZone, snapshots: [] }),
    suggestedPercent: 20,
    usedPercent: 12,
    coverage: "complete",
    remainingPercent: 60,
    isStale: false,
    planningResetWindow: { resetsAt: new Date(now + DAY).toISOString(), source: "account" },
    ...overrides,
  };
}

function pace(overrides: Partial<CockpitDailyPlanStatus> = {}, now = NOW, timeZone = "UTC") {
  return buildCockpitRecommendationPace(status(overrides, now, timeZone), now, new Date(now + DAY).toISOString(), timeZone);
}

describe("Cockpit recommendation pace parity", () => {
  it("advances the daily reference without shrinking the full-day recommendation", () => {
    expect(pace()).toEqual({
      suggestedPercent: 20,
      observedUsedPercent: 12,
      expectedUsedPercent: 10,
      deltaPercent: 2,
      elapsedDayFraction: 0.5,
      isLowerBound: false,
    });
    const evening = pace({}, NOW + 6 * HOUR)!;
    expect(evening.suggestedPercent).toBe(20);
    expect(evening.expectedUsedPercent).toBe(15);
    expect(evening.deltaPercent).toBe(-3);
  });

  it("uses the new comfort/reset recommendation immediately and leaves a manual cap independent", () => {
    const updated = pace({ suggestedPercent: 40 });
    expect(updated?.expectedUsedPercent).toBe(20);
    expect(updated?.deltaPercent).toBe(-8);
    expect(pace({ suggestedPercent: 40, manualCapPercent: 1, effectiveCapPercent: 1 })).toEqual(updated);
  });

  it("spending the live balance moves pace without awarding a second daily allocation", () => {
    const start = NOW - 12 * HOUR;
    const continuous = (remaining: number): CockpitQuotaObservation[] => Array.from({ length: 25 }, (_, index) => ({
      providerID: "codex", accountID: "synthetic-owner", capturedAt: new Date(start + index * HOUR / 2).toISOString(),
      remainingPercent: index === 24 ? remaining : 90, resetsAt: RESET, windowDurationSeconds: 604800, coverage: "complete",
    }));
    const plan = (remaining: number) => buildCockpitDailyPlan({
      providerID: "codex", accountID: "synthetic-owner", now: NOW, timeZone: "UTC", snapshots: continuous(remaining),
    });
    const before = buildCockpitRecommendationPace(plan(90), NOW, RESET, "UTC")!;
    const after = buildCockpitRecommendationPace(plan(80), NOW, RESET, "UTC")!;
    expect(after.suggestedPercent).toBe(before.suggestedPercent);
    expect(after.expectedUsedPercent).toBe(before.expectedUsedPercent);
    expect(after.observedUsedPercent).toBe(before.observedUsedPercent + 10);
    expect(after.deltaPercent).toBe(before.deltaPercent + 10);
  });

  it("keeps known zero targets and weekly percentage-point units", () => {
    expect(pace({ suggestedPercent: 0, usedPercent: 0 })?.deltaPercent).toBe(0);
    expect(pace({ suggestedPercent: 0, usedPercent: 4 })?.deltaPercent).toBe(4);
    expect(pace({ suggestedPercent: 40, usedPercent: 130 }, NOW + 6 * HOUR)).toMatchObject({
      observedUsedPercent: 130, expectedUsedPercent: 30, deltaPercent: 100,
    });
  });

  it("starts the new local day at zero expected use", () => {
    const midnight = NOW - 12 * HOUR;
    expect(pace({ usedPercent: 0 }, midnight)).toMatchObject({ expectedUsedPercent: 0, deltaPercent: 0, elapsedDayFraction: 0 });
  });

  it.each([
    ["2026-03-08T16:00:00Z", 23, 11],
    ["2026-11-01T17:00:00Z", 25, 13],
  ])("uses actual local-day duration across DST at %s", (date, hours, elapsed) => {
    const now = Date.parse(date as string), timeZone = "America/New_York";
    const day = localCalendarDay(now, timeZone);
    expect(day.end - day.start).toBe(Number(hours) * HOUR);
    const result = pace({}, now, timeZone)!;
    expect(result.elapsedDayFraction).toBeCloseTo(Number(elapsed) / Number(hours), 12);
    expect(result.expectedUsedPercent).toBeCloseTo(20 * Number(elapsed) / Number(hours), 12);
  });

  it("retains one-sided uncertainty even when recorded use is below the reference", () => {
    expect(pace({ usedPercent: 1, coverage: "partial" })).toMatchObject({ deltaPercent: -9, isLowerBound: true });
    expect(pace({ suggestionIsPartial: true })?.isLowerBound).toBe(true);
  });

  it("rejects unavailable stale missing and prior-day plans", () => {
    for (const overrides of [
      { suggestedPercent: null }, { usedPercent: null }, { coverage: "unavailable" as const }, { isStale: true },
      { localDateKey: "2026-11-01" },
    ]) expect(pace(overrides)).toBeNull();
    expect(buildCockpitRecommendationPace(null, NOW, RESET, "UTC")).toBeNull();
    expect(buildCockpitRecommendationPace(undefined, NOW, RESET, "UTC")).toBeNull();
  });

  it("rejects expired actual resets and expired or invalid planning horizons", () => {
    for (const reset of [null, undefined, "invalid", new Date(NOW).toISOString(), new Date(NOW - 1).toISOString()]) {
      expect(buildCockpitRecommendationPace(status(), NOW, reset, "UTC")).toBeNull();
    }
    for (const resetsAt of ["invalid", new Date(NOW).toISOString(), new Date(NOW - 1).toISOString()]) {
      expect(pace({ planningResetWindow: { resetsAt, source: "announced" } })).toBeNull();
    }
  });

  it("rejects a different or malformed local timezone instead of reusing an archived day", () => {
    expect(buildCockpitRecommendationPace(status(), NOW, RESET, "America/New_York")).toBeNull();
    expect(buildCockpitRecommendationPace(status({ timeZoneIdentifier: "invalid/zone" }), NOW, RESET, "invalid/zone")).toBeNull();
  });

  it("rejects nonfinite negative measurements and invalid dates", () => {
    for (const value of [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY, -1]) {
      expect(pace({ suggestedPercent: value })).toBeNull();
      expect(pace({ usedPercent: value })).toBeNull();
    }
    expect(buildCockpitRecommendationPace(status(), Number.NaN, RESET, "UTC")).toBeNull();
    expect(buildCockpitRecommendationPace(status(), new Date(Number.NaN), RESET, "UTC")).toBeNull();
  });
});
