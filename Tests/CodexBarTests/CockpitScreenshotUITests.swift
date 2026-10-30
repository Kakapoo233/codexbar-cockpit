import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

/// Optional visual proof uses synthetic data only and never initializes a provider or SettingsStore.
struct CockpitScreenshotUITests {
    @Test
    @MainActor
    func `render synthetic native panels and a partial multi currency receipt`() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_PROOF_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            try Self.renderReceipt(to: directory)
            try Self.renderPanels(to: directory)
        }
    }

    @MainActor
    private static func renderReceipt(to directory: URL) throws {
        let items = [
            CockpitReceiptLine(
                id: "synthetic-a",
                title: "整理系外行星论文阅读笔记与模型结果：一个较长的中文任务标题测试",
                providerName: "Codex",
                currencyCode: "USD",
                tokens: 1_234_567,
                estimatedCost: 12.5,
                tokensArePartial: false,
                costIsPartial: false,
                sessionCount: 3),
            CockpitReceiptLine(
                id: "synthetic-b",
                title: "修复统计口径并保留未知模型的已知金额",
                providerName: "Codex",
                currencyCode: "USD",
                tokens: 85000,
                estimatedCost: nil,
                tokensArePartial: false,
                costIsPartial: true,
                lineageIsPartial: true),
            CockpitReceiptLine(
                id: "synthetic-c",
                title: "独立币种测试：中文任务列表与金额展示",
                providerName: "Claude",
                currencyCode: "EUR",
                tokens: 620_000,
                estimatedCost: 4.75,
                tokensArePartial: true,
                costIsPartial: false),
        ]
        let receipt = CockpitReceiptModel(
            items: items,
            createdAt: Self.now,
            scopeLabel: CockpitReceiptModel.scopeLabel(for: .rolling(days: 7), timeZone: Self.calendar.timeZone))
        let png = try #require(ShareStatsRenderer.pngData(for: receipt))
        try png.write(to: directory.appendingPathComponent("cockpit-receipt-partial-zh.png"))
    }

    @MainActor
    private static func renderPanels(to directory: URL) throws {
        var state = CockpitPlanState()
        let midnight = Self.calendar.startOfDay(for: Self.now)
        _ = state.record(CockpitQuotaSnapshot(
            providerID: "codex",
            accountID: "synthetic-quota-account",
            capturedAt: midnight,
            remainingPercent: 100,
            resetsAt: midnight.addingTimeInterval(5 * 86400)), calendar: Self.calendar)
        _ = state.record(CockpitQuotaSnapshot(
            providerID: "codex",
            accountID: "synthetic-quota-account",
            capturedAt: Self.now,
            remainingPercent: 88,
            resetsAt: midnight.addingTimeInterval(5 * 86400)), calendar: Self.calendar)
        for index in 0..<8 {
            let date = try #require(Self.calendar.date(byAdding: .day, value: -index, to: Self.now))
            state.recordComfort(
                index.isMultiple(of: 3) ? .light : .comfortable,
                providerID: "codex",
                accountID: "local-machine",
                on: date,
                totalTokens: (index + 1) * 200_000,
                coverage: .complete,
                calendar: Self.calendar)
        }
        let status = state.status(
            providerID: "codex",
            accountID: "synthetic-quota-account",
            on: Self.now,
            calendar: Self.calendar)
        let comfort = CockpitComfortModel.build(
            records: state.comfortRecords,
            providerID: "codex",
            accountID: "local-machine",
            now: Self.now,
            calendar: Self.calendar)
        let overview = VStack(alignment: .leading, spacing: 22) {
            Text("CodexBar Cockpit · 合成数据预览").font(.title2.weight(.semibold))
            CockpitPlanSummaryView(status: status)
            Text(L("cockpit_ui_local_experience")).font(.headline)
            Text(L("cockpit_ui_local_experience_note")).font(.caption).foregroundStyle(.secondary)
            CockpitComfortChartView(model: comfort, records: state.comfortRecords)
        }
        .padding(28)
        let overviewPNG = try #require(Self.pngData(overview, size: CGSize(width: 960, height: 760)))
        try overviewPNG.write(to: directory.appendingPathComponent("cockpit-overview-zh.png"))

        let cells = CockpitCalendarProjection.cells(month: Self.now, calendar: Self.calendar).compactMap(\.self)
        let days = Dictionary(uniqueKeysWithValues: cells.map { day in
            let number = Self.calendar.component(.day, from: day)
            return (day, CockpitCalendarDay(
                day: day,
                tokens: number <= 29 ? number * 100_000 : nil,
                feeling: number.isMultiple(of: 4) ? .comfortable : nil))
        })
        let month = VStack(alignment: .leading, spacing: 18) {
            Text("2026 年 10 月 · 合成数据预览").font(.title2.weight(.semibold))
            Text(L("cockpit_ui_local_experience_note")).font(.caption).foregroundStyle(.secondary)
            CockpitMonthGridView(
                calendar: Self.calendar,
                month: Self.now,
                selectedDay: Self.now,
                days: days,
                select: { _ in })
            CockpitCalendarStatusEditor(
                selected: .comfortable,
                canRecord: true,
                errorMessage: nil,
                onSelect: { _ in },
                onClear: {})
        }
        .padding(28)
        let monthPNG = try #require(Self.pngData(month, size: CGSize(width: 960, height: 940)))
        try monthPNG.write(to: directory.appendingPathComponent("cockpit-calendar-zh.png"))
    }

    @MainActor
    private static func pngData(_ view: some View, size: CGSize) -> Data? {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "zh_Hans_CN")).background(Color.white))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        bitmap.size = size
        host.displayIgnoringOpacity(host.bounds, in: context)
        return bitmap.representation(using: .png, properties: [:])
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        return calendar
    }

    private static var now: Date {
        self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 18))!
    }
}
