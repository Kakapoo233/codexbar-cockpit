import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct MenuBarLayoutCockpitV7PersistenceTests {
    private static let layout = MenuBarLayout(lines: [[.icon, .cockpitDailyRecommendation, .spendBudget]])

    @Test
    func `saving recommendation writes a new generation and a strict V6 readable projection`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        settings.setMenuBarLayout(Self.layout, for: nil)
        settings.setMenuBarLayout(Self.layout, for: .codex)
        let decoder = JSONDecoder()
        let current = try #require(defaults.data(forKey: "menuBarLayoutCockpitV7"))
        let v6 = try #require(defaults.data(forKey: "menuBarLayoutV6"))
        #expect(try decoder.decode(MenuBarLayout.self, from: current) == Self.layout)
        #expect(try decoder.decode(FrozenV6Layout.self, from: v6).lines == [[.icon, .spendBudget]])
        #expect(throws: DecodingError.self) { try decoder.decode(FrozenV6Layout.self, from: current) }
        let overrides = try #require(defaults.data(forKey: "menuBarLayoutOverridesV6"))
        #expect(try decoder.decode([String: FrozenV6Layout].self, from: overrides)["codex"]?.lines
            == [[.icon, .spendBudget]])
        let reloaded = testSettingsStore(suiteName: "v7-restored", userDefaults: defaults)
        #expect(reloaded.menuBarLayout == Self.layout)
        #expect(reloaded.menuBarLayoutOverrides[.codex] == Self.layout)
    }

    @Test
    func `a V6 only install upgrades without replacing its saved layout or provider overrides`() throws {
        let defaults = InMemoryUserDefaults()
        let previous = MenuBarLayout(lines: [[.icon, .spendBudget]])
        try defaults.set(JSONEncoder().encode(previous), forKey: "menuBarLayoutV6")
        try defaults.set(JSONEncoder().encode(["claude": previous]), forKey: "menuBarLayoutOverridesV6")
        try defaults.set(
            JSONEncoder().encode([MenuBarLayoutConditional.makeDefault()]),
            forKey: "menuBarLayoutConditionalsV6")
        let loaded = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(loaded.menuBarLayout == previous)
        #expect(loaded.menuBarLayoutOverrides[.claude] == previous)
        #expect(defaults.data(forKey: "menuBarLayoutCockpitV7") != nil)
        #expect(defaults.data(forKey: "menuBarLayoutOverridesCockpitV7") != nil)
        #expect(defaults.data(forKey: "menuBarLayoutConditionalsCockpitV7") != nil)
        #expect(testSettingsStore(suiteName: "upgrade-restored", userDefaults: defaults).menuBarLayout == previous)
    }

    @Test
    func `older edits win while untouched provider recommendation layouts survive`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        settings.setMenuBarLayout(Self.layout, for: nil)
        settings.setMenuBarLayout(Self.layout, for: .codex)
        settings.setMenuBarLayout(Self.layout, for: .claude)
        let edited = MenuBarLayout(lines: [[.icon, .costToday]])
        try Self.writeV6(MenuBarLayoutPersistence.encoded(edited), kind: "menuBarLayout", to: defaults)
        try Self.writeV6(
            MenuBarLayoutPersistence.encodedOverrides(["codex": Self.layout.v6Compatible(), "claude": edited]),
            kind: "menuBarLayoutOverrides",
            to: defaults)
        let reloaded = testSettingsStore(suiteName: "after-v6-edit", userDefaults: defaults)
        #expect(reloaded.menuBarLayout == edited)
        #expect(reloaded.menuBarLayoutOverrides[.claude] == edited)
        #expect(reloaded.menuBarLayoutOverrides[.codex] == Self.layout)
    }

    @Test
    func `older library edits preserve invisible recommendation rules and an explicit clear still wins`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        let visible = MenuBarLayoutConditional.makeDefault()
        let recommendation = MenuBarLayoutConditional(
            clauses: visible.clauses,
            thenToken: .cockpitDailyRecommendation,
            elseToken: .hidden)
        settings.menuBarLayoutConditionals = [visible, recommendation]
        var edited = visible
        edited.name = "Edited in V6"
        try Self.writeV6(
            MenuBarLayoutPersistence.encodedLibrary([edited]), kind: "menuBarLayoutConditionals", to: defaults)
        let reloaded = testSettingsStore(suiteName: "after-v6-library-edit", userDefaults: defaults)
        #expect(reloaded.menuBarLayoutConditionals == [edited, recommendation])
        try Self.writeV6(
            MenuBarLayoutPersistence.encodedLibrary([]), kind: "menuBarLayoutConditionals", to: defaults)
        #expect(testSettingsStore(suiteName: "after-v6-library-clear", userDefaults: defaults)
            .menuBarLayoutConditionals.isEmpty)
    }

    private static func writeV6(
        _ blobs: MenuBarLayoutPersistence.EncodedGenerations,
        kind: String,
        to defaults: UserDefaults)
    {
        for (suffix, blob) in [
            ("V6", blobs.v6), ("V5", blobs.v5), ("V4", blobs.v4),
            ("V3", blobs.v3), ("V2", blobs.released), ("", blobs.legacy),
        ] {
            defaults.set(blob, forKey: kind + suffix)
        }
    }
}

/// Frozen subset of the strict 0.8.6 decoder used by the fixture; the new case is intentionally absent.
private struct FrozenV6Layout: Decodable {
    let lines: [[FrozenV6Token]]
}

private enum FrozenV6Token: Decodable, Equatable {
    case icon
    case spendBudget
}
