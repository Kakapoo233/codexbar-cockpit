import Foundation
import Testing
@testable import CodexBarCore

struct CockpitPlanCoreTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func snapshot(
        _ timestamp: String,
        remaining: Double,
        reset: String = "2026-07-13T04:00:00Z",
        provider: String = "codex",
        account: String = "default") -> CockpitQuotaSnapshot
    {
        CockpitQuotaSnapshot(
            providerID: provider, accountID: account, capturedAt: self.date(timestamp),
            remainingPercent: remaining, resetsAt: self.date(reset))
    }

    @Test
    func `daily suggestion is frozen while a manual cap can be restored`() {
        var state = CockpitPlanState()
        state.record(self.snapshot("2026-07-06T04:00:00Z", remaining: 70), calendar: self.calendar)
        let noon = self.date("2026-07-06T16:00:00Z")
        state.record(self.snapshot("2026-07-06T16:00:00Z", remaining: 50), calendar: self.calendar)
        var status = state.status(providerID: "codex", on: noon, calendar: self.calendar)
        #expect(status.suggestedPercent == 10)
        #expect(status.usedPercent == 20)
        #expect(status.remainingSuggestedPercent == 0)
        state.setPersonalCap(30, providerID: "codex", on: noon, calendar: self.calendar)
        status = state.status(providerID: "codex", on: noon, calendar: self.calendar)
        #expect(status.manualCapPercent == 30)
        #expect(status.effectiveCapPercent == 30)
        #expect(status.suggestedPercent == 10)
        #expect(status.remainingSuggestedPercent == 10)
        state.setPersonalCap(nil, providerID: "codex", on: noon, calendar: self.calendar)
        #expect(state.status(providerID: "codex", on: noon, calendar: self.calendar).effectiveCapPercent == 10)
    }

    @Test
    func `a single daytime snapshot cannot establish actual daily use`() {
        var state = CockpitPlanState()
        let noon = self.date("2026-07-06T16:00:00Z")
        state.record(self.snapshot(
            "2026-07-06T16:00:00Z", remaining: 70, reset: "2026-07-12T04:00:00Z"), calendar: self.calendar)
        let status = state.status(providerID: "codex", on: noon, calendar: self.calendar)
        #expect(status.usedPercent == nil)
        #expect(status.coverage == .partial)
        #expect(status.remainingSuggestedPercent == nil)
        #expect(status.suggestedPercent != nil)
    }

    @Test
    func `same day reset consumption accumulates beyond one hundred without changing the plan`() {
        var state = CockpitPlanState()
        state.record(self.snapshot(
            "2026-07-06T04:00:00Z", remaining: 100, reset: "2026-07-06T16:00:00Z"), calendar: self.calendar)
        let original = state.plans.first?.suggestedPercent
        state.record(self.snapshot(
            "2026-07-06T15:50:00Z", remaining: 5, reset: "2026-07-06T16:00:00Z"), calendar: self.calendar)
        state.record(self.snapshot(
            "2026-07-06T16:10:00Z", remaining: 40, reset: "2026-07-13T16:00:00Z"), calendar: self.calendar)
        let status = state.status(
            providerID: "codex", on: self.date("2026-07-06T16:10:00Z"), calendar: self.calendar)
        #expect(status.usedPercent == 155)
        #expect(status.suggestedPercent == original)
        #expect(status.coverage == .partial)
    }

    @Test
    func `balance rebounds and replayed observations do not double count consumption`() {
        var state = CockpitPlanState()
        let initial = self.snapshot("2026-07-06T04:00:00Z", remaining: 70)
        let inserted = state.record(initial, calendar: self.calendar)
        let replayed = state.record(initial, calendar: self.calendar)
        #expect(inserted)
        #expect(!replayed)
        state.record(self.snapshot("2026-07-06T04:10:00Z", remaining: 50), calendar: self.calendar)
        state.record(self.snapshot("2026-07-06T04:20:00Z", remaining: 60), calendar: self.calendar)
        state.record(self.snapshot("2026-07-06T04:30:00Z", remaining: 45), calendar: self.calendar)
        let usage = state.dailyUsage(
            providerID: "codex", on: self.date("2026-07-06T04:30:00Z"), calendar: self.calendar)
        #expect(usage.usedPercent == 25)
        #expect(usage.coverage == .complete)
        #expect(usage.sampleCount == 4)
    }

    @Test
    func `alternating reset timestamp precision cannot create duplicate quota cycles`() {
        var state = CockpitPlanState()
        let observations = [
            ("2026-07-06T04:00:00Z", 90.0, "2026-07-12T16:00:45Z"),
            ("2026-07-06T04:10:00Z", 80.0, "2026-07-12T16:00:00Z"),
            ("2026-07-06T04:20:00Z", 70.0, "2026-07-12T16:00:45Z"),
            ("2026-07-06T04:30:00Z", 60.0, "2026-07-12T16:00:00Z"),
        ]
        for observation in observations {
            state.record(self.snapshot(
                observation.0, remaining: observation.1, reset: observation.2), calendar: self.calendar)
        }
        let usage = state.dailyUsage(
            providerID: "codex", on: self.date("2026-07-06T04:30:00Z"), calendar: self.calendar)
        #expect(usage.usedPercent == 30)
        #expect(usage.coverage == .partial)
        #expect(usage.sampleCount == 4)
    }

    @Test
    func `an observed new cycle start confirms an early reset before the previous deadline`() {
        var state = CockpitPlanState()
        state.record(self.snapshot(
            "2026-07-06T04:00:00Z", remaining: 100, reset: "2026-07-07T16:00:00Z"), calendar: self.calendar)
        state.record(self.snapshot(
            "2026-07-06T15:50:00Z", remaining: 5, reset: "2026-07-07T16:00:00Z"), calendar: self.calendar)
        state.record(self.snapshot(
            "2026-07-06T16:10:00Z", remaining: 40, reset: "2026-07-13T16:00:00Z"), calendar: self.calendar)
        let usage = state.dailyUsage(
            providerID: "codex", on: self.date("2026-07-06T16:10:00Z"), calendar: self.calendar)
        #expect(usage.usedPercent == 155)
        #expect(usage.coverage == .partial)
    }

    @Test
    func `an unconfirmed future reset reschedule stays in the current observed cycle`() {
        var state = CockpitPlanState()
        state.record(self.snapshot(
            "2026-07-06T04:00:00Z", remaining: 90, reset: "2026-07-12T16:00:00Z"), calendar: self.calendar)
        state.record(self.snapshot(
            "2026-07-06T04:10:00Z", remaining: 80, reset: "2026-07-12T18:00:00Z"), calendar: self.calendar)
        state.record(self.snapshot(
            "2026-07-06T04:20:00Z", remaining: 70, reset: "2026-07-12T16:00:00Z"), calendar: self.calendar)
        let usage = state.dailyUsage(
            providerID: "codex", on: self.date("2026-07-06T04:20:00Z"), calendar: self.calendar)
        #expect(usage.usedPercent == 20)
        #expect(usage.coverage == .partial)
    }

    @Test
    func `night gaps do not assign unknown consumption to the following day`() {
        var state = CockpitPlanState()
        state.record(self.snapshot("2026-07-06T23:00:00Z", remaining: 90), calendar: self.calendar)
        state.record(self.snapshot("2026-07-07T14:00:00Z", remaining: 50), calendar: self.calendar)
        #expect(state.dailyUsage(
            providerID: "codex", on: self.date("2026-07-07T14:00:00Z"),
            calendar: self.calendar).usedPercent == nil)
        state.record(self.snapshot("2026-07-07T14:20:00Z", remaining: 45), calendar: self.calendar)
        let usage = state.dailyUsage(
            providerID: "codex", on: self.date("2026-07-07T14:20:00Z"), calendar: self.calendar)
        #expect(usage.usedPercent == 5)
        #expect(usage.coverage == .partial)
    }

    @Test
    func `accounts and providers cannot borrow quota caps or feelings`() {
        var state = CockpitPlanState()
        let time = self.date("2026-07-06T16:00:00Z")
        state.record(self.snapshot("2026-07-06T16:00:00Z", remaining: 70), calendar: self.calendar)
        state.setPersonalCap(12, providerID: "codex", on: time, calendar: self.calendar)
        state.recordComfort(.light, providerID: "codex", on: time, calendar: self.calendar)
        for (provider, account) in [("claude", "default"), ("codex", "other")] {
            let status = state.status(providerID: provider, accountID: account, on: time, calendar: self.calendar)
            #expect(status.suggestedPercent == nil)
            #expect(status.manualCapPercent == nil)
            #expect(status.remainingPercent == nil)
            #expect(status.usedPercent == nil)
            #expect(status.feeling == nil)
            #expect(status.coverage == .unavailable)
        }
    }

    @Test
    func `expiry never invents a renewed official balance`() {
        var state = CockpitPlanState()
        state.record(self.snapshot(
            "2026-07-06T04:00:00Z", remaining: 70, reset: "2026-07-06T05:00:00Z"), calendar: self.calendar)
        let status = state.status(
            providerID: "codex", on: self.date("2026-07-06T06:00:00Z"), calendar: self.calendar)
        #expect(status.remainingPercent == nil)
        #expect(status.resetsAt == nil)
        #expect(status.isStale)
        #expect(status.suggestedPercent == 70)
    }

    @Test
    func `invalid percentages reset metadata and caps are rejected`() {
        var state = CockpitPlanState()
        for remaining in [Double.nan, .infinity, -1, 101] {
            let accepted = state.record(self.snapshot("2026-07-06T04:00:00Z", remaining: remaining))
            #expect(!accepted)
            state.setPersonalCap(remaining, providerID: "codex")
        }
        let acceptedExpired = state.record(self.snapshot(
            "2026-07-06T04:00:00Z", remaining: 60, reset: "2026-07-06T03:00:00Z"))
        #expect(!acceptedExpired)
        #expect(state.snapshots.isEmpty)
        #expect(state.plans.isEmpty)
        #expect(state.personalCaps.isEmpty)
    }

    @Test(arguments: [
        ("2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z", 23.0),
        ("2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z", 25.0),
    ])
    func `daily allocation follows the actual local day through DST`(example: (String, String, Double)) {
        let start = self.date(example.0)
        let end = self.date(example.1)
        var state = CockpitPlanState()
        state.record(CockpitQuotaSnapshot(
            providerID: "codex", capturedAt: start, remainingPercent: 70,
            resetsAt: start.addingTimeInterval(7 * 86400)), calendar: self.calendar)
        #expect(self.calendar.dateInterval(of: .day, for: start)?.end == end)
        let expected = (70 * example.2 / (7 * 24) * 100).rounded() / 100
        #expect(state.plans.first?.suggestedPercent == expected)
    }

    @Test
    func `state survives JSON round trip with personal settings and original feelings`() throws {
        var state = CockpitPlanState()
        let time = self.date("2026-07-06T16:00:00Z")
        state.record(self.snapshot("2026-07-06T16:00:00Z", remaining: 70), calendar: self.calendar)
        state.setPersonalCap(15, providerID: "codex", on: time, calendar: self.calendar)
        state.recordComfort(
            .comfortable, providerID: "codex", on: time, totalTokens: 1234,
            coverage: .complete, calendar: self.calendar)
        let decoded = try JSONDecoder().decode(CockpitPlanState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
        #expect(decoded.status(providerID: "codex", on: time, calendar: self.calendar).feeling == .comfortable)
    }
}
