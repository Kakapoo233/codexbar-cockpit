import Foundation

/// Today's observed quota use compared with the current full-day automatic recommendation.
/// The comfort curve sets the daily total; local elapsed time advances its reference uniformly.
/// All amounts remain percentage points of the weekly quota, not percentages of a daily allowance.
public struct CockpitRecommendationPace: Equatable, Sendable {
    public let suggestedPercent: Double
    public let observedUsedPercent: Double
    public let expectedUsedPercent: Double
    public let deltaPercent: Double
    public let elapsedDayFraction: Double
    /// With incomplete observations, true use and its deviation may be greater than recorded.
    /// A negative lower bound therefore cannot establish a reserve or an on-track result.
    public let isLowerBound: Bool

    public init?(
        status: CockpitDayStatus,
        on date: Date = Date(),
        calendar: Calendar = .current)
    {
        guard date.timeIntervalSince1970.isFinite,
              !status.isStale,
              status.coverage != .unavailable,
              let suggested = status.suggestedPercent, suggested.isFinite, suggested >= 0,
              let used = status.usedPercent, used.isFinite, used >= 0,
              let reset = status.resetsAt, reset.timeIntervalSince1970.isFinite, reset > date,
              let interval = calendar.dateInterval(of: .day, for: date),
              interval.duration.isFinite, interval.duration > 0,
              status.localDateKey == CockpitCalendar.dateKey(for: date, calendar: calendar)
        else { return nil }
        if let horizon = status.planningResetWindow {
            guard horizon.resetsAt.timeIntervalSince1970.isFinite, horizon.resetsAt > date else { return nil }
        }

        let fraction = min(1, max(0, date.timeIntervalSince(interval.start) / interval.duration))
        let expected = suggested * fraction
        let delta = used - expected
        guard expected.isFinite, delta.isFinite else { return nil }
        self.suggestedPercent = suggested
        self.observedUsedPercent = used
        self.expectedUsedPercent = expected
        self.deltaPercent = delta
        self.elapsedDayFraction = fraction
        self.isLowerBound = status.coverage != .complete || status.suggestionIsPartial
    }
}
