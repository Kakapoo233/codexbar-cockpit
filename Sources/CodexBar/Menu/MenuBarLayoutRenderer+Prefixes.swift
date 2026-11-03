import AppKit
import CodexBarCore
import Foundation

/// Keep compact status-item identifiers separate from values, colors and spoken descriptions.
extension MenuBarLayoutRenderer {
    static func labelStatusItem(
        _ rendered: (value: NSAttributedString, accessibilityText: String?),
        token: MenuBarLayoutToken,
        data: MenuBarLayoutRenderData,
        options: MenuBarLayoutRenderOptions,
        attributes: [NSAttributedString.Key: Any])
        -> (value: NSAttributedString, accessibilityText: String?)
    {
        // Some balance-backed providers use resetDescription to carry their funded balance.
        // When it is the only visible fallback, it remains money rather than a reset timestamp.
        if token.resetWindow == .automatic, let balance = data.automaticText,
           data.automatic?.resetsAt == nil, data.automatic?.resetDescription == balance
        {
            return rendered
        }
        let metric: String?
        let window: PercentWindow?
        switch token {
        case .percent(window: .automatic), .progressBar(window: .automatic), .usageBar:
            metric = nil
            window = .automatic
        case let .pace(selection):
            metric = "P"
            window = selection
        case .resetCountdown, .resetAbsolute, .windowResetCountdown, .windowResetAbsolute:
            metric = "R"
            window = token.resetWindow ?? .automatic
        case .runsOut, .runsOutCompact:
            metric = "E"
            window = nil
        default: return rendered
        }
        let label = window.flatMap { selection -> (short: String, full: String)? in
            if selection == .automatic { return self.automaticWindowLabel(data: data) }
            guard selection != .spend else { return nil }
            return (self.windowPrefix(selection, data: data), self.windowAccessibilityLabel(selection, data: data))
        }
        let prefix = [metric, label?.short].compactMap(\.self).joined(separator: " ")
        let accessibility = window == .automatic && label?.full != L("Usage")
            ? label.flatMap { label in rendered.accessibilityText.map { L("%@: %@", label.full, $0) } }
            ?? rendered.accessibilityText
            : rendered.accessibilityText
        return (
            self.prefixedValue(
                options.showWindowLabels ? prefix : "",
                value: rendered.value,
                attributes: attributes),
            accessibility)
    }

    static func automaticWindowLabel(data: MenuBarLayoutRenderData) -> (short: String, full: String)? {
        guard data.automaticText == nil else { return nil }
        guard let automatic = data.automatic else { return ("U", L("Usage")) }
        let semantic: [PercentWindow] = [.session, .weekly, .scopedWeekly]
        let lanes: [MenuBarLayoutLane] = [.primary, .secondary, .tertiary]
        let extras = data.extraRateWindows.filter { data.extraTitle($0.id) != nil }
        // Match the complete selected window, never its percentage or formatted pace alone.
        let matches = semantic.filter { self.window($0, data: data) == automatic }
        let laneMatches = lanes.filter { self.laneWindow($0, data: data) == automatic }
        let extraMatches = extras.filter { $0.window == automatic }
        let fallback = (MenuBarDisplayText.periodPrefix(windowMinutes: automatic.windowMinutes), L("Usage"))
        guard laneMatches.count + extraMatches.count <= 1 else { return fallback }
        if matches.count == 1, let selected = matches.first {
            return (self.windowPrefix(selected, data: data), self.windowAccessibilityLabel(selected, data: data))
        }
        guard matches.isEmpty else { return fallback }
        if laneMatches.count == 1, let lane = laneMatches.first {
            let title = data.laneLabels.label(for: lane)
            let short = self.laneShortLabel(lane, data: data)
                ?? self.englishInitial(title, fallback: fallback.0)
            return (short, title)
        }
        guard laneMatches.isEmpty else { return fallback }
        guard extraMatches.count == 1, let extra = extraMatches.first, let title = data.extraTitle(extra.id)
        else { return fallback }
        let short = ProviderDescriptorRegistry.descriptor(for: data.provider).menuBarMetrics
            .namedExtraShortLabels[extra.id] ?? title
        return (short, title)
    }

    static func prefixedValue(
        _ prefix: String,
        value: NSAttributedString,
        attributes: [NSAttributedString.Key: Any]) -> NSAttributedString
    {
        guard !prefix.isEmpty else { return value }
        let result = NSMutableAttributedString(string: "\(prefix) ", attributes: attributes)
        result.addAttribute(self.windowPrefixKey, value: true, range: NSRange(location: 0, length: result.length))
        result.append(value)
        return result
    }

    static func windowPrefix(
        _ window: PercentWindow,
        data: MenuBarLayoutRenderData,
        showWindowLabels: Bool = true) -> String
    {
        let taggedPrefix = Self.taggedSemanticLane(window, data: data)
            .flatMap { Self.laneShortLabel($0, data: data) }
        // Named lanes identify distinct allowances; Spend's currency is not a window label.
        if let taggedPrefix { return taggedPrefix }
        guard showWindowLabels || window == .spend else { return "" }
        return switch window {
        case .session:
            MenuBarTextLanguage.withEnglish(enabled: true) {
                let fallback = self.window(window, data: data).map {
                    MenuBarDisplayText.periodPrefix(windowMinutes: $0.windowMinutes)
                } ?? "S"
                return self.englishInitial(self.primaryLabel(data: data), fallback: fallback)
            }
        case .weekly:
            MenuBarTextLanguage.withEnglish(enabled: true) {
                let fallback = self.window(window, data: data).map {
                    MenuBarDisplayText.periodPrefix(windowMinutes: $0.windowMinutes)
                } ?? "W"
                return self.englishInitial(
                    PercentWindow.weekly.providerLabel(provider: data.provider), fallback: fallback)
            }
        case .scopedWeekly:
            self.englishInitial(data.scopedWeeklyTitle, fallback: "F")
        case .automatic:
            ""
        case .spend:
            data.spendCurrencySymbol
        }
    }

    private static func englishInitial(_ title: String?, fallback: String) -> String {
        guard let first = title?.uppercased().first, first.isASCII, first.isLetter else { return fallback }
        return String(first)
    }

    static func windowAccessibilityLabel(_ window: PercentWindow, data: MenuBarLayoutRenderData) -> String {
        if let lane = self.taggedSemanticLane(window, data: data) {
            return data.laneLabels.label(for: lane)
        }
        return switch window {
        case .session: self.primaryLabel(data: data) ?? L("Session")
        case .weekly: PercentWindow.weekly.providerLabel(provider: data.provider) ?? L("Weekly")
        case .scopedWeekly: data.scopedWeeklyTitle ?? L("Scoped weekly")
        case .automatic: L("Usage")
        case .spend: L("Spend")
        }
    }

    static func primaryLabel(data: MenuBarLayoutRenderData) -> String? {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: data.provider)
        if let label = descriptor.presentation.menuBarLayoutPrimaryLabel { return L(label) }
        let lane: MenuBarLayoutLane = descriptor.presentation.primarySemanticWindow == .session ? .primary : .secondary
        let label = data.laneLabels.label(for: lane)
        let renamedTaggedLane = !descriptor.menuBarMetrics.laneShortLabels.isEmpty
            && label != MenuBarLayoutLaneLabels(provider: data.provider, snapshot: nil).label(for: lane)
        guard (descriptor.metadata.usesDetailBackedWindow && data.session?.windowMinutes == nil) || renamedTaggedLane
        else { return nil }
        return label
    }

    static func laneShortLabel(_ lane: MenuBarLayoutLane, data: MenuBarLayoutRenderData) -> String? {
        let labels = ProviderDescriptorRegistry.descriptor(for: data.provider).menuBarMetrics.laneShortLabels
        guard !labels.isEmpty else { return nil }
        let staticLabels = MenuBarLayoutLaneLabels(provider: data.provider, snapshot: nil)
        guard data.laneLabels.label(for: lane) == staticLabels.label(for: lane) else { return nil }
        return switch lane {
        case .primary: labels[.primary]
        case .secondary: labels[.secondary]
        case .tertiary: labels[.tertiary]
        }
    }

    static func taggedSemanticLane(
        _ window: PercentWindow,
        data: MenuBarLayoutRenderData) -> MenuBarLayoutLane?
    {
        let presentation = ProviderDescriptorRegistry.descriptor(for: data.provider).presentation
        let primaryWindow = PercentWindow.forSemanticWindow(presentation.primarySemanticWindow)
        let lane: MenuBarLayoutLane? = if window == primaryWindow {
            .primary
        } else if window == PercentWindow.forSemanticWindow(presentation.secondarySemanticWindow) {
            .secondary
        } else {
            nil
        }
        guard let lane, self.laneShortLabel(lane, data: data) != nil else { return nil }
        return lane
    }
}
