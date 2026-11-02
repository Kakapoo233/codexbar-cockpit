import AppKit
import CodexBarCore
import Observation
import os
import Testing
@testable import CodexBar

@MainActor
private final class CockpitPageChangeRecorder {
    var observed = false
}

@MainActor
private final class CockpitSizeCountingMenu: NSMenu {
    private nonisolated let sizeReads = OSAllocatedUnfairLock(initialState: 0)

    var sizeReadCount: Int {
        self.sizeReads.withLock { $0 }
    }

    override var size: NSSize {
        self.sizeReads.withLock { $0 += 1 }
        return super.size
    }
}

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

    @Test
    func `hidden usage refreshes wait for the page to become visible`() async throws {
        let controller = self.makeController()
        defer { controller.releaseStatusItemsForTesting() }
        let menu = try #require(controller.cockpitBackingMenu(provider: nil))
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { true })
        controller.cockpitMenuPanelController = panel
        panel.bridge.reload(menu)
        panel.navigation.page = .statistics
        let initialRevision = panel.bridge.revision

        for _ in 0..<3 {
            panel.invalidate()
            for _ in 0..<5 {
                await Task.yield()
            }
        }

        #expect(panel.bridge.revision == initialRevision)
        panel.navigation.page = .usage
        #expect(panel.bridge.revision == initialRevision + 1)
        for _ in 0..<5 {
            await Task.yield()
        }
        #expect(panel.bridge.revision == initialRevision + 1)
    }

    @Test(arguments: [false, true])
    func `a queued usage refresh does not rebuild after leaving its page`(drainWhileHidden: Bool) async throws {
        let controller = self.makeController()
        defer { controller.releaseStatusItemsForTesting() }
        let menu = try #require(controller.cockpitBackingMenu(provider: nil))
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { true })
        controller.cockpitMenuPanelController = panel
        panel.bridge.reload(menu)
        let initialRevision = panel.bridge.revision

        panel.invalidate()
        panel.navigation.page = .calendar
        if drainWhileHidden {
            for _ in 0..<20 {
                await Task.yield()
            }
        }
        #expect(panel.bridge.revision == initialRevision)

        panel.navigation.page = .usage
        #expect(panel.bridge.revision == initialRevision + 1)
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(panel.bridge.revision == initialRevision + 1)
    }

    @Test
    func `returning to usage publishes current provider settings before the selected page changes`() async throws {
        let controller = self.makeController()
        defer { controller.releaseStatusItemsForTesting() }
        let menu = try #require(controller.cockpitBackingMenu(provider: nil))
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { true })
        controller.cockpitMenuPanelController = panel
        controller.populateMenu(menu, provider: .codex)
        panel.bridge.reload(menu)
        panel.navigation.page = .calendar
        let initialRevision = panel.bridge.revision

        controller.settings.selectedMenuProvider = .claude
        controller.settings.statusChecksEnabled = true
        controller.invalidateMenus()
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(panel.bridge.revision == initialRevision)

        let recorder = CockpitPageChangeRecorder()
        withObservationTracking {
            _ = panel.navigation.page
        } onChange: {
            MainActor.assumeIsolated {
                recorder.observed = true
                #expect(panel.navigation.page == .calendar)
                #expect(panel.bridge.revision == initialRevision + 1)
                #expect(panel.navigation.planningProviders == [.claude])
                let statusRows = panel.bridge.items.compactMap(\.submenu).flatMap(\.items).filter {
                    $0.representedObject as? String == StatusItemController.statusComponentsID
                }
                #expect(statusRows.count == 1)
                #expect(statusRows.first?.toolTip == UsageProvider.claude.rawValue)
            }
        }

        panel.navigation.page = .usage
        #expect(recorder.observed)
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(panel.bridge.revision == initialRevision + 1)
    }

    @Test(arguments: [false, true])
    func `hidden refreshes preserve the detail route unless any refresh requests the root`(
        resetRoute: Bool) async throws
    {
        let controller = self.makeController(statusChecksEnabled: true)
        defer { controller.releaseStatusItemsForTesting() }
        controller.settings.selectedMenuProvider = .claude
        let menu = try #require(controller.cockpitBackingMenu(provider: nil))
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { true })
        controller.cockpitMenuPanelController = panel
        controller.populateMenu(menu, provider: .claude)
        panel.bridge.reload(menu)
        let item = try #require(panel.bridge.items.first {
            $0.submenu?.items.first?.representedObject as? String == StatusItemController.statusComponentsID
        })
        #expect(panel.bridge.openSubmenu(item))
        panel.navigation.page = .statistics
        let initialRevision = panel.bridge.revision

        panel.invalidate(resetNavigation: resetRoute)
        panel.invalidate()
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(panel.bridge.revision == initialRevision)

        panel.navigation.page = .usage
        #expect(panel.bridge.revision == initialRevision + 1)
        #expect(panel.bridge.canGoBack == !resetRoute)
        if !resetRoute { #expect(panel.bridge.path.first?.title == item.title) }
    }

    @Test
    func `shutdown discards hidden refreshes before another page selection`() async throws {
        let controller = self.makeController()
        defer { controller.releaseStatusItemsForTesting() }
        let menu = try #require(controller.cockpitBackingMenu(provider: nil))
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { true })
        controller.cockpitMenuPanelController = panel
        panel.bridge.reload(menu)
        panel.navigation.page = .team
        panel.invalidate(resetNavigation: true)
        panel.shutdown()
        let closedRevision = panel.bridge.revision

        panel.navigation.page = .usage
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(panel.bridge.rootMenu == nil)
        #expect(panel.bridge.revision == closedRevision)
    }

    @Test(arguments: [CGFloat(0), CGFloat(1400)])
    func `first presentation sizes cards before attaching the backing menu`(minimumNativeWidth: CGFloat) {
        let controller = self.makeController(renderCards: true)
        defer { controller.releaseStatusItemsForTesting() }
        let menu = CockpitSizeCountingMenu()
        menu.minimumWidth = minimumNativeWidth
        controller.mergedMenu = menu
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { false })
        controller.cockpitMenuPanelController = panel
        #expect(panel.bridge.rootMenu == nil)
        let initialSizeReads = menu.sizeReadCount

        let size = panel.preparePresentation(
            provider: nil,
            page: .usage,
            availableSize: NSSize(width: 1920, height: 1080))
        let views = menu.items.compactMap(\.view).filter { $0 is any MenuCardMeasuring }

        #expect(size == NSSize(width: 960, height: 700))
        #expect(panel.bridge.rootMenu === menu)
        #expect(!views.isEmpty)
        #expect(views.allSatisfy { $0.frame.width == 608 })
        #expect(menu.sizeReadCount == initialSizeReads)
    }

    @Test(arguments: [false, true])
    func `a new presentation replaces pending refreshes with one build at the new provider width`(
        pendingWhileHidden: Bool) async throws
    {
        let controller = self.makeController(merged: false, renderCards: true)
        defer { controller.releaseStatusItemsForTesting() }
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { true })
        controller.cockpitMenuPanelController = panel
        let originalMenu = try #require(controller.cockpitBackingMenu(provider: .codex))
        let nextMenu = try #require(controller.cockpitBackingMenu(provider: .claude))
        nextMenu.minimumWidth = 1400
        _ = panel.preparePresentation(
            provider: .codex,
            page: .usage,
            availableSize: NSSize(width: 1920, height: 1080))
        #expect(panel.bridge.rootMenu === originalMenu)
        #expect(panel.bridge.width == 608)
        if pendingWhileHidden { panel.navigation.page = .calendar }
        panel.invalidate(resetNavigation: true)
        let initialRevision = panel.bridge.revision

        let size = panel.preparePresentation(
            provider: .claude,
            page: .usage,
            availableSize: NSSize(width: 840, height: 700))

        #expect(size == NSSize(width: 816, height: 660))
        #expect(panel.bridge.rootMenu === nextMenu)
        #expect(panel.bridge.revision == initialRevision + 1)
        #expect(panel.navigation.page == .usage)
        #expect(panel.navigation.planningProviders == [.claude])
        #expect(panel.bridge.width == 464)
        let views = nextMenu.items.compactMap(\.view).filter { $0 is any MenuCardMeasuring }
        #expect(!views.isEmpty)
        #expect(views.allSatisfy { $0.frame.width == 464 })
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(panel.bridge.revision == initialRevision + 1)
    }

    @Test(arguments: [CGFloat(264), CGFloat(608)])
    func `panel menu trees keep the column width despite oversized native menu measurement`(width: CGFloat) {
        let controller = self.makeController()
        defer { controller.releaseStatusItemsForTesting() }
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { false })
        controller.cockpitMenuPanelController = panel
        panel.bridge.width = width
        let root = NSMenu()
        let submenu = NSMenu()
        let nested = NSMenu()
        self.attach(submenu, to: root)
        self.attach(nested, to: submenu)
        nested.addItem(withTitle: "Leaf", action: nil, keyEquivalent: "")
        panel.bridge.reload(root)

        for menu in [root, submenu, nested] {
            menu.minimumWidth = 1400
            #expect(menu.size.width > width)
            #expect(controller.renderedMenuWidth(for: menu) == width)
        }
    }

    @Test
    func `hosted detail hydration and refresh use the panel column width`() throws {
        let controller = self.makeController(renderCards: true, statusChecksEnabled: true)
        defer { controller.releaseStatusItemsForTesting() }
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { true })
        controller.cockpitMenuPanelController = panel
        let initialWidth = CockpitPanelLayout(width: 960).menuCardWidth
        panel.bridge.width = initialWidth
        let componentName = ProviderDescriptorRegistry.descriptor(for: .claude)
            .metadata.statusComponentAllowlist?.first ?? "API"
        controller.store.statusComponents[.claude] = [
            ProviderStatusComponent(id: "synthetic-api", name: componentName, indicator: .none, status: "operational"),
        ]
        let root = NSMenu()
        let submenu = controller.makeHostedSubviewPlaceholderMenu(
            chartID: StatusItemController.statusComponentsID, provider: .claude)
        self.attach(submenu, to: root)
        root.minimumWidth = 1400
        submenu.minimumWidth = 1400
        panel.bridge.reload(root)
        #expect(root.size.width > initialWidth)

        panel.bridge.hydrate(submenu)
        let firstView = try #require(submenu.items.compactMap(\.view).first)
        #expect(firstView.frame.width == initialWidth)

        let refreshedWidth = CockpitPanelLayout(width: 816).menuCardWidth
        panel.bridge.width = refreshedWidth
        panel.bridge.hydrate(submenu)
        let refreshedView = try #require(submenu.items.compactMap(\.view).first)
        #expect(refreshedView.frame.width == refreshedWidth)
        #expect(controller.openMenus.isEmpty)
    }

    @Test
    func `menus outside the panel retain native width resolution`() {
        let controller = self.makeController()
        defer { controller.releaseStatusItemsForTesting() }
        let panel = CockpitMenuPanelController(owner: controller, presentationIsVisible: { true })
        controller.cockpitMenuPanelController = panel
        panel.bridge.width = 608
        panel.bridge.reload(NSMenu())

        for minimumWidth in [CGFloat(0), CGFloat(1400)] {
            let outside = NSMenu()
            outside.minimumWidth = minimumWidth
            outside.addItem(withTitle: "Native menu", action: nil, keyEquivalent: "")
            #expect(controller.renderedMenuWidth(for: outside) == StatusItemController.resolvedRenderedMenuWidth(
                menuWidth: outside.size.width, trackedWindowWidth: nil))
        }
    }

    private func attach(_ submenu: NSMenu, to parent: NSMenu) {
        let title = String(repeating: "Synthetic long native menu title ", count: 20)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        parent.addItem(item)
    }

    private func makeController(
        merged: Bool = true,
        renderCards: Bool = false,
        statusChecksEnabled: Bool = false) -> StatusItemController
    {
        let settings = testSettingsStore(
            suiteName: "CockpitStatusItemPanelTests",
            userDefaults: InMemoryUserDefaults())
        settings.statusChecksEnabled = statusChecksEnabled
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
            menuCardRenderingEnabled: renderCards,
            menuRefreshEnabled: false,
            unifiedMenuPanelEnabled: true,
            observeProviderConfigNotifications: false)
    }
}
