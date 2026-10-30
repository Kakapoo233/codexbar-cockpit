import Foundation

// Local weekday calibration adapted from Codex Cockpit v0.3.4 (MIT).
// Copyright (c) 2026 Quota Float contributors. See the repository's third-party notices.

/// Persisted only for finished local days. Coverage is retained; qualifying observed periods are not full days.
public struct CockpitObservedDaySummary: Codable, Equatable, Sendable, Identifiable {
    public let providerID: String
    public let accountID: String
    public let timeZoneIdentifier: String
    public let localDateKey: String
    public let firstObservedAt: Date
    public let lastObservedAt: Date
    public let sampleCount: Int
    public let usedPercent: Double?
    public let coverage: CockpitCoverage
    public let qualifiesForCalibration: Bool
    public let unreconciledCorrection: Bool?

    public var id: String {
        "\(self.providerID)|\(self.accountID)|\(self.timeZoneIdentifier)|\(self.localDateKey)"
    }
}

public struct CockpitPersonalUsageDay: Equatable, Sendable {
    public let providerID: String
    public let accountID: String
    public let timeZoneIdentifier: String
    public let localDateKey: String
    public let suggestedPercent: Double
    public let usedPercent: Double?
    public let coverage: CockpitCoverage
    public let observedPeriodQualifies: Bool

    public init(
        providerID: String,
        accountID: String,
        timeZoneIdentifier: String,
        localDateKey: String,
        suggestedPercent: Double,
        usedPercent: Double?,
        coverage: CockpitCoverage,
        observedPeriodQualifies: Bool = false)
    {
        self.providerID = providerID
        self.accountID = accountID
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localDateKey = localDateKey
        self.suggestedPercent = suggestedPercent
        self.usedPercent = usedPercent
        self.coverage = coverage
        self.observedPeriodQualifies = observedPeriodQualifies
    }
}

public struct CockpitWeekdayUsageStat: Equatable, Sendable {
    /// Calendar weekday: Sunday = 1, Saturday = 7.
    public let weekday: Int
    public let sampleCount: Int
    public let allocationWeight: Double
}

public struct CockpitPersonalUsageValidation: Equatable, Sendable {
    public let holdoutDayCount: Int
    public let baselineMeanAbsoluteError: Double
    public let personalMeanAbsoluteError: Double
    public let relativeImprovement: Double
}

/// An optional reference scenario, never an official quota or a replacement for a frozen daily plan.
/// Unlike the upstream browser model, missing and partial native observations cannot train as zero.
public struct CockpitPersonalUsageModel: Equatable, Sendable {
    public enum Status: String, Sendable {
        case collecting
        case stale
        case distributionDrift
        case noValidationGain
        case ready
    }

    public let status: Status
    public let plannedDayCount: Int
    public let eligibleDayCount: Int
    public let activeDayCount: Int
    public let weekdayStats: [CockpitWeekdayUsageStat]
    public let validation: CockpitPersonalUsageValidation?

    private struct Day {
        let date: Date
        let weekday: Int
        let target: Double
        let used: Double

        var utilization: Double {
            min(2, max(0, self.used / self.target))
        }

        var isWeekend: Bool {
            self.weekday == 1 || self.weekday == 7
        }
    }

    public static func build(
        state: CockpitPlanState,
        providerID: String,
        accountID: String,
        now: Date = Date(),
        calendar: Calendar = .current) -> Self
    {
        let today = calendar.startOfDay(for: now)
        let oldest = calendar.date(byAdding: .day, value: -90, to: today) ?? today
        let summaries = Dictionary(
            state.observedDaySummaries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let days = state.plans.compactMap { plan -> CockpitPersonalUsageDay? in
            guard plan.providerID == providerID, plan.accountID == accountID,
                  plan.timeZoneIdentifier == calendar.timeZone.identifier,
                  let date = Self.date(for: plan.localDateKey, calendar: calendar), date >= oldest, date < today
            else { return nil }
            let summaryID = "\(providerID)|\(accountID)|\(plan.timeZoneIdentifier)|\(plan.localDateKey)"
            let summary = summaries[summaryID]
            return CockpitPersonalUsageDay(
                providerID: providerID,
                accountID: accountID,
                timeZoneIdentifier: plan.timeZoneIdentifier,
                localDateKey: plan.localDateKey,
                suggestedPercent: plan.suggestedPercent,
                usedPercent: summary?.usedPercent,
                coverage: summary?.coverage ?? .unavailable,
                observedPeriodQualifies: summary?.qualifiesForCalibration ?? false)
        }
        return Self.build(days: days, providerID: providerID, accountID: accountID, now: now, calendar: calendar)
    }

    public static func build(
        days: [CockpitPersonalUsageDay],
        providerID: String,
        accountID: String,
        now: Date = Date(),
        calendar: Calendar = .current) -> Self
    {
        let today = calendar.startOfDay(for: now)
        let oldest = calendar.date(byAdding: .day, value: -90, to: today) ?? today
        var scoped: [String: CockpitPersonalUsageDay] = [:]
        var ambiguous = Set<String>()
        for day in days {
            guard day.providerID == providerID, day.accountID == accountID,
                  day.timeZoneIdentifier == calendar.timeZone.identifier,
                  let date = Self.date(for: day.localDateKey, calendar: calendar), date >= oldest, date < today,
                  day.suggestedPercent.isFinite, (0.1...100).contains(day.suggestedPercent) else { continue }
            // Conflicting duplicate days have no reliable single observation to train from.
            if let previous = scoped[day.localDateKey], previous != day { ambiguous.insert(day.localDateKey) }
            scoped[day.localDateKey] = day
        }
        let complete = scoped.values.compactMap { day -> Day? in
            guard !ambiguous.contains(day.localDateKey),
                  day.coverage == .complete || (day.coverage == .partial && day.observedPeriodQualifies),
                  let used = day.usedPercent, used.isFinite, (0...100).contains(used),
                  let date = Self.date(for: day.localDateKey, calendar: calendar) else { return nil }
            return Day(
                date: date,
                weekday: calendar.component(.weekday, from: date),
                target: day.suggestedPercent,
                used: used)
        }.sorted { $0.date < $1.date }
        let active = complete.filter { $0.used > 0.5 }
        func result(
            _ status: Status,
            stats: [CockpitWeekdayUsageStat] = [],
            validation: CockpitPersonalUsageValidation? = nil) -> Self
        {
            Self(
                status: status,
                plannedDayCount: scoped.count,
                eligibleDayCount: complete.count,
                activeDayCount: active.count,
                weekdayStats: stats,
                validation: validation)
        }
        guard complete.count >= 21, active.count >= 12,
              complete.filter({ !$0.isWeekend }).count >= 15,
              complete.filter(\.isWeekend).count >= 6,
              let latest = complete.last, let latestActive = active.last else { return result(.collecting) }
        let age = calendar.dateComponents([.day], from: latest.date, to: today).day ?? Int.max
        let activeAge = calendar.dateComponents([.day], from: latestActive.date, to: today).day ?? Int.max
        guard age <= 3, activeAge <= 7 else { return result(.stale) }
        let holdout = Array(complete.suffix(7))
        guard let firstHoldout = holdout.first,
              calendar.dateComponents([.day], from: firstHoldout.date, to: latest.date).day == 6
        else { return result(.collecting) }
        let training = Array(complete.dropLast(7))
        let stats = Self.fit(training)
        let validation = Self.validate(holdout, stats: stats)
        let drift = [false, true].map { weekend in
            abs(Self.groupRatio(training, weekend: weekend) - Self.groupRatio(holdout, weekend: weekend))
        }.max() ?? 0
        guard drift <= 0.45 else { return result(.distributionDrift, stats: stats, validation: validation) }
        guard validation.relativeImprovement >= 0.01 else {
            return result(.noValidationGain, stats: stats, validation: validation)
        }
        return result(.ready, stats: stats, validation: validation)
    }

    /// Uses exactly the weekday prediction tested in the holdout. It predicts recorded usage on comparable days,
    /// not unobserved full-day consumption. A prediction above the available quota is withheld, not clipped.
    public func referencePercent(
        status: CockpitDayStatus,
        now: Date = Date(),
        calendar: Calendar = .current) -> Double?
    {
        guard self.status == .ready, !status.isStale,
              let target = status.suggestedPercent, target.isFinite, target >= 0,
              let remaining = status.remainingPercent, remaining.isFinite, (0...100).contains(remaining),
              let reset = status.resetsAt, reset > now else { return nil }
        let weekday = calendar.component(.weekday, from: now)
        let reference = min(100, target * self.weight(for: weekday))
        let used = status.usedPercent.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
        guard reference <= used + remaining else { return nil }
        return (reference * 10).rounded() / 10
    }

    private func weight(for weekday: Int) -> Double {
        self.weekdayStats.first { $0.weekday == weekday }?.allocationWeight ?? 1
    }

    private static func fit(_ days: [Day]) -> [CockpitWeekdayUsageStat] {
        (1...7).map { weekday in
            let group = days.filter { $0.weekday == weekday }
            // The native frozen-plan baseline distributes quota uniformly, hence a neutral prior of 1.
            let weight = (group.reduce(0) { $0 + $1.utilization } + 4) / Double(group.count + 4)
            return CockpitWeekdayUsageStat(
                weekday: weekday, sampleCount: group.count, allocationWeight: min(1.75, max(0.25, weight)))
        }
    }

    private static func validate(
        _ days: [Day], stats: [CockpitWeekdayUsageStat]) -> CockpitPersonalUsageValidation
    {
        let baseline = days.reduce(0) { $0 + abs($1.target - $1.used) } / Double(days.count)
        let personal = days.reduce(0) { sum, day in
            let weight = stats.first { $0.weekday == day.weekday }?.allocationWeight ?? 1
            return sum + abs(min(100, day.target * weight) - day.used)
        } / Double(days.count)
        return CockpitPersonalUsageValidation(
            holdoutDayCount: days.count,
            baselineMeanAbsoluteError: baseline,
            personalMeanAbsoluteError: personal,
            relativeImprovement: baseline > 0 ? (baseline - personal) / baseline : 0)
    }

    private static func groupRatio(_ days: [Day], weekend: Bool) -> Double {
        let group = days.filter { $0.isWeekend == weekend }
        return group.isEmpty ? 0 : group.reduce(0) { $0 + $1.utilization } / Double(group.count)
    }

    private static func date(for key: String, calendar: Calendar) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard key.count == 10, values.count == 3,
              let date = calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2])),
              CockpitCalendar.dateKey(for: date, calendar: calendar) == key else { return nil }
        return date
    }
}
