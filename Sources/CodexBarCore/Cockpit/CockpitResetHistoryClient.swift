import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches only public reset announcements. Requests never use provider credentials or browser cookies.
public struct CockpitResetHistoryClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public static let websiteURL = URL(string: "https://codex-resets.com/zh-CN")!
    public static let apiURL = URL(string: "https://codex-resets.com/api/v1/resets")!
    public static let statusURL = URL(string: "https://codex-resets.com/api/v1/status")!
    public static let maximumPageBytes = 2 * 1024 * 1024
    public static let maximumPages = 32
    private let load: Loader

    public init() {
        self.load = { request in try await Self.loadPublicPage(request) }
    }

    public init(load: @escaping Loader) {
        self.load = load
    }

    /// Returns only after every page succeeds; callers can retain a previous cache on any failure.
    public func fetchHistory() async throws -> CockpitResetHistory {
        var events: [CockpitResetEvent] = []
        var generatedAt: Date?
        var cursor: String?
        var seenCursors: Set<String> = []
        for _ in 0..<Self.maximumPages {
            try Task.checkCancellation()
            let request = try Self.request(cursor: cursor)
            let (data, response) = try await self.load(request)
            try Task.checkCancellation()
            try Self.validate(data: data, response: response)
            let page = try Self.decodePage(data)
            generatedAt = max(generatedAt ?? page.generatedAt, page.generatedAt)
            events += page.events
            guard events.count <= 10000 else { throw CockpitResetHistoryError.responseTooLarge }
            guard page.hasMore else {
                return CockpitResetHistory(events: events, generatedAt: generatedAt ?? page.generatedAt)
            }
            guard !page.events.isEmpty, let next = page.nextCursor,
                  !next.isEmpty, next.utf8.count <= 8192, seenCursors.insert(next).inserted
            else { throw CockpitResetHistoryError.invalidPagination }
            cursor = next
        }
        throw CockpitResetHistoryError.pageLimitExceeded
    }

    public func fetchStatus() async throws -> CockpitResetStatus {
        try Task.checkCancellation()
        var request = URLRequest(url: Self.statusURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await self.load(request)
        try Task.checkCancellation()
        try Self.validate(data: data, response: response)
        let page: APIStatus
        do {
            page = try JSONDecoder().decode(APIStatus.self, from: data)
        } catch {
            throw CockpitResetHistoryError.invalidResponse
        }
        guard page.meta.apiVersion == "v1" else { throw CockpitResetHistoryError.unsupportedAPIVersion }
        guard let generatedAt = Self.date(page.meta.generatedAt) else {
            throw CockpitResetHistoryError.invalidResponse
        }
        return try CockpitResetStatus(
            generatedAt: generatedAt,
            latestReset: page.data.latestReset.map { try $0.event() },
            scheduledReset: page.data.scheduledReset.map { try $0.scheduled() },
            activeWatch: page.data.activeWatch.map { try $0.watch() })
    }

    private static func validate(data: Data, response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme == "https", response.url?.host == Self.apiURL.host
        else { throw CockpitResetHistoryError.invalidResponse }
        if response.statusCode == 429 {
            throw CockpitResetHistoryError.rateLimited(retryAfter: self.retryAfter(response))
        }
        guard response.statusCode == 200 else { throw CockpitResetHistoryError.httpStatus(response.statusCode) }
        guard data.count <= Self.maximumPageBytes else { throw CockpitResetHistoryError.responseTooLarge }
    }

    private static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return 300 }
        if let seconds = TimeInterval(header), seconds.isFinite { return min(86400, max(0, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        guard let date = formatter.date(from: header) else { return 300 }
        return min(86400, max(0, date.timeIntervalSinceNow))
    }

    private static func request(cursor: String?) throws -> URLRequest {
        guard var components = URLComponents(url: self.apiURL, resolvingAgainstBaseURL: false) else {
            throw CockpitResetHistoryError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "order", value: "desc")]
        if let cursor { components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        guard let url = components.url else { throw CockpitResetHistoryError.invalidPagination }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func loadPublicPage(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        #if canImport(FoundationNetworking)
        let (data, response) = try await session.data(for: request)
        guard data.count <= self.maximumPageBytes else { throw CockpitResetHistoryError.responseTooLarge }
        return (data, response)
        #else
        let (bytes, response) = try await session.bytes(for: request)
        guard response.expectedContentLength <= self.maximumPageBytes else {
            throw CockpitResetHistoryError.responseTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < self.maximumPageBytes else { throw CockpitResetHistoryError.responseTooLarge }
            data.append(byte)
        }
        return (data, response)
        #endif
    }

    private static func decodePage(_ data: Data) throws -> DecodedPage {
        let page: APIPage
        do {
            page = try JSONDecoder().decode(APIPage.self, from: data)
        } catch {
            throw CockpitResetHistoryError.invalidResponse
        }
        guard page.meta.apiVersion == "v1" else { throw CockpitResetHistoryError.unsupportedAPIVersion }
        guard let generatedAt = Self.date(page.meta.generatedAt) else {
            throw CockpitResetHistoryError.invalidResponse
        }
        let events = try page.data.map { try $0.event() }
        return DecodedPage(
            events: events,
            generatedAt: generatedAt,
            hasMore: page.pagination.hasMore,
            nextCursor: page.pagination.nextCursor)
    }

    fileprivate static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private struct DecodedPage {
    let events: [CockpitResetEvent]
    let generatedAt: Date
    let hasMore: Bool
    let nextCursor: String?
}

private struct APIPage: Decodable {
    struct Event: Decodable {
        struct Source: Decodable {
            let type: String
            let url: String?
            let author: String?

            func sourceURL() throws -> URL {
                if let url {
                    guard let parsed = URL(string: url) else { throw CockpitResetHistoryError.invalidEvent }
                    return parsed
                }
                guard self.type == "observed" else { throw CockpitResetHistoryError.invalidEvent }
                return CockpitResetHistoryClient.websiteURL
            }
        }

        let id: String
        let resetType: String
        let announcedAt: String
        let text: String
        let source: Source

        enum CodingKeys: String, CodingKey {
            case id, text, source
            case resetType = "reset_type"
            case announcedAt = "announced_at"
        }

        func event() throws -> CockpitResetEvent {
            guard let date = CockpitResetHistoryClient.date(self.announcedAt) else {
                throw CockpitResetHistoryError.invalidEvent
            }
            return try CockpitResetEvent(
                id: self.id,
                kind: CockpitResetKind(rawValue: self.resetType),
                announcedAt: date,
                text: self.text,
                sourceType: self.source.type,
                sourceURL: self.source.sourceURL(),
                sourceAuthor: self.source.author)
        }
    }

    struct Pagination: Decodable {
        let hasMore: Bool
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case hasMore = "has_more"
            case nextCursor = "next_cursor"
        }
    }

    struct Metadata: Decodable {
        let apiVersion: String
        let generatedAt: String

        enum CodingKeys: String, CodingKey {
            case apiVersion = "api_version"
            case generatedAt = "generated_at"
        }
    }

    let data: [Event]
    let pagination: Pagination
    let meta: Metadata
}

private struct APIStatus: Decodable {
    struct Status: Decodable {
        let latestReset: APIPage.Event?
        let scheduledReset: Scheduled?
        let activeWatch: Watch?

        enum CodingKeys: String, CodingKey {
            case latestReset = "latest_reset"
            case scheduledReset = "scheduled_reset"
            case activeWatch = "active_watch"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.latestReset = try container.decode(APIPage.Event?.self, forKey: .latestReset)
            self.scheduledReset = try container.decode(Scheduled?.self, forKey: .scheduledReset)
            self.activeWatch = try container.decode(Watch?.self, forKey: .activeWatch)
        }
    }

    struct Scheduled: Decodable {
        let id: String
        let status: String
        let resetType: String
        let announcedAt: String
        let scheduledFor: String?
        let text: String
        let source: APIPage.Event.Source

        enum CodingKeys: String, CodingKey {
            case id, status, text, source
            case resetType = "reset_type"
            case announcedAt = "announced_at"
            case scheduledFor = "scheduled_for"
        }

        func scheduled() throws -> CockpitScheduledReset {
            guard let announced = CockpitResetHistoryClient.date(self.announcedAt) else {
                throw CockpitResetHistoryError.invalidEvent
            }
            let scheduledDate = self.scheduledFor.flatMap(CockpitResetHistoryClient.date)
            guard self.scheduledFor == nil || scheduledDate != nil else { throw CockpitResetHistoryError.invalidEvent }
            return try CockpitScheduledReset(
                id: self.id,
                status: self.status,
                kind: CockpitResetKind(rawValue: self.resetType),
                announcedAt: announced,
                scheduledFor: scheduledDate,
                text: self.text,
                sourceType: self.source.type,
                sourceURL: self.source.sourceURL(),
                sourceAuthor: self.source.author)
        }
    }

    struct Watch: Decodable {
        let level: String
        let resetChancePercent: Int?
        let forecastWindow: String
        let observedAt: String
        let expiresAt: String
        let text: String
        let source: APIPage.Event.Source

        enum CodingKeys: String, CodingKey {
            case level, text, source
            case resetChancePercent = "reset_chance_percent"
            case forecastWindow = "forecast_window"
            case observedAt = "observed_at"
            case expiresAt = "expires_at"
        }

        func watch() throws -> CockpitResetWatch {
            guard let observed = CockpitResetHistoryClient.date(self.observedAt),
                  let expires = CockpitResetHistoryClient.date(self.expiresAt)
            else { throw CockpitResetHistoryError.invalidEvent }
            return try CockpitResetWatch(
                id: "watch-\(observed.timeIntervalSince1970)",
                level: self.level,
                resetChancePercent: self.resetChancePercent,
                forecastWindow: self.forecastWindow,
                observedAt: observed,
                expiresAt: expires,
                text: self.text,
                sourceType: self.source.type,
                sourceURL: self.source.sourceURL())
        }
    }

    let data: Status
    let meta: APIPage.Metadata
}
