import CodexBarCore
import CryptoKit
import Foundation

extension CockpitTeamStore {
    convenience init(usageStore: UsageStore, settings: SettingsStore) {
        let file = CockpitAppIdentity.applicationSupportDirectory(home: FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("team-sync.json")
        self.init(
            fileURL: file,
            loadToken: { try CockpitTeamCredentialStore.load(endpoint: $0, deviceID: $1) },
            saveToken: { try CockpitTeamCredentialStore.save($0, endpoint: $1, deviceID: $2) },
            quotaInput: { [weak usageStore] in
                guard let snapshot = usageStore?.menuBarSnapshot(for: UsageProvider.codex.instanceID),
                      let hash = Self.localAccountID(snapshot),
                      let window = CockpitPlanStore.weeklyWindow(in: snapshot), let reset = window.resetsAt
                else { return nil }
                return QuotaInput(
                    accountID: hash,
                    observedAt: snapshot.updatedAt,
                    remainingPercent: max(0, min(100, 100 - window.usedPercent)),
                    resetsAt: reset)
            },
            accountIdentity: { [weak usageStore] in
                Self.localAccountID(usageStore?.menuBarSnapshot(for: UsageProvider.codex.instanceID))
            },
            usageSnapshot: { [weak usageStore, weak settings] connection, now in
                guard let usageStore, let settings else {
                    return (
                        CockpitTeamUsageSnapshot(
                            deviceID: connection.deviceID,
                            timestamp: Int64(now.timeIntervalSince1970)),
                        L("No eligible local activity is available."))
                }
                let liveID = settings.codexVisibleAccountProjection.liveVisibleAccountID
                let sourceID = liveID.map { "codex:\($0)" } ?? "codex:local"
                let result = CockpitTeamUsageProjection.build(
                    publication: usageStore.spendDashboardPublication,
                    ambientSourceID: settings.codexResolvedActiveSource == .liveSystem ? sourceID : nil,
                    deviceID: connection.deviceID,
                    uploadEnabled: connection.shareUsage,
                    independentSourceConfirmed: connection.shareUsage,
                    boundAt: connection.boundAt,
                    now: now)
                let status: String = switch result.reason {
                case .uploadDisabled:
                    L("Usage sharing is off. Team budgets still synchronize.")
                case .awaitingFirstFullDay:
                    L("Sharing starts on the next complete Beijing day after confirmation.")
                case .incompatibleTimeZone:
                    L("Set the statistics time zone to Asia/Shanghai to share daily activity with this service.")
                case nil:
                    L("Sharing local Codex daily aggregates. Current-day data is partial.")
                default:
                    L("No eligible local activity is available. Check the live Codex source and statistics.")
                }
                return (result.snapshot, status)
            })
    }

    private static func localAccountID(_ snapshot: UsageSnapshot?) -> String? {
        guard let identity = snapshot?.identity(for: UsageProvider.codex.instanceID),
              let owner = identity.accountID ?? identity.accountEmail, !owner.isEmpty else { return nil }
        let scope = ["codex", owner, identity.accountOrganization ?? ""].joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
