import Foundation

/// Dates in the original v2 shared plan use Asia/Shanghai, independently of local reporting settings.
public struct CockpitTeamPlanBasis: Codable, Equatable, Sendable {
    public var localDate: String
    public var anchorAt: String
    public var remainingPercent: Double
    public var resetsAt: String

    public init(localDate: String, anchorAt: String, remainingPercent: Double, resetsAt: String) {
        self.localDate = localDate
        self.anchorAt = anchorAt
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct CockpitTeamPlanField: Codable, Equatable, Sendable {
    public var value: Double?
    public var revision: Int

    public init(value: Double? = nil, revision: Int = 0) {
        self.value = value
        self.revision = revision
    }
}

public struct CockpitTeamDailyPlan: Codable, Equatable, Sendable {
    public var basis: CockpitTeamPlanBasis
    public var people: [String: CockpitTeamPlanField]
    public var risk: CockpitTeamPlanField

    public init(
        basis: CockpitTeamPlanBasis,
        people: [String: CockpitTeamPlanField] = [:],
        risk: CockpitTeamPlanField = CockpitTeamPlanField())
    {
        self.basis = basis
        self.people = people
        self.risk = risk
    }
}

public struct CockpitTeamPlanChange: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case person, risk }
    public var kind: Kind
    public var personID: String?
    public var value: Double?
    public var expectedRevision: Int

    public init(kind: Kind, personID: String? = nil, value: Double?, expectedRevision: Int) {
        self.kind = kind
        self.personID = personID
        self.value = value
        self.expectedRevision = expectedRevision
    }

    private enum CodingKeys: String, CodingKey {
        case kind, value, expectedRevision
        case personID = "personId"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.kind, forKey: .kind)
        try container.encodeIfPresent(self.personID, forKey: .personID)
        try container.encode(self.value, forKey: .value)
        try container.encode(self.expectedRevision, forKey: .expectedRevision)
    }
}
