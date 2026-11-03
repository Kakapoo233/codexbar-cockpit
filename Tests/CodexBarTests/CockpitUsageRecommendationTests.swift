import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CockpitUsageRecommendationTests {
    private let fixture = CockpitRecommendationPaceIntegrationTests()

    @Test
    func `top recommendation uses the automatic full day share independently of a manual cap`() async throws {
        try await self.withFixture { store, plans in
            let snapshot = self.fixture.ingestDay(plans)
            store._setSnapshotForTesting(snapshot, provider: .codex)
            let suggestion = try #require(plans.status(for: .codex, on: self.fixture.now).suggestedPercent)
            plans.setPersonalCap(1, for: .codex)
            let status = try #require(plans.status(for: .codex, matching: snapshot, on: self.fixture.now))
            #expect(status.effectiveCapPercent == 1)
            #expect(status.suggestedPercent == suggestion)
            #expect(status.remainingDailyBudgetPercent == 0)

            let host = self.host(store: store, plans: plans)
            defer { host.close() }
            try await host.settle()
            let row = try self.row(in: host)
            let text = MenuLayoutScreenshotRenderTests.accessibilityText(row)
            #expect(text.contains(L(
                "cockpit_menu_daily_recommendation_accessibility",
                cockpitLocalizedPercent(suggestion))))
            #expect(text.contains("Codex"))
        }
    }

    @Test
    func `scope and account switches cannot borrow an unrelated provider or previous account plan`() async throws {
        try await self.withFixture { store, plans in
            let snapshot = self.fixture.ingestDay(plans)
            store._setSnapshotForTesting(snapshot, provider: .codex)
            let scoped = self.host(store: store, plans: plans, providers: [.codex, .claude, .codex])
            defer { scoped.close() }
            try await scoped.settle()
            #expect(Self.nodes(scoped.host).filter { Self.identifier($0) == Self.rowID }.count == 1)
            #expect(!Self.nodes(scoped.host).contains {
                Self.identifier($0) == "cockpit-usage-daily-recommendation-claude"
            })

            let next = self.fixture.snapshot(used: 80, at: self.fixture.now, owner: "synthetic-next-owner")
            store._setSnapshotForTesting(next, provider: .codex)
            let pending = self.host(store: store, plans: plans)
            defer { pending.close() }
            try await pending.settle()
            #expect(try MenuLayoutScreenshotRenderTests.accessibilityText(self.row(in: pending))
                .contains(L("%@ unavailable", L("cockpit_menu_daily_recommendation"))))

            plans.ingest([.codex: next])
            let resolved = self.host(store: store, plans: plans)
            defer { resolved.close() }
            try await resolved.settle()
            let status = try #require(plans.status(for: .codex, matching: next, on: self.fixture.now))
            let value = try #require(status.suggestedPercent)
            #expect(try MenuLayoutScreenshotRenderTests.accessibilityText(self.row(in: resolved))
                .contains(L("cockpit_menu_daily_recommendation_accessibility", cockpitLocalizedPercent(value))))
        }
    }

    @Test(arguments: [false, true], [false, true])
    func `incomplete or stale recommendations are approximate without substituting today's remaining allowance`(
        partial: Bool,
        stale: Bool)
    {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            var status = Self.status(suggestion: 20, manual: 10, used: 5, stale: stale)
            status.suggestionIsPartial = partial
            let text = CockpitUsageRecommendationText.value(status)
            #expect(text == "\(partial || stale ? "≈ " : "")20.0%")
            #expect(status.remainingDailyBudgetPercent == 50)
            let spoken = CockpitUsageRecommendationText.accessibility(status)
            #expect(spoken.contains("20.0% of the weekly quota"))
            #expect(spoken.contains("incomplete") == partial)
            #expect(spoken.contains(L("cockpit_ui_stale")) == stale)
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func `invalid or missing recommendation readings remain unknown`(value: Double) {
        for status in [nil, Self.status(suggestion: nil), Self.status(suggestion: value)] {
            #expect(CockpitUsageRecommendationText.value(status) == "—")
            #expect(CockpitUsageRecommendationText.accessibility(status)
                == L("%@ unavailable", L("cockpit_menu_daily_recommendation")))
        }
        #expect(CockpitUsageRecommendationText.value(Self.status(suggestion: 0)) == cockpitLocalizedPercent(0))
    }

    @Test(arguments: [360.0, 676.0, 960.0], [false, true])
    func `the native header exposes its title units and current recommendation within narrow and wide bounds`(
        width: Double,
        dark: Bool) async throws
    {
        try await self.withFixture { store, plans in
            let snapshot = self.fixture.ingestDay(plans)
            store._setSnapshotForTesting(snapshot, provider: .codex)
            let host = self.host(store: store, plans: plans, width: width, dark: dark)
            defer { host.close() }
            try await host.settle()

            #expect(abs(host.host.bounds.width - width) < 0.5)
            #expect(abs(host.host.bounds.height - 200) < 0.5)
            let text = MenuLayoutScreenshotRenderTests.accessibilityText(host.host)
            #expect(text.contains(L("cockpit_menu_daily_recommendation")))
            #expect(text.contains(L("cockpit_advice_full_day")))
            let row = try self.row(in: host)
            let frame = try host.frame(of: row)
            let status = try #require(plans.status(for: .codex, matching: snapshot, on: self.fixture.now))
            let recommendation = try cockpitLocalizedPercent(#require(status.suggestedPercent))
            let rowText = MenuLayoutScreenshotRenderTests.accessibilityText(row)
            #expect(rowText.contains("Codex"))
            #expect(rowText.contains(L("cockpit_menu_daily_recommendation_accessibility", recommendation)))
            let baseFont = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
            let rounded = try #require(baseFont.fontDescriptor.withDesign(.rounded))
            let valueFont = try #require(NSFont(descriptor: rounded, size: 28))
            let intrinsicWidth = NSAttributedString(string: recommendation, attributes: [.font: valueFont]).size().width
            // AX encloses rendered ink, not the row's empty minimum-width padding.
            #expect(frame.width + 2 >= intrinsicWidth)
            #expect(frame.height >= 28)
            #expect(host.host.bounds.insetBy(dx: -1, dy: -1).contains(frame))
            try host.exportIfRequested(name: "usage-recommendation-\(Int(width))-\(dark ? "dark" : "light")")
        }
    }

    private static let rowID = "cockpit-usage-daily-recommendation-codex"

    private func row(in fixture: UsageRecommendationHost) throws -> NSObject {
        let nodes = Self.nodes(fixture.host)
        let fields = [
            #selector(NSAccessibilityProtocol.accessibilityRole),
            #selector(NSAccessibilityProtocol.accessibilityIdentifier),
            #selector(NSAccessibilityProtocol.accessibilityLabel),
            #selector(NSAccessibilityProtocol.accessibilityValue),
        ]
        let diagnostic = nodes.map { node in
            let values = fields.map { selector in
                let value = Self.property(node, selector).map { String(describing: $0) } ?? "nil"
                return "\(NSStringFromSelector(selector))=\(value)"
            }.joined(separator: " | ")
            return "\(NSStringFromClass(type(of: node))): \(values)"
        }.joined(separator: "\n")
        try fixture.exportDiagnosticIfRequested(diagnostic)
        return try #require(nodes.first { Self.identifier($0) == Self.rowID })
    }

    private func host(
        store: UsageStore,
        plans: CockpitPlanStore,
        providers: [UsageProvider] = [.codex],
        width: Double = 676,
        dark: Bool = false) -> UsageRecommendationHost
    {
        UsageRecommendationHost(
            content: AnyView(CockpitUsageRecommendationHeader(planStore: plans, store: store, providers: providers)
                .content(on: self.fixture.now)),
            width: width,
            dark: dark)
    }

    private func withFixture(_ body: (UsageStore, CockpitPlanStore) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        defer { settings.configFileWatcher?.stop() }
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(homeDirectory: folder.path, cacheTTL: 0),
            settings: settings,
            historicalUsageHistoryStore: HistoricalUsageHistoryStore(fileURL: folder.appendingPathComponent("history")),
            planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
            startupBehavior: .testing,
            environmentBase: ["HOME": folder.path, "CODEX_HOME": folder.appendingPathComponent("codex").path],
            pluginApprovalStore: ProviderPluginApprovalStore(fileURL: folder.appendingPathComponent("plugins")),
            widgetSnapshotURL: folder.appendingPathComponent("widget"),
            cliUsageCacheURL: folder.appendingPathComponent("cli"),
            widgetTimelineReloader: {})
        store._test_providerRefreshOverride = { _ in Issue.record("Unexpected live provider refresh") }
        store._test_widgetSnapshotSaveOverride = { _ in }
        defer { store.stopSharedSpendDashboardPublication() }
        let plans = CockpitPlanStore(fileURL: folder.appendingPathComponent("plan"))
        store.cockpitPlanStore = plans
        try await body(store, plans)
    }

    private static func status(
        suggestion: Double?,
        manual: Double? = nil,
        used: Double? = nil,
        stale: Bool = false) -> CockpitDayStatus
    {
        CockpitDayStatus(
            localDateKey: "2026-11-03",
            suggestedPercent: suggestion,
            manualCapPercent: manual,
            usedPercent: used,
            coverage: .complete,
            remainingPercent: 50,
            resetsAt: nil,
            feeling: nil,
            isStale: stale)
    }

    private static func nodes(_ element: Any, depth: Int = 0) -> [NSObject] {
        guard depth < 30, let object = element as? NSObject else { return [] }
        let children = self.property(object, #selector(NSAccessibilityProtocol.accessibilityChildren)) as? [Any] ?? []
        return [object] + children.flatMap { self.nodes($0, depth: depth + 1) }
    }

    private static func identifier(_ object: NSObject) -> String? {
        self.property(object, #selector(NSAccessibilityProtocol.accessibilityIdentifier)) as? String
    }

    private static func property(_ object: NSObject, _ selector: Selector) -> Any? {
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
}

@MainActor
private final class UsageRecommendationHost {
    let host: NSHostingView<AnyView>
    private let window: NSWindow

    init(content: AnyView, width: Double, dark: Bool) {
        _ = NSApplication.shared
        self.host = NSHostingView(rootView: AnyView(content
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.accessibilityEnabled, true)
                .environment(\.colorScheme, dark ? .dark : .light)))
        self.host.sizingOptions = []
        self.host.frame = CGRect(x: 0, y: 0, width: width, height: 200)
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
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_USAGE_RECOMMENDATION_PREVIEW_DIR"],
              !directory.isEmpty else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bitmap = try #require(self.host.bitmapImageRepForCachingDisplay(in: self.host.bounds))
        self.host.cacheDisplay(in: self.host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }

    func exportDiagnosticIfRequested(_ text: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_USAGE_RECOMMENDATION_PREVIEW_DIR"],
              !directory.isEmpty else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try text.write(
            to: output.appendingPathComponent("usage-recommendation-ax-\(UUID().uuidString).txt"),
            atomically: true,
            encoding: .utf8)
    }

    func close() {
        self.window.contentView = nil
        self.window.close()
    }
}
