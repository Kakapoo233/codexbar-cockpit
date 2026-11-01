import Foundation
import Testing
@testable import CodexBarCore

struct CockpitRecommendationPaceTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func status(
        on date: Date,
        suggested: Double? = 20,
        used: Double? = 12,
        manualCap: Double? = nil,
        coverage: CockpitCoverage = .complete,
        stale: Bool = false,
        reset: Date? = nil,
        calendar: Calendar? = nil) -> CockpitDayStatus
    {
        CockpitDayStatus(
            localDateKey: CockpitCalendar.dateKey(for: date, calendar: calendar ?? self.calendar),
            suggestedPercent: suggested,
            manualCapPercent: manualCap,
            usedPercent: used,
            coverage: coverage,
            remainingPercent: 60,
            resetsAt: reset ?? date.addingTimeInterval(86400),
            feeling: nil,
            isStale: stale)
    }

    @Test
    func `recommendation advances with the local day without shrinking the full day target`() throws {
        let noon = self.date("2026-07-06T12:00:00Z")
        let pace = try #require(CockpitRecommendationPace(
            status: self.status(on: noon), on: noon, calendar: self.calendar))
        #expect(pace.suggestedPercent == 20)
        #expect(pace.observedUsedPercent == 12)
        #expect(pace.elapsedDayFraction == 0.5)
        #expect(pace.expectedUsedPercent == 10)
        #expect(pace.deltaPercent == 2)
        #expect(!pace.isLowerBound)

        let evening = self.date("2026-07-06T18:00:00Z")
        let later = try #require(CockpitRecommendationPace(
            status: self.status(on: evening), on: evening, calendar: self.calendar))
        #expect(later.suggestedPercent == 20)
        #expect(later.expectedUsedPercent == 15)
        #expect(later.deltaPercent == -3)
    }

    @Test
    func `comfort and reset recommendation changes immediately move the pace reference`() throws {
        let now = self.date("2026-07-06T12:00:00Z")
        let before = try #require(CockpitRecommendationPace(
            status: self.status(on: now, suggested: 20), on: now, calendar: self.calendar))
        let after = try #require(CockpitRecommendationPace(
            status: self.status(on: now, suggested: 40), on: now, calendar: self.calendar))
        #expect(before.deltaPercent == 2)
        #expect(after.expectedUsedPercent == 20)
        #expect(after.deltaPercent == -8)
        let capped = try #require(CockpitRecommendationPace(
            status: self.status(on: now, suggested: 40, manualCap: 1), on: now, calendar: self.calendar))
        #expect(capped == after)
    }

    @Test
    func `spending the live balance moves pace without awarding another daily allocation`() throws {
        let now = self.date("2026-07-06T12:00:00Z")
        let reset = now.addingTimeInterval(6 * 86400)
        var state = CockpitPlanState()
        for date in [self.calendar.startOfDay(for: now), now] {
            state.record(
                CockpitQuotaSnapshot(
                    providerID: "codex", capturedAt: date, remainingPercent: 90, resetsAt: reset),
                calendar: self.calendar)
        }
        let before = try #require(CockpitRecommendationPace(
            status: state.status(providerID: "codex", on: now, calendar: self.calendar),
            on: now,
            calendar: self.calendar))
        state.record(
            CockpitQuotaSnapshot(providerID: "codex", capturedAt: now, remainingPercent: 80, resetsAt: reset),
            calendar: self.calendar)
        let after = try #require(CockpitRecommendationPace(
            status: state.status(providerID: "codex", on: now, calendar: self.calendar),
            on: now,
            calendar: self.calendar))
        #expect(after.suggestedPercent == before.suggestedPercent)
        #expect(after.expectedUsedPercent == before.expectedUsedPercent)
        #expect(after.observedUsedPercent == before.observedUsedPercent + 10)
        #expect(after.deltaPercent == before.deltaPercent + 10)
    }

    @Test
    func `known zero recommendations remain zero and usage is not a daily utilization ratio`() throws {
        let now = self.date("2026-07-06T12:00:00Z")
        let zero = try #require(CockpitRecommendationPace(
            status: self.status(on: now, suggested: 0, used: 0), on: now, calendar: self.calendar))
        #expect(zero.expectedUsedPercent == 0)
        #expect(zero.deltaPercent == 0)
        let spent = try #require(CockpitRecommendationPace(
            status: self.status(on: now, suggested: 0, used: 4), on: now, calendar: self.calendar))
        #expect(spent.deltaPercent == 4)
    }

    @Test
    func `midnight and both daylight saving transitions use actual local day durations`() throws {
        let midnight = self.date("2026-07-06T00:00:00Z")
        let start = try #require(CockpitRecommendationPace(
            status: self.status(on: midnight, used: 0), on: midnight, calendar: self.calendar))
        #expect(start.elapsedDayFraction == 0)
        #expect(start.expectedUsedPercent == 0)

        var calendar = self.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        for value in ["2026-03-08T16:00:00Z", "2026-11-01T17:00:00Z"] {
            let noon = self.date(value)
            let interval = try #require(calendar.dateInterval(of: .day, for: noon))
            let pace = try #require(CockpitRecommendationPace(
                status: self.status(on: noon, calendar: calendar), on: noon, calendar: calendar))
            let expectedFraction = noon.timeIntervalSince(interval.start) / interval.duration
            #expect(abs(pace.elapsedDayFraction - expectedFraction) < 1e-12)
            #expect(abs(pace.expectedUsedPercent - 20 * expectedFraction) < 1e-12)
        }
    }

    @Test
    func `a reset day preserves all observed daily use including prior cycles`() throws {
        let now = self.date("2026-07-06T18:00:00Z")
        let pace = try #require(CockpitRecommendationPace(
            status: self.status(on: now, suggested: 40, used: 130), on: now, calendar: self.calendar))
        #expect(pace.observedUsedPercent == 130)
        #expect(pace.expectedUsedPercent == 30)
        #expect(pace.deltaPercent == 100)
    }

    @Test
    func `partial observations retain one sided uncertainty even when the measured delta is negative`() throws {
        let now = self.date("2026-07-06T12:00:00Z")
        let pace = try #require(CockpitRecommendationPace(
            status: self.status(on: now, used: 1, coverage: .partial), on: now, calendar: self.calendar))
        #expect(pace.deltaPercent == -9)
        #expect(pace.isLowerBound)
        var uncertainSuggestion = self.status(on: now)
        uncertainSuggestion.suggestionIsPartial = true
        #expect(CockpitRecommendationPace(
            status: uncertainSuggestion, on: now, calendar: self.calendar)?.isLowerBound == true)
    }

    @Test
    func `missing stale mismatched or expired inputs do not manufacture a pace`() {
        let now = self.date("2026-07-06T12:00:00Z")
        for status in [
            self.status(on: now, suggested: nil),
            self.status(on: now, used: nil),
            self.status(on: now, coverage: .unavailable),
            self.status(on: now, stale: true),
            self.status(on: now, reset: now),
            self.status(on: now, reset: now.addingTimeInterval(-1)),
            self.status(on: now.addingTimeInterval(-86400)),
        ] {
            #expect(CockpitRecommendationPace(status: status, on: now, calendar: self.calendar) == nil)
        }
        var expiredPublicHorizon = self.status(on: now)
        expiredPublicHorizon.planningResetWindow = CockpitPlanningResetWindow(resetsAt: now, source: .announced)
        #expect(CockpitRecommendationPace(
            status: expiredPublicHorizon, on: now, calendar: self.calendar) == nil)
    }

    @Test
    func `nonfinite and negative measurements are rejected`() {
        let now = self.date("2026-07-06T12:00:00Z")
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            #expect(CockpitRecommendationPace(
                status: self.status(on: now, suggested: invalid), on: now, calendar: self.calendar) == nil)
            #expect(CockpitRecommendationPace(
                status: self.status(on: now, used: invalid), on: now, calendar: self.calendar) == nil)
        }
        #expect(CockpitRecommendationPace(
            status: self.status(on: now, reset: Date(timeIntervalSince1970: .infinity)),
            on: now,
            calendar: self.calendar) == nil)
        #expect(CockpitRecommendationPace(
            status: self.status(on: now),
            on: Date(timeIntervalSince1970: .nan),
            calendar: self.calendar) == nil)
    }
}
