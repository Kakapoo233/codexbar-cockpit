import AppKit
import CodexBarCore

extension StatusItemController {
    func startCockpitResetHistory() {
        self.cockpitResetHistoryStore.start()
        AppNotifications.shared.configureResetCalendarAction { [weak self] in self?.showCockpitCalendar() }
    }

    func attachPresentationMenu(_ menu: NSMenu?, to item: NSStatusItem) {
        if self.unifiedMenuPanelEnabledForController {
            self.configureCockpitStatusItem(item)
        } else if item.menu !== menu {
            item.menu = menu
        }
    }

    func configureCockpitStatusItem(_ item: NSStatusItem) {
        item.menu = nil
        item.button?.target = self
        item.button?.action = #selector(self.toggleCockpitPanel(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc func toggleCockpitPanel(_ sender: NSStatusBarButton) {
        let provider = self.statusItems.first { $0.value.button === sender }?.key.firstPartyProvider
        self.ensureCockpitPanel().toggle(relativeTo: sender, provider: provider)
    }

    func ensureCockpitPanel() -> CockpitMenuPanelController {
        if let cockpitMenuPanelController { return cockpitMenuPanelController }
        let panel = CockpitMenuPanelController(owner: self)
        self.cockpitMenuPanelController = panel
        return panel
    }

    func cockpitBackingMenu(provider: UsageProvider?) -> NSMenu? {
        if self.shouldMergeIcons {
            if self.mergedMenu == nil { self.mergedMenu = self.makeMenu() }
            return self.mergedMenu
        }
        if let provider, self.isEnabled(provider) {
            if self.providerMenus[provider.instanceID] == nil {
                self.providerMenus[provider.instanceID] = self.makeMenu(for: provider)
            }
            return self.providerMenus[provider.instanceID]
        }
        if self.fallbackMenu == nil { self.fallbackMenu = self.makeMenu(for: nil) }
        return self.fallbackMenu
    }

    func cockpitPlanningProviders(provider: UsageProvider?) -> [UsageProvider] {
        guard self.shouldMergeIcons else { return [provider ?? self.resolvedMenuProvider() ?? .codex] }
        let enabled = self.store.enabledFirstPartyProvidersForDisplay()
        switch self.resolvedMergedMenuSelection(enabledProviders: enabled) {
        case .overview: return enabled
        case let .provider(instanceID): return instanceID.firstPartyProvider.map { [$0] } ?? []
        case nil: return [self.resolvedMenuProvider() ?? .codex]
        }
    }

    /// Returns true only for the panel's backing tree; it never creates an NSMenu tracking session.
    @discardableResult
    func refreshCockpitPanel(for menu: NSMenu, resetNavigation: Bool = false) -> Bool {
        guard let panel = self.cockpitMenuPanelController, panel.owns(menu) else { return false }
        panel.invalidate(resetNavigation: resetNavigation)
        return true
    }

    func showCockpitStatistics() {
        guard self.unifiedMenuPanelEnabledForController else {
            self.settingsOpenHandler?(.usageSpend)
            return
        }
        if let panel = self.cockpitMenuPanelController, panel.isShown {
            panel.navigation.page = .statistics
            return
        }
        let provider = self.shouldMergeIcons ? nil : self.resolvedShortcutProvider()
        let item = provider.map { self.lazyStatusItem(for: $0) } ?? self.statusItem
        guard let button = item.button else { return }
        self.ensureCockpitPanel().show(relativeTo: button, provider: provider, page: .statistics)
    }

    func showCockpitCalendar() {
        if let panel = self.cockpitMenuPanelController, panel.isShown {
            panel.navigation.page = .calendar
            return
        }
        let provider = self.shouldMergeIcons ? nil : self.resolvedShortcutProvider()
        let item = provider.map { self.lazyStatusItem(for: $0) } ?? self.statusItem
        guard let button = item.button else { return }
        self.ensureCockpitPanel().show(relativeTo: button, provider: provider, page: .calendar)
    }

    func cockpitPanelDidClose(menu: NSMenu?) {
        if let menu { self.cancelMenuWork(ObjectIdentifier(menu)) }
        self.resetClaudeSwapAccountInspection()
        self.resetCompactAccountMenuExpansionStateIfIdle()
        self.scheduleDeferredMenuInteractionRefreshIfNeeded()
    }
}
