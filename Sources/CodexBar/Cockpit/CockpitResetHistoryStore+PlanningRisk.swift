import CodexBarCore
import Foundation

extension CockpitResetHistoryStore {
    /// Upstream's default is a heuristic, not a measured probability. Text watch windows never
    /// become exact dates, and distant announcements do not imply spending the whole balance today.
    func planningRisk(accountResetAt: Date, on date: Date = Date()) -> CockpitResetRisk {
        guard accountResetAt > date,
              let status = self.status,
              (-300...15 * 60).contains(date.timeIntervalSince(status.generatedAt)) else { return .assumed }
        if let scheduled = status.scheduledReset,
           scheduled.kind == .regular, scheduled.isPending(at: date)
        {
            guard let deadline = scheduled.scheduledFor,
                  deadline > date, deadline < accountResetAt,
                  deadline.timeIntervalSince(date) <= 86400 else { return .assumed }
            return CockpitResetRisk(probability: 1, source: .announced)
        }
        if let watch = status.activeWatch, watch.isActive(at: date), let percent = watch.resetChancePercent {
            return CockpitResetRisk(probability: Double(percent) / 100, source: .estimated)
        }
        return .assumed
    }
}
