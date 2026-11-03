import AppKit
import Foundation
import SwiftUI
import Testing
import XCTest
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
    func `menu sign follows preference and preserves partial rounding without comparison prefixes`() throws {
        let ahead = try #require(Self.pace(used: 15.6))
        #expect(CockpitRecommendationPaceText.menuBarText(pace: ahead) == "+6%")
        #expect(CockpitRecommendationPaceText.menuBarText(pace: ahead, reservePositive: true) == "-6%")
        let partialAhead = try #require(Self.pace(used: 15.6, coverage: .partial))
        #expect(CockpitRecommendationPaceText.menuBarText(pace: partialAhead) == "+5%")
        #expect(CockpitRecommendationPaceText.menuBarText(pace: partialAhead, reservePositive: true) == "-5%")
        let partialBehind = try #require(Self.pace(used: 4.4, coverage: .partial))
        #expect(CockpitRecommendationPaceText.menuBarText(pace: partialBehind) == "-6%")
        #expect(CockpitRecommendationPaceText.menuBarText(pace: partialBehind, reservePositive: true) == "+6%")
        #expect(CockpitRecommendationPaceText.menuBarText(pace: nil) == nil)
    }

    @Test
    func `recommendation detail restores original localized labels and neutral band`() throws {
        let cases: [(used: Double, english: String, chinese: String)] = [
            (5, "5% in reserve", "余量 5%"),
            (7.49, "3% in reserve", "余量 3%"),
            (7.5, "3% in reserve", "余量 3%"),
            (7.99, "2% in reserve", "余量 2%"),
            (8, "On pace", "节奏正常"),
            (10, "On pace", "节奏正常"),
            (12, "On pace", "节奏正常"),
            (12.01, "2% in deficit", "超额 2%"),
            (12.5, "3% in deficit", "超额 3%"),
            (12.51, "3% in deficit", "超额 3%"),
            (15, "5% in deficit", "超额 5%"),
        ]
        for testCase in cases {
            let pace = try #require(Self.pace(used: testCase.used))
            CodexBarLocalizationOverride.$appLanguage.withValue("en") {
                #expect(CockpitRecommendationPaceText.detailLabel(pace) == testCase.english)
            }
            CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
                #expect(CockpitRecommendationPaceText.detailLabel(pace) == testCase.chinese)
            }
        }
    }

    @Test
    func `incomplete and missing observations never claim reserve or on pace`() throws {
        for language in ["en", "zh-Hans"] {
            CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                #expect(CockpitRecommendationPaceText.detailLabel(nil) == "—")
            }
            for used in [0.0, 5, 10] {
                let pace = try #require(Self.pace(used: used, coverage: .partial))
                CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                    #expect(CockpitRecommendationPaceText.detailLabel(pace) == "—")
                }
            }
            for used in [10.1, 15.6] {
                let pace = try #require(Self.pace(used: used, coverage: .partial))
                CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                    #expect(CockpitRecommendationPaceText.detailLabel(pace) ==
                        CockpitRecommendationPaceText.menuBarText(pace: pace))
                }
            }
        }
    }

    @Test
    func `complete menu bar text retains original signed rounded presentation`() throws {
        for used in [0.0, 5, 9.49, 9.5, 9.6, 10, 10.4, 10.5, 10.51, 15.6] {
            let daily = try #require(Self.pace(used: used))
            let original = UsagePace(
                stage: .onTrack,
                deltaPercent: daily.deltaPercent,
                expectedUsedPercent: daily.expectedUsedPercent,
                actualUsedPercent: daily.observedUsedPercent,
                etaSeconds: nil,
                willLastToReset: false)
            for reservePositive in [false, true] {
                #expect(CockpitRecommendationPaceText.menuBarText(pace: daily, reservePositive: reservePositive) ==
                    MenuBarDisplayText.paceText(pace: original, reservePositive: reservePositive))
            }
        }
    }

    @Test
    func `expanded explanation preserves daily source and incomplete observation wording`() throws {
        let behind = try #require(Self.pace(used: 5))
        let partial = try #require(Self.pace(used: 5, coverage: .partial))
        let partialAhead = try #require(Self.pace(used: 15, coverage: .partial))
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(CockpitRecommendationPaceText.explanationLabel(behind) == "Today: 5 pp behind recommendation")
            #expect(CockpitRecommendationPaceText.explanationLabel(partial) == "Today's pace needs complete usage data")
            #expect(CockpitRecommendationPaceText.explanationLabel(partialAhead) ==
                "Today: at least 5 pp ahead · incomplete data")
            #expect(CockpitRecommendationPaceText.explanationLabel(Self.pace(used: 10)) ==
                "Today: on recommendation pace")
            #expect(CockpitRecommendationPaceText.explanationLabel(nil) ==
                "Today's recommendation pace is unavailable")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            #expect(CockpitRecommendationPaceText.explanationLabel(behind) == "今日：比推荐节奏慢 5 个周额度百分点")
            #expect(CockpitRecommendationPaceText.explanationLabel(partial) == "今日节奏需要完整的用量数据")
            #expect(CockpitRecommendationPaceText.explanationLabel(partialAhead) ==
                "今日：至少快 5 个周额度百分点 · 数据不完整")
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
            #expect(detail.leftLabel == "5% in deficit")
            #expect(detail.rightLabel == UsagePaceText.weeklyDetail(
                provider: .codex, pace: official, now: Self.now).rightLabel)
            #expect(detail.rightLabel?.contains("Quota forecast") == false)
            let help = CockpitRecommendationPaceText.detailHelp(pace: pace, officialPace: official, now: Self.now)
            #expect(help.contains(L("menu_bar_help_pace")))
            #expect(help.contains("Today: 5 pp ahead of recommendation"))
            #expect(help.contains("Quota forecast: Lasts until reset"))
            #expect(detail.pacePercent == nil)
            #expect(detail.isPaceDerived)
            let missing = CockpitRecommendationPaceText.weeklyDetail(pace: nil, officialPace: nil, now: Self.now)
            #expect(missing.leftLabel == "—")
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
        #expect(weekly.detailRightText == originalWeekly.detailRightText)
        #expect(weekly.paceHelpText?.contains(L("menu_bar_help_pace")) == true)
        #expect(weekly.paceHelpText?.contains(CockpitRecommendationPaceText.explanationLabel(pace)) == true)
        #expect(missingWeekly.detailLeftText == CockpitRecommendationPaceText.detailLabel(nil))
        #expect(missingWeekly.detailLeftText != originalWeekly.detailLeftText)
        #expect(missingWeekly.pacePercent == nil)
        #expect(linked.metrics.first { $0.id == "primary" }?.detailLeftText ==
            original.metrics.first { $0.id == "primary" }?.detailLeftText)
        #expect(linked.metrics.first { $0.id == "primary" }?.detailRightText ==
            original.metrics.first { $0.id == "primary" }?.detailRightText)
        #expect(linked.metrics.first { $0.id == "primary" }?.pacePercent ==
            original.metrics.first { $0.id == "primary" }?.pacePercent)
        #expect(linked.metrics.first { $0.id == "primary" }?.paceHelpText ==
            original.metrics.first { $0.id == "primary" }?.paceHelpText)
    }

    fileprivate static func pace(used: Double, coverage: CockpitCoverage = .complete) -> CockpitRecommendationPace? {
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

    fileprivate static func card(pace: CockpitRecommendationPace?, linked: Bool) throws -> UsageMenuCardView.Model {
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
            weeklyPace: snapshot.secondary.flatMap { UsagePace.weekly(window: $0, now: self.now) },
            cockpitRecommendationPace: pace,
            usesCockpitRecommendationPace: linked,
            now: self.now))
    }
}

/// Opt-in visual proof using only fixed, synthetic observations and no account identity.
@MainActor
final class CockpitRecommendationPaceScreenshotRenderTests: XCTestCase {
    func test_renderNativePacePresentation() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_DAILY_PACE_PROOF_DIR"] else {
            throw XCTSkip("Set CODEXBAR_DAILY_PACE_PROOF_DIR to render synthetic daily pace proof")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in ["en", "zh-Hans"] {
            try CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                let complete = try XCTUnwrap(CockpitRecommendationPaceTextTests.pace(used: 15))
                let partial = try XCTUnwrap(CockpitRecommendationPaceTextTests.pace(used: 5, coverage: .partial))
                for (name, pace, linked) in [
                    ("original", Optional(complete), false),
                    ("daily", Optional(complete), true),
                    ("partial", Optional(partial), true),
                    ("missing", nil, true),
                ] {
                    let model = try CockpitRecommendationPaceTextTests.card(pace: pace, linked: linked)
                    for dark in [false, true] {
                        let view = AnyView(UsageMenuCardView(model: model, width: 320)
                            .environment(\.locale, Locale(identifier: language))
                            .environment(\.colorScheme, dark ? .dark : .light)
                            .environment(\.displayScale, 2)
                            .background(Color(nsColor: .windowBackgroundColor)))
                        let hosting = NSHostingView(rootView: view)
                        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                        let png = try XCTUnwrap(MenuLayoutScreenshotRenderTests.pngDataWithWindow(hosting: hosting))
                        let filename = "pace-\(name)-\(language)-\(dark ? "dark" : "light").png"
                        try png.write(to: directory.appendingPathComponent(filename), options: .atomic)
                    }
                }
            }
        }
    }
}
