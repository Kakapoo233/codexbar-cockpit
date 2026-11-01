import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct CockpitRecommendationPaceTextTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let now = Date(timeIntervalSince1970: 1_800_014_400) // UTC noon

    @Test
    func `menu sign follows preference and partial bounds round outward`() throws {
        let ahead = try #require(Self.pace(used: 15.6))
        #expect(CockpitRecommendationPaceText.menuBarText(pace: ahead) == "+6%")
        #expect(CockpitRecommendationPaceText.menuBarText(pace: ahead, reservePositive: true) == "-6%")
        let partialAhead = try #require(Self.pace(used: 15.6, coverage: .partial))
        #expect(CockpitRecommendationPaceText.menuBarText(pace: partialAhead) == "≥+5%")
        #expect(CockpitRecommendationPaceText.menuBarText(pace: partialAhead, reservePositive: true) == "≤-5%")
        let partialBehind = try #require(Self.pace(used: 4.4, coverage: .partial))
        #expect(CockpitRecommendationPaceText.menuBarText(pace: partialBehind) == "≥-6%")
        #expect(CockpitRecommendationPaceText.menuBarText(pace: partialBehind, reservePositive: true) == "≤+6%")
        #expect(CockpitRecommendationPaceText.menuBarText(pace: nil) == nil)
    }

    @Test
    func `recommendation detail distinguishes exact reserve from incomplete observations`() throws {
        let behind = try #require(Self.pace(used: 5))
        let partial = try #require(Self.pace(used: 5, coverage: .partial))
        let partialAhead = try #require(Self.pace(used: 15, coverage: .partial))
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(CockpitRecommendationPaceText.detailLabel(behind) == "Today: 5 pp behind recommendation")
            #expect(CockpitRecommendationPaceText.detailLabel(partial) == "Today's pace needs complete usage data")
            #expect(CockpitRecommendationPaceText.detailLabel(partialAhead) ==
                "Today: at least 5 pp ahead · incomplete data")
            #expect(CockpitRecommendationPaceText.detailLabel(Self.pace(used: 10)) == "Today: on recommendation pace")
        }
    }

    @Test
    func `daily comparison never supplies a cumulative weekly stripe or a quota forecast`() throws {
        let pace = try #require(Self.pace(used: 15))
        let official = UsagePace(
            stage: .behind,
            deltaPercent: -20,
            expectedUsedPercent: 60,
            actualUsedPercent: 40,
            etaSeconds: nil,
            willLastToReset: true)
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let detail = CockpitRecommendationPaceText.weeklyDetail(pace: pace, officialPace: official, now: Self.now)
            #expect(detail.leftLabel == "Today: 5 pp ahead of recommendation")
            #expect(detail.rightLabel?.hasPrefix("Quota forecast: Lasts until reset") == true)
            #expect(detail.pacePercent == nil)
            #expect(detail.isPaceDerived)
            let missing = CockpitRecommendationPaceText.weeklyDetail(pace: nil, officialPace: nil, now: Self.now)
            #expect(missing.leftLabel == "Today's recommendation pace is unavailable")
            #expect(missing.rightLabel == nil)
            #expect(missing.pacePercent == nil)
        }
    }

    @Test
    func `live Codex weekly card uses recommendation while session retains its own pace`() throws {
        let pace = try #require(Self.pace(used: 15))
        let linked = try Self.card(pace: pace, linked: true)
        let unavailable = try Self.card(pace: nil, linked: true)
        let original = try Self.card(pace: nil, linked: false)
        let weekly = try #require(linked.metrics.first { $0.id == "secondary" })
        let missingWeekly = try #require(unavailable.metrics.first { $0.id == "secondary" })
        let originalWeekly = try #require(original.metrics.first { $0.id == "secondary" })
        #expect(weekly.detailLeftText == CockpitRecommendationPaceText.detailLabel(pace))
        #expect(weekly.pacePercent == nil)
        #expect(missingWeekly.detailLeftText == CockpitRecommendationPaceText.detailLabel(nil))
        #expect(missingWeekly.detailLeftText != originalWeekly.detailLeftText)
        #expect(missingWeekly.pacePercent == nil)
        #expect(linked.metrics.first { $0.id == "primary" }?.detailLeftText ==
            original.metrics.first { $0.id == "primary" }?.detailLeftText)
    }

    private static func pace(used: Double, coverage: CockpitCoverage = .complete) -> CockpitRecommendationPace? {
        CockpitRecommendationPace(
            status: CockpitDayStatus(
                localDateKey: CockpitCalendar.dateKey(for: self.now, calendar: self.calendar),
                suggestedPercent: 20,
                manualCapPercent: nil,
                usedPercent: used,
                coverage: coverage,
                remainingPercent: 50,
                resetsAt: self.now.addingTimeInterval(86400),
                feeling: nil,
                isStale: false),
            on: self.now,
            calendar: self.calendar)
    }

    private static func card(pace: CockpitRecommendationPace?, linked: Bool) throws -> UsageMenuCardView.Model {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 20,
                windowMinutes: 300,
                resetsAt: self.now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 40,
                windowMinutes: 10080,
                resetsAt: self.now.addingTimeInterval(3 * 86400),
                resetDescription: nil),
            updatedAt: self.now)
        let projection = CodexConsumerProjection.make(
            surface: .liveCard,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: nil,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: self.now))
        return try UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            snapshot: snapshot,
            codexProjection: projection,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            cockpitRecommendationPace: pace,
            usesCockpitRecommendationPace: linked,
            now: self.now))
    }
}
