import Foundation
import Testing
@testable import CodexBarCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CockpitTeamClientTests {
    private static let token = "ccs_" + String(repeating: "a", count: 43)

    @Test
    func `service checks are read only and carry no device or bootstrap credential`() async throws {
        let fixture = TeamClientFixture(pages: [
            "{\"ok\":true,\"service\":\"codex-cockpit-sync\",\"version\":1}",
        ])
        let client = try CockpitTeamClient(endpoint: "https://example.invalid", load: { try await fixture.load($0) })
        try await client.checkService()
        let requests = await fixture.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://example.invalid/health")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "x-bootstrap-secret") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(!request.httpShouldHandleCookies)
    }

    @Test
    func `service checks reject a different service or unsupported protocol version`() async throws {
        for page in [
            "{\"ok\":true,\"service\":\"another-service\",\"version\":1}",
            "{\"ok\":true,\"service\":\"codex-cockpit-sync\",\"version\":2}",
        ] {
            let fixture = TeamClientFixture(pages: [page])
            let client = try CockpitTeamClient(
                endpoint: "https://example.invalid",
                load: { try await fixture.load($0) })
            await #expect(throws: CockpitTeamError.unsupportedProtocol) { try await client.checkService() }
        }
    }

    @Test
    func `service checks reject incomplete malformed and unsuccessful health responses`() async throws {
        for page in [
            "<html>not a sync service</html>",
            "{\"ok\":true}",
            "{\"ok\":true,\"service\":\"codex-cockpit-sync\",\"version\":\"1\"}",
            "{\"ok\":true,\"service\":null,\"version\":1}",
            "{\"ok\":false,\"service\":\"codex-cockpit-sync\",\"version\":1}",
        ] {
            let fixture = TeamClientFixture(pages: [page])
            let client = try CockpitTeamClient(
                endpoint: "https://example.invalid",
                load: { try await fixture.load($0) })
            await #expect(throws: CockpitTeamError.invalidResponse) { try await client.checkService() }
        }
    }

    @Test
    func `endpoints require an HTTPS origin and normalize only harmless spelling`() throws {
        #expect(try CockpitTeamClient.normalizeEndpoint(" HTTPS://EXAMPLE.INVALID/ ") == "https://example.invalid")
        #expect(try CockpitTeamClient.normalizeEndpoint("https://example.invalid:8443")
            == "https://example.invalid:8443")
        for value in [
            "http://example.invalid",
            "https://user@example.invalid",
            "https://example.invalid/api",
            "https://example.invalid?token=secret",
            "https://example.invalid#fragment",
            "https://example.invalid:0",
            "file:///private/tmp/example",
            "https://example.invalid//",
        ] {
            #expect(throws: CockpitTeamError.invalidEndpoint) { try CockpitTeamClient(endpoint: value) }
        }
    }

    @Test
    func `groups preserve explicit unassigned null and reject ambiguous ownership`() throws {
        let groups = CockpitTeamGroups(groups: [CockpitTeamPerson(id: "person", name: "Example", deviceIDs: ["mac"])])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(groups)) as? [String: Any]
        #expect(encoded?["defaultGroupId"] is NSNull)
        let duplicateDevice = CockpitTeamGroups(groups: [
            CockpitTeamPerson(id: "one", name: "One", deviceIDs: ["mac"]),
            CockpitTeamPerson(id: "two", name: "Two", deviceIDs: ["mac"]),
        ])
        #expect(throws: CockpitTeamError.invalidRequest) { try duplicateDevice.validate() }
        let duplicateName = CockpitTeamGroups(groups: [
            CockpitTeamPerson(id: "one", name: "Same"),
            CockpitTeamPerson(id: "two", name: "Same"),
        ])
        #expect(throws: CockpitTeamError.invalidRequest) { try duplicateName.validate() }
        #expect(throws: CockpitTeamError.invalidRequest) {
            try CockpitTeamGroups(defaultGroupID: "absent").validate()
        }
    }

    @Test
    func `bundled initialization exports real nonzero base rates without accessing local state`() throws {
        let pricing = CockpitTeamPricing.bundled
        try pricing.validate()
        let rate = try #require(pricing.models["gpt-5-codex"])
        #expect(rate.input == 1.25)
        #expect(rate.output == 10)
        #expect(rate.cacheRead == 0.125)
        #expect(throws: CockpitTeamError.invalidRequest) { try CockpitTeamPricing(models: [:]).validate() }
    }

    @Test
    func `enrollment sends one time credentials only in the intended places`() async throws {
        let fixture = TeamClientFixture(pages: [
            """
            {"ok":true,"spaceId":"space","token":"\(Self.token)",
            "inviteCode":"CCI-example","inviteExpiresAt":1800000000}
            """,
        ], statuses: [201])
        let client = try CockpitTeamClient(endpoint: "https://example.invalid", load: { try await fixture.load($0) })
        let result = try await client.createSpace(
            name: "Example team",
            displayName: "Example Mac",
            deviceID: "device",
            bootstrapSecret: "example-bootstrap")
        #expect(result.spaceID == "space")
        #expect(result.inviteCode == "CCI-example")
        let requests = await fixture.requests
        let request = try #require(requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/spaces")
        #expect(request.value(forHTTPHeaderField: "x-bootstrap-secret") == "example-bootstrap")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(!request.httpShouldHandleCookies)
        let body = try #require(request.httpBody)
        #expect(try #require(String(bytes: body, encoding: .utf8)).contains("example-bootstrap") == false)
    }

    @Test
    func `minimal upload contains aggregate fields and protocol revision only`() async throws {
        let fixture = TeamClientFixture(pages: ["{\"ok\":true,\"snapshots\":[]}"])
        let client = try CockpitTeamClient(endpoint: "https://example.invalid", load: { try await fixture.load($0) })
        let payload = CockpitTeamUsageSnapshot(
            deviceID: "device",
            timestamp: 1_790_000_000,
            metadata: CockpitTeamSnapshotMetadata(status: .unavailable))
        let result = try await client.sync(payload, settingsRevision: 7, appVersion: "0.6.0", token: Self.token)
        #expect(result.isEmpty)
        let requests = await fixture.requests
        let request = try #require(requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token)")
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let snapshot = try #require(object["payload"] as? [String: Any])
        #expect(Set(snapshot.keys) == ["_device", "_ts", "_ledger", "codex", "_cockpit"])
        #expect(snapshot["taskUsage"] == nil)
        #expect(snapshot["comfortFeedback"] == nil)
        #expect((object["clientInfo"] as? [String: Any])?["settingsRevision"] as? Int == 7)
        #expect(try JSONDecoder().decode(CockpitTeamUsageSnapshot.self, from: JSONEncoder().encode(payload)) == payload)
    }

    @Test
    func `foreign optional task detail is ignored and cannot be re exported`() async throws {
        let fixture = TeamClientFixture(pages: [Self.snapshots(extra: ",\"taskUsage\":{\"privateTitle\":\"example\"}")])
        let client = try CockpitTeamClient(endpoint: "https://example.invalid", load: { try await fixture.load($0) })
        let snapshots = try await client.snapshots(token: Self.token)
        #expect(snapshots.count == 1)
        let encoded = try JSONEncoder().encode(snapshots[0].payload)
        #expect(try #require(String(bytes: encoded, encoding: .utf8)).contains("privateTitle") == false)
    }

    @Test
    func `plan clears encode null and use person revision without overwriting peers`() async throws {
        let response = """
        {"ok":true,"plan":{"basis":{"localDate":"2026-10-30","anchorAt":"2026-10-30T00:00:00Z",
        "remainingPercent":40,"resetsAt":"2026-11-01T00:00:00Z"},"people":{"person":{"value":null,"revision":3}},
        "risk":{"value":null,"revision":0}}}
        """
        let fixture = TeamClientFixture(pages: [response])
        let client = try CockpitTeamClient(endpoint: "https://example.invalid", load: { try await fixture.load($0) })
        let basis = CockpitTeamPlanBasis(
            localDate: "2026-10-30",
            anchorAt: "2026-10-30T00:00:00Z",
            remainingPercent: 40,
            resetsAt: "2026-11-01T00:00:00Z")
        let plan = try await client.dailyPlan(
            basis: basis,
            change: CockpitTeamPlanChange(
                kind: .person,
                personID: "person",
                value: nil,
                expectedRevision: 2),
            token: Self.token)
        #expect(plan.people["person"]?.revision == 3)
        let requests = await fixture.requests
        let body = try #require(requests.first?.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let change = try #require(object["change"] as? [String: Any])
        #expect(change["value"] is NSNull)
        #expect(change["expectedRevision"] as? Int == 2)
        #expect(change["personId"] as? String == "person")
        #expect(object["people"] == nil)
    }

    @Test
    func `CAS auth rate limit and server failures expose typed errors without server text`() async throws {
        for (status, expected) in [
            (409, CockpitTeamError.conflict),
            (401, .accessDenied),
            (403, .accessDenied),
            (429, .rateLimited),
            (503, .serviceUnavailable),
            (413, .requestTooLarge),
            (500, .httpStatus(500)),
        ] {
            let fixture = TeamClientFixture(
                pages: ["{\"ok\":false,\"error\":\"private-response\"}"],
                statuses: [status])
            let client = try CockpitTeamClient(
                endpoint: "https://example.invalid",
                load: { try await fixture.load($0) })
            await #expect(throws: expected) { try await client.settings(token: Self.token) }
            let requests = await fixture.requests
            #expect(requests.count == 1)
        }
    }

    @Test
    func `redirected or malformed success responses are rejected`() async throws {
        let redirected = TeamClientFixture(
            pages: ["{\"ok\":true,\"snapshots\":[]}"],
            responseURL: "https://other.invalid")
        let redirectClient = try CockpitTeamClient(endpoint: "https://example.invalid", load: {
            try await redirected.load($0)
        })
        await #expect(throws: CockpitTeamError.invalidResponse) { try await redirectClient.snapshots(token: Self.token)
        }
        for value in ["<html>not JSON</html>", "{\"ok\":false}", "{\"ok\":true,\"snapshots\":null}"] {
            let fixture = TeamClientFixture(pages: [value])
            let client = try CockpitTeamClient(
                endpoint: "https://example.invalid",
                load: { try await fixture.load($0) })
            await #expect(throws: CockpitTeamError.invalidResponse) { try await client.snapshots(token: Self.token) }
        }
    }

    @Test
    func `invalid local data and credentials are rejected before any network request`() async throws {
        let fixture = TeamClientFixture(pages: [])
        let client = try CockpitTeamClient(endpoint: "https://example.invalid", load: { try await fixture.load($0) })
        await #expect(throws: CockpitTeamError.invalidCredential) { try await client.settings(token: "unsafe\nheader") }
        let bad = CockpitTeamUsageSnapshot(
            deviceID: "device",
            timestamp: 1_790_000_000,
            days: ["2026-02-30": CockpitTeamLedgerDay(inputTokens: 1, outputTokens: 1)])
        await #expect(throws: CockpitTeamError.invalidRequest) {
            try await client.sync(bad, settingsRevision: 0, appVersion: "0.6.0", token: Self.token)
        }
        let requests = await fixture.requests
        #expect(requests.isEmpty)
    }

    @Test
    func `oversized responses cannot be decoded or published`() async throws {
        let client = try CockpitTeamClient(endpoint: "https://example.invalid", load: { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(repeating: 32, count: CockpitTeamClient.maximumResponseBytes + 1), response)
        })
        await #expect(throws: CockpitTeamError.responseTooLarge) { try await client.snapshots(token: Self.token) }
    }

    @Test
    func `device identity mismatch and duplicate snapshots cannot be double counted`() async throws {
        for page in [
            Self.snapshots().replacingOccurrences(of: "\"_device\":\"device\"", with: "\"_device\":\"different\""),
            Self.snapshots().replacingOccurrences(of: "}]}", with: "},\(Self.snapshotRow())]}"),
        ] {
            let fixture = TeamClientFixture(pages: [page])
            let client = try CockpitTeamClient(
                endpoint: "https://example.invalid",
                load: { try await fixture.load($0) })
            await #expect(throws: CockpitTeamError.invalidResponse) { try await client.snapshots(token: Self.token) }
        }
    }

    private static func snapshots(extra: String = "") -> String {
        "{\"ok\":true,\"snapshots\":[\(self.snapshotRow(extra: extra))]}"
    }

    private static func snapshotRow(extra: String = "") -> String {
        """
        {"deviceId":"device","displayName":"Example Mac","updatedAt":1790000000,
        "payload":{"_device":"device","_ts":1790000000,"codex":{"ranges":{}},"_ledger":{"tools":{"codex":{}}}\(extra)}}
        """
    }
}

private actor TeamClientFixture {
    private let pages: [Data]
    private let statuses: [Int]
    private let responseURL: String?
    private(set) var requests: [URLRequest] = []

    init(pages: [String], statuses: [Int] = [], responseURL: String? = nil) {
        self.pages = pages.map { Data($0.utf8) }
        self.statuses = statuses
        self.responseURL = responseURL
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        let index = self.requests.count
        self.requests.append(request)
        guard self.pages.indices.contains(index), let url = self.responseURL.flatMap(URL.init(string:)) ?? request.url
        else { throw CockpitTeamError.network }
        let response = HTTPURLResponse(
            url: url,
            statusCode: self.statuses.indices.contains(index) ? self.statuses[index] : 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        return (self.pages[index], response)
    }
}
