import Foundation

// Daily risk and fatigue policy adapted from Codex Cockpit v0.3.4 (MIT).
// Copyright (c) 2026 Quota Float contributors. See the repository's third-party notices.

/// A planning input, never evidence that the account balance has reset.
public struct CockpitResetRisk: Equatable, Sendable {
    public enum Source: String, Sendable {
        case assumed, estimated, announced
    }

    public static let assumed = Self(probability: 0.1, source: .assumed)
    public static let none = Self(probability: 0, source: .assumed)

    public let probability: Double
    public let source: Source

    public init(probability: Double, source: Source) {
        let valid = probability.isFinite && (0...1).contains(probability)
        self.probability = valid ? probability : 0.1
        self.source = valid ? source : .assumed
    }
}

/// Full-day adaptation of Codex Cockpit v0.3.4's planRemainingQuota policy.
/// Percentages share the account's quota unit; subjective comfort never creates official quota.
public struct CockpitComfortAdvice: Equatable, Sendable {
    public let kneePercent: Double
    public let curveStatus: CockpitQuotaComfortModel.Status
    public let sampleCount: Int
    /// The whole-day comfort limit, including consumption before an observed same-day reset.
    public let softCapPercent: Double
    /// Earlier-cycle consumption plus the current cycle's full-day uniform share.
    public let baseDailyPercent: Double
    public let riskBonusPercent: Double
    public let risk: CockpitResetRisk
    public let isWeekend: Bool

    public init(
        kneePercent: Double,
        curveStatus: CockpitQuotaComfortModel.Status,
        sampleCount: Int,
        softCapPercent: Double,
        baseDailyPercent: Double,
        riskBonusPercent: Double,
        risk: CockpitResetRisk,
        isWeekend: Bool)
    {
        self.kneePercent = kneePercent
        self.curveStatus = curveStatus
        self.sampleCount = sampleCount
        self.softCapPercent = softCapPercent
        self.baseDailyPercent = baseDailyPercent
        self.riskBonusPercent = riskBonusPercent
        self.risk = risk
        self.isWeekend = isWeekend
    }

    public var isComfortLimited: Bool {
        self.softCapPercent + 1e-9 < self.baseDailyPercent + self.riskBonusPercent
    }

    public var suggestedPercent: Double {
        (min(self.softCapPercent, self.baseDailyPercent + self.riskBonusPercent) * 100).rounded() / 100
    }
}
