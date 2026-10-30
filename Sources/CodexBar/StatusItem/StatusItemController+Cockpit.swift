import AppKit
import CodexBarCore

extension StatusItemController {
    func addCockpitMenuItems(to menu: NSMenu, provider: UsageProvider) {
        let open = NSMenuItem(title: "CodexBar Cockpit…", action: #selector(self.openCockpit), keyEquivalent: "")
        open.target = self
        open.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: nil)
        menu.addItem(open)
        if !SettingsStore.isRunningTests, self.cockpitPlanStore.availableProviders.contains(provider) {
            let status = self.cockpitPlanStore.status(for: provider)
            if let suggestion = status.suggestedPercent {
                let cap = status.manualCapPercent.map { " · 个人上限 \(Int($0.rounded()))%" } ?? ""
                let summary = NSMenuItem(
                    title: "今日建议 \(String(format: "%.1f", suggestion))%\(cap)",
                    action: nil,
                    keyEquivalent: "")
                summary.isEnabled = false
                menu.addItem(summary)
            }
        }
        menu.addItem(.separator())
    }

    @objc func openCockpit() {
        self.cockpitPlanStore.ingest(self.store)
        if self.cockpitWindowController == nil {
            self.cockpitWindowController = CockpitWindowController(
                settings: self.settings,
                store: self.store,
                planStore: self.cockpitPlanStore)
        }
        self.cockpitWindowController?.present()
    }
}
