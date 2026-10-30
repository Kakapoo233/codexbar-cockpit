import AppKit
import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct CockpitQuotaComfortUITests {
    @Test
    func `quota feedback persists and feeling edits preserve the captured usage`() throws {
        try Self.withStore { store, url in
            let calendar = Self.calendar
            let now = Self.now
            store.ingest([.codex: Self.snapshot(
                at: now.addingTimeInterval(-600),
                usedPercent: 20)])
            store.ingest([.codex: Self.snapshot(
                at: now,
                usedPercent: 35)])
            let accountID = store.accountID(for: .codex)
            store.setQuotaComfortFeeling(
                .comfortable,
                for: .codex,
                on: now,
                now: now,
                calendar: calendar)
            let initial = try #require(CockpitCalendarProjection.record(
                on: now,
                providerID: "codex",
                accountID: accountID,
                records: store.state.comfortRecords,
                calendar: calendar))
            #expect(initial.usedPercent == 15)
            #expect(initial.totalTokens == nil)
            #expect(initial.coverage == .partial)
            #expect(CockpitPlanStore(fileURL: url).state == store.state)

            let later = now.addingTimeInterval(60)
            store.ingest([.codex: Self.snapshot(
                at: later,
                usedPercent: 60)])
            let plans = store.state.plans
            let snapshots = store.state.snapshots
            store.setQuotaComfortFeeling(
                .overloaded,
                for: .codex,
                on: now,
                now: later,
                calendar: calendar)
            let edited = try #require(CockpitCalendarProjection.record(
                on: now,
                providerID: "codex",
                accountID: accountID,
                records: store.state.comfortRecords,
                calendar: calendar))
            #expect(edited.feeling == .overloaded)
            #expect(edited.usedPercent == initial.usedPercent)
            #expect(edited.coverage == initial.coverage)
            #expect(store.state.comfortRecords.count == 1)
            #expect(store.state.plans == plans)
            #expect(store.state.snapshots == snapshots)
            #expect(CockpitPlanStore(fileURL: url).state == store.state)
            let text = try String(
                contentsOf: url,
                encoding: .utf8)
            #expect(!text.contains("synthetic-account-one"))
            #expect(!text.contains("synthetic-org"))
        }
    }

    @Test
    func `account switches and clearing quota feedback preserve other account and local feedback`() throws {
        try Self.withStore { store, url in
            let calendar = Self.calendar
            let now = Self.now
            for (account, feeling) in [
                ("synthetic-account-one", CockpitFeeling.comfortable),
                ("synthetic-account-two", CockpitFeeling.overloaded),
            ] {
                store.ingest([.codex: Self.snapshot(
                    at: now.addingTimeInterval(-600),
                    usedPercent: 20,
                    account: account)])
                store.ingest([.codex: Self.snapshot(
                    at: now,
                    usedPercent: 35,
                    account: account)])
                if account == "synthetic-account-two" {
                    #expect(CockpitCalendarProjection.feeling(
                        on: now,
                        providerID: "codex",
                        accountID: store.accountID(for: .codex),
                        records: store.state.comfortRecords,
                        calendar: calendar) == nil)
                }
                store.setQuotaComfortFeeling(
                    feeling,
                    for: .codex,
                    on: now,
                    now: now,
                    calendar: calendar)
            }
            store.recordLocalComfort(
                .light,
                for: .codex,
                on: now,
                totalTokens: 12345,
                coverage: .complete,
                calendar: calendar)
            let secondAccount = store.accountID(for: .codex)
            #expect(store.state.comfortRecords.count == 3)
            #expect(CockpitCalendarProjection.feeling(
                on: now,
                providerID: "codex",
                records: store.state.comfortRecords,
                calendar: calendar) == .light)
            #expect(CockpitCalendarProjection.feeling(
                on: now,
                providerID: "codex",
                accountID: secondAccount,
                records: store.state.comfortRecords,
                calendar: calendar) == .overloaded)

            store.clearQuotaComfort(
                for: .codex,
                on: now,
                calendar: calendar)
            #expect(store.state.comfortRecords.count == 2)
            #expect(store.state.comfortRecords.allSatisfy { $0.accountID != secondAccount })
            store.ingest([.codex: Self.snapshot(
                at: now,
                usedPercent: 35)])
            let firstAccount = store.accountID(for: .codex)
            #expect(firstAccount != secondAccount)
            #expect(CockpitCalendarProjection.feeling(
                on: now,
                providerID: "codex",
                accountID: firstAccount,
                records: store.state.comfortRecords,
                calendar: calendar) == .comfortable)
            store.clearQuotaComfort(
                for: .codex,
                on: now,
                calendar: calendar)
            let local = try #require(store.state.comfortRecords.first)
            #expect(store.state.comfortRecords.count == 1)
            #expect(local.accountID == "local-machine")
            #expect(local.totalTokens == 12345)
            #expect(local.usedPercent == nil)
            #expect(CockpitPlanStore(fileURL: url).state == store.state)
        }
    }

    @Test
    func `unknown account cannot write or clear quota feedback`() throws {
        try Self.withStore { store, url in
            let now = Self.now
            store.setQuotaComfortFeeling(
                .comfortable,
                for: .codex,
                on: now,
                now: now,
                calendar: Self.calendar)
            #expect(store.state.comfortRecords.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            store.ingest([.codex: Self.snapshot(
                at: now,
                usedPercent: 30)])
            store.setQuotaComfortFeeling(
                .light,
                for: .codex,
                on: now,
                now: now,
                calendar: Self.calendar)
            let records = store.state.comfortRecords
            store.ingest([.codex: Self.snapshot(
                at: now,
                usedPercent: 30,
                account: nil)])
            #expect(store.accountID(for: .codex) == "unidentified")
            store.setQuotaComfortFeeling(
                .overloaded,
                for: .codex,
                on: now,
                now: now,
                calendar: Self.calendar)
            store.clearQuotaComfort(
                for: .codex,
                on: now,
                calendar: Self.calendar)
            #expect(store.state.comfortRecords == records)
        }
    }

    @Test
    func `calendar projection isolates quota local provider and reporting time zone`() throws {
        let calendar = Self.calendar
        var otherZone = calendar
        otherZone.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = Self.now
        let records = [
            Self.record(
                on: now,
                account: "quota-one",
                feeling: .comfortable,
                calendar: calendar),
            Self.record(
                on: now,
                account: "quota-two",
                feeling: .overloaded,
                calendar: calendar),
            Self.record(
                on: now,
                account: "local-machine",
                feeling: .light,
                calendar: calendar),
            Self.record(
                on: now,
                provider: "claude",
                account: "quota-one",
                feeling: .light,
                calendar: calendar),
            Self.record(
                on: now,
                account: "quota-one",
                feeling: .overloaded,
                calendar: otherZone),
        ]
        #expect(CockpitCalendarProjection.feeling(
            on: now,
            providerID: "codex",
            accountID: "quota-one",
            records: records,
            calendar: calendar) == .comfortable)
        #expect(CockpitCalendarProjection.feeling(
            on: now,
            providerID: "codex",
            accountID: "quota-two",
            records: records,
            calendar: calendar) == .overloaded)
        #expect(CockpitCalendarProjection.feeling(
            on: now,
            providerID: "codex",
            records: records,
            calendar: calendar) == .light)
        #expect(CockpitCalendarProjection.feeling(
            on: now,
            providerID: "claude",
            accountID: "quota-one",
            records: records,
            calendar: calendar) == .light)
        #expect(CockpitCalendarProjection.feeling(
            on: now,
            providerID: "codex",
            accountID: "quota-one",
            records: records,
            calendar: otherZone) == .overloaded)
        #expect(CockpitCalendarProjection.record(
            on: now,
            providerID: "codex",
            accountID: "missing",
            records: records,
            calendar: calendar) == nil)
    }

    @Test
    func `render default and fitted comfort curves with synthetic records in both languages and widths`() async throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_PROOF_DIR"],
              !path.isEmpty else { return }
        let directory = URL(
            fileURLWithPath: path,
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let calendar = Self.calendar
        let now = Self.now
        let records = try [5.0, 10, 20, 30, 50, 120].enumerated().map { index, used in
            let offset = index == 0 ? -28 : -index
            let date = try #require(calendar.date(
                byAdding: .day,
                value: offset,
                to: now))
            return Self.record(
                on: date,
                account: "synthetic-proof-account",
                feeling: index < 2 ? .light : (index < 4 ? .comfortable : .overloaded),
                calendar: calendar,
                coverage: index == 3 ? .partial : .complete,
                usedPercent: used)
        }
        for language in ["zh-Hans", "en"] {
            try await CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                for fitted in [false, true] {
                    let selected = fitted ? records : []
                    let model = CockpitQuotaComfortModel.build(
                        records: selected,
                        providerID: "codex",
                        accountID: "synthetic-proof-account",
                        now: now,
                        calendar: calendar)
                    #expect(model.status == (fitted ? .fitted : .baseline))
                    #expect(model.sampleCount == (fitted ? 6 : 0))
                    for width in [600.0, 420.0] {
                        let view = VStack(
                            alignment: .leading,
                            spacing: 16)
                        {
                            Text(language == "en" ? "Synthetic data preview" : "合成数据预览")
                                .font(.headline)
                            CockpitQuotaComfortChartView(
                                model: model,
                                records: Array(selected.reversed()))
                            Spacer(minLength: 0)
                        }
                        .padding(20)
                        .codexBarLocalized()
                        let png = try #require(await Self.pngData(
                            view,
                            size: CGSize(
                                width: width,
                                height: 660)))
                        let mode = fitted ? "fitted" : "default"
                        let filename = "cockpit-comfort-\(mode)-\(Int(width))-\(language)-synthetic.png"
                        try png.write(to: directory.appendingPathComponent(filename))
                    }
                }
            }
        }
    }

    private static var now: Date {
        Date(timeIntervalSince1970: 1_793_361_600)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func snapshot(
        at date: Date,
        usedPercent: Double,
        account: String? = "synthetic-account-one") -> UsageSnapshot
    {
        UsageSnapshot(
            primary: nil,
            secondary: RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 10080,
                resetsAt: self.now.addingTimeInterval(4 * 86400),
                resetDescription: nil),
            updatedAt: date,
            identity: account.map {
                ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: nil,
                    accountOrganization: "synthetic-org",
                    loginMethod: nil,
                    accountID: $0)
            })
    }

    private static func record(
        on date: Date,
        provider: String = "codex",
        account: String,
        feeling: CockpitFeeling,
        calendar: Calendar,
        coverage: CockpitCoverage = .complete,
        usedPercent: Double? = 15) -> CockpitComfortRecord
    {
        CockpitComfortRecord(
            providerID: provider,
            accountID: account,
            localDateKey: CockpitCalendar.dateKey(
                for: date,
                calendar: calendar),
            timeZoneIdentifier: calendar.timeZone.identifier,
            recordedAt: date,
            feeling: feeling,
            totalTokens: nil,
            coverage: coverage,
            usedPercent: usedPercent)
    }

    private static func withStore(_ body: (CockpitPlanStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CockpitQuotaComfortUITests-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(
            CockpitPlanStore(fileURL: directory.appendingPathComponent("plan.json")),
            directory.appendingPathComponent("plan.json"))
    }

    private static func pngData(
        _ view: some View,
        size: CGSize) async throws -> Data?
    {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light).background(Color.white))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = CGRect(
            origin: .zero,
            size: size)
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
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = size
        host.displayIgnoringOpacity(
            host.bounds,
            in: context)
        return bitmap.representation(
            using: .png,
            properties: [:])
    }
}
