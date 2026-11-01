import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct MenuBarLayoutCockpitV8PersistenceTests {
    @Test(arguments: CockpitDailyRemainingStyle.allCases)
    func `remaining styles persist with older readable projections`(style: CockpitDailyRemainingStyle) throws {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        let layout = MenuBarLayout(lines: [[.icon, .cockpitDailyRecommendation, .cockpitDailyRemaining(style: style)]])
        settings.setMenuBarLayout(layout, for: nil)
        settings.setMenuBarLayout(layout, for: .claude)
        let blobs = try MenuBarLayoutPersistence.encoded(layout)
        let decoder = JSONDecoder()
        #expect(try decoder.decode(MenuBarLayout.self, from: blobs.current) == layout)
        #expect(try decoder.decode(MenuBarLayout.self, from: blobs.v7)
            == .init(lines: [[.icon, .cockpitDailyRecommendation]]))
        for blob in [blobs.v7, blobs.v6, blobs.v5, blobs.v4, blobs.v3, blobs.released, blobs.legacy] {
            let text = try #require(String(data: blob, encoding: .utf8))
            #expect(!text.contains("cockpitDailyRemaining"))
        }
        let restored = testSettingsStore(suiteName: "restored-v8", userDefaults: defaults)
        #expect(restored.menuBarLayout == layout)
        #expect(restored.menuBarLayoutOverrides[.claude] == layout)
    }

    @Test
    func `V7 upgrade and older edits retain their established priority`() throws {
        let defaults = InMemoryUserDefaults()
        let previous = MenuBarLayout(lines: [[.icon, .cockpitDailyRecommendation]])
        try defaults.set(JSONEncoder().encode(previous), forKey: "menuBarLayoutCockpitV7")
        let upgraded = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(upgraded.menuBarLayout == previous)
        #expect(defaults.data(forKey: "menuBarLayoutCockpitV8") != nil)
        let current = MenuBarLayout(lines: [[.icon, .cockpitDailyRemaining(style: .circle)]])
        let older = MenuBarLayout(lines: [[.icon, .costToday]])
        #expect(MenuBarLayoutPersistence.preferredLayout(current: current, v7: older, legacy: nil) == older)
        #expect(MenuBarLayoutPersistence.preferredLayout(current: current, v7: current.v7Compatible(), legacy: nil)
            == current)
    }
}
