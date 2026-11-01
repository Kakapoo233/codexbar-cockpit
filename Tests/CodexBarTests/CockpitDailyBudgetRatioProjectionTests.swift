import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CockpitDailyBudgetRatioProjectionTests {
    @Test
    func `daily ratio and weekly equivalent use distinct denominators`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let status = Self.status(suggestion: 20, used: 5)
            #expect(CockpitDailyAdviceProjection.remainingDailyText(status) == "75.0%")
            #expect(CockpitDailyAdviceProjection.remainingWeeklyText(status) == "15.0%")
            #expect(CockpitDailyAdviceProjection.remainingWeeklyEquivalentText(status) == "Weekly quota: 15.0%")
        }
    }

    @Test
    func `manual allocation supplies the daily denominator and balance constrains both values`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let manual = Self.status(suggestion: 10, manual: 20, used: 5)
            #expect(CockpitDailyAdviceProjection.remainingDailyText(manual) == "75.0%")
            #expect(CockpitDailyAdviceProjection.remainingWeeklyText(manual) == "15.0%")
            let constrained = Self.status(suggestion: 10, manual: 20, used: 5, balance: 6)
            #expect(CockpitDailyAdviceProjection.remainingDailyText(constrained) == "30.0%")
            #expect(CockpitDailyAdviceProjection.remainingWeeklyText(constrained) == "6.0%")
        }
    }

    @Test
    func `partial daily use makes both displayed remaining values upper bounds`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let partial = Self.status(suggestion: 20, used: 5, coverage: .partial)
            #expect(CockpitDailyAdviceProjection.remainingDailyText(partial) == "≤ 75.0%")
            #expect(CockpitDailyAdviceProjection.remainingWeeklyEquivalentText(partial) == "Weekly quota: ≤ 15.0%")
        }
    }

    @Test
    func `unknown use keeps both values missing while a known zero cap displays zero`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let unknown = Self.status(suggestion: 20, used: nil, coverage: .unavailable)
            #expect(CockpitDailyAdviceProjection.remainingDailyText(unknown) == "—")
            #expect(CockpitDailyAdviceProjection.remainingWeeklyText(unknown) == "—")
            #expect(CockpitDailyAdviceProjection.remainingWeeklyEquivalentText(unknown) == "Weekly quota: —")
            let zero = Self.status(suggestion: 20, manual: 0, used: 0)
            #expect(CockpitDailyAdviceProjection.remainingDailyText(zero) == "0.0%")
            #expect(CockpitDailyAdviceProjection.remainingWeeklyText(zero) == "0.0%")
        }
    }

    @Test
    func `Chinese weekly equivalent preserves its weekly quota label`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let status = Self.status(suggestion: 20, used: 5)
            #expect(CockpitDailyAdviceProjection.remainingWeeklyEquivalentText(status) == "相当于周额度 15.0%")
        }
    }

    private static func status(
        suggestion: Double?,
        manual: Double? = nil,
        used: Double?,
        balance: Double? = 50,
        coverage: CockpitCoverage = .complete) -> CockpitDayStatus
    {
        CockpitDayStatus(
            localDateKey: "2026-10-31",
            suggestedPercent: suggestion,
            manualCapPercent: manual,
            usedPercent: used,
            coverage: coverage,
            remainingPercent: balance,
            resetsAt: nil,
            feeling: nil,
            isStale: false)
    }
}
