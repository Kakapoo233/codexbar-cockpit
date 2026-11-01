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

/// Both units come from the same plan status; partial observations provide an upper bound.
struct CockpitMenuBarDailyRemaining: Hashable {
    let percent: Double
    let weeklyPercent: Double
    let isUpperBound: Bool
    let isStale: Bool

    init(percent: Double, weeklyPercent: Double, isUpperBound: Bool, isStale: Bool) {
        self.percent = percent
        self.weeklyPercent = weeklyPercent
        self.isUpperBound = isUpperBound
        self.isStale = isStale
    }

    init?(status: CockpitDayStatus?) {
        guard let status, let percent = status.remainingDailyBudgetPercent,
              let weekly = status.remainingSuggestedPercent,
              percent.isFinite, (0...100).contains(percent), weekly.isFinite, weekly >= 0 else { return nil }
        self.init(
            percent: percent,
            weeklyPercent: weekly,
            isUpperBound: status.coverage != .complete,
            isStale: status.isStale)
    }
}

struct CockpitMenuBarPlanValues: Hashable {
    let recommendation: CockpitMenuBarRecommendation?
    let remaining: CockpitMenuBarDailyRemaining?

    init(status: CockpitDayStatus?) {
        self.recommendation = CockpitMenuBarRecommendation(status: status)
        self.remaining = CockpitMenuBarDailyRemaining(status: status)
    }
}

extension UsageStore {
    func cockpitMenuBarPlanValues(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        now: Date = Date()) -> CockpitMenuBarPlanValues
    {
        CockpitMenuBarPlanValues(status: self.cockpitPlanStore?.status(
            for: provider, matching: snapshot, on: now))
    }

    func cockpitMenuBarRecommendation(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        now: Date = Date()) -> CockpitMenuBarRecommendation?
    {
        CockpitMenuBarRecommendation(status: self.cockpitPlanStore?.status(
            for: provider, matching: snapshot, on: now))
    }
}
