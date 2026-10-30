import CodexBarCore
import CryptoKit
import Foundation
import Observation

/// A separate sharing boundary from personal iCloud sync and provider authentication.
@MainActor
@Observable
final class CockpitTeamStore {
    struct Connection: Codable, Equatable {
        var endpoint: String
        var spaceID: String
        var spaceName: String
        var deviceID: String
        var deviceName: String
        var role: CockpitTeamRole
        var enabled = true
        var shareUsage = false
        var boundAccountID: String?
        var boundAt: Date?
    }

    struct Cache: Codable {
        var connection: Connection?
        var identity: CockpitTeamIdentity?
        var snapshots: [CockpitTeamDeviceSnapshot] = []
        var plan: CockpitTeamDailyPlan?
        var lastSyncedAt: Date?
        var lastUploadTimestamp: Int64?
    }

    struct QuotaInput {
        var accountID: String
        var observedAt: Date
        var remainingPercent: Double
        var resetsAt: Date
    }

    struct PendingEnrollment {
        let endpoint: String
        let deviceID: String
        let deviceName: String
        let result: CockpitTeamEnrollment
    }

    var connection: Connection?
    var identity: CockpitTeamIdentity?
    var sharedSettings = CockpitTeamSharedSettings()
    var snapshots: [CockpitTeamDeviceSnapshot] = []
    var plan: CockpitTeamDailyPlan?
    var isBusy = false
    var errorMessage: String?
    var lastSyncedAt: Date?
    var inviteCode: String?
    var inviteExpiresAt: Date?
    var hasPendingEnrollment = false
    var uploadStatus = L("Usage sharing is off. Team budgets still synchronize.")

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored let clientFactory: (String) throws -> CockpitTeamClient
    @ObservationIgnored let loadToken: (String, String) throws -> String?
    @ObservationIgnored let saveToken: (String?, String, String) throws -> Void
    @ObservationIgnored let quotaInput: () -> QuotaInput?
    @ObservationIgnored let accountIdentity: () -> String?
    @ObservationIgnored let usageSnapshot: (Connection, Date) -> (CockpitTeamUsageSnapshot, String)
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored var generation = UUID()
    @ObservationIgnored var pollingTask: Task<Void, Never>?
    @ObservationIgnored var observingAccount = false
    @ObservationIgnored var lastUploadAt: Date?
    @ObservationIgnored var lastUploadTimestamp: Int64?
    @ObservationIgnored var canSave = true
    @ObservationIgnored var pendingEnrollment: PendingEnrollment?

    init(
        fileURL: URL,
        clientFactory: @escaping (String) throws -> CockpitTeamClient = { try CockpitTeamClient(endpoint: $0) },
        loadToken: @escaping (String, String) throws -> String?,
        saveToken: @escaping (String?, String, String) throws -> Void,
        quotaInput: @escaping () -> QuotaInput? = { nil },
        accountIdentity: (() -> String?)? = nil,
        usageSnapshot: @escaping (Connection, Date) -> (CockpitTeamUsageSnapshot, String) = { connection, date in
            (
                CockpitTeamUsageSnapshot(
                    deviceID: connection.deviceID,
                    timestamp: Int64(date.timeIntervalSince1970),
                    metadata: CockpitTeamSnapshotMetadata(status: .unavailable)),
                L("No eligible local activity is available."))
        },
        now: @escaping () -> Date = { Date() })
    {
        self.fileURL = fileURL
        self.clientFactory = clientFactory
        self.loadToken = loadToken
        self.saveToken = saveToken
        self.quotaInput = quotaInput
        self.accountIdentity = accountIdentity ?? { quotaInput()?.accountID }
        self.usageSnapshot = usageSnapshot
        self.now = now
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            guard data.count <= 40 * 1024 * 1024 else { throw CockpitTeamError.invalidResponse }
            let cache = try JSONDecoder().decode(Cache.self, from: data)
            if let connection = cache.connection { _ = try clientFactory(connection.endpoint) }
            self.connection = cache.connection
            self.identity = cache.identity
            self.sharedSettings = cache.identity?.sharedSettings ?? CockpitTeamSharedSettings()
            self.snapshots = cache.snapshots
            self.plan = cache.plan
            self.lastSyncedAt = cache.lastSyncedAt
            self.lastUploadTimestamp = cache.lastUploadTimestamp
        } catch {
            self.canSave = false
            self.errorMessage = L("Team data could not be read. The saved file has been preserved.")
        }
    }

    var currentAccountAvailable: Bool {
        self.validQuota != nil
    }

    var accountMatches: Bool {
        guard let bound = self.connection?.boundAccountID, let quota = self.validQuota else { return false }
        return bound == quota.accountID
    }

    var currentPerson: CockpitTeamPerson? {
        guard let device = self.connection?.deviceID else { return nil }
        return self.sharedSettings.value?.groups.groups.first { $0.deviceIDs.contains(device) }
    }

    var currentPlan: CockpitTeamDailyPlan? {
        guard let plan, plan.basis.localDate == Self.day(self.now()),
              let reset = Self.date(plan.basis.resetsAt), reset > self.now()
        else { return nil }
        return plan
    }

    var recommendedTotal: Double? {
        guard let plan = self.currentPlan else { return nil }
        return CockpitTeamAllocation.recommendation(basis: plan.basis, riskPercent: plan.risk.value ?? 0)
    }

    var allocations: [String: Double] {
        guard let total = self.recommendedTotal, let plan = self.currentPlan else { return [:] }
        let people = self.sharedSettings.value?.groups.groups.filter { !$0.deviceIDs.isEmpty }.map(\.id) ?? []
        return CockpitTeamAllocation.allocate(total: total, people: people, overrides: plan.people)?.allocations ?? [:]
    }

    var validQuota: QuotaInput? {
        guard let input = self.quotaInput(), !input.accountID.isEmpty,
              input.observedAt <= self.now().addingTimeInterval(300),
              self.now().timeIntervalSince(input.observedAt) <= 15 * 60,
              input.resetsAt > self.now(), input.resetsAt <= self.now().addingTimeInterval(8 * 86400),
              input.remainingPercent.isFinite, (0...100).contains(input.remainingPercent)
        else { return nil }
        return input
    }

    var basis: CockpitTeamPlanBasis? {
        guard self.accountMatches, let input = self.validQuota,
              Self.day(input.observedAt) == Self.day(self.now()) else { return nil }
        return CockpitTeamPlanBasis(
            localDate: Self.day(self.now()),
            anchorAt: Self.timestamp(input.observedAt),
            remainingPercent: input.remainingPercent,
            resetsAt: Self.timestamp(input.resetsAt))
    }

    func start() {
        guard self.pollingTask == nil else { return }
        self.observingAccount = true
        self.observeAccount()
        self.reconcileAccount()
        self.pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    func stop() {
        self.observingAccount = false
        self.pollingTask?.cancel()
        self.pollingTask = nil
        self.generation = UUID()
        self.isBusy = false
    }

    func bindCurrentAccount() {
        guard let input = self.validQuota, self.connection != nil else { return }
        self.generation = UUID()
        self.isBusy = false
        self.connection?.boundAccountID = input.accountID
        self.connection?.boundAt = self.now()
        self.connection?.shareUsage = false
        self.plan = nil
        self.lastUploadAt = nil
        self.persist()
    }

    func setUsageSharing(_ enabled: Bool) {
        guard !enabled || self.accountMatches else { return }
        self.generation = UUID()
        self.isBusy = false
        self.connection?.shareUsage = enabled
        if enabled { self.connection?.boundAt = self.now() }
        self.lastUploadAt = nil
        self.persist()
    }

    func setEnabled(_ enabled: Bool) {
        self.generation = UUID()
        self.isBusy = false
        self.connection?.enabled = enabled
        self.persist()
    }

    func disconnect() {
        // The v2 server has no owner recovery or transfer endpoint. Keep the only owner key recoverable.
        if self.connection?.role == .owner {
            self.setEnabled(false)
            return
        }
        self.generation = UUID()
        self.isBusy = false
        do {
            if let connection { try self.saveToken(nil, connection.endpoint, connection.deviceID) }
            self.connection = nil
            self.identity = nil
            self.sharedSettings = CockpitTeamSharedSettings()
            self.snapshots = []
            self.plan = nil
            self.inviteCode = nil
            self.inviteExpiresAt = nil
            self.lastSyncedAt = nil
            self.lastUploadAt = nil
            self.lastUploadTimestamp = nil
            self.persist()
        } catch { self.errorMessage = L("The team credential could not be removed from Keychain.") }
    }

    func reconcileAccount() {
        guard let bound = self.connection?.boundAccountID,
              let accountID = self.accountIdentity(), bound != accountID else { return }
        self.generation = UUID()
        self.isBusy = false
        self.connection?.shareUsage = false
        self.connection?.boundAccountID = nil
        self.connection?.boundAt = nil
        self.plan = nil
        self.lastUploadAt = nil
        self.uploadStatus = L("Account changed or quota is stale. Usage sharing is paused.")
        self.persist()
    }

    private func observeAccount() {
        guard self.observingAccount else { return }
        withObservationTracking {
            _ = self.accountIdentity()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observingAccount else { return }
                self.reconcileAccount()
                self.observeAccount()
            }
        }
    }

    func persist() {
        guard self.canSave else { return }
        do {
            try self.persistThrowing()
        } catch {
            self.errorMessage = L("Team changes could not be saved on this Mac.")
        }
    }

    func persistThrowing() throws {
        guard self.canSave else { throw CockpitTeamError.invalidResponse }
        self.identity?.sharedSettings = self.sharedSettings
        let cache = Cache(
            connection: self.connection,
            identity: self.identity,
            snapshots: self.snapshots,
            plan: self.plan,
            lastSyncedAt: self.lastSyncedAt,
            lastUploadTimestamp: self.lastUploadTimestamp)
        let data = try JSONEncoder().encode(cache)
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: self.fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.fileURL.path)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    deinit { self.pollingTask?.cancel() }
}
