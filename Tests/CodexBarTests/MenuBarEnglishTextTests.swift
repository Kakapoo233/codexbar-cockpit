import CodexBarCore
import Foundation
import Observation
import os
import Testing
@testable import CodexBar

@MainActor
struct MenuBarEnglishTextTests {
    @Test
    func `English menu bar choice defaults off and persists independently of app language`() {
        let defaults = InMemoryUserDefaults()
        defaults.set("zh-Hans", forKey: "appLanguage")
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(!settings.menuBarEnglishText)
        settings.menuBarEnglishText = true
        let reloaded = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(reloaded.menuBarEnglishText)
        #expect(reloaded.appLanguage == "zh-Hans")
        reloaded.menuBarEnglishText = false
        #expect(!testSettingsStore(suiteName: #function, userDefaults: defaults).menuBarEnglishText)
        #expect(defaults.string(forKey: "appLanguage") == "zh-Hans")
    }

    @Test
    func `changing the English choice invalidates menu bar observation`() {
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = settings.menuObservationToken
        } onChange: {
            changed.withLock { $0 = true }
        }
        settings.menuBarEnglishText = true
        #expect(changed.withLock { $0 })
    }

    @Test(arguments: [false, true])
    func `English choice survives app and CLI portable preferences`(enabled: Bool) throws {
        let defaults = InMemoryUserDefaults()
        let source = testSettingsStore(suiteName: #function, userDefaults: defaults)
        source.menuBarEnglishText = enabled
        for document in try [source.exportPreferences(), PreferencesDocument(defaults: defaults)] {
            let target = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
            target.menuBarEnglishText = !enabled
            try target.importPreferences(PreferencesDocument(data: document.encoded()))
            #expect(target.menuBarEnglishText == enabled)
            try target.importPreferences(PreferencesDocument())
            #expect(target.menuBarEnglishText == enabled)
        }
    }

    @Test(arguments: ["zh-Hans", "ar", "ja"])
    func `top bar override restores panel language even after a rendering error`(language: String) {
        CodexBarLocalizationOverride.$appLanguage.withValue(language) {
            let panelTitle = L("cockpit_ui_calendar")
            #expect(MenuBarTextLanguage.withEnglish(enabled: false) { L("cockpit_ui_calendar") } == panelTitle)
            let english = MenuBarTextLanguage.withEnglish(enabled: true) {
                #expect(codexBarLocalizationSignature() == "en")
                #expect(codexBarLocalizedLayoutDirection() == .leftToRight)
                return L("cockpit_ui_calendar")
            }
            #expect(english == L("cockpit_ui_calendar", language: "en"))
            #expect(english != panelTitle)
            #expect(throws: RenderFailure.self) {
                try MenuBarTextLanguage.withEnglish(enabled: true) { throw RenderFailure.synthetic }
            }
            #expect(codexBarLocalizationSignature() == language)
            #expect(L("cockpit_ui_calendar") == panelTitle)
        }
    }

    @Test
    func `layout cache never reuses accessibility text from a different language`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let renderer = MenuBarLayoutRenderer()
            let fixture = MenuBarLayoutRendererTests()
            let data = fixture.data()
            let options = fixture.options(showWindowLabels: false)
            let layout = MenuBarLayout(lines: [[.percent(window: .weekly)]])
            let original = renderer.render(layout: layout, data: data, icon: nil, options: options)
            let english = MenuBarTextLanguage.withEnglish(enabled: true) {
                renderer.render(layout: layout, data: data, icon: nil, options: options)
            }
            #expect(original.attributedTitle.string == english.attributedTitle.string)
            #expect(original.accessibilityLabel != english.accessibilityLabel)
            #expect(english.accessibilityLabel.contains("Weekly"))
            let restored = renderer.render(layout: layout, data: data, icon: nil, options: options)
            #expect(restored.accessibilityLabel == original.accessibilityLabel)
            #expect(restored.attributedTitle === original.attributedTitle)
        }
    }

    private enum RenderFailure: Error { case synthetic }
}
