import CodexBarCore
import Foundation
import Observation

/// Public community history has its own cache and lifecycle, independent of account quota observations.
@MainActor
@Observable
final class CockpitResetHistoryStore {
    struct Notice {
        let identifier: String
        let title: String
        let body: String
        let isCurrent: @MainActor () -> Bool
        let completion: @MainActor (Bool) -> Void
    }

    typealias Fetch = @Sendable () async throws -> CockpitResetHistory
    typealias FetchStatus = @Sendable () async throws -> CockpitResetStatus
    typealias Post = @MainActor (Notice) -> Void
    static let refreshInterval: TimeInterval = 60
    static let historyRefreshInterval: TimeInterval = 15 * 60
    static let notificationIdentifier = "cockpit-reset-forecast"

    private(set) var history: CockpitResetHistory?
    private(set) var status: CockpitResetStatus?
    private(set) var forecast: CockpitResetForecast?
    private(set) var isRefreshing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastStatusSyncedAt: Date?
    private var statusErrorNotice: CockpitLocalizedMessage?
    var statusErrorMessage: String? {
        self.statusErrorNotice?.text
    }

    private var errorNotice: CockpitLocalizedMessage?
    var errorMessage: String? {
        self.errorNotice?.text
    }

    private var notificationErrorNotice: CockpitLocalizedMessage?
    var notificationErrorMessage: String? {
        self.notificationErrorNotice?.text
    }

    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let receiptsURL: URL
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let fetchStatus: FetchStatus?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let notificationsEnabled: @MainActor () -> Bool
    @ObservationIgnored private let post: Post
    @ObservationIgnored private let remove: @MainActor (String) -> Void
    @ObservationIgnored private let pollInterval: TimeInterval
    @ObservationIgnored private var deliveredAnchors: [String] = []
    @ObservationIgnored private var canSaveCache = true
    @ObservationIgnored private var canSaveReceipts = true
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var preferenceObservationID = UUID()
    @ObservationIgnored private var noticeID = UUID()
    @ObservationIgnored private var pendingAnchor: String?
    @ObservationIgnored private var activeNotificationIdentifiers: Set<String> = []
    @ObservationIgnored private var activeCandidate: Candidate?
    @ObservationIgnored private var hasFreshHistory = false
    @ObservationIgnored private var hasFreshStatus = false
    @ObservationIgnored private var historySyncedAt: Date?
    @ObservationIgnored private var currentRequestIncludesHistory = false
    @ObservationIgnored private var cacheReadError: CockpitLocalizedMessage?
    @ObservationIgnored private var receiptsReadError: CockpitLocalizedMessage?
    @ObservationIgnored private var retryNotBefore: Date?

    convenience init(settings: SettingsStore) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let client = CockpitResetHistoryClient()
        self.init(
            cacheURL: CockpitAppIdentity.cacheDirectory(home: home)
                .appendingPathComponent("codex-reset-history.json"),
            receiptsURL: CockpitAppIdentity.applicationSupportDirectory(home: home)
                .appendingPathComponent("codex-reset-notices.json"),
            notificationsEnabled: { settings.cockpitResetForecastNotificationsEnabled },
            fetch: { try await client.fetchHistory() },
            fetchStatus: { try await client.fetchStatus() },
            post: { notice in
                AppNotifications.shared.post(
                    idPrefix: "cockpit-reset-forecast",
                    title: notice.title,
                    body: notice.body,
                    identifier: notice.identifier,
                    categoryIdentifier: AppNotifications.cockpitResetForecastCategoryIdentifier,
                    isCurrent: notice.isCurrent,
                    onCompletion: notice.completion)
            },
            remove: { AppNotifications.shared.remove(identifier: $0) })
    }

    init(
        cacheURL: URL,
        receiptsURL: URL,
        notificationsEnabled: @escaping @MainActor () -> Bool,
        fetch: @escaping Fetch,
        fetchStatus: FetchStatus? = nil,
        now: @escaping @MainActor () -> Date = { Date() },
        pollInterval: TimeInterval = CockpitResetHistoryStore.refreshInterval,
        post: @escaping Post,
        remove: @escaping @MainActor (String) -> Void)
    {
        self.cacheURL = cacheURL
        self.receiptsURL = receiptsURL
        self.notificationsEnabled = notificationsEnabled
        self.fetch = fetch
        self.fetchStatus = fetchStatus
        self.now = now
        self.pollInterval = max(1, pollInterval)
        self.post = post
        self.remove = remove
        self.loadCache()
        self.loadReceipts()
    }

    func start() {
        guard !self.isStarted else { return }
        self.isStarted = true
        self.observeNotificationPreference()
        let interval = self.pollInterval
        self.pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh(forceHistory: false)
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
    }

    func stop() {
        self.isStarted = false
        self.preferenceObservationID = UUID()
        self.pollingTask?.cancel()
        self.pollingTask = nil
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.refreshID = UUID()
        self.isRefreshing = false
        self.hasFreshHistory = false
        self.hasFreshStatus = false
        self.cancelNotices()
    }

    /// Status is light enough for minute polling; full history refreshes separately or on a manual request.
    func refresh(forceHistory: Bool = true) async {
        if let task = self.refreshTask {
            let waitingID = self.refreshID
            await task.value
            if forceHistory, !self.currentRequestIncludesHistory, self.refreshID == waitingID, !Task.isCancelled {
                await self.refresh(forceHistory: true)
            }
            return
        }
        if let retryNotBefore, retryNotBefore > self.now() {
            self.errorNotice = CockpitLocalizedMessage("cockpit_reset_rate_limited", date: retryNotBefore)
            return
        }
        let id = UUID()
        self.refreshID = id
        self.isRefreshing = true
        let needsHistory = forceHistory || self.history == nil || self.historySyncedAt.map {
            self.now().timeIntervalSince($0) >= Self.historyRefreshInterval
        } != false
        self.currentRequestIncludesHistory = needsHistory
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishRefresh(id: id) }
            await self.load(id: id, needsHistory: needsHistory)
        }
        self.refreshTask = task
        await task.value
    }

    private func finishRefresh(id: UUID) {
        guard self.refreshID == id else { return }
        self.refreshTask = nil
        self.isRefreshing = false
    }

    private func load(id: UUID, needsHistory: Bool) async {
        var failure: CockpitLocalizedMessage?
        var reloadHistory = needsHistory
        var succeeded = false
        if let fetchStatus {
            do {
                let status = try await fetchStatus()
                guard !Task.isCancelled, self.refreshID == id else { return }
                if let latest = status.latestReset, !self.historyEventsContain(latest.id) { reloadHistory = true }
                self.currentRequestIncludesHistory = reloadHistory
                self.status = status
                self.lastStatusSyncedAt = self.now()
                self.statusErrorNotice = nil
                self.hasFreshStatus = abs(self.now().timeIntervalSince(status.generatedAt)) <= 5 * 60
                succeeded = true
                // Announced plans should be visible and notified before a slower history backfill finishes.
                self.postForecastIfNeeded()
            } catch {
                guard !Task.isCancelled, self.refreshID == id else { return }
                self.hasFreshStatus = false
                failure = self.refreshError(error)
                self.statusErrorNotice = failure
            }
        }
        if reloadHistory, self.retryNotBefore.map({ $0 <= self.now() }) != false {
            do {
                let history = try await self.fetch()
                guard !Task.isCancelled, self.refreshID == id else { return }
                self.history = history
                self.historySyncedAt = self.now()
                self.lastSyncedAt = self.historySyncedAt
                self.hasFreshHistory = abs(self.now().timeIntervalSince(history.generatedAt)) <= 24 * 3600
                self.forecast = CockpitResetForecast.estimate(events: history.events, now: self.now())
                succeeded = true
            } catch {
                guard !Task.isCancelled, self.refreshID == id else { return }
                self.hasFreshHistory = false
                failure = self.refreshError(error)
            }
        } else if let history {
            self.forecast = CockpitResetForecast.estimate(events: history.events, now: self.now())
        }
        self.errorNotice = failure ?? self.cacheReadError
        if succeeded {
            self.saveCache()
        }
        self.postForecastIfNeeded()
    }

    private func historyEventsContain(_ id: String) -> Bool {
        self.history?.events.contains { $0.id == id } == true
    }

    private func refreshError(_ error: any Error) -> CockpitLocalizedMessage {
        if let error = error as? CockpitResetHistoryError, case let .rateLimited(retryAfter) = error {
            let retry = self.now().addingTimeInterval(retryAfter)
            self.retryNotBefore = retry
            return CockpitLocalizedMessage("cockpit_reset_rate_limited", date: retry)
        }
        return CockpitLocalizedMessage("cockpit_reset_sync_failed", error.localizedDescription)
    }

    func notificationPreferenceDidChange() {
        if self.notificationsEnabled() {
            self.notificationErrorNotice = self.receiptsReadError
            self.postForecastIfNeeded()
        } else {
            self.cancelNotices()
            self.notificationErrorNotice = nil
        }
    }

    /// Uses fresh public metadata only as a planning horizon, independently of notification preferences.
    /// Text-only website watch windows cannot be converted into a precise reset deadline.
    func planningWindow(accountResetAt: Date, on date: Date = Date()) -> CockpitPlanningResetWindow? {
        let freshStatus = self.status.flatMap { status in
            (-300...15 * 60).contains(date.timeIntervalSince(status.generatedAt)) ? status : nil
        }
        let freshForecast = self.history.flatMap { history -> CockpitResetForecast? in
            guard (-300...24 * 3600).contains(date.timeIntervalSince(history.generatedAt)),
                  let synced = self.historySyncedAt,
                  (-300...Self.historyRefreshInterval * 2).contains(date.timeIntervalSince(synced)) else { return nil }
            return self.forecast
        }
        let hasStalePendingAnnouncement = freshStatus == nil
            && self.status?.scheduledReset?.isPending(at: date) == true
        return CockpitPlanningResetWindow.resolve(
            accountResetAt: accountResetAt,
            scheduled: freshStatus?.scheduledReset,
            forecast: hasStalePendingAnnouncement ? nil : freshForecast,
            latestPublicReset: self.status?.latestReset,
            now: date)
    }

    private func observeNotificationPreference() {
        let observationID = self.preferenceObservationID
        withObservationTracking {
            _ = self.notificationsEnabled()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted, self.preferenceObservationID == observationID else { return }
                self.observeNotificationPreference()
                self.notificationPreferenceDidChange()
            }
        }
    }

    private struct Candidate: Equatable {
        let key: String
        let title: String
        let body: String
    }

    private func candidate() -> Candidate? {
        let now = self.now()
        if self.hasFreshStatus, let status = self.status,
           let synced = self.lastStatusSyncedAt, (0...Self.refreshInterval * 3).contains(now.timeIntervalSince(synced))
        {
            if let scheduled = status.scheduledReset, scheduled.isPending(at: now),
               scheduled.scheduledFor.map({ $0 > now }) != false
            {
                return Candidate(
                    key: "scheduled:\(scheduled.id)",
                    title: L("cockpit_reset_scheduled_notification_title"),
                    body: scheduled.scheduledFor.map {
                        L("cockpit_reset_scheduled_notification_body", Self.dateText($0))
                    } ?? L("cockpit_reset_scheduled_notification_unspecified"))
            }
            if let watch = status.activeWatch, watch.isActive(at: now) {
                return Candidate(
                    key: "watch:\(watch.id)",
                    title: L("cockpit_reset_watch_notification_title"),
                    body: L("cockpit_reset_watch_notification_body", watch.forecastWindow))
            }
        }
        // A known pending source announcement outranks a local estimate even while offline.
        if let scheduled = self.status?.scheduledReset, scheduled.isPending(at: now) { return nil }
        if self.status?.activeWatch?.isActive(at: now) == true { return nil }
        guard self.hasFreshHistory, let forecast = self.forecast, !forecast.isOverdue(at: now),
              let synced = self.historySyncedAt,
              (0...Self.historyRefreshInterval * 2).contains(now.timeIntervalSince(synced)) else { return nil }
        if let latest = self.status?.latestReset, latest.kind == .regular, latest.id != forecast.anchorEventID,
           latest.announcedAt > forecast.anchorDate
        {
            return nil
        }
        return Candidate(
            key: "local:\(forecast.anchorEventID)",
            title: L("cockpit_reset_forecast_notification_title"),
            body: L("cockpit_reset_forecast_notification_body", Self.dateText(forecast.estimatedAt)))
    }

    private func postForecastIfNeeded() {
        let candidate = self.candidate()
        if self.activeCandidate != candidate {
            self.cancelNotices()
            self.activeCandidate = candidate
        }
        guard self.isStarted, self.notificationsEnabled(), self.canSaveReceipts,
              let candidate, !self.deliveredAnchors.contains(candidate.key),
              self.pendingAnchor != candidate.key else { return }
        let id = UUID()
        let identifier = "\(Self.notificationIdentifier)-\(id.uuidString)"
        self.noticeID = id
        self.pendingAnchor = candidate.key
        self.activeNotificationIdentifiers.insert(identifier)
        let isCurrent: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.isStarted && self.notificationsEnabled() && self.noticeID == id
                && self.candidate() == candidate
        }
        self.post(Notice(
            identifier: identifier,
            title: candidate.title,
            body: candidate.body,
            isCurrent: isCurrent,
            completion: { [weak self] delivered in
                guard let self else { return }
                guard self.noticeID == id else {
                    self.remove(identifier)
                    self.activeNotificationIdentifiers.remove(identifier)
                    return
                }
                self.pendingAnchor = nil
                guard delivered, isCurrent() else {
                    self.remove(identifier)
                    self.activeNotificationIdentifiers.remove(identifier)
                    if self.isStarted, self.notificationsEnabled() {
                        self.notificationErrorNotice = CockpitLocalizedMessage("cockpit_reset_notice_unavailable")
                    }
                    return
                }
                self.notificationErrorNotice = nil
                self.deliveredAnchors.append(candidate.key)
                self.deliveredAnchors = Array(self.deliveredAnchors.suffix(64))
                self.saveReceipts()
            }))
    }

    private static func dateText(_ date: Date) -> String {
        CockpitLocalizedMessage.dateText(date)
    }

    private func cancelNotices() {
        self.noticeID = UUID()
        for identifier in self.activeNotificationIdentifiers {
            self.remove(identifier)
        }
        self.activeNotificationIdentifiers.removeAll()
        self.pendingAnchor = nil
    }
}

extension CockpitResetHistoryStore {
    fileprivate struct Cache: Codable {
        let history: CockpitResetHistory?
        let status: CockpitResetStatus?
        let historySyncedAt: Date?
        let statusSyncedAt: Date?
        let lastSyncedAt: Date?
    }

    private func loadCache() {
        guard FileManager.default.fileExists(atPath: self.cacheURL.path) else { return }
        do {
            let cache = try JSONDecoder().decode(Cache.self, from: Self.read(self.cacheURL))
            self.history = cache.history
            self.status = cache.status
            self.lastSyncedAt = cache.lastSyncedAt
            self.historySyncedAt = cache.historySyncedAt
            self.lastStatusSyncedAt = cache.statusSyncedAt
            self.forecast = cache.history.flatMap { CockpitResetForecast.estimate(events: $0.events, now: self.now()) }
        } catch {
            self.canSaveCache = false
            self.cacheReadError = CockpitLocalizedMessage("cockpit_reset_cache_read_failed", error.localizedDescription)
            self.errorNotice = self.cacheReadError
        }
    }

    private func loadReceipts() {
        guard FileManager.default.fileExists(atPath: self.receiptsURL.path) else { return }
        do {
            self.deliveredAnchors = try Array(JSONDecoder().decode([String].self, from: Self.read(self.receiptsURL))
                .suffix(64))
        } catch {
            self.canSaveReceipts = false
            self.receiptsReadError = CockpitLocalizedMessage(
                "cockpit_reset_receipts_read_failed",
                error.localizedDescription)
            self.notificationErrorNotice = self.receiptsReadError
        }
    }

    private func saveCache() {
        guard self.canSaveCache, self.history != nil || self.status != nil else { return }
        do {
            try Self.write(Cache(
                history: self.history,
                status: self.status,
                historySyncedAt: self.historySyncedAt,
                statusSyncedAt: self.lastStatusSyncedAt,
                lastSyncedAt: self.lastSyncedAt), to: self.cacheURL)
        } catch {
            self.errorNotice = CockpitLocalizedMessage("cockpit_reset_cache_save_failed", error.localizedDescription)
        }
    }

    private func saveReceipts() {
        guard self.canSaveReceipts else { return }
        do {
            try Self.write(self.deliveredAnchors, to: self.receiptsURL)
        } catch {
            self.notificationErrorNotice = CockpitLocalizedMessage(
                "cockpit_reset_receipts_save_failed",
                error.localizedDescription)
        }
    }

    fileprivate static func read(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard data.count <= 4 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    fileprivate static func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
