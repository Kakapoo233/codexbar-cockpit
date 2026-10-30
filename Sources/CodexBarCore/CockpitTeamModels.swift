import Foundation

/// The v2 service calls devices "members" and people "groups". Keep those identities distinct.
public struct CockpitTeamPerson: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var deviceIDs: [String]

    public init(id: String, name: String, deviceIDs: [String] = []) {
        self.id = id
        self.name = name
        self.deviceIDs = deviceIDs
    }

    private enum CodingKeys: String, CodingKey { case id, name; case deviceIDs = "deviceIds" }
}

public struct CockpitTeamGroups: Codable, Equatable, Sendable {
    public var groups: [CockpitTeamPerson]
    public var defaultGroupID: String?

    public init(groups: [CockpitTeamPerson] = [], defaultGroupID: String? = nil) {
        self.groups = groups
        self.defaultGroupID = defaultGroupID
    }

    private enum CodingKeys: String, CodingKey { case groups; case defaultGroupID = "defaultGroupId" }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.groups, forKey: .groups)
        try container.encode(self.defaultGroupID, forKey: .defaultGroupID)
    }

    public func validate() throws {
        guard self.groups.count <= 32 else { throw CockpitTeamError.invalidRequest }
        var ids = Set<String>(), names = Set<String>(), devices = Set<String>()
        for person in self.groups {
            guard CockpitTeamValidation.safeID(person.id), CockpitTeamValidation.safeName(person.name),
                  ids.insert(person.id).inserted, names.insert(person.name).inserted,
                  person.deviceIDs.count <= 128 else { throw CockpitTeamError.invalidRequest }
            for device in person.deviceIDs {
                guard CockpitTeamValidation.safeID(device), devices.insert(device).inserted else {
                    throw CockpitTeamError.invalidRequest
                }
            }
        }
        guard self.defaultGroupID == nil || ids.contains(self.defaultGroupID ?? "") else {
            throw CockpitTeamError.invalidRequest
        }
    }
}

public enum CockpitTeamRole: String, Codable, Sendable { case owner, member }

public struct CockpitTeamDevice: Codable, Equatable, Identifiable, Sendable {
    public var deviceID: String
    public var displayName: String
    public var role: CockpitTeamRole
    public var updatedAt: Double?
    public var heartbeatAt: Double?
    public var id: String {
        self.deviceID
    }

    public init(
        deviceID: String,
        displayName: String,
        role: CockpitTeamRole = .member,
        updatedAt: Double? = nil,
        heartbeatAt: Double? = nil)
    {
        self.deviceID = deviceID
        self.displayName = displayName
        self.role = role
        self.updatedAt = updatedAt
        self.heartbeatAt = heartbeatAt
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID = "deviceId"
        case displayName, role, updatedAt, heartbeatAt
    }
}

public struct CockpitTeamSpace: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct CockpitTeamIdentity: Codable, Equatable, Sendable {
    public var space: CockpitTeamSpace
    public var deviceID: String
    public var role: CockpitTeamRole
    public var members: [CockpitTeamDevice]
    public var sharedSettings: CockpitTeamSharedSettings
    public var groupSettings: CockpitTeamGroups?

    public init(
        space: CockpitTeamSpace,
        deviceID: String,
        role: CockpitTeamRole,
        members: [CockpitTeamDevice],
        sharedSettings: CockpitTeamSharedSettings,
        groupSettings: CockpitTeamGroups? = nil)
    {
        self.space = space
        self.deviceID = deviceID
        self.role = role
        self.members = members
        self.sharedSettings = sharedSettings
        self.groupSettings = groupSettings
    }

    private enum CodingKeys: String, CodingKey {
        case space, role, members, sharedSettings, groupSettings
        case deviceID = "deviceId"
    }
}

public struct CockpitTeamEnrollment: Codable, Equatable, Sendable {
    public let spaceID: String
    /// Returned once by the server. The application must put this in its credential store.
    public let token: String
    public let inviteCode: String?
    public let inviteExpiresAt: Double?

    private enum CodingKeys: String, CodingKey {
        case spaceID = "spaceId"
        case token, inviteCode, inviteExpiresAt
    }
}

public struct CockpitTeamInvite: Codable, Equatable, Sendable {
    public let inviteCode: String
    public let inviteExpiresAt: Double
}

public struct CockpitTeamPrice: Codable, Equatable, Sendable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var canonicalSlug: String?

    public init(input: Double, output: Double, cacheRead: Double, canonicalSlug: String? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.canonicalSlug = canonicalSlug
    }

    private enum CodingKeys: String, CodingKey {
        case input = "in"
        case output = "out"
        case cacheRead = "cache_read"
        case canonicalSlug = "canonical_slug"
    }
}

public struct CockpitTeamPricing: Codable, Equatable, Sendable {
    public var models: [String: CockpitTeamPrice]
    public var aliases: [String: String]

    public static var bundled: Self {
        Self(models: CostUsagePricing.cockpitTeamBundledPricing)
    }

    public init(models: [String: CockpitTeamPrice], aliases: [String: String] = [:]) {
        self.models = models
        self.aliases = aliases
    }

    public func validate() throws {
        guard !self.models.isEmpty, self.models.count <= 2048, self.aliases.count <= 4096 else {
            throw CockpitTeamError.invalidRequest
        }
        for (id, rate) in self.models {
            guard CockpitTeamValidation.modelID(id),
                  [rate.input, rate.output, rate.cacheRead].allSatisfy({ $0.isFinite && (0...1e6).contains($0) }),
                  rate.canonicalSlug.map(CockpitTeamValidation.modelID) ?? true
            else {
                throw CockpitTeamError.invalidRequest
            }
        }
        guard self.aliases.allSatisfy({ CockpitTeamValidation.modelID($0.key)
                && CockpitTeamValidation.modelID($0.value) }) else { throw CockpitTeamError.invalidRequest }
    }
}

public struct CockpitTeamSettingsValue: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var groups: CockpitTeamGroups
    public var pricing: CockpitTeamPricing
    public var costPolicy: String

    public init(groups: CockpitTeamGroups, pricing: CockpitTeamPricing) {
        self.schemaVersion = 2
        self.groups = groups
        self.pricing = pricing
        self.costPolicy = "event-context-v1"
    }

    public func validate() throws {
        guard self.schemaVersion == 2, self.costPolicy == "event-context-v1" else {
            throw CockpitTeamError.unsupportedProtocol
        }
        try self.groups.validate()
        try self.pricing.validate()
    }
}

public struct CockpitTeamSharedSettings: Codable, Equatable, Sendable {
    public var revision: Int
    public var value: CockpitTeamSettingsValue?

    public init(revision: Int = 0, value: CockpitTeamSettingsValue? = nil) {
        self.revision = revision
        self.value = value
    }
}
