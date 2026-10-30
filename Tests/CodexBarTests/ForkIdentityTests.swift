import Foundation
import Testing
@testable import CodexBarCore

struct ForkIdentityTests {
    @Test
    func `fork config does not discover upstream settings or inherited override`() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("fork-identity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let upstream = home.appendingPathComponent(".config/codexbar/config.json")
        try FileManager.default.createDirectory(
            at: upstream.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("UPSTREAM-SENTINEL".utf8).write(to: upstream)
        let upstreamLegacy = home.appendingPathComponent(".codexbar/config.json")
        try FileManager.default.createDirectory(
            at: upstreamLegacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("LEGACY-SENTINEL".utf8).write(to: upstreamLegacy)

        let actual = CodexBarConfigStore.defaultURL(
            home: home,
            environment: ["CODEXBAR_CONFIG": upstream.path])

        #expect(actual == CockpitAppIdentity.configDirectory(home: home).appendingPathComponent("config.json"))
        #expect(!FileManager.default.fileExists(atPath: actual.path))
        #expect(try Data(contentsOf: upstream) == Data("UPSTREAM-SENTINEL".utf8))
        #expect(try Data(contentsOf: upstreamLegacy) == Data("LEGACY-SENTINEL".utf8))
    }

    @Test
    func `fork storage and credential namespaces are separate from upstream`() {
        let home = URL(fileURLWithPath: "/synthetic-home", isDirectory: true)
        #expect(CockpitAppIdentity.applicationSupportDirectory(home: home).path
            == "/synthetic-home/Library/Application Support/CodexBar Cockpit")
        #expect(CockpitAppIdentity.cacheDirectory(home: home).path
            == "/synthetic-home/Library/Caches/CodexBar Cockpit")
        #expect(CockpitAppIdentity.keychainService != "com.steipete.CodexBar")
        #expect(CockpitAppIdentity.keychainCacheService != "com.steipete.codexbar.cache")
        #expect(PreferencesDocument.defaultsDomain == CockpitAppIdentity.bundleIdentifier)
        #expect(AppGroupSupport.currentGroupID(teamID: "TESTTEAM01", bundleID: CockpitAppIdentity.bundleIdentifier)
            == "TESTTEAM01.\(CockpitAppIdentity.bundleIdentifier)")
        #expect(!AppGroupSupport.legacyGroupID().contains("steipete"))
    }
}
