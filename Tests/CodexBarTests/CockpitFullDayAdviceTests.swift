import Foundation
import Testing
@testable import CodexBarCore

struct CockpitFullDayAdviceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var start: Date {
        Date(timeIntervalSince1970: 1_798_761_600)
    }

    @Test
    func `an unused full day allowance does not shrink as the clock advances`() {
        let calendar = self.calendar
        let start = calendar.startOfDay(for: self.start)
        let morning = start.addingTimeInterval(8 * 3600)
        let reset = morning.addingTimeInterval(6 * 86400)
        var state = CockpitPlanState()
        for offset in 0...16 {
            state.record(CockpitQuotaSnapshot(
                providerID: "codex",
                capturedAt: start.addingTimeInterval(Double(offset) * 1800),
                remainingPercent: 90,
                resetsAt: reset), calendar: calendar)
        }
        let anchors = state.plans
        let morningStatus = state.status(
            providerID: "codex",
            on: morning,
            calendar: calendar,
            resetRisk: CockpitResetRisk.none)
        #expect(morningStatus.coverage == .complete)
        #expect(morningStatus.usedPercent == 0)
        #expect(morningStatus.suggestedPercent == 15)
        #expect(morningStatus.remainingSuggestedPercent == 15)
        let evening = state.status(
            providerID: "codex",
            on: start.addingTimeInterval(22 * 3600),
            calendar: calendar,
            resetRisk: CockpitResetRisk.none)
        #expect((evening.suggestedPercent ?? 0) >= (morningStatus.suggestedPercent ?? 0))
        #expect(state.plans == anchors)
    }

    @Test
    func `spending reduces the remaining allowance without increasing the full day target`() {
        let calendar = self.calendar
        let start = calendar.startOfDay(for: self.start)
        let now = start.addingTimeInterval(8 * 3600)
        let reset = now.addingTimeInterval(6 * 86400)
        var unspent = CockpitPlanState()
        unspent.record(CockpitQuotaSnapshot(
            providerID: "codex",
            capturedAt: start,
            remainingPercent: 90,
            resetsAt: reset), calendar: calendar)
        unspent.record(CockpitQuotaSnapshot(
            providerID: "codex",
            capturedAt: now,
            remainingPercent: 90,
            resetsAt: reset), calendar: calendar)
        var spent = CockpitPlanState()
        spent.record(CockpitQuotaSnapshot(
            providerID: "codex",
            capturedAt: start,
            remainingPercent: 90,
            resetsAt: reset), calendar: calendar)
        spent.record(CockpitQuotaSnapshot(
            providerID: "codex",
            capturedAt: now,
            remainingPercent: 80,
            resetsAt: reset), calendar: calendar)
        let before = unspent.status(providerID: "codex", on: now, calendar: calendar, resetRisk: CockpitResetRisk.none)
        let after = spent.status(providerID: "codex", on: now, calendar: calendar, resetRisk: CockpitResetRisk.none)
        #expect(before.suggestedPercent == 15)
        #expect(after.suggestedPercent == before.suggestedPercent)
        #expect(after.usedPercent == 10)
        #expect(after.remainingSuggestedPercent == 5)
    }

    @Test
    func `earlier cycles stay consumed rather than entering a renewed quota pool`() {
        let calendar = self.calendar
        let start = calendar.startOfDay(for: self.start)
        let now = start.addingTimeInterval(8 * 3600)
        let reset = now.addingTimeInterval(6 * 86400)
        var state = CockpitPlanState()
        let observations: [(Double, Double, Date)] = [
            (0, 100, start.addingTimeInterval(4 * 3600)),
            (3.5, 20, start.addingTimeInterval(4 * 3600)),
            (4, 100, now),
            (7.5, 10, now),
            (8, 90, reset),
        ]
        for (hour, remaining, deadline) in observations {
            state.record(CockpitQuotaSnapshot(
                providerID: "codex",
                capturedAt: start.addingTimeInterval(hour * 3600),
                remainingPercent: remaining,
                resetsAt: deadline), calendar: calendar)
        }
        let status = state.status(providerID: "codex", on: now, calendar: calendar, resetRisk: CockpitResetRisk.none)
        #expect(status.usedPercent == 180)
        #expect(abs((status.comfortAdvice?.baseDailyPercent ?? 0) - 186.6666667) < 0.0001)
        #expect(status.suggestedPercent == status.comfortAdvice?.softCapPercent)
        #expect(status.remainingSuggestedPercent == 0)
        #expect(status.remainingPercent == 90)
    }

    @Test(arguments: [
        ("2026-03-08T05:00:00Z", 23.0, 15.33),
        ("2026-11-01T04:00:00Z", 25.0, 16.67),
    ])
    func `the full local day uses its actual DST duration`(example: (String, Double, Double)) throws {
        var calendar = self.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let start = try #require(ISO8601DateFormatter().date(from: example.0))
        let now = start.addingTimeInterval(8 * 3600)
        var state = CockpitPlanState()
        state.record(CockpitQuotaSnapshot(
            providerID: "codex",
            capturedAt: start,
            remainingPercent: 96,
            resetsAt: now.addingTimeInterval(6 * 86400)), calendar: calendar)
        #expect(calendar.dateInterval(of: .day, for: now)?.duration == example.1 * 3600)
        #expect(state.status(providerID: "codex", on: now, calendar: calendar, resetRisk: CockpitResetRisk.none)
            .suggestedPercent == example.2)
    }

    @Test
    func `a partial first observation does not imply a measured remaining daily allowance`() {
        let now = self.calendar.startOfDay(for: self.start).addingTimeInterval(8 * 3600)
        var state = CockpitPlanState()
        state.record(CockpitQuotaSnapshot(
            providerID: "codex",
            capturedAt: now,
            remainingPercent: 90,
            resetsAt: now.addingTimeInterval(6 * 86400)), calendar: self.calendar)
        let status = state.status(
            providerID: "codex",
            on: now,
            calendar: self.calendar,
            resetRisk: CockpitResetRisk.none)
        #expect(status.suggestedPercent == 15)
        #expect(status.suggestionIsPartial)
        #expect(status.usedPercent == nil)
        #expect(status.remainingSuggestedPercent == nil)
    }

    @Test
    func `manual allowance cannot exceed remaining quota or survive an expired balance`() {
        let start = self.calendar.startOfDay(for: self.start)
        let reset = start.addingTimeInterval(3600)
        var state = CockpitPlanState()
        state.record(CockpitQuotaSnapshot(
            providerID: "codex",
            capturedAt: start,
            remainingPercent: 2,
            resetsAt: reset), calendar: self.calendar)
        state.setPersonalCap(100, providerID: "codex", on: start, calendar: self.calendar)
        let status = state.status(
            providerID: "codex",
            on: start,
            calendar: self.calendar,
            resetRisk: CockpitResetRisk.none)
        #expect(status.suggestedPercent == 2)
        #expect(status.manualCapPercent == 100)
        #expect(status.remainingSuggestedPercent == 2)
        #expect(state.status(providerID: "codex", on: reset, calendar: self.calendar, resetRisk: CockpitResetRisk.none)
            .remainingSuggestedPercent == nil)
    }
}
