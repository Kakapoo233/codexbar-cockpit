import Foundation
import Testing
@testable import CodexBar

struct ICloudDriveReplicaTests {
    private static let deviceA = "00000000-0000-4000-8000-000000000001"
    private static let deviceB = "ffffffff-ffff-4fff-8fff-ffffffffffff"

    @Test
    func `a new device pulls existing values before publishing defaults`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.replica(Self.deviceA)
        let initial = try await first.synchronize(localValues: ["settings/theme": Self.data("dark")])
        try await first.acknowledge(initial)
        let second = try fixture.replica(Self.deviceB)
        let joined = try await second.synchronize(localValues: [
            "settings/theme": Self.data("light"), "settings/locale": Self.data("en"),
        ])
        #expect(joined.values["settings/theme"] == Self.data("dark"))
        #expect(joined.values["settings/locale"] == Self.data("en"))
        #expect(joined.deviceCount == 2)
        #expect(joined.uploadedToICloud == nil)
        try await second.acknowledge(joined)
        let returned = try await first.synchronize(localValues: initial.values)
        #expect(returned.values == joined.values)
    }

    @Test
    func `calendar edits and clears propagate without resurrecting deleted values`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.replica(Self.deviceA)
        let second = try fixture.replica(Self.deviceB)
        let seeded = try await first.synchronize(localValues: ["calendar/day": Self.data("light")])
        try await first.acknowledge(seeded)
        let joined = try await second.synchronize(localValues: [:])
        try await second.acknowledge(joined)
        let edited = try await second.synchronize(localValues: ["calendar/day": Self.data("comfortable")])
        try await second.acknowledge(edited)
        let pulled = try await first.synchronize(localValues: seeded.values)
        #expect(pulled.values["calendar/day"] == Self.data("comfortable"))
        try await first.acknowledge(pulled)
        let cleared = try await first.synchronize(localValues: [:])
        try await first.acknowledge(cleared)
        let deletion = try await second.synchronize(localValues: edited.values)
        #expect(deletion.values.isEmpty)
        #expect(deletion.removedKeys == ["calendar/day"])
        try await second.acknowledge(deletion)
        let restart = try fixture.replica(Self.deviceB)
        let afterRestart = try await restart.synchronize(localValues: [:])
        #expect(afterRestart.values.isEmpty)
        #expect(!afterRestart.didUpload)
    }

    @Test
    func `pulling an edit does not echo it back as a later local edit`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.replica(Self.deviceA)
        let second = try fixture.replica(Self.deviceB)
        let seeded = try await first.synchronize(localValues: ["settings/theme": Self.data("dark")])
        try await first.acknowledge(seeded)
        let pulled = try await second.synchronize(localValues: [:])
        try await second.acknowledge(pulled)
        let own = fixture.cloud.appendingPathComponent(Self.deviceB + ".json")
        let before = try Data(contentsOf: own)
        let unchanged = try await second.synchronize(localValues: pulled.values)
        #expect(!unchanged.didUpload)
        #expect(try Data(contentsOf: own) == before)
    }

    @Test
    func `unacknowledged remote application is retried after restart`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.replica(Self.deviceA)
        let seeded = try await first.synchronize(localValues: ["settings/theme": Self.data("dark")])
        try await first.acknowledge(seeded)
        let second = try fixture.replica(Self.deviceB)
        let pending = try await second.synchronize(localValues: ["settings/theme": Self.data("light")])
        #expect(pending.values["settings/theme"] == Self.data("dark"))
        let restart = try fixture.replica(Self.deviceB)
        let retried = try await restart.synchronize(localValues: ["settings/theme": Self.data("light")])
        #expect(retried.values["settings/theme"] == Self.data("dark"))
        #expect(!retried.didUpload)
    }

    @Test
    func `a crash after remote application does not overwrite a newer remote edit on restart`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.replica(Self.deviceA)
        let second = try fixture.replica(Self.deviceB)
        let seeded = try await first.synchronize(localValues: ["settings/theme": Self.data("dark")])
        try await first.acknowledge(seeded)
        let joined = try await second.synchronize(localValues: [:])
        try await second.acknowledge(joined)
        let changed = try await second.synchronize(localValues: ["settings/theme": Self.data("light")])
        try await second.acknowledge(changed)
        let appliedBeforeCrash = try await first.synchronize(localValues: seeded.values)
        #expect(appliedBeforeCrash.values["settings/theme"] == Self.data("light"))
        // The app has saved light locally, but exits before acknowledging that result to the replica.
        let newest = try await second.synchronize(localValues: ["settings/theme": Self.data("system")])
        try await second.acknowledge(newest)
        let restarted = try fixture.replica(Self.deviceA)
        let recovered = try await restarted.synchronize(localValues: appliedBeforeCrash.values)
        #expect(recovered.values["settings/theme"] == Self.data("system"))
        #expect(!recovered.didUpload)
    }

    @Test
    func `explicit edits during first join win while untouched defaults still adopt remote values`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.replica(Self.deviceA)
        let seeded = try await first.synchronize(localValues: [
            "settings/theme": Self.data("dark"), "settings/locale": Self.data("en"),
        ])
        try await first.acknowledge(seeded)
        let second = try fixture.replica(Self.deviceB)
        _ = try await second.synchronize(localValues: [
            "settings/theme": Self.data("light"), "settings/locale": Self.data("fr"),
        ])
        // The app skips applying that in-flight result because the user has just edited the theme.
        let recovered = try await second.synchronize(
            localValues: ["settings/theme": Self.data("system"), "settings/locale": Self.data("fr")],
            locallyChangedKeys: ["settings/theme"])
        #expect(recovered.values["settings/theme"] == Self.data("system"))
        #expect(recovered.values["settings/locale"] == Self.data("en"))
        try await second.acknowledge(recovered)
        let cleared = try await second.synchronize(
            localValues: ["settings/locale": Self.data("en")], locallyChangedKeys: ["settings/theme"])
        #expect(cleared.removedKeys.contains("settings/theme"))
    }

    @Test
    func `offline edits survive restart and retain unrelated remote changes`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.replica(Self.deviceA)
        let second = try fixture.replica(Self.deviceB)
        let seeded = try await first.synchronize(localValues: ["settings/theme": Self.data("dark")])
        try await first.acknowledge(seeded)
        let joined = try await second.synchronize(localValues: [:])
        try await second.acknowledge(joined)
        var remote = joined.values
        remote["calendar/day"] = Self.data("light")
        let changed = try await second.synchronize(localValues: remote)
        try await second.acknowledge(changed)
        let restart = try fixture.replica(Self.deviceA)
        let recovered = try await restart.synchronize(localValues: ["settings/theme": Self.data("light")])
        #expect(recovered.values["settings/theme"] == Self.data("light"))
        #expect(recovered.values["calendar/day"] == Self.data("light"))
    }

    @Test
    func `equal logical clocks converge by device identity without relying on wall time`() async throws {
        let fixture = try Fixture()
        let isolated = try Fixture()
        defer { fixture.remove(); isolated.remove() }
        let first = try fixture.replica(Self.deviceA)
        let second = try isolated.replica(Self.deviceB)
        let earlier = try await first.synchronize(
            localValues: ["settings/theme": Self.data("dark")], now: Date(timeIntervalSince1970: 9_000_000))
        let later = try await second.synchronize(
            localValues: ["settings/theme": Self.data("light")], now: Date(timeIntervalSince1970: 1))
        try await first.acknowledge(earlier)
        try await second.acknowledge(later)
        try FileManager.default.copyItem(
            at: isolated.cloud.appendingPathComponent(Self.deviceB + ".json"),
            to: fixture.cloud.appendingPathComponent(Self.deviceB + ".json"))
        try FileManager.default.copyItem(
            at: fixture.cloud.appendingPathComponent(Self.deviceA + ".json"),
            to: isolated.cloud.appendingPathComponent(Self.deviceA + ".json"))
        let mergedA = try await first.synchronize(localValues: earlier.values)
        let mergedB = try await second.synchronize(localValues: later.values)
        #expect(mergedA.values == mergedB.values)
        #expect(mergedA.values["settings/theme"] == Self.data("light"))
    }

    @Test(arguments: ["corrupt", "future", "placeholder", "symlink"])
    func `unreadable remote state fails closed without replacing local or cloud data`(_ failure: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let replica = try fixture.replica(Self.deviceA)
        let seeded = try await replica.synchronize(localValues: ["settings/theme": Self.data("dark")])
        try await replica.acknowledge(seeded)
        let own = fixture.cloud.appendingPathComponent(Self.deviceA + ".json")
        let journal = fixture.journal(Self.deviceA)
        let beforeCloud = try Data(contentsOf: own)
        let beforeJournal = try Data(contentsOf: journal)
        let other = fixture.cloud.appendingPathComponent(Self.deviceB + ".json")
        let expected: ICloudDriveReplicaError
        switch failure {
        case "future":
            try Self.data("{\"version\":2}").write(to: other)
            expected = .unsupportedVersion
        case "placeholder":
            try Data().write(to: fixture.cloud.appendingPathComponent("." + Self.deviceB + ".json.icloud"))
            expected = .pendingDownload
        case "symlink":
            try FileManager.default.createSymbolicLink(at: other, withDestinationURL: own)
            expected = .invalidLocation
        default:
            try Self.data("broken document").write(to: other)
            expected = .invalidDocument
        }
        await #expect(throws: expected) {
            try await replica.synchronize(localValues: ["settings/theme": Self.data("light")])
        }
        #expect(try Data(contentsOf: own) == beforeCloud)
        #expect(try Data(contentsOf: journal) == beforeJournal)
    }

    @Test
    func `directory and local journal failures cannot reset synchronization history`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.cloud, withIntermediateDirectories: true)
        let link = fixture.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.cloud)
        let invalid = try ICloudDriveReplica(
            directoryURL: link, localStateURL: fixture.journal(Self.deviceA), deviceID: Self.deviceA)
        await #expect(throws: ICloudDriveReplicaError.invalidLocation) {
            try await invalid.synchronize(localValues: [:])
        }
        let replica = try fixture.replica(Self.deviceA)
        let seeded = try await replica.synchronize(localValues: [:])
        try await replica.acknowledge(seeded)
        try Self.data("broken journal").write(to: fixture.journal(Self.deviceA))
        await #expect(throws: ICloudDriveReplicaError.invalidDocument) {
            try await replica.synchronize(localValues: ["settings/theme": Self.data("light")])
        }
    }

    @Test
    func `obsolete acknowledgements and cancelled writes are rejected`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let replica = try fixture.replica(Self.deviceA)
        let first = try await replica.synchronize(localValues: [:])
        let second = try await replica.synchronize(localValues: [:])
        await #expect(throws: ICloudDriveReplicaError.obsoleteAcknowledgement) {
            try await replica.acknowledge(first)
        }
        try await replica.acknowledge(second)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await replica.synchronize(localValues: ["settings/theme": Self.data("dark")])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private static func data(_ value: String) -> Data { Data(value.utf8) }

    private struct Fixture {
        let root: URL
        var cloud: URL {
            self.root.appendingPathComponent("cloud")
        }

        init() throws {
            self.root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        }

        func journal(_ device: String) -> URL {
            self.root.appendingPathComponent("local/" + device + ".json")
        }

        func replica(_ device: String) throws -> ICloudDriveReplica {
            try ICloudDriveReplica(directoryURL: self.cloud, localStateURL: self.journal(device), deviceID: device)
        }

        func remove() { try? FileManager.default.removeItem(at: self.root) }
    }
}
