import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import CodexBar
@testable import CodexBarCore

/// Manual acceptance only: the user must authorize reading this Mac's native Codex logs.
/// Run this suite alone with CODEXBAR_COCKPIT_LIVE_ACCEPTANCE=1 and an existing output directory.
/// No SettingsStore, UsageStore, PlanStore, account probe, network pricing refresh, or clipboard is used.
/// Artifacts contain real private usage and must remain outside the repository and any upload.
@MainActor
final class CockpitRealDataAcceptanceTests: XCTestCase {
    private static let output = URL(fileURLWithPath: "/private/tmp/codex-cockpit-live-validation/rendered")

    func test_authorizedNativeLedgerCalendarAndReceipt() async throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_LIVE_ACCEPTANCE"] == "1",
              let resource = try? Self.output.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              resource.isDirectory == true, resource.isSymbolicLink != true
        else {
            throw XCTSkip("Explicit live-data opt-in and the prepared private output directory are required.")
        }
        let priorLogLevel = CodexBarLog.currentLogLevel()
        CodexBarLog.bootstrapIfNeeded(.init(destination: .discard, level: .critical, json: false))
        CodexBarLog.setLogLevel(.critical)
        defer { CodexBarLog.setLogLevel(priorLogLevel) }
        let cache = Self.output.appendingPathComponent(".acceptance-cache-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: cache,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: cache) }
            let calendar = Calendar.current
            let now = Date()
            let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            let snapshot = try await Self.boundedSnapshot(home: home, cache: cache, calendar: calendar, now: now)
            XCTAssertTrue(!snapshot.daily.isEmpty, "The authorized source did not yield native usage history.")
            let model = SpendDashboardModel.build(
                inputs: [.init(id: "codex:this-mac", provider: .codex, displayName: "Codex", snapshot: snapshot)],
                requestedDays: 30,
                now: now,
                calendar: calendar)
            let rows = model.groups.filter { !$0.detailsExcludedFromTotals }.flatMap(\.sessions)
            let lineage = try await CockpitTaskLineageLoader.load(
                sources: rows.compactMap { row in
                    row.toolActivitySource.map {
                        CockpitTaskLineageSource(
                            identity: .init(sourceID: row.sourceID, sessionID: row.sessionID),
                            source: $0)
                    }
                },
                limits: .init(files: 1024, bytes: 4 * 1024 * 1024, lineBytes: 64 * 1024, duration: 2))
            let items = CockpitReceiptModel.items(
                model: model,
                hidePersonalInfo: true,
                metadata: lineage.metadata,
                conflicting: lineage.conflicting)
            XCTAssertTrue(!items.isEmpty, "The bounded source did not yield usable task rows.")
            guard !items.isEmpty else { return }
            let receipt = CockpitReceiptModel(
                items: Array(items.prefix(5)),
                scopeLabel: CockpitReceiptModel.scopeLabel(for: .rolling(days: 30), timeZone: calendar.timeZone))
            Self.checkReceipt(receipt, allItems: items, rows: rows, model: model, snapshot: snapshot)
            try Self.renderReceipt(receipt)
            try Self.renderCalendar(model: model, calendar: calendar, now: now)
            let status: [String: Bool] = [
                "hasNativeHistory": !snapshot.daily.isEmpty,
                "historyIsFullyScanned": snapshot.historyIsFullyScanned,
                "lineageWasLimited": lineage.wasLimited,
                "hasIncompleteLineage": items.contains(where: \.lineageIsPartial),
                "receiptRendered": true,
                "calendarRendered": true,
            ]
            try JSONEncoder().encode(status).write(
                to: Self.output.appendingPathComponent("acceptance-status.json"),
                options: .atomic)
        } catch {
            // Never expose parser errors, paths, identifiers, titles, or real usage in test output.
            XCTFail("Private native usage acceptance could not complete; inspect the local artifacts manually.")
        }
    }

    private static func boundedSnapshot(
        home: URL,
        cache: URL,
        calendar: Calendar,
        now: Date) async throws -> CostUsageTokenSnapshot
    {
        let options = CostUsageScanner.Options(
            codexSessionsRoot: home.appendingPathComponent("sessions"),
            cacheRoot: cache,
            calendar: calendar,
            maxCodexSessionFileBytes: 4 * 1024 * 1024,
            maxCodexScanBytesPerRefresh: 16 * 1024 * 1024,
            maxCodexScanDurationPerRefresh: 3)
        let fetcher = CostUsageFetcher(scannerOptions: options)
        // The scanner cooperatively cancels. The manual runner must also use a 90-second process watchdog
        // because synchronous filesystem or SQLite work cannot be forcibly interrupted by a Swift task.
        return try await withThrowingTaskGroup(of: CostUsageTokenSnapshot.self) { group in
            group.addTask {
                var latest: CostUsageTokenSnapshot?
                for _ in 0..<4 {
                    try Task.checkCancellation()
                    let snapshot = try await fetcher.loadTokenSnapshot(
                        provider: .codex,
                        environment: [:],
                        now: now,
                        codexHomePath: home.path,
                        historyDays: 30,
                        allowPricingRefresh: false,
                        refreshPricingInBackground: false,
                        includePiSessions: false,
                        bypassScannerDebounce: true,
                        calendar: calendar)
                    latest = snapshot
                    if !snapshot.sessions.isEmpty { return snapshot }
                }
                guard let latest else { throw PrivateAcceptanceError.incomplete }
                return latest
            }
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                throw PrivateAcceptanceError.deadline
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw PrivateAcceptanceError.incomplete }
            return result
        }
    }

    private static func checkReceipt(
        _ receipt: CockpitReceiptModel,
        allItems: [CockpitReceiptLine],
        rows: [SpendDashboardModel.SessionRow],
        model: SpendDashboardModel,
        snapshot: CostUsageTokenSnapshot)
    {
        XCTAssertTrue(receipt.items.count <= 5, "Receipt selection must remain bounded.")
        XCTAssertTrue(Set(receipt.items.map(\.id)).count == receipt.items.count, "Receipt task identities repeat.")
        let sourceIdentities = Set(rows.map { CockpitTaskIdentity(sourceID: $0.sourceID, sessionID: $0.sessionID) })
        XCTAssertTrue(
            allItems.reduce(0) { $0 + $1.sessionCount } == sourceIdentities.count,
            "Task grouping must account for every unique source session once.")
        for total in receipt.totals {
            let sourceRows = model.groups.filter { $0.currencyCode == total.currencyCode }.flatMap(\.sessions)
            if let selected = total.knownTokens,
               let source = CheckedSum.integers(sourceRows.compactMap(\.totalTokens))
            {
                XCTAssertTrue(selected <= source, "Receipt token subtotal exceeds the source session ledger.")
            }
            if let selected = total.knownCost,
               let source = SpendDashboardModel.safeCostSum(sourceRows.compactMap(\.totalCost))
            {
                XCTAssertTrue(selected <= source + 0.000001, "Receipt cost subtotal exceeds the source session ledger.")
            }
            if snapshot.historyScanIsPartial {
                XCTAssertTrue(total.tokensArePartial, "A partial native scan must retain its partial-token label.")
                XCTAssertTrue(total.costIsPartial, "A partial native scan must retain its partial-cost label.")
            }
            let selectedItems = receipt.items.filter { $0.currencyCode == total.currencyCode }
            if selectedItems.contains(where: { $0.estimatedCost == nil }) {
                XCTAssertTrue(total.costIsPartial, "Missing prices must not become a complete zero cost.")
            }
        }
    }

    private static func renderReceipt(_ receipt: CockpitReceiptModel) throws {
        guard let data = ShareStatsRenderer.pngData(for: receipt), NSBitmapImageRep(data: data) != nil else {
            throw PrivateAcceptanceError.render
        }
        try data.write(to: Self.output.appendingPathComponent("native-codex-receipt-private.png"), options: .atomic)
    }

    private static func renderCalendar(model: SpendDashboardModel, calendar: Calendar, now: Date) throws {
        let cells = CockpitCalendarProjection.cells(month: now, calendar: calendar).compactMap(\.self)
        let expectedDays = calendar.range(of: .day, in: .month, for: now)?.count
        XCTAssertTrue(cells.count == expectedDays, "The native month projection lost local calendar days.")
        XCTAssertTrue(Set(cells).count == cells.count, "The native month projection repeated a day.")
        let summaries = model.groups.flatMap(\.dailySummaries)
        let days = Dictionary(uniqueKeysWithValues: cells.map { day in
            let summary = summaries.first { calendar.isDate($0.day, inSameDayAs: day) }
            let tokens = summary?.hasPartialCounts == false ? summary?.totalTokens : nil
            return (day, CockpitCalendarDay(day: day, tokens: tokens, feeling: nil))
        })
        let view = VStack(alignment: .leading, spacing: 16) {
            Text("Codex · This Mac · Private Native Usage").font(.title2.weight(.semibold))
            Text(self.snapshotLabel(model)).font(.caption).foregroundStyle(.secondary)
            CockpitMonthGridView(calendar: calendar, month: now, selectedDay: now, days: days, select: { _ in })
        }
        .padding(28)
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light).background(Color.white))
        let size = CGSize(width: 960, height: 700)
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
        else { throw PrivateAcceptanceError.render }
        bitmap.size = size
        host.displayIgnoringOpacity(host.bounds, in: context)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw PrivateAcceptanceError.render
        }
        try data.write(to: Self.output.appendingPathComponent("native-codex-calendar-private.png"), options: .atomic)
    }

    private static func snapshotLabel(_ model: SpendDashboardModel) -> String {
        // This label contains no source identifiers, titles, paths, or actual usage.
        model.groups.contains { $0.modelHistoryCompleteness == .incomplete }
            ? "Partial local coverage; unavailable days remain unknown."
            : "Local calendar projection; unavailable days remain unknown."
    }

    private enum PrivateAcceptanceError: Error {
        case incomplete, deadline, render
    }
}
