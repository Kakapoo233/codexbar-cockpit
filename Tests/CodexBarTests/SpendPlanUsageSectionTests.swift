import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@MainActor
struct SpendPlanUsageSectionTests {
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
