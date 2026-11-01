import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@MainActor
struct SpendPlanUsageSectionTests {
    @Test
    func `new quota samples follow the current clock while cost tracking is disabled`() throws {
        let settings = testSettingsStore(
            suiteName: "SpendPlanUsageCurrentClock",
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        defer { settings.configFileWatcher?.stop() }
        settings.costUsageEnabled = false
        enableTestProviders([.antigravity], settings: settings)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
            startupBehavior: .testing,
            environmentBase: [:])
        let initial = try #require(ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z"))
        let clock = LockIsolated(initial)
        let controller = SpendDashboardController(
            userDefaults: InMemoryUserDefaults(),
            requestBuilder: { _ in fatalError("Disabled cost tracking must not load a provider") },
            nowProvider: { clock.value })
        store.sharedSpendDashboardControllerStorage = controller
        defer { store.stopSharedSpendDashboardPublication() }
        controller.update(configuration: SpendDashboardConfiguration(
            costUsageEnabled: false,
            providerIDs: ["antigravity"],
            codexAccountIdentities: [],
            bucketTimeZoneIdentifier: "UTC"))
        controller.refreshDateWindow(now: initial)
        controller.selectPeriod(.rolling(days: 7))
        clock.setValue(initial.addingTimeInterval(2))
        let entries = [0.0, 1.0, 3.0].map { seconds in
            PlanUtilizationHistoryEntry(
                capturedAt: initial.addingTimeInterval(seconds), usedPercent: seconds, resetsAt: nil)
        }
        store.planUtilizationHistory[.antigravity] = PlanUtilizationHistoryBuckets(unscoped: [
            PlanUtilizationSeriesHistory(name: .antigravityGemini, windowMinutes: 0, entries: entries),
        ])
        store.planUtilizationHistoryRevision &+= 1
        let displayed = SpendPlanUsageSection(store: store).displayedHistories(for: .antigravity)
        #expect(displayed.first?.entries == Array(entries.prefix(2)))
        #expect(!controller.isRefreshing)
    }

    @Test
    func `quota history remains available without cost tracking and follows enabled providers`() {
        let settings = testSettingsStore(
            suiteName: "SpendPlanUsageSectionTests",
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        defer { settings.configFileWatcher?.stop() }
        settings.costUsageEnabled = false
        settings.historicalTrackingEnabled = false
        enableTestProviders([.codex], settings: settings)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
            startupBehavior: .testing,
            environmentBase: [:])
        let section = SpendPlanUsageSection(store: store)
        #expect(section.providers.contains(.codex))
        #expect(!section.providers.contains(.claude))
        #expect(!settings.costUsageEnabled)
        settings.setProviderEnabled(
            provider: .codex, metadata: ProviderDescriptorRegistry.descriptor(for: .codex).metadata, enabled: false)
        #expect(!section.providers.contains(.codex))
    }

    @Test
    func `history publication invalidates an already displayed quota section`() {
        let settings = testSettingsStore(
            suiteName: "SpendPlanUsageSectionObservation",
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        defer { settings.configFileWatcher?.stop() }
        enableTestProviders([.codex], settings: settings)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
            startupBehavior: .testing,
            environmentBase: [:])
        let section = SpendPlanUsageSection(store: store)
        let changed = LockIsolated(false)
        withObservationTracking {
            _ = section.providers
        } onChange: {
            changed.setValue(true)
        }

        #expect(!changed.value)
        store.planUtilizationHistoryRevision &+= 1
        #expect(changed.value)
        #expect(section.providers.contains(.codex))
    }
}
