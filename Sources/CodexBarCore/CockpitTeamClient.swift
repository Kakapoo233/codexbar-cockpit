import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CockpitTeamError: Error, Equatable, Sendable {
    case invalidEndpoint
    case invalidRequest
    case invalidCredential
    case invalidResponse
    case unsupportedProtocol
    case requestTooLarge
    case responseTooLarge
    case accessDenied
    case conflict
    case rateLimited
    case serviceUnavailable
    case network
    case httpStatus(Int)
}

/// A credential-free transport for the original Codex Cockpit v2 service.
/// Mutations are never automatically retried: enrollment and invitation responses contain one-time secrets.
public struct CockpitTeamClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public static let maximumRequestBytes = 1024 * 1024
    public static let maximumResponseBytes = 40 * 1024 * 1024
    public let endpoint: String
    private let load: Loader

    public init(endpoint: String, load: Loader? = nil) throws {
        self.endpoint = try Self.normalizeEndpoint(endpoint)
        self.load = load ?? { request in try await CockpitTeamHTTPTransport().load(request) }
    }

    public static func normalizeEndpoint(_ value: String) throws -> String {
        guard var parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port.map({ (1...65535).contains($0) }) ?? true
        else {
            throw CockpitTeamError.invalidEndpoint
        }
        parts.scheme = "https"
        parts.host = host.lowercased()
        parts.path = ""
        guard let url = parts.url, url.host != nil else { throw CockpitTeamError.invalidEndpoint }
        return url.absoluteString
    }

    /// Checks service identity and reachability only; this does not exercise its database or device credentials.
    public func checkService() async throws {
        let response: HealthResponse = try await self.send("/health")
        guard response.service == "codex-cockpit-sync", response.version == 1 else {
            throw CockpitTeamError.unsupportedProtocol
        }
    }

    public func createSpace(
        name: String,
        displayName: String,
        deviceID: String,
        bootstrapSecret: String) async throws
        -> CockpitTeamEnrollment
    {
        try Self.validateIdentity(name: displayName, deviceID: deviceID)
        guard CockpitTeamValidation.safeName(name), Self.safeHeader(bootstrapSecret), !bootstrapSecret.isEmpty else {
            throw CockpitTeamError.invalidRequest
        }
        let body = SpaceRequest(name: name, displayName: displayName, deviceId: deviceID)
        let enrollment: CockpitTeamEnrollment = try await self.send(
            "/v1/spaces",
            body: Self.encode(body),
            bootstrap: bootstrapSecret)
        return try Self.validateEnrollment(enrollment)
    }

    public func join(inviteCode: String, displayName: String, deviceID: String) async throws -> CockpitTeamEnrollment {
        try Self.validateIdentity(name: displayName, deviceID: deviceID)
        guard Self.safeHeader(inviteCode), !inviteCode.isEmpty else { throw CockpitTeamError.invalidRequest }
        let body = JoinRequest(inviteCode: inviteCode, displayName: displayName, deviceId: deviceID)
        let enrollment: CockpitTeamEnrollment = try await self.send("/v1/join", body: Self.encode(body))
        return try Self.validateEnrollment(enrollment)
    }

    public func me(token: String) async throws -> CockpitTeamIdentity {
        let identity: CockpitTeamIdentity = try await self.send("/v1/me", token: token)
        guard CockpitTeamValidation.safeID(identity.deviceID), CockpitTeamValidation.safeID(identity.space.id),
              CockpitTeamValidation.safeName(identity.space.name), identity.members.count <= 32,
              Set(identity.members.map(\.deviceID)).count == identity.members.count,
              identity.members.contains(where: { $0.deviceID == identity.deviceID }),
              identity.members.allSatisfy({ CockpitTeamValidation.safeID($0.deviceID)
                      && CockpitTeamValidation.safeName($0.displayName) })
        else {
            throw CockpitTeamError.invalidResponse
        }
        try Self.validateSettings(identity.sharedSettings)
        if let groups = identity.groupSettings { try groups.validate() }
        return identity
    }

    public func settings(token: String) async throws -> CockpitTeamSharedSettings {
        let response: SettingsResponse = try await self.send("/v2/settings", token: token)
        try Self.validateSettings(response.sharedSettings)
        return response.sharedSettings
    }

    public func saveSettings(
        _ value: CockpitTeamSettingsValue,
        expectedRevision: Int,
        token: String) async throws -> CockpitTeamSharedSettings
    {
        try value.validate()
        guard expectedRevision >= 0 else { throw CockpitTeamError.invalidRequest }
        let body = SettingsRequest(expectedRevision: expectedRevision, value: value)
        let response: SettingsResponse = try await self.send(
            "/v2/settings",
            token: token,
            body: Self.encode(body))
        try Self.validateSettings(response.sharedSettings)
        return response.sharedSettings
    }

    public func saveGroups(
        _ groups: CockpitTeamGroups,
        expectedRevision: Int,
        token: String) async throws -> CockpitTeamSharedSettings
    {
        try groups.validate()
        guard expectedRevision >= 0 else { throw CockpitTeamError.invalidRequest }
        let body = GroupsRequest(expectedRevision: expectedRevision, groups: groups)
        let response: SettingsResponse = try await self.send("/v2/groups", token: token, body: Self.encode(body))
        try Self.validateSettings(response.sharedSettings)
        return response.sharedSettings
    }

    public func sync(
        _ snapshot: CockpitTeamUsageSnapshot,
        settingsRevision: Int,
        appVersion: String,
        token: String) async throws
        -> [CockpitTeamDeviceSnapshot]
    {
        try CockpitTeamValidation.snapshot(snapshot)
        guard settingsRevision >= 0, appVersion.range(of: "^[A-Za-z0-9.+-]{1,64}$", options: .regularExpression) != nil
        else { throw CockpitTeamError.invalidRequest }
        let body = SyncRequest(
            deviceId: snapshot.deviceID,
            payload: snapshot,
            clientInfo: ClientInfo(protocolVersion: 2, appVersion: appVersion, settingsRevision: settingsRevision))
        let response: SnapshotsResponse = try await self.send("/v1/sync", token: token, body: Self.encode(body))
        return try Self.validateSnapshots(response.snapshots)
    }

    public func snapshots(token: String) async throws -> [CockpitTeamDeviceSnapshot] {
        let response: SnapshotsResponse = try await self.send("/v1/snapshots", token: token)
        return try Self.validateSnapshots(response.snapshots)
    }

    public func invite(maxUses: Int = 1, expiresHours: Int = 24, token: String) async throws -> CockpitTeamInvite {
        guard (1...20).contains(maxUses), (1...720).contains(expiresHours) else {
            throw CockpitTeamError.invalidRequest
        }
        let body = InviteRequest(maxUses: maxUses, expiresHours: expiresHours)
        let invite: CockpitTeamInvite = try await self.send("/v1/invites", token: token, body: Self.encode(body))
        guard Self.safeHeader(invite.inviteCode), !invite.inviteCode.isEmpty, invite.inviteExpiresAt.isFinite,
              invite.inviteExpiresAt > 0 else { throw CockpitTeamError.invalidResponse }
        return invite
    }

    public func revoke(deviceID: String, token: String) async throws {
        guard CockpitTeamValidation.safeID(deviceID) else { throw CockpitTeamError.invalidRequest }
        let _: SuccessResponse = try await self.send(
            "/v1/devices/revoke",
            token: token,
            body: Self.encode(DeviceRequest(deviceId: deviceID)))
    }

    public func dailyPlan(
        basis: CockpitTeamPlanBasis,
        initialRisk: Double? = nil,
        change: CockpitTeamPlanChange? = nil,
        token: String) async throws -> CockpitTeamDailyPlan
    {
        try CockpitTeamValidation.planBasis(basis)
        guard CockpitTeamValidation.percent(initialRisk) else { throw CockpitTeamError.invalidRequest }
        if let change {
            guard change.expectedRevision >= 0, CockpitTeamValidation.percent(change.value),
                  change.kind != .person || change.personID.map(CockpitTeamValidation.safeID) == true
            else {
                throw CockpitTeamError.invalidRequest
            }
        }
        let body = PlanRequest(basis: basis, initialRisk: initialRisk, change: change)
        let response: PlanResponse = try await self.send("/v2/daily-plan", token: token, body: Self.encode(body))
        try CockpitTeamValidation.plan(response.plan)
        return response.plan
    }

    private func send<Response: Decodable>(
        _ route: String,
        token: String? = nil,
        body: Data? = nil,
        bootstrap: String? = nil) async throws -> Response
    {
        try Task.checkCancellation()
        guard let url = URL(string: self.endpoint + route) else { throw CockpitTeamError.invalidEndpoint }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpShouldHandleCookies = false
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            guard Self.validToken(token) else { throw CockpitTeamError.invalidCredential }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let bootstrap { request.setValue(bootstrap, forHTTPHeaderField: "x-bootstrap-secret") }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await self.load(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CockpitTeamError {
            throw error
        } catch {
            try Task.checkCancellation()
            throw CockpitTeamError.network
        }
        try Task.checkCancellation()
        guard data.count <= Self.maximumResponseBytes else { throw CockpitTeamError.responseTooLarge }
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw CockpitTeamError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw CockpitTeamError.accessDenied
        case 409: throw CockpitTeamError.conflict
        case 413: throw CockpitTeamError.requestTooLarge
        case 429: throw CockpitTeamError.rateLimited
        case 503: throw CockpitTeamError.serviceUnavailable
        default: throw CockpitTeamError.httpStatus(http.statusCode)
        }
        do {
            guard try JSONDecoder().decode(SuccessResponse.self, from: data).ok else {
                throw CockpitTeamError.invalidResponse
            }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CockpitTeamError.invalidResponse
        }
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        let data: Data
        do { data = try JSONEncoder().encode(value) } catch { throw CockpitTeamError.invalidRequest }
        guard data.count <= self.maximumRequestBytes else { throw CockpitTeamError.requestTooLarge }
        return data
    }

    private static func validateIdentity(name: String, deviceID: String) throws {
        guard CockpitTeamValidation.safeName(name), CockpitTeamValidation.safeID(deviceID) else {
            throw CockpitTeamError.invalidRequest
        }
    }

    private static func validateEnrollment(_ enrollment: CockpitTeamEnrollment) throws -> CockpitTeamEnrollment {
        guard CockpitTeamValidation.safeID(enrollment.spaceID), self.validToken(enrollment.token) else {
            throw CockpitTeamError.invalidResponse
        }
        return enrollment
    }

    private static func validateSettings(_ settings: CockpitTeamSharedSettings) throws {
        guard settings.revision >= 0 else { throw CockpitTeamError.invalidResponse }
        try settings.value?.validate()
    }

    private static func validateSnapshots(_ snapshots: [CockpitTeamDeviceSnapshot]) throws
        -> [CockpitTeamDeviceSnapshot]
    {
        guard snapshots.count <= 32, Set(snapshots.map(\.deviceID)).count == snapshots.count else {
            throw CockpitTeamError.invalidResponse
        }
        for snapshot in snapshots {
            guard snapshot.deviceID == snapshot.payload.deviceID,
                  CockpitTeamValidation.safeName(snapshot.displayName),
                  snapshot.updatedAt.isFinite, snapshot.updatedAt > 0 else { throw CockpitTeamError.invalidResponse }
            try CockpitTeamValidation.snapshot(snapshot.payload)
        }
        return snapshots
    }

    private static func safeHeader(_ value: String) -> Bool {
        value.utf8.count <= 1024 && !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
    }

    private static func validToken(_ value: String) -> Bool {
        value.range(of: "^ccs_[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
    }
}

private struct SpaceRequest: Encodable { let name: String; let displayName: String; let deviceId: String }
private struct JoinRequest: Encodable { let inviteCode: String; let displayName: String; let deviceId: String }
private struct DeviceRequest: Encodable { let deviceId: String }
private struct InviteRequest: Encodable { let maxUses: Int; let expiresHours: Int }
private struct SuccessResponse: Decodable { let ok: Bool }
private struct HealthResponse: Decodable { let service: String; let version: Int }
private struct SettingsResponse: Decodable { let sharedSettings: CockpitTeamSharedSettings }
private struct SettingsRequest: Encodable { let expectedRevision: Int; let value: CockpitTeamSettingsValue }
private struct GroupsRequest: Encodable { let expectedRevision: Int; let groups: CockpitTeamGroups }
private struct ClientInfo: Encodable { let protocolVersion: Int; let appVersion: String; let settingsRevision: Int }
private struct SyncRequest: Encodable {
    let deviceId: String
    let payload: CockpitTeamUsageSnapshot
    let clientInfo: ClientInfo
}

private struct SnapshotsResponse: Decodable { let snapshots: [CockpitTeamDeviceSnapshot] }
private struct PlanRequest: Encodable {
    let basis: CockpitTeamPlanBasis
    let initialRisk: Double?
    let change: CockpitTeamPlanChange?
}

private struct PlanResponse: Decodable { let plan: CockpitTeamDailyPlan }
