import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct UsagePaceHeadroomDurationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `card duration extends the uncapped rate beyond reset without changing exhaustion metrics`() throws {
        let reset = self.now.addingTimeInterval(3 * 86400)
        let window = RateWindow(usedPercent: 20, windowMinutes: 10080, resetsAt: reset, resetDescription: nil)
        let pace = try #require(UsagePace.weekly(window: window, now: self.now))
        #expect(pace.willLastToReset)
        #expect(pace.etaSeconds == nil)
        for language in ["en", "zh-Hans"] {
            CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                let original = UsagePaceText.weeklyDetail(provider: .codex, pace: pace, now: self.now)
                let card = UsagePaceText.weeklyDetail(
                    provider: .codex, pace: pace, now: self.now, headroomResetsAt: reset)
                let duration = UsageFormatter.resetCountdownDuration(
                    from: self.now.addingTimeInterval(16 * 86400), now: self.now)
                #expect(card.rightLabel == L(
                    "%@ · %@",
                    original.rightLabel!,
                    L("cockpit_pace_headroom_duration", duration)))
                #expect(card.leftLabel == original.leftLabel)
                #expect(UsagePaceText.weeklyDetail(
                    provider: .claude, pace: pace, now: self.now, headroomResetsAt: reset).rightLabel ==
                    L("Lasts until reset"))
            }
        }
    }

    @Test
    func `session card opts into the same headroom duration while summary stays unchanged`() throws {
        let window = RateWindow(
            usedPercent: 20, windowMinutes: 300, resetsAt: self.now.addingTimeInterval(3600), resetDescription: nil)
        let original = try #require(UsagePaceText.sessionDetail(provider: .codex, window: window, now: self.now))
        let card = try #require(UsageMenuCardView.Model.sessionPaceDetail(
            provider: .codex, window: window, now: self.now, showUsed: false))
        #expect(card.rightLabel == original.rightLabel! + " · At this average pace: 16h left (ignoring reset)")
        #expect(card.leftLabel == original.leftLabel)
    }

    @Test
    func `workday headroom explicitly extrapolates the projected wall-clock average`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))
        let reset = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14)))
        let pace = try #require(UsagePace.weekly(
            window: RateWindow(usedPercent: 25, windowMinutes: 10080, resetsAt: reset, resetDescription: nil),
            now: now,
            workDays: 5,
            calendar: calendar))
        // 25 points / 72 elapsed work hours projects 16.667 points across the remaining 72 wall hours.
        // Extending that window-average rate uses 75 / (16.667 / 72) = 324 wall hours.
        // This intentionally does not promise a future workday-by-workday calendar schedule.
        #expect(pace.speedMultiplierToReset == 4.5)
        #expect(UsagePaceText.weeklyDetail(
            provider: .codex, pace: pace, now: now, headroomResetsAt: reset).rightLabel ==
            "Lasts until reset · 1.5× headroom · At this average pace: 13d 12h left (ignoring reset)")
        #expect(pace.etaSeconds == nil)
    }

    @Test
    func `historical headroom uses its own projected average rather than linear expected use`() {
        let pace = UsagePace.historical(
            expectedUsedPercent: 45,
            actualUsedPercent: 20,
            etaSeconds: nil,
            willLastToReset: true,
            runOutProbability: 0.02,
            projectedRemainingUsage: 20)
        let detail = UsagePaceText.weeklyDetail(
            provider: .codex, pace: pace, now: self.now, headroomResetsAt: self.now.addingTimeInterval(2 * 86400))
        #expect(detail.rightLabel ==
            "Lasts until reset · 1.5× headroom · At this average pace: 8d left (ignoring reset) (0% risk)")
    }

    @Test
    func `unavailable zero or invalid rates do not invent a remaining duration`() {
        for multiplier in [Double?.none, 0, -1, .infinity, .nan, Double.greatestFiniteMagnitude] {
            let pace = UsagePace(
                stage: .farBehind,
                deltaPercent: -40,
                expectedUsedPercent: 60,
                actualUsedPercent: 20,
                etaSeconds: nil,
                willLastToReset: true,
                speedMultiplierToReset: multiplier)
            let detail = UsagePaceText.weeklyDetail(
                provider: .codex, pace: pace, now: self.now, headroomResetsAt: self.now.addingTimeInterval(86400))
            #expect(detail.rightLabel?.contains("At this average pace") == false)
        }
        let zero = UsagePace.weekly(window: RateWindow(
            usedPercent: 0,
            windowMinutes: 10080,
            resetsAt: self.now.addingTimeInterval(86400),
            resetDescription: nil), now: self.now)
        #expect(zero?.speedMultiplierToReset == nil)
    }

    @Test
    func `missing expired and invalid reset dates hide only the added duration`() throws {
        let pace = try #require(UsagePace.weekly(window: RateWindow(
            usedPercent: 20,
            windowMinutes: 10080,
            resetsAt: self.now.addingTimeInterval(3 * 86400),
            resetDescription: nil), now: self.now))
        for reset in [Date?.none, self.now, self.now.addingTimeInterval(-60), Date(timeIntervalSince1970: .nan)] {
            #expect(UsagePaceText.weeklyDetail(
                provider: .codex, pace: pace, now: self.now, headroomResetsAt: reset).rightLabel ==
                "Lasts until reset · 1.5× headroom")
        }
    }

    @Test
    func `ordinary pre-reset exhaustion retains its existing countdown`() throws {
        let reset = self.now.addingTimeInterval(4 * 86400)
        let pace = try #require(UsagePace.weekly(window: RateWindow(
            usedPercent: 50, windowMinutes: 10080, resetsAt: reset, resetDescription: nil), now: self.now))
        #expect(UsagePaceText.weeklyDetail(
            provider: .codex, pace: pace, now: self.now, headroomResetsAt: reset).rightLabel == "Runs out in 3d")
    }
}
