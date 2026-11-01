import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitResetHistoryStoreTests {
    @Test func `successful sync announces the next estimate once across refreshes and restarts`() async throws {
        try await self.withFixture { fixture in
            let history = try fixture.history(anchor: "cycle-one")
            let loader = Loader(history: history)
            let store = fixture.store(loader: loader)
            #expect(store.history == nil)
            #expect(await loader.calls == 0)
            store.start()
            defer { store.stop() }
            await store.refresh()
            #expect(store.history == history)
            #expect(store.lastSyncedAt == fixture.now)
            #expect(fixture.notices.count == 1)
            let notice = try #require(fixture.notices.first)
            #expect(notice.isCurrent())
            notice.completion(true)
            await store.refresh()
            #expect(fixture.notices.count == 1)
            store.stop()

            let reloaded = fixture.store(loader: loader)
            #expect(reloaded.history == history)
            reloaded.start()
            defer { reloaded.stop() }
            await reloaded.refresh()
            #expect(fixture.notices.count == 1)
        }
    }

    @Test func `cached history remains visible offline without notifying from stale cache`() async throws {
        try await self.withFixture { fixture in
            let history = try fixture.history(anchor: "cached-cycle")
            let loader = Loader(history: history)
            let first = fixture.store(loader: loader)
            await first.refresh()
            #expect(fixture.notices.isEmpty)
            await loader.setFailure(true)
            let offline = fixture.store(loader: loader)
            let cachedForecast = offline.forecast
            offline.start()
            defer { offline.stop() }
            await offline.refresh()
            #expect(offline.history == history)
            #expect(offline.lastSyncedAt == fixture.now)
            #expect(offline.forecast == cachedForecast)
            #expect(offline.errorMessage != nil)
            #expect(fixture.notices.isEmpty)
        }
    }

    @Test func `failed delivery retries but disabling invalidates an in flight notice`() async throws {
        try await self.withFixture { fixture in
            let loader = try Loader(history: fixture.history(anchor: "retry-cycle"))
            let store = fixture.store(loader: loader)
            store.start()
            defer { store.stop() }
            await store.refresh()
            let failed = try #require(fixture.notices.last)
            failed.completion(false)
            #expect(store.notificationErrorMessage != nil)
            #expect(!FileManager.default.fileExists(atPath: fixture.receiptsURL.path))
            await store.refresh()
            #expect(fixture.notices.count == 2)
            let cancelled = try #require(fixture.notices.last)
            fixture.enabled = false
            store.notificationPreferenceDidChange()
            #expect(!cancelled.isCurrent())
            cancelled.completion(true)
            #expect(!FileManager.default.fileExists(atPath: fixture.receiptsURL.path))
            #expect(fixture.removed.contains(cancelled.identifier))
            fixture.enabled = true
            store.notificationPreferenceDidChange()
            #expect(fixture.notices.count == 3)
            let delivered = try #require(fixture.notices.last)
            delivered.completion(true)
            #expect(store.notificationErrorMessage == nil)
            #expect(FileManager.default.fileExists(atPath: fixture.receiptsURL.path))
        }
    }

    @Test func `a replacement estimate cancels old delivery and remembers only the current cycle`() async throws {
        try await self.withFixture { fixture in
            let loader = try Loader(history: fixture.history(anchor: "old-cycle"))
            let store = fixture.store(loader: loader)
            store.start()
            defer { store.stop() }
            await store.refresh()
            let old = try #require(fixture.notices.last)
            try await loader.setHistory(fixture.history(anchor: "new-cycle", shift: 3600))
            await store.refresh()
            #expect(!old.isCurrent())
            old.completion(true)
            #expect(fixture.notices.count == 2)
            let current = try #require(fixture.notices.last)
            #expect(current.isCurrent())
            current.completion(true)
            let receipts = try JSONDecoder().decode([String].self, from: Data(contentsOf: fixture.receiptsURL))
            #expect(receipts == ["local:new-cycle"])
        }
    }

    @Test func `overdue estimates are retained without announcing a fictional next cycle`() async throws {
        try await self.withFixture { fixture in
            let loader = try Loader(history: fixture.history(anchor: "overdue", shift: -4 * 86400))
            let store = fixture.store(loader: loader)
            store.start()
            defer { store.stop() }
            await store.refresh()
            let forecast = try #require(store.forecast)
            #expect(forecast.isOverdue(at: fixture.now))
            #expect(fixture.notices.isEmpty)
            let estimatedAt = forecast.estimatedAt
            await store.refresh()
            #expect(store.forecast?.estimatedAt == estimatedAt)
        }
    }

    @Test func `concurrent refreshes share one load and stop discards a delayed result`() async throws {
        try await self.withFixture { fixture in
            let gate = Gate()
            let store = CockpitResetHistoryStore(
                cacheURL: fixture.cacheURL,
                receiptsURL: fixture.receiptsURL,
                notificationsEnabled: { fixture.enabled },
                fetch: { try await gate.load() },
                now: { fixture.now },
                post: { fixture.notices.append($0) },
                remove: { fixture.removed.append($0) })
            store.start()
            let first = Task { await store.refresh() }
            let second = Task { await store.refresh() }
            for _ in 0..<100 where await gate.calls == 0 {
                await Task.yield()
            }
            #expect(await gate.calls == 1)
            #expect(store.isRefreshing)
            store.stop()
            try await gate.finish(fixture.history(anchor: "discarded"))
            await first.value
            await second.value
            #expect(!store.isRefreshing)
            #expect(store.history == nil)
            #expect(fixture.notices.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: fixture.cacheURL.path))
        }
    }

    @Test func `corrupt persisted files survive synchronization and disable unsafe duplicate receipts`() async throws {
        try await self.withFixture { fixture in
            let original = Data("not-json".utf8)
            try original.write(to: fixture.cacheURL)
            try original.write(to: fixture.receiptsURL)
            let history = try fixture.history(anchor: "preserved")
            let store = fixture.store(loader: Loader(history: history))
            #expect(store.errorMessage != nil)
            #expect(store.notificationErrorMessage != nil)
            store.start()
            defer { store.stop() }
            await store.refresh()
            #expect(store.history == history)
            #expect(try Data(contentsOf: fixture.cacheURL) == original)
            #expect(try Data(contentsOf: fixture.receiptsURL) == original)
            #expect(fixture.notices.isEmpty)
        }
    }

    @Test func `announced future resets notify immediately even when history backfill fails`() async throws {
        try await self.withFixture { fixture in
            let loader = try Loader(history: fixture.history(anchor: "history-unavailable"))
            let scheduled = try fixture.scheduled(id: "announced-plan")
            let status = CockpitResetStatus(generatedAt: fixture.now, scheduledReset: scheduled)
            await loader.setStatus(status)
            await loader.setFailure(true)
            let store = fixture.store(loader: loader, includesStatus: true)
            store.start()
            defer { store.stop() }
            await store.refresh()
            #expect(store.history == nil)
            #expect(store.status == status)
            #expect(store.lastStatusSyncedAt == fixture.now)
            #expect(store.lastSyncedAt == nil)
            #expect(store.errorMessage != nil)
            let notice = try #require(fixture.notices.first)
            #expect(notice.title == L("cockpit_reset_scheduled_notification_title"))
            #expect(notice.isCurrent())
            notice.completion(true)
            await store.refresh()
            #expect(fixture.notices.count == 1)
        }
    }

    @Test func `minute status polls avoid full backfill until a new reset appears`() async throws {
        try await self.withFixture { fixture in
            let history = try fixture.history(anchor: "known-cycle")
            let loader = Loader(history: history)
            await loader.setStatus(CockpitResetStatus(generatedAt: fixture.now, latestReset: history.events.first))
            fixture.enabled = false
            let store = fixture.store(loader: loader, includesStatus: true)
            store.start()
            defer { store.stop() }
            await store.refresh()
            #expect(await loader.calls == 1)
            await store.refresh(forceHistory: false)
            #expect(await loader.calls == 1)
            #expect(await loader.statusCalls == 2)
            let newer = try fixture.history(anchor: "new-cycle", shift: 3600)
            await loader.setHistory(newer)
            await loader.setStatus(CockpitResetStatus(generatedAt: fixture.now, latestReset: newer.events.first))
            await store.refresh(forceHistory: false)
            #expect(await loader.calls == 2)
            #expect(store.history == newer)
        }
    }

    @Test func `watch episodes deduplicate and expired or stale watches never announce`() async throws {
        try await self.withFixture { fixture in
            let empty = CockpitResetHistory(events: [], generatedAt: fixture.now)
            let loader = Loader(history: empty)
            let watch = try fixture.watch(id: "watch-one")
            await loader.setStatus(CockpitResetStatus(generatedAt: fixture.now, activeWatch: watch))
            let store = fixture.store(loader: loader, includesStatus: true)
            store.start()
            defer { store.stop() }
            await store.refresh()
            let notice = try #require(fixture.notices.first)
            #expect(notice.title == L("cockpit_reset_watch_notification_title"))
            notice.completion(true)
            await store.refresh(forceHistory: false)
            #expect(fixture.notices.count == 1)
            fixture.now = fixture.now.addingTimeInterval(601)
            await loader.setStatus(CockpitResetStatus(generatedAt: fixture.now, activeWatch: watch))
            await store.refresh(forceHistory: false)
            #expect(fixture.notices.count == 1)
            let stale = try CockpitResetStatus(
                generatedAt: fixture.now.addingTimeInterval(-3600),
                activeWatch: fixture.watch(id: "stale-watch"))
            await loader.setStatus(stale)
            await store.refresh(forceHistory: false)
            #expect(fixture.notices.count == 1)
            try await loader.setStatus(CockpitResetStatus(
                generatedAt: fixture.now, activeWatch: fixture.watch(id: "watch-two")))
            await store.refresh(forceHistory: false)
            #expect(fixture.notices.count == 2)
        }
    }

    @Test func `retry after prevents automatic and manual requests before the server deadline`() async throws {
        try await self.withFixture { fixture in
            let history = try fixture.history(anchor: "rate-limited")
            let loader = Loader(history: history)
            await loader.setRateLimited(true)
            let store = fixture.store(loader: loader, includesStatus: true)
            store.start()
            defer { store.stop() }
            await store.refresh()
            #expect(await loader.statusCalls == 1)
            #expect(await loader.calls == 0)
            await store.refresh()
            #expect(await loader.statusCalls == 1)
            #expect(await loader.calls == 0)
            fixture.now = fixture.now.addingTimeInterval(301)
            await loader.setRateLimited(false)
            await loader.setStatus(CockpitResetStatus(generatedAt: fixture.now))
            await store.refresh()
            #expect(await loader.statusCalls == 2)
            #expect(await loader.calls == 1)
        }
    }

    @Test func `manual refresh following a status only load finishes with one history backfill`() async throws {
        try await self.withFixture { fixture in
            fixture.enabled = false
            let history = try fixture.history(anchor: "cached-cycle")
            let loader = Loader(history: history)
            await fixture.store(loader: loader).refresh()
            let gate = StatusGate(status: CockpitResetStatus(generatedAt: fixture.now))
            let store = CockpitResetHistoryStore(
                cacheURL: fixture.cacheURL,
                receiptsURL: fixture.receiptsURL,
                notificationsEnabled: { false },
                fetch: { try await loader.load() },
                fetchStatus: { await gate.load() },
                now: { fixture.now },
                post: { fixture.notices.append($0) },
                remove: { fixture.removed.append($0) })
            let background = Task(priority: .low) { await store.refresh(forceHistory: false) }
            for _ in 0..<100 where await gate.calls == 0 {
                await Task.yield()
            }
            #expect(await gate.calls == 1)
            var manualStarted = false
            let manual = Task(priority: .high) {
                manualStarted = true
                await store.refresh()
            }
            for _ in 0..<100 where !manualStarted {
                await Task.yield()
            }
            #expect(manualStarted)
            await gate.finish()
            await background.value
            await manual.value
            #expect(await loader.calls == 2)
            #expect(await gate.calls == 2)
            #expect(!store.isRefreshing)
            #expect(store.history == history)
        }
    }

    @Test func `stale submission cleanup cannot remove a newer delivery of the same candidate`() async throws {
        try await self.withFixture { fixture in
            let loader = try Loader(history: fixture.history(anchor: "same-candidate"))
            var visible: Set<String> = []
            let store = CockpitResetHistoryStore(
                cacheURL: fixture.cacheURL,
                receiptsURL: fixture.receiptsURL,
                notificationsEnabled: { fixture.enabled },
                fetch: { try await loader.load() },
                now: { fixture.now },
                post: { fixture.notices.append($0) },
                remove: {
                    fixture.removed.append($0)
                    visible.remove($0)
                })
            store.start()
            defer { store.stop() }
            await store.refresh()
            let first = try #require(fixture.notices.first)
            let gate = SubmissionGate()
            let delayed = Task {
                let delivered = try await AppNotifications.deliverIfCurrent(
                    authorize: { true },
                    submit: {
                        await gate.wait()
                        visible.insert(first.identifier)
                    },
                    remove: { visible.remove(first.identifier) },
                    isCurrent: first.isCurrent)
                first.completion(delivered)
            }
            for _ in 0..<100 where await gate.calls == 0 {
                await Task.yield()
            }
            #expect(await gate.calls == 1)
            fixture.enabled = false
            store.notificationPreferenceDidChange()
            fixture.enabled = true
            store.notificationPreferenceDidChange()
            let second = try #require(fixture.notices.last)
            #expect(first.identifier != second.identifier)
            let currentDelivered = try await AppNotifications.deliverIfCurrent(
                authorize: { true },
                submit: { visible.insert(second.identifier) },
                remove: { visible.remove(second.identifier) },
                isCurrent: second.isCurrent)
            second.completion(currentDelivered)
            #expect(currentDelivered)
            await gate.finish()
            try await delayed.value
            #expect(visible == [second.identifier])
            #expect(!fixture.removed.contains(second.identifier))
            #expect(store.notificationErrorMessage == nil)
            let receipts = try JSONDecoder().decode([String].self, from: Data(contentsOf: fixture.receiptsURL))
            #expect(receipts == ["local:same-candidate"])
        }
    }

    @Test func `an older status snapshot does not suppress a newer history estimate`() async throws {
        try await self.withFixture { fixture in
            let history = try fixture.history(anchor: "newer-history")
            let loader = Loader(history: history)
            await loader.setStatus(CockpitResetStatus(generatedAt: fixture.now, latestReset: history.events[1]))
            let store = fixture.store(loader: loader, includesStatus: true)
            store.start()
            defer { store.stop() }
            await store.refresh()
            let notice = try #require(fixture.notices.first)
            #expect(notice.title == L("cockpit_reset_forecast_notification_title"))
            #expect(notice.isCurrent())
        }
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CockpitResetStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(Fixture(directory: directory))
    }

    @MainActor
    private final class Fixture {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let cacheURL: URL
        let receiptsURL: URL
        var enabled = true
        var notices: [CockpitResetHistoryStore.Notice] = []
        var removed: [String] = []

        init(directory: URL) {
            self.cacheURL = directory.appendingPathComponent("cache.json")
            self.receiptsURL = directory.appendingPathComponent("receipts.json")
        }

        func history(anchor: String, shift: TimeInterval = 0) throws -> CockpitResetHistory {
            let source = try #require(URL(string: "https://example.invalid/synthetic-reset"))
            let events: [CockpitResetEvent] = try (0..<4).map { index in
                let eventID = index == 0 ? anchor : "\(anchor)-\(index)"
                let daysAgo = Double(1 + 2 * index)
                let offset: TimeInterval = shift - daysAgo * 86400
                let announcedAt = self.now.addingTimeInterval(offset)
                return try CockpitResetEvent(
                    id: eventID,
                    kind: .regular,
                    announcedAt: announcedAt,
                    text: "Synthetic reset announcement",
                    sourceType: "observed",
                    sourceURL: source)
            }
            return CockpitResetHistory(events: events, generatedAt: self.now)
        }

        func scheduled(id: String) throws -> CockpitScheduledReset {
            try CockpitScheduledReset(
                id: id,
                announcedAt: self.now,
                scheduledFor: self.now.addingTimeInterval(12 * 3600),
                text: "Synthetic upcoming reset",
                sourceURL: #require(URL(string: "https://example.invalid/announcement")))
        }

        func watch(id: String) throws -> CockpitResetWatch {
            try CockpitResetWatch(
                id: id,
                level: "elevated",
                resetChancePercent: 60,
                forecastWindow: "Synthetic forecast window",
                observedAt: self.now,
                expiresAt: self.now.addingTimeInterval(600),
                text: "Synthetic watch prediction",
                sourceURL: #require(URL(string: "https://example.invalid/watch")))
        }

        func store(loader: Loader, includesStatus: Bool = false) -> CockpitResetHistoryStore {
            let fetchStatus: CockpitResetHistoryStore.FetchStatus? = if includesStatus {
                { @Sendable in try await loader.loadStatus() }
            } else {
                nil
            }
            return CockpitResetHistoryStore(
                cacheURL: self.cacheURL,
                receiptsURL: self.receiptsURL,
                notificationsEnabled: { self.enabled },
                fetch: { try await loader.load() },
                fetchStatus: fetchStatus,
                now: { self.now },
                post: { self.notices.append($0) },
                remove: { self.removed.append($0) })
        }
    }

    private actor Loader {
        var history: CockpitResetHistory
        var calls = 0
        var fails = false
        var status: CockpitResetStatus?
        var statusCalls = 0
        var rateLimited = false

        init(history: CockpitResetHistory) { self.history = history }

        func load() throws -> CockpitResetHistory {
            self.calls += 1
            if self.fails { throw URLError(.notConnectedToInternet) }
            return self.history
        }

        func loadStatus() throws -> CockpitResetStatus {
            self.statusCalls += 1
            if self.rateLimited { throw CockpitResetHistoryError.rateLimited(retryAfter: 300) }
            guard let status = self.status else { throw URLError(.badServerResponse) }
            return status
        }

        func setStatus(_ value: CockpitResetStatus) { self.status = value }
        func setRateLimited(_ value: Bool) { self.rateLimited = value }
        func setFailure(_ value: Bool) { self.fails = value }
        func setHistory(_ value: CockpitResetHistory) { self.history = value }
    }

    private actor StatusGate {
        let status: CockpitResetStatus
        var calls = 0
        var continuation: CheckedContinuation<CockpitResetStatus, Never>?

        init(status: CockpitResetStatus) { self.status = status }

        func load() async -> CockpitResetStatus {
            self.calls += 1
            if self.calls > 1 { return self.status }
            return await withCheckedContinuation { self.continuation = $0 }
        }

        func finish() {
            self.continuation?.resume(returning: self.status)
            self.continuation = nil
        }
    }

    private actor SubmissionGate {
        var calls = 0
        var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            self.calls += 1
            await withCheckedContinuation { self.continuation = $0 }
        }

        func finish() {
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    private actor Gate {
        var calls = 0
        var continuation: CheckedContinuation<CockpitResetHistory, Error>?

        func load() async throws -> CockpitResetHistory {
            self.calls += 1
            return try await withCheckedThrowingContinuation { self.continuation = $0 }
        }

        func finish(_ history: CockpitResetHistory) {
            self.continuation?.resume(returning: history)
            self.continuation = nil
        }
    }
}
