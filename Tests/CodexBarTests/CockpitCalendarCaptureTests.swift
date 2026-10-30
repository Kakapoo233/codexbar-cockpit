import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CockpitCalendarCaptureTests {
    @Test
    func `today may attach a verified device sample but editing an existing complete sample preserves it`() throws {
        let calendar = try Self.calendar("America/New_York")
        let now = Date(timeIntervalSince1970: 1_793_275_200)
        let earlier = now.addingTimeInterval(-60)
        #expect(CockpitCalendarProjection.canCaptureTokens(
            on: earlier,
            now: now,
            existingRecord: nil,
            calendar: calendar))

        let complete = Self.record(on: earlier, calendar: calendar, tokens: 1200, coverage: .complete)
        #expect(!CockpitCalendarProjection.canCaptureTokens(
            on: earlier,
            now: now,
            existingRecord: complete,
            calendar: calendar))
        let partial = Self.record(on: earlier, calendar: calendar, tokens: nil, coverage: .partial)
        #expect(CockpitCalendarProjection.canCaptureTokens(
            on: earlier,
            now: now,
            existingRecord: partial,
            calendar: calendar))
    }

    @Test
    func `historical and future days never receive the current device measurement across a local midnight`() throws {
        let calendar = try Self.calendar("America/New_York")
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0)))
        let yesterday = now.addingTimeInterval(-1)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        for date in [yesterday, tomorrow] {
            #expect(!CockpitCalendarProjection.canCaptureTokens(
                on: date,
                now: now,
                existingRecord: nil,
                calendar: calendar))
        }
        #expect(CockpitCalendarProjection.canRecord(on: yesterday, now: now, calendar: calendar))
        #expect(!CockpitCalendarProjection.canRecord(on: tomorrow, now: now, calendar: calendar))
    }

    @Test
    func `calendar history and measurements stay within the selected provider machine and bucket timezone`() throws {
        let calendar = try Self.calendar("America/New_York")
        let otherCalendar = try Self.calendar("UTC")
        let now = Date(timeIntervalSince1970: 1_793_275_200)
        let expected = Self.record(on: now, calendar: calendar, tokens: 1200, coverage: .complete)
        let records = [
            Self.record(on: now, calendar: calendar, providerID: "claude", tokens: 4000, coverage: .complete),
            Self.record(on: now, calendar: calendar, accountID: "quota-account", tokens: 8000, coverage: .complete),
            Self.record(on: now, calendar: otherCalendar, tokens: 16000, coverage: .complete),
            expected,
        ]
        #expect(CockpitCalendarProjection.record(
            on: now,
            providerID: "codex",
            records: records,
            calendar: calendar) == expected)
    }

    private static func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }

    private static func record(
        on date: Date,
        calendar: Calendar,
        providerID: String = "codex",
        accountID: String = "local-machine",
        tokens: Int?,
        coverage: CockpitCoverage) -> CockpitComfortRecord
    {
        CockpitComfortRecord(
            providerID: providerID,
            accountID: accountID,
            localDateKey: CockpitCalendar.dateKey(for: date, calendar: calendar),
            timeZoneIdentifier: calendar.timeZone.identifier,
            recordedAt: date,
            feeling: .comfortable,
            totalTokens: tokens,
            coverage: coverage)
    }
}
