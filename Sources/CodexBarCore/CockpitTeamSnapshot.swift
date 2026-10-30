import Foundation

public struct CockpitTeamModelUsage: Codable, Equatable, Sendable {
    public var modelID: String
    public var name: String?
    public var inputTokens: Int64
    public var cachedInputTokens: Int64?
    public var outputTokens: Int64
    public var reasoningTokens: Int64?
    public var cost: Double?

    public init(
        modelID: String,
        name: String? = nil,
        inputTokens: Int64,
        cachedInputTokens: Int64? = nil,
        outputTokens: Int64,
        reasoningTokens: Int64? = nil,
        cost: Double? = nil)
    {
        self.modelID = modelID
        self.name = name
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.cost = cost
    }

    private enum CodingKeys: String, CodingKey {
        case modelID = "model_id"
        case name, cost
        case inputTokens = "in"
        case cachedInputTokens = "cr"
        case outputTokens = "out"
        case reasoningTokens = "reason"
    }
}

public struct CockpitTeamRangeUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int64
    public var cachedInputTokens: Int64?
    public var outputTokens: Int64
    public var reasoningTokens: Int64?
    public var cost: Double?
    public var models: [CockpitTeamModelUsage]

    public init(
        inputTokens: Int64,
        cachedInputTokens: Int64? = nil,
        outputTokens: Int64,
        reasoningTokens: Int64? = nil,
        cost: Double? = nil,
        models: [CockpitTeamModelUsage] = [])
    {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.cost = cost
        self.models = models
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "in"
        case cachedInputTokens = "cached"
        case outputTokens = "out"
        case reasoningTokens = "reason"
        case cost, models
    }
}

public struct CockpitTeamLedgerModel: Codable, Equatable, Sendable {
    public var name: String?
    public var inputTokens: Int64
    public var cachedInputTokens: Int64?
    public var cacheWriteTokens: Int64?
    public var outputTokens: Int64
    public var reasoningTokens: Int64?
    public var cost: Double?

    public init(
        name: String? = nil,
        inputTokens: Int64,
        cachedInputTokens: Int64? = nil,
        cacheWriteTokens: Int64? = nil,
        outputTokens: Int64,
        reasoningTokens: Int64? = nil,
        cost: Double? = nil)
    {
        self.name = name
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.cost = cost
    }

    private enum CodingKeys: String, CodingKey {
        case name, cost
        case inputTokens = "in"
        case cachedInputTokens = "cr"
        case cacheWriteTokens = "cw"
        case outputTokens = "out"
        case reasoningTokens = "reason"
    }
}

public struct CockpitTeamLedgerDay: Codable, Equatable, Sendable {
    public var inputTokens: Int64
    public var cachedInputTokens: Int64?
    public var outputTokens: Int64
    public var reasoningTokens: Int64?
    public var cost: Double?
    public var models: [String: CockpitTeamLedgerModel]

    public init(
        inputTokens: Int64,
        cachedInputTokens: Int64? = nil,
        outputTokens: Int64,
        reasoningTokens: Int64? = nil,
        cost: Double? = nil,
        models: [String: CockpitTeamLedgerModel] = [:])
    {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.cost = cost
        self.models = models
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "in"
        case cachedInputTokens = "cached"
        case outputTokens = "out"
        case reasoningTokens = "reason"
        case cost, models
    }
}

public struct CockpitTeamSnapshotMetadata: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case ready, partial, unavailable }
    public var schemaVersion = 1
    public var collectedAt: String?
    public var status: Status?
    public var retainedDays: Int?
    public var nativeDays: [String]?

    public init(
        collectedAt: String? = nil,
        status: Status? = nil,
        retainedDays: Int? = nil,
        nativeDays: [String]? = nil)
    {
        self.collectedAt = collectedAt
        self.status = status
        self.retainedDays = retainedDays
        self.nativeDays = nativeDays
    }
}

/// An allowlisted aggregate. This type cannot carry provider credentials, messages, paths or task titles.
public struct CockpitTeamUsageSnapshot: Codable, Equatable, Sendable {
    public struct Codex: Codable, Equatable, Sendable {
        public var ranges: [String: CockpitTeamRangeUsage]
    }

    public struct Ledger: Codable, Equatable, Sendable {
        public struct Tools: Codable, Equatable, Sendable {
            public var codex: [String: CockpitTeamLedgerDay]
        }

        public var v: Int?
        public var tools: Tools
    }

    public var deviceID: String
    public var timestamp: Int64
    public var codex: Codex
    public var ledger: Ledger
    public var metadata: CockpitTeamSnapshotMetadata?
    public var days: [String: CockpitTeamLedgerDay] {
        self.ledger.tools.codex
    }

    public init(
        deviceID: String,
        timestamp: Int64,
        ranges: [String: CockpitTeamRangeUsage] = [:],
        days: [String: CockpitTeamLedgerDay] = [:],
        metadata: CockpitTeamSnapshotMetadata? = nil)
    {
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.codex = Codex(ranges: ranges)
        self.ledger = Ledger(v: 1, tools: Ledger.Tools(codex: days))
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID = "_device"
        case timestamp = "_ts"
        case codex
        case ledger = "_ledger"
        case metadata = "_cockpit"
    }
}

public struct CockpitTeamDeviceSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var deviceID: String
    public var displayName: String
    public var updatedAt: Double
    public var payload: CockpitTeamUsageSnapshot
    public var id: String {
        self.deviceID
    }

    public init(deviceID: String, displayName: String, updatedAt: Double, payload: CockpitTeamUsageSnapshot) {
        self.deviceID = deviceID
        self.displayName = displayName
        self.updatedAt = updatedAt
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID = "deviceId"
        case displayName, updatedAt, payload
    }
}
