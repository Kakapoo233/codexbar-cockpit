import Foundation

public enum CockpitResetKind: Equatable, Sendable, Codable {
    case regular
    case banked
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "regular": self = .regular
        case "banked": self = .banked
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .regular: "regular"
        case .banked: "banked"
        case let .unknown(value): value
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

/// Public announcement/observation time, not a confirmation that an individual account has reset.
public struct CockpitResetEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: CockpitResetKind
    public let announcedAt: Date
    public let text: String
    public let sourceType: String
    public let sourceURL: URL
    public let sourceAuthor: String?

    public init(
        id: String,
        kind: CockpitResetKind,
        announcedAt: Date,
        text: String,
        sourceType: String,
        sourceURL: URL,
        sourceAuthor: String? = nil) throws
    {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.utf8.count <= 256,
              announcedAt.timeIntervalSince1970.isFinite,
              text.utf8.count <= 32000,
              !sourceType.isEmpty, sourceType.utf8.count <= 128,
              !kind.rawValue.isEmpty, kind.rawValue.utf8.count <= 128,
              (sourceAuthor?.utf8.count ?? 0) <= 256,
              sourceURL.scheme?.lowercased() == "https",
              sourceURL.host?.isEmpty == false,
              sourceURL.user == nil, sourceURL.password == nil,
              sourceURL.absoluteString.utf8.count <= 4096
        else { throw CockpitResetHistoryError.invalidEvent }
        self.id = id
        self.kind = kind
        self.announcedAt = announcedAt
        self.text = text
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.sourceAuthor = sourceAuthor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            kind: container.decode(CockpitResetKind.self, forKey: .kind),
            announcedAt: container.decode(Date.self, forKey: .announcedAt),
            text: container.decode(String.self, forKey: .text),
            sourceType: container.decode(String.self, forKey: .sourceType),
            sourceURL: container.decode(URL.self, forKey: .sourceURL),
            sourceAuthor: container.decodeIfPresent(String.self, forKey: .sourceAuthor))
    }
}

public struct CockpitResetHistory: Codable, Equatable, Sendable {
    public let events: [CockpitResetEvent]
    public let generatedAt: Date

    public init(events: [CockpitResetEvent], generatedAt: Date) {
        var seen: Set<String> = []
        self.events = events.sorted(by: Self.precedes).filter { seen.insert($0.id).inserted }
        self.generatedAt = generatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decode(Date.self, forKey: .generatedAt)
        guard date.timeIntervalSince1970.isFinite else { throw CockpitResetHistoryError.invalidResponse }
        try self.init(events: container.decode([CockpitResetEvent].self, forKey: .events), generatedAt: date)
    }

    private static func precedes(_ lhs: CockpitResetEvent, _ rhs: CockpitResetEvent) -> Bool {
        if lhs.announcedAt != rhs.announcedAt { return lhs.announcedAt > rhs.announcedAt }
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.sourceURL != rhs.sourceURL { return lhs.sourceURL.absoluteString < rhs.sourceURL.absoluteString }
        if lhs.sourceType != rhs.sourceType { return lhs.sourceType < rhs.sourceType }
        if lhs.sourceAuthor != rhs.sourceAuthor { return (lhs.sourceAuthor ?? "") < (rhs.sourceAuthor ?? "") }
        return lhs.text < rhs.text
    }
}

public enum CockpitResetCalendar {
    /// Calendar arithmetic respects the selected reporting zone and its daylight-saving boundaries.
    public static func eventsByDay(
        _ events: [CockpitResetEvent],
        calendar: Calendar) -> [Date: [CockpitResetEvent]]
    {
        Dictionary(grouping: CockpitResetHistory(events: events, generatedAt: .distantPast).events) {
            calendar.startOfDay(for: $0.announcedAt)
        }
    }
}

public enum CockpitResetHistoryError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidEvent
    case unsupportedAPIVersion
    case httpStatus(Int)
    case rateLimited(retryAfter: TimeInterval)
    case responseTooLarge
    case invalidPagination
    case pageLimitExceeded
}
