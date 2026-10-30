import Foundation
import Testing
@testable import CodexBarCore

struct CockpitComfortCoreTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        Date(timeIntervalSince1970: 1_783_512_000)
    }

    private func record(
        day: String,
        tokens: Int?,
        coverage: CockpitCoverage = .complete,
        provider: String = "codex",
        account: String = "default",
        feeling: CockpitFeeling = .comfortable) -> CockpitComfortRecord
    {
        CockpitComfortRecord(
            providerID: provider,
            accountID: account,
            localDateKey: day,
            timeZoneIdentifier: self.calendar.timeZone.identifier,
            recordedAt: self.now,
            feeling: feeling,
            totalTokens: tokens,
            coverage: coverage)
    }

    @Test
    func `partial experiences are shown as observations without inventing a fitted curve`() {
        let records = (1...8).map { self.record(day: "2026-07-0\($0)", tokens: $0 * 100_000, coverage: .partial) }
        let model = CockpitComfortModel.build(
            records: records,
            providerID: "codex",
            now: self.now,
            calendar: self.calendar)
        #expect(model.status == .insufficientData)
        #expect(model.points.isEmpty)
        #expect(model.completeSampleCount == 0)
        #expect(model.observations.count == 8)
    }

    @Test
    func `seven varied complete days permit descriptive binned experience means`() {
        let records = (1...7).map {
            self.record(day: "2026-07-0\($0)", tokens: $0 * 100_000, feeling: $0 < 4 ? .light : .overloaded)
        }
        let model = CockpitComfortModel.build(
            records: records,
            providerID: "codex",
            now: self.now,
            calendar: self.calendar)
        #expect(model.status == .ready)
        #expect(model.completeSampleCount == 7)
        #expect(model.points.count == 3)
        #expect(model.points.reduce(0) { $0 + $1.sampleCount } == 7)
        #expect(model.points.allSatisfy { (0.25...1).contains($0.score) })
        #expect(model.points.map(\.totalTokens) == model.points.map(\.totalTokens).sorted())
    }

    @Test
    func `unknown tokens future dates and another identity cannot train this experience chart`() {
        let records = [
            self.record(day: "2026-07-01", tokens: nil),
            self.record(day: "2026-07-02", tokens: 100, coverage: .unavailable),
            self.record(day: "2026-07-03", tokens: 200, provider: "claude"),
            self.record(day: "2026-07-04", tokens: 300, account: "other"),
            self.record(day: "2026-02-30", tokens: 400),
            self.record(day: "2027-07-01", tokens: 500),
        ]
        let model = CockpitComfortModel.build(
            records: records,
            providerID: "codex",
            now: self.now,
            calendar: self.calendar)
        #expect(model.observations.isEmpty)
        #expect(model.points.isEmpty)
    }

    @Test
    func `revising a daily feeling replaces that day while preserving the quota plan`() {
        var state = CockpitPlanState()
        state.recordComfort(.light, providerID: "codex", on: self.now, totalTokens: 20, calendar: self.calendar)
        state.recordComfort(.overloaded, providerID: "codex", on: self.now, totalTokens: 50, calendar: self.calendar)
        #expect(state.comfortRecords.count == 1)
        #expect(state.comfortRecords.first?.feeling == .overloaded)
        #expect(state.comfortRecords.first?.totalTokens == 50)
        #expect(state.plans.isEmpty)
        #expect(state.snapshots.isEmpty)
    }
}
