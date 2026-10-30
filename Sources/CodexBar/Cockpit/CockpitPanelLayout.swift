import Foundation

/// Shared by the SwiftUI columns and the fixed-width AppKit menu card builders.
struct CockpitPanelLayout {
    static let preferredSize = CGSize(width: 960, height: 700)
    static let contentInset: CGFloat = 16
    static let columnSpacing: CGFloat = 16
    static let sidebarWidth: CGFloat = 280
    static let sidebarBreakpoint: CGFloat = 800
    private static let submenuIndicatorWidth: CGFloat = 24

    let width: CGFloat

    var usesSidebar: Bool {
        self.width >= Self.sidebarBreakpoint
    }

    var mainColumnWidth: CGFloat {
        max(
            0,
            self.width - Self.contentInset * 2
                - (self.usesSidebar ? Self.sidebarWidth + Self.columnSpacing : 0))
    }

    var menuCardWidth: CGFloat {
        max(1, self.mainColumnWidth - Self.submenuIndicatorWidth)
    }

    static func boundedSize(available: CGSize) -> CGSize {
        CGSize(
            width: min(self.preferredSize.width, max(1, available.width - 24)),
            height: min(self.preferredSize.height, max(1, available.height - 40)))
    }
}
