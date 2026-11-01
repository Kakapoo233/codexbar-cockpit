import CodexBarCore
import Foundation

/// A full day's automatic recommendation in percentage points of the weekly quota.
/// Keep the planner's uncertainty; manual caps and today's remaining allowance are different values.
struct CockpitMenuBarRecommendation: Hashable {
    let percent: Double
    let isPartial: Bool
    let isStale: Bool

    init?(status: CockpitDayStatus?) {
        guard let status, let percent = status.suggestedPercent,
              percent.isFinite, percent >= 0 else { return nil }
        self.percent = percent
        self.isPartial = status.suggestionIsPartial
        self.isStale = status.isStale
    }
}

extension UsageStore {
    func cockpitMenuBarRecommendation(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        now: Date = Date()) -> CockpitMenuBarRecommendation?
    {
        CockpitMenuBarRecommendation(status: self.cockpitPlanStore?.status(
            for: provider, matching: snapshot, on: now))
    }
}
