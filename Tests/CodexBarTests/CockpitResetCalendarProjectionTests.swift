import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitResetCalendarProjectionTests {
    @Test(arguments: [-3600.0, 3600.0])
    func `a newer public reset suppresses the old calendar estimate but an older status does not`(
        statusOffset: TimeInterval) async throws
    {
        let now = Date()
        let history = try Self.history(now: now)
        let anchor = try #require(history.events.first)
        let latest = try CockpitResetEvent(
            id: "status-latest",
            kind: .regular,
            announcedAt: anchor.announcedAt.addingTimeInterval(statusOffset),
            text: "Synthetic observation",
            sourceType: "observed",
            sourceURL: CockpitResetHistoryClient.websiteURL)
        let status = CockpitResetStatus(
            generatedAt: now,
            latestReset: latest)
        try await Self.withStore(
            history: history,
            status: status)
        { store in
            #expect(store.forecast != nil)
            #expect((store.calendarLocalForecast == nil) == (statusOffset > 0))
        }
    }

    @Test
    func `an undated scheduled announcement stays undated and supersedes a local estimate`() async throws {
        let now = Date()
        let reset = try CockpitScheduledReset(
            id: "upcoming",
            announcedAt: now,
            scheduledFor: nil,
            text: "Synthetic upcoming reset",
            sourceURL: CockpitResetHistoryClient.websiteURL)
        let status = CockpitResetStatus(
            generatedAt: now,
            scheduledReset: reset)
        try await Self.withStore(
            history: Self.history(now: now),
            status: status)
        { store in
            #expect(store.pendingCalendarReset?.id == "upcoming")
            #expect(store.pendingCalendarReset?.scheduledFor == nil)
            #expect(store.calendarLocalForecast == nil)
        }
    }

    @Test(arguments: [-3600.0, 3600.0])
    func `only an unexpired website watch takes precedence in the calendar`(expiryOffset: TimeInterval) async throws {
        let now = Date()
        let watch = try CockpitResetWatch(
            id: "watch",
            level: "strong",
            resetChancePercent: 60,
            forecastWindow: "Synthetic upcoming window",
            observedAt: now.addingTimeInterval(-7200),
            expiresAt: now.addingTimeInterval(expiryOffset),
            text: "Synthetic forecast",
            sourceURL: CockpitResetHistoryClient.websiteURL)
        let status = CockpitResetStatus(
            generatedAt: now,
            activeWatch: watch)
        try await Self.withStore(
            history: Self.history(now: now),
            status: status)
        { store in
            #expect((store.activeCalendarWatch != nil) == (expiryOffset > 0))
            #expect((store.calendarLocalForecast == nil) == (expiryOffset > 0))
        }
    }

    private static func history(now: Date) throws -> CockpitResetHistory {
        let events = try (0..<4).map { index in
            try CockpitResetEvent(
                id: "regular-\(index)",
                kind: .regular,
                announcedAt: now.addingTimeInterval(-3600 - Double(index) * 86400),
                text: "Synthetic reset",
                sourceType: "observed",
                sourceURL: CockpitResetHistoryClient.websiteURL)
        }
        return CockpitResetHistory(
            events: events,
            generatedAt: now)
    }

    private static func withStore(
        history: CockpitResetHistory,
        status: CockpitResetStatus,
        body: (CockpitResetHistoryStore) throws -> Void) async throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CockpitResetHistoryStore(
            cacheURL: root.appendingPathComponent("history.json"),
            receiptsURL: root.appendingPathComponent("notices.json"),
            notificationsEnabled: { false },
            fetch: { history },
            fetchStatus: { status },
            post: { _ in Issue.record("Calendar projection must not deliver notifications") },
            remove: { _ in })
        await store.refresh()
        try body(store)
    }
}
