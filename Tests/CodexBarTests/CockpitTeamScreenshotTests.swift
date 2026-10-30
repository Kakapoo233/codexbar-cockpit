import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

/// Opt-in native rendering proof. All identities, usage and credentials are synthetic.
@MainActor
struct CockpitTeamScreenshotTests {
    @Test
    func `render synthetic shared team at wide and narrow menu widths`() async throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_PROOF_DIR"] != nil else { return }
        let directory = try Self.proofDirectory()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = try #require(CockpitTeamStore.date("2026-10-30T04:00:00.000Z"))
        let store = Self.store(
            file: folder.appendingPathComponent("team.json"),
            now: now)
        let groups = CockpitTeamGroups(groups: [
            CockpitTeamPerson(
                id: "person-a",
                name: "组员甲",
                deviceIDs: ["synthetic-mac-a", "synthetic-mac-b"]),
            CockpitTeamPerson(
                id: "person-b",
                name: "组员乙",
                deviceIDs: ["synthetic-mac-c"]),
            CockpitTeamPerson(
                id: "person-c",
                name: "组员丙",
                deviceIDs: ["synthetic-mac-d"]),
        ])
        let shared = CockpitTeamSharedSettings(
            revision: 3,
            value: CockpitTeamSettingsValue(
                groups: groups,
                pricing: .bundled))
        let devices = [
            CockpitTeamDevice(
                deviceID: "synthetic-mac-a",
                displayName: "演示 Mac 甲",
                role: .owner),
            CockpitTeamDevice(
                deviceID: "synthetic-mac-b",
                displayName: "演示 Mac 乙"),
            CockpitTeamDevice(
                deviceID: "synthetic-mac-c",
                displayName: "演示 Mac 丙"),
            CockpitTeamDevice(
                deviceID: "synthetic-mac-d",
                displayName: "演示 Mac 丁"),
        ]
        store.connection = CockpitTeamStore.Connection(
            endpoint: "https://team.example.invalid",
            spaceID: "synthetic-space",
            spaceName: "合成数据演示团队",
            deviceID: devices[0].deviceID,
            deviceName: devices[0].displayName,
            role: .owner,
            enabled: true,
            shareUsage: true,
            boundAccountID: "synthetic-account",
            boundAt: now.addingTimeInterval(-86400))
        store.sharedSettings = shared
        store.identity = CockpitTeamIdentity(
            space: CockpitTeamSpace(
                id: "synthetic-space",
                name: "合成数据演示团队"),
            deviceID: devices[0].deviceID,
            role: .owner,
            members: devices,
            sharedSettings: shared)
        store.plan = CockpitTeamDailyPlan(
            basis: CockpitTeamPlanBasis(
                localDate: "2026-10-30",
                anchorAt: CockpitTeamStore.timestamp(now),
                remainingPercent: 72,
                resetsAt: "2026-11-03T04:00:00.000Z"),
            people: ["person-a": CockpitTeamPlanField(
                value: 8,
                revision: 2)],
            risk: CockpitTeamPlanField(
                value: 10,
                revision: 1))
        store.lastSyncedAt = now.addingTimeInterval(-120)
        store.snapshots = devices.enumerated().map { index, device in
            let partial = index == 3
            return CockpitTeamDeviceSnapshot(
                deviceID: device.deviceID,
                displayName: device.displayName,
                updatedAt: now.addingTimeInterval(-Double(index + 1) * 120).timeIntervalSince1970,
                payload: CockpitTeamUsageSnapshot(
                    deviceID: device.deviceID,
                    timestamp: Int64(now.timeIntervalSince1970),
                    days: ["2026-10-30": CockpitTeamLedgerDay(
                        inputTokens: Int64(12000 * (index + 1)),
                        outputTokens: Int64(2400 * (index + 1)),
                        cost: partial ? nil : Double(index + 1) * 0.75)],
                    metadata: CockpitTeamSnapshotMetadata(status: partial ? .partial : .ready)))
        }
        try await CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            store.uploadStatus = L("Sharing local Codex daily aggregates. Current-day data is partial.")
            for width in [600, 420] {
                for height in [760, 1400] {
                    let view = CockpitTeamView(
                        teamStore: store,
                        onSettings: {}).codexBarLocalized()
                    let data = try #require(await Self.pngData(
                        view,
                        size: CGSize(
                            width: width,
                            height: height)))
                    try data.write(to: directory.appendingPathComponent("cockpit-team-\(width)x\(height)-zh.png"))
                }
            }
        }
    }

    @Test
    func `render unconnected team settings without host identity or credentials`() async throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_PROOF_DIR"] != nil else { return }
        let directory = try Self.proofDirectory()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = try #require(CockpitTeamStore.date("2026-10-30T04:00:00.000Z"))
        let store = Self.store(
            file: folder.appendingPathComponent("team.json"),
            now: now)
        try await CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let data = try #require(await Self.pngData(
                PreferencesTeamPane(teamStore: store).codexBarLocalized(),
                size: CGSize(
                    width: 880,
                    height: 760)))
            try data.write(to: directory.appendingPathComponent("cockpit-team-settings-unconnected-zh.png"))
        }
    }

    private static func store(
        file: URL,
        now: Date) -> CockpitTeamStore
    {
        CockpitTeamStore(
            fileURL: file,
            clientFactory: { _ in throw CockpitTeamError.invalidRequest },
            loadToken: { _, _ in nil },
            saveToken: { _, _, _ in },
            quotaInput: {
                CockpitTeamStore.QuotaInput(
                    accountID: "synthetic-account",
                    observedAt: now,
                    remainingPercent: 72,
                    resetsAt: now.addingTimeInterval(4 * 86400))
            },
            now: { now })
    }

    private static func proofDirectory() throws -> URL {
        let path = ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_PROOF_DIR"]
            ?? "/private/tmp/cockpit-0.6.0-proof"
        let directory = URL(
            fileURLWithPath: path,
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        return directory
    }

    private static func pngData(
        _ view: some View,
        size: CGSize) async throws -> Data?
    {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "zh_Hans_CN")).background(Color.white))
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
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        bitmap.size = size
        host.displayIgnoringOpacity(
            host.bounds,
            in: context)
        return bitmap.representation(
            using: .png,
            properties: [:])
    }
}
