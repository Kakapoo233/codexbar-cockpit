import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
private final class CockpitMenuActionRecorder: NSObject {
    var sender: NSMenuItem?
    @objc func record(_ sender: NSMenuItem) { self.sender = sender }
}

@MainActor
@Suite(.serialized)
struct CockpitMenuBridgeTests {
    @Test
    func `actions retain the original sender represented object and menu`() {
        _ = NSApplication.shared
        let recorder = CockpitMenuActionRecorder()
        let menu = NSMenu()
        let item = NSMenuItem(title: "Sign in", action: #selector(recorder.record(_:)), keyEquivalent: "")
        item.target = recorder
        item.representedObject = "test-provider"
        menu.addItem(item)
        let bridge = CockpitMenuBridge()
        bridge.reload(menu)

        #expect(bridge.activate(item))
        #expect(recorder.sender === item)
        #expect(recorder.sender?.menu === menu)
        #expect(recorder.sender?.representedObject as? String == "test-provider")
    }

    @Test
    func `disabled actions and disabled submenu routes never dispatch`() {
        let bridge = CockpitMenuBridge()
        var dispatched = false
        bridge.dispatch = { _ in dispatched = true }
        let item = NSMenuItem(title: "Disabled", action: #selector(StatusItemController.refreshNow), keyEquivalent: "")
        item.isEnabled = false
        #expect(!bridge.activate(item))
        item.submenu = NSMenu()
        #expect(!bridge.openSubmenu(item))
        #expect(!dispatched)
        #expect(!bridge.canGoBack)
    }

    @Test
    func `hosted submenu hydration happens before its rows are read and back restores root`() {
        let root = NSMenu()
        let item = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        item.submenu = submenu
        root.addItem(item)
        let bridge = CockpitMenuBridge()
        var hydrated = 0
        bridge.hydrate = { menu in
            #expect(menu === submenu)
            hydrated += 1
            menu.addItem(withTitle: "Synthetic chart", action: nil, keyEquivalent: "")
        }
        bridge.reload(root)

        #expect(bridge.openSubmenu(item))
        #expect(hydrated == 1)
        #expect(bridge.items.map(\.title) == ["Synthetic chart"])
        #expect(bridge.owns(submenu))
        #expect(bridge.goBack())
        #expect(bridge.currentMenu === root)
        #expect(!bridge.goBack())
    }

    @Test
    func `a refreshed backing tree restores the current submenu by its stable identifier`() {
        let root = NSMenu()
        let first = Self.submenuItem("history", title: "History")
        root.addItem(first)
        let bridge = CockpitMenuBridge()
        bridge.reload(root)
        #expect(bridge.openSubmenu(first))

        root.removeAllItems()
        let replacement = Self.submenuItem("history", title: "New title")
        root.addItem(replacement)
        bridge.reload(root)
        #expect(bridge.path.first === replacement)
        #expect(bridge.currentMenu === replacement.submenu)

        let otherProvider = NSMenu()
        bridge.reload(otherProvider)
        #expect(!bridge.canGoBack)
        #expect(bridge.currentMenu === otherProvider)
        #expect(!bridge.owns(root))
    }

    @Test
    func `root settings and refresh are merged while provider settings and nested refresh survive`() {
        let root = NSMenu()
        let settings = NSMenuItem(
            title: "Settings",
            action: #selector(StatusItemController.showSettingsGeneral),
            keyEquivalent: ",")
        let refresh = NSMenuItem()
        refresh.representedObject = StatusItemController.persistentRefreshMenuItemID
        let providerSettings = NSMenuItem(
            title: "Provider settings",
            action: #selector(StatusItemController.showProviderSettings(_:)),
            keyEquivalent: "")
        let history = Self.submenuItem("history", title: "History")
        let nestedRefresh = NSMenuItem(
            title: "Refresh history",
            action: #selector(StatusItemController.refreshMenuItem(_:)),
            keyEquivalent: "")
        history.submenu?.addItem(nestedRefresh)
        [NSMenuItem.separator(), settings, refresh, NSMenuItem.separator(), providerSettings, history]
            .forEach(root.addItem)
        let bridge = CockpitMenuBridge()
        bridge.includesRootItem = CockpitMenuBridge.isSeparateRootAction
        bridge.reload(root)

        #expect(bridge.items == [providerSettings, history])
        #expect(bridge.openSubmenu(history))
        #expect(bridge.items == [nestedRefresh])
    }

    @Test
    func `close cleanup releases the backing tree and navigation`() {
        let bridge = CockpitMenuBridge()
        let root = NSMenu()
        let item = Self.submenuItem("details", title: "Details")
        root.addItem(item)
        bridge.reload(root)
        #expect(bridge.openSubmenu(item))
        let revision = bridge.revision
        bridge.clear()
        #expect(bridge.rootMenu == nil)
        #expect(bridge.currentMenu == nil)
        #expect(bridge.path.isEmpty)
        #expect(bridge.items.isEmpty)
        #expect(bridge.revision > revision)
    }

    @Test
    func `hosted row height follows expanded content and stops observing when removed`() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        view.postsFrameChangedNotifications = false
        let coordinator = CockpitMenuItemView.Coordinator()
        var heights: [CGFloat] = []
        coordinator.observe(view) { heights.append($0) }
        view.setFrameSize(NSSize(width: 300, height: 120))
        view.setFrameSize(NSSize(width: 300, height: 40))
        #expect(heights == [120, 40])
        coordinator.stop()
        view.setFrameSize(NSSize(width: 300, height: 180))
        #expect(heights == [120, 40])
        #expect(!view.postsFrameChangedNotifications)
    }

    @Test
    func `popover content fits a smaller screen`() {
        let size = CockpitMenuPanelController.contentSize(available: NSSize(width: 700, height: 500))
        #expect(size.width == 676)
        #expect(size.height == 460)
        #expect(CockpitMenuPanelController.contentSize(available: NSSize(width: 1920, height: 1080)) ==
            NSSize(width: 960, height: 700))
        let tiny = CockpitMenuPanelController.contentSize(available: NSSize(width: 300, height: 260))
        #expect(tiny.width <= 276)
        #expect(tiny.height <= 220)
    }

    @Test
    func `wide and compact columns leave room for the hosted submenu control`() {
        for width in [CGFloat(676), 800, 960] {
            let layout = CockpitPanelLayout(width: width)
            #expect(layout.menuCardWidth > 0)
            #expect(layout.menuCardWidth + 24 <= layout.mainColumnWidth)
            #expect(layout.mainColumnWidth + 2 * CockpitPanelLayout.contentInset <= width)
            if layout.usesSidebar {
                #expect(layout.mainColumnWidth >= 440)
                #expect(layout.mainColumnWidth + CockpitPanelLayout.sidebarWidth
                    + CockpitPanelLayout.columnSpacing + 2 * CockpitPanelLayout.contentInset <= width)
            }
        }
        #expect(!CockpitPanelLayout(width: 676).usesSidebar)
        #expect(CockpitPanelLayout(width: 960).usesSidebar)
    }

    private static func submenuItem(_ identifier: String, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = identifier
        item.submenu = NSMenu()
        return item
    }
}
