import type { ProviderSnapshot } from "../types";
import { normalizeCockpitQuotaObservations, type CockpitDailyPlanStatus, type CockpitQuotaObservation } from "./cockpitDailyPlan";
import { buildCockpitRecommendationPace } from "./cockpitRecommendationPace";

/** App builds `plan` from this render's account/observations. A newly published snapshot
 * may arrive before its ledger write; wait for matching evidence instead of borrowing
 * the previous account/cycle's daily use. Only the local collector's main weekly pool applies.
 */
export function scopedRecommendationPace(
  snapshot: ProviderSnapshot | null | undefined,
  plan: CockpitDailyPlanStatus,
  observations: readonly CockpitQuotaObservation[],
  now: Date,
  timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone,
) {
  const scope = snapshot?.accountScope;
  const window = snapshot?.weeklyWindow;
  const timestamp = now.getTime();
  if (snapshot?.provider !== "codex" || snapshot.status !== "ok" || !scope
    || ["unavailable", "unidentified", "local-machine", "default"].includes(scope)
    || window?.windowSeconds !== 604800 || !window.resetsAt
    || !Number.isFinite(window.remainingPercent) || window.remainingPercent < 0 || window.remainingPercent > 100
    || !Number.isFinite(timestamp)) return null;
  const captured = Date.parse(snapshot.updatedAt);
  if (!Number.isFinite(captured) || captured > timestamp || timestamp - captured > 1_800_000) return null;
  const latest = normalizeCockpitQuotaObservations(observations)
    .filter(row => row.providerID === "codex" && row.accountID === scope && Date.parse(row.capturedAt) <= timestamp).at(-1);
  if (!latest || Date.parse(latest.resetsAt) !== Date.parse(window.resetsAt)
    || Math.abs(latest.remainingPercent - window.remainingPercent) >= 0.0001
    || plan.remainingPercent === null || !Number.isFinite(plan.remainingPercent)
    || Math.abs(plan.remainingPercent - window.remainingPercent) >= 0.0001) return null;
  return buildCockpitRecommendationPace(plan, now, window.resetsAt, timeZone);
}
