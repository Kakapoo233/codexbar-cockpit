import AppKit
import SwiftUI

/// Calendar-only type sizes: enlarge the native text styles without scaling or blurring the whole panel.
enum CockpitCalendarTypography {
    static let scale: CGFloat = 1.5

    static var body: Font {
        self.font(.body)
    }

    static var callout: Font {
        self.font(.callout)
    }

    static var caption: Font {
        self.font(.caption1)
    }

    static var caption2: Font {
        self.font(.caption2)
    }

    static var headline: Font {
        self.font(.headline, weight: .bold)
    }

    static var subheadline: Font {
        self.font(.subheadline)
    }

    static var title3: Font {
        self.font(.title3)
    }

    static var smallControl: Font {
        self.font(size: NSFont.smallSystemFontSize)
    }

    static func scaled(_ size: CGFloat) -> CGFloat { size * self.scale }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: self.scaled(size), weight: weight)
    }

    private static func font(_ style: NSFont.TextStyle, weight: Font.Weight = .regular) -> Font {
        self.font(size: NSFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
    }
}
