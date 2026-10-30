import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized, CodexCredentialFixtures())
struct CockpitStatusItemPanelTests {
    @Test(arguments: [false, true])
    func `first presentation binds legacy actions to the selected Claude provider`(merged: Bool) throws {
        let controller = self.makeController(merged: merged)
        defer { controller.releaseStatusItemsForTesting() }
        controller.settings.selectedMenuProvider = .claude
        controller.settings.mergedMenuLastSelectedWasOverview = false
        let menu = try #require(controller.cockpitBackingMenu(provider: merged ? nil : .claude))
        controller.lastMenuProvider = nil

        #expect(controller.resolveProviderForMenuPresentation(menu) == .claude)
        #expect(controller.lastMenuProvider == .claude)
        #expect(controller.openMenus.isEmpty)
        if merged {
            #expect(controller.statusItem.menu == nil)
            #expect(controller.statusItem.button?.action == #selector(StatusItemController.toggleCockpitPanel(_:)))
        } else {
            #expect(controller.statusItems[.claude]?.menu == nil)
            #expect(controller.statusItems[.claude]?.button?.action ==
                #selector(StatusItemController.toggleCockpitPanel(_:)))
        }
    }

    @Test
    func `fallback presentation clears the previous provider action context`() throws {
        let controller = self.makeController(merged: false)
        defer { controller.releaseStatusItemsForTesting() }
        let menu = try #require(controller.cockpitBackingMenu(provider: nil))
        controller.lastMenuProvider = .gemini
        #expect(controller.resolveProviderForMenuPresentation(menu) == nil)
        #expect(controller.lastMenuProvider == controller.store.enabledProvidersForDisplay().first)
    }

    @Test
    func `provider selection rebuilds panel data without a native tracking session`() async throws {
        let controller = self.makeController()
        defer { controller.releaseStatusItemsForTesting() }
        let menu = try #require(controller.cockpitBackingMenu(provider: nil))
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { true })
        controller.cockpitMenuPanelController = panel
        panel.bridge.reload(menu)
        let initialRevision = panel.bridge.revision

        controller.selectOverviewProvider(.claude, menu: menu)
        for _ in 0..<100 where panel.bridge.revision == initialRevision {
            await Task.yield()
        }

        #expect(panel.bridge.revision > initialRevision)
        #expect(controller.lastMenuProvider == .claude)
        #expect(panel.navigation.planningProviders == [.claude])
        #expect(controller.openMenus.isEmpty)
        #expect(controller.menuSession.menuInteractionGeneration(for: ObjectIdentifier(menu)) == nil)
        #expect(controller.mergedSwitcherContentCaches.isEmpty)
    }

    @Test
    func `settings invalidation refreshes the panel and shutdown cancels pending presentation work`() async throws {
        let controller = self.makeController()
        let menu = try #require(controller.cockpitBackingMenu(provider: nil))
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { true })
        controller.cockpitMenuPanelController = panel
        panel.bridge.reload(menu)
        let initialRevision = panel.bridge.revision
        controller.settings.usageBarsShowUsed.toggle()
        controller.invalidateMenus()
        for _ in 0..<100 where panel.bridge.revision == initialRevision {
            await Task.yield()
        }
        #expect(panel.bridge.revision > initialRevision)
        #expect(controller.openMenus.isEmpty)

        controller.invalidateMenus()
        controller.releaseStatusItemsForTesting()
        let closedRevision = panel.bridge.revision
        for _ in 0..<5 {
            await Task.yield()
        }
        #expect(panel.bridge.rootMenu == nil)
        #expect(panel.bridge.revision == closedRevision)
        #expect(controller.cockpitMenuPanelController == nil)
    }

    private func makeController(merged: Bool = true) -> StatusItemController {
        let settings = testSettingsStore(
            suiteName: "CockpitStatusItemPanelTests",
            userDefaults: InMemoryUserDefaults())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = merged
        settings.selectedMenuProvider = .codex
        settings.mergedMenuLastSelectedWasOverview = false
        enableTestProviders([.codex, .claude], settings: settings)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let environment = [
            "HOME": root.path,
            "CODEX_HOME": root.appendingPathComponent(".codex").path,
            "XDG_CONFIG_HOME": root.appendingPathComponent(".config").path,
        ]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: environment)
        for provider in [UsageProvider.codex, .claude] {
            store.accountInfoCache[provider.instanceID] = .init(
                account: AccountInfo(email: nil, plan: nil),
                configRevision: settings.configRevision,
                expiresAt: .distantFuture)
        }
        return StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar(),
            menuCardRenderingEnabled: false,
            menuRefreshEnabled: false,
            unifiedMenuPanelEnabled: true,
            observeProviderConfigNotifications: false)
    }
}
