import Foundation

/// A planning deadline only. Public announcements and estimates never establish an observed quota cycle.
public struct CockpitPlanningResetWindow: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        case account, announced, estimated
    }

    public let resetsAt: Date
    public let source: Source

    public init(resetsAt: Date, source: Source) {
        self.resetsAt = resetsAt
        self.source = source
    }

    /// Public signals may shorten, but never extend, the account's known deadline. A pending dated
    /// announcement takes precedence over a conflicting historical estimate, even when it is later.
    public static func resolve(
        accountResetAt: Date,
        scheduled: CockpitScheduledReset? = nil,
        forecast: CockpitResetForecast? = nil,
        latestPublicReset: CockpitResetEvent? = nil,
        now: Date) -> Self?
    {
        guard now.timeIntervalSince1970.isFinite,
              accountResetAt.timeIntervalSince1970.isFinite, accountResetAt > now else { return nil }
        let account = Self(resetsAt: accountResetAt, source: .account)
        if let scheduled, scheduled.kind == .regular, scheduled.isPending(at: now) {
            // An undated or overdue plan cannot supply a safe deadline or revive an older estimate.
            guard let date = scheduled.scheduledFor, date > now else { return account }
            return date < accountResetAt ? Self(resetsAt: date, source: .announced) : account
        }
        guard let forecast, forecast.estimatedAt.timeIntervalSince1970.isFinite,
              forecast.estimatedAt > now, forecast.estimatedAt < accountResetAt,
              forecast.anchorDate <= now else { return account }
        if let latestPublicReset, latestPublicReset.kind == .regular,
           latestPublicReset.announcedAt > forecast.anchorDate { return account }
        return Self(resetsAt: forecast.estimatedAt, source: .estimated)
    }
}
