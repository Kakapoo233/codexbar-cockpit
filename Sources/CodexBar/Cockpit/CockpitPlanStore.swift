import CodexBarCore
import CryptoKit
import Foundation
import Observation

/// Persists observations from the existing provider refresh loop; never fetches credentials or usage itself.
@MainActor
@Observable
final class CockpitPlanStore {
    private(set) var state: CockpitPlanState
    private(set) var errorMessage: String?
    private(set) var availableProviders: [UsageProvider] = []
    private var accounts: [UsageProvider: String] = [:]
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var canSave = true

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? CockpitAppIdentity
            .applicationSupportDirectory(home: FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("cockpit-plan.json")
        self.state = CockpitPlanState()
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            self.state = try JSONDecoder().decode(CockpitPlanState.self, from: Data(contentsOf: self.fileURL))
        } catch {
            self.canSave = false
            self.errorMessage = "无法读取已有计划记录，已保留原文件：\(error.localizedDescription)"
        }
    }

    func accountID(for provider: UsageProvider) -> String {
        self.accounts[provider] ?? "unidentified"
    }

    func status(for provider: UsageProvider, on date: Date = Date()) -> CockpitDayStatus {
        self.state.status(providerID: provider.rawValue, accountID: self.accountID(for: provider), on: date)
    }

    func ingest(_ store: UsageStore) {
        let snapshots = Dictionary(uniqueKeysWithValues: UsageProvider.allCases.compactMap { provider in
            store.menuBarSnapshot(for: provider.instanceID).map { (provider.instanceID, $0) }
        })
        self.ingest(snapshots)
    }

    func ingest(_ snapshots: [ProviderInstanceID: UsageSnapshot]) {
        var changed = false
        var currentAccounts: [UsageProvider: String] = [:]
        for provider in UsageProvider.allCases {
            guard let snapshot = snapshots[provider.instanceID],
                  let identity = snapshot.identity(for: provider.instanceID),
                  let owner = identity.accountID ?? identity.accountEmail,
                  !owner.isEmpty,
                  let window = Self.weeklyWindow(in: snapshot),
                  let reset = window.resetsAt
            else { continue }
            let scope = [provider.rawValue, owner, identity.accountOrganization ?? ""].joined(separator: "\u{1f}")
            let accountID = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
            currentAccounts[provider] = accountID
            let observation = CockpitQuotaSnapshot(
                providerID: provider.rawValue,
                accountID: accountID,
                capturedAt: snapshot.updatedAt,
                remainingPercent: max(0, min(100, 100 - window.usedPercent)),
                resetsAt: reset,
                windowDuration: Double(window.windowMinutes ?? 10080) * 60)
            changed = self.state.record(observation) || changed
        }
        self.accounts = currentAccounts
        self.availableProviders = currentAccounts.keys.sorted { $0.rawValue < $1.rawValue }
        if changed { self.save() }
    }

    func setPersonalCap(_ percent: Double?, for provider: UsageProvider) {
        guard self.accounts[provider] != nil else { return }
        self.state.setPersonalCap(percent, providerID: provider.rawValue, accountID: self.accountID(for: provider))
        self.save()
    }

    func recordComfort(_ feeling: CockpitFeeling, for provider: UsageProvider, totalTokens: Int? = nil) {
        guard self.accounts[provider] != nil else { return }
        self.state.recordComfort(
            feeling,
            providerID: provider.rawValue,
            accountID: self.accountID(for: provider),
            totalTokens: totalTokens,
            coverage: totalTokens == nil ? .partial : .complete)
        self.save()
    }

    /// Local usage can span accounts. Its subjective records must never be attached to a quota account.
    func recordLocalComfort(
        _ feeling: CockpitFeeling,
        for provider: UsageProvider,
        on date: Date = Date(),
        totalTokens: Int?,
        coverage: CockpitCoverage = .partial,
        calendar: Calendar = .current)
    {
        self.state.recordComfort(
            feeling,
            providerID: provider.rawValue,
            accountID: "local-machine",
            on: date,
            totalTokens: totalTokens,
            coverage: totalTokens == nil ? .partial : coverage,
            calendar: calendar)
        self.save()
    }

    /// Editing a calendar rating preserves any measurement captured with the original record.
    func setLocalComfortFeeling(
        _ feeling: CockpitFeeling,
        for provider: UsageProvider,
        on date: Date,
        calendar: Calendar = .current)
    {
        let day = CockpitCalendar.dateKey(for: date, calendar: calendar)
        let previous = self.state.comfortRecords.last {
            $0.providerID == provider.rawValue && $0.accountID == "local-machine"
                && $0.localDateKey == day && $0.timeZoneIdentifier == calendar.timeZone.identifier
        }
        self.recordLocalComfort(
            feeling,
            for: provider,
            on: previous?.recordedAt ?? date,
            totalTokens: previous?.totalTokens,
            coverage: previous?.coverage ?? .partial,
            calendar: calendar)
    }

    func clearLocalComfort(
        for provider: UsageProvider,
        on date: Date,
        calendar: Calendar = .current)
    {
        self.state.clearComfort(
            providerID: provider.rawValue,
            accountID: "local-machine",
            on: date,
            calendar: calendar)
        self.save()
    }

    static func weeklyWindow(in snapshot: UsageSnapshot) -> RateWindow? {
        [snapshot.secondary, snapshot.primary, snapshot.tertiary].compactMap(\.self).first { window in
            guard let minutes = window.windowMinutes, let reset = window.resetsAt else { return false }
            return minutes == 10080 && !window.isSyntheticPlaceholder && window.usedPercent.isFinite
                && reset > snapshot.updatedAt
        }
    }

    private func save() {
        guard self.canSave else { return }
        do {
            let directory = self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(self.state)
            try data.write(to: self.fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.fileURL.path)
            self.errorMessage = nil
        } catch {
            self.errorMessage = "计划记录未能保存：\(error.localizedDescription)"
        }
    }
}
