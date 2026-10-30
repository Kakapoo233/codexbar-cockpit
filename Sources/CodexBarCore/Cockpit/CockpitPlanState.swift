import Foundation

/// Local-first planning state. This module has no file, credential, network, or UI access.
/// The daily anchor is intentionally frozen; changing the manual cap never rewrites the suggestion.
public struct CockpitPlanState: Codable, Equatable, Sendable {
    public private(set) var snapshots: [CockpitQuotaSnapshot]
    public private(set) var plans: [CockpitDailyPlan]
    public private(set) var personalCaps: [CockpitPersonalCap]
    public private(set) var comfortRecords: [CockpitComfortRecord]
    public private(set) var observedDaySummaries: [CockpitObservedDaySummary]

    public init() {
        self.snapshots = []
        self.plans = []
        self.personalCaps = []
        self.comfortRecords = []
        self.observedDaySummaries = []
    }

    private enum CodingKeys: String, CodingKey {
        case snapshots, plans, personalCaps, comfortRecords, observedDaySummaries
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.snapshots = try values.decode([CockpitQuotaSnapshot].self, forKey: .snapshots)
        self.plans = try values.decode([CockpitDailyPlan].self, forKey: .plans)
        self.personalCaps = try values.decode([CockpitPersonalCap].self, forKey: .personalCaps)
        self.comfortRecords = try values.decode([CockpitComfortRecord].self, forKey: .comfortRecords)
        self.observedDaySummaries = try values.decodeIfPresent(
            [CockpitObservedDaySummary].self, forKey: .observedDaySummaries) ?? []
    }

    /// Ignores invalid values and identical samples. Samples can arrive out of order.
    @discardableResult
    public mutating func record(_ snapshot: CockpitQuotaSnapshot, calendar: Calendar = .current) -> Bool {
        guard snapshot.isValid else { return false }
        let latestAt = self.snapshots.last?.capturedAt
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
        let day = CockpitCalendar.dateKey(for: snapshot.capturedAt, calendar: calendar)
        let summaryCount = self.observedDaySummaries.count
        let previousSummary = self.observedDaySummaries.first {
            $0.providerID == snapshot.providerID && $0.accountID == snapshot.accountID
                && $0.timeZoneIdentifier == calendar.timeZone.identifier && $0.localDateKey == day
        }
        self.observedDaySummaries.removeAll {
            $0.providerID == snapshot.providerID && $0.accountID == snapshot.accountID
                && $0.timeZoneIdentifier == calendar.timeZone.identifier && $0.localDateKey == day
        }
        // Corrections to expired raw data cannot safely reconstruct the archived aggregate.
        // Withdraw the measurement and training qualification until it can be reconstructed reliably.
        if let archived = previousSummary,
           !self.containsFullRawPeriod(of: archived, calendar: calendar)
        {
            self.observedDaySummaries.append(CockpitObservedDaySummary(
                providerID: archived.providerID,
                accountID: archived.accountID,
                timeZoneIdentifier: archived.timeZoneIdentifier,
                localDateKey: archived.localDateKey,
                firstObservedAt: archived.firstObservedAt,
                lastObservedAt: archived.lastObservedAt,
                sampleCount: archived.sampleCount,
                usedPercent: nil,
                coverage: .unavailable,
                qualifiesForCalibration: false,
                unreconciledCorrection: true))
        }
        if let latestAt,
           summaryCount != self.observedDaySummaries.count || !calendar.isDate(
               latestAt, inSameDayAs: snapshot.capturedAt)
        {
            self.summarizeClosedDays(through: max(latestAt, snapshot.capturedAt), calendar: calendar)
        }
        return true
    }

    /// Archives measured closed-day periods before bounded raw observations age out. This does not change
    /// dailyUsage's strict completeness contract or rewrite any daily plan.
    @discardableResult
    public mutating func summarizeClosedDays(
        through now: Date = Date(),
        calendar: Calendar = .current) -> Bool
    {
        let today = calendar.startOfDay(for: now)
        let zone = calendar.timeZone.identifier
        var groups: [String: [CockpitQuotaSnapshot]] = [:]
        for sample in self.snapshots where sample.isValid && sample.capturedAt < today {
            let day = CockpitCalendar.dateKey(for: sample.capturedAt, calendar: calendar)
            let id = "\(sample.providerID)|\(sample.accountID)|\(zone)|\(day)"
            groups[id, default: []].append(sample)
        }
        var summaries = Dictionary(self.observedDaySummaries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var changed = false
        for (id, samples) in groups {
            let points = samples.sorted { $0.capturedAt < $1.capturedAt }
            guard let first = points.first, let last = points.last else { continue }
            if summaries[id]?.unreconciledCorrection == true { continue }
            if let existing = summaries[id], existing.lastObservedAt >= last.capturedAt,
               existing.firstObservedAt <= first.capturedAt, existing.sampleCount >= points.count { continue }
            let day = CockpitCalendar.dateKey(for: first.capturedAt, calendar: calendar)
            guard let interval = calendar.dateInterval(of: .day, for: first.capturedAt) else { continue }
            let usage = self.dailyUsage(
                providerID: first.providerID,
                accountID: first.accountID,
                on: interval.end.addingTimeInterval(-0.001),
                calendar: calendar)
            let segments = Self.quotaSegments(points)
            let span = last.capturedAt.timeIntervalSince(first.capturedAt)
            let continuous = zip(points, points.dropFirst()).allSatisfy {
                $1.capturedAt.timeIntervalSince($0.capturedAt) <= 5400
            }
            let qualifies = points.count >= 13 && span >= 21600 && span / interval.duration >= 0.25
                && continuous && points.allSatisfy { $0.coverage == .complete }
                && !segments.isEmpty && !segments.contains(where: \.hasMetadataDrift)
                && usage.usedPercent != nil
            summaries[id] = CockpitObservedDaySummary(
                providerID: first.providerID,
                accountID: first.accountID,
                timeZoneIdentifier: zone,
                localDateKey: day,
                firstObservedAt: first.capturedAt,
                lastObservedAt: last.capturedAt,
                sampleCount: points.count,
                usedPercent: usage.usedPercent,
                coverage: usage.coverage,
                qualifiesForCalibration: qualifies,
                unreconciledCorrection: nil)
            changed = true
        }
        guard changed else { return false }
        self.observedDaySummaries = Array(summaries.values.sorted {
            if $0.lastObservedAt != $1.lastObservedAt { return $0.lastObservedAt < $1.lastObservedAt }
            return $0.id < $1.id
        }.suffix(400))
        return true
    }

    private func containsFullRawPeriod(of summary: CockpitObservedDaySummary, calendar: Calendar) -> Bool {
        let points = self.snapshots.filter {
            $0.providerID == summary.providerID && $0.accountID == summary.accountID
                && CockpitCalendar.dateKey(for: $0.capturedAt, calendar: calendar) == summary.localDateKey
        }
        return points.count >= summary.sampleCount
            && (points.first?.capturedAt ?? .distantFuture) <= summary.firstObservedAt
            && (points.last?.capturedAt ?? .distantPast) >= summary.lastObservedAt
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
                providerID: providerID,
                accountID: accountID,
                localDateKey: day,
                timeZoneIdentifier: calendar.timeZone.identifier,
                percent: percent))
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
            providerID: providerID,
            accountID: accountID,
            localDateKey: CockpitCalendar.dateKey(for: date, calendar: calendar),
            timeZoneIdentifier: calendar.timeZone.identifier,
            recordedAt: date,
            feeling: feeling,
            totalTokens: totalTokens,
            coverage: coverage)
        self.comfortRecords.removeAll { $0.id == record.id }
        self.comfortRecords.append(record)
        self.comfortRecords = Array(self.comfortRecords.suffix(3000))
    }

    public mutating func clearComfort(
        providerID: String,
        accountID: String = "default",
        on date: Date = Date(),
        calendar: Calendar = .current)
    {
        let day = CockpitCalendar.dateKey(for: date, calendar: calendar)
        self.comfortRecords.removeAll {
            $0.providerID == providerID && $0.accountID == accountID
                && $0.localDateKey == day && $0.timeZoneIdentifier == calendar.timeZone.identifier
        }
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
            localDateKey: day,
            usedPercent: hasObservation ? Self.round(used) : nil,
            coverage: complete ? .complete : .partial,
            sampleCount: today.count)
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
                    samples: [sample],
                    latestReset: sample.resetsAt,
                    beginsWithObservedReset: true)
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
            providerID: snapshot.providerID,
            accountID: snapshot.accountID,
            on: snapshot.capturedAt,
            calendar: calendar).usedPercent ?? 0
        self.plans.append(CockpitDailyPlan(
            providerID: snapshot.providerID,
            accountID: snapshot.accountID,
            localDateKey: day,
            timeZoneIdentifier: calendar.timeZone.identifier,
            anchorAt: snapshot.capturedAt,
            resetsAt: snapshot.resetsAt,
            suggestedPercent: Self.round(used + additional)))
        self.plans = Array(self.plans.suffix(400))
    }

    private static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
