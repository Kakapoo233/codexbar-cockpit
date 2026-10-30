import AppKit
import SwiftUI

/// One ordinary document-style window, opened explicitly from the menu bar.
@MainActor
final class CockpitWindowController: NSWindowController {
    init(settings: SettingsStore, store: UsageStore, planStore: CockpitPlanStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = L("cockpit_ui_brand")
        window.minSize = NSSize(width: 840, height: 620)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CockpitDashboardWindow")
        window.contentViewController = NSHostingController(rootView: CockpitDashboardView(
            settings: settings,
            store: store,
            planStore: planStore).codexBarLocalized())
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        self.showWindow(nil)
        self.window?.makeKeyAndOrderFront(nil)
    }
}
