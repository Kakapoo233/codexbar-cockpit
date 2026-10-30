import Foundation
import Testing
@testable import CodexBarCore

struct CockpitResetStatusTests {
    @Test
    func `status preserves an announced reset whose execution time is unspecified`() async throws {
        var scheduled = Self.scheduled()
        scheduled["scheduled_for"] = NSNull()
        let status = try await Self.client(Self.page(scheduled: scheduled)).fetchStatus()
        let item = try #require(status.scheduledReset)
        #expect(item.id == "synthetic-scheduled")
        #expect(item.scheduledFor == nil)
        #expect(try item.isPending(at: Self.date("2026-10-30T12:00:00Z")))
        #expect(status.latestReset == nil)
    }

    @Test
    func `passing a scheduled target never changes a pending announcement into a completed reset`() async throws {
        let status = try await Self.client(Self.page(scheduled: Self.scheduled())).fetchStatus()
        let item = try #require(status.scheduledReset)
        #expect(try item.scheduledFor == (Self.date("2026-10-30T10:00:00Z")))
        #expect(try item.isPending(at: Self.date("2026-10-30T12:00:00Z")))
        #expect(try !item.isPending(at: Self.date("2026-10-29T12:00:00Z")))
    }

    @Test
    func `third party watch keeps its descriptive window and expires without inventing a target date`() async throws {
        let status = try await Self.client(Self.page(watch: Self.watch())).fetchStatus()
        let item = try #require(status.activeWatch)
        #expect(item.level == "strong")
        #expect(item.resetChancePercent == 75)
        #expect(item.forecastWindow == "within 24 hours")
        #expect(try item.isActive(at: Self.date("2026-10-30T12:00:00Z")))
        #expect(try !item.isActive(at: Self.date("2026-10-31T00:00:00Z")))
        #expect(try !item.isActive(at: Self.date("2026-10-29T12:00:00Z")))
        let repeated = try await Self.client(Self.page(watch: Self.watch())).fetchStatus()
        #expect(repeated.activeWatch?.id == item.id)
    }

    @Test
    func `unknown watch levels remain data and cannot produce an active signal`() async throws {
        var watch = Self.watch()
        watch["level"] = "future-level"
        watch["reset_chance_percent"] = NSNull()
        let status = try await Self.client(Self.page(watch: watch)).fetchStatus()
        let item = try #require(status.activeWatch)
        #expect(item.resetChancePercent == nil)
        #expect(try !item.isActive(at: Self.date("2026-10-30T12:00:00Z")))
    }

    @Test
    func `an observed reset without an original URL links to the credited tracker`() async throws {
        let latest: [String: Any] = [
            "id": "synthetic-observed", "reset_type": "regular", "announced_at": "2026-10-30T06:00:00Z",
            "text": "Synthetic observed reset", "source": ["type": "observed"],
        ]
        let status = try await Self.client(Self.page(latest: latest)).fetchStatus()
        #expect(status.latestReset?.sourceURL == CockpitResetHistoryClient.websiteURL)
        #expect(status.latestReset?.sourceType == "observed")
    }

    @Test
    func `invalid watch percentages and malformed target dates reject status atomically`() async throws {
        var watch = Self.watch()
        watch["reset_chance_percent"] = 101
        let chanceClient = try Self.client(Self.page(watch: watch))
        await #expect(throws: CockpitResetHistoryError.invalidEvent) { try await chanceClient.fetchStatus() }
        var scheduled = Self.scheduled()
        scheduled["scheduled_for"] = "not-a-date"
        let scheduledClient = try Self.client(Self.page(scheduled: scheduled))
        await #expect(throws: CockpitResetHistoryError.invalidEvent) { try await scheduledClient.fetchStatus() }
        watch = Self.watch()
        watch["expires_at"] = "2026-10-29T00:00:00Z"
        let expiryClient = try Self.client(Self.page(watch: watch))
        await #expect(throws: CockpitResetHistoryError.invalidEvent) { try await expiryClient.fetchStatus() }
    }

    @Test
    func `null status signals are valid but missing signal fields are not a successful refresh`() async throws {
        let status = try await Self.client(Self.page()).fetchStatus()
        #expect(status.latestReset == nil)
        #expect(status.scheduledReset == nil)
        #expect(status.activeWatch == nil)
        let missing = try JSONSerialization.data(withJSONObject: [
            "data": [:], "meta": ["api_version": "v1", "generated_at": "2026-10-30T12:00:00Z"],
        ])
        let client = Self.client(missing)
        await #expect(throws: CockpitResetHistoryError.invalidResponse) { try await client.fetchStatus() }
    }

    @Test
    func `status cache preserves announcement and watch semantics after a round trip`() async throws {
        let status = try await Self.client(Self.page(scheduled: Self.scheduled(), watch: Self.watch())).fetchStatus()
        let data = try JSONEncoder().encode(status)
        #expect(try JSONDecoder().decode(CockpitResetStatus.self, from: data) == status)
    }

    @Test(arguments: [("120", 120.0), ("invalid", 300.0), ("-1", 0.0), ("9999999", 86400.0)])
    func `rate limits carry bounded retry delay for both source endpoints`(_ header: String, _ expected: Double) async {
        let client = Self.client(Data(), statusCode: 429, headers: ["Retry-After": header])
        await #expect(throws: CockpitResetHistoryError.rateLimited(retryAfter: expected)) {
            try await client.fetchStatus()
        }
        await #expect(throws: CockpitResetHistoryError.rateLimited(retryAfter: expected)) {
            try await client.fetchHistory()
        }
    }

    @Test
    func `public source integration proof uses no provider credentials`() async throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_RESET_API_LIVE"] == "1" else { return }
        let client = CockpitResetHistoryClient()
        let history = try await client.fetchHistory()
        let status = try await client.fetchStatus()
        #expect(!history.events.isEmpty)
        #expect(Set(history.events.map(\.id)).count == history.events.count)
        #expect(history.events.map(\.announcedAt) == history.events.map(\.announcedAt).sorted(by: >))
        let allDatesFinite = history.events.allSatisfy(\.announcedAt.timeIntervalSince1970.isFinite)
        #expect(allDatesFinite)
        #expect(status.generatedAt.timeIntervalSince1970.isFinite)
        print("Public reset API: \(history.events.count) events; scheduled=\(status.scheduledReset != nil); " +
            "watch=\(status.activeWatch != nil)")
    }

    private static func client(
        _ data: Data,
        statusCode: Int = 200,
        headers: [String: String] = [:]) -> CockpitResetHistoryClient
    {
        CockpitResetHistoryClient(load: { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers))
            return (data, response)
        })
    }

    private static func page(
        latest: [String: Any]? = nil,
        scheduled: [String: Any]? = nil,
        watch: [String: Any]? = nil) throws -> Data
    {
        try JSONSerialization.data(withJSONObject: [
            "data": [
                "latest_reset": latest as Any? ?? NSNull(),
                "scheduled_reset": scheduled as Any? ?? NSNull(),
                "active_watch": watch as Any? ?? NSNull(),
                "stats": ["total": 1],
            ],
            "meta": ["api_version": "v1", "generated_at": "2026-10-30T12:00:00.000Z"],
        ])
    }

    private static func scheduled() -> [String: Any] {
        [
            "id": "synthetic-scheduled", "status": "scheduled", "reset_type": "regular",
            "announced_at": "2026-10-30T06:00:00Z", "scheduled_for": "2026-10-30T10:00:00Z",
            "text": "Synthetic future announcement",
            "source": ["type": "x_post", "author": "thsottiaux", "url": "https://example.invalid/reset"],
        ]
    }

    private static func watch() -> [String: Any] {
        [
            "level": "strong", "reset_chance_percent": 75, "forecast_window": "within 24 hours",
            "observed_at": "2026-10-30T06:00:00Z", "expires_at": "2026-10-31T00:00:00Z",
            "text": "Synthetic third-party forecast", "source": ["type": "observed"],
        ]
    }

    private static func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }
}
