import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CockpitUsageRecommendationBarTests {
    private let fixture = CockpitRecommendationPaceIntegrationTests()

    @Test
    func `the weekly bar receives the automatic target independently of direction and personal cap`() async throws {
        try await self.withFixture { store, plans, settings in
            plans.ingest([.codex: self.fixture.snapshot(
                used: 20, at: Calendar.current.startOfDay(for: self.fixture.now))])
            let snapshot = self.fixture.snapshot(used: 30, at: self.fixture.now)
            plans.ingest([.codex: snapshot])
            store._setSnapshotForTesting(snapshot, provider: .codex)
            let suggested = try #require(plans.status(for: .codex, on: self.fixture.now).suggestedPercent)
            var weeklyPercents: [Double] = []
            for showUsed in [false, true] {
                settings.usageBarsShowUsed = showUsed
                let input = store.menuCardInput(for: .codex, context: .menu, now: self.fixture.now)
                let recommendation = try #require(input.cockpitDailyRecommendation)
                #expect(recommendation.percent == suggested)
                let model = UsageMenuCardView.Model.make(input)
                let weekly = try #require(model.metrics.first { $0.id == "secondary" })
                weeklyPercents.append(weekly.percent)
                #expect(weekly.cockpitDailyRecommendation == recommendation)
                #expect(model.metrics.filter { $0.cockpitDailyRecommendation != nil }.map(\.id) == ["secondary"])
                #expect(model.metrics.first { $0.id == "primary" }?.cockpitDailyRecommendation == nil)
            }
            #expect(weeklyPercents == [70, 30])

            plans.setPersonalCap(1, for: .codex)
            #expect(plans.status(for: .codex, on: self.fixture.now).remainingDailyBudgetPercent == 0)
            let capped = store.menuCardInput(for: .codex, context: .menu, now: self.fixture.now)
            #expect(capped.cockpitDailyRecommendation?.percent == suggested)
        }
    }

    @Test
    func `account organization remote settings and missing inputs never borrow a local recommendation`() async throws {
        try await self.withFixture { store, plans, _ in
            let snapshot = self.fixture.ingestDay(plans)
            store._setSnapshotForTesting(snapshot, provider: .codex)
            #expect(store.menuCardInput(
                for: .codex,
                context: .account(.init(snapshot: snapshot)),
                now: self.fixture.now)
                .cockpitDailyRecommendation != nil)
            let contexts: [UsageMenuCardContext] = [
                .account(.init(snapshot: self.fixture.snapshot(
                    used: 50, at: self.fixture.now, owner: "synthetic-other-account"))),
                .account(.init(snapshot: self.fixture.snapshot(
                    used: 50, at: self.fixture.now, organization: "synthetic-other-organization"))),
                .account(.init(snapshot: snapshot, allowsLocalCockpitPlan: false)),
                .account(.init(snapshot: nil)),
                .settings,
                .settingsAccount(.init(snapshot: snapshot)),
            ]
            for context in contexts {
                let input = store.menuCardInput(for: .codex, context: context, now: self.fixture.now)
                #expect(input.cockpitDailyRecommendation == nil)
                #expect(UsageMenuCardView.Model.make(input).metrics.allSatisfy {
                    $0.cockpitDailyRecommendation == nil
                })
            }
        }
    }

    @Test
    func `additional pools keep their own metrics and never receive the main weekly recommendation`() async throws {
        try await self.withFixture { store, plans, _ in
            let snapshot = self.fixture.ingestDay(plans)
            store._setSnapshotForTesting(snapshot, provider: .codex)
            let input = store.menuCardInput(for: .codex, context: .menu, now: self.fixture.now)
            let model = UsageMenuCardView.Model.make(input)
            var spark = Self.metric(id: "codex-spark-weekly")
            spark.cockpitDailyRecommendation = input.cockpitDailyRecommendation
            let original = model.metrics + [spark, Self.metric(id: "monthly")]
            let attached = UsageMenuCardView.Model.cockpitRecommendationMetrics(original, input: input)
            #expect(attached.map(\.id) == original.map(\.id))
            #expect(attached.map(\.percent) == original.map(\.percent))
            #expect(attached.filter { $0.cockpitDailyRecommendation != nil }.map(\.id) == ["secondary"])

            let monthly = UsageSnapshot(
                primary: nil,
                secondary: RateWindow(
                    usedPercent: 20,
                    windowMinutes: 43200,
                    resetsAt: self.fixture.now.addingTimeInterval(15 * 86400),
                    resetDescription: nil),
                updatedAt: self.fixture.now,
                identity: snapshot.identity)
            let monthlyInput = store.menuCardInput(
                for: .codex, context: .account(.init(snapshot: monthly)), now: self.fixture.now)
            #expect(monthlyInput.cockpitDailyRecommendation == nil)
            #expect(UsageMenuCardView.Model.make(monthlyInput).metrics.allSatisfy {
                $0.cockpitDailyRecommendation == nil
            })
        }
    }

    @Test
    func `recommendation visibility changes tracked height while value changes remain compatible`() async throws {
        try await self.withFixture { store, plans, _ in
            let snapshot = self.fixture.ingestDay(plans)
            store._setSnapshotForTesting(snapshot, provider: .codex)
            let present = UsageMenuCardView.Model.make(store.menuCardInput(
                for: .codex, context: .menu, now: self.fixture.now))
            let weeklyIndex = try #require(present.metrics.firstIndex { $0.cockpitDailyRecommendation != nil })
            var absent = present
            absent.metrics[weeklyIndex].cockpitDailyRecommendation = nil
            #expect(!present.hasCompatibleTrackedLayout(with: absent))
            #expect(!absent.hasCompatibleTrackedLayout(with: present))
            #expect(present.heightFingerprint(section: "usage") != absent.heightFingerprint(section: "usage"))
            var changed = present
            changed.metrics[weeklyIndex].cockpitDailyRecommendation = try #require(CockpitMenuBarRecommendation(
                status: Self.status(suggestion: 30)))
            #expect(present.hasCompatibleTrackedLayout(with: changed))
        }
    }

    @Test(arguments: [false, true], [false, true])
    func `partial and stale targets retain the automatic amount and their uncertainty`(partial: Bool, stale: Bool) {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            var status = Self.status(suggestion: 20, stale: stale)
            status.suggestionIsPartial = partial
            let recommendation = CockpitMenuBarRecommendation(status: status)
            #expect(CockpitUsageRecommendationText.value(recommendation) == "\(partial || stale ? "≈ " : "")20.0%")
            let spoken = CockpitUsageRecommendationText.accessibility(recommendation)
            #expect(spoken.contains("20.0% of the weekly quota"))
            #expect(spoken.contains("incomplete") == partial)
            #expect(spoken.contains(L("cockpit_ui_stale")) == stale)
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func `invalid targets remain missing rather than becoming an empty allowance`(value: Double) {
        #expect(CockpitMenuBarRecommendation(status: Self.status(suggestion: value)) == nil)
        #expect(CockpitUsageRecommendationText.value(nil) == "—")
        #expect(CockpitUsageRecommendationText.accessibility(nil)
            == L("%@ unavailable", L("cockpit_menu_daily_recommendation")))
        #expect(CockpitMenuBarRecommendation(status: Self.status(suggestion: 0))?.percent == 0)
    }

    @Test(arguments: [296.0, 620.0], [false, true])
    func `the recommendation bar sits below the weekly bar with matching native dimensions`(
        width: Double,
        dark: Bool) async throws
    {
        try await self.withFixture { store, plans, _ in
            let snapshot = self.fixture.ingestDay(plans)
            store._setSnapshotForTesting(snapshot, provider: .codex)
            let model = UsageMenuCardView.Model.make(store.menuCardInput(
                for: .codex, context: .menu, now: self.fixture.now))
            let weekly = try #require(model.metrics.first { $0.id == "secondary" })
            let target = try #require(weekly.cockpitDailyRecommendation)
            let host = RecommendationBarHost(
                content: AnyView(MetricRow(
                    metric: weekly, layoutMetric: weekly, title: "Weekly", progressColor: model.progressColor)),
                width: width,
                dark: dark)
            defer { host.close() }
            try await host.settle()
            let nodes = Self.nodes(host.host)
            let weeklyNode = try #require(nodes.first { Self.identifier($0) == "usage-metric-secondary-progress" })
            let recommendedNode = try #require(nodes.first {
                Self.identifier($0) == "cockpit-usage-daily-recommendation-progress"
            })
            let weeklyFrame = try host.frame(of: weeklyNode)
            let recommendationFrame = try host.frame(of: recommendedNode)
            #expect(abs(weeklyFrame.width - recommendationFrame.width) < 1)
            #expect(abs(weeklyFrame.height - 6) < 1)
            #expect(abs(recommendationFrame.height - 6) < 1)
            #expect(host.host.isFlipped
                ? recommendationFrame.minY > weeklyFrame.maxY
                : recommendationFrame.maxY < weeklyFrame.minY)
            #expect(host.host.bounds.insetBy(dx: -1, dy: -1).contains(recommendationFrame))
            let text = MenuLayoutScreenshotRenderTests.accessibilityText(host.host)
            #expect(text.contains(L("cockpit_menu_daily_recommendation")))
            #expect(text.contains(L("cockpit_advice_full_day")))
            #expect(text.contains(CockpitUsageRecommendationText.accessibility(target)))
            try host.exportIfRequested(name: "recommendation-bar-\(Int(width))-\(dark ? "dark" : "light")")

            var missing = weekly
            missing.cockpitDailyRecommendation = nil
            let unavailable = RecommendationBarHost(
                content: AnyView(MetricRow(
                    metric: missing, layoutMetric: missing, title: "Weekly", progressColor: model.progressColor)),
                width: width,
                dark: dark)
            defer { unavailable.close() }
            try await unavailable.settle()
            #expect(!Self.nodes(unavailable.host).contains {
                Self.identifier($0) == "cockpit-usage-daily-recommendation-progress"
            })
        }
    }

    private func withFixture(_ body: (UsageStore, CockpitPlanStore, SettingsStore) async throws -> Void) async throws {
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
        for provider in [UsageProvider.codex, .claude] {
            store.accountInfoCache[provider.instanceID] = .init(
                account: AccountInfo(email: nil, plan: nil),
                configRevision: settings.configRevision,
                expiresAt: .distantFuture)
        }
        store._test_providerRefreshOverride = { _ in Issue.record("Unexpected live provider refresh") }
        store._test_widgetSnapshotSaveOverride = { _ in }
        defer { store.stopSharedSpendDashboardPublication() }
        let plans = CockpitPlanStore(fileURL: folder.appendingPathComponent("plan"))
        store.cockpitPlanStore = plans
        try await body(store, plans, settings)
    }

    private static func metric(id: String) -> UsageMenuCardView.Model.Metric {
        .init(
            id: id,
            title: id,
            percent: 40,
            percentStyle: .left,
            resetText: nil,
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: true)
    }

    private static func status(suggestion: Double?, stale: Bool = false) -> CockpitDayStatus {
        CockpitDayStatus(
            localDateKey: "2026-11-03",
            suggestedPercent: suggestion,
            manualCapPercent: nil,
            usedPercent: nil,
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
private final class RecommendationBarHost {
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
        self.host.frame = CGRect(x: 0, y: 0, width: width, height: 240)
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
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_USAGE_RECOMMENDATION_BAR_PREVIEW_DIR"],
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
