import AppKit
import CodexBarCore
import SwiftUI

/// Owns the single, anchored menu-bar surface. Provider collection remains owned by UsageStore.
@MainActor
final class CockpitMenuPanelController: NSObject, NSPopoverDelegate {
    let navigation = CockpitPanelNavigation()
    let bridge = CockpitMenuBridge()
    let popover = NSPopover()
    private weak var owner: StatusItemController?
    private weak var anchor: NSStatusBarButton?
    private var pinnedProvider: UsageProvider?
    private var buildingMenu: NSMenu?
    private var rebuildTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private var needsRebuild = false
    private var needsRootNavigation = false
    private let presentationIsVisible: (() -> Bool)?

    var isShown: Bool {
        self.presentationIsVisible?() ?? self.popover.isShown
    }

    var backingMenu: NSMenu? {
        self.bridge.rootMenu
    }

    init(owner: StatusItemController, presentationIsVisible: (() -> Bool)? = nil) {
        self.owner = owner
        self.presentationIsVisible = presentationIsVisible
        super.init()
        self.popover.behavior = .transient
        self.popover.animates = false
        self.popover.delegate = self
        self.bridge.includesRootItem = CockpitMenuBridge.isSeparateRootAction
        self.bridge.hydrate = { [weak owner] submenu in
            guard let owner else { return }
            if !owner.hydrateHostedSubviewMenuIfNeeded(submenu) {
                owner.refreshHostedSubviewMenu(submenu)
            }
            if owner.isMenuRefreshEnabled, owner.isOpenAIWebSubviewMenu(submenu) {
                owner.store.requestOpenAIDashboardRefreshIfStale(reason: "menu panel details")
            }
        }
        self.bridge.dispatch = { [weak self] item in self?.perform(item) }
        self.navigation.beforePageChange = { [weak self] page in
            // Refresh the hidden provider tree before observers can reveal its previous account.
            if page == .usage { self?.flushPendingRebuild() }
        }
    }

    func toggle(relativeTo button: NSStatusBarButton, provider: UsageProvider?) {
        if self.isShown, self.anchor === button {
            self.close()
        } else {
            self.show(relativeTo: button, provider: provider, page: .usage)
        }
    }

    func show(relativeTo button: NSStatusBarButton, provider: UsageProvider?, page: CockpitPanelPage) {
        guard let owner = self.owner else { return }
        self.anchor = button
        let visibleFrame = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let size = self.preparePresentation(
            provider: provider,
            page: page,
            availableSize: visibleFrame?.size ?? NSSize(width: 1024, height: 768))
        if self.popover.contentViewController == nil {
            self.popover.contentViewController = NSHostingController(rootView: CockpitPanelView(
                settings: owner.settings,
                store: owner.store,
                planStore: owner.cockpitPlanStore,
                navigation: self.navigation,
                resetStore: owner.cockpitResetHistoryStore,
                teamStore: owner.cockpitTeamStore,
                onTeamSettings: { [weak owner] in owner?.openCockpitTeamSettings() },
                usageContent: AnyView(CockpitMenuBridgeView(bridge: self.bridge)),
                onSettings: { [weak owner] in owner?.showSettingsGeneral() },
                onRefresh: { [weak self] in self?.refresh() }).codexBarLocalized())
        }
        owner.store.noteMenuOpened()
        owner.agentSessions.refreshOnMenuOpen()
        if owner.settings.providerStorageFootprintsEnabled { owner.store.refreshStorageFootprintsForOverview() }
        NSApp.activate()
        self.popover.contentSize = size
        self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover.contentViewController?.view.window?.makeKey()
        self.installKeyMonitor()
        if let menu = self.backingMenu, owner.isMenuRefreshEnabled {
            owner.scheduleCodexAccountMenuProjectionRevalidationIfNeeded(for: owner.renderedProviders(for: menu))
            owner.scheduleOpenMenuRefresh(for: menu)
            if owner.lastMenuProvider == .codex {
                owner.store.requestOpenAIDashboardRefreshIfStale(reason: "menu panel open")
            }
        }
    }

    func preparePresentation(provider: UsageProvider?, page: CockpitPanelPage, availableSize: NSSize) -> NSSize {
        self.clearPendingRebuild()
        self.pinnedProvider = provider
        self.navigation.page = page
        let size = Self.contentSize(available: availableSize)
        self.bridge.width = CockpitPanelLayout(width: size.width).menuCardWidth
        self.rebuild(preservingPath: false)
        return size
    }

    static func contentSize(available: NSSize) -> NSSize {
        CockpitPanelLayout.boundedSize(available: available)
    }

    func owns(_ menu: NSMenu) -> Bool {
        self.isShown && self.bridge.owns(menu)
    }

    func menuLayoutWidth(for menu: NSMenu) -> CGFloat? {
        if self.bridge.owns(menu) { return self.bridge.width }
        guard let buildingMenu = self.buildingMenu else { return nil }
        var root = menu
        while let parent = root.supermenu {
            root = parent
        }
        return root === buildingMenu ? self.bridge.width : nil
    }

    func invalidate(resetNavigation: Bool = false) {
        guard self.isShown else { return }
        self.needsRebuild = true
        self.needsRootNavigation = self.needsRootNavigation || resetNavigation
        guard self.navigation.page == .usage, self.rebuildTask == nil else { return }
        self.rebuildTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.rebuildTask = nil
            guard self.navigation.page == .usage else { return }
            self.flushPendingRebuild()
        }
    }

    private func flushPendingRebuild() {
        guard self.isShown, self.needsRebuild else { return }
        let preservesPath = !self.needsRootNavigation
        self.clearPendingRebuild()
        self.rebuild(preservingPath: preservesPath)
    }

    private func clearPendingRebuild() {
        self.rebuildTask?.cancel()
        self.rebuildTask = nil
        self.needsRebuild = false
        self.needsRootNavigation = false
    }

    func close() {
        self.popover.performClose(nil)
    }

    func shutdown() {
        self.popover.close()
        self.cleanUpClosedPresentation()
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        // Receipt previews and NSSavePanel must finish before transient outside-click dismissal.
        popover.contentViewController?.view.window?.attachedSheet == nil && NSApp.modalWindow == nil
    }

    func popoverDidClose(_ notification: Notification) {
        self.cleanUpClosedPresentation()
    }

    private func cleanUpClosedPresentation() {
        self.clearPendingRebuild()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        self.keyMonitor = nil
        // Tear down the hosted root so page onDisappear callbacks release visibility subscriptions.
        self.popover.contentViewController = nil
        self.owner?.cockpitPanelDidClose(menu: self.backingMenu)
        self.bridge.clear()
        self.anchor = nil
    }

    private func rebuild(preservingPath: Bool) {
        guard let owner = self.owner,
              let menu = owner.cockpitBackingMenu(provider: self.pinnedProvider)
        else { return }
        // First presentation has no bridge root yet; its cards already belong to the panel column.
        let previousBuildingMenu = self.buildingMenu
        self.buildingMenu = menu
        defer { self.buildingMenu = previousBuildingMenu }
        let provider = owner.resolveProviderForMenuPresentation(menu)
        owner.populateMenu(menu, provider: provider)
        self.navigation.planningProviders = owner.cockpitPlanningProviders(provider: self.pinnedProvider)
        self.bridge.reload(menu, preservingPath: preservingPath)
    }

    private func perform(_ item: NSMenuItem) {
        guard item.isEnabled, let action = item.action else { return }
        let keepsOpen = action == #selector(StatusItemController.refreshMenuItem(_:))
            || action == #selector(StatusItemController.selectOverviewProvider(_:))
        if !keepsOpen { self.close() }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    private func refresh() {
        guard let owner = self.owner else { return }
        if self.navigation.page == .team {
            Task { await owner.cockpitTeamStore?.refresh() }
            return
        }
        if self.navigation.page == .calendar {
            Task { await owner.cockpitResetHistoryStore.refresh() }
        }
        if self.navigation.page == .usage {
            owner.refreshMenuProviderNow(in: self.backingMenu)
        } else {
            guard owner.settings.costUsageEnabled else { return }
            owner.store.refreshSpendDashboard(accounts: SpendDashboardSource.codexRequests(
                settings: owner.settings,
                store: owner.store))
        }
    }

    private func installKeyMonitor() {
        guard self.keyMonitor == nil else { return }
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let owner = self.owner, self.isShown,
              let window = self.popover.contentViewController?.view.window,
              event.window === window, window.attachedSheet == nil, NSApp.modalWindow == nil
        else { return false }
        if event.keyCode == 53 {
            if self.navigation.page != .usage || !self.bridge.goBack() { self.close() }
            return true
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "r": self.refresh(); return true
            case ",": owner.showSettingsGeneral(); return true
            case "q": self.close(); owner.quit(); return true
            default: break
            }
        }
        // Arrow keys belong to text editing; provider navigation is only active on the usage page.
        guard self.navigation.page == .usage,
              !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField),
              let menu = self.backingMenu
        else { return false }
        return owner.handleProviderSwitcherShortcut(event, menu: menu)
    }
}
