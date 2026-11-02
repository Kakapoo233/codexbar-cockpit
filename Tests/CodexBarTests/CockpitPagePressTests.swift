import AppKit
import SwiftUI
import Testing
@testable import CodexBar

/// Verify the production buttons' minimum target layout and native accessibility activation.
@MainActor
struct CockpitPagePressTests {
    @Test(arguments: [true, false])
    func `page buttons retain 44 point targets and accessible actions in both layouts`(
        showsTitle: Bool) async throws
    {
        let fixture = PagePressFixture(showsTitle: showsTitle)
        defer { fixture.close() }
        try await Self.settle(fixture.host)

        var expectedChanges: [CockpitPanelPage] = []
        let pages: [CockpitPanelPage] = [.statistics, .calendar, .team, .usage, .statistics, .statistics, .usage]
        for page in pages {
            let button = try Self.button(for: page, in: fixture.host)
            let frame = try Self.frame(of: button, in: fixture)
            #expect(frame.width >= 44 - 0.5)
            #expect(frame.height >= 44 - 0.5)
            #expect(fixture.host.bounds.contains(frame))
            let role = Self.property(button, #selector(NSAccessibilityProtocol.accessibilityRole)) as? String
            let label = Self.property(button, #selector(NSAccessibilityProtocol.accessibilityLabel)) as? String
            #expect(role == "AXButton")
            #expect(label == page.title)
            let selector = #selector(NSAccessibilityProtocol.accessibilityPerformPress)
            try #require(button.responds(to: selector))
            let implementation = try #require(button.method(for: selector))
            typealias PerformPress = @convention(c) (NSObject, Selector) -> Bool
            let press = unsafeBitCast(implementation, to: PerformPress.self)
            if fixture.navigation.page != page { expectedChanges.append(page) }
            try #require(press(button, selector))
            try await Self.settle(fixture.host)
            #expect(fixture.navigation.page == page)
            #expect(fixture.changes == expectedChanges)
        }
    }

    private static func button(for page: CockpitPanelPage, in host: NSView) throws -> NSObject {
        try self.node(identifier: "cockpit-panel-page-\(page.rawValue)", in: host)
    }

    private static func node(identifier: String, in host: NSView) throws -> NSObject {
        try #require(self.accessibilityNodes(host).first {
            Self.property($0, #selector(NSAccessibilityProtocol.accessibilityIdentifier)) as? String == identifier
        })
    }

    private static func frame(of button: NSObject, in fixture: PagePressFixture) throws -> CGRect {
        let screenFrame = try #require((button.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue)
        return fixture.host.convert(fixture.window.convertFromScreen(screenFrame), from: nil)
    }

    private static func accessibilityNodes(_ element: Any, depth: Int = 0) -> [NSObject] {
        guard depth < 30, let element = element as? NSObject else { return [] }
        let children = Self.property(element, #selector(NSAccessibilityProtocol.accessibilityChildren)) as? [Any] ?? []
        return [element] + children.flatMap { Self.accessibilityNodes($0, depth: depth + 1) }
    }

    private static func property(_ element: NSObject, _ selector: Selector) -> Any? {
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue()
    }

    private static func settle(_ host: NSView) async throws {
        for _ in 0..<3 {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class PagePressFixture {
    let navigation: CockpitPanelNavigation
    let host: NSHostingView<AnyView>
    let window: NSWindow
    var changes: [CockpitPanelPage] = []

    init(showsTitle: Bool) {
        _ = NSApplication.shared
        let navigation = CockpitPanelNavigation()
        let host = NSHostingView(rootView: AnyView(VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(CockpitPanelPage.allCases) { page in
                    CockpitPanelPageButton(page: page, navigation: navigation, showsTitle: showsTitle)
                }
            }
            Text("Synthetic page buttons")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.accessibilityEnabled, true)
        .environment(\.controlActiveState, .active)))
        host.frame = CGRect(x: 0, y: 0, width: showsTitle ? 960 : 260, height: 140)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.navigation = navigation
        self.host = host
        self.window = window
        self.navigation.beforePageChange = { [weak self] page in self?.changes.append(page) }
    }

    func close() {
        self.navigation.beforePageChange = nil
        self.window.contentView = nil
        self.window.close()
    }
}
