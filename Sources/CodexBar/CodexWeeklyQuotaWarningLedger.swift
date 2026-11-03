import CodexBarCore
import CryptoKit
import Foundation

/// Local Codex weekly threshold episodes, including quiet startup baselines, independent of provider state.
@MainActor
final class CodexWeeklyQuotaWarningLedger {
    static let defaultsKey = "codexWeeklyQuotaWarningLedgerV1"
    static let maximumEntries = 128
    private static let maximumSerializedBytes = 256 * 1024

    private struct Entry: Codable {
        var trustedReset: Date?
        var lastRemaining: Double
        var observedAt: Date
        var firedThresholds: Set<Int>

        var isValid: Bool {
            self.lastRemaining.isFinite && (0...100).contains(self.lastRemaining)
                && self.observedAt.timeIntervalSinceReferenceDate.isFinite
                && (self.trustedReset?.timeIntervalSinceReferenceDate.isFinite ?? true)
                && self.firedThresholds.allSatisfy { (1...99).contains($0) }
        }
    }

    private struct Payload: Codable {
        let version: Int
        let entries: [String: Entry]
    }

    private let defaults: UserDefaults
    private let logger = CodexBarLog.logger(LogCategories.sessionQuotaNotifications)
    private var entries: [String: Entry]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
    }

    /// Returns at most one newly reached threshold after recording its receipt locally.
    /// A new owner starts quietly, including after an upgrade or an unproven credential rotation.
    func observe(owner: String, window: RateWindow, observedAt: Date, thresholds: [Int]) -> Int? {
        guard let ownerKey = Self.ownerKey(owner),
              !window.isSyntheticPlaceholder,
              window.usedPercent.isFinite, window.usedPercent >= 0,
              observedAt.timeIntervalSinceReferenceDate.isFinite,
              window.resetsAt?.timeIntervalSinceReferenceDate.isFinite ?? true
        else { return nil }
        let remaining = window.remainingPercent
        guard remaining.isFinite, (0...100).contains(remaining) else { return nil }
        let activeThresholds = QuotaWarningThresholds.active(thresholds)
        let futureReset = window.resetsAt.flatMap { $0 > observedAt ? $0 : nil }

        guard var entry = self.entries[ownerKey] else {
            // Existing low quota is a baseline, not another downward crossing after every launch.
            let baseline = Entry(
                trustedReset: futureReset,
                lastRemaining: remaining,
                observedAt: observedAt,
                firedThresholds: Set(activeThresholds.filter { remaining <= Double($0) }))
            if self.persist(baseline, ownerKey: ownerKey) {
                self.logDecision("quiet-baseline", remaining: remaining)
            }
            return nil
        }
        guard observedAt > entry.observedAt else { return nil }

        var previousRemaining: Double? = entry.lastRemaining
        var beginsNewCycle = false
        if let trustedReset = entry.trustedReset,
           trustedReset <= observedAt,
           let futureReset,
           UsageStore.limitResetBoundaryAdvanced(previous: trustedReset, current: futureReset)
        {
            entry.trustedReset = futureReset
            entry.firedThresholds.removeAll()
            previousRemaining = nil
            beginsNewCycle = true
        } else if entry.trustedReset == nil {
            // Learning missing metadata does not create another warning episode.
            entry.trustedReset = futureReset
        }
        // Keep a known anchor through missing metadata or future reset-time corrections. A fresh
        // high reading alone cannot clear delivered thresholds within that same quota cycle.
        let warning = activeThresholds.isEmpty ? nil : QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: previousRemaining,
            currentRemaining: remaining,
            thresholds: activeThresholds,
            alreadyFired: entry.firedThresholds)
        if let warning {
            entry.firedThresholds.formUnion(QuotaWarningNotificationLogic.firedThresholdsAfterWarning(
                threshold: warning, thresholds: activeThresholds))
        }
        entry.lastRemaining = remaining
        entry.observedAt = observedAt
        guard self.persist(entry, ownerKey: ownerKey) else { return nil }
        if let warning {
            self.logDecision(beginsNewCycle ? "new-cycle-warning" : "warning", remaining: remaining, threshold: warning)
        } else if beginsNewCycle {
            self.logDecision("new-cycle", remaining: remaining)
        }
        return warning
    }

    private func logDecision(_ decision: String, remaining: Double, threshold: Int? = nil) {
        var metadata = ["decision": decision, "remaining": String(format: "%.3f", remaining)]
        if let threshold { metadata["threshold"] = String(threshold) }
        self.logger.info("Codex weekly quota warning decision", metadata: metadata)
    }

    private static func ownerKey(_ owner: String) -> String? {
        let normalized = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 4096 else { return nil }
        let material = "codex-weekly-quota-warning-owner:v1\0\(normalized)"
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func load(from defaults: UserDefaults) -> [String: Entry] {
        guard let data = defaults.data(forKey: defaultsKey), data.count <= Self.maximumSerializedBytes,
              let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.version == 1
        else { return [:] }
        let valid = payload.entries.filter { key, entry in
            key.utf8.count == 64 && key.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            } && entry.isValid
        }
        let recent = valid.sorted { lhs, rhs in
            lhs.value.observedAt == rhs.value.observedAt
                ? lhs.key < rhs.key : lhs.value.observedAt > rhs.value.observedAt
        }.prefix(Self.maximumEntries)
        return Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })
    }

    @discardableResult
    private func persist(_ entry: Entry, ownerKey: String) -> Bool {
        guard entry.isValid else { return false }
        var updated = self.entries
        updated[ownerKey] = entry
        if updated.count > Self.maximumEntries {
            // Always retain the observation being committed, even if another owner has a bad future clock.
            let oldestOthers = updated.filter { $0.key != ownerKey }.sorted { lhs, rhs in
                lhs.value.observedAt == rhs.value.observedAt
                    ? lhs.key < rhs.key : lhs.value.observedAt < rhs.value.observedAt
            }
            for item in oldestOthers.prefix(updated.count - Self.maximumEntries) {
                updated.removeValue(forKey: item.key)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Payload(version: 1, entries: updated)),
              data.count <= Self.maximumSerializedBytes
        else { return false }
        // Reserve the episode before UserDefaults callbacks or any caller's sound/banner effects.
        self.entries = updated
        self.defaults.set(data, forKey: Self.defaultsKey)
        return true
    }
}
