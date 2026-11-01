import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct CockpitComfortAdviceProjectionTests {
    @Test
    func `comfort caption displays the adjusted ceiling rather than the fitted knee`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let baseline = Self.advice(softCap: 40, base: 50)
            let text = CockpitDailyAdviceProjection.comfortCeilingText(baseline)
            #expect(text == "Comfort ceiling: 40.0% · default curve")
            let fitted = Self.advice(softCap: 30, base: 50, curve: .fitted)
            #expect(CockpitDailyAdviceProjection.comfortCeilingText(fitted)
                == "Comfort ceiling: 30.0% · personal fit")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let fitted = Self.advice(softCap: 30, base: 50, curve: .fitted)
            #expect(CockpitDailyAdviceProjection.comfortCeilingText(fitted).contains("个人拟合"))
        }
    }

    @Test
    func `binding ceiling is disclosed without claiming it constrains a manual cap`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let limited = Self.advice(softCap: 20, base: 50)
            #expect(CockpitDailyAdviceProjection.comfortLimitText(limited, manualCap: nil)
                == "The comfort ceiling reduced the automatic target.")
            #expect(CockpitDailyAdviceProjection.comfortLimitText(limited, manualCap: 60)
                == "The curve limits the automatic target; your manual cap still takes priority.")
        }
    }

    @Test
    func `nonbinding ceiling has no reduction claim and a zero manual cap still takes priority`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let unbounded = Self.advice(softCap: 60, base: 20)
            #expect(CockpitDailyAdviceProjection.comfortLimitText(unbounded, manualCap: nil) == nil)
            #expect(CockpitDailyAdviceProjection.comfortLimitText(unbounded, manualCap: 0)
                == "Your manual cap takes priority over the automatic target.")
        }
    }

    @Test
    func `reset captions distinguish assumptions estimates and a pending announcement`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(CockpitDailyAdviceProjection.resetRiskText(
                CockpitResetRisk(probability: 0.1, source: .assumed))
                == "Reset chance: 10.0% · model default")
            #expect(CockpitDailyAdviceProjection.resetRiskText(
                CockpitResetRisk(probability: 1, source: .estimated))
                == "Reset chance: 100.0% · community estimate")
            #expect(CockpitDailyAdviceProjection.resetRiskText(
                CockpitResetRisk(probability: 1, source: .announced))
                == "Reset announced within 24 hours; this account still needs confirmation.")
        }
    }

    private static func advice(
        softCap: Double,
        base: Double,
        curve: CockpitQuotaComfortModel.Status = .baseline) -> CockpitComfortAdvice
    {
        CockpitComfortAdvice(
            kneePercent: 25,
            curveStatus: curve,
            sampleCount: curve == .fitted ? 12 : 0,
            softCapPercent: softCap,
            baseDailyPercent: base,
            riskBonusPercent: 0,
            risk: CockpitResetRisk(probability: 0.1, source: .assumed),
            isWeekend: false)
    }
}
