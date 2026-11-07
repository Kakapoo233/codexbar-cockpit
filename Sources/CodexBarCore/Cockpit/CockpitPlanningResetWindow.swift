import Foundation

/// A planning deadline only. Public announcements never establish an observed quota cycle.
public struct CockpitPlanningResetWindow: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        case account, announced
    }

    public let resetsAt: Date
    public let source: Source

    public init(resetsAt: Date, source: Source) {
        self.resetsAt = resetsAt
        self.source = source
    }

    /// A pending dated public announcement may shorten, but never extend, the account's known deadline.
    public static func resolve(
        accountResetAt: Date,
        scheduled: CockpitScheduledReset? = nil,
        now: Date) -> Self?
    {
        guard now.timeIntervalSince1970.isFinite,
              accountResetAt.timeIntervalSince1970.isFinite, accountResetAt > now else { return nil }
        let account = Self(resetsAt: accountResetAt, source: .account)
        if let scheduled, scheduled.kind == .regular, scheduled.isPending(at: now) {
            // An undated or overdue plan cannot supply a safe deadline.
            guard let date = scheduled.scheduledFor, date > now else { return account }
            return date < accountResetAt ? Self(resetsAt: date, source: .announced) : account
        }
        return account
    }
}
