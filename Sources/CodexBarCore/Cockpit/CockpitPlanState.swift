import Foundation

/// Local-first planning state. This module has no file, credential, network, or UI access.
/// The daily anchor is intentionally frozen; changing the manual cap never rewrites the suggestion.
public struct CockpitPlanState: Codable, Equatable, Sendable {
    public private(set) var snapshots: [CockpitQuotaSnapshot]
    public private(set) var plans: [CockpitDailyPlan]
    public private(set) var personalCaps: [CockpitPersonalCap]
    public private(set) var comfortRecords: [CockpitComfortRecord]

    public init() {
        self.snapshots = []
        self.plans = []
        self.personalCaps = []
        self.comfortRecords = []
    }

    /// Ignores invalid values and identical samples. Samples can arrive out of order.
    @discardableResult
    public mutating func record(_ snapshot: CockpitQuotaSnapshot, calendar: Calendar = .current) -> Bool {
        guard snapshot.isValid else { return false }
        let duplicate = self.snapshots.firstIndex {
            $0.providerID == snapshot.providerID && $0.accountID == snapshot.accountID
                && $0.capturedAt == snapshot.capturedAt
        }
        if let duplicate {
            // Equal-time rebounds must not lower an already observed high-water mark.
            guard self.snapshots[duplicate].remainingPercent > snapshot.remainingPercent else { return false }
            self.snapshots[duplicate] = snapshot
        } else {
            self.snapshots.append(snapshot)
        }
        self.snapshots.sort { $0.capturedAt < $1.capturedAt }
        self.snapshots = Array(self.snapshots.suffix(8192))
        self.ensurePlan(for: snapshot, calendar: calendar)
        return true
    }

    public mutating func setPersonalCap(
        _ percent: Double?,
        providerID: String,
        accountID: String = "default",
        on date: Date = Date(),
        calendar: Calendar = .current)
    {
        if let percent, !percent.isFinite || !(0...100).contains(percent) { return }
        let day = CockpitCalendar.dateKey(for: date, calendar: calendar)
        self.personalCaps.removeAll {
            $0.providerID == providerID && $0.accountID == accountID
                && $0.localDateKey == day && $0.timeZoneIdentifier == calendar.timeZone.identifier
        }
        if let percent {
            self.personalCaps.append(CockpitPersonalCap(
                providerID: providerID, accountID: accountID, localDateKey: day,
                timeZoneIdentifier: calendar.timeZone.identifier, percent: percent))
        }
        self.personalCaps = Array(self.personalCaps.suffix(400))
    }

    public mutating func recordComfort(
        _ feeling: CockpitFeeling,
        providerID: String,
        accountID: String = "default",
        on date: Date = Date(),
        totalTokens: Int? = nil,
        coverage: CockpitCoverage = .partial,
        calendar: Calendar = .current)
    {
        let record = CockpitComfortRecord(
            providerID: providerID, accountID: accountID,
            localDateKey: CockpitCalendar.dateKey(for: date, calendar: calendar),
            timeZoneIdentifier: calendar.timeZone.identifier, recordedAt: date,
            feeling: feeling, totalTokens: totalTokens, coverage: coverage)
        self.comfortRecords.removeAll { $0.id == record.id }
        self.comfortRecords.append(record)
        self.comfortRecords = Array(self.comfortRecords.suffix(3000))
    }

    public func status(
        providerID: String,
        accountID: String = "default",
        on date: Date = Date(),
        calendar: Calendar = .current) -> CockpitDayStatus
    {
        let day = CockpitCalendar.dateKey(for: date, calendar: calendar)
        let zone = calendar.timeZone.identifier
        let usage = self.dailyUsage(providerID: providerID, accountID: accountID, on: date, calendar: calendar)
        let plan = self.plans.first {
            $0.providerID == providerID && $0.accountID == accountID
                && $0.localDateKey == day && $0.timeZoneIdentifier == zone && $0.anchorAt <= date
        }
        let cap = self.personalCaps.last {
            $0.providerID == providerID && $0.accountID == accountID
                && $0.localDateKey == day && $0.timeZoneIdentifier == zone
        }
        let latest = self.samples(providerID: providerID, accountID: accountID, through: date).last
        let usable = latest.flatMap { $0.resetsAt > date ? $0 : nil }
        let feeling = self.comfortRecords.last {
            $0.providerID == providerID && $0.accountID == accountID
                && $0.localDateKey == day && $0.timeZoneIdentifier == zone
        }?.feeling
        let stale = usable.map { date.timeIntervalSince($0.capturedAt) > 1800 } ?? true
        return CockpitDayStatus(
            localDateKey: day,
            suggestedPercent: plan?.suggestedPercent,
            manualCapPercent: cap?.percent,
            usedPercent: usage.usedPercent,
            coverage: usage.coverage,
            remainingPercent: usable?.remainingPercent,
            resetsAt: usable?.resetsAt,
            feeling: feeling,
            isStale: stale)
    }

    public func dailyUsage(
        providerID: String,
        accountID: String = "default",
        on date: Date = Date(),
        calendar: Calendar = .current) -> CockpitDayUsage
    {
        let day = CockpitCalendar.dateKey(for: date, calendar: calendar)
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            return CockpitDayUsage(localDateKey: day, usedPercent: nil, coverage: .unavailable, sampleCount: 0)
        }
        let samples = self.samples(providerID: providerID, accountID: accountID, through: date)
        let today = samples.filter { $0.capturedAt >= interval.start && $0.capturedAt < interval.end }
        guard let firstToday = today.first, let lastToday = today.last else {
            return CockpitDayUsage(localDateKey: day, usedPercent: nil, coverage: .unavailable, sampleCount: 0)
        }
        let segments = Self.quotaSegments(today)
        var used = 0.0
        var hasObservation = false
        // Completeness requires a boundary sample and continuous recent observations.
        var complete = firstToday.capturedAt == interval.start
            && date.timeIntervalSince(lastToday.capturedAt) <= 1800
        var previous = firstToday.capturedAt
        for sample in today {
            if sample.capturedAt.timeIntervalSince(previous) > 1800 || sample.coverage != .complete {
                complete = false
            }
            previous = sample.capturedAt
        }
        for segment in segments {
            let points = segment.samples
            guard let first = points.first,
                  let maximum = points.map({ 100 - $0.remainingPercent }).max() else { continue }
            if segment.hasMetadataDrift { complete = false }
            let baseline: Double
            if segment.beginsWithObservedReset || (first.capturedAt > interval.start
                && first.resetsAt.addingTimeInterval(-first.windowDuration) >= interval.start)
            {
                // A new, observed cycle begins during this day: its use starts at zero.
                baseline = 0
                hasObservation = true
            } else {
                // No midnight sample means pre-launch consumption is unknown, not zero.
                baseline = 100 - first.remainingPercent
                hasObservation = hasObservation || points.count > 1 || first.capturedAt == interval.start
            }
            used += max(0, maximum - baseline)
        }
        return CockpitDayUsage(
            localDateKey: day, usedPercent: hasObservation ? Self.round(used) : nil,
            coverage: complete ? .complete : .partial, sampleCount: today.count)
    }

    private struct QuotaSegment {
        var samples: [CockpitQuotaSnapshot]
        var latestReset: Date
        var beginsWithObservedReset = false
        var hasMetadataDrift = false
    }

    /// Reset timestamps can alternate between second and minute precision across sources.
    /// A different timestamp alone never establishes another quota cycle.
    private static func quotaSegments(_ samples: [CockpitQuotaSnapshot]) -> [QuotaSegment] {
        guard let first = samples.first else { return [] }
        var segments: [QuotaSegment] = []
        var current = QuotaSegment(samples: [first], latestReset: first.resetsAt)
        var previous = first
        for sample in samples.dropFirst() {
            let advancedReset = sample.resetsAt.timeIntervalSince(current.latestReset) > 60
            let crossedReset = sample.capturedAt >= current.latestReset
            let cycleStart = sample.resetsAt.addingTimeInterval(-sample.windowDuration)
            let observedNewStart = cycleStart > previous.capturedAt && cycleStart <= sample.capturedAt
            if advancedReset, crossedReset || observedNewStart {
                segments.append(current)
                current = QuotaSegment(
                    samples: [sample], latestReset: sample.resetsAt, beginsWithObservedReset: true)
            } else {
                if sample.resetsAt != previous.resetsAt || sample.windowDuration != previous.windowDuration {
                    current.hasMetadataDrift = true
                }
                current.samples.append(sample)
                current.latestReset = max(current.latestReset, sample.resetsAt)
            }
            previous = sample
        }
        segments.append(current)
        return segments
    }

    private func samples(providerID: String, accountID: String, through date: Date) -> [CockpitQuotaSnapshot] {
        self.snapshots.filter {
            $0.isValid && $0.providerID == providerID && $0.accountID == accountID && $0.capturedAt <= date
        }.sorted { $0.capturedAt < $1.capturedAt }
    }

    private mutating func ensurePlan(for snapshot: CockpitQuotaSnapshot, calendar: Calendar) {
        let day = CockpitCalendar.dateKey(for: snapshot.capturedAt, calendar: calendar)
        guard !self.plans.contains(where: {
            $0.providerID == snapshot.providerID && $0.accountID == snapshot.accountID
                && $0.localDateKey == day && $0.timeZoneIdentifier == calendar.timeZone.identifier
        }), let interval = calendar.dateInterval(of: .day, for: snapshot.capturedAt) else { return }
        let untilReset = snapshot.resetsAt.timeIntervalSince(snapshot.capturedAt)
        let dayRemaining = interval.end.timeIntervalSince(snapshot.capturedAt)
        let additional = snapshot.remainingPercent * min(1, dayRemaining / untilReset)
        let used = self.dailyUsage(
            providerID: snapshot.providerID, accountID: snapshot.accountID,
            on: snapshot.capturedAt, calendar: calendar).usedPercent ?? 0
        self.plans.append(CockpitDailyPlan(
            providerID: snapshot.providerID, accountID: snapshot.accountID,
            localDateKey: day, timeZoneIdentifier: calendar.timeZone.identifier,
            anchorAt: snapshot.capturedAt, resetsAt: snapshot.resetsAt,
            suggestedPercent: Self.round(used + additional)))
        self.plans = Array(self.plans.suffix(400))
    }

    private static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
