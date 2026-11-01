import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

/// Opt-in layout proof using the same recent observations for three different date axes.
@MainActor
struct SpendPlanHistoryTimelineScreenshotTests {
    @Test
    func `render recent quota observations on seven thirty and ninety day axes`() async throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_PROOF_DIR"],
              !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z"))
        let reset = now.addingTimeInterval(86400)
        let offsets: [Double] = [26, 25, 24, 2, 1, 0]
        let entries = offsets.enumerated().map { index, hours in
            PlanUtilizationHistoryEntry(
                capturedAt: now.addingTimeInterval(-hours * 3600),
                usedPercent: Double(10 + index * 10),
                resetsAt: reset)
        }
        let history = PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: entries)
        try await CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            for days in [7, 30, 90] {
                for width in [CGFloat(600), 920] {
                    let view = VStack(alignment: .leading, spacing: 12) {
                        Text(spendDashboardDayRangeText(days)).font(.title2.weight(.semibold))
                        SpendPlanHistoryTimelineView(
                            provider: .codex,
                            histories: [history],
                            period: .rolling(days: days),
                            referenceDate: now,
                            calendar: calendar)
                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    let png = try await Self.pngData(view, size: CGSize(width: width, height: 460))
                    try png.write(to: directory.appendingPathComponent("quota-\(days)d-\(Int(width)).png"))
                }
            }
        }
    }

    private static func pngData(_ view: some View, size: CGSize) async throws -> Data {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
            .frame(width: size.width, height: size.height)
            .background(Color.white))
        renderer.scale = 1
        let rendered = try #require(renderer.nsImage)
        let tiff = try #require(rendered.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        var visiblePixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.5,
                   min(color.redComponent, color.greenComponent, color.blueComponent) < 0.8
                {
                    visiblePixels += 1
                }
            }
        }
        try #require(visiblePixels > 20, "The quota preview must contain rendered content, not a blank bitmap")
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
