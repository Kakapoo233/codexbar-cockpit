import Foundation

/// Completeness is carried separately from values. A missing observation is never a measured zero.
public enum CockpitCoverage: String, Codable, Sendable {
    case complete
    case partial
    case unavailable
}

public enum CockpitFeeling: String, Codable, Sendable, CaseIterable {
    case overloaded
    case comfortable
    case light

    /// A subjective score for the experience chart, not measured productivity or official quota.
    public var score: Double {
        switch self {
        case .overloaded: 0.25
        case .comfortable: 0.8
        case .light: 1
        }
    }
}

public struct CockpitQuotaSnapshot: Codable, Equatable, Sendable {
    public let providerID: String
    public let accountID: String
    public let capturedAt: Date
    public let remainingPercent: Double
    public let resetsAt: Date
    public let windowDuration: TimeInterval
    public let coverage: CockpitCoverage

    public init(
        providerID: String,
        accountID: String = "default",
        capturedAt: Date,
        remainingPercent: Double,
        resetsAt: Date,
        windowDuration: TimeInterval = 604_800,
        coverage: CockpitCoverage = .complete)
    {
        self.providerID = providerID
        self.accountID = accountID
        self.capturedAt = capturedAt
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
        self.coverage = coverage
    }

    var isValid: Bool {
        !self.providerID.isEmpty && !self.accountID.isEmpty
            && self.capturedAt.timeIntervalSince1970.isFinite
            && self.resetsAt.timeIntervalSince1970.isFinite
            && self.remainingPercent.isFinite && (0...100).contains(self.remainingPercent)
            && self.windowDuration.isFinite && self.windowDuration > 0
            && self.resetsAt > self.capturedAt
            && self.resetsAt.timeIntervalSince(self.capturedAt) <= self.windowDuration + 300
            && self.coverage != .unavailable
    }
}

public struct CockpitDailyPlan: Codable, Equatable, Sendable {
    public let providerID: String
    public let accountID: String
    public let localDateKey: String
    public let timeZoneIdentifier: String
    public let anchorAt: Date
    public let resetsAt: Date
    /// Historical anchor retained for calibration. Live advice is computed from the latest observations.
    public let suggestedPercent: Double
}

public struct CockpitPersonalCap: Codable, Equatable, Sendable {
    public let providerID: String
    public let accountID: String
    public let localDateKey: String
    public let timeZoneIdentifier: String
    public let percent: Double
}

public struct CockpitComfortRecord: Codable, Equatable, Sendable, Identifiable {
    public let providerID: String
    public let accountID: String
    public let localDateKey: String
    public let timeZoneIdentifier: String
    public let recordedAt: Date
    public let feeling: CockpitFeeling
    public let totalTokens: Int?
    public let coverage: CockpitCoverage
    /// Observed use of the selected account's quota during this calendar day; never derived from Tokens.
    public let usedPercent: Double?

    public var id: String {
        "\(self.providerID)|\(self.accountID)|\(self.timeZoneIdentifier)|\(self.localDateKey)"
    }

    public init(
        providerID: String,
        accountID: String = "default",
        localDateKey: String,
        timeZoneIdentifier: String,
        recordedAt: Date,
        feeling: CockpitFeeling,
        totalTokens: Int?,
        coverage: CockpitCoverage,
        usedPercent: Double? = nil)
    {
        self.providerID = providerID
        self.accountID = accountID
        self.localDateKey = localDateKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.recordedAt = recordedAt
        self.feeling = feeling
        self.totalTokens = totalTokens.flatMap { $0 >= 0 ? $0 : nil }
        self.coverage = coverage
        self.usedPercent = usedPercent.flatMap {
            $0.isFinite && (0...10000).contains($0) ? $0 : nil
        }
    }
}

public struct CockpitDayUsage: Equatable, Sendable {
    public let localDateKey: String
    /// A lower bound from observed official percentages; never inferred from token costs.
    public let usedPercent: Double?
    public let coverage: CockpitCoverage
    public let sampleCount: Int
}

public struct CockpitDayStatus: Equatable, Sendable {
    public let localDateKey: String
    public let suggestedPercent: Double?
    public let manualCapPercent: Double?
    public let usedPercent: Double?
    public let coverage: CockpitCoverage
    public let remainingPercent: Double?
    public let resetsAt: Date?
    public let feeling: CockpitFeeling?
    public let isStale: Bool
    /// The selected planning horizon; public horizons never replace the observed account reset metadata.
    public var planningResetWindow: CockpitPlanningResetWindow?
    public var suggestionIsPartial = false
    /// Live policy explanation only; archived plan anchors retain their original calibration meaning.
    public var comfortAdvice: CockpitComfortAdvice?

    public var effectiveCapPercent: Double? {
        self.manualCapPercent ?? self.suggestedPercent
    }

    public var remainingSuggestedPercent: Double? {
        guard let limit = self.effectiveCapPercent, let used = self.usedPercent,
              let remaining = self.remainingPercent else { return nil }
        return min(remaining, max(0, limit - used))
    }

    /// Share of today's effective allocation still available, distinct from the original weekly quota unit.
    /// Completeness remains on the status so the presentation can label partial observations separately.
    public var remainingDailyBudgetPercent: Double? {
        guard let limit = self.effectiveCapPercent, limit.isFinite, limit >= 0,
              let used = self.usedPercent, used.isFinite, used >= 0,
              let remaining = self.remainingPercent, remaining.isFinite, remaining >= 0,
              let available = self.remainingSuggestedPercent, available.isFinite, available >= 0 else { return nil }
        guard limit > 0 else { return 0 }
        let fraction = min(100, max(0, available / limit * 100))
        return (fraction * 100).rounded() / 100
    }
}

public enum CockpitCalendar {
    public static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
