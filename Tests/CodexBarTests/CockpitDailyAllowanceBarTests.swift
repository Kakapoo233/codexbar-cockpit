import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CockpitDailyAllowanceBarTests {
    @Test(arguments: [false, true], [false, true])
    func `allowance bar uses the effective daily allocation and available balance`(
        manual: Bool, constrained: Bool) async throws
    {
        let status = Self.status(
            suggestion: manual ? 10 : 20,
            manual: manual ? 20 : nil,
            balance: constrained ? 6 : 50)
        let remaining = try #require(CockpitMenuBarDailyRemaining(status: status))
        #expect(remaining.percent == (constrained ? 30 : 75))
        #expect(remaining.weeklyPercent == (constrained ? 6 : 15))
        #expect(remaining.percent != status.suggestedPercent)

        let host = DailyAllowanceBarHost(content: AnyView(CockpitDailyAllowanceBar(
            status: status, progressColor: .blue)))
        defer { host.close() }
        try await host.settle()
        let bar = try Self.requireNode("cockpit-advice-daily-remaining-progress", in: host.host)
        let spoken = Self.spokenValue(bar)
        #expect(spoken.contains(CockpitDailyAdviceProjection.remainingDailyText(status)))
        #expect(spoken.contains(CockpitDailyAdviceProjection.remainingWeeklyEquivalentText(status)))
        #expect(Self.nodes(host.host).contains { Self.identifier($0) == "cockpit-advice-remaining-daily-ratio" })
        #expect(!Self.nodes(host.host).contains { Self.identifier($0) == "cockpit-advice-remaining-weekly-equivalent" })
    }

    @Test(arguments: ["allocation", "usage", "balance"])
    func `missing allowance inputs show a dash without drawing an empty progress bar`(missing: String) async throws {
        let status = Self.status(
            suggestion: missing == "allocation" ? nil : 20,
            used: missing == "usage" ? nil : 5,
            balance: missing == "balance" ? nil : 50)
        #expect(CockpitMenuBarDailyRemaining(status: status) == nil)
        let host = DailyAllowanceBarHost(content: AnyView(CockpitDailyAllowanceBar(
            status: status, progressColor: .blue)))
        defer { host.close() }
        try await host.settle()
        #expect(!Self.nodes(host.host).contains { Self.identifier($0) == "cockpit-advice-daily-remaining-progress" })
        let text = MenuLayoutScreenshotRenderTests.accessibilityText(host.host)
        #expect(text.contains("—"))
        #expect(!Self.nodes(host.host).contains { Self.identifier($0) == "cockpit-advice-remaining-weekly-equivalent" })
    }

    @Test(arguments: ["complete", "partial", "unknown", "zero"])
    func `advice replaces weekly balance with available today in weekly units`(state: String) async throws {
        let status = Self.status(
            manual: state == "zero" ? 0 : nil,
            used: state == "unknown" ? nil : 5,
            coverage: state == "partial" ? .partial : .complete)
        let host = DailyAllowanceBarHost(content: AnyView(CockpitDailyAdviceRow(
            provider: .codex, status: status, setCap: { _ in }, layout: .sidebar, showsRecommendation: false)))
        defer { host.close() }
        try await host.settle()
        let value = try Self.requireNode("cockpit-advice-remaining-weekly-equivalent", in: host.host)
        #expect(MenuLayoutScreenshotRenderTests.accessibilityText(value)
            .contains(CockpitDailyAdviceProjection.remainingWeeklyText(status)))
        let text = MenuLayoutScreenshotRenderTests.accessibilityText(host.host)
        #expect(text.contains(L("cockpit_advice_remaining_weekly")))
        #expect(!text.contains(L("cockpit_ui_weekly_remaining")))
        #expect(!text.contains(L("cockpit_ui_observed")))
        #expect(Self.nodes(host.host).filter {
            Self.identifier($0) == "cockpit-advice-remaining-weekly-equivalent"
        }.count == 1)
    }

    @Test(arguments: [false, true])
    func `known zero allocations and overspending have a real zero allowance bar`(zeroAllocation: Bool) async throws {
        let status = Self.status(manual: zeroAllocation ? 0 : nil, used: zeroAllocation ? 0 : 25)
        let remaining = try #require(CockpitMenuBarDailyRemaining(status: status))
        #expect(remaining.percent == 0)
        #expect(remaining.weeklyPercent == 0)
        let host = DailyAllowanceBarHost(content: AnyView(CockpitDailyAllowanceBar(
            status: status, progressColor: .blue)))
        defer { host.close() }
        try await host.settle()
        let bar = try Self.requireNode("cockpit-advice-daily-remaining-progress", in: host.host)
        #expect(Self.spokenValue(bar)
            .contains(CockpitDailyAdviceProjection.remainingDailyText(status)))
    }

    @Test(arguments: [false, true], [false, true])
    func `partial and stale allowance bars retain upper bounds and spoken uncertainty`(
        partial: Bool, stale: Bool) async throws
    {
        var status = Self.status(coverage: partial ? .partial : .complete, stale: stale)
        // The available allowance follows observed-use coverage, not the automatic-target qualifier.
        status.suggestionIsPartial = !partial
        let remaining = try #require(CockpitMenuBarDailyRemaining(status: status))
        #expect(remaining.percent == 75)
        #expect(remaining.isUpperBound == partial)
        #expect(remaining.isStale == stale)
        let host = DailyAllowanceBarHost(content: AnyView(CockpitDailyAllowanceBar(
            status: status, progressColor: .blue)))
        defer { host.close() }
        try await host.settle()
        let bar = try Self.requireNode("cockpit-advice-daily-remaining-progress", in: host.host)
        let spoken = Self.spokenValue(bar)
        #expect(spoken.contains("≤") == partial)
        #expect(spoken.contains(CockpitDailyAdviceProjection.remainingDailyText(status)))
        #expect(spoken.contains(CockpitDailyAdviceProjection.remainingWeeklyEquivalentText(status)))
        #expect(spoken.contains(L("cockpit_ui_stale")) == stale)
    }

    @Test(arguments: [280.0, 620.0], [false, true])
    func `actual advice rows keep a single native allowance bar within both layouts`(
        width: Double, dark: Bool) async throws
    {
        let status = Self.status(suggestion: 10, manual: 20)
        for (layout, name) in [(CockpitDailyAdviceLayout.sidebar, "sidebar"), (.inline, "inline")] {
            let host = DailyAllowanceBarHost(
                content: AnyView(CockpitDailyAdviceRow(
                    provider: .codex,
                    status: status,
                    setCap: { _ in },
                    layout: layout,
                    showsRecommendation: false)),
                width: width,
                dark: dark)
            defer { host.close() }
            try await host.settle()
            let nodes = Self.nodes(host.host)
            let bars = nodes.filter { Self.identifier($0) == "cockpit-advice-daily-remaining-progress" }
            #expect(bars.count == 1)
            let bar = try #require(bars.first)
            let frame = try host.frame(of: bar)
            #expect(abs(frame.height - 6) < 1)
            #expect(frame.width > 150)
            #expect(host.host.bounds.insetBy(dx: -1, dy: -1).contains(frame))
            for identifier in ["cockpit-advice-remaining-daily-ratio", "cockpit-advice-remaining-weekly-equivalent"] {
                let node = try Self.requireNode(identifier, in: host.host)
                #expect(try host.host.bounds.insetBy(dx: -1, dy: -1).contains(host.frame(of: node)))
                #expect(nodes.filter { Self.identifier($0) == identifier }.count == 1)
            }
            let text = MenuLayoutScreenshotRenderTests.accessibilityText(host.host)
            #expect(text.contains(L("cockpit_advice_remaining_today")))
            #expect(text.contains(L("cockpit_advice_remaining_weekly")))
            #expect(text.contains(CockpitDailyAdviceProjection.remainingDailyText(status)))
            #expect(text.contains(CockpitDailyAdviceProjection.remainingWeeklyEquivalentText(status)))
            #expect(!text.contains(L("cockpit_ui_weekly_remaining")))
            #expect(!text.contains(L("cockpit_ui_observed")))
            let weeklyValue = try Self.requireNode("cockpit-advice-remaining-weekly-equivalent", in: host.host)
            #expect(MenuLayoutScreenshotRenderTests.accessibilityText(weeklyValue)
                .contains(CockpitDailyAdviceProjection.remainingWeeklyText(status)))
            #expect(!text.contains(L("cockpit_advice_full_day")))
            #expect(!nodes.contains { Self.identifier($0) == "cockpit-usage-daily-recommendation-progress" })
            try host.exportIfRequested(name: "daily-allowance-\(name)-\(Int(width))-\(dark ? "dark" : "light")")
        }
    }

    private static func status(
        suggestion: Double? = 20,
        manual: Double? = nil,
        used: Double? = 5,
        balance: Double? = 50,
        coverage: CockpitCoverage = .complete,
        stale: Bool = false) -> CockpitDayStatus
    {
        CockpitDayStatus(
            localDateKey: "2026-11-03",
            suggestedPercent: suggestion,
            manualCapPercent: manual,
            usedPercent: used,
            coverage: coverage,
            remainingPercent: balance,
            resetsAt: nil,
            feeling: nil,
            isStale: stale)
    }

    private static func requireNode(_ identifier: String, in root: Any) throws -> NSObject {
        try #require(self.nodes(root).first { Self.identifier($0) == identifier })
    }

    private static func nodes(_ element: Any, depth: Int = 0) -> [NSObject] {
        guard depth < 30, let object = element as? NSObject else { return [] }
        let children = self.property(object, #selector(NSAccessibilityProtocol.accessibilityChildren)) as? [Any] ?? []
        return [object] + children.flatMap { self.nodes($0, depth: depth + 1) }
    }

    private static func identifier(_ object: NSObject) -> String? {
        self.property(object, #selector(NSAccessibilityProtocol.accessibilityIdentifier)) as? String
    }

    private static func spokenValue(_ object: NSObject) -> String {
        // SwiftUI Canvas publishes its custom value through valueDescription on macOS.
        [
            #selector(NSAccessibilityProtocol.accessibilityValueDescription),
            #selector(NSAccessibilityProtocol.accessibilityValue),
        ].compactMap { selector in
            self.property(object, selector).map { value in
                (value as? NSAttributedString)?.string ?? String(describing: value)
            }
        }.joined(separator: ", ")
    }

    private static func property(_ object: NSObject, _ selector: Selector) -> Any? {
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
}

@MainActor
private final class DailyAllowanceBarHost {
    let host: NSHostingView<AnyView>
    private let window: NSWindow

    init(content: AnyView, width: Double = 340, dark: Bool = false) {
        _ = NSApplication.shared
        self.host = NSHostingView(rootView: AnyView(content
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.accessibilityEnabled, true)
                .environment(\.colorScheme, dark ? .dark : .light)))
        self.host.sizingOptions = []
        self.host.frame = CGRect(x: 0, y: 0, width: width, height: 600)
        self.window = NSWindow(contentRect: self.host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        self.window.isReleasedWhenClosed = false
        self.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        self.host.appearance = self.window.appearance
        self.window.contentView = self.host
    }

    func settle() async throws {
        for _ in 0..<3 {
            self.window.layoutIfNeeded()
            self.host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func frame(of node: NSObject) throws -> CGRect {
        let frame = try #require((node.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue)
        return self.host.convert(self.window.convertFromScreen(frame), from: nil)
    }

    func exportIfRequested(name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_DAILY_ALLOWANCE_PREVIEW_DIR"],
              !directory.isEmpty else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bitmap = try #require(self.host.bitmapImageRepForCachingDisplay(in: self.host.bounds))
        self.host.cacheDisplay(in: self.host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }

    func close() {
        self.window.contentView = nil
        self.window.close()
    }
}
