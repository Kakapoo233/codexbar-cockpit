import CodexBarCore
import Foundation

/// The device scope deliberately includes all accounts in the local source, never a quota account.
enum CockpitLocalComfortProjection {
    static func tokens(
        snapshot: CostUsageTokenSnapshot?,
        isAmbient: Bool,
        bucketCalendar: Calendar,
        now: Date = Date(),
        calendar: Calendar = .current) -> Int?
    {
        guard isAmbient,
              bucketCalendar.timeZone.identifier == calendar.timeZone.identifier,
              let snapshot, snapshot.historyIsFullyScanned,
              calendar.isDate(snapshot.updatedAt, inSameDayAs: now),
              (0...300).contains(now.timeIntervalSince(snapshot.updatedAt)),
              let entry = snapshot.currentDayEntry(calendar: calendar),
              entry.incompleteRequestCount == 0,
              let tokens = entry.totalTokens, tokens >= 0
        else { return nil }
        return tokens
    }
}
