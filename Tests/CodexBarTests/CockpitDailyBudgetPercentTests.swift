import Foundation
import Testing
@testable import CodexBarCore

struct CockpitDailyBudgetPercentTests {
    @Test
    func `remaining daily percentage uses the daily allocation as its denominator`() {
        let status = self.status()
        #expect(status.remainingSuggestedPercent == 15)
        #expect(status.remainingDailyBudgetPercent == 75)
    }

    @Test
    func `a manual cap replaces the automatic allocation for the daily percentage`() {
        let status = self.status(manual: 30)
        #expect(status.effectiveCapPercent == 30)
        #expect(status.remainingSuggestedPercent == 25)
        #expect(status.remainingDailyBudgetPercent == 83.33)
        #expect(self.status(suggested: nil, manual: 30).remainingDailyBudgetPercent == 83.33)
    }

    @Test
    func `the real quota balance bounds the remaining daily percentage`() {
        let status = self.status(remaining: 4)
        #expect(status.remainingSuggestedPercent == 4)
        #expect(status.remainingDailyBudgetPercent == 20)
        #expect(self.status(used: 0, remaining: 100).remainingDailyBudgetPercent == 100)
    }

    @Test(arguments: [0.0, 5, 25])
    func `a known zero allocation and overspending both have zero remaining share`(used: Double) {
        #expect(self.status(suggested: 0, used: used).remainingDailyBudgetPercent == 0)
        #expect(self.status(used: 25).remainingDailyBudgetPercent == 0)
    }

    @Test
    func `missing inputs remain unknown including a zero allocation with unknown use`() {
        #expect(self.status(suggested: nil).remainingDailyBudgetPercent == nil)
        #expect(self.status(used: nil).remainingDailyBudgetPercent == nil)
        #expect(self.status(remaining: nil).remainingDailyBudgetPercent == nil)
        #expect(self.status(suggested: 0, used: nil).remainingDailyBudgetPercent == nil)
        #expect(self.status(suggested: 0, remaining: nil).remainingDailyBudgetPercent == nil)
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity, -1])
    func `invalid inputs never produce a nonfinite daily percentage`(value: Double) {
        #expect(self.status(suggested: value).remainingDailyBudgetPercent == nil)
        #expect(self.status(manual: value).remainingDailyBudgetPercent == nil)
        #expect(self.status(used: value).remainingDailyBudgetPercent == nil)
        #expect(self.status(remaining: value).remainingDailyBudgetPercent == nil)
    }

    @Test
    func `partial coverage keeps its computed share and its separate uncertainty marker`() {
        let status = self.status(coverage: .partial)
        #expect(status.remainingDailyBudgetPercent == 75)
        #expect(status.coverage == .partial)
    }

    private func status(
        suggested: Double? = 20,
        manual: Double? = nil,
        used: Double? = 5,
        remaining: Double? = 95,
        coverage: CockpitCoverage = .complete) -> CockpitDayStatus
    {
        CockpitDayStatus(
            localDateKey: "2026-11-01",
            suggestedPercent: suggested,
            manualCapPercent: manual,
            usedPercent: used,
            coverage: coverage,
            remainingPercent: remaining,
            resetsAt: nil,
            feeling: nil,
            isStale: false)
    }
}
