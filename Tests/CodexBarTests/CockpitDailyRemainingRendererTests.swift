import AppKit
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitDailyRemainingRendererTests {
    @Test(arguments: [0.0, 25.0, 75.0, 100.0], [false, true])
    func `numeric remaining uses daily allocation and ignores used direction`(percent: Double, showUsed: Bool) {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let fixture = MenuBarLayoutRendererTests()
            var data = fixture.data()
            data.cockpitDailyRemaining = .init(
                percent: percent, weeklyPercent: percent / 5, isUpperBound: false, isStale: false)
            let output = MenuBarLayoutRenderer().render(
                layout: .init(lines: [[.cockpitDailyRemaining(style: .percent)]]),
                data: data,
                icon: nil,
                options: fixture.options(showUsed: showUsed))
            #expect(output.attributedTitle.string == "Today \(Int(percent))%")
            #expect(output.accessibilityLabel == L(
                "cockpit_menu_remaining_accessibility", "\(Int(percent))%", "\(Int(percent / 5))%"))
        }
    }

    @Test(arguments: CockpitDailyRemainingStyle.allCases)
    func `bounds stale observations and unavailable data stay distinguishable`(
        style: CockpitDailyRemainingStyle) throws
    {
        let fixture = MenuBarLayoutRendererTests()
        var data = fixture.data()
        let renderer = MenuBarLayoutRenderer()
        let layout = MenuBarLayout(lines: [[.cockpitDailyRemaining(style: style)]])
        let missing = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
        #expect(missing.accessibilityLabel == L("%@ unavailable", L("cockpit_menu_remaining_title")))
        if style == .percent { #expect(missing.attributedTitle.string.hasSuffix("—")) }
        data.cockpitDailyRemaining = .init(percent: 75, weeklyPercent: 15, isUpperBound: false, isStale: false)
        let exact = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
        data.cockpitDailyRemaining = .init(percent: 75, weeklyPercent: 15, isUpperBound: true, isStale: true)
        let partial = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
        #expect(partial.attributedTitle.string.contains("≈≤"))
        #expect(partial.accessibilityLabel.contains("≤75%"))
        #expect(partial.accessibilityLabel.contains("≤15%"))
        #expect(partial.accessibilityLabel.hasSuffix(L("cockpit_ui_stale")))
        #expect(partial.attributedTitle !== exact.attributedTitle)
        data.cockpitDailyRemaining = .init(percent: 25, weeklyPercent: 5, isUpperBound: false, isStale: false)
        let changed = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
        #expect(changed.attributedTitle !== exact.attributedTitle)
        if style != .percent {
            #expect(try self.bitmap(of: self.attachmentImage(exact)).tiffRepresentation
                != self.bitmap(of: self.attachmentImage(changed)).tiffRepresentation)
        }
    }

    @Test(arguments: [CockpitDailyRemainingStyle.bar, .circle])
    func `graphical forms fill continuously and measured empty differs from unavailable`(
        style: CockpitDailyRemainingStyle) throws
    {
        let shape: CockpitDailyRemainingMeter.Shape = style == .bar ? .bar : .circle
        let size = NSSize(width: style == .bar ? 80 : 40, height: 40)
        let bitmaps = try [0.0, 25, 75, 100].map { percent in
            try self.bitmap(of: CockpitDailyRemainingMeter.image(
                shape: shape,
                percent: percent,
                size: size,
                tint: .black))
        }
        let counts = bitmaps.map(self.inkCount)
        #expect(zip(counts, counts.dropFirst()).allSatisfy { $0.0 < $0.1 })
        let unknown = try self.bitmap(of: CockpitDailyRemainingMeter.image(
            shape: shape, percent: nil, size: size, tint: .black))
        #expect(unknown.tiffRepresentation != bitmaps[0].tiffRepresentation)
        #expect(unknown.tiffRepresentation != bitmaps[3].tiffRepresentation)
    }

    @Test
    func `status language override translates all remaining forms and restores cached Chinese`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let fixture = MenuBarLayoutRendererTests()
            var data = fixture.data()
            data.cockpitDailyRemaining = .init(percent: 75, weeklyPercent: 15, isUpperBound: false, isStale: false)
            for style in CockpitDailyRemainingStyle.allCases {
                let renderer = MenuBarLayoutRenderer()
                let layout = MenuBarLayout(lines: [[.cockpitDailyRemaining(style: style)]])
                let chinese = renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
                let english = MenuBarTextLanguage.withEnglish(enabled: true) {
                    renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
                }
                #expect(chinese.attributedTitle.string.hasPrefix("今日 "))
                #expect(english.attributedTitle.string.hasPrefix("Today "))
                #expect(chinese.accessibilityLabel != english.accessibilityLabel)
                #expect(renderer.render(layout: layout, data: data, icon: nil, options: fixture.options())
                    .attributedTitle === chinese.attributedTitle)
            }
        }
    }

    @Test
    func `synthetic remaining meter previews can be exported in light and dark appearance`() throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_PROOF_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            for dark in [false, true] {
                let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
                let image = NSImage(size: NSSize(width: 720, height: 300))
                appearance.performAsCurrentDrawingAppearance {
                    image.lockFocus()
                    (dark ? NSColor.black : .white).setFill()
                    NSRect(origin: .zero, size: image.size).fill()
                    let fixture = MenuBarLayoutRendererTests()
                    for (row, style) in CockpitDailyRemainingStyle.allCases.enumerated() {
                        let y = CGFloat(220 - row * 80)
                        let caption = NSAttributedString(string: style.rawValue, attributes: [
                            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
                        ])
                        caption.draw(at: NSPoint(x: 12, y: y + 30))
                        for (column, percent) in [nil, 0.0, 25, 75, 100].enumerated() {
                            var data = fixture.data()
                            data.cockpitDailyRemaining = percent.map { .init(
                                percent: $0, weeklyPercent: $0 / 5, isUpperBound: false, isStale: false) }
                            let output = MenuBarLayoutRenderer().render(
                                layout: .init(lines: [[.cockpitDailyRemaining(style: style)]]),
                                data: data,
                                icon: nil,
                                options: fixture.options(
                                    highContrast: true,
                                    appearanceName: dark ? "darkAqua" : "aqua"))
                            output.attributedTitle.draw(at: NSPoint(x: CGFloat(column * 140 + 12), y: y))
                        }
                    }
                    image.unlockFocus()
                }
                let bitmap = try self.bitmap(of: image)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("daily-remaining-\(dark ? "dark" : "light").png"))
            }
        }
    }

    private func attachmentImage(_ output: MenuBarLayoutRenderedTitle) throws -> NSImage {
        let text = output.attributedTitle.string
        let index = try #require(text.firstIndex(of: "\u{FFFC}"))
        let attachment = try #require(output.attributedTitle.attribute(
            .attachment, at: text.distance(from: text.startIndex, to: index), effectiveRange: nil) as? NSTextAttachment)
        return try #require(attachment.image)
    }

    private func bitmap(of image: NSImage) throws -> NSBitmapImageRep {
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff))
    }

    private func inkCount(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                count += 1
            }
        }
        return count
    }
}
