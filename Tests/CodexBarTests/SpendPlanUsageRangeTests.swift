import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct SpendPlanUsageRangeTests {
    @Test(arguments: [63, 2160, 17520])
    func `long range bars and hover widths fit their sample spacing`(count: Int) {
        for width: CGFloat in [320, 800] {
            let barWidth = PlanUtilizationHistoryChartMenuView.barWidth(pointCount: count, plotWidth: width)
            let spacing = (width - 2 * ChartAxisLabelLayout.dateLabelEdgePadding) / CGFloat(count)
            #expect(barWidth > 0)
            #expect(barWidth <= spacing)
            #expect(ChartBarHoverSelection.accepts(
                distanceFromBarCenter: barWidth / 2, barHalfWidth: barWidth / 2, selectableCount: count))
            #expect(!ChartBarHoverSelection.accepts(
                distanceFromBarCenter: spacing / 2, barHalfWidth: barWidth / 2, selectableCount: count))
        }
        #expect(PlanUtilizationHistoryChartMenuView.barWidth(pointCount: 30, plotWidth: 320) == 6)
    }

    @Test
    func `statistics retains more than thirty chart samples while menu charts retain their compact limit`() throws {
        let now = try Self.date("2026-10-15T12:00:00Z")
        let history = PlanUtilizationSeriesHistory(
            name: .antigravityGemini,
            windowMinutes: 0,
            entries: (0..<63).map { offset in
                Self.entry(now.addingTimeInterval(Double(-offset) * 86400), used: Double(offset))
            })
        let expanded = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: [history], provider: .antigravity, referenceDate: now, pointLimit: nil)
        let compact = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: [history], provider: .antigravity, referenceDate: now)
        #expect(expanded.pointCount == 63)
        #expect(expanded.xDomain == -0.5...62.5)
        #expect(compact.pointCount == 30)
        #expect(compact.xDomain == -0.5...29.5)
    }

    @MainActor
    @Test(arguments: [
        (CostReportingPeriod.rolling(days: 7), "2026-10-09T00:00:00Z"),
        (CostReportingPeriod.rolling(days: 30), "2026-09-16T00:00:00Z"),
        (CostReportingPeriod.rolling(days: 90), "2026-07-18T00:00:00Z"),
        (CostReportingPeriod.monthToDate, "2026-10-01T00:00:00Z"),
    ])
    func `natural day bounds include their first instant and today observations but exclude future captures`(
        example: (CostReportingPeriod, String)) throws
    {
        let now = try Self.date("2026-10-15T12:00:00Z")
        let start = try Self.date(example.1)
        let duringToday = try Self.date("2026-10-15T09:30:00Z")
        let futureReset = try Self.date("2026-10-20T00:00:00Z")
        let first = Self.entry(start, used: 10, reset: futureReset)
        let today = Self.entry(duringToday, used: 20, reset: futureReset)
        let latest = Self.entry(now, used: 30, reset: futureReset)
        let history = try PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: [
            Self.entry(start.addingTimeInterval(-1), used: 5, reset: futureReset),
            first,
            today,
            latest,
            Self.entry(now.addingTimeInterval(1), used: 40, reset: futureReset),
            Self.entry(Self.date("2026-10-16T00:00:00Z"), used: 50, reset: futureReset),
        ])
        let filtered = try SpendPlanUsageSection.filterHistories(
            [history], period: example.0, now: now, calendar: Self.calendar("UTC"))
        #expect(filtered.count == 1)
        #expect(filtered.first?.entries == [first, today, latest])
        #expect(filtered.first?.name == .weekly)
        #expect(filtered.first?.windowMinutes == 10080)
    }

    @MainActor
    @Test
    func `all time retains old observations while future reset timestamps do not rescue future captures`() throws {
        let now = try Self.date("2026-10-15T12:00:00Z")
        let futureReset = now.addingTimeInterval(7 * 86400)
        let ancient = try Self.entry(Self.date("2000-01-01T00:00:00Z"), used: 10, reset: futureReset)
        let current = Self.entry(now, used: 20, reset: futureReset)
        let future = Self.entry(now.addingTimeInterval(1), used: 30, reset: futureReset)
        let history = PlanUtilizationSeriesHistory(
            name: .weekly, windowMinutes: 10080, entries: [ancient, current, future])
        let filtered = try SpendPlanUsageSection.filterHistories(
            [history], period: .allTime, now: now, calendar: Self.calendar("UTC"))
        #expect(filtered.first?.entries == [ancient, current])
    }

    @MainActor
    @Test
    func `month to date uses the reporting time zone rather than the UTC month`() throws {
        let now = try Self.date("2026-11-01T00:30:00Z")
        let localStart = try Self.entry(Self.date("2026-10-31T15:00:00Z"), used: 10)
        let sameLocalMonth = try Self.entry(Self.date("2026-10-31T16:00:00Z"), used: 20)
        let previousMonth = try Self.entry(Self.date("2026-10-31T14:59:59Z"), used: 5)
        let history = PlanUtilizationSeriesHistory(
            name: .session, windowMinutes: 300, entries: [previousMonth, localStart, sameLocalMonth])
        let filtered = try SpendPlanUsageSection.filterHistories(
            [history], period: .monthToDate, now: now, calendar: Self.calendar("Asia/Tokyo"))
        #expect(filtered.first?.entries == [localStart, sameLocalMonth])
    }

    @MainActor
    @Test(arguments: [
        ("2026-03-09T12:00:00Z", "2026-03-08T05:00:00Z"),
        ("2026-11-02T12:00:00Z", "2026-11-01T04:00:00Z"),
    ])
    func `rolling days honor both short and long daylight saving days`(example: (String, String)) throws {
        let now = try Self.date(example.0)
        let start = try Self.date(example.1)
        let boundary = Self.entry(start, used: 10)
        let insideFirstHour = Self.entry(start.addingTimeInterval(1800), used: 20)
        let history = PlanUtilizationSeriesHistory(name: .session, windowMinutes: 300, entries: [
            Self.entry(start.addingTimeInterval(-1), used: 5),
            boundary,
            insideFirstHour,
        ])
        let filtered = try SpendPlanUsageSection.filterHistories(
            [history], period: .rolling(days: 2), now: now, calendar: Self.calendar("America/New_York"))
        #expect(filtered.first?.entries == [boundary, insideFirstHour])
    }

    @MainActor
    @Test
    func `series retain their order cadence and identities even when a series becomes empty`() throws {
        let now = try Self.date("2026-10-15T12:00:00Z")
        let current = now.addingTimeInterval(-3600)
        let tooOld = now.addingTimeInterval(-120 * 86400)
        let session = Self.entry(current, used: 15)
        let weekly = Self.entry(current, used: 85, reset: now.addingTimeInterval(7 * 86400))
        let histories = [
            PlanUtilizationSeriesHistory(name: .session, windowMinutes: 300, entries: [
                Self.entry(tooOld, used: 5), session,
            ]),
            PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: [
                Self.entry(tooOld, used: 95), weekly,
            ]),
            PlanUtilizationSeriesHistory(name: .antigravityGemini, windowMinutes: 0, entries: [
                Self.entry(tooOld, used: 50),
            ]),
        ]
        let filtered = try SpendPlanUsageSection.filterHistories(
            histories, period: .rolling(days: 7), now: now, calendar: Self.calendar("UTC"))
        #expect(filtered.count == 3)
        #expect(filtered.map(\.name) == [.session, .weekly, .antigravityGemini])
        #expect(filtered.map(\.windowMinutes) == [300, 10080, 0])
        #expect(filtered.map(\.entries) == [[session], [weekly], []])
    }

    private static func entry(_ date: Date, used: Double, reset: Date? = nil) -> PlanUtilizationHistoryEntry {
        PlanUtilizationHistoryEntry(capturedAt: date, usedPercent: used, resetsAt: reset)
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
