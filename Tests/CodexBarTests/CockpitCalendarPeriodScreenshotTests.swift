import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

/// Opt-in visual proof of the real period components, with synthetic ledger rows only.
@MainActor
struct CockpitCalendarPeriodScreenshotTests {
    @Test
    func `render calendar scales with missing multi currency history at wide and narrow widths`() async throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_PROOF_DIR"],
              !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12)))
        let ledger = try Self.ledger(calendar: calendar, now: now)
        try await CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            for scale in CockpitCalendarScale.allCases {
                for width in [CGFloat(600), 960] {
                    let view = Self.preview(ledger: ledger, calendar: calendar, now: now, scale: scale)
                    let height: CGFloat = switch scale {
                    case .day, .week: 1050
                    case .month: 1400
                    case .quarter, .year: 1800
                    }
                    let png = try #require(await Self.pngData(view, size: CGSize(width: width, height: height)))
                    let name = "cockpit-calendar-\(scale.rawValue)-cost-zh-\(Int(width)).png"
                    try png.write(to: directory.appendingPathComponent(name))
                }
            }
        }
    }

    private static func preview(
        ledger: CockpitCalendarLedger,
        calendar: Calendar,
        now: Date,
        scale: CockpitCalendarScale) -> some View
    {
        let period = CockpitCalendarPeriod(containing: now, scale: scale, calendar: calendar)
        let visibleDays = Set(CockpitCalendarProjection.cells(month: now, calendar: calendar).compactMap(\.self)
            + period.days(calendar: calendar))
        let days = Dictionary(uniqueKeysWithValues: visibleDays.map { day in
            let number = calendar.component(.day, from: day)
            return (day, CockpitCalendarDay(
                day: day,
                tokens: ledger.tokens(on: day).total,
                feeling: number == 30 ? .overloaded : number.isMultiple(of: 4) ? .comfortable : nil,
                resetKinds: number == 30 ? [.regular, .banked, .unknown("synthetic")]
                    : number == 28 ? [.regular] : [],
                hasResetForecast: number == 30 || number == 31,
                hasScheduledReset: number == 30 || number == 1))
        })
        return VStack(alignment: .leading, spacing: 16) {
            Text("CodexBar Cockpit · 合成数据预览").font(.caption).foregroundStyle(.secondary)
            CockpitCalendarToolbar(
                title: period.title(calendar: calendar),
                scale: .constant(scale),
                metric: .constant(.cost),
                previous: {},
                today: {},
                next: {})
            Divider()
            if scale != .month {
                CockpitCalendarPeriodView(
                    ledger: ledger, period: period, metric: .cost, selectedDay: now, select: { _ in }, days: days)
            }
            if [.month, .quarter, .year].contains(scale) {
                if scale != .month { Text(L("cockpit_calendar_month")).font(.headline) }
                CockpitMonthGridView(
                    calendar: calendar,
                    month: now,
                    selectedDay: now,
                    days: days,
                    select: { _ in },
                    compact: true,
                    metricText: { ledger.text(on: $0, metric: .cost) })
            }
            CockpitCalendarPeriodSummaryView(ledger: ledger, period: period, metric: .cost)
            CockpitCalendarStatusEditor(
                selected: .comfortable,
                canRecord: true,
                onSelect: { _ in },
                onClear: {},
                compact: true)
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private static func ledger(calendar: Calendar, now: Date) throws -> CockpitCalendarLedger {
        let groups = try ["USD", "EUR"].enumerated().map { index, currency in
            let rows = try (0..<90).filter { !$0.isMultiple(of: 11) }.map { offset in
                let day = try #require(calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)))
                let amount = Double((offset % 9 + 1) * (index + 1)) / 5
                let partial = offset.isMultiple(of: 13)
                return SpendDashboardModel.DailySummary(
                    day: day,
                    providers: [.init(
                        costIsLowerBound: partial,
                        countsAreLowerBound: partial,
                        sourceID: "synthetic-\(currency)",
                        provider: index == 0 ? .codex : .claude,
                        displayName: "Synthetic \(currency)",
                        totalTokens: (offset + 1) * 1000,
                        requestCount: 1,
                        totalCost: amount)],
                    totalTokens: (offset + 1) * 1000,
                    requestCount: 1,
                    totalCost: amount)
            }
            return SpendDashboardModel.CurrencyGroup(
                currencyCode: currency,
                providers: [],
                models: [],
                dailyPoints: [],
                dailySummaries: rows,
                totalTokens: nil,
                totalCost: nil,
                coveredDayCount: rows.count,
                chartDomain: now...now,
                modelHistoryCompleteness: .incomplete)
        }
        return CockpitCalendarLedger(
            model: SpendDashboardModel(requestedDays: 365, groups: groups), calendar: calendar, now: now)
    }

    private static func pngData(_ view: some View, size: CGSize) async throws -> Data? {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "zh_Hans_CN")).background(Color.white))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        for _ in 0..<3 {
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
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
}
