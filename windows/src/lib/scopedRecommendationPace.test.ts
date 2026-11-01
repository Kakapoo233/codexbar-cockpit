import { describe, expect, it } from "vitest";
import type { ProviderSnapshot } from "../types";
import { buildCockpitDailyPlan, type CockpitQuotaObservation } from "./cockpitDailyPlan";
import { buildCockpitRecommendationPace } from "./cockpitRecommendationPace";
import { scopedRecommendationPace } from "./scopedRecommendationPace";

const now = new Date("2026-11-02T12:00:00Z"), reset = "2026-11-07T12:00:00Z";
function fixture() {
  const observations: CockpitQuotaObservation[] = Array.from({ length: 25 }, (_, index) => ({
    providerID: "codex", accountID: "synthetic-owner", coverage: "complete",
    capturedAt: new Date(Date.parse("2026-11-02T00:00:00Z") + index * 1_800_000).toISOString(),
    remainingPercent: 60 - index * 10 / 24, resetsAt: reset, windowDurationSeconds: 604800,
  }));
  const snapshot: ProviderSnapshot = { provider: "codex", accountScope: "synthetic-owner", displayName: "Codex",
    plan: "Synthetic", shortWindow: null, weeklyWindow: { remainingPercent: 50, resetsAt: reset, windowSeconds: 604800 },
    resetCredits: null, updatedAt: now.toISOString(), status: "ok", message: null };
  const plan = buildCockpitDailyPlan({ providerID: "codex", accountID: snapshot.accountScope, snapshots: observations, now, timeZone: "UTC" });
  return { snapshot, observations, plan };
}

describe("local recommendation pace publication", () => {
  it("uses the exact published automatic plan and keeps a manual cap independent", () => {
    const { snapshot, observations, plan } = fixture();
    const result = scopedRecommendationPace(snapshot, plan, observations, now, "UTC");
    expect(result).toEqual(buildCockpitRecommendationPace(plan, now, reset, "UTC"));
    expect(result?.isLowerBound).toBe(false);
    const capped = buildCockpitDailyPlan({ providerID: "codex", accountID: snapshot.accountScope, snapshots: observations,
      now, timeZone: "UTC", personalCapPercent: 1 });
    expect(scopedRecommendationPace(snapshot, capped, observations, now, "UTC")).toEqual(result);
  });

  it("does not borrow a previous account, provider or cycle before ingestion", () => {
    const { snapshot, observations, plan } = fixture();
    const variants: ProviderSnapshot[] = [
      { ...snapshot, accountScope: "another-owner" }, { ...snapshot, provider: "qoder" },
      { ...snapshot, weeklyWindow: { ...snapshot.weeklyWindow!, resetsAt: "2026-11-08T12:00:00Z" } },
      { ...snapshot, weeklyWindow: { ...snapshot.weeklyWindow!, remainingPercent: 49 } },
      { ...snapshot, weeklyWindow: { ...snapshot.weeklyWindow!, windowSeconds: 18000 } },
    ];
    for (const value of variants) expect(scopedRecommendationPace(value, plan, observations, now, "UTC")).toBeNull();
    const switched = observations.map(row => ({ ...row, accountID: "another-owner" }));
    const switchedPlan = buildCockpitDailyPlan({ providerID: "codex", accountID: "another-owner", snapshots: switched, now, timeZone: "UTC" });
    expect(scopedRecommendationPace(variants[0], switchedPlan, switched, now, "UTC")).not.toBeNull();
  });

  it("preserves partial bounds and does not replace missing or stale observations with zero", () => {
    const { snapshot, observations, plan } = fixture();
    const partial = buildCockpitDailyPlan({ providerID: "codex", accountID: snapshot.accountScope,
      snapshots: [observations[1], observations.at(-1)!], now, timeZone: "UTC" });
    expect(scopedRecommendationPace(snapshot, partial, observations, now, "UTC")?.isLowerBound).toBe(true);
    expect(scopedRecommendationPace(snapshot, plan, [], now, "UTC")).toBeNull();
    expect(scopedRecommendationPace({ ...snapshot, status: "stale" }, plan, observations, now, "UTC")).toBeNull();
    expect(scopedRecommendationPace({ ...snapshot, updatedAt: "2026-11-02T10:00:00Z" }, plan, observations, now, "UTC")).toBeNull();
    expect(scopedRecommendationPace(snapshot, { ...plan, remainingPercent: 20 }, observations, now, "UTC")).toBeNull();
    expect(scopedRecommendationPace(snapshot, { ...plan, remainingPercent: Number.NaN }, observations, now, "UTC")).toBeNull();
  });

  it("fails closed on unknown scopes, invalid balances, future publications and zone changes", () => {
    const { snapshot, observations, plan } = fixture();
    for (const scope of [null, undefined, "", "unidentified", "local-machine", "unavailable", "default"]) {
      expect(scopedRecommendationPace({ ...snapshot, accountScope: scope }, plan, observations, now, "UTC")).toBeNull();
    }
    for (const remainingPercent of [Number.NaN, Number.POSITIVE_INFINITY, -1, 101]) {
      expect(scopedRecommendationPace({ ...snapshot, weeklyWindow: { ...snapshot.weeklyWindow!, remainingPercent } }, plan, observations, now, "UTC")).toBeNull();
    }
    expect(scopedRecommendationPace({ ...snapshot, updatedAt: "2026-11-02T12:01:00Z" }, plan, observations, now, "UTC")).toBeNull();
    expect(scopedRecommendationPace(snapshot, plan, observations, now, "America/New_York")).toBeNull();
  });
});
