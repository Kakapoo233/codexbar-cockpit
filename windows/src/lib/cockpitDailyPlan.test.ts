import { describe, expect, it } from "vitest";
import { buildCockpitDailyPlan, cockpitResetSignal, fitCockpitComfortKnee, localCalendarDay, normalizeCockpitQuotaObservations, type CockpitComfortObservation, type CockpitQuotaObservation, type CockpitResetSignal } from "./cockpitDailyPlan";
import { normalizeRuntimeState } from "./activity";
import { COMFORT_CURVE_VERSION, normalizeComfortFeedbackRecords } from "./comfortFeedback";

const START = Date.parse("2026-11-02T00:00:00Z");
const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const NOW = START + 8 * HOUR;
const RESET = NOW + 6 * DAY;
const iso = (value: number) => new Date(value).toISOString();
function sample(hours: number, remainingPercent = 90, resetsAt = RESET, accountID = "account-a"): CockpitQuotaObservation {
  return { providerID: "codex", accountID, capturedAt: iso(START + hours * HOUR), remainingPercent, resetsAt: iso(resetsAt), windowDurationSeconds: 604800, coverage: "complete" };
}
function plan(snapshots: CockpitQuotaObservation[], options: Partial<Parameters<typeof buildCockpitDailyPlan>[0]> = {}) {
  return buildCockpitDailyPlan({ providerID: "codex", accountID: "account-a", now: NOW, timeZone: "UTC", snapshots, ...options });
}
function continuous(remainingAtEnd = 90) {
  return Array.from({ length: 17 }, (_, index) => sample(index / 2, index === 16 ? remainingAtEnd : 90));
}

describe("fork full-local-day planning", () => {
  it("uses daily allocation as denominator and retains weekly equivalent", () => {
    const status = plan(continuous(85), { personalCapPercent: 20 });
    expect(status.usedPercent).toBe(5);
    expect(status.remainingSuggestedPercent).toBe(15);
    expect(status.remainingDailyBudgetPercent).toBe(75);
    expect(status.coverage).toBe("complete");
    expect(status.isStale).toBe(false);
  });

  it("allocates a full day and does not shrink it merely because evening arrives", () => {
    const morning = plan(continuous(), { resetSignal: { status: { generatedAt: iso(NOW), watch: { level: "elevated", observedAt: iso(NOW), expiresAt: iso(NOW + DAY), riskPercent: 0 } } } });
    // Non-Codex policy has the same full-day baseline with risk=0, simplifying comparison.
    const zeroRisk = { status: { generatedAt: iso(NOW), watch: { level: "elevated", observedAt: iso(NOW), expiresAt: iso(NOW + DAY), riskPercent: 0 } } } satisfies CockpitResetSignal;
    const baseline = plan(continuous(), { resetSignal: zeroRisk });
    expect(baseline.suggestedPercent).toBe(15);
    expect(morning.remainingSuggestedPercent).toBe(15);
    const evening = plan(continuous(), { now: START + 22 * HOUR });
    expect(evening.suggestedPercent).toBeGreaterThanOrEqual(baseline.suggestedPercent!);
  });

  it("deducts observed consumption once without increasing the full-day target", () => {
    const zeroRisk: CockpitResetSignal = { status: { generatedAt: iso(NOW), watch: { level: "elevated", observedAt: iso(NOW), expiresAt: iso(NOW + DAY), riskPercent: 0 } } };
    const before = plan(continuous(), { resetSignal: zeroRisk });
    const after = plan(continuous(80), { resetSignal: zeroRisk });
    expect(before.suggestedPercent).toBe(15);
    expect(after.suggestedPercent).toBe(15);
    expect(after.usedPercent).toBe(10);
    expect(after.remainingSuggestedPercent).toBe(5);
  });

  it("keeps earlier reset cycles spent instead of granting a renewed pool", () => {
    const status = plan([
      sample(0, 100, START + 4 * HOUR), sample(3.5, 20, START + 4 * HOUR),
      sample(4, 100, NOW), sample(7.5, 10, NOW), sample(8, 90),
    ], { comfortKneePercent: 100 });
    expect(status.usedPercent).toBe(180);
    expect(status.comfortAdvice?.baseDailyPercent).toBeCloseTo(186.6666667, 5);
    expect(status.remainingSuggestedPercent).toBe(0);
    expect(status.remainingPercent).toBe(90);
  });

  it.each([
    ["2026-03-08T05:00:00Z", 23, 15.33],
    ["2026-11-01T04:00:00Z", 25, 16.67],
  ])("uses actual local-day duration at DST boundary %s", (startText, hours, target) => {
    const start = Date.parse(startText as string), now = start + 8 * HOUR;
    const status = buildCockpitDailyPlan({ providerID: "claude", accountID: "account-a", now, timeZone: "America/New_York", snapshots: [{ ...sample(0, 96), providerID: "claude", capturedAt: iso(start), resetsAt: iso(now + 6 * DAY) }] });
    const day = localCalendarDay(now, "America/New_York");
    expect(day.end - day.start).toBe(Number(hours) * HOUR);
    expect(status.suggestedPercent).toBe(target);
  });

  it("does not turn the first incomplete observation into measured zero use", () => {
    const status = plan([sample(8)]);
    expect(status.suggestedPercent).not.toBeNull();
    expect(status.usedPercent).toBeNull();
    expect(status.remainingDailyBudgetPercent).toBeNull();
    expect(status.suggestionIsPartial).toBe(true);
    expect(status.coverage).toBe("partial");
  });

  it("marks gaps partial and stale observations stale without dropping measured use", () => {
    const status = plan([sample(0), sample(7, 85)]);
    expect(status.usedPercent).toBe(5);
    expect(status.coverage).toBe("partial");
    expect(status.isStale).toBe(true);
    expect(status.remainingDailyBudgetPercent).not.toBeNull();
  });

  it("respects a known zero cap and actual account balance", () => {
    const zero = plan(continuous(85), { personalCapPercent: 0 });
    expect(zero.effectiveCapPercent).toBe(0);
    expect(zero.remainingDailyBudgetPercent).toBe(0);
    const low = plan([sample(8, 2, NOW + HOUR)], { personalCapPercent: 100 });
    // One mid-cycle observation cannot establish how much was consumed today.
    expect(low.usedPercent).toBeNull();
    const known = plan([sample(0, 3, NOW + HOUR), sample(8, 2, NOW + HOUR)], { personalCapPercent: 100 });
    expect(known.remainingSuggestedPercent).toBe(2);
    expect(known.remainingDailyBudgetPercent).toBe(2);
    expect(plan(continuous(), { personalCapPercent: -1 }).manualCapPercent).toBeNull();
  });

  it("does not revive an expired balance after its reset deadline", () => {
    const status = plan([sample(0, 2, START + HOUR)], { personalCapPercent: 100 });
    expect(status.remainingPercent).toBeNull();
    expect(status.suggestedPercent).toBeNull();
    expect(status.remainingDailyBudgetPercent).toBeNull();
  });

  it("isolates accounts, providers, future samples and unknown identity", () => {
    expect(plan([sample(0), sample(8, 10, RESET, "different")]).usedPercent).toBe(0);
    expect(plan([sample(8, 10, RESET, "different")]).remainingPercent).toBeNull();
    expect(plan([sample(8)], { accountID: null }).suggestedPercent).toBeNull();
    expect(plan([sample(9)]).remainingPercent).toBeNull();
    expect(plan([{ ...sample(8), providerID: "claude" }]).remainingPercent).toBeNull();
  });

  it("uses a high-water usage mark for rebounds and never treats metadata drift as reset", () => {
    const status = plan([sample(0), sample(7.5, 80), sample(8, 85, RESET + 30000)]);
    expect(status.usedPercent).toBe(10);
    expect(status.coverage).toBe("partial");
  });

  it("treats incomplete but observed consumption as an upper bound on remaining allowance", () => {
    const status = plan([sample(7.5), sample(8, 85)], { personalCapPercent: 20 });
    expect(status.remainingDailyBudgetPercent).toBe(75);
    expect(status.coverage).toBe("partial");
    expect(status.suggestionIsPartial).toBe(true);
  });
});

describe("reset inputs remain planning signals", () => {
  it("gives fresh dated confirmed resets priority over estimates", () => {
    const signal: CockpitResetSignal = { status: { generatedAt: iso(NOW), scheduled: { kind: "regular", status: "scheduled", announcedAt: iso(NOW - HOUR), resetsAt: iso(NOW + 12 * HOUR) } }, forecast: { resetsAt: iso(NOW + HOUR), anchorAt: iso(NOW - DAY), fetchedAt: iso(NOW), generatedAt: iso(NOW) } };
    const status = plan(continuous(), { resetSignal: signal });
    expect(status.planningResetWindow).toEqual({ resetsAt: iso(NOW + 12 * HOUR), source: "announced" });
    expect(status.comfortAdvice?.riskProbability).toBe(1);
    expect(status.remainingPercent).toBe(90);
  });
  it("shortens the horizon with an estimate without assigning it certain probability", () => {
    const status = plan(continuous(), { resetSignal: { forecast: { resetsAt: iso(NOW + 2 * DAY), anchorAt: iso(NOW - DAY), fetchedAt: iso(NOW), generatedAt: iso(NOW) } } });
    expect(status.planningResetWindow?.source).toBe("estimated");
    expect(status.comfortAdvice?.riskProbability).toBe(0.1);
  });
  it("ignores stale risk and does not make distant announcements certain today", () => {
    const stale = plan(continuous(), { resetSignal: { status: { generatedAt: iso(NOW - HOUR), watch: { level: "strong", observedAt: iso(NOW - HOUR), expiresAt: iso(NOW + DAY), riskPercent: 100 } } } });
    expect(stale.comfortAdvice?.riskProbability).toBe(0.1);
    const distant = plan(continuous(), { resetSignal: { status: { generatedAt: iso(NOW), scheduled: { kind: "regular", status: "scheduled", announcedAt: iso(NOW), resetsAt: iso(NOW + 3 * DAY) } } } });
    expect(distant.planningResetWindow?.source).toBe("announced");
    expect(distant.comfortAdvice?.riskProbability).toBe(0.1);
  });
  it("does not infer an exact deadline from website watch duration", () => {
    const signal = cockpitResetSignal({ score: 80, windowHours: 12, fetchedAt: iso(NOW), resetAnnounced: false, sourceUrl: "https://example.invalid" });
    expect(signal?.forecast).toBeUndefined();
    expect(signal?.status?.scheduled).toBeNull();
  });
});

describe("safe persistence and comfort calibration", () => {
  it("validates observations and preserves same-time high-water marks", () => {
    const rows = normalizeCockpitQuotaObservations([sample(0), sample(0, 80), { ...sample(1), remainingPercent: NaN }, { ...sample(1), accountID: "" }, { ...sample(1), coverage: "unavailable" }]);
    expect(rows).toHaveLength(1);
    expect(rows[0].remainingPercent).toBe(80);
    expect(normalizeCockpitQuotaObservations(rows, 0)).toEqual([]);
    expect(normalizeRuntimeState({ cockpitQuotaObservations: rows }).cockpitQuotaObservations).toEqual(rows);
  });
  it("fits account-scoped comfort and does not revive cleared newer measurements", () => {
    const record: CockpitComfortObservation = { providerID: "codex", accountID: "account-a", localDateKey: "2026-11-01", timeZoneIdentifier: "UTC", recordedAt: iso(START - HOUR), usedPercent: 50, feeling: "comfortable", coverage: "complete" };
    const fit = fitCockpitComfortKnee([record], "codex", "account-a", NOW, "UTC");
    expect(fit).not.toBe(25);
    expect(fitCockpitComfortKnee([record, { ...record, accountID: "other", usedPercent: 1 }], "codex", "account-a", NOW, "UTC")).toBe(fit);
    expect(fitCockpitComfortKnee([record, { ...record, recordedAt: iso(START), usedPercent: null }], "codex", "account-a", NOW, "UTC")).toBe(25);
  });
  it("preserves opaque account scopes across feedback reload and day deduplication", () => {
    const record = { localDate: "2026-11-01", observedAt: iso(START - HOUR), comfort: "comfortable", personId: null, observedUsedPercent: 5, usageObservedAt: iso(START - HOUR), usageCoverage: "complete", usageSource: "official-snapshot", curveVersion: COMFORT_CURVE_VERSION };
    const rows = normalizeComfortFeedbackRecords([{ ...record, accountScope: "a".repeat(64), timeZoneIdentifier: "UTC" }, { ...record, accountScope: "b".repeat(64), timeZoneIdentifier: "America/New_York" }]);
    expect(rows).toHaveLength(2);
    expect(rows.map(row => row.accountScope).sort()).toEqual(["a".repeat(64), "b".repeat(64)]);
    expect(rows.map(row => row.timeZoneIdentifier).sort()).toEqual(["America/New_York", "UTC"]);
  });
});
