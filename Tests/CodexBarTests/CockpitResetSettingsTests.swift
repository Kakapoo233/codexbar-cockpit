import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@MainActor
struct CockpitResetSettingsTests {
    @Test
    func `forecast notices default on and preserve an explicit opt out after reload`() {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(settings.cockpitResetForecastNotificationsEnabled)

        settings.cockpitResetForecastNotificationsEnabled = false
        #expect(defaults.object(forKey: "cockpitResetForecastNotificationsEnabled") as? Bool == false)
        let reloaded = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(!reloaded.cockpitResetForecastNotificationsEnabled)

        reloaded.cockpitResetForecastNotificationsEnabled = true
        #expect(testSettingsStore(suiteName: #function, userDefaults: defaults)
            .cockpitResetForecastNotificationsEnabled)
    }

    @Test
    func `forecast notice changes participate in observation`() {
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        let change = ObservationChangeFlag()
        withObservationTracking {
            _ = settings.cockpitResetForecastNotificationsEnabled
        } onChange: {
            change.record()
        }
        settings.cockpitResetForecastNotificationsEnabled = false
        #expect(change.didChange)
    }

    @Test(arguments: [false, true])
    func `forecast notice preference survives portable export and import`(enabled: Bool) throws {
        let source = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        source.cockpitResetForecastNotificationsEnabled = enabled
        let target = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        target.cockpitResetForecastNotificationsEnabled = !enabled

        let document = try PreferencesDocument(data: source.exportPreferences().encoded())
        #expect(try document.value("cockpitResetForecastNotificationsEnabled", as: Bool.self) == enabled)
        try target.importPreferences(document)
        #expect(target.cockpitResetForecastNotificationsEnabled == enabled)
    }

    @Test
    func `older preference documents leave the forecast notice choice intact`() throws {
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        settings.cockpitResetForecastNotificationsEnabled = false
        try settings.importPreferences(PreferencesDocument())
        #expect(!settings.cockpitResetForecastNotificationsEnabled)
    }
}

private final class ObservationChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false

    var didChange: Bool {
        self.lock.withLock { self.changed }
    }

    func record() {
        self.lock.withLock { self.changed = true }
    }
}
