import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitRecommendationPaceIntegrationTests {
    private let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)

    @Test
    func `layout text metrics and card share daily recommendation while quota forecast stays independent`() throws {
        try self.withFixture { store, plans, settings in
            let snapshot = self.ingestDay(plans)
            let pace = try #require(store.cockpitRecommendationPace(
                provider: .codex,
                snapshot: snapshot,
                now: self.now))
            #expect(!pace.isLowerBound)
            #expect(pace.suggestedPercent == plans.status(for: .codex, on: self.now).suggestedPercent)
            let rendered = self.render(store, snapshot: snapshot)
            #expect(rendered.weeklyPace == CockpitRecommendationPaceText.menuBarText(pace: pace))
            #expect(rendered.metrics.weeklyPaceDelta == pace.deltaPercent.rounded())
            let weekly = try #require(snapshot.secondary)
            let official = store.weeklyPace(
                provider: .codex, window: weekly, dataConfidence: .unknown, now: self.now)
            #expect(rendered.metrics.runsOutMinutes == official.flatMap(\.etaSeconds).map { Int(($0 / 60).rounded()) })
            store._setSnapshotForTesting(snapshot, provider: .codex)
            let input = store.menuCardInput(for: .codex, context: .menu, now: self.now)
            #expect(input.usesCockpitRecommendationPace)
            #expect(input.cockpitRecommendationPace == pace)
            let remote = store.menuCardInput(
                for: .codex,
                context: .account(.init(snapshot: snapshot, allowsLocalCockpitPlan: false)),
                now: self.now)
            #expect(!remote.usesCockpitRecommendationPace)
            #expect(remote.cockpitRecommendationPace == nil)
            settings.menuBarPaceReservePositive = true
            #expect(self.render(store, snapshot: snapshot).weeklyPace ==
                CockpitRecommendationPaceText.menuBarText(pace: pace, reservePositive: true))
            #expect(self.render(store, snapshot: snapshot).metrics.weeklyPaceDelta == pace.deltaPercent.rounded())
        }
    }

    @Test
    func `partial observations show a bound and cannot drive exact numeric rules`() throws {
        try self.withFixture { store, plans, _ in
            let snapshot = self.ingestDay(plans, complete: false)
            let pace = try #require(store.cockpitRecommendationPace(
                provider: .codex,
                snapshot: snapshot,
                now: self.now))
            #expect(pace.isLowerBound)
            let rendered = self.render(store, snapshot: snapshot)
            #expect(rendered.weeklyPace?.hasPrefix("≥") == true)
            #expect(rendered.metrics.weeklyPaceDelta == nil)
            #expect(self.render(store, snapshot: snapshot, local: false).weeklyPace == nil)
        }
    }

    @Test
    func `new accounts organizations cycles and stale or pending observations never borrow another plan`() throws {
        try self.withFixture { store, plans, _ in
            let snapshot = self.ingestDay(plans)
            for mismatch in [
                self.snapshot(used: 50, at: self.now, owner: "another"),
                self.snapshot(used: 50, at: self.now, organization: "another"),
                self.snapshot(used: 50, at: self.now, resetOffset: 6 * 86400),
                self.snapshot(used: 55, at: self.now),
            ] {
                #expect(store.cockpitRecommendationPace(provider: .codex, snapshot: mismatch, now: self.now) == nil)
                #expect(self.render(store, snapshot: mismatch).weeklyPace == nil)
            }
            #expect(store.cockpitRecommendationPace(
                provider: .codex, snapshot: snapshot, now: self.now.addingTimeInterval(1801)) == nil)
            #expect(store.cockpitRecommendationPace(provider: .claude, snapshot: snapshot, now: self.now) == nil)
            #expect(!store.usesCockpitRecommendationPace(
                provider: .codex, window: snapshot.primary, snapshot: snapshot))
            let otherPool = RateWindow(
                usedPercent: 80, windowMinutes: 10080, resetsAt: snapshot.secondary?.resetsAt, resetDescription: nil)
            #expect(!store.usesCockpitRecommendationPace(
                provider: .codex, window: otherPool, snapshot: snapshot))
        }
    }

    @Test
    func `time and comfort curve update daily pace without rewriting manual cap`() throws {
        try self.withFixture { store, plans, _ in
            let snapshot = self.ingestDay(plans)
            let before = try #require(store.cockpitRecommendationPace(
                provider: .codex,
                snapshot: snapshot,
                now: self.now))
            plans.setPersonalCap(1, for: .codex)
            #expect(store.cockpitRecommendationPace(provider: .codex, snapshot: snapshot, now: self.now) == before)
            let later = try #require(store.cockpitRecommendationPace(
                provider: .codex, snapshot: snapshot, now: self.now.addingTimeInterval(60)))
            #expect(later.expectedUsedPercent > before.expectedUsedPercent)
            #expect(later.deltaPercent < before.deltaPercent)
            #expect(MenuBarLayoutToken.pace(window: .weekly).readsCockpitPlan)
            #expect(MenuBarLayoutToken.pace(window: .automatic).readsCockpitPlan)
        }
    }

    @Test
    func `legacy display uses the same comparison and never falls back to old weekly pace`() throws {
        try self.withFixture { store, plans, _ in
            let snapshot = self.ingestDay(plans)
            let pace = try #require(store.cockpitRecommendationPace(
                provider: .codex,
                snapshot: snapshot,
                now: self.now))
            let official = try UsagePace.weekly(window: #require(snapshot.secondary), now: self.now)
            let text = MenuBarDisplayText.displayText(
                mode: .pace,
                percentWindow: snapshot.secondary,
                pace: official,
                recommendationPace: pace,
                usesRecommendationPace: true,
                showUsed: true)
            #expect(text == self.render(store, snapshot: snapshot).weeklyPace)
            let missing = MenuBarDisplayText.displayText(
                mode: .both,
                percentWindow: snapshot.secondary,
                pace: official,
                usesRecommendationPace: true,
                showUsed: true)
            #expect(missing == "50%")
        }
    }

    private func ingestDay(_ plans: CockpitPlanStore, complete: Bool = true) -> UsageSnapshot {
        let start = Calendar.current.startOfDay(for: self.now)
        if complete {
            let count = Int(self.now.timeIntervalSince(start) / 1800)
            for index in 0...count {
                plans.ingest([.codex: self.snapshot(
                    used: 40 + 10 * Double(index) / Double(count),
                    at: start.addingTimeInterval(Double(index) * 1800))])
            }
        } else {
            plans.ingest([.codex: self.snapshot(used: 40, at: self.now.addingTimeInterval(-60))])
        }
        let snapshot = self.snapshot(used: 50, at: self.now)
        plans.ingest([.codex: snapshot])
        return snapshot
    }

    private func snapshot(
        used: Double,
        at date: Date,
        owner: String = "synthetic-owner",
        organization: String = "synthetic-org",
        resetOffset: Double = 5 * 86400) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: 10,
                windowMinutes: 300,
                resetsAt: self.now.addingTimeInterval(7200),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: used,
                windowMinutes: 10080,
                resetsAt: self.now.addingTimeInterval(resetOffset),
                resetDescription: nil),
            updatedAt: date,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: nil,
                accountOrganization: organization,
                loginMethod: nil,
                accountID: owner))
    }

    private func render(_ store: UsageStore, snapshot: UsageSnapshot, local: Bool = true) -> MenuBarLayoutRenderData {
        store.menuBarLayoutRenderData(
            provider: .codex,
            snapshot: snapshot,
            iconKey: "synthetic",
            accountLabel: nil,
            costs: MenuBarLayoutCostValues(today: nil, last30Days: nil, todayUSD: nil, last30DaysUSD: nil),
            includeLocalDerivedData: local,
            now: self.now)
    }

    private func withFixture(_ body: (UsageStore, CockpitPlanStore, SettingsStore) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = testSettingsStore(suiteName: "recommendation-pace-\(UUID().uuidString)")
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
        let plans = CockpitPlanStore(fileURL: folder.appendingPathComponent("plan.json"))
        store.cockpitPlanStore = plans
        try body(store, plans, settings)
    }
}
