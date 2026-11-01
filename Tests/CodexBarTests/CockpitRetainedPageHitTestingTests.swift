import AppKit
import Observation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct CockpitRetainedPageHitTestingTests {
    @Test
    func `retained calendar native picker does not cover the active statistics picker`() async throws {
        let state = RetainedPickerState()
        let host = NSHostingView(rootView: RetainedPickerFixture(state: state))
        host.frame = CGRect(x: 0, y: 0, width: 480, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        for page in [false, true, false] {
            state.calendarActive = page
            for _ in 0..<3 {
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(25))
            }
            let controls = Self.controls(in: host)
            let active = try #require(controls.first { $0.segmentCount == (page ? 2 : 5) })
            let point = active.convert(CGPoint(x: active.bounds.midX, y: active.bounds.midY), to: host)
            let hit = try #require(host.hitTest(point))
            #expect(
                hit === active || hit.isDescendant(of: active),
                "Active page: \(page ? "calendar" : "statistics"), hit: \(type(of: hit))")
        }
    }

    private static func controls(in view: NSView) -> [NSSegmentedControl] {
        (view as? NSSegmentedControl).map { [$0] } ?? view.subviews.flatMap { Self.controls(in: $0) }
    }
}

@MainActor @Observable
private final class RetainedPickerState {
    var calendarActive = false
    var selectedRange = 0
    var calendarMetric = 0
}

@MainActor
private struct RetainedPickerFixture: View {
    @Bindable var state: RetainedPickerState

    var body: some View {
        ZStack {
            Picker("Range", selection: self.$state.selectedRange) {
                ForEach(0..<5) { Text("Range \($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .opacity(self.state.calendarActive ? 0 : 1)
            .allowsHitTesting(!self.state.calendarActive)
            .accessibilityHidden(self.state.calendarActive)
            CockpitCalendarPicker(
                selection: self.$state.calendarMetric,
                choices: [0, 1],
                title: { "Calendar \($0)" },
                label: "Calendar metric")
                .opacity(self.state.calendarActive ? 1 : 0)
                .allowsHitTesting(self.state.calendarActive)
                .accessibilityHidden(!self.state.calendarActive)
        }
        .frame(width: 440, height: 80)
    }
}
