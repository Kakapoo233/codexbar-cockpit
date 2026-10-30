import AppKit
import Observation
import SwiftUI

/// The existing menu remains the provider/action model, but is never asked to track events.
/// Retaining its original items is essential: account and refresh actions inspect sender.menu.
@MainActor
@Observable
final class CockpitMenuBridge {
    private(set) var rootMenu: NSMenu?
    private(set) var currentMenu: NSMenu?
    private(set) var path: [NSMenuItem] = []
    private(set) var revision = 0
    var width: CGFloat = 712

    @ObservationIgnored var hydrate: (NSMenu) -> Void = { _ in }
    @ObservationIgnored var includesRootItem: (NSMenuItem) -> Bool = { _ in true }
    @ObservationIgnored var dispatch: (NSMenuItem) -> Void = { item in
        guard let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    var items: [NSMenuItem] {
        let source = self.currentMenu?.items.filter {
            !$0.isHidden && (self.currentMenu !== self.rootMenu || self.includesRootItem($0))
        } ?? []
        var result: [NSMenuItem] = []
        for item in source {
            if item.isSeparatorItem, result.isEmpty || result.last?.isSeparatorItem == true { continue }
            result.append(item)
        }
        if result.last?.isSeparatorItem == true { result.removeLast() }
        return result
    }

    var canGoBack: Bool {
        !self.path.isEmpty
    }

    func owns(_ menu: NSMenu) -> Bool {
        var root = menu
        while let parent = root.supermenu {
            root = parent
        }
        return root === self.rootMenu
    }

    func reload(_ menu: NSMenu, preservingPath: Bool = true) {
        let route = preservingPath && self.rootMenu === menu
            ? self.path.map { ($0.representedObject as? String, $0.title) } : []
        self.rootMenu = menu
        self.currentMenu = menu
        self.path = []
        for (identifier, title) in route {
            guard let item = self.currentMenu?.items.first(where: {
                if let identifier { return $0.representedObject as? String == identifier }
                return $0.title == title
            }), let submenu = item.submenu else { break }
            self.hydrate(submenu)
            self.path.append(item)
            self.currentMenu = submenu
        }
        self.revision &+= 1
    }

    @discardableResult
    func openSubmenu(_ item: NSMenuItem) -> Bool {
        guard item.isEnabled, let submenu = item.submenu else { return false }
        self.hydrate(submenu)
        self.path.append(item)
        self.currentMenu = submenu
        self.revision &+= 1
        return true
    }

    @discardableResult
    func goBack() -> Bool {
        guard !self.path.isEmpty else { return false }
        self.path.removeLast()
        self.currentMenu = self.path.last?.submenu ?? self.rootMenu
        self.revision &+= 1
        return true
    }

    @discardableResult
    func activate(_ item: NSMenuItem) -> Bool {
        guard item.isEnabled else { return false }
        if item.submenu != nil { return self.openSubmenu(item) }
        guard item.action != nil else { return false }
        self.dispatch(item)
        return true
    }

    func clear() {
        self.path = []
        self.currentMenu = nil
        self.rootMenu = nil
        self.revision &+= 1
    }

    /// Root chrome owns one settings entry and a refresh whose scope is the selected provider.
    static func isSeparateRootAction(_ item: NSMenuItem) -> Bool {
        if item.representedObject as? String == StatusItemController.persistentRefreshMenuItemID { return false }
        let mergedActions: Set<Selector> = [
            #selector(StatusItemController.showSettingsGeneral),
            #selector(StatusItemController.refreshMenuItem(_:)),
            #selector(StatusItemController.refreshNow),
        ]
        return item.action.map { !mergedActions.contains($0) } ?? true
    }
}

@MainActor
struct CockpitMenuBridgeView: View {
    @Bindable var bridge: CockpitMenuBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if self.bridge.canGoBack {
                Button {
                    self.bridge.goBack()
                } label: {
                    Label(L("Back"), systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 6)
            }
            ForEach(self.bridge.items, id: \.self) { item in
                self.row(item)
            }
        }
        .id(self.bridge.revision)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ item: NSMenuItem) -> some View {
        if item.isSeparatorItem {
            Divider().padding(.vertical, 3)
        } else if let view = item.view {
            HStack(alignment: .top, spacing: 0) {
                CockpitHostedMenuRow(view: view)
                if item.submenu != nil {
                    Button {
                        self.bridge.openSubmenu(item)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 24, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!item.isEnabled)
                    .accessibilityLabel(item.title.isEmpty ? L("Show details") : item.title)
                }
            }
        } else if item.action != nil || item.submenu != nil {
            Button {
                self.bridge.activate(item)
            } label: {
                self.label(item)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!item.isEnabled)
            .help(item.toolTip ?? "")
        } else {
            self.label(item)
                .foregroundStyle(.secondary)
        }
    }

    private func label(_ item: NSMenuItem) -> some View {
        HStack(spacing: 8) {
            if item.state != .off {
                Image(systemName: item.state == .on ? "checkmark" : "minus")
            } else if let image = item.image {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 16, height: 16)
            }
            Text(item.title).multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if item.submenu != nil {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            } else if !item.keyEquivalent.isEmpty {
                Text(Self.shortcutLabel(item)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func shortcutLabel(_ item: NSMenuItem) -> String {
        let modifiers: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]
        return modifiers.filter { item.keyEquivalentModifierMask.contains($0.0) }.map(\.1).joined()
            + item.keyEquivalent.uppercased()
    }
}

private struct CockpitHostedMenuRow: View {
    let view: NSView
    @State private var height: CGFloat

    init(view: NSView) {
        self.view = view
        self._height = State(initialValue: max(1, view.frame.height))
    }

    var body: some View {
        CockpitMenuItemView(view: self.view) { newHeight in
            if abs(self.height - newHeight) > 0.5 { self.height = newHeight }
        }
        .frame(height: self.height)
    }
}

/// These views belong exclusively to the untracked backing menu. No view is taken from a live NSMenu.
struct CockpitMenuItemView: NSViewRepresentable {
    let view: NSView
    let onHeightChange: @MainActor (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: self.view.frame)
        self.install(in: container)
        context.coordinator.observe(self.view, onHeightChange: self.onHeightChange)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if self.view.superview !== container { self.install(in: container) }
    }

    private func install(in container: NSView) {
        for child in container.subviews {
            child.removeFromSuperview()
        }
        self.view.removeFromSuperview()
        self.view.frame.origin = .zero
        self.view.autoresizingMask = [.width]
        container.addSubview(self.view)
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.stop()
        for child in container.subviews {
            child.removeFromSuperview()
        }
    }

    @MainActor
    final class Coordinator {
        private var frameObserver: NSObjectProtocol?
        private weak var observedView: NSView?
        private var previousPostsFrameNotifications = false

        func observe(_ view: NSView, onHeightChange: @escaping @MainActor (CGFloat) -> Void) {
            self.stop()
            self.observedView = view
            self.previousPostsFrameNotifications = view.postsFrameChangedNotifications
            view.postsFrameChangedNotifications = true
            self.frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: view, queue: .main)
            { [weak view] _ in
                MainActor.assumeIsolated {
                    guard let view else { return }
                    onHeightChange(max(1, view.frame.height))
                }
            }
        }

        func stop() {
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
            self.frameObserver = nil
            self.observedView?.postsFrameChangedNotifications = self.previousPostsFrameNotifications
            self.observedView = nil
        }
    }
}
