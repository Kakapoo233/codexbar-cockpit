import Foundation
import Testing
@testable import CodexBarCore

struct CockpitResetHistoryTests {
    @Test
    func `history fetches all pages sorts deduplicates and safely encodes cursors`() async throws {
        let cursor = "opaque/+?cursor=https://example.invalid"
        let fixture = try ResetHistoryPages(pages: [
            Self.page(
                [
                    Self.item(id: "new", date: "2026-10-28T06:29:38.000Z"),
                    Self.item(id: "same", date: "2026-10-26T07:00:00Z"),
                ],
                hasMore: true,
                cursor: cursor),
            Self.page([
                Self.item(id: "same", date: "2026-10-26T07:00:00.000Z"),
                Self.item(id: "old", date: "2026-10-01T00:00:00Z", kind: "future-kind"),
            ]),
        ])
        let client = CockpitResetHistoryClient(load: { try await fixture.load($0) })
        let result = try await client.fetchHistory()
        #expect(result.events.map(\.id) == ["new", "same", "old"])
        #expect(result.events.last?.kind == .unknown("future-kind"))
        #expect(result.events.first?.sourceType == "observed")
        let requests = await fixture.requests
        #expect(requests.count == 2)
        let secondURL = try #require(requests.last?.url)
        #expect(secondURL.host == "codex-resets.com")
        let query = try #require(URLComponents(url: secondURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "cursor" }?.value == cursor)
        #expect(query.first { $0.name == "limit" }?.value == "100")
        #expect(query.first { $0.name == "order" }?.value == "desc")
        #expect(requests
            .allSatisfy { !$0.httpShouldHandleCookies && $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    @Test
    func `invalid timestamp or unsafe source fails the entire response`() async throws {
        for item in [
            Self.item(id: "bad-date", date: "not-a-date"),
            Self.item(id: "bad-url", url: "javascript:alert(1)"),
            Self.item(id: "bad-url", url: "https://user:password@example.invalid"),
            Self.item(id: " "),
        ] {
            let fixture = try ResetHistoryPages(pages: [Self.page([item])])
            let client = CockpitResetHistoryClient(load: { try await fixture.load($0) })
            await #expect(throws: CockpitResetHistoryError.invalidEvent) { try await client.fetchHistory() }
        }
    }

    @Test
    func `unexpected API or non JSON response cannot erase a valid cache`() async throws {
        let malformed = ResetHistoryPages(pages: [Data("<html>unavailable</html>".utf8)])
        let malformedClient = CockpitResetHistoryClient(load: { try await malformed.load($0) })
        await #expect(throws: CockpitResetHistoryError.invalidResponse) { try await malformedClient.fetchHistory() }
        let version = try ResetHistoryPages(pages: [Self.page([Self.item(id: "one")], version: "v2")])
        let versionClient = CockpitResetHistoryClient(load: { try await version.load($0) })
        await #expect(throws: CockpitResetHistoryError.unsupportedAPIVersion) { try await versionClient.fetchHistory() }
    }

    @Test
    func `HTTP failure on a later page does not return a partial history`() async throws {
        let fixture = try ResetHistoryPages(pages: [
            Self.page([Self.item(id: "one")], hasMore: true, cursor: "older"),
            Data(),
        ], statuses: [200, 503])
        let client = CockpitResetHistoryClient(load: { try await fixture.load($0) })
        await #expect(throws: CockpitResetHistoryError.httpStatus(503)) { try await client.fetchHistory() }
    }

    @Test
    func `missing or repeating next cursor stops pagination`() async throws {
        for pages in try [
            [Self.page([Self.item(id: "one")], hasMore: true)],
            [
                Self.page([Self.item(id: "one")], hasMore: true, cursor: "same"),
                Self.page([Self.item(id: "two")], hasMore: true, cursor: "same"),
            ],
        ] {
            let fixture = ResetHistoryPages(pages: pages)
            let client = CockpitResetHistoryClient(load: { try await fixture.load($0) })
            await #expect(throws: CockpitResetHistoryError.invalidPagination) { try await client.fetchHistory() }
        }
    }

    @Test
    func `unbounded pagination and oversized responses are rejected`() async throws {
        let pages = try (0..<CockpitResetHistoryClient.maximumPages).map {
            try Self.page([Self.item(id: "event-\($0)")], hasMore: true, cursor: "cursor-\($0)")
        }
        let fixture = ResetHistoryPages(pages: pages)
        let client = CockpitResetHistoryClient(load: { try await fixture.load($0) })
        await #expect(throws: CockpitResetHistoryError.pageLimitExceeded) { try await client.fetchHistory() }
        let large = ResetHistoryPages(pages: [Data(
            repeating: 32,
            count: CockpitResetHistoryClient.maximumPageBytes + 1)])
        let largeClient = CockpitResetHistoryClient(load: { try await large.load($0) })
        await #expect(throws: CockpitResetHistoryError.responseTooLarge) { try await largeClient.fetchHistory() }
    }

    @Test
    func `cancelled fetch never publishes downloaded pages`() async throws {
        let fixture = try ResetHistoryPages(pages: [Self.page([Self.item(id: "one")])])
        let client = CockpitResetHistoryClient(load: { request in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.load(request)
        })
        let task = Task { try await client.fetchHistory() }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func `domain cache round trip preserves unknown kinds and rejects unsafe cached links`() throws {
        let event = try Self.event(id: "one", kind: .unknown("future-kind"), date: "2026-10-28T06:29:38Z")
        let history = CockpitResetHistory(events: [event], generatedAt: event.announcedAt)
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(CockpitResetHistory.self, from: data) == history)
        let poisoned = try #require(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "https:", with: "http:")
        #expect(throws: CockpitResetHistoryError.invalidEvent) {
            try JSONDecoder().decode(CockpitResetHistory.self, from: Data(poisoned.utf8))
        }
    }

    @Test
    func `day grouping uses reporting zone through midnight and daylight saving changes`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let events = try [
            Self.event(id: "yesterday", date: "2026-11-01T03:59:59Z"),
            Self.event(id: "today", date: "2026-11-01T04:00:00Z"),
            Self.event(id: "first-one-thirty", date: "2026-11-01T05:30:00Z"),
            Self.event(id: "second-one-thirty", date: "2026-11-01T06:30:00Z"),
            Self.event(id: "late-today", date: "2026-11-02T04:59:59Z"),
            Self.event(id: "tomorrow", date: "2026-11-02T05:00:00Z"),
        ]
        let groups = CockpitResetCalendar.eventsByDay(events, calendar: calendar)
        #expect(groups.count == 3)
        let day = try calendar.startOfDay(for: Self.date("2026-11-01T12:00:00Z"))
        #expect(groups[day]?.count == 4)
        #expect(groups[day]?.map(\.id) == ["late-today", "second-one-thirty", "first-one-thirty", "today"])
    }

    @Test
    func `historical estimate uses recent regular intervals and excludes banked and future announcements`() throws {
        let now = try Self.date("2026-10-30T00:00:00Z")
        let events = try [
            Self.event(id: "anchor", date: "2026-10-28T00:00:00Z"),
            Self.event(id: "previous", date: "2026-10-26T00:00:00Z"),
            Self.event(id: "third", date: "2026-10-23T00:00:00Z"),
            Self.event(id: "fourth", date: "2026-10-19T00:00:00Z"),
            Self.event(id: "banked", kind: .banked, date: "2026-10-29T00:00:00Z"),
            Self.event(id: "future", date: "2026-10-31T00:00:00Z"),
            Self.event(id: "too-old", date: "2025-10-01T00:00:00Z"),
        ]
        let forecast = try #require(CockpitResetForecast.estimate(events: events, now: now))
        #expect(forecast.anchorEventID == "anchor")
        #expect(forecast.sampleCount == 3)
        #expect(forecast.medianInterval == 3 * 86400)
        #expect(forecast.minimumInterval == 2 * 86400)
        #expect(forecast.maximumInterval == 4 * 86400)
        #expect(try forecast.estimatedAt == (Self.date("2026-10-31T00:00:00Z")))
        #expect(!forecast.isOverdue(at: now))
    }

    @Test
    func `estimate requires at least three positive intervals and at most the latest ten`() throws {
        let now = try Self.date("2026-10-30T00:00:00Z")
        let few = try (0..<3).map {
            try Self.event(id: "few-\($0)", at: now.addingTimeInterval(Double(-$0) * 86400))
        }
        #expect(CockpitResetForecast.estimate(events: few, now: now) == nil)
        let sameTime = try (0..<4).map { try Self.event(id: "same-\($0)", at: now) }
        #expect(CockpitResetForecast.estimate(events: sameTime, now: now) == nil)
        let many = try (0..<20).map {
            try Self.event(id: "many-\($0)", at: now.addingTimeInterval(Double(-$0) * 86400))
        }
        #expect(CockpitResetForecast.estimate(events: many, now: now)?.sampleCount == 10)
    }

    @Test
    func `overdue estimate stays anchored and never invents a new reset`() throws {
        let events = try [
            Self.event(id: "anchor", date: "2026-10-20T00:00:00Z"),
            Self.event(id: "two", date: "2026-10-18T00:00:00Z"),
            Self.event(id: "three", date: "2026-10-16T00:00:00Z"),
            Self.event(id: "four", date: "2026-10-14T00:00:00Z"),
        ]
        let firstNow = try Self.date("2026-10-23T00:00:00Z")
        let laterNow = try Self.date("2026-10-30T00:00:00Z")
        let first = try #require(CockpitResetForecast.estimate(events: events, now: firstNow))
        let later = try #require(CockpitResetForecast.estimate(events: events, now: laterNow))
        #expect(first == later)
        #expect(first.isOverdue(at: firstNow))
        #expect(later.isOverdue(at: laterNow))
        #expect(try first.estimatedAt == (Self.date("2026-10-22T00:00:00Z")))
    }

    private static func event(
        id: String,
        kind: CockpitResetKind = .regular,
        date: String) throws -> CockpitResetEvent
    {
        try self.event(id: id, kind: kind, at: self.date(date))
    }

    private static func event(
        id: String,
        kind: CockpitResetKind = .regular,
        at date: Date) throws -> CockpitResetEvent
    {
        try CockpitResetEvent(
            id: id,
            kind: kind,
            announcedAt: date,
            text: "Synthetic announcement",
            sourceType: "observed",
            sourceURL: URL(string: "https://example.invalid/reset/\(id)")!)
    }

    private static func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }

    private static func item(
        id: String,
        date: String = "2026-10-28T06:29:38.000Z",
        kind: String = "regular",
        url: String = "https://example.invalid/reset") -> [String: Any]
    {
        [
            "id": id,
            "reset_type": kind,
            "announced_at": date,
            "text": "Synthetic announcement",
            "source": ["type": "observed", "url": url],
        ]
    }

    private static func page(
        _ items: [[String: Any]],
        hasMore: Bool = false,
        cursor: String? = nil,
        version: String = "v1") throws -> Data
    {
        try JSONSerialization.data(withJSONObject: [
            "data": items,
            "pagination": ["has_more": hasMore, "next_cursor": cursor as Any? ?? NSNull()],
            "meta": ["api_version": version, "generated_at": "2026-10-30T00:00:00.000Z"],
        ])
    }
}

private actor ResetHistoryPages {
    let pages: [Data]
    let statuses: [Int]
    private(set) var requests: [URLRequest] = []

    init(pages: [Data], statuses: [Int] = []) {
        self.pages = pages
        self.statuses = statuses
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        let index = self.requests.count
        self.requests.append(request)
        let data = try #require(self.pages.indices.contains(index) ? self.pages[index] : nil)
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: self.statuses.indices.contains(index) ? self.statuses[index] : 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]))
        return (data, response)
    }
}
