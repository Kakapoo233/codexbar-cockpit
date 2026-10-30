import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CockpitCalendarPeriodTests {
    @Test
    func `local days use calendar boundaries through both daylight saving transitions`() throws {
        let calendar = try Self.calendar()
        let spring = try CockpitCalendarPeriod(
            containing: Self.date(2026, 3, 8, calendar: calendar), scale: .day, calendar: calendar)
        let autumn = try CockpitCalendarPeriod(
            containing: Self.date(2026, 11, 1, calendar: calendar), scale: .day, calendar: calendar)
        #expect(spring.end.timeIntervalSince(spring.start) == 23 * 3600)
        #expect(autumn.end.timeIntervalSince(autumn.start) == 25 * 3600)
        #expect(spring.days(calendar: calendar).count == 1)
        #expect(autumn.days(calendar: calendar).count == 1)
        #expect(!spring.contains(spring.end))
    }

    @Test
    func `weeks follow the first weekday and quarters shift across the year`() throws {
        var calendar = try Self.calendar()
        calendar.firstWeekday = 2
        let week = try CockpitCalendarPeriod(
            containing: Self.date(2026, 11, 1, calendar: calendar), scale: .week, calendar: calendar)
        #expect(calendar.component(.weekday, from: week.start) == 2)
        #expect(week.days(calendar: calendar).count == 7)
        #expect(week.end.timeIntervalSince(week.start) == 169 * 3600)
        let quarter = try CockpitCalendarPeriod(
            containing: Self.date(2026, 12, 25, calendar: calendar), scale: .quarter, calendar: calendar)
        #expect(try quarter.start == (Self.date(2026, 10, 1, hour: 0, calendar: calendar)))
        let next = quarter.shifted(by: 1, calendar: calendar)
        #expect(try next.start == (Self.date(2027, 1, 1, hour: 0, calendar: calendar)))
        #expect(next.shifted(by: -1, calendar: calendar) == quarter)
    }

    @Test
    func `leap years contain every local day and future days are excluded from totals`() throws {
        let calendar = try Self.calendar()
        let now = try Self.date(2028, 2, 29, calendar: calendar)
        let year = CockpitCalendarPeriod(containing: now, scale: .year, calendar: calendar)
        #expect(year.days(calendar: calendar).count == 366)
        #expect(year.days(calendar: calendar, through: now).count == 60)
        #expect(year.days(calendar: calendar, through: year.start.addingTimeInterval(-1)).isEmpty)
    }

    @Test
    func `period totals preserve separate currencies missing days and measured zero`() throws {
        let calendar = try Self.calendar()
        let first = try Self.date(2026, 10, 1, hour: 0, calendar: calendar)
        let second = try Self.date(2026, 10, 2, hour: 0, calendar: calendar)
        let third = try Self.date(2026, 10, 3, hour: 0, calendar: calendar)
        let model = SpendDashboardModel(
            requestedDays: 365,
            groups: [
                Self.group("USD", summaries: [
                    Self.row(first, tokens: 100, cost: 1),
                    Self.row(second, tokens: 0, cost: 0),
                ]),
                Self.group("EUR", summaries: [Self.row(first, tokens: 200, cost: 2)]),
            ],
            selectedDay: nil)
        let ledger = CockpitCalendarLedger(model: model, calendar: calendar, now: third)
        let period = CockpitCalendarPeriod(containing: first, scale: .month, calendar: calendar)
        let result = ledger.summary(for: period)
        #expect(result.tokens.total == 300)
        #expect(result.tokens.isPartial)
        #expect(result.costs == [
            .init(currencyCode: "USD", total: 1, isPartial: true),
            .init(currencyCode: "EUR", total: 2, isPartial: true),
        ])
        let idle = CockpitCalendarLedger(
            model: SpendDashboardModel(
                requestedDays: 365,
                groups: [Self.group("USD", summaries: [Self.row(second, tokens: 0, cost: 0)])],
                selectedDay: nil),
            calendar: calendar,
            now: second)
        let idleResult = idle.summary(for: .init(containing: second, scale: .day, calendar: calendar))
        #expect(idleResult.tokens == .init(total: 0, isPartial: false))
        #expect(idleResult.costs == [.init(currencyCode: "USD", total: 0, isPartial: false)])
    }

    @Test
    func `missing history remains unavailable and future or outside records do not enter the range`() throws {
        let calendar = try Self.calendar()
        let now = try Self.date(2026, 10, 2, calendar: calendar)
        let old = try Self.date(2025, 1, 1, calendar: calendar)
        let future = try Self.date(2026, 10, 3, calendar: calendar)
        let model = SpendDashboardModel(
            requestedDays: 365,
            groups: [Self.group("USD", summaries: [
                Self.row(old, tokens: 999, cost: 999),
                Self.row(future, tokens: 999, cost: 999),
            ])],
            selectedDay: nil)
        let ledger = CockpitCalendarLedger(model: model, calendar: calendar, now: now)
        let result = ledger.summary(for: .init(containing: now, scale: .year, calendar: calendar))
        #expect(result.tokens == .init(total: nil, isPartial: true))
        #expect(result.costs == [.init(currencyCode: "USD", total: nil, isPartial: true)])
    }

    @Test
    func `partial source values and integer overflow cannot become exact totals`() throws {
        let calendar = try Self.calendar()
        let day = try Self.date(2026, 10, 2, hour: 0, calendar: calendar)
        let partial = Self.row(day, tokens: 100, cost: 1, partial: true)
        let partialLedger = CockpitCalendarLedger(
            model: SpendDashboardModel(
                requestedDays: 365,
                groups: [Self.group("USD", summaries: [partial])],
                selectedDay: nil),
            calendar: calendar,
            now: day)
        let period = CockpitCalendarPeriod(containing: day, scale: .day, calendar: calendar)
        #expect(partialLedger.summary(for: period).tokens == .init(total: 100, isPartial: true))
        #expect(partialLedger.summary(for: period).costs.first?.isPartial == true)
        let overflow = CockpitCalendarLedger(
            model: SpendDashboardModel(
                requestedDays: 365,
                groups: [
                    Self.group("USD", summaries: [Self.row(day, tokens: Int.max, cost: nil)]),
                    Self.group("EUR", summaries: [Self.row(day, tokens: 1, cost: nil)]),
                ],
                selectedDay: nil),
            calendar: calendar,
            now: day)
        #expect(overflow.summary(for: period).tokens.total == nil)
    }

    private static func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        return calendar
    }

    private static func date(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 12, calendar: Calendar) throws -> Date
    {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private static func row(
        _ day: Date, tokens: Int?, cost: Double?, partial: Bool = false) -> SpendDashboardModel.DailySummary
    {
        .init(
            day: day,
            providers: [.init(
                costIsLowerBound: partial,
                countsAreLowerBound: partial,
                sourceID: "synthetic",
                provider: .codex,
                displayName: "Synthetic Codex",
                totalTokens: tokens,
                requestCount: nil,
                totalCost: cost)],
            totalTokens: tokens,
            requestCount: nil,
            totalCost: cost)
    }

    private static func group(
        _ currency: String, summaries: [SpendDashboardModel.DailySummary]) -> SpendDashboardModel.CurrencyGroup
    {
        let day = summaries.first?.day ?? .distantPast
        return .init(
            currencyCode: currency,
            providers: [],
            models: [],
            dailyPoints: [],
            dailySummaries: summaries,
            totalTokens: nil,
            totalCost: nil,
            coveredDayCount: summaries.count,
            chartDomain: day...day,
            modelHistoryCompleteness: .complete)
    }
}
