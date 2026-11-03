import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MenuBarStatusPrefixTests {
    private let fixture = MenuBarLayoutRendererTests()

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
            #expect(parts[0].hasPrefix("W "))
            #expect(parts[1].hasPrefix("P W "))
            #expect(parts[2].hasPrefix("R W "))
            #expect(parts[3].hasPrefix("E "))
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
        #expect(output.attributedTitle.string == "W 50%\u{2009}T \u{FFFC}\nR W \(reset)\u{2009}E 1d 16h")
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
        #expect(visible.attributedTitle.string.hasPrefix("\(expected) "))
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
        #expect(output.attributedTitle.string == "P F –")
        #expect(output.accessibilityLabel.contains("unavailable"))
    }

    @Test(arguments: [false, true])
    func `pace prefixes stay neutral while the signed value retains its color`(highContrast: Bool) throws {
        let output = MenuBarLayoutRenderer().render(
            layout: .init(lines: [[.pace(window: .weekly)]]),
            data: self.fixture.data(),
            icon: nil,
            options: self.fixture.options(colorPace: true, highContrast: highContrast))
        #expect(output.attributedTitle.string == "P W +11%")
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
            mode: .percent, percentWindow: week, showUsed: true, showPrefixes: true, now: now) == "W 73%")
        #expect(MenuBarDisplayText.displayText(
            mode: .both,
            percentWindow: week,
            pace: pace,
            showUsed: true,
            showPrefixes: true,
            now: now) == "W 73% · P +23%")
        let reset = MenuBarDisplayText.displayText(
            mode: .resetTime, percentWindow: week, showUsed: true, showPrefixes: true, now: now)
        #expect(reset?.hasPrefix("R W ") == true)
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
            now: now) == "R W in 2h")
        let noReset = RateWindow(usedPercent: 100, windowMinutes: 10080, resetsAt: nil, resetDescription: nil)
        #expect(MenuBarDisplayText.displayText(
            mode: .both,
            percentWindow: noReset,
            pace: pace,
            showUsed: true,
            showsResetTimeWhenExhausted: true,
            showPrefixes: true,
            now: now) == "W 100%")
    }
}
