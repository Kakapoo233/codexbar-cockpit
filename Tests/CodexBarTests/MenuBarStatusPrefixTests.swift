import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MenuBarStatusPrefixTests {
    private let fixture = MenuBarLayoutRendererTests()

    @Test
    func `prefixed reset countdown omits in while unprefixed text and spoken time remain complete`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let data = self.fixture.data()
            let renderer = MenuBarLayoutRenderer()
            let layout = MenuBarLayout(lines: [[.windowResetCountdown(window: .weekly)]])
            let visible = renderer.render(layout: layout, data: data, icon: nil, options: self.fixture.options())
            #expect(visible.attributedTitle.string == "R\u{200A}3d")
            #expect(visible.accessibilityLabel == "Weekly: in 3d")
            let hidden = renderer.render(
                layout: layout, data: data, icon: nil, options: self.fixture.options(showWindowLabels: false))
            #expect(hidden.attributedTitle.string == "in 3d")
            #expect(hidden.accessibilityLabel == visible.accessibilityLabel)

            let date = self.fixture.now.addingTimeInterval(3 * 24 * 60 * 60)
            let absolute = renderer.render(
                layout: .init(lines: [[.windowResetAbsolute(window: .weekly)]]),
                data: data,
                icon: nil,
                options: self.fixture.options())
            let fullDate = UsageFormatter.resetDescription(from: date, now: self.fixture.now)
            #expect(absolute.attributedTitle.string == "R\u{200A}\(fullDate)")
            #expect(absolute.accessibilityLabel == "Weekly: \(fullDate)")

            let week = RateWindow(
                usedPercent: 50,
                windowMinutes: 10080,
                resetsAt: self.fixture.now.addingTimeInterval(7200),
                resetDescription: nil)
            #expect(MenuBarDisplayText.resetTimeText(
                window: week, style: .countdown, showPrefixes: true, now: self.fixture.now) == "R\u{200A}2h")
            #expect(MenuBarDisplayText.resetTimeText(
                window: week, style: .countdown, now: self.fixture.now) == "↻ in 2h")
        }
    }

    @Test(arguments: [
        MenuBarLayoutToken.resetCountdown, .resetAbsolute,
        .windowResetCountdown(window: .weekly), .windowResetAbsolute(window: .weekly),
        .windowResetCountdown(window: .automatic), .windowResetAbsolute(window: .automatic),
    ])
    func `weekly reset variants use a single R and retain the spoken weekly context`(token: MenuBarLayoutToken) {
        let data = self.fixture.data(
            automaticUsedPercent: 60,
            automaticResetAt: self.fixture.now.addingTimeInterval(3 * 24 * 60 * 60),
            automaticWindowMinutes: 10080)
        let output = MenuBarLayoutRenderer().render(
            layout: .init(lines: [[token]]), data: data, icon: nil, options: self.fixture.options())
        #expect(output.attributedTitle.string.hasPrefix("R\u{200A}"))
        #expect(!output.attributedTitle.string.contains("R W"))
        #expect(output.accessibilityLabel.contains("Weekly"))
        #expect(!output.accessibilityLabel.contains("\u{200A}"))
    }

    @Test(arguments: MenuBarLayoutSize.allCases)
    func `the prefix separator is visibly narrower than a normal space`(size: MenuBarLayoutSize) {
        let output = MenuBarLayoutRenderer().render(
            layout: .init(lines: [[.percent(window: .weekly)]]),
            data: self.fixture.data(),
            icon: nil,
            options: self.fixture.options(size: size))
        #expect(output.attributedTitle.string == "W\u{200A}60%")
        let oldSpacing = NSAttributedString(
            string: "W 60%", attributes: output.attributedTitle.attributes(at: 0, effectiveRange: nil))
        #expect(output.attributedTitle.size().width < oldSpacing.size().width)
    }

    @Test(arguments: CockpitDailyRemainingStyle.allCases)
    func `today values and graphical forms retain T with the compact separator`(style: CockpitDailyRemainingStyle) {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            var data = self.fixture.data()
            data.cockpitDailyRemaining = .init(percent: 75, weeklyPercent: 15, isUpperBound: false, isStale: false)
            let output = MenuBarLayoutRenderer().render(
                layout: .init(lines: [[.cockpitDailyRemaining(style: style)]]),
                data: data,
                icon: nil,
                options: self.fixture.options())
            #expect(output.attributedTitle.string.hasPrefix("T\u{200A}"))
            if style == .percent { #expect(output.attributedTitle.string == "T\u{200A}75%") }
            #expect(output.accessibilityLabel.contains("75%"))
            #expect(output.accessibilityLabel.contains("15%"))
        }
    }

    @Test(arguments: ["en", "zh-Hans", "ja", "ar"])
    func `period and metric initials stay English while surrounding content keeps the app language`(language: String) {
        CodexBarLocalizationOverride.$appLanguage.withValue(language) {
            let data = self.fixture.data(automaticWindowMinutes: 10080)
            let layout = MenuBarLayout(lines: [[
                .percent(window: .automatic), .pace(window: .weekly),
                .windowResetCountdown(window: .weekly), .runsOutCompact,
            ]])
            let output = MenuBarLayoutRenderer().render(
                layout: layout, data: data, icon: nil, options: self.fixture.options(colorPace: true))
            let parts = output.attributedTitle.string.components(separatedBy: "\u{2009}")
            #expect(parts[0].hasPrefix("W\u{200A}"))
            #expect(parts[1].hasPrefix("P W\u{200A}"))
            #expect(parts[2].hasPrefix("R\u{200A}"))
            #expect(parts[3].hasPrefix("E\u{200A}"))
            #expect(codexBarLocalizationSignature() == language)
            #expect(!output.accessibilityLabel.contains("P W"))
            #expect(!output.accessibilityLabel.contains("R W"))
        }
    }

    @Test
    func `the saved two row layout distinguishes weekly quota today reset and exhaustion`() {
        var data = self.fixture.data(automaticWindowMinutes: 10080)
        data.cockpitDailyRemaining = .init(percent: 70, weeklyPercent: 14, isUpperBound: false, isStale: false)
        let layout = MenuBarLayout(lines: [
            [.percent(window: .automatic), .cockpitDailyRemaining(style: .bar)],
            [.windowResetCountdown(window: .weekly), .runsOutCompact],
        ])
        let output = MenuBarLayoutRenderer().render(
            layout: layout, data: data, icon: nil, options: self.fixture.options())
        let reset = UsageFormatter.resetCountdownDescription(
            from: self.fixture.now.addingTimeInterval(3 * 24 * 60 * 60), now: self.fixture.now)
        let visibleReset = String(reset.dropFirst(3))
        #expect(output.attributedTitle
            .string == "W\u{200A}50%\u{2009}T\u{200A}\u{FFFC}\nR\u{200A}\(visibleReset)\u{2009}E\u{200A}1d 16h")
        #expect(output.accessibilityLabel.contains("Weekly"))
        #expect(output.accessibilityLabel.contains("Runs out in 1d 16h"))
    }

    @Test(arguments: [300, 1440, 10080, 40320, 43200, 44640], [false, true])
    func `automatic numeric and graphical forms share actual period initials`(minutes: Int, graphical: Bool) {
        let expected = minutes == 300 ? "S" : minutes == 1440 ? "D" : minutes == 10080 ? "W" : "M"
        let data = self.fixture.data(automaticWindowMinutes: minutes)
        let token: MenuBarLayoutToken = graphical ? .progressBar(window: .automatic) : .percent(window: .automatic)
        let renderer = MenuBarLayoutRenderer()
        let layout = MenuBarLayout(lines: [[token]])
        let visible = renderer.render(layout: layout, data: data, icon: nil, options: self.fixture.options())
        #expect(visible.attributedTitle.string.hasPrefix("\(expected)\u{200A}"))
        let hidden = renderer.render(
            layout: layout, data: data, icon: nil, options: self.fixture.options(showWindowLabels: false))
        #expect(hidden.attributedTitle.string == (graphical ? "\u{FFFC}" : "50%"))
        #expect(hidden.accessibilityLabel == visible.accessibilityLabel)
        let restored = renderer.render(layout: layout, data: data, icon: nil, options: self.fixture.options())
        #expect(restored.attributedTitle === visible.attributedTitle)
    }

    @Test
    func `missing pace retains its own initial while its value stays unknown`() {
        let data = self.fixture.data(metrics: .unavailable)
        let output = MenuBarLayoutRenderer().render(
            layout: .init(lines: [[.pace(window: .scopedWeekly)]]),
            data: data,
            icon: nil,
            options: self.fixture.options())
        #expect(output.attributedTitle.string == "P F\u{200A}–")
        #expect(output.accessibilityLabel.contains("unavailable"))
    }

    @Test(arguments: [false, true])
    func `pace prefixes stay neutral while the signed value retains its color`(highContrast: Bool) throws {
        let output = MenuBarLayoutRenderer().render(
            layout: .init(lines: [[.pace(window: .weekly)]]),
            data: self.fixture.data(),
            icon: nil,
            options: self.fixture.options(colorPace: true, highContrast: highContrast))
        #expect(output.attributedTitle.string == "P W\u{200A}+11%")
        let text = output.attributedTitle.string as NSString
        let value = text.range(of: "+11%")
        try #require(value.location != NSNotFound)
        output.attributedTitle.enumerateAttribute(
            .foregroundColor, in: NSRange(location: 0, length: value.location))
        { color, _, _ in
            #expect(color as? NSColor == (highContrast ? .labelColor : .controlTextColor))
        }
        output.attributedTitle.enumerateAttribute(.foregroundColor, in: value) { color, _, _ in
            #expect(color as? NSColor == .systemRed)
        }
    }

    @Test
    func `legacy prefixed modes distinguish quota pace reset and exhausted fallback`() {
        let now = self.fixture.now
        let week = RateWindow(
            usedPercent: 73,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(7 * 24 * 60 * 60 / 2),
            resetDescription: nil)
        let pace = UsagePace.weekly(window: week, now: now)
        #expect(MenuBarDisplayText.displayText(
            mode: .percent, percentWindow: week, showUsed: true, showPrefixes: true, now: now) == "W\u{200A}73%")
        #expect(MenuBarDisplayText.displayText(
            mode: .both,
            percentWindow: week,
            pace: pace,
            showUsed: true,
            showPrefixes: true,
            now: now) == "W\u{200A}73% · P\u{200A}+23%")
        let reset = MenuBarDisplayText.displayText(
            mode: .resetTime, percentWindow: week, showUsed: true, showPrefixes: true, now: now)
        #expect(reset?.hasPrefix("R\u{200A}") == true)
        #expect(reset?.contains("↻") == false)
        let exhausted = RateWindow(
            usedPercent: 100,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(7200),
            resetDescription: nil)
        #expect(MenuBarDisplayText.displayText(
            mode: .both,
            percentWindow: exhausted,
            pace: pace,
            showUsed: true,
            showsResetTimeWhenExhausted: true,
            showPrefixes: true,
            now: now) == "R\u{200A}2h")
        let noReset = RateWindow(usedPercent: 100, windowMinutes: 10080, resetsAt: nil, resetDescription: nil)
        #expect(MenuBarDisplayText.displayText(
            mode: .both,
            percentWindow: noReset,
            pace: pace,
            showUsed: true,
            showsResetTimeWhenExhausted: true,
            showPrefixes: true,
            now: now) == "W\u{200A}100%")
    }
}
