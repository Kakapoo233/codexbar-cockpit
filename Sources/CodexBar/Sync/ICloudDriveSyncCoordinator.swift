import CodexBarCore
import Foundation
import Observation

@MainActor
@Observable
final class ICloudDriveSyncState {
    var enabled = false
    var isSynchronizing = false
    var directoryURL: URL?
    var lastSynchronizedAt: Date?
    var deviceCount = 0
    var uploadedToICloud: Bool?
    var errorMessage: String?
    @ObservationIgnored var enableHandler: ((Bool) -> Void)?
    @ObservationIgnored var synchronizeHandler: (() -> Void)?

    func setEnabled(_ enabled: Bool) {
        self.enableHandler?(enabled)
    }

    func synchronize() {
        self.synchronizeHandler?()
    }
}

/// Personal, credential-free document sync. CloudKit and team synchronization remain separate.
@MainActor
final class ICloudDriveSyncCoordinator {
    static let enabledKey = "iCloudDriveSyncEnabled"
    private let settings: SettingsStore
    private let state: ICloudDriveSyncState
    private let directoryURL: URL
    private let localStateURL: URL
    private let driveRoot: URL
    private var planStore: CockpitPlanStore?
    private var replica: ICloudDriveReplica?
    private var timer: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var generation = 0
    private var pendingLocalEdits: Set<String> = []

    init(
        settings: SettingsStore,
        state: ICloudDriveSyncState,
        driveRoot: URL? = nil,
        localStateURL: URL? = nil)
    {
        self.settings = settings
        self.state = state
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.driveRoot = driveRoot ?? home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        self.directoryURL = self.driveRoot.appendingPathComponent("CodexBar Cockpit/Sync-v1", isDirectory: true)
        self.localStateURL = localStateURL ?? CockpitAppIdentity.applicationSupportDirectory(home: home)
            .appendingPathComponent("icloud-drive/replica.json")
        state.directoryURL = self.directoryURL
        state.enabled = settings.userDefaults.bool(forKey: Self.enabledKey)
        state.enableHandler = { [weak self] enabled in self?.setEnabled(enabled) }
        state.synchronizeHandler = { [weak self] in self?.synchronize() }
    }

    func attachPlanStore(_ planStore: CockpitPlanStore) {
        self.planStore = planStore
        self.synchronize()
    }

    func start() {
        self.timer?.cancel()
        self.timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.synchronize()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }

    func stop() {
        self.generation += 1
        self.timer?.cancel()
        self.syncTask?.cancel()
        self.timer = nil
        self.syncTask = nil
        self.state.isSynchronizing = false
    }

    func applicationDidBecomeActive() {
        self.synchronize()
    }

    private func setEnabled(_ enabled: Bool) {
        self.generation += 1
        self.syncTask?.cancel()
        self.syncTask = nil
        self.state.enabled = enabled
        self.state.isSynchronizing = false
        self.state.errorMessage = nil
        self.settings.userDefaults.set(enabled, forKey: Self.enabledKey)
        if enabled { self.synchronize() }
    }

    private func projection() throws -> [String: Data] {
        var values = try self.settings.driveSyncSettingsValues()
        if let planStore {
            try values.merge(planStore.driveSyncValues(), uniquingKeysWith: { _, last in last })
        }
        return values
    }

    func synchronize() {
        // Do not interpret a not-yet-attached planner as deletion of all planning records.
        guard self.state.enabled, self.planStore != nil, self.syncTask == nil else { return }
        let generation = self.generation
        self.state.isSynchronizing = true
        self.syncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == self.generation {
                    self.state.isSynchronizing = false
                    self.syncTask = nil
                }
            }
            do {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: self.driveRoot.path, isDirectory: &isDirectory),
                      isDirectory.boolValue
                else {
                    throw DriveUnavailable()
                }
                if self.replica == nil {
                    let idKey = "iCloudDriveReplicaID"
                    let storedID = self.settings.userDefaults.string(forKey: idKey)
                    let id = storedID.flatMap(UUID.init(uuidString:))?.uuidString ?? UUID().uuidString
                    self.settings.userDefaults.set(id, forKey: idKey)
                    self.replica = try ICloudDriveReplica(
                        directoryURL: self.directoryURL, localStateURL: self.localStateURL, deviceID: id)
                }
                guard let replica = self.replica else { return }
                let before = try self.projection()
                let result = try await replica.synchronize(
                    localValues: before, locallyChangedKeys: self.pendingLocalEdits)
                guard !Task.isCancelled, generation == self.generation, self.state.enabled else { return }
                // A local edit during file coordination belongs to the user, not to this old fetch.
                let latest = try self.projection()
                guard latest == before else {
                    self.pendingLocalEdits.formUnion(Set(before.keys).union(latest.keys).filter {
                        before[$0] != latest[$0]
                    })
                    return
                }
                try self.settings.validateDriveSyncSettingsValues(result.values)
                try self.planStore?.applyDriveSyncValues(
                    result.values, managedKeys: Set(result.values.keys).union(result.removedKeys))
                try self.settings.applyDriveSyncSettingsValues(result.values)
                try await replica.acknowledge(result, appliedValues: self.projection())
                guard !Task.isCancelled, generation == self.generation, self.state.enabled else { return }
                self.state.lastSynchronizedAt = result.synchronizedAt
                self.state.deviceCount = result.deviceCount
                self.state.uploadedToICloud = result.uploadedToICloud
                self.state.errorMessage = nil
                self.pendingLocalEdits.removeAll()
            } catch is CancellationError {
                // Disabling sync must not surface a stale error or restart the operation.
            } catch {
                guard generation == self.generation else { return }
                self.state.errorMessage = Self.message(for: error)
            }
        }
    }

    private static func message(for error: any Error) -> String {
        switch error as? ICloudDriveReplicaError {
        case .pendingDownload:
            L("Waiting for iCloud Drive to download sync files.")
        case .unsupportedVersion:
            L("Sync is paused: another Mac uses a newer version of CodexBar. Update to resume.")
        case .invalidDocument, .limitExceeded, .invalidDevice:
            L("Sync files could not be read safely. Local data has been preserved.")
        case .invalidLocation:
            L("The sync folder is unavailable. Check iCloud Drive and try again.")
        default:
            error.localizedDescription
        }
    }

    private struct DriveUnavailable: LocalizedError {
        var errorDescription: String? {
            L("Turn on iCloud Drive in System Settings, then try again.")
        }
    }
}
