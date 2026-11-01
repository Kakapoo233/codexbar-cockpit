import AppKit
import Observation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct CockpitCalendarPickerTests {
    @Test(arguments: [false, true])
    func `native calendar choices retain original type and write back to the binding`(popUp: Bool) async throws {
        try await Self.withPicker(style: popUp ? .popUp : .segmented) { host, selection in
            let control = try #require(Self.findControl(in: host))
            #expect(control.font?.pointSize == 13)
            #expect(control.frame.height >= 24)
            #expect(control.accessibilityLabel() == "Synthetic calendar scale")
            if let popUp = control as? NSPopUpButton {
                #expect(popUp.menu?.font.pointSize == 13)
                #expect(popUp.indexOfSelectedItem == 0)
                popUp.selectItem(at: 2)
            } else {
                let segmented = try #require(control as? NSSegmentedControl)
                #expect(segmented.selectedSegment == 0)
                segmented.selectedSegment = 2
            }
            let action = try #require(control.action)
            let target = try #require(control.target)
            let handled = control.sendAction(action, to: target)
            #expect(handled)
            #expect(selection.value == 2)

            selection.value = 1
            try await Self.settle(host)
            let updated = try #require(Self.findControl(in: host))
            if let popUp = updated as? NSPopUpButton {
                #expect(popUp.indexOfSelectedItem == 1)
            } else {
                let segmented = try #require(updated as? NSSegmentedControl)
                #expect(segmented.selectedSegment == 1)
            }
            #expect(updated.font?.pointSize == 13)
        }
    }

    @Test(arguments: [false, true])
    func `an unrepresented selection and empty native action do not choose another value`(popUp: Bool) async throws {
        try await Self.withPicker(style: popUp ? .popUp : .segmented) { host, selection in
            selection.value = 99
            try await Self.settle(host)
            let control = try #require(Self.findControl(in: host))
            if let popUp = control as? NSPopUpButton {
                #expect(popUp.indexOfSelectedItem == -1)
            } else {
                let segmented = try #require(control as? NSSegmentedControl)
                #expect(segmented.selectedSegment == -1)
            }
            let action = try #require(control.action)
            let target = try #require(control.target)
            let handled = control.sendAction(action, to: target)
            #expect(handled)
            #expect(selection.value == 99)
        }
    }

    private static func withPicker(
        style: CockpitCalendarPickerStyle,
        body: (NSHostingView<CalendarPickerFixtureView>, CalendarPickerSelectionFixture) async throws
            -> Void) async throws
    {
        let selection = CalendarPickerSelectionFixture()
        let host = NSHostingView(rootView: CalendarPickerFixtureView(selection: selection, style: style))
        host.frame = CGRect(x: 0, y: 0, width: 440, height: 70)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        try await Self.settle(host)
        try await body(host, selection)
    }

    private static func settle(_ host: NSView) async throws {
        for _ in 0..<3 {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func findControl(in view: NSView) -> NSControl? {
        if let control = view as? NSSegmentedControl { return control }
        if let control = view as? NSPopUpButton { return control }
        for child in view.subviews {
            if let control = Self.findControl(in: child) { return control }
        }
        return nil
    }
}

@MainActor
@Observable
private final class CalendarPickerSelectionFixture {
    var value = 0
}

@MainActor
private struct CalendarPickerFixtureView: View {
    @Bindable var selection: CalendarPickerSelectionFixture
    let style: CockpitCalendarPickerStyle

    var body: some View {
        CockpitCalendarPicker(
            selection: self.$selection.value,
            choices: [0, 1, 2],
            title: { ["Day", "Week", "Month"][$0] },
            label: "Synthetic calendar scale",
            style: self.style)
            .frame(width: 400)
    }
}
