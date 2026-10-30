import Dispatch
import Foundation

public struct CockpitTaskLineageSource: Sendable, Equatable, Hashable {
    public let identity: CockpitTaskIdentity
    public let source: SessionToolActivitySource

    public init(identity: CockpitTaskIdentity, source: SessionToolActivitySource) {
        self.identity = identity
        self.source = source
    }
}

public struct CockpitTaskLineageLoadResult: Sendable, Equatable {
    public let metadata: [CockpitTaskIdentity: CockpitTaskLineageMetadata]
    public let unavailable: Set<CockpitTaskIdentity>
    public let conflicting: Set<CockpitTaskIdentity>
    public let wasLimited: Bool
}

/// Reads only a bounded first-record metadata prefix from scanner-owned sources.
/// No home-directory discovery, transcript retention, usage scan or credential access occurs here.
public enum CockpitTaskLineageLoader {
    public struct Limits: Sendable {
        public var files: Int
        public var bytes: Int
        public var lineBytes: Int
        public var duration: TimeInterval

        public init(
            files: Int = 4096,
            bytes: Int = 16 * 1024 * 1024,
            lineBytes: Int = 64 * 1024,
            duration: TimeInterval = 2)
        {
            self.files = max(0, files)
            self.bytes = max(0, bytes)
            self.lineBytes = max(0, lineBytes)
            self.duration = duration.isFinite ? max(0, duration) : 0
        }
    }

    private static let queue = DispatchQueue(label: "io.github.kakapoo233.codexbar-cockpit.task-lineage", qos: .utility)

    public static func load(
        sources: [CockpitTaskLineageSource],
        limits: Limits = Limits()) async throws -> CockpitTaskLineageLoadResult
    {
        try await CostUsageScanExecutor.run(on: self.queue) { checkCancellation in
            try self.read(sources: sources, limits: limits, checkCancellation: checkCancellation)
        }
    }

    static func read(
        sources: [CockpitTaskLineageSource],
        limits: Limits = Limits(),
        checkCancellation: () throws -> Void = {}) throws -> CockpitTaskLineageLoadResult
    {
        let ordered = Set(sources).sorted {
            if $0.identity != $1.identity { return $0.identity < $1.identity }
            return $0.source.fileURL.path < $1.source.fileURL.path
        }
        let start = ContinuousClock.now
        var metadata: [CockpitTaskIdentity: CockpitTaskLineageMetadata] = [:]
        var conflicting: Set<CockpitTaskIdentity> = []
        var remainingBytes = limits.bytes
        var visited = 0
        var wasLimited = false
        for entry in ordered {
            try checkCancellation()
            let elapsed = (ContinuousClock.now - start).components
            let elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
            guard visited < limits.files, remainingBytes > 0, elapsedSeconds < limits.duration else {
                wasLimited = true
                break
            }
            visited += 1
            guard entry.source.sessionID == entry.identity.sessionID,
                  let line = try self.firstLine(
                      source: entry.source,
                      lineLimit: limits.lineBytes,
                      remainingBytes: &remainingBytes,
                      wasLimited: &wasLimited,
                      checkCancellation: checkCancellation),
                  let parsed = self.parse(line: line, expectedSessionID: entry.identity.sessionID)
            else { continue }
            guard !conflicting.contains(entry.identity) else { continue }
            if let existing = metadata[entry.identity] {
                if let merged = self.merge(existing, parsed) {
                    metadata[entry.identity] = merged
                } else {
                    conflicting.insert(entry.identity)
                    metadata.removeValue(forKey: entry.identity)
                }
            } else {
                metadata[entry.identity] = parsed
            }
        }
        let unavailable = Set(sources.map(\.identity)).subtracting(metadata.keys)
        return CockpitTaskLineageLoadResult(
            metadata: metadata,
            unavailable: unavailable,
            conflicting: conflicting,
            wasLimited: wasLimited)
    }

    private static func firstLine(
        source: SessionToolActivitySource,
        lineLimit: Int,
        remainingBytes: inout Int,
        wasLimited: inout Bool,
        checkCancellation: () throws -> Void) throws -> Data?
    {
        guard lineLimit > 0 else {
            wasLimited = true
            return nil
        }
        guard source.fileURL.isFileURL,
              let values = try? source.fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let handle = try? FileHandle(forReadingFrom: source.fileURL)
        else { return nil }
        defer { try? handle.close() }
        var data = Data()
        while data.count < lineLimit, remainingBytes > 0 {
            try checkCancellation()
            let count = min(4096, lineLimit - data.count, remainingBytes)
            guard let chunk = try? handle.read(upToCount: count) else { return nil }
            remainingBytes -= chunk.count
            if chunk.isEmpty { return data }
            if let newline = chunk.firstIndex(of: 0x0A) {
                data.append(chunk.prefix(upTo: newline))
                return data
            }
            data.append(chunk)
        }
        // A line that reaches a budget before its terminator is not evidence of root ownership.
        wasLimited = true
        return nil
    }

    static func parse(line: Data, expectedSessionID: String) -> CockpitTaskLineageMetadata? {
        guard self.safeID(expectedSessionID) == expectedSessionID,
              let string = String(data: line, encoding: .utf8),
              let native = CodexRolloutFirstLineParser.parse(string),
              self.safeID(native.sessionID) == expectedSessionID,
              let record = try? JSONDecoder().decode(MetadataRecord.self, from: line)
        else { return nil }
        let payload = record.payload
        let fork = [payload.forkedFromID, payload.forkedFromCamel, payload.parentSessionID, payload.parentSessionCamel]
            .lazy.compactMap(self.safeID).first
        let parent = [payload.parentThreadID, payload.source?.parentThreadID]
            .lazy.compactMap(self.safeID).first
        let isSubagent = parent != nil || payload.source?.isSubagent == true || payload.threadSource == "subagent"
        return CockpitTaskLineageMetadata(
            sessionID: expectedSessionID,
            parentThreadID: parent ?? (isSubagent ? fork : nil),
            forkedFromID: fork,
            isSubagent: isSubagent)
    }

    private static func safeID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.utf8.count <= 256,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        return trimmed
    }

    private static func merge(
        _ lhs: CockpitTaskLineageMetadata,
        _ rhs: CockpitTaskLineageMetadata) -> CockpitTaskLineageMetadata?
    {
        guard lhs.sessionID == rhs.sessionID,
              lhs.parentThreadID == nil || rhs.parentThreadID == nil || lhs.parentThreadID == rhs.parentThreadID,
              lhs.forkedFromID == nil || rhs.forkedFromID == nil || lhs.forkedFromID == rhs.forkedFromID
        else { return nil }
        return CockpitTaskLineageMetadata(
            sessionID: lhs.sessionID,
            parentThreadID: lhs.parentThreadID ?? rhs.parentThreadID,
            forkedFromID: lhs.forkedFromID ?? rhs.forkedFromID,
            isSubagent: lhs.isSubagent || rhs.isSubagent)
    }
}

private struct MetadataRecord: Decodable {
    let payload: Payload

    struct Payload: Decodable {
        let parentThreadID: String?
        let forkedFromID: String?
        let forkedFromCamel: String?
        let parentSessionID: String?
        let parentSessionCamel: String?
        let threadSource: String?
        let source: Source?

        enum CodingKeys: String, CodingKey {
            case parentThreadID = "parent_thread_id"
            case forkedFromID = "forked_from_id"
            case forkedFromCamel = "forkedFromId"
            case parentSessionID = "parent_session_id"
            case parentSessionCamel = "parentSessionId"
            case threadSource = "thread_source"
            case source
        }
    }

    struct Source: Decodable {
        let isSubagent: Bool
        let parentThreadID: String?

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) {
                self.isSubagent = value.lowercased() == "subagent"
                self.parentThreadID = nil
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.isSubagent = container.contains(.subagent)
            if let subagent = try? container.decode(Subagent.self, forKey: .subagent) {
                self.parentThreadID = subagent.threadSpawn?.parentThreadID
            } else {
                self.parentThreadID = nil
            }
        }

        enum CodingKeys: String, CodingKey { case subagent }
    }

    struct Subagent: Decodable {
        let threadSpawn: Spawn?

        enum CodingKeys: String, CodingKey { case threadSpawn = "thread_spawn" }
    }

    struct Spawn: Decodable {
        let parentThreadID: String?

        enum CodingKeys: String, CodingKey { case parentThreadID = "parent_thread_id" }
    }
}
