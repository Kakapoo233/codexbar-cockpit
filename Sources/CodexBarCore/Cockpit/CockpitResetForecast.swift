import Foundation

/// A local historical estimate. It does not infer whether a public announcement was fulfilled.
public struct CockpitResetForecast: Codable, Equatable, Sendable {
    public let anchorEventID: String
    public let anchorDate: Date
    public let estimatedAt: Date
    public let medianInterval: TimeInterval
    public let minimumInterval: TimeInterval
    public let maximumInterval: TimeInterval
    /// Number of observed intervals, rather than the number of announcements.
    public let sampleCount: Int

    public func isOverdue(at now: Date) -> Bool {
        self.estimatedAt <= now
    }

    public static func estimate(events: [CockpitResetEvent], now: Date = Date()) -> Self? {
        guard now.timeIntervalSince1970.isFinite else { return nil }
        let cutoff = now.addingTimeInterval(-180 * 86400)
        let regular = CockpitResetHistory(events: events, generatedAt: now).events.filter {
            $0.kind == .regular && $0.announcedAt <= now && $0.announcedAt >= cutoff
        }.prefix(11)
        guard regular.count >= 4, let anchor = regular.first else { return nil }
        let dates = regular.map(\.announcedAt)
        let intervals = zip(dates, dates.dropFirst()).map { $0.timeIntervalSince($1) }.filter { $0 > 0 }.sorted()
        guard intervals.count >= 3, let minimum = intervals.first, let maximum = intervals.last else { return nil }
        let middle = intervals.count / 2
        let median = intervals.count.isMultiple(of: 2)
            ? (intervals[middle - 1] + intervals[middle]) / 2
            : intervals[middle]
        return Self(
            anchorEventID: anchor.id,
            anchorDate: anchor.announcedAt,
            estimatedAt: anchor.announcedAt.addingTimeInterval(median),
            medianInterval: median,
            minimumInterval: minimum,
            maximumInterval: maximum,
            sampleCount: intervals.count)
    }
}
