import Foundation
import Testing
@testable import CodexBarCore

struct ForkSettingsImportTests {
    @Test
    func `explicit import projects only presentation and provider visibility`() throws {
        let upstream = CodexBarConfig(providers: [
            ProviderConfig(id: .claude, enabled: false, source: .oauth, apiKey: "UPSTREAM-SECRET"),
            ProviderConfig(id: .codex, enabled: true, cookieHeader: "UPSTREAM-COOKIE"),
        ])
        let imported = try CockpitSettingsImport(upstreamPreferences: [
            "hidePersonalInfo": true,
            "refreshFrequency": "fiveMinutes",
            "appLanguage": "zh-Hans",
            "apiKey": "DEFAULTS-SECRET",
            "claudeOAuthKeychainPromptMode": "always",
            "iCloudSyncEnabled": true,
            "hooks": "UNSAFE-HOOK",
            "launchAtLogin": true,
        ], upstreamConfigData: upstream.encodedData())

        let document = try #require(String(data: imported.preferences.encoded(), encoding: .utf8))
        #expect(imported.appLanguage == "zh-Hans")
        #expect(imported.importedSettingCount == 5)
        #expect(try imported.preferences.value("hidePersonalInfo", as: Bool.self) == true)
        #expect(!document.contains("SECRET"))
        #expect(!document.contains("iCloud"))
        #expect(!document.contains("hooks"))
        #expect(!document.contains("Keychain"))
        #expect(!document.contains("launchAtLogin"))
        #expect(imported.providerSelection.map(\.id) == [.claude, .codex])
        #expect(imported.providerSelection
            .allSatisfy { $0.apiKey == nil && $0.cookieHeader == nil && $0.source == nil })

        let current = CodexBarConfig(providers: [
            ProviderConfig(id: .codex, enabled: false, apiKey: "EXISTING-FORK-KEY"),
            ProviderConfig(id: .claude, enabled: true, source: .cli),
            ProviderConfig(id: .cursor, enabled: true),
        ])
        let result = imported.applyingProviderSelection(to: current)
        #expect(result.providers.map(\.id) == [.claude, .codex, .cursor])
        #expect(result.providerConfig(for: .codex)?.enabled == true)
        #expect(result.providerConfig(for: .claude)?.enabled == false)
        #expect(result.providerConfig(for: .claude)?.source == .cli)
        #expect(result.providerConfig(for: .codex)?.apiKey == "EXISTING-FORK-KEY")
        let exported = try #require(String(data: result.encodedData(), encoding: .utf8))
        #expect(!exported.contains("UPSTREAM"))
    }

    @Test
    func `missing config preserves configured providers and malformed import throws before writes`() throws {
        let imported = try CockpitSettingsImport(upstreamPreferences: [:])
        let current = CodexBarConfig(providers: [ProviderConfig(id: .codex, enabled: true)])
        #expect(imported.importedSettingCount == 0)
        #expect(try imported.applyingProviderSelection(to: current).encodedData() == current.encodedData())
        #expect(throws: (any Error).self) {
            try CockpitSettingsImport(upstreamPreferences: ["refreshFrequency": "invalid-frequency"])
        }
        #expect(throws: (any Error).self) {
            try CockpitSettingsImport(upstreamPreferences: [:], upstreamConfigData: Data("invalid-json".utf8))
        }
    }
}
