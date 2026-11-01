import CodexBarCore
import Foundation

extension UsageStore {
    /// Only the local account's weekly lane uses the daily recommendation comparison.
    /// Session and additional quota pools keep their own window-based pace.
    func usesCockpitRecommendationPace(
        provider: UsageProvider,
        window: RateWindow?,
        snapshot: UsageSnapshot?) -> Bool
    {
        guard provider == .codex, self.cockpitPlanStore != nil,
              let window, !window.isSyntheticPlaceholder,
              let snapshot, let weekly = CockpitPlanStore.weeklyWindow(in: snapshot) else { return false }
        // Recognize the lane independently of planner readiness. A new account/cycle must show
        // unavailable until ingestion, rather than silently switching to a different pace basis.
        return window.windowMinutes == weekly.windowMinutes && window.resetsAt == weekly.resetsAt
            && window.usedPercent == weekly.usedPercent
    }

    func cockpitRecommendationPace(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        now: Date = Date()) -> CockpitRecommendationPace?
    {
        guard provider == .codex, let snapshot,
              ProviderDescriptorRegistry.descriptor(for: provider).pace
                  .allowsPace(dataConfidence: snapshot.dataConfidence),
                  let weekly = CockpitPlanStore.weeklyWindow(in: snapshot),
                  let status = self.cockpitPlanStore?.status(for: provider, matching: snapshot, on: now),
                  status.resetsAt == weekly.resetsAt,
                  let remaining = status.remainingPercent,
                  abs(remaining - weekly.remainingPercent) < 0.0001
        else { return nil }
        return CockpitRecommendationPace(status: status, on: now)
    }

    func menuPaceSummary(
        provider: UsageProvider,
        window: RateWindow,
        snapshot: UsageSnapshot,
        now: Date = Date()) -> String?
    {
        let official = self.weeklyPace(
            provider: provider, window: window, dataConfidence: snapshot.dataConfidence, now: now)
        if self.usesCockpitRecommendationPace(provider: provider, window: window, snapshot: snapshot) {
            let detail = CockpitRecommendationPaceText.weeklyDetail(
                pace: self.cockpitRecommendationPace(provider: provider, snapshot: snapshot, now: now),
                officialPace: official,
                now: now)
            if let forecast = detail.rightLabel { return L("Pace: %@ · %@", detail.leftLabel, forecast) }
            return L("Pace: %@", detail.leftLabel)
        }
        return official.map { UsagePaceText.weeklySummary(provider: provider, pace: $0, now: now) }
    }
}
