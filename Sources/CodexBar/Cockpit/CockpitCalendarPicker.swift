import AppKit
import SwiftUI

enum CockpitCalendarPickerStyle: Equatable {
    case segmented
    case popUp
}

/// Calendar-only native controls use explicit AppKit fonts because SwiftUI's native picker
/// ignores the surrounding Font on macOS. AppKit retains selection, keyboard and accessibility behavior.
@MainActor
struct CockpitCalendarPicker<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let choices: [Value]
    let title: (Value) -> String
    let label: String
    var style: CockpitCalendarPickerStyle = .segmented
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: self.$selection, choices: self.choices)
    }

    func makeNSView(context: Context) -> CockpitCalendarPickerHost {
        let host = CockpitCalendarPickerHost()
        self.updateNSView(host, context: context)
        return host
    }

    func updateNSView(_ host: CockpitCalendarPickerHost, context: Context) {
        context.coordinator.selection = self.$selection
        context.coordinator.choices = self.choices
        let font = NSFont.systemFont(ofSize: CockpitCalendarTypography.scaled(13))
        if host.style != self.style {
            let control: NSControl = switch self.style {
            case .segmented:
                NSSegmentedControl()
            case .popUp:
                NSPopUpButton(frame: .zero, pullsDown: false)
            }
            host.install(control, style: self.style)
        }
        guard let control = host.control else { return }
        control.controlSize = .regular
        control.font = font
        control.isEnabled = self.isEnabled
        control.target = context.coordinator
        control.setAccessibilityLabel(self.label)
        let labels = self.choices.map(self.title)
        let selected = self.choices.firstIndex(of: self.selection)
        if let segmented = control as? NSSegmentedControl {
            segmented.trackingMode = .selectOne
            segmented.segmentDistribution = .fillEqually
            segmented.segmentCount = labels.count
            for (index, title) in labels.enumerated() {
                segmented.setLabel(title, forSegment: index)
                segmented.setEnabled(self.isEnabled, forSegment: index)
            }
            segmented.selectedSegment = selected ?? -1
            segmented.action = #selector(Coordinator.segmentedChanged(_:))
        } else if let popUp = control as? NSPopUpButton {
            if popUp.itemTitles != labels {
                popUp.removeAllItems()
                popUp.addItems(withTitles: labels)
            }
            popUp.menu?.font = font
            if let selected {
                popUp.selectItem(at: selected)
            } else {
                popUp.select(nil)
            }
            popUp.action = #selector(Coordinator.popUpChanged(_:))
        }
        host.controlHeight = max(32, ceil(font.ascender - font.descender) + 10)
        control.invalidateIntrinsicContentSize()
        host.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: CockpitCalendarPickerHost,
        context: Context) -> CGSize?
    {
        let intrinsic = nsView.intrinsicContentSize
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? intrinsic.width
        return CGSize(width: width, height: intrinsic.height)
    }

    static func dismantleNSView(_ host: CockpitCalendarPickerHost, coordinator: Coordinator) {
        host.control?.target = nil
        host.control?.action = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var choices: [Value]

        init(selection: Binding<Value>, choices: [Value]) {
            self.selection = selection
            self.choices = choices
        }

        @objc func segmentedChanged(_ sender: NSSegmentedControl) {
            self.select(sender.selectedSegment)
        }

        @objc func popUpChanged(_ sender: NSPopUpButton) {
            self.select(sender.indexOfSelectedItem)
        }

        private func select(_ index: Int) {
            guard self.choices.indices.contains(index) else { return }
            let value = self.choices[index]
            if self.selection.wrappedValue != value { self.selection.wrappedValue = value }
        }
    }
}

@MainActor
final class CockpitCalendarPickerHost: NSView {
    private(set) var control: NSControl?
    private(set) var style: CockpitCalendarPickerStyle?
    var controlHeight: CGFloat = 32

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(0, self.control?.intrinsicContentSize.width ?? 0), height: self.controlHeight)
    }

    func install(_ control: NSControl, style: CockpitCalendarPickerStyle) {
        self.control?.removeFromSuperview()
        self.control = control
        self.style = style
        control.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            control.topAnchor.constraint(equalTo: self.topAnchor),
            control.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
        self.setAccessibilityElement(false)
    }
}
