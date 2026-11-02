import AppKit
import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

/// Opt-in measurement of the actual retained panel with a bounded, entirely synthetic ledger.
@MainActor
@Suite(.serialized, CodexCredentialFixtures())
struct CockpitPanelLatencyTests {
    @Test
    func `measure real panel presentation and retained page switching`() async throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_LATENCY_PROBE"] == "1" else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CockpitLatency-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let settings = try Self.settings(in: directory)
        settings.configFileWatcher?.stop()
        let fixture = try Self.fixture(directory: directory, settings: settings, now: now)
        let store = fixture.store
        let plans = fixture.plans
        let tokens = Self.tokens(now: now)
        store._setTokenSnapshotForTesting(
            tokens,
            provider: .codex)
        let input = SpendDashboardModel.ProviderInput(
            provider: .codex,
            displayName: "Synthetic latency",
            snapshot: tokens)
        let configuration = SpendDashboardSource.configuration(
            settings: settings,
            store: store)
        let controller = Self.controller(configuration: configuration, input: input, now: now)
        store.sharedSpendDashboardControllerStorage = controller
        defer {
            controller.stop()
            store.stopSharedSpendDashboardPublication()
            settings.configFileWatcher?.stop()
        }
        var measurements: [String: Double] = [:]
        let loadStart = ContinuousClock.now
        controller.update(configuration: configuration)
        try await SpendDashboardStateWait.until { !controller.isRefreshing }
        measurements["dashboard_initial_publication"] = Self.milliseconds(since: loadStart)
        let statusStart = ContinuousClock.now
        for _ in 0..<20 {
            _ = plans.status(
                for: .codex,
                on: now)
        }
        measurements["twenty_planner_reads"] = Self.milliseconds(since: statusStart)
        let cardStart = ContinuousClock.now
        _ = store.menuCardModel(for: .codex, now: now)
        measurements["provider_card_model"] = Self.milliseconds(since: cardStart)
        for round in 0..<3 {
            let start = ContinuousClock.now
            _ = store.menuCardModel(for: .codex, now: now)
            measurements["warm_provider_card_model_\(round)"] = Self.milliseconds(since: start)
        }
        let firstPreparation = try Self.firstPreparation(store: store, settings: settings, plans: plans)
        for (name, elapsed) in firstPreparation {
            measurements[name] = elapsed
        }
        let ownerStart = ContinuousClock.now
        let owner = Self.owner(store: store, settings: settings, plans: plans)
        measurements["status_controller_init"] = Self.milliseconds(since: ownerStart)
        defer { owner.releaseStatusItemsForTesting() }
        let panel = CockpitMenuPanelController(
            owner: owner,
            presentationIsVisible: { true })
        owner.cockpitMenuPanelController = panel
        panel.bridge.width = CockpitPanelLayout(width: 960).menuCardWidth
        let backingStart = ContinuousClock.now
        let menu = try #require(owner.cockpitBackingMenu(provider: .codex))
        measurements["cold_backing_menu"] = Self.milliseconds(since: backingStart)
        panel.bridge.reload(menu)
        for round in 0..<3 {
            let start = ContinuousClock.now
            owner.populateMenu(
                menu,
                provider: .codex)
            measurements["populate_menu_\(round)"] = Self.milliseconds(since: start)
        }
        let bridge = panel.bridge
        let navigation = panel.navigation
        navigation.planningProviders = [.codex]
        let presentationStart = ContinuousClock.now
        let root = CockpitPanelView(
            settings: settings,
            store: store,
            planStore: plans,
            navigation: navigation,
            usageContent: AnyView(CockpitMenuBridgeView(bridge: bridge)),
            onSettings: {},
            onRefresh: {})
        let host = NSHostingView(rootView: root.codexBarLocalized())
        host.frame = CGRect(
            x: 0,
            y: 0,
            width: 960,
            height: 700)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await Self.settle(host)
        measurements["initial_panel_render"] = Self.milliseconds(since: presentationStart)
        for round in 0..<2 {
            for page in [CockpitPanelPage.statistics, .calendar, .team, .usage] {
                let start = ContinuousClock.now
                navigation.page = page
                try await Self.settle(host)
                measurements["\(round == 0 ? "first" : "retained")_\(page.rawValue)"] = Self.milliseconds(since: start)
            }
        }
        for round in 0..<3 {
            let revision = bridge.revision
            let start = ContinuousClock.now
            panel.invalidate()
            for _ in 0..<100 where bridge.revision == revision {
                try await Task.sleep(for: .milliseconds(1))
            }
            #expect(bridge.revision > revision)
            measurements["panel_rebuild_\(round)"] = Self.milliseconds(since: start)
        }
        let hiddenInvalidations = try await Self.hiddenInvalidations(panel: panel, host: host)
        for (name, elapsed) in hiddenInvalidations {
            measurements[name] = elapsed
        }
        let unrendered = try Self.populateWithoutCardRendering(store: store, settings: settings, plans: plans)
        for (name, elapsed) in unrendered {
            measurements[name] = elapsed
        }
        let data = try JSONSerialization.data(
            withJSONObject: measurements,
            options: [.sortedKeys])
        let text = try #require(String(
            data: data,
            encoding: .utf8))
        print("COCKPIT_LATENCY_MS \(text)")
        let hasRoot = bridge.rootMenu != nil
        let actualSamples = plans.state.snapshots.count
        #expect(hasRoot)
        #expect(actualSamples == fixture.samples)
        if let raw = ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_LATENCY_MAX_MS"],
           let maximum = Double(raw)
        {
            // The legacy counterfactual deliberately retains the expensive native-layout fallback.
            for (name, elapsed) in measurements where !name.hasPrefix("legacy_") {
                #expect(elapsed <= maximum, "\(name) took \(elapsed)ms; budget \(maximum)ms")
            }
        }
    }

    private struct Fixture {
        let store: UsageStore
        let plans: CockpitPlanStore
        let samples: Int
    }

    private static func fixture(directory: URL, settings: SettingsStore, now: Date) throws -> Fixture {
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            historicalUsageHistoryStore: HistoricalUsageHistoryStore(fileURL: directory
                .appendingPathComponent("history.json")),
            planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
            startupBehavior: .testing,
            environmentBase: ["HOME": directory.path, "CODEX_HOME": directory.appendingPathComponent("codex").path],
            pluginApprovalStore: ProviderPluginApprovalStore(fileURL: directory.appendingPathComponent("plugins.json")),
            widgetSnapshotURL: directory.appendingPathComponent("widget.json"),
            cliUsageCacheURL: directory.appendingPathComponent("cli.json"),
            widgetTimelineReloader: {})
        store._test_providerRefreshOverride = { _ in Issue.record("Latency fixture must not contact a provider") }
        store._test_widgetSnapshotSaveOverride = { _ in }
        let planURL = directory.appendingPathComponent("plan.json")
        let bootstrap = CockpitPlanStore(fileURL: planURL)
        let firstSnapshot = Self.snapshot(
            used: 40,
            reset: now.addingTimeInterval(3 * 86400),
            at: now)
        bootstrap.ingest([.codex: firstSnapshot])
        let account = bootstrap.accountID(for: .codex)
        let samples = Int(ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_LATENCY_SAMPLES"] ?? "521") ?? 521
        let feedback = Int(ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_LATENCY_FEEDBACK"] ?? "3") ?? 3
        let seed = Self.seed(
            account: account,
            now: now,
            count: samples,
            feedbackCount: feedback)
        try JSONEncoder().encode(seed).write(to: planURL)
        let plans = CockpitPlanStore(fileURL: planURL)
        let latest = try #require(seed.snapshots.last)
        let snapshot = Self.snapshot(
            used: 100 - latest.remainingPercent,
            reset: latest.resetsAt,
            at: now)
        plans.ingest([.codex: snapshot])
        store.cockpitPlanStore = plans
        store._setSnapshotForTesting(
            snapshot,
            provider: .codex)
        return Fixture(store: store, plans: plans, samples: samples)
    }

    private static func tokens(now: Date) -> CostUsageTokenSnapshot {
        let daily = (0..<44).map { offset in
            CostUsageDailyReport.Entry(
                date: CockpitCalendar.dateKey(for: now.addingTimeInterval(-Double(offset + 1) * 86400)),
                inputTokens: 1000,
                outputTokens: 100,
                totalTokens: 1100,
                costUSD: 0.1,
                modelsUsed: ["synthetic-latency-model"],
                modelBreakdowns: nil)
        }
        let sessionCount = 506
        let eventCount = 28000
        let sessions = (0..<sessionCount).map { index in
            let count = eventCount / sessionCount + (index < eventCount % sessionCount ? 1 : 0)
            return CostUsageSessionBreakdown(
                sessionID: "synthetic-session-\(index)",
                lastActivity: now.addingTimeInterval(-Double(index % 44) * 86400),
                inputTokens: count * 80,
                cachedInputTokens: 0,
                outputTokens: count * 20,
                totalTokens: count * 100,
                requestCount: count,
                costUSD: Double(count) * 0.001,
                modelBreakdowns: [],
                projectPath: "/synthetic/project-\(index % 12)",
                projectName: "Synthetic project \(index % 12)",
                title: "Synthetic session \(index)")
        }
        let slices = (0..<eventCount).map { index in
            CostUsageTimedEntry(
                timestamp: now.addingTimeInterval(-Double(index) / Double(eventCount) * 44 * 86400),
                totalTokens: 100,
                costUSD: 0.001)
        }
        return CostUsageTokenSnapshot(
            sessionTokens: 100,
            sessionCostUSD: 0.001,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            historyDays: 44,
            historyCoverageIsEstablished: true,
            daily: daily,
            sessions: sessions,
            detailsAreComplete: true,
            quotaSlices: slices,
            updatedAt: now)
    }

    private static func controller(
        configuration: SpendDashboardConfiguration,
        input: SpendDashboardModel.ProviderInput,
        now: Date) -> SpendDashboardController
    {
        SpendDashboardController(
            userDefaults: InMemoryUserDefaults(),
            requestBuilder: { mode in
                SpendDashboardLoadRequest(
                    configuration: configuration,
                    capturedInputs: [input],
                    unavailableSourceIDs: [],
                    codexRequests: [],
                    now: now,
                    force: mode.forcesLoader)
            },
            loader: { _ in SpendDashboardLoadResult(
                inputs: [input],
                failedSourceIDs: []) },
            nowProvider: { now })
    }

    private static func owner(
        store: UsageStore,
        settings: SettingsStore,
        plans: CockpitPlanStore,
        renderCards: Bool = true) -> StatusItemController
    {
        settings.agentSessionsEnabled = false
        settings.agentSessionsRemoteEnabled = false
        settings.mergeIcons = false
        settings.selectedMenuProvider = .codex
        store.accountInfoCache[.codex] = .init(
            account: AccountInfo(
                email: nil,
                plan: nil),
            configRevision: settings.configRevision,
            expiresAt: .distantFuture)
        let owner = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(
                email: nil,
                plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar(),
            menuCardRenderingEnabled: renderCards,
            menuRefreshEnabled: false,
            unifiedMenuPanelEnabled: true,
            observeProviderConfigNotifications: false)
        owner.cockpitPlanStore = plans
        return owner
    }

    private static func firstPreparation(
        store: UsageStore,
        settings: SettingsStore,
        plans: CockpitPlanStore) throws -> [String: Double]
    {
        // Legacy goes first so framework startup does not penalize only the corrected path.
        // These measurements cover backing-tree preparation, not full cold-app presentation.
        let legacy = try Self.firstPreparation(store: store, settings: settings, plans: plans, legacy: true)
        let actual = try Self.firstPreparation(store: store, settings: settings, plans: plans, legacy: false)
        return [
            "legacy_unowned_first_populate": legacy,
            "actual_first_prepare": actual,
        ]
    }

    private static func firstPreparation(
        store: UsageStore,
        settings: SettingsStore,
        plans: CockpitPlanStore,
        legacy: Bool) throws -> Double
    {
        let owner = Self.owner(store: store, settings: settings, plans: plans, renderCards: true)
        defer { owner.releaseStatusItemsForTesting() }
        let panel = CockpitMenuPanelController(owner: owner, presentationIsVisible: { false })
        owner.cockpitMenuPanelController = panel
        defer { panel.shutdown() }
        let initiallyEmpty = panel.backingMenu == nil
        #expect(initiallyEmpty)
        let expectedWidth = CockpitPanelLayout(width: 960).menuCardWidth
        panel.bridge.width = expectedWidth
        let start = ContinuousClock.now
        if legacy {
            let menu = try #require(owner.cockpitBackingMenu(provider: .codex))
            owner.populateMenu(menu, provider: .codex)
            panel.bridge.reload(menu)
        } else {
            _ = panel.preparePresentation(
                provider: .codex,
                page: .usage,
                availableSize: NSSize(width: 1024, height: 768))
        }
        let elapsed = Self.milliseconds(since: start)
        let hasRoot = panel.backingMenu != nil
        let actualWidth = panel.bridge.width
        #expect(hasRoot)
        #expect(actualWidth == expectedWidth)
        return elapsed
    }

    private static func hiddenInvalidations(
        panel: CockpitMenuPanelController,
        host: NSView) async throws -> [String: Double]
    {
        panel.navigation.page = .statistics
        try await self.settle(host)
        let initialRevision = panel.bridge.revision
        let start = ContinuousClock.now
        for _ in 0..<10 {
            panel.invalidate()
        }
        let callsElapsed = Self.milliseconds(since: start)
        for _ in 0..<2 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(1))
        }
        let settledElapsed = Self.milliseconds(since: start)
        let hiddenRevision = panel.bridge.revision
        #expect(hiddenRevision == initialRevision)
        let returnStart = ContinuousClock.now
        panel.navigation.page = .usage
        let returnedElapsed = Self.milliseconds(since: returnStart)
        let visibleRevision = panel.bridge.revision
        #expect(visibleRevision == initialRevision + 1)
        for _ in 0..<2 {
            await Task.yield()
        }
        let finalRevision = panel.bridge.revision
        #expect(finalRevision == visibleRevision)
        return [
            "hidden_invalidation_calls": callsElapsed,
            "hidden_invalidations_settled": settledElapsed,
            "usage_return_flush": returnedElapsed,
        ]
    }

    private static func populateWithoutCardRendering(
        store: UsageStore,
        settings: SettingsStore,
        plans: CockpitPlanStore) throws -> [String: Double]
    {
        let owner = Self.owner(store: store, settings: settings, plans: plans, renderCards: false)
        defer { owner.releaseStatusItemsForTesting() }
        let panel = CockpitMenuPanelController(owner: owner, presentationIsVisible: { true })
        owner.cockpitMenuPanelController = panel
        panel.bridge.width = CockpitPanelLayout(width: 960).menuCardWidth
        let menu = try #require(owner.cockpitBackingMenu(provider: .codex))
        panel.bridge.reload(menu)
        var measurements: [String: Double] = [:]
        for round in 0..<3 {
            let start = ContinuousClock.now
            owner.populateMenu(menu, provider: .codex)
            measurements["populate_without_card_render_\(round)"] = Self.milliseconds(since: start)
        }
        return measurements
    }

    private static func settle(_ host: NSView) async throws {
        for _ in 0..<2 {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
    }

    private static func snapshot(
        used: Double,
        reset: Date,
        at date: Date) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: 10,
                windowMinutes: 300,
                resetsAt: date.addingTimeInterval(7200),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: used,
                windowMinutes: 10080,
                resetsAt: reset,
                resetDescription: nil),
            updatedAt: date,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: nil,
                accountID: "synthetic-latency-account"))
    }

    private struct Seed: Encodable {
        let snapshots: [CockpitQuotaSnapshot]
        var plans: [CockpitDailyPlan] = []
        var personalCaps: [CockpitPersonalCap] = []
        let comfortRecords: [CockpitComfortRecord]
        var observedDaySummaries: [CockpitObservedDaySummary] = []
    }

    private static func seed(
        account: String,
        now: Date,
        count: Int,
        feedbackCount: Int) -> Seed
    {
        let origin = now.addingTimeInterval(-Double((count - 1) * 300))
        let week = 604_800.0
        let samples = (0..<count).map { index in
            let elapsed = Double(index * 300)
            let cycle = floor(elapsed / week)
            let progress = elapsed - cycle * week
            return CockpitQuotaSnapshot(
                providerID: "codex",
                accountID: account,
                capturedAt: origin.addingTimeInterval(elapsed),
                remainingPercent: 100 - progress / week * 55,
                resetsAt: origin.addingTimeInterval((cycle + 1) * week))
        }
        let calendar = Calendar.current
        let feedback = (0..<feedbackCount).map { offset in
            let date = now.addingTimeInterval(-Double(offset + 1) * 86400)
            return CockpitComfortRecord(
                providerID: "codex",
                accountID: account,
                localDateKey: CockpitCalendar.dateKey(
                    for: date,
                    calendar: calendar),
                timeZoneIdentifier: calendar.timeZone.identifier,
                recordedAt: date,
                feeling: offset % 3 == 0 ? .overloaded : offset % 3 == 1 ? .comfortable :
                    .light,
                totalTokens: nil,
                coverage: .complete,
                usedPercent: Double(10 + offset % 50))
        }
        return Seed(
            snapshots: samples,
            comfortRecords: feedback)
    }

    private static func settings(in directory: URL) throws -> SettingsStore {
        let configStore = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        var config = testConfigWithAllProvidersDisabled()
        config.setProviderConfig(ProviderConfig(
            id: .codex,
            enabled: true,
            source: .oauth))
        try configStore.save(config)
        return SettingsStore(
            userDefaults: InMemoryUserDefaults(values: [
                "tokenCostUsageEnabled": true,
                "preferredCurrencyCode": "USD",
                "statusChecksEnabled": false,
            ]),
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore(fileURL: directory.appendingPathComponent("accounts.json")),
            antigravityOAuthCredentialsStore: AntigravityOAuthCredentialsStore(fileURL: directory
                .appendingPathComponent("antigravity.json")),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in },
                isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
    }
}
