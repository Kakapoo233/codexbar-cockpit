import AppKit
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct CockpitProjectionUITests {
    @Test
    func `calendar state editing permits past and the whole current day but rejects future local days`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9)))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let tonight = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 23)))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        #expect(CockpitCalendarProjection.canRecord(on: yesterday, now: now, calendar: calendar))
        #expect(CockpitCalendarProjection.canRecord(on: tonight, now: now, calendar: calendar))
        #expect(!CockpitCalendarProjection.canRecord(on: tomorrow, now: now, calendar: calendar))
    }

    @Test
    func `calendar selected status is isolated by provider day time zone and machine scope`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12)))
        let key = CockpitCalendar.dateKey(for: day, calendar: calendar)
        func record(
            provider: String,
            account: String = "local-machine",
            dateKey: String? = nil,
            timeZone: String? = nil,
            feeling: CockpitFeeling,
            order: TimeInterval = 0) -> CockpitComfortRecord
        {
            CockpitComfortRecord(
                providerID: provider,
                accountID: account,
                localDateKey: dateKey ?? key,
                timeZoneIdentifier: timeZone ?? calendar.timeZone.identifier,
                recordedAt: day.addingTimeInterval(order),
                feeling: feeling,
                totalTokens: nil,
                coverage: .partial)
        }
        let records = [
            record(provider: "codex", feeling: .comfortable),
            record(provider: "codex", feeling: .overloaded, order: 1),
            record(provider: "claude", feeling: .light),
            record(provider: "codex", account: "quota-account", feeling: .light, order: 3),
            record(provider: "codex", dateKey: "2026-10-28", feeling: .light, order: 4),
            record(provider: "codex", timeZone: "Asia/Shanghai", feeling: .light, order: 5),
        ]
        #expect(CockpitCalendarProjection.feeling(
            on: day,
            providerID: "codex",
            records: records,
            calendar: calendar) == .overloaded)
        #expect(CockpitCalendarProjection.feeling(
            on: day,
            providerID: "claude",
            records: records,
            calendar: calendar) == .light)
        let withoutCodexLocalDay = records.filter {
            !($0.providerID == "codex" && $0.accountID == "local-machine"
                && $0.localDateKey == key && $0.timeZoneIdentifier == calendar.timeZone.identifier)
        }
        #expect(CockpitCalendarProjection.feeling(
            on: day,
            providerID: "codex",
            records: withoutCodexLocalDay,
            calendar: calendar) == nil)
        #expect(CockpitCalendarProjection.feeling(
            on: day,
            providerID: "claude",
            records: withoutCodexLocalDay,
            calendar: calendar) == .light)
    }

    @Test
    func `month cells preserve every local day across DST with Monday first`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        calendar.firstWeekday = 2
        let month = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)))
        let cells = CockpitCalendarProjection.cells(month: month, calendar: calendar)
        let days = cells.compactMap(\.self)
        #expect(cells.count.isMultiple(of: 7))
        #expect(days.count == 31)
        #expect(days.map { calendar.component(.day, from: $0) } == Array(1...31))
        #expect(cells.prefix(6).allSatisfy { $0 == nil })
        #expect(Set(days).count == days.count)
        let durations = zip(days, days.dropFirst()).map { $1.timeIntervalSince($0) }
        #expect(durations.contains(23 * 3600))
    }

    @Test
    func `receipt deduplicates identity but preserves equal titles and separate currencies`() {
        let first = Self.line(id: "a", currency: "USD", tokens: 30, cost: 1)
        let second = Self.line(id: "b", currency: "USD", tokens: 20, cost: 2)
        let euro = Self.line(id: "c", currency: "EUR", tokens: 10, cost: 4)
        let receipt = CockpitReceiptModel(items: [first, first, second, euro])
        #expect(receipt.items.count == 3)
        #expect(receipt.totals.map(\.currencyCode) == ["EUR", "USD"])
        #expect(receipt.totals.last?.knownCost == 3)
        #expect(receipt.totals.last?.knownTokens == 50)
    }

    @Test
    func `unavailable metrics stay unknown while genuine zero survives`() {
        let unknown = CockpitReceiptModel(items: [Self.line(id: "unknown", tokens: nil, cost: nil)])
        #expect(unknown.totals.first?.knownTokens == nil)
        #expect(unknown.totals.first?.knownCost == nil)
        let mixed = CockpitReceiptModel(items: [
            Self.line(id: "zero", tokens: 0, cost: 0),
            Self.line(id: "unknown", tokens: nil, cost: nil),
        ])
        #expect(mixed.totals.first?.knownTokens == 0)
        #expect(mixed.totals.first?.knownCost == 0)
        #expect(mixed.totals.first?.tokensArePartial == true)
        #expect(mixed.totals.first?.costIsPartial == true)
    }

    @Test
    func `overflow cannot produce a false receipt total`() {
        let receipt = CockpitReceiptModel(items: [
            Self.line(id: "max", tokens: Int.max, cost: Double.greatestFiniteMagnitude),
            Self.line(id: "plus", tokens: 1, cost: Double.greatestFiniteMagnitude),
        ])
        #expect(receipt.totals.first?.knownTokens == nil)
        #expect(receipt.totals.first?.knownCost == nil)
        #expect(receipt.totals.first?.tokensArePartial == true)
        #expect(receipt.totals.first?.costIsPartial == true)
    }

    @Test
    func `subagents join root once while ordinary forks remain independent`() throws {
        let root = Self.row(session: "root", tokens: 100, cost: 1)
        let child = Self.row(session: "child", tokens: 40, cost: 0.5)
        let fork = Self.row(session: "fork", tokens: 20, cost: 0.25)
        let metadata: [CockpitTaskIdentity: CockpitTaskLineageMetadata] = [
            Self.identity("root"): .init(sessionID: "root"),
            Self.identity("child"): .init(sessionID: "child", parentThreadID: "root", isSubagent: true),
            Self.identity("fork"): .init(sessionID: "fork", forkedFromID: "root"),
        ]
        let lines = CockpitReceiptModel.items(
            model: Self.model(rows: [root, child, child, fork]),
            hidePersonalInfo: false,
            metadata: metadata)
        #expect(lines.count == 2)
        let combined = try #require(lines.first { $0.sessionCount == 2 })
        #expect(combined.tokens == 140)
        #expect(combined.estimatedCost == 1.5)
        #expect(!combined.lineageIsPartial)
        let receipt = CockpitReceiptModel(items: lines)
        #expect(receipt.totals.first?.knownTokens == 160)
        #expect(receipt.totals.first?.knownCost == 1.75)
    }

    @Test
    func `missing lineage is visible and retained source details cannot enter a receipt`() throws {
        let rows = [Self.row(session: "unknown", tokens: 100, cost: 1)]
        let lines = CockpitReceiptModel.items(model: Self.model(rows: rows), hidePersonalInfo: false)
        #expect(try #require(lines.first).lineageIsPartial)
        var group = try #require(Self.model(rows: rows).groups.first)
        group.detailsExcludedFromTotals = true
        let stale = SpendDashboardModel(requestedDays: 30, groups: [group])
        #expect(CockpitReceiptModel.items(model: stale, hidePersonalInfo: false).isEmpty)
    }

    @Test
    func `privacy hides session titles and account labels in the export projection`() throws {
        var row = Self.row(session: "root", tokens: 100, cost: 1)
        row.sourceName = "private@example.com"
        let lines = CockpitReceiptModel.items(model: Self.model(rows: [row]), hidePersonalInfo: true)
        let line = try #require(lines.first)
        #expect(!line.title.contains("Private project"))
        #expect(!line.providerName.contains("private@example.com"))
    }

    @Test
    func `non native sessions do not require Codex rollout metadata`() throws {
        let row = Self.row(session: "proxy", tokens: 100, cost: 1)
        let model = Self.model(rows: [row], sourceKind: .openCodex)
        let lines = CockpitReceiptModel.items(model: model, hidePersonalInfo: false)
        #expect(try #require(lines.first).lineageIsPartial == false)
    }

    @Test
    func `local comfort accepts only fresh complete ambient history in the same time zone`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 14)))
        let entry = CostUsageDailyReport.Entry(
            date: "2026-10-29",
            inputTokens: 3000,
            outputTokens: 1200,
            totalTokens: 4200,
            costUSD: 0.5,
            modelsUsed: nil,
            modelBreakdowns: nil)
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 4200,
            sessionCostUSD: 0.5,
            last30DaysTokens: 4200,
            last30DaysCostUSD: 0.5,
            daily: [entry],
            updatedAt: now)
        #expect(CockpitLocalComfortProjection.tokens(
            snapshot: snapshot,
            isAmbient: true,
            bucketCalendar: calendar,
            now: now,
            calendar: calendar) == 4200)
        #expect(CockpitLocalComfortProjection.tokens(
            snapshot: snapshot,
            isAmbient: false,
            bucketCalendar: calendar,
            now: now,
            calendar: calendar) == nil)
        #expect(CockpitLocalComfortProjection.tokens(
            snapshot: snapshot,
            isAmbient: true,
            bucketCalendar: calendar,
            now: now.addingTimeInterval(301),
            calendar: calendar) == nil)
        var otherZone = calendar
        otherZone.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        #expect(CockpitLocalComfortProjection.tokens(
            snapshot: snapshot,
            isAmbient: true,
            bucketCalendar: otherZone,
            now: now,
            calendar: calendar) == nil)
    }

    @Test
    func `activity filter receipt retains cross month session totals with an explicit lifetime scope`() throws {
        let row = Self.row(session: "cross-month", tokens: 500_000, cost: 12)
        let lines = CockpitReceiptModel.items(model: Self.model(rows: [row]), hidePersonalInfo: false)
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        let receipt = CockpitReceiptModel(
            items: lines,
            scopeLabel: CockpitReceiptModel.scopeLabel(for: .rolling(days: 7), timeZone: zone))
        #expect(receipt.totals.first?.knownTokens == 500_000)
        #expect(receipt.totals.first?.knownCost == 12)
        #expect(receipt.scopeLabel.contains("Active in the Last 7 Days"))
        #expect(receipt.scopeLabel.contains("all scanned usage"))
        #expect(receipt.scopeLabel.contains("outside the activity filter"))
    }

    @Test
    @MainActor
    func `receipt exports an actual bounded PNG without accessing the clipboard`() throws {
        let receipt = CockpitReceiptModel(items: [Self.line(id: "synthetic", tokens: 12345, cost: 0.5)])
        let png = try #require(ShareStatsRenderer.pngData(for: receipt))
        #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
        let bitmap = try #require(NSBitmapImageRep(data: png))
        let size = CockpitReceiptCardView.size(for: receipt)
        #expect(bitmap.pixelsWide == Int(size.width))
        #expect(bitmap.pixelsHigh == Int(size.height))
        let longReceipt = CockpitReceiptModel(items: (0..<100).map {
            Self.line(id: "task-\($0)", tokens: 100, cost: 1)
        })
        #expect(CockpitReceiptCardView.size(for: longReceipt).height < 6000)
        #expect(longReceipt.totals.first?.knownCost == 100)
    }

    private static func identity(_ session: String) -> CockpitTaskIdentity {
        CockpitTaskIdentity(sourceID: "codex:synthetic", sessionID: session)
    }

    private static func line(
        id: String,
        currency: String = "USD",
        tokens: Int?,
        cost: Double?) -> CockpitReceiptLine
    {
        CockpitReceiptLine(
            id: id,
            title: "Same title",
            providerName: "Codex",
            currencyCode: currency,
            tokens: tokens,
            estimatedCost: cost,
            tokensArePartial: false,
            costIsPartial: false)
    }

    private static func row(session: String, tokens: Int?, cost: Double?) -> SpendDashboardModel.SessionRow {
        SpendDashboardModel.SessionRow(
            id: "codex:synthetic:\(session)",
            rank: 1,
            sessionID: session,
            sourceID: "codex:synthetic",
            provider: .codex,
            title: "Private project",
            projectName: nil,
            projectPath: nil,
            lastActivity: Date(timeIntervalSince1970: 1_790_000_000),
            totalTokens: tokens,
            totalCost: cost,
            modelName: "synthetic-model")
    }

    private static func model(
        rows: [SpendDashboardModel.SessionRow],
        sourceKind: SpendDashboardModel.SourceKind = .native) -> SpendDashboardModel
    {
        let provider = SpendDashboardModel.ProviderRow(
            id: "codex:synthetic",
            rank: 1,
            provider: .codex,
            displayName: "Codex",
            totalTokens: 160,
            totalCost: 1.75,
            coveredDayCount: 1,
            sourceKind: sourceKind)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let group = SpendDashboardModel.CurrencyGroup(
            currencyCode: "USD",
            providers: [provider],
            models: [],
            dailyPoints: [],
            totalTokens: 160,
            totalCost: 1.75,
            coveredDayCount: 1,
            chartDomain: date...date,
            modelHistoryCompleteness: .complete,
            sessions: rows)
        return SpendDashboardModel(requestedDays: 30, groups: [group])
    }
}
