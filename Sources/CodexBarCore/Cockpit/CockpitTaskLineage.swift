import Foundation

/// A session identity is scoped to its usage source, including the provider/account scope.
/// Titles, project paths and receipt selection never change this identity.
public struct CockpitTaskIdentity: Codable, Sendable, Equatable, Hashable, Identifiable, Comparable {
    public let sourceID: String
    public let sessionID: String

    public var id: String {
        "\(self.sourceID.utf8.count):\(self.sourceID)\(self.sessionID)"
    }

    public init(sourceID: String, sessionID: String) {
        self.sourceID = sourceID
        self.sessionID = sessionID
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.sourceID != rhs.sourceID { return lhs.sourceID < rhs.sourceID }
        return lhs.sessionID < rhs.sessionID
    }
}

/// Only ownership metadata is retained. Token usage is supplied by the native usage ledger,
/// which already removes inherited fork history and archived rollout copies.
public struct CockpitTaskLineageMetadata: Codable, Sendable, Equatable {
    public let sessionID: String
    public let parentThreadID: String?
    public let forkedFromID: String?
    public let isSubagent: Bool

    public init(
        sessionID: String,
        parentThreadID: String? = nil,
        forkedFromID: String? = nil,
        isSubagent: Bool = false)
    {
        self.sessionID = sessionID
        self.parentThreadID = parentThreadID
        self.forkedFromID = forkedFromID
        self.isSubagent = isSubagent || parentThreadID != nil
    }
}

public enum CockpitTaskLineageIssue: String, Codable, Sendable, Hashable {
    case metadataUnavailable
    case missingParent
    case cycle
    case conflictingMetadata
}

public struct CockpitTaskGroup: Sendable, Equatable, Identifiable {
    public let rootID: CockpitTaskIdentity
    public let sessionIDs: [CockpitTaskIdentity]
    public let issues: Set<CockpitTaskLineageIssue>

    public var id: CockpitTaskIdentity {
        self.rootID
    }
}

/// Adds ownership to already-counted session usage; it never estimates or recounts tokens.
/// Ordinary forks remain separate tasks. Only subagent edges contribute to a parent task.
public struct CockpitTaskLineage: Sendable, Equatable {
    public let groups: [CockpitTaskGroup]
    public let rootBySession: [CockpitTaskIdentity: CockpitTaskIdentity]
    private let children: [CockpitTaskIdentity: Set<CockpitTaskIdentity>]

    public static func build(
        sessionIDs: Set<CockpitTaskIdentity>,
        metadata: [CockpitTaskIdentity: CockpitTaskLineageMetadata],
        metadataRequired: Set<CockpitTaskIdentity> = [],
        conflictingMetadata: Set<CockpitTaskIdentity> = []) -> Self
    {
        var parents: [CockpitTaskIdentity: CockpitTaskIdentity] = [:]
        var issues: [CockpitTaskIdentity: Set<CockpitTaskLineageIssue>] = [:]

        for key in sessionIDs {
            if conflictingMetadata.contains(key) {
                issues[key, default: []].insert(.conflictingMetadata)
                continue
            }
            guard let info = metadata[key], info.sessionID == key.sessionID else {
                if metadataRequired.contains(key) {
                    issues[key, default: []].insert(.metadataUnavailable)
                }
                continue
            }
            guard info.isSubagent else { continue }
            guard let parentID = info.parentThreadID else {
                issues[key, default: []].insert(.missingParent)
                continue
            }
            let parent = CockpitTaskIdentity(sourceID: key.sourceID, sessionID: parentID)
            guard sessionIDs.contains(parent) else {
                issues[key, default: []].insert(.missingParent)
                continue
            }
            parents[key] = parent
        }

        var roots: [CockpitTaskIdentity: CockpitTaskIdentity] = [:]
        for key in sessionIDs.sorted() where roots[key] == nil {
            var path: [CockpitTaskIdentity] = []
            var positions: [CockpitTaskIdentity: Int] = [:]
            var current = key
            var root: CockpitTaskIdentity?
            var cyclic = false
            while true {
                if let resolved = roots[current] {
                    root = resolved
                    cyclic = issues[current]?.contains(.cycle) == true
                    break
                }
                if positions[current] != nil {
                    cyclic = true
                    break
                }
                positions[current] = path.count
                path.append(current)
                guard let parent = parents[current] else {
                    root = current
                    break
                }
                current = parent
            }
            for member in path {
                // A malformed ownership cycle has no true root. Keep every session visible as
                // an unlinked task instead of assigning somebody else's work to an arbitrary title.
                roots[member] = cyclic ? member : (root ?? member)
                if cyclic {
                    issues[member, default: []].insert(.cycle)
                    parents.removeValue(forKey: member)
                }
            }
        }

        var children: [CockpitTaskIdentity: Set<CockpitTaskIdentity>] = [:]
        for (child, parent) in parents {
            children[parent, default: []].insert(child)
        }
        var grouped: [CockpitTaskIdentity: [CockpitTaskIdentity]] = [:]
        for (session, root) in roots {
            grouped[root, default: []].append(session)
        }
        let groups = grouped.keys.sorted().map { root in
            let members = (grouped[root] ?? []).sorted()
            return CockpitTaskGroup(
                rootID: root,
                sessionIDs: members,
                issues: members.reduce(into: Set<CockpitTaskLineageIssue>()) {
                    $0.formUnion(issues[$1] ?? [])
                })
        }
        return Self(groups: groups, rootBySession: roots, children: children)
    }

    /// A selected parent and any selected children resolve to a union, so each native
    /// session total is included once. Unknown selection keys cannot introduce new usage.
    public func resolvedSessionIDs(
        for selected: Set<CockpitTaskIdentity>,
        includeSubagents: Bool = true) -> Set<CockpitTaskIdentity>
    {
        var result = selected.filter { self.rootBySession[$0] != nil }
        guard includeSubagents else { return result }
        var pending = Array(result)
        while let current = pending.popLast() {
            for child in self.children[current] ?? [] where result.insert(child).inserted {
                pending.append(child)
            }
        }
        return result
    }
}
