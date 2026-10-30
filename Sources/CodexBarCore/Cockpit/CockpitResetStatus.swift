import Foundation

/// A source announcement awaiting execution. Passing its target time never marks it completed.
public struct CockpitScheduledReset: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let status: String
    public let kind: CockpitResetKind
    public let announcedAt: Date
    public let scheduledFor: Date?
    public let text: String
    public let sourceType: String
    public let sourceURL: URL
    public let sourceAuthor: String?

    public init(
        id: String,
        status: String = "scheduled",
        kind: CockpitResetKind = .regular,
        announcedAt: Date,
        scheduledFor: Date?,
        text: String,
        sourceType: String = "x_post",
        sourceURL: URL,
        sourceAuthor: String? = nil) throws
    {
        let event = try CockpitResetEvent(
            id: id,
            kind: kind,
            announcedAt: announcedAt,
            text: text,
            sourceType: sourceType,
            sourceURL: sourceURL,
            sourceAuthor: sourceAuthor)
        guard !status.isEmpty, status.utf8.count <= 128,
              scheduledFor?.timeIntervalSince1970.isFinite != false
        else { throw CockpitResetHistoryError.invalidEvent }
        self.id = event.id
        self.status = status
        self.kind = event.kind
        self.announcedAt = event.announcedAt
        self.scheduledFor = scheduledFor
        self.text = event.text
        self.sourceType = event.sourceType
        self.sourceURL = event.sourceURL
        self.sourceAuthor = event.sourceAuthor
    }

    public func isPending(at now: Date) -> Bool {
        self.status == "scheduled" && self.announcedAt <= now.addingTimeInterval(300)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            status: container.decode(String.self, forKey: .status),
            kind: container.decode(CockpitResetKind.self, forKey: .kind),
            announcedAt: container.decode(Date.self, forKey: .announcedAt),
            scheduledFor: container.decodeIfPresent(Date.self, forKey: .scheduledFor),
            text: container.decode(String.self, forKey: .text),
            sourceType: container.decode(String.self, forKey: .sourceType),
            sourceURL: container.decode(URL.self, forKey: .sourceURL),
            sourceAuthor: container.decodeIfPresent(String.self, forKey: .sourceAuthor))
    }
}

/// Third-party AI-classified watch metadata. Its window is descriptive text, not a promised date.
public struct CockpitResetWatch: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let level: String
    public let resetChancePercent: Int?
    public let forecastWindow: String
    public let observedAt: Date
    public let expiresAt: Date
    public let text: String
    public let sourceType: String
    public let sourceURL: URL

    public init(
        id: String,
        level: String,
        resetChancePercent: Int?,
        forecastWindow: String,
        observedAt: Date,
        expiresAt: Date,
        text: String,
        sourceType: String = "x_post",
        sourceURL: URL) throws
    {
        let event = try CockpitResetEvent(
            id: id,
            kind: .unknown("watch"),
            announcedAt: observedAt,
            text: text,
            sourceType: sourceType,
            sourceURL: sourceURL)
        guard !level.isEmpty, level.utf8.count <= 128,
              resetChancePercent.map({ (0...100).contains($0) }) != false,
              forecastWindow.utf8.count <= 4096,
              expiresAt.timeIntervalSince1970.isFinite, expiresAt > observedAt
        else { throw CockpitResetHistoryError.invalidEvent }
        self.id = event.id
        self.level = level
        self.resetChancePercent = resetChancePercent
        self.forecastWindow = forecastWindow
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.text = event.text
        self.sourceType = event.sourceType
        self.sourceURL = event.sourceURL
    }

    public func isActive(at now: Date) -> Bool {
        ["elevated", "strong"].contains(self.level)
            && self.observedAt <= now.addingTimeInterval(300) && self.expiresAt > now
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            level: container.decode(String.self, forKey: .level),
            resetChancePercent: container.decodeIfPresent(Int.self, forKey: .resetChancePercent),
            forecastWindow: container.decode(String.self, forKey: .forecastWindow),
            observedAt: container.decode(Date.self, forKey: .observedAt),
            expiresAt: container.decode(Date.self, forKey: .expiresAt),
            text: container.decode(String.self, forKey: .text),
            sourceType: container.decode(String.self, forKey: .sourceType),
            sourceURL: container.decode(URL.self, forKey: .sourceURL))
    }
}

public struct CockpitResetStatus: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let latestReset: CockpitResetEvent?
    public let scheduledReset: CockpitScheduledReset?
    public let activeWatch: CockpitResetWatch?

    public init(
        generatedAt: Date,
        latestReset: CockpitResetEvent? = nil,
        scheduledReset: CockpitScheduledReset? = nil,
        activeWatch: CockpitResetWatch? = nil)
    {
        self.generatedAt = generatedAt
        self.latestReset = latestReset
        self.scheduledReset = scheduledReset
        self.activeWatch = activeWatch
    }
}
