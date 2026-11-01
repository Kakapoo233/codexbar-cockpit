import AppKit
import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@MainActor
struct CockpitMenuBarRecommendationTests {
    private let now = Date()

    @Test
    func `menu recommendation matches full day advice and never uses manual cap or remaining allowance`() throws {
        try self.withFixture { store, plans, _ in
            let snapshot = self.snapshot()
            plans.ingest([.claude: snapshot])
            let expected = try #require(plans.status(for: .claude, on: self.now).suggestedPercent)
            plans.setPersonalCap(1, for: .claude)
            #expect(plans.status(for: .claude, on: self.now).manualCapPercent == 1)
            let rendered = self.renderData(store, snapshot: snapshot)
            #expect(rendered.cockpitDailyRecommendationPercent == expected)
            #expect(rendered.cockpitDailyRecommendationIsPartial)
            #expect(!rendered.cockpitDailyRecommendationIsStale)
            #expect(self.renderData(store, snapshot: snapshot, local: false)
                .cockpitDailyRecommendationPercent == nil)
            #expect(self.renderData(store, snapshot: snapshot, included: false)
                .cockpitDailyRecommendationPercent == nil)
            #expect(self.renderData(store, snapshot: snapshot, now: self.now.addingTimeInterval(1801))
                .cockpitDailyRecommendationIsStale)
            #expect(self.renderData(store, snapshot: snapshot, now: self.now.addingTimeInterval(6 * 86400))
                .cockpitDailyRecommendationPercent == nil)
        }
    }

    @Test
    func `account organization provider and unknown identities cannot borrow a recommendation`() throws {
        try self.withFixture { store, plans, _ in
            let original = self.snapshot()
            plans.ingest([.claude: original])
            #expect(self.renderData(store, snapshot: original).cockpitDailyRecommendationPercent != nil)
            for mismatch in [
                self.snapshot(account: "other"), self.snapshot(organization: "other"),
                self.snapshot(account: nil), self.snapshot(provider: .codex), self.snapshot(minutes: 300),
            ] {
                #expect(self.renderData(store, snapshot: mismatch).cockpitDailyRecommendationPercent == nil)
            }
            let switched = self.snapshot(account: "other")
            plans.ingest([.claude: switched])
            #expect(self.renderData(store, snapshot: original).cockpitDailyRecommendationPercent == nil)
            #expect(self.renderData(store, snapshot: switched).cockpitDailyRecommendationPercent != nil)
            plans.ingest([:])
            #expect(self.renderData(store, snapshot: switched).cockpitDailyRecommendationPercent == nil)
        }
    }

    @Test
    func `comfort changes invalidate the existing icon observation without an open panel`() async throws {
        try await self.withFixture { store, plans, _ in
            plans.ingest([.claude: self.snapshot()])
            await confirmation { changed in
                withObservationTracking { _ = store.iconObservationToken } onChange: { changed() }
                plans.setQuotaComfortFeeling(.comfortable, for: .claude, on: self.now, now: self.now)
            }
        }
    }

    @Test
    func `public reset updates invalidate icons and change advice without quota polling`() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = self.now
        let announcement = try CockpitScheduledReset(
            id: "synthetic-menu-reset",
            kind: .regular,
            announcedAt: now.addingTimeInterval(-60),
            scheduledFor: now.addingTimeInterval(3600),
            text: "Synthetic reset",
            sourceURL: #require(URL(string: "https://example.com/reset")))
        let status = CockpitResetStatus(generatedAt: now, scheduledReset: announcement)
        let resets = CockpitResetHistoryStore(
            cacheURL: folder.appendingPathComponent("resets.json"),
            receiptsURL: folder.appendingPathComponent("notices.json"),
            notificationsEnabled: { false },
            fetch: { CockpitResetHistory(events: [], generatedAt: now) },
            fetchStatus: { status },
            now: { now },
            post: { _ in Issue.record("No notifications expected") },
            remove: { _ in })
        try await self.withFixture(resets: resets) { store, plans, _ in
            let snapshot = self.snapshot(provider: .codex)
            plans.ingest([.codex: snapshot])
            let before = try #require(store.cockpitMenuBarRecommendation(
                provider: .codex, snapshot: snapshot, now: now))
            await confirmation { changed in
                withObservationTracking { _ = store.iconObservationToken } onChange: { changed() }
                await resets.refresh()
            }
            let after = try #require(store.cockpitMenuBarRecommendation(
                provider: .codex, snapshot: snapshot, now: now))
            #expect(after.percent > before.percent)
            #expect(after.percent == plans.status(for: .codex, on: now).suggestedPercent)
        }
    }

    @Test
    func `placed daily token and conditional branch schedule updates while an ordinary percent does not`() throws {
        try self.withFixture { store, _, settings in
            settings.mergeIcons = false
            settings.menuBarShowsBrandIconWithPercent = true
            for provider in UsageProvider.allCases {
                if let metadata = ProviderRegistry.shared.metadata[provider] {
                    settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == .claude)
                }
            }
            settings.menuBarLayout = MenuBarLayout(lines: [[.cockpitDailyRecommendation]])
            let controller = StatusItemController(
                store: store,
                settings: settings,
                account: AccountInfo(email: nil, plan: nil),
                updater: DisabledUpdaterController(),
                preferencesSelection: PreferencesSelection(),
                statusBar: testStatusBar())
            defer { controller.releaseStatusItemsForTesting() }
            controller.scheduleMenuBarCountdownRefreshIfNeeded(now: self.now)
            #expect(controller._test_isMenuBarCountdownRefreshScheduled())
            settings.menuBarLayout = MenuBarLayout(lines: [[.percent(window: .automatic)]])
            controller.scheduleMenuBarCountdownRefreshIfNeeded(now: self.now)
            #expect(!controller._test_isMenuBarCountdownRefreshScheduled())
            var conditional = MenuBarLayoutConditional.makeDefault()
            conditional.thenToken = .cockpitDailyRecommendation
            settings.menuBarLayoutConditionals = [conditional]
            settings.menuBarLayout = MenuBarLayout(lines: [[.conditional(id: conditional.id)]])
            controller.scheduleMenuBarCountdownRefreshIfNeeded(now: self.now)
            #expect(controller._test_isMenuBarCountdownRefreshScheduled())
        }
    }

    private func snapshot(
        account: String? = "synthetic-menu-account",
        organization: String = "synthetic-org",
        provider: UsageProvider = .claude,
        minutes: Int = 10080) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: nil,
            secondary: RateWindow(
                usedPercent: 30,
                windowMinutes: minutes,
                resetsAt: self.now.addingTimeInterval(5 * 86400),
                resetDescription: nil),
            updatedAt: self.now,
            identity: account.map { ProviderIdentitySnapshot(
                providerID: provider.instanceID,
                accountEmail: nil,
                accountOrganization: organization,
                loginMethod: nil,
                accountID: $0) })
    }

    private func renderData(
        _ store: UsageStore,
        snapshot: UsageSnapshot?,
        local: Bool = true,
        included: Bool = true,
        now: Date? = nil) -> MenuBarLayoutRenderData
    {
        store.menuBarLayoutRenderData(
            provider: .claude,
            snapshot: snapshot,
            iconKey: "synthetic",
            accountLabel: nil,
            costs: MenuBarLayoutCostValues(today: nil, last30Days: nil, todayUSD: nil, last30DaysUSD: nil),
            includeLocalDerivedData: local,
            includeCockpitRecommendation: included,
            now: now ?? self.now)
    }

    private func withFixture<T>(
        resets: CockpitResetHistoryStore? = nil,
        _ body: (UsageStore, CockpitPlanStore, SettingsStore) throws -> T) throws -> T
    {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, plans, settings) = self.fixture(folder: folder, resets: resets)
        return try body(store, plans, settings)
    }

    private func withFixture<T>(
        resets: CockpitResetHistoryStore? = nil,
        _ body: (UsageStore, CockpitPlanStore, SettingsStore) async throws -> T) async throws -> T
    {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, plans, settings) = self.fixture(folder: folder, resets: resets)
        return try await body(store, plans, settings)
    }

    private func fixture(folder: URL, resets: CockpitResetHistoryStore?)
        -> (UsageStore, CockpitPlanStore, SettingsStore)
    {
        let settings = testSettingsStore(suiteName: "cockpit-menu-recommendation-\(UUID().uuidString)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            historicalUsageHistoryStore: HistoricalUsageHistoryStore(fileURL: folder
                .appendingPathComponent("history.json")),
            planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
            startupBehavior: .testing,
            environmentBase: ["HOME": folder.path, "CODEX_HOME": folder.appendingPathComponent("codex").path],
            pluginApprovalStore: ProviderPluginApprovalStore(fileURL: folder.appendingPathComponent("plugins.json")),
            widgetSnapshotURL: folder.appendingPathComponent("widget.json"),
            cliUsageCacheURL: folder.appendingPathComponent("cli.json"),
            widgetTimelineReloader: {})
        store._test_providerRefreshOverride = { _ in Issue.record("No live provider refresh expected") }
        store._test_widgetSnapshotSaveOverride = { _ in }
        let plans = CockpitPlanStore(fileURL: folder.appendingPathComponent("plan.json"), resetHistoryStore: resets)
        store.cockpitPlanStore = plans
        return (store, plans, settings)
    }
}
