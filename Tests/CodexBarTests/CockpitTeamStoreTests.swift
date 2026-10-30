import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitTeamStoreTests {
    @Test
    func `account changes permanently withdraw usage sharing until the user binds again`() async throws {
        try await self.withStore { store, fixture, state, _ in
            #expect(store.accountMatches)
            await store.refresh()
            state.accountID = "account-b"
            await store.refresh()
            #expect(store.connection?.shareUsage == false)
            #expect(store.connection?.boundAccountID == nil)
            state.accountID = "account-a"
            await store.refresh()
            #expect(!store.accountMatches)
            store.setUsageSharing(true)
            #expect(store.connection?.shareUsage == false)
            store.bindCurrentAccount()
            #expect(store.accountMatches)
            #expect(store.connection?.shareUsage == false)
            store.setUsageSharing(true)
            #expect(store.connection?.shareUsage == true)
            let uploads = try await fixture.uploads()
            #expect(uploads.first?.days.isEmpty == false)
            let laterUploadsAreEmpty = uploads.dropFirst().allSatisfy(\.days.isEmpty)
            #expect(laterUploadsAreEmpty)
        }
    }

    @Test
    func `withdrawing sharing replaces cloud usage even within the same clock second`() async throws {
        try await self.withStore { store, fixture, _, _ in
            await store.refresh()
            store.setUsageSharing(false)
            await store.refresh()
            let uploads = try await fixture.uploads()
            #expect(uploads.count == 2)
            #expect(uploads[0].days.isEmpty == false)
            #expect(uploads[1].days.isEmpty)
            #expect(uploads[1].timestamp > uploads[0].timestamp)
            #expect(uploads[1].metadata?.status == .unavailable)
        }
    }

    @Test
    func `group conflicts reload the winning version and never retry a stale write`() async throws {
        try await self.withStore { store, fixture, _, file in
            let remote = CockpitTeamSharedSettings(
                revision: 9,
                value: CockpitTeamSettingsValue(
                    groups: CockpitTeamGroups(groups: [
                        CockpitTeamPerson(id: "remote", name: "Remote edit", deviceIDs: ["device"]),
                    ]),
                    pricing: .bundled))
            await fixture.conflictGroups(with: remote)
            let draft = CockpitTeamGroups(groups: [CockpitTeamPerson(id: "draft", name: "Draft")])
            await store.saveGroups(draft, expectedRevision: 1)
            #expect(store.sharedSettings == remote)
            #expect(store.errorMessage != nil)
            let requests = await fixture.requests
            #expect(requests.map { $0.url?.path } == ["/v2/groups", "/v2/settings"])
            let cached = try JSONDecoder().decode(CockpitTeamStore.Cache.self, from: Data(contentsOf: file))
            #expect(cached.identity?.sharedSettings == remote)
        }
    }

    @Test
    func `paused connections make no requests and preserve their previous data`() async throws {
        try await self.withStore { store, fixture, _, _ in
            store.snapshots = [Self.snapshot()]
            store.setEnabled(false)
            await store.refresh()
            let requests = await fixture.requests
            #expect(requests.isEmpty)
            #expect(store.snapshots.count == 1)
        }
    }

    @Test
    func `disconnect discards an inflight response instead of reviving the previous space`() async throws {
        try await self.withStore { store, fixture, state, file in
            await fixture.blockNextIdentity()
            let refresh = Task { await store.refresh() }
            await fixture.waitUntilBlocked()
            store.disconnect()
            await fixture.releaseIdentity()
            await refresh.value
            #expect(store.connection == nil)
            #expect(store.identity == nil)
            #expect(store.snapshots.isEmpty)
            #expect(store.plan == nil)
            #expect(state.tokens.isEmpty)
            #expect(!store.isBusy)
            let cached = try JSONDecoder().decode(CockpitTeamStore.Cache.self, from: Data(contentsOf: file))
            #expect(cached.connection == nil)
        }
    }

    @Test
    func `credentials never enter the JSON cache and connection state reloads independently`() async throws {
        try await self.withStore { store, _, state, file in
            await store.refresh()
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains(state.token))
            #expect(!text.contains("Bearer"))
            let cached = try JSONDecoder().decode(CockpitTeamStore.Cache.self, from: Data(contentsOf: file))
            #expect(cached.connection?.spaceID == "space")
            #expect(cached.lastSyncedAt != nil)
            #expect(cached.snapshots.count == 1)
        }
    }

    @Test
    func `an offline refresh retains the last successful snapshots and sync time`() async throws {
        try await self.withStore { store, fixture, _, _ in
            await store.refresh()
            let previous = store.snapshots
            let syncedAt = store.lastSyncedAt
            await fixture.goOffline()
            await store.refresh()
            #expect(store.snapshots == previous)
            #expect(store.lastSyncedAt == syncedAt)
            #expect(store.errorMessage != nil)
        }
    }

    @Test
    func `two devices share one person budget and edits preserve the peer budget`() async throws {
        try await self.withStore { store, _, _, _ in
            await store.refresh()
            let total = try #require(store.recommendedTotal)
            #expect(store.allocations.count == 2)
            #expect(store.allocations["first"] == total / 2)
            #expect(store.allocations["second"] == total / 2)
            let peerBudget = store.allocations["second"]
            let expectedPlan = try #require(store.currentPlan)
            await store.setPersonalBudget(12, expectedPlan: expectedPlan)
            #expect(store.allocations["first"] == 12)
            #expect(store.allocations["second"] == peerBudget)
        }
    }

    @Test
    func `known account changes withdraw consent even when weekly quota is unavailable`() async throws {
        try await self.withStore { store, fixture, state, _ in
            state.accountID = "account-b"
            state.quotaAvailable = false
            await store.refresh()
            #expect(store.connection?.boundAccountID == nil)
            #expect(store.connection?.boundAt == nil)
            #expect(store.connection?.shareUsage == false)
            state.accountID = "account-a"
            state.quotaAvailable = true
            await store.refresh()
            #expect(!store.accountMatches)
            #expect(store.connection?.shareUsage == false)
            let uploads = try await fixture.uploads()
            let allUploadsAreEmpty = uploads.allSatisfy(\.days.isEmpty)
            #expect(allUploadsAreEmpty)
        }
    }

    @Test
    func `early quota reset rejects an old budget draft without writing into the new cycle`() async throws {
        try await self.withStore { store, fixture, state, _ in
            await store.refresh()
            let draft = try #require(store.currentPlan)
            let countBefore = await fixture.requests.count
            state.resetInterval = 2 * 86400
            await store.setPersonalBudget(12, expectedPlan: draft)
            #expect(store.errorMessage != nil)
            await store.setRisk(30, expectedPlan: draft)
            let countAfter = await fixture.requests.count
            #expect(countAfter == countBefore)
            #expect(store.plan == draft)
        }
    }

    @Test
    func `enrollment retries a failed credential write without consuming another invitation`() async throws {
        try await self.withStore { store, fixture, state, file in
            store.disconnect()
            state.failNextRealTokenWrite = true
            await store.join(endpoint: "https://example.invalid", inviteCode: "CCI-synthetic", deviceName: "New Mac")
            #expect(store.hasPendingEnrollment)
            #expect(store.connection == nil)
            #expect(store.errorMessage != nil)
            let pendingCache = try String(contentsOf: file, encoding: .utf8)
            #expect(!pendingCache.contains(state.token))
            await store.retryEnrollment()
            #expect(!store.hasPendingEnrollment)
            #expect(store.connection?.spaceID == "space")
            #expect(store.identity?.deviceID == store.connection?.deviceID)
            #expect(state.realTokenWrites == 2)
            let requests = await fixture.requests
            #expect(requests.filter { $0.url?.path == "/v1/join" }.count == 1)
            #expect(requests.filter { $0.url?.path == "/v1/me" }.count == 1)
            let finalCache = try String(contentsOf: file, encoding: .utf8)
            #expect(!finalCache.contains(state.token))
        }
    }

    private func withStore(
        _ body: (CockpitTeamStore, TeamStoreFixture, TeamStoreState, URL) async throws -> Void) async throws
    {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("team.json")
        let state = TeamStoreState()
        let groups = CockpitTeamGroups(groups: [
            CockpitTeamPerson(id: "first", name: "First", deviceIDs: ["device", "device-two"]),
            CockpitTeamPerson(id: "second", name: "Second", deviceIDs: ["device-three"]),
        ])
        let shared = CockpitTeamSharedSettings(
            revision: 1,
            value: CockpitTeamSettingsValue(groups: groups, pricing: .bundled))
        let identity = CockpitTeamIdentity(
            space: CockpitTeamSpace(id: "space", name: "Synthetic space"),
            deviceID: "device",
            role: .member,
            members: [CockpitTeamDevice(deviceID: "device", displayName: "Synthetic Mac")],
            sharedSettings: shared)
        let basis = CockpitTeamPlanBasis(
            localDate: CockpitTeamStore.day(state.now),
            anchorAt: CockpitTeamStore.timestamp(state.now),
            remainingPercent: 60,
            resetsAt: CockpitTeamStore.timestamp(state.now.addingTimeInterval(3 * 86400)))
        let fixture = TeamStoreFixture(identity: identity, plan: CockpitTeamDailyPlan(basis: basis), token: state.token)
        let store = CockpitTeamStore(
            fileURL: file,
            clientFactory: { try CockpitTeamClient(endpoint: $0, load: { try await fixture.load($0) }) },
            loadToken: { endpoint, deviceID in state.tokens[endpoint + "|" + deviceID] },
            saveToken: { token, endpoint, deviceID in
                if token?.hasPrefix("ccs_") == true {
                    state.realTokenWrites += 1
                    if state.failNextRealTokenWrite {
                        state.failNextRealTokenWrite = false
                        throw CockpitTeamCredentialError.unavailable
                    }
                }
                state.tokens[endpoint + "|" + deviceID] = token
            },
            quotaInput: {
                guard state.quotaAvailable else { return nil }
                return CockpitTeamStore.QuotaInput(
                    accountID: state.accountID,
                    observedAt: state.now,
                    remainingPercent: 60,
                    resetsAt: state.now.addingTimeInterval(state.resetInterval))
            },
            accountIdentity: { state.accountID },
            usageSnapshot: { connection, date in
                let days = connection.shareUsage
                    ? [CockpitTeamStore.day(date): CockpitTeamLedgerDay(inputTokens: 200, outputTokens: 10, cost: 1)]
                    : [:]
                return (
                    CockpitTeamUsageSnapshot(
                        deviceID: connection.deviceID,
                        timestamp: Int64(date.timeIntervalSince1970),
                        days: days,
                        metadata: CockpitTeamSnapshotMetadata(status: connection.shareUsage ? .partial : .unavailable)),
                    "Synthetic fixture")
            },
            now: { state.now })
        store.connection = CockpitTeamStore.Connection(
            endpoint: "https://example.invalid",
            spaceID: "space",
            spaceName: "Synthetic space",
            deviceID: "device",
            deviceName: "Synthetic Mac",
            role: .member,
            shareUsage: true,
            boundAccountID: "account-a",
            boundAt: state.now.addingTimeInterval(-2 * 86400))
        store.identity = identity
        store.sharedSettings = shared
        defer { store.stop() }
        try await body(store, fixture, state, file)
    }

    private static func snapshot() -> CockpitTeamDeviceSnapshot {
        CockpitTeamDeviceSnapshot(
            deviceID: "device",
            displayName: "Synthetic Mac",
            updatedAt: 1_790_000_000,
            payload: CockpitTeamUsageSnapshot(deviceID: "device", timestamp: 1_790_000_000))
    }
}

@MainActor
private final class TeamStoreState {
    let now = Date()
    let token = "ccs_" + String(repeating: "t", count: 43)
    var tokens: [String: String] = [:]
    var accountID = "account-a"
    var quotaAvailable = true
    var resetInterval: TimeInterval = 3 * 86400
    var failNextRealTokenWrite = false
    var realTokenWrites = 0

    init() {
        self.tokens = ["https://example.invalid|device": self.token]
    }
}

private actor TeamStoreFixture {
    private var identity: CockpitTeamIdentity
    private var plan: CockpitTeamDailyPlan
    private let token: String
    private var conflictingSettings: CockpitTeamSharedSettings?
    private var offline = false
    private var shouldBlockIdentity = false
    private var identityRelease: CheckedContinuation<Void, Never>?
    private var identityWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requests: [URLRequest] = []

    init(identity: CockpitTeamIdentity, plan: CockpitTeamDailyPlan, token: String) {
        self.identity = identity
        self.plan = plan
        self.token = token
    }

    func goOffline() { self.offline = true }
    func conflictGroups(with settings: CockpitTeamSharedSettings) { self.conflictingSettings = settings }
    func blockNextIdentity() { self.shouldBlockIdentity = true }

    func waitUntilBlocked() async {
        if self.identityRelease != nil { return }
        await withCheckedContinuation { self.identityWaiters.append($0) }
    }

    func releaseIdentity() {
        self.identityRelease?.resume()
        self.identityRelease = nil
    }

    func uploads() throws -> [CockpitTeamUsageSnapshot] {
        try self.requests.filter { $0.url?.path == "/v1/sync" }.map {
            try JSONDecoder().decode(Upload.self, from: $0.httpBody ?? Data()).payload
        }
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        self.requests.append(request)
        if request.url?.path == "/v1/me", self.shouldBlockIdentity {
            self.shouldBlockIdentity = false
            await withCheckedContinuation {
                self.identityRelease = $0
                let waiters = self.identityWaiters
                self.identityWaiters = []
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }
        if self.offline { throw CockpitTeamError.network }
        let data: Data
        var status = 200
        switch request.url?.path {
        case "/v1/join":
            let joining = try JSONDecoder().decode(JoinRequest.self, from: request.httpBody ?? Data())
            self.identity.deviceID = joining.deviceId
            self.identity.members = [CockpitTeamDevice(deviceID: joining.deviceId, displayName: joining.displayName)]
            data = Data("{\"ok\":true,\"spaceId\":\"space\",\"token\":\"\(self.token)\"}".utf8)
            status = 201
        case "/v1/me":
            var encoded = Data("{\"ok\":true,".utf8)
            try encoded.append(JSONEncoder().encode(self.identity).dropFirst())
            data = encoded
        case "/v1/sync":
            let upload = try JSONDecoder().decode(Upload.self, from: request.httpBody ?? Data())
            data = try Self.page("snapshots", [CockpitTeamDeviceSnapshot(
                deviceID: upload.payload.deviceID,
                displayName: "Synthetic Mac",
                updatedAt: Double(upload.payload.timestamp),
                payload: upload.payload)])
        case "/v1/snapshots":
            data = try Self.page("snapshots", [CockpitTeamDeviceSnapshot]())
        case "/v2/groups":
            status = 409
            data = Data("{\"ok\":false,\"error\":\"settings_conflict\"}".utf8)
        case "/v2/settings":
            data = try Self.page("sharedSettings", self.conflictingSettings ?? self.identity.sharedSettings)
        case "/v2/daily-plan":
            let change = try JSONDecoder().decode(PlanRequest.self, from: request.httpBody ?? Data()).change
            if let change, let personID = change.personID {
                self.plan.people[personID] = CockpitTeamPlanField(
                    value: change.value,
                    revision: change.expectedRevision + 1)
            }
            data = try Self.page("plan", self.plan)
        default:
            throw CockpitTeamError.invalidRequest
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        return (data, response)
    }

    private static func page(_ field: String, _ value: some Encodable) throws -> Data {
        var result = Data("{\"ok\":true,\"\(field)\":".utf8)
        try result.append(JSONEncoder().encode(value))
        result.append(Data("}".utf8))
        return result
    }

    private struct Upload: Decodable { let payload: CockpitTeamUsageSnapshot }
    private struct JoinRequest: Decodable { let deviceId: String; let displayName: String }
    private struct PlanRequest: Decodable { let change: CockpitTeamPlanChange? }
}
