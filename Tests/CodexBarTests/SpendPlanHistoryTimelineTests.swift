import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct SpendPlanHistoryTimelineTests {
    @Test(arguments: [
        (CostReportingPeriod.rolling(days: 7), "2026-10-09T00:00:00Z"),
        (CostReportingPeriod.rolling(days: 30), "2026-09-16T00:00:00Z"),
        (CostReportingPeriod.rolling(days: 90), "2026-07-18T00:00:00Z"),
    ])
    func `a wider selected window changes the date domain even with the same two recent observations`(
        example: (CostReportingPeriod, String)) throws
    {
        let now = try Self.date("2026-10-15T12:00:00Z")
        let first = try Self.date("2026-10-14T10:00:00Z")
        let second = try Self.date("2026-10-15T10:00:00Z")
        let model = try Self.build(
            [
                Self.entry(
                    first,
                    used: 20), Self.entry(
                    second,
                    used: 40),
            ],
            period: example.0,
            now: now,
            calendar: Self.calendar("UTC"))
        #expect(model.sampleCount == 2)
        #expect(model.points.map(\.capturedAt) == [first, second])
        #expect(try model.domain.lowerBound == (Self.date(example.1)))
        #expect(try model.domain.upperBound == (Self.date("2026-10-16T00:00:00Z")))
        #expect(model.recordedRange?.lowerBound == first)
        #expect(model.recordedRange?.upperBound == second)
    }

    @Test
    func `remaining percentages reflect real observations and reset cycles do not join`() throws {
        let start = try Self.date("2026-10-15T10:00:00Z")
        let now = start.addingTimeInterval(2 * 3600)
        let firstReset = now.addingTimeInterval(4 * 3600)
        let nextReset = now.addingTimeInterval(7 * 86400)
        let model = try Self.build(
            [
                Self.entry(
                    start,
                    used: 10,
                    reset: firstReset),
                Self.entry(
                    start.addingTimeInterval(1800),
                    used: 20,
                    reset: firstReset),
                Self.entry(
                    start.addingTimeInterval(3600),
                    used: 30,
                    reset: nextReset),
            ],
            now: now,
            calendar: Self.calendar("UTC"))
        #expect(model.points.map(\.remainingPercent) == [90, 80, 70])
        #expect(model.points.count == 3)
        guard model.points.count == 3 else { return }
        #expect(model.points[0].segmentID == model.points[1].segmentID)
        #expect(model.points[1].segmentID != model.points[2].segmentID)
    }

    @Test
    func `remaining balance increases and long observation gaps break a known cycle line`() throws {
        let start = try Self.date("2026-10-15T07:00:00Z")
        let now = start.addingTimeInterval(5 * 3600)
        let reset = now.addingTimeInterval(7 * 86400)
        let model = try Self.build(
            [
                Self.entry(
                    start,
                    used: 20,
                    reset: reset),
                Self.entry(
                    start.addingTimeInterval(1800),
                    used: 10,
                    reset: reset),
                Self.entry(
                    start.addingTimeInterval(4 * 3600),
                    used: 30,
                    reset: reset),
            ],
            now: now,
            calendar: Self.calendar("UTC"))
        #expect(model.points.count == 3)
        guard model.points.count == 3 else { return }
        #expect(model.points[0].segmentID != model.points[1].segmentID)
        #expect(model.points[1].segmentID != model.points[2].segmentID)
    }

    @Test
    func `unknown or expired reset boundaries preserve samples without claiming a native cycle connection`() throws {
        let start = try Self.date("2026-10-15T10:00:00Z")
        let now = start.addingTimeInterval(2 * 3600)
        let model = try Self.build(
            [
                Self.entry(
                    start,
                    used: 10),
                Self.entry(
                    start.addingTimeInterval(1800),
                    used: 20),
                Self.entry(
                    start.addingTimeInterval(3600),
                    used: 30,
                    reset: start.addingTimeInterval(-1)),
            ],
            now: now,
            calendar: Self.calendar("UTC"))
        #expect(model.sampleCount == 3)
        #expect(Set(model.points.map(\.segmentID)).count == 3)
    }

    @Test
    func `zero cadence observations connect nearby balances without manufacturing reset points`() throws {
        let start = try Self.date("2026-10-15T10:00:00Z")
        let now = start.addingTimeInterval(3600)
        let history = PlanUtilizationSeriesHistory(
            name: .antigravityGemini,
            windowMinutes: 0,
            entries: [
                Self.entry(
                    start,
                    used: 10), Self.entry(
                    now,
                    used: 20),
            ])
        let model = try SpendPlanHistoryTimelineModel.build(
            history: history,
            period: .rolling(days: 7),
            now: now,
            calendar: Self.calendar("UTC"))
        #expect(model.points.map(\.capturedAt) == [start, now])
        #expect(model.points.map(\.remainingPercent) == [90, 80])
        #expect(Set(model.points.map(\.segmentID)).count == 1)
    }

    @Test
    func `missing history is empty rather than a fabricated zero balance`() throws {
        let now = try Self.date("2026-10-15T12:00:00Z")
        let model = try SpendPlanHistoryTimelineModel.build(
            history: nil,
            period: .rolling(days: 30),
            now: now,
            calendar: Self.calendar("UTC"))
        #expect(model.points.isEmpty)
        #expect(model.sampleCount == 0)
        #expect(model.recordedRange == nil)
        #expect(try model.domain.lowerBound == (Self.date("2026-09-16T00:00:00Z")))
        #expect(try model.domain.upperBound == (Self.date("2026-10-16T00:00:00Z")))
    }

    @Test
    func `invalid values and future captures are excluded but measured zero and full usage survive`() throws {
        let now = try Self.date("2026-10-15T12:00:00Z")
        let zero = now.addingTimeInterval(-60)
        let reset = now.addingTimeInterval(7 * 86400)
        let model = try Self.build(
            [
                Self.entry(
                    now.addingTimeInterval(-3600),
                    used: .nan),
                Self.entry(
                    now.addingTimeInterval(-3500),
                    used: .infinity),
                Self.entry(
                    now.addingTimeInterval(-3400),
                    used: -1),
                Self.entry(
                    now.addingTimeInterval(-3300),
                    used: 100.1),
                Self.entry(
                    Date(timeIntervalSince1970: .nan),
                    used: 30),
                Self.entry(
                    Date(timeIntervalSince1970: .infinity),
                    used: 30),
                Self.entry(
                    zero,
                    used: 0,
                    reset: reset),
                Self.entry(
                    now,
                    used: 100,
                    reset: reset),
                Self.entry(
                    now.addingTimeInterval(1),
                    used: 50,
                    reset: reset),
            ],
            now: now,
            calendar: Self.calendar("UTC"))
        #expect(model.points.map(\.capturedAt) == [zero, now])
        #expect(model.points.map(\.remainingPercent) == [100, 0])
    }

    @Test
    func `month domain and filtering follow the reporting time zone across a UTC month boundary`() throws {
        let now = try Self.date("2026-11-01T00:30:00Z")
        let captured = try Self.date("2026-10-31T16:00:00Z")
        let model = try Self.build(
            [
                Self.entry(
                    Self.date("2026-10-31T14:59:59Z"),
                    used: 10),
                Self.entry(
                    captured,
                    used: 20),
            ],
            period: .monthToDate,
            now: now,
            calendar: Self.calendar("Asia/Tokyo"))
        #expect(model.points.map(\.capturedAt) == [captured])
        #expect(try model.domain.lowerBound == (Self.date("2026-10-31T15:00:00Z")))
        #expect(try model.domain.upperBound == (Self.date("2026-11-01T15:00:00Z")))
    }

    @Test(arguments: [
        ("2026-03-09T12:00:00Z", "2026-03-08T05:00:00Z", "2026-03-10T04:00:00Z", 47.0),
        ("2026-11-02T12:00:00Z", "2026-11-01T04:00:00Z", "2026-11-03T05:00:00Z", 49.0),
    ])
    func `date domains use natural days across both daylight saving transitions`(
        example: (String, String, String, Double)) throws
    {
        let now = try Self.date(example.0)
        let first = try Self.date(example.1)
        let model = try Self.build(
            [
                Self.entry(
                    first.addingTimeInterval(-1),
                    used: 10), Self.entry(
                    first,
                    used: 20),
            ],
            period: .rolling(days: 2),
            now: now,
            calendar: Self.calendar("America/New_York"))
        #expect(model.points.map(\.capturedAt) == [first])
        #expect(model.domain.lowerBound == first)
        #expect(try model.domain.upperBound == (Self.date(example.2)))
        #expect(model.domain.upperBound.timeIntervalSince(model.domain.lowerBound) == example.3 * 3600)
    }

    @Test
    func `all time starts with the oldest valid observation rather than an invalid older record`() throws {
        let now = try Self.date("2026-10-15T12:00:00Z")
        let ancient = try Self.date("2000-01-01T10:00:00Z")
        let latest = now.addingTimeInterval(-3600)
        let model = try Self.build(
            [
                Self.entry(
                    Self.date("1950-01-01T00:00:00Z"),
                    used: .nan),
                Self.entry(
                    ancient,
                    used: 10), Self.entry(
                    latest,
                    used: 20),
                Self.entry(
                    now.addingTimeInterval(1),
                    used: 30),
            ],
            period: .allTime,
            now: now,
            calendar: Self.calendar("UTC"))
        #expect(model.points.map(\.capturedAt) == [ancient, latest])
        #expect(try model.domain.lowerBound == (Self.date("2000-01-01T00:00:00Z")))
        #expect(try model.domain.upperBound == (Self.date("2026-10-16T00:00:00Z")))
        #expect(model.recordedRange?.lowerBound == ancient)
        #expect(model.recordedRange?.upperBound == latest)
    }

    @Test
    func `empty and single point all time charts retain a usable natural day domain`() throws {
        let now = try Self.date("2026-10-15T12:00:00Z")
        let calendar = try Self.calendar("UTC")
        let empty = SpendPlanHistoryTimelineModel.build(
            history: nil,
            period: .allTime,
            now: now,
            calendar: calendar)
        #expect(empty.sampleCount == 0)
        #expect(empty.recordedRange == nil)
        #expect(try empty.domain.lowerBound == (Self.date("2026-10-15T00:00:00Z")))
        #expect(try empty.domain.upperBound == (Self.date("2026-10-16T00:00:00Z")))
        let single = Self.build(
            [Self.entry(
                now,
                used: 0)],
            period: .allTime,
            now: now,
            calendar: calendar)
        #expect(single.sampleCount == 1)
        #expect(single.domain == empty.domain)
        #expect(single.recordedRange?.lowerBound == now)
        #expect(single.recordedRange?.upperBound == now)
    }

    @Test
    func `dense history keeps all real observations while drawing preserves endpoints and extrema`() throws {
        let now = try Self.date("2026-10-15T12:00:00Z")
        let entries = (0...4000).map { index in
            let used: Double = switch index {
            case 1001: 100
            case 3003: 0
            default: 50
            }
            return Self.entry(
                now.addingTimeInterval(Double(index - 4000)),
                used: used)
        }
        let model = try Self.build(
            entries,
            now: now,
            calendar: Self.calendar("UTC"))
        #expect(model.sampleCount == 4001)
        #expect(model.points.count == 4001)
        #expect(model.drawingPoints.count <= 1000)
        #expect(model.drawingPoints.count < model.points.count)
        #expect(model.drawingPoints.first == model.points.first)
        #expect(model.drawingPoints.last == model.points.last)
        let fullByDate = Dictionary(uniqueKeysWithValues: model.points.map { ($0.capturedAt, $0) })
        let allDrawnPointsAreReal = model.drawingPoints.allSatisfy { fullByDate[$0.capturedAt] == $0 }
        #expect(allDrawnPointsAreReal)
        let drawnDates = Set(model.drawingPoints.map(\.capturedAt))
        #expect(drawnDates.contains(entries[1001].capturedAt))
        #expect(drawnDates.contains(entries[3003].capturedAt))
        #expect(model.drawingPoints.map(\.remainingPercent).min() == 0)
        #expect(model.drawingPoints.map(\.remainingPercent).max() == 100)
    }

    @Test
    func `nearest inspection returns actual neighbors and endpoints without accepting invalid dates`() throws {
        let start = try Self.date("2026-10-15T10:00:00Z")
        let middleDate = start.addingTimeInterval(600)
        let end = start.addingTimeInterval(1200)
        let now = start.addingTimeInterval(1800)
        let model = try Self.build(
            [
                Self.entry(
                    start,
                    used: 10), Self.entry(
                    middleDate,
                    used: 20), Self.entry(
                    end,
                    used: 30),
            ],
            now: now,
            calendar: Self.calendar("UTC"))
        let first = try #require(model.points.first)
        let middle = try #require(model.points.first { $0.capturedAt == middleDate })
        let last = try #require(model.points.last)
        #expect(model.point(nearestTo: start.addingTimeInterval(-1)) == first)
        #expect(model.point(nearestTo: start) == first)
        #expect(model.point(nearestTo: start.addingTimeInterval(240)) == first)
        #expect(model.point(nearestTo: start.addingTimeInterval(360)) == middle)
        #expect(model.point(nearestTo: middleDate) == middle)
        #expect(model.point(nearestTo: middleDate.addingTimeInterval(240)) == middle)
        #expect(model.point(nearestTo: middleDate.addingTimeInterval(360)) == last)
        #expect(model.point(nearestTo: end) == last)
        #expect(model.point(nearestTo: end.addingTimeInterval(1)) == last)
        #expect(model.point(nearestTo: Date(timeIntervalSince1970: .nan)) == nil)
        #expect(model.point(nearestTo: Date(timeIntervalSince1970: .infinity)) == nil)
        let empty = try Self.build(
            [],
            now: now,
            calendar: Self.calendar("UTC"))
        #expect(empty.point(nearestTo: start) == nil)
    }

    private static func build(
        _ entries: [PlanUtilizationHistoryEntry],
        period: CostReportingPeriod = .rolling(days: 7),
        now: Date,
        calendar: Calendar) -> SpendPlanHistoryTimelineModel
    {
        SpendPlanHistoryTimelineModel.build(
            history: PlanUtilizationSeriesHistory(
                name: .weekly,
                windowMinutes: 10080,
                entries: entries),
            period: period,
            now: now,
            calendar: calendar)
    }

    private static func entry(
        _ date: Date,
        used: Double,
        reset: Date? = nil) -> PlanUtilizationHistoryEntry
    {
        PlanUtilizationHistoryEntry(
            capturedAt: date,
            usedPercent: used,
            resetsAt: reset)
    }

    private static func date(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    private static func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }
}
