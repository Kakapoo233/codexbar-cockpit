import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ICloudDriveSettingsTests {
    @Test
    func `Drive projection excludes credentials local permissions and synchronization controls`() throws {
        let store = self.fixture(config: CodexBarConfig(providers: [
            ProviderConfig(id: .codex, enabled: true, apiKey: "SYNTHETIC-SECRET", cookieHeader: "SYNTHETIC-COOKIE"),
        ]))
        store.iCloudSyncEnabled = true
        store.iCloudSyncIncludeSecrets = true
        store.adaptiveActivityScanConsent = .allowed
        let values = try store.driveSyncSettingsValues()
        let text = values.values.compactMap { String(data: $0, encoding: .utf8) }.joined()
        #expect(!text.contains("SYNTHETIC-SECRET"))
        #expect(!text.contains("SYNTHETIC-COOKIE"))
        #expect(!values.keys.contains { $0.contains("iCloud") || $0.contains("Consent") || $0.contains("apiKey") })
        #expect(values["settings.preferences.refreshFrequency"] != nil)
        #expect(values["settings.menuBarLayout"] != nil)
        #expect(try values == store.driveSyncSettingsValues())
    }

    @Test
    func `Drive settings and dependent layouts round trip and remain persisted`() throws {
        let source = self.fixture()
        source.hidePersonalInfo = true
        source.preferredCurrencyCode = "EUR"
        source.refreshFrequency = .thirtyMinutes
        source.weeklyProgressWorkDays = 4
        source.menuBarEnglishText = true
        source.menuBarLayoutSize = .large
        source.menuBarLayoutGap = .tight
        source.menuBarLayoutVerticalAdjustment = 3
        var conditional = MenuBarLayoutConditional.makeDefault()
        conditional.name = "Synthetic remaining rule"
        conditional.thenToken = .cockpitDailyRemaining(style: .circle)
        source.menuBarLayoutConditionals = [conditional]
        source.menuBarLayout = MenuBarLayout(lines: [[.icon, .conditional(id: conditional.id)]])
        let providerLayout = MenuBarLayout(lines: [[.cockpitDailyRemaining(style: .bar)]])
        source.setMenuBarLayout(providerLayout, for: .codex)
        let values = try source.driveSyncSettingsValues()

        let defaults = InMemoryUserDefaults()
        let target = testSettingsStore(suiteName: #function, userDefaults: defaults)
        target.setMenuBarLayout(.init(lines: [[.costToday]]), for: .claude)
        try target.applyDriveSyncSettingsValues(values)
        #expect(target.hidePersonalInfo)
        #expect(target.preferredCurrencyCode == "EUR")
        #expect(target.refreshFrequency == .thirtyMinutes)
        #expect(target.weeklyProgressWorkDays == 4)
        #expect(target.menuBarEnglishText)
        #expect(target.menuBarLayout == source.menuBarLayout)
        #expect(target.menuBarLayoutConditionals == [conditional])
        #expect(target.menuBarLayoutOverrides[.codex] == providerLayout)
        #expect(target.menuBarLayoutOverrides[.claude] == nil)
        #expect(target.menuBarLayoutSize == .large)
        #expect(target.menuBarLayoutGap == .tight)
        #expect(target.menuBarLayoutVerticalAdjustment == 3)
        #expect(try target.driveSyncSettingsValues() == values)

        let restored = testSettingsStore(suiteName: "drive-restored", userDefaults: defaults)
        #expect(restored.hidePersonalInfo)
        #expect(restored.refreshFrequency == .thirtyMinutes)
        #expect(restored.menuBarLayout == source.menuBarLayout)
        #expect(restored.menuBarLayoutConditionals == [conditional])
    }

    @Test
    func `invalid known fields prevent every other incoming change`() throws {
        let store = self.fixture()
        store.hidePersonalInfo = false
        let before = try store.driveSyncSettingsValues()
        for invalid in [
            ["settings.appLanguage": Data("\"unsupported-language\"".utf8)],
            ["settings.menuBarEnglishText": Data("7".utf8)],
            ["settings.preferences.refreshFrequency": Data("\"invalid-frequency\"".utf8)],
            ["settings.preferences.weeklyProgressWorkDays": Data("20".utf8)],
        ] {
            var incoming = invalid
            incoming["settings.preferences.hidePersonalInfo"] = Data("true".utf8)
            #expect(throws: (any Error).self) { try store.applyDriveSyncSettingsValues(incoming) }
            #expect(try store.driveSyncSettingsValues() == before)
        }
    }

    @Test
    func `unknown fields do not change credentials or machine specific consent`() throws {
        let config = CodexBarConfig(providers: [ProviderConfig(id: .codex, enabled: true, apiKey: "LOCAL-KEY")])
        let store = self.fixture(config: config)
        store.adaptiveActivityScanConsent = .declined
        store.iCloudSyncEnabled = false
        let unknown: [String: Data] = [
            "settings.preferences.apiKey": Data("\"REMOTE-KEY\"".utf8),
            "settings.preferences.adaptiveActivityScanConsent": Data("\"allowed\"".utf8),
            "settings.iCloudSyncEnabled": Data("true".utf8),
            "settings.futurePresentationField": Data("future".utf8),
            "plan.cap.synthetic": Data("not-settings".utf8),
        ]
        try store.validateDriveSyncSettingsValues(unknown)
        try store.applyDriveSyncSettingsValues(unknown)
        #expect(store.adaptiveActivityScanConsent == .declined)
        #expect(!store.iCloudSyncEnabled)
        #expect(store.configSnapshot.providerConfig(for: .codex)?.apiKey == "LOCAL-KEY")

        try store.applyDriveSyncSettingsValues([
            "settings.preferences.refreshFrequency": Data("\"adaptiveAgentAware\"".utf8),
        ])
        #expect(store.refreshFrequency == .adaptiveAgentAware)
        #expect(store.adaptiveActivityScanConsent == .declined)
        #expect(!store.adaptiveActivityScanningEnabled)
    }

    @Test
    func `invalid layout references and oversized values cannot partially apply`() throws {
        let source = self.fixture()
        let valid = try source.driveSyncSettingsValues()
        let data = try #require(valid["settings.menuBarLayout"])
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["size"] = "unknown-size"
        let badSize = try JSONSerialization.data(withJSONObject: object)
        object["size"] = "regular"
        object["global"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            MenuBarLayout(lines: [[.conditional(id: UUID())]])))
        let dangling = try JSONSerialization.data(withJSONObject: object)
        for invalid in [badSize, dangling, Data(repeating: 32, count: 256 * 1024 + 1)] {
            #expect(throws: (any Error).self) {
                try source.applyDriveSyncSettingsValues([
                    "settings.menuBarLayout": invalid,
                    "settings.preferences.hidePersonalInfo": Data("true".utf8),
                ])
            }
            #expect(try source.driveSyncSettingsValues() == valid)
        }
    }

    @Test
    func `an explicit nil weekday preference round trips as a value`() throws {
        let source = self.fixture()
        source.weeklyProgressWorkDays = nil
        let target = self.fixture()
        target.weeklyProgressWorkDays = 5
        try target.applyDriveSyncSettingsValues(source.driveSyncSettingsValues())
        #expect(target.weeklyProgressWorkDays == nil)
    }

    private func fixture(config: CodexBarConfig? = nil) -> SettingsStore {
        testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults(), config: config)
    }
}
