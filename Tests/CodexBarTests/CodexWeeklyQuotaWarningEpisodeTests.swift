import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CodexWeeklyQuotaWarningEpisodeTests {
    private let start = Date(timeIntervalSince1970: 1_900_000_000)
    private let email = "weekly-warning@example.invalid"

    private final class NotifierSpy: SessionQuotaNotifying {
        var warnings: [QuotaWarningEvent] = []

        func post(transition _: SessionQuotaTransition, provider _: UsageProvider, badge _: NSNumber?) {}

        func postQuotaWarning(
            event: QuotaWarningEvent,
            provider: UsageProvider,
            soundEnabled _: Bool,
            onScreenAlertEnabled _: Bool)
        {
            #expect(provider == .codex)
            self.warnings.append(event)
        }
    }

    @Test
    func `fresh quota rebounds cannot repeat a weekly threshold in the same cycle`() async throws {
        try await self.withStore { store, notifier in
            let owner = self.owner(workspace: "synthetic-workspace-a")
            for (step, remaining) in [60.0, 49, 51, 48, 52, 47].enumerated() {
                self.observe(store, remaining: remaining, step: step, owner: owner)
            }
            #expect(notifier.warnings.map(\.threshold) == [50])
            #expect(notifier.warnings.map(\.window) == [.weekly])
        }
    }

    @Test
    func `email only credential rotation cannot repeat the already warned weekly threshold`() async throws {
        try await self.withStore { store, notifier in
            let observations: [(Double, String)] = [
                (60, "fixture-a"), (49, "fixture-a"), (48, "fixture-b"), (47, "fixture-c"),
            ]
            for (step, observation) in observations.enumerated() {
                let owner = CodexAccountScopedRefreshGuard(
                    source: .liveSystem,
                    identity: .emailOnly(normalizedEmail: self.email),
                    accountKey: self.email,
                    authFingerprint: observation.1)
                self.observe(store, remaining: observation.0, step: step, owner: owner)
            }
            #expect(notifier.warnings.map(\.threshold) == [50])
            #expect(notifier.warnings.map(\.window) == [.weekly])
        }
    }

    @Test
    func `a passed weekly reset starts a new threshold episode`() async throws {
        try await self.withStore { store, notifier in
            let owner = self.owner(workspace: "synthetic-workspace-a")
            self.observe(store, remaining: 60, step: 0, owner: owner)
            self.observe(store, remaining: 49, step: 1, owner: owner)
            self.observe(store, remaining: 48, step: 2, owner: owner)
            self.observe(store, remaining: 49, step: 601, owner: owner, resetOffset: 605_400)
            self.observe(store, remaining: 48, step: 602, owner: owner, resetOffset: 605_400)
            #expect(notifier.warnings.map(\.threshold) == [50, 50])
            #expect(notifier.warnings.allSatisfy { $0.window == .weekly })
        }
    }

    @Test
    func `a lower weekly threshold remains eligible within the same cycle`() async throws {
        try await self.withStore { store, notifier in
            let owner = self.owner(workspace: "synthetic-workspace-a")
            for (step, remaining) in [60.0, 49, 48, 19, 18].enumerated() {
                self.observe(store, remaining: remaining, step: step, owner: owner)
            }
            #expect(notifier.warnings.map(\.threshold) == [50, 20])
            #expect(notifier.warnings.allSatisfy { $0.window == .weekly })
        }
    }

    @Test
    func `distinct workspaces sharing an email retain independent weekly warning episodes`() async throws {
        try await self.withStore { store, notifier in
            let ownerA = self.owner(workspace: "synthetic-workspace-a")
            let ownerB = self.owner(workspace: "synthetic-workspace-b")
            let observations: [(CodexAccountScopedRefreshGuard, Double)] = [
                (ownerA, 60), (ownerA, 49), (ownerB, 60), (ownerB, 49), (ownerA, 48), (ownerB, 47),
            ]
            for (step, observation) in observations.enumerated() {
                self.observe(store, remaining: observation.1, step: step, owner: observation.0)
            }
            #expect(notifier.warnings.map(\.threshold) == [50, 50])
            #expect(notifier.warnings.allSatisfy { $0.window == .weekly })
        }
    }

    @Test
    func `already low startup readings at forty four and forty three are quiet baselines`() async throws {
        try await self.withStore { store, notifier in
            let owner = self.owner(workspace: "synthetic-workspace-a")
            for (step, remaining) in [44.0, 43, 43, 19, 18].enumerated() {
                self.observe(store, remaining: remaining, step: step, owner: owner)
            }
            #expect(notifier.warnings.map(\.threshold) == [20])
        }
    }

    @Test
    func `unresolved identity cannot emit or duplicate a weekly warning`() async throws {
        try await self.withStore { store, notifier in
            let unresolved = CodexAccountScopedRefreshGuard(
                source: .liveSystem, identity: .unresolved, accountKey: nil, authFingerprint: nil)
            let resolved = self.owner(workspace: "synthetic-workspace-a")
            self.observe(store, remaining: 44, step: 0, owner: unresolved)
            self.observe(store, remaining: 43, step: 1, owner: resolved)
            self.observe(store, remaining: 43, step: 2, owner: unresolved)
            self.observe(store, remaining: 42, step: 3, owner: resolved)
            #expect(notifier.warnings.isEmpty)
            self.observe(store, remaining: 19, step: 4, owner: resolved)
            #expect(notifier.warnings.map(\.threshold) == [20])
        }
    }

    @Test
    func `weekly thresholds survive reconstruction and provider runtime cleanup`() async throws {
        let defaults = InMemoryUserDefaults()
        let owner = self.owner(workspace: "synthetic-workspace-a")
        try await self.withStore(defaults: defaults) { store, notifier in
            self.observe(store, remaining: 60, step: 0, owner: owner)
            self.observe(store, remaining: 49, step: 1, owner: owner)
            #expect(notifier.warnings.map(\.threshold) == [50])
        }
        let reloaded = InMemoryUserDefaults(values: defaults.dictionaryRepresentation())
        try await self.withStore(defaults: reloaded) { store, notifier in
            self.observe(store, remaining: 44, step: 2, owner: owner)
            store.clearProviderRuntimeState(.codex)
            self.observe(store, remaining: 43, step: 3, owner: owner)
            self.observe(store, remaining: 51, step: 4, owner: owner)
            self.observe(store, remaining: 43, step: 5, owner: owner)
            #expect(notifier.warnings.isEmpty)
            self.observe(store, remaining: 19, step: 6, owner: owner)
            #expect(notifier.warnings.map(\.threshold) == [20])
        }
        let restarted = InMemoryUserDefaults(values: reloaded.dictionaryRepresentation())
        try await self.withStore(defaults: restarted) { store, notifier in
            self.observe(store, remaining: 18, step: 7, owner: owner)
            #expect(notifier.warnings.isEmpty)
            self.observe(store, remaining: 49, step: 601, owner: owner, resetOffset: 605_400)
            self.observe(store, remaining: 48, step: 602, owner: owner, resetOffset: 605_400)
            #expect(notifier.warnings.map(\.threshold) == [50])
        }
    }

    private func owner(workspace: String) -> CodexAccountScopedRefreshGuard {
        CodexAccountScopedRefreshGuard(
            source: .liveSystem,
            identity: .providerAccount(id: workspace),
            accountKey: self.email,
            authFingerprint: "fixture-auth")
    }

    @Test
    func `selected visible accounts without a provable owner cannot emit weekly warnings`() async throws {
        try await self.withStore { store, notifier in
            let account = CodexVisibleAccount(
                id: "live:synthetic-unresolved-owner",
                email: self.email,
                workspaceAccountID: nil,
                authFingerprint: nil,
                storedAccountID: nil,
                selectionSource: .liveSystem,
                isActive: true,
                isLive: true,
                canReauthenticate: false,
                canRemove: false)
            for (step, remaining) in [44.0, 43].enumerated() {
                let snapshot = UsageSnapshot(
                    primary: nil,
                    secondary: RateWindow(
                        usedPercent: 100 - remaining,
                        windowMinutes: 10080,
                        resetsAt: self.start.addingTimeInterval(600),
                        resetDescription: nil),
                    updatedAt: self.start.addingTimeInterval(Double(step)))
                let result = ProviderFetchResult(
                    usage: snapshot,
                    credits: nil,
                    dashboard: nil,
                    sourceLabel: "synthetic",
                    strategyID: "codex.fixture-oauth",
                    strategyKind: .oauth)
                await store.applySelectedCodexVisibleAccountOutcome(
                    ProviderFetchOutcome(result: .success(result), attempts: []),
                    account: account,
                    snapshot: snapshot,
                    sourceLabel: "synthetic",
                    limitResetOwnerKey: nil)
            }
            #expect(notifier.warnings.isEmpty)
        }
    }

    private func observe(
        _ store: UsageStore,
        remaining: Double,
        step: Int,
        owner: CodexAccountScopedRefreshGuard,
        resetOffset: TimeInterval = 600)
    {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: RateWindow(
                usedPercent: 100 - remaining,
                windowMinutes: 10080,
                resetsAt: self.start.addingTimeInterval(resetOffset),
                resetDescription: nil),
            updatedAt: self.start.addingTimeInterval(Double(step)),
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: self.email,
                accountOrganization: nil,
                loginMethod: "synthetic"))
        let result = ProviderFetchResult(
            usage: snapshot,
            credits: nil,
            dashboard: nil,
            sourceLabel: "synthetic",
            strategyID: "codex.fixture-oauth",
            strategyKind: .oauth)
        let context = UsageStore.ProviderRefreshOutcomeContext(
            generation: 0,
            includesCredits: false,
            claudeUsesConsumerAutoPipeline: false,
            codexExpectedGuard: owner,
            tokenAccount: nil,
            priorTokenAccountSnapshot: nil,
            codexLimitResetOwnerKey: nil,
            claudeOAuthHistoryPersistentRefHash: nil,
            claudeOAuthActiveAccountObservation: .stable(identity: nil),
            claudeCredentialFingerprint: nil)
        _ = store.handleProviderRefreshNotifications(
            provider: .codex, result: result, snapshot: snapshot, context: context)
    }

    private func withStore(
        defaults: UserDefaults? = nil,
        _ body: (UsageStore, NotifierSpy) async throws -> Void) async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexWeeklyQuotaWarningEpisodeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = ["HOME": root.path, "CODEX_HOME": root.appendingPathComponent("codex").path]
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults ?? InMemoryUserDefaults())
        settings._test_codexReconciliationEnvironment = environment
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50, 20]
        settings.setQuotaWarningWindowEnabled(.session, enabled: false)
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)
        settings.sessionQuotaNotificationsEnabled = false
        settings.predictivePaceWarningNotificationsEnabled = false
        settings.credentialExpiryNotificationsEnabled = false
        settings.limitResetNotificationsEnabled = false
        settings.showOptionalCreditsAndExtraUsage = false
        settings.setHooksEnabled(false)
        defer { settings.configFileWatcher?.stop() }
        let notifier = NotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(homeDirectory: root.path, cacheTTL: 0),
            settings: settings,
            historicalUsageHistoryStore: HistoricalUsageHistoryStore(fileURL: root.appendingPathComponent("history")),
            planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
            sessionQuotaNotifier: notifier,
            startupBehavior: .testing,
            environmentBase: environment,
            pluginApprovalStore: ProviderPluginApprovalStore(fileURL: root.appendingPathComponent("plugins")),
            widgetSnapshotURL: root.appendingPathComponent("widget"),
            cliUsageCacheURL: root.appendingPathComponent("cli"),
            widgetTimelineReloader: {})
        store._test_providerRefreshOverride = { _ in Issue.record("Unexpected live provider refresh") }
        try await body(store, notifier)
    }
}
