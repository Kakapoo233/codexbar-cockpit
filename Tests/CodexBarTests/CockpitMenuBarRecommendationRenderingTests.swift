import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CockpitMenuBarRecommendationRenderingTests {
    @Test
    func `daily recommendation survives layout persistence without entering older projections`() throws {
        let layout = MenuBarLayout(lines: [[.icon, .cockpitDailyRecommendation, .costToday]])
        let blobs = try MenuBarLayoutPersistence.encoded(layout)
        let decoder = JSONDecoder()
        #expect(try decoder.decode(MenuBarLayout.self, from: blobs.current) == layout)
        for blob in [blobs.v6, blobs.v5, blobs.v4, blobs.v3, blobs.released, blobs.legacy] {
            #expect(try decoder.decode(MenuBarLayout.self, from: blob) == .init(lines: [[.icon, .costToday]]))
            let text = try #require(String(data: blob, encoding: .utf8))
            #expect(!text.contains("cockpitDailyRecommendation"))
        }
        let restored = try MenuBarLayoutPersistence.preferredLayout(
            current: decoder.decode(MenuBarLayout.self, from: blobs.current),
            v6: decoder.decode(MenuBarLayout.self, from: blobs.v6),
            v5: decoder.decode(MenuBarLayout.self, from: blobs.v5),
            v4: decoder.decode(MenuBarLayout.self, from: blobs.v4),
            v3: decoder.decode(MenuBarLayout.self, from: blobs.v3),
            released: decoder.decode(MenuBarLayout.self, from: blobs.released),
            legacy: decoder.decode(MenuBarLayout.self, from: blobs.legacy))
        #expect(restored == layout)
        #expect(MenuBarLayoutPaletteTokens.usage(provider: .codex, snapshot: nil)
            .contains(.cockpitDailyRecommendation))
        #expect(MenuBarLayoutPaletteTokens.conditionalBranch.contains(.cockpitDailyRecommendation))
        #expect(!MenuBarLayout.defaultLayout.lines.joined().contains(.cockpitDailyRecommendation))
        #expect(MenuBarLayoutToken.cockpitDailyRecommendation.editorLabel(provider: .codex)
            == L("cockpit_menu_daily_recommendation"))
        #expect(MenuBarLayoutToken.cockpitDailyRecommendation.editorHelp(provider: .codex)
            .contains(L("cockpit_menu_daily_recommendation_help")))
    }

    @Test
    func `conditional recommendation branches remain in the current library only`() throws {
        let rule = MenuBarLayoutConditional(
            clauses: [.init(
                combinator: nil,
                predicate: .init(metric: .weekly, comparison: .greaterThan, threshold: 50))],
            thenToken: .cockpitDailyRecommendation,
            elseToken: .hidden)
        let blobs = try MenuBarLayoutPersistence.encodedLibrary([rule])
        let decoder = JSONDecoder()
        #expect(try decoder.decode([MenuBarLayoutConditional].self, from: blobs.current) == [rule])
        for blob in [blobs.v6, blobs.v5, blobs.v4, blobs.v3, blobs.released, blobs.legacy] {
            #expect(try decoder.decode([MenuBarLayoutConditional].self, from: blob).isEmpty)
        }
        let restored = try MenuBarLayoutPersistence.preferredLibrary(
            current: decoder.decode([MenuBarLayoutConditional].self, from: blobs.current),
            v6: decoder.decode([MenuBarLayoutConditional].self, from: blobs.v6),
            v5: decoder.decode([MenuBarLayoutConditional].self, from: blobs.v5),
            v4: decoder.decode([MenuBarLayoutConditional].self, from: blobs.v4),
            v3: decoder.decode([MenuBarLayoutConditional].self, from: blobs.v3),
            released: decoder.decode([MenuBarLayoutConditional].self, from: blobs.released),
            legacy: decoder.decode([MenuBarLayoutConditional].self, from: blobs.legacy))
        #expect(restored == [rule])
    }

    @Test(arguments: [0.0, 15.0, 15.4, 100.0, 125.0], [false, true])
    func `daily recommendation keeps its weekly denominator for either usage direction`(
        value: Double,
        showUsed: Bool)
    {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let fixture = MenuBarLayoutRendererTests()
            var data = fixture.data()
            data.cockpitDailyRecommendationPercent = value
            let output = MenuBarLayoutRenderer().render(
                layout: .init(lines: [[.cockpitDailyRecommendation]]),
                data: data,
                icon: nil,
                options: fixture.options(showUsed: showUsed))
            let percent = (value / 100).formatted(
                .percent.precision(.fractionLength(0...1)).locale(Locale(identifier: "en")))
            #expect(output.attributedTitle.string == "Daily \(percent)")
            #expect(output.accessibilityLabel == L("cockpit_menu_daily_recommendation_accessibility", percent))
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func `invalid recommendations remain unavailable rather than becoming a quota`(value: Double) {
        let fixture = MenuBarLayoutRendererTests()
        var data = fixture.data()
        let layout = MenuBarLayout(lines: [[.cockpitDailyRecommendation]])
        let renderer = MenuBarLayoutRenderer()
        let unavailable = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
        data.cockpitDailyRecommendationPercent = value
        let invalid = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
        #expect(invalid.attributedTitle.string == unavailable.attributedTitle.string)
        #expect(invalid.attributedTitle.string == "\(L("cockpit_menu_daily_recommendation_short")) —")
        #expect(invalid.accessibilityLabel == L("%@ unavailable", L("cockpit_menu_daily_recommendation")))
    }

    @Test
    func `partial recommendation is labeled and invalidates the cached title`() {
        let fixture = MenuBarLayoutRendererTests()
        var data = fixture.data()
        data.cockpitDailyRecommendationPercent = 15
        let renderer = MenuBarLayoutRenderer()
        let layout = MenuBarLayout(lines: [[.cockpitDailyRecommendation]])
        let complete = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
        data.cockpitDailyRecommendationIsPartial = true
        let partial = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
        #expect(partial.attributedTitle.string.contains("≈"))
        #expect(!complete.attributedTitle.string.contains("≈"))
        #expect(partial.attributedTitle !== complete.attributedTitle)
        #expect(partial.accessibilityLabel == L(
            "cockpit_menu_daily_recommendation_partial",
            complete.accessibilityLabel))
    }

    @Test
    func `stale recommendation is approximate without claiming partial coverage`() {
        let fixture = MenuBarLayoutRendererTests()
        var data = fixture.data()
        data.cockpitDailyRecommendationPercent = 15
        data.cockpitDailyRecommendationIsStale = true
        let output = MenuBarLayoutRenderer().render(
            layout: .init(lines: [[.cockpitDailyRecommendation]]),
            data: data,
            icon: nil,
            options: fixture.options())
        #expect(output.attributedTitle.string.contains("≈"))
        #expect(output.accessibilityLabel.hasSuffix(L("cockpit_ui_stale")))
        data.cockpitDailyRecommendationIsStale = false
        let fresh = MenuBarLayoutRenderer().render(
            layout: .init(lines: [[.cockpitDailyRecommendation]]),
            data: data,
            icon: nil,
            options: fixture.options())
        #expect(output.accessibilityLabel == fresh.accessibilityLabel + ", " + L("cockpit_ui_stale"))
    }

    @Test
    func `daily recommendation follows the status text language and restores the panel language`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let fixture = MenuBarLayoutRendererTests()
            var data = fixture.data()
            data.cockpitDailyRecommendationPercent = 15
            let renderer = MenuBarLayoutRenderer()
            let layout = MenuBarLayout(lines: [[.cockpitDailyRecommendation]])
            let chinese = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
            let english = MenuBarTextLanguage.withEnglish(enabled: true) {
                renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
            }
            #expect(chinese.attributedTitle.string.hasPrefix("建议 "))
            #expect(english.attributedTitle.string == "Daily 15%")
            #expect(english.accessibilityLabel != chinese.accessibilityLabel)
            #expect(codexBarLocalizationSignature() == "zh-Hans")
            let restored = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
            #expect(restored.attributedTitle === chinese.attributedTitle)
        }
    }
}
