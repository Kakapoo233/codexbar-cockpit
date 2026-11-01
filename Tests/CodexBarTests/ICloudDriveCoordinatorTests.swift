import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ICloudDriveCoordinatorTests {
    @Test
    func `two clients exchange actual settings and disabling prevents further file writes`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = self.fixture(root: root, name: "first")
        let second = self.fixture(root: root, name: "second")
        defer { first.coordinator.stop(); second.coordinator.stop() }
        first.settings.hidePersonalInfo = true
        first.state.setEnabled(true)
        try await self.finish(first.state)
        #expect(first.state.errorMessage == nil)
        #expect(first.state.lastSynchronizedAt != nil)
        second.state.setEnabled(true)
        try await self.finish(second.state)
        #expect(second.settings.hidePersonalInfo)
        #expect(second.state.deviceCount == 2)
        second.settings.hidePersonalInfo = false
        second.state.synchronize()
        try await self.finish(second.state)
        first.state.synchronize()
        try await self.finish(first.state)
        #expect(!first.settings.hidePersonalInfo)
        let directory = try #require(first.state.directoryURL)
        let before = try self.files(in: directory)
        first.state.setEnabled(false)
        first.settings.hidePersonalInfo = true
        first.state.synchronize()
        try await self.finish(first.state)
        #expect(try self.files(in: directory) == before)
        #expect(!first.defaults.bool(forKey: ICloudDriveSyncCoordinator.enabledKey))
    }

    @Test
    func `missing iCloud Drive is reported without creating a pretend drive folder`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fixture = self.fixture(root: root, name: "missing")
        defer { fixture.coordinator.stop(); try? FileManager.default.removeItem(at: root) }
        fixture.state.setEnabled(true)
        try await self.finish(fixture.state)
        #expect(fixture.state.errorMessage != nil)
        #expect(fixture.state.lastSynchronizedAt == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    private func finish(_ state: ICloudDriveSyncState) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while state.isSynchronizing, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!state.isSynchronizing)
    }

    private func files(in directory: URL) throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: urls.map { try ($0.lastPathComponent, Data(contentsOf: $0)) })
    }

    private func fixture(root: URL, name: String) -> (
        settings: SettingsStore, defaults: UserDefaults, state: ICloudDriveSyncState,
        coordinator: ICloudDriveSyncCoordinator)
    {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: UUID().uuidString, userDefaults: defaults)
        let state = ICloudDriveSyncState()
        let coordinator = ICloudDriveSyncCoordinator(
            settings: settings,
            state: state,
            driveRoot: root,
            localStateURL: root.appendingPathComponent(name + "/replica.json"))
        coordinator.attachPlanStore(CockpitPlanStore(fileURL: root.appendingPathComponent(name + "-plan.json")))
        return (settings, defaults, state, coordinator)
    }
}
