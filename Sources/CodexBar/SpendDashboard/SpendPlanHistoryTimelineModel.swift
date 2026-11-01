import CodexBarCore
import Foundation

/// Calendar-time projection of recorded quota observations, independent of reset-cycle menu summaries.
struct SpendPlanHistoryTimelineModel {
    struct Point: Identifiable, Equatable {
        let capturedAt: Date
        let remainingPercent: Double
        let segmentID: Int
        let resetsAt: Date?

        var id: Date {
            self.capturedAt
        }
    }

    private struct Sample {
        let capturedAt: Date
        var usedPercent: Double
        var resetsAt: Date?
        var breakBefore: Bool
    }

    static let maximumConnectedGap: TimeInterval = 2 * 3600
    let domain: ClosedRange<Date>
    let points: [Point]
    /// Rendering retains actual extrema and endpoints; inspection and coverage use all recorded points.
    let drawingPoints: [Point]
    let recordedRange: ClosedRange<Date>?

    var sampleCount: Int {
        self.points.count
    }

    static func build(
        history: PlanUtilizationSeriesHistory?,
        period: CostReportingPeriod,
        now: Date,
        calendar: Calendar) -> Self
    {
        let validClock = now.timeIntervalSince1970.isFinite
        let reference = validClock ? now : Date(timeIntervalSince1970: 0)
        let entries = validClock ? (history?.entries ?? []).filter {
            $0.capturedAt.timeIntervalSince1970.isFinite && $0.capturedAt <= reference
        }.sorted(by: PlanUtilizationHistoryEntry.precedes) : []
        let earliest = entries.first(where: { Self.validPercent($0.usedPercent) })?.capturedAt ?? reference
        let bounds = period.bounds(now: reference, calendar: calendar, earliest: earliest)
        let end = calendar.date(byAdding: .day, value: 1, to: bounds.upperBound)
            ?? reference.addingTimeInterval(1)
        let domain = bounds.lowerBound...max(end, bounds.lowerBound.addingTimeInterval(1))
        let samples = Self.samples(entries, in: domain)
        var segment = 0
        let points = samples.enumerated().map { index, sample in
            if index > 0, Self.breaksLine(
                after: samples[index - 1], before: sample, windowMinutes: history?.windowMinutes ?? 0)
            {
                segment += 1
            }
            return Point(
                capturedAt: sample.capturedAt,
                remainingPercent: 100 - sample.usedPercent,
                segmentID: segment,
                resetsAt: sample.resetsAt)
        }
        let range = points.first.flatMap { first in points.last.map { first.capturedAt...$0.capturedAt } }
        return Self(
            domain: domain,
            points: points,
            drawingPoints: Self.renderingPoints(points),
            recordedRange: range)
    }

    func point(nearestTo date: Date) -> Point? {
        guard date.timeIntervalSince1970.isFinite, !self.points.isEmpty else { return nil }
        var lower = 0
        var upper = self.points.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if self.points[middle].capturedAt < date { lower = middle + 1 } else { upper = middle }
        }
        let right = min(lower, self.points.count - 1)
        let left = max(0, right - 1)
        return abs(self.points[left].capturedAt.timeIntervalSince(date))
            <= abs(self.points[right].capturedAt.timeIntervalSince(date)) ? self.points[left] : self.points[right]
    }

    private static func validPercent(_ value: Double) -> Bool {
        value.isFinite && (0...100).contains(value)
    }

    private static func samples(
        _ entries: [PlanUtilizationHistoryEntry], in domain: ClosedRange<Date>) -> [Sample]
    {
        var result: [Sample] = []
        var breakBefore = false
        for entry in entries where entry.capturedAt >= domain.lowerBound && entry.capturedAt < domain.upperBound {
            guard Self.validPercent(entry.usedPercent) else {
                breakBefore = true
                continue
            }
            let reset = entry.resetsAt.flatMap {
                $0.timeIntervalSince1970.isFinite && $0 > entry.capturedAt ? $0 : nil
            }
            if let last = result.last, last.capturedAt == entry.capturedAt {
                let index = result.count - 1
                result[index].usedPercent = max(last.usedPercent, entry.usedPercent)
                if let priorReset = last.resetsAt, let reset, abs(priorReset.timeIntervalSince(reset)) <= 60 {
                    result[index].resetsAt = max(priorReset, reset)
                } else {
                    result[index].resetsAt = nil
                }
                result[index].breakBefore = last.breakBefore || breakBefore
            } else {
                result.append(Sample(
                    capturedAt: entry.capturedAt,
                    usedPercent: entry.usedPercent,
                    resetsAt: reset,
                    breakBefore: breakBefore))
            }
            breakBefore = false
        }
        return result
    }

    private static func breaksLine(after prior: Sample, before current: Sample, windowMinutes: Int) -> Bool {
        if current.breakBefore || current.capturedAt.timeIntervalSince(prior.capturedAt) > self.maximumConnectedGap
            || current.usedPercent < prior.usedPercent - 1e-9 { return true }
        if let priorReset = prior.resetsAt, let reset = current.resetsAt {
            return abs(priorReset.timeIntervalSince(reset)) > 60 || current.capturedAt >= priorReset
        }
        // A duration-less observation pool intentionally has no reset timestamp. Other unknown
        // cycle metadata cannot establish that two points belong to the same quota cycle.
        return windowMinutes != 0 || prior.resetsAt != nil || current.resetsAt != nil
    }

    private static func renderingPoints(_ points: [Point], limit: Int = 1000) -> [Point] {
        guard points.count > limit else { return points }
        let buckets = max(1, (limit - 2) / 4)
        let size = Int(ceil(Double(points.count) / Double(buckets)))
        var indices: Set<Int> = [0, points.count - 1]
        for start in stride(from: 0, to: points.count, by: size) {
            let end = min(start + size, points.count)
            let slice = start..<end
            indices.insert(start)
            indices.insert(end - 1)
            if let minimum = slice.min(by: { points[$0].remainingPercent < points[$1].remainingPercent }) {
                indices.insert(minimum)
            }
            if let maximum = slice.max(by: { points[$0].remainingPercent < points[$1].remainingPercent }) {
                indices.insert(maximum)
            }
        }
        return indices.sorted().map { points[$0] }
    }
}
