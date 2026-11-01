import Foundation
import Testing
@testable import CodexBarCore

struct CockpitComfortAdviceTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var weekday: Date {
        ISO8601DateFormatter().date(from: "2026-07-06T08:00:00Z")!
    }

    private func state(at now: Date, provider: String = "codex", reset: Date? = nil) -> CockpitPlanState {
        let reset = reset ?? now.addingTimeInterval(6 * 86400)
        var state = CockpitPlanState()
        for date in [self.calendar.startOfDay(for: now), now] {
            state.record(
                CockpitQuotaSnapshot(
                    providerID: provider, capturedAt: date, remainingPercent: 90, resetsAt: reset),
                calendar: self.calendar)
        }
        return state
    }

    @Test
    func `the baseline curve uses the upstream squared risk bonus with a full day horizon`() {
        let status = self.state(at: self.weekday).status(
            providerID: "codex",
            on: self.weekday,
            calendar: self.calendar)
        #expect(status.comfortAdvice?.curveStatus == .baseline)
        #expect(status.comfortAdvice?.kneePercent == 25)
        #expect(status.comfortAdvice?.sampleCount == 0)
        #expect(status.comfortAdvice?.risk == .assumed)
        #expect(status.comfortAdvice?.baseDailyPercent == 15)
        #expect(abs((status.comfortAdvice?.riskBonusPercent ?? 0) - 0.75) < 0.0001)
        #expect(abs((status.comfortAdvice?.softCapPercent ?? 0) - 28.75) < 1e-9)
        #expect(status.comfortAdvice?.isComfortLimited == false)
        #expect(status.suggestedPercent == 15.75)
        #expect(status.remainingSuggestedPercent == 15.75)
    }

    @Test
    func `explicit community risk and an imminent announcement change the bonus without creating quota`() {
        let state = self.state(at: self.weekday)
        let estimated = state.status(
            providerID: "codex",
            on: self.weekday,
            calendar: self.calendar,
            resetRisk: CockpitResetRisk(probability: 0.6, source: .estimated))
        #expect(estimated.comfortAdvice?.risk.source == .estimated)
        #expect(estimated.suggestedPercent == 42)
        let announced = state.status(
            providerID: "codex",
            on: self.weekday,
            calendar: self.calendar,
            resetRisk: CockpitResetRisk(probability: 1, source: .announced))
        #expect(announced.comfortAdvice?.riskBonusPercent == 75)
        #expect(announced.comfortAdvice?.isComfortLimited == true)
        #expect(announced.suggestedPercent == 62.5)
        #expect(announced.remainingPercent == 90)
        #expect(state.snapshots.count == 2)
    }

    @Test
    func `weekends apply the upstream fatigue factor to the whole day`() throws {
        let saturday = try #require(ISO8601DateFormatter().date(from: "2026-07-11T08:00:00Z"))
        let state = self.state(at: saturday, reset: saturday.addingTimeInterval(3600))
        let status = state.status(
            providerID: "codex",
            on: saturday,
            calendar: self.calendar)
        #expect(status.comfortAdvice?.isWeekend == true)
        #expect(abs((status.comfortAdvice?.softCapPercent ?? 0) - 21.5625) < 1e-9)
        #expect(status.comfortAdvice?.isComfortLimited == true)
        #expect(status.suggestedPercent == 21.56)
    }

    @Test
    func `fitted quota feedback affects only its own account and excludes future records`() {
        var state = self.state(at: self.weekday)
        let yesterday = self.weekday.addingTimeInterval(-86400)
        state.recordComfort(
            .overloaded,
            providerID: "codex",
            accountID: "other",
            on: yesterday,
            coverage: .complete,
            calendar: self.calendar,
            usedPercent: 10)
        state.recordComfort(
            .overloaded,
            providerID: "codex",
            on: self.weekday.addingTimeInterval(3600),
            coverage: .complete,
            calendar: self.calendar,
            usedPercent: 10)
        let before = state.status(
            providerID: "codex",
            on: self.weekday,
            calendar: self.calendar)
        #expect(before.comfortAdvice?.curveStatus == .baseline)
        state.recordComfort(
            .overloaded,
            providerID: "codex",
            on: yesterday,
            coverage: .complete,
            calendar: self.calendar,
            usedPercent: 10)
        let fitted = state.status(
            providerID: "codex",
            on: self.weekday,
            calendar: self.calendar)
        #expect(fitted.comfortAdvice?.curveStatus == .fitted)
        #expect(fitted.comfortAdvice?.sampleCount == 1)
        #expect((fitted.comfortAdvice?.kneePercent ?? 100) < 25)
        #expect(fitted.comfortAdvice?.isComfortLimited == true)
        #expect((fitted.suggestedPercent ?? 100) < (before.suggestedPercent ?? 0))
    }

    @Test
    func `a manual cap remains independent of the automatic comfort limit`() {
        var state = self.state(at: self.weekday, reset: self.weekday.addingTimeInterval(3600))
        state.setPersonalCap(
            50,
            providerID: "codex",
            on: self.weekday,
            calendar: self.calendar)
        let status = state.status(
            providerID: "codex",
            on: self.weekday,
            calendar: self.calendar)
        #expect(status.suggestedPercent == 28.75)
        #expect(status.manualCapPercent == 50)
        #expect(status.effectiveCapPercent == 50)
        #expect(status.remainingSuggestedPercent == 50)
    }

    @Test
    func `another provider cannot borrow the public Codex reset probability`() {
        let status = self.state(at: self.weekday, provider: "claude").status(
            providerID: "claude",
            on: self.weekday,
            calendar: self.calendar,
            resetRisk: CockpitResetRisk(probability: 1, source: .announced))
        #expect(status.comfortAdvice?.risk == CockpitResetRisk.none)
        #expect(status.comfortAdvice?.riskBonusPercent == 0)
        #expect(status.suggestedPercent == 15)
    }
}
