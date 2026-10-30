import Foundation
import Testing
@testable import CodexBarCore

struct CockpitTaskLineageTests {
    private func key(_ session: String, source: String = "codex-main") -> CockpitTaskIdentity {
        CockpitTaskIdentity(sourceID: source, sessionID: session)
    }

    @Test
    func `nested subagents and repeated selections include each ledger session once`() {
        let root = self.key("root")
        let child = self.key("child")
        let leaf = self.key("leaf")
        let independent = self.key("independent")
        let graph = CockpitTaskLineage.build(
            sessionIDs: [root, child, leaf, independent, root],
            metadata: [
                child: .init(sessionID: "child", parentThreadID: "root"),
                leaf: .init(sessionID: "leaf", parentThreadID: "child"),
            ])

        #expect(graph.rootBySession[leaf] == root)
        #expect(graph.groups.count == 2)
        #expect(graph.groups.first { $0.rootID == root }?.sessionIDs == [child, leaf, root])
        #expect(graph.resolvedSessionIDs(for: [root, child, leaf]) == [root, child, leaf])
        #expect(graph.resolvedSessionIDs(for: [child]) == [child, leaf])
        #expect(graph.resolvedSessionIDs(for: [root], includeSubagents: false) == [root])
        #expect(graph.resolvedSessionIDs(for: [self.key("absent")]).isEmpty)
    }

    @Test
    func `ordinary forks remain separate tasks and accounts cannot adopt each others sessions`() {
        let parent = self.key("parent")
        let fork = self.key("fork")
        let forkChild = self.key("fork-child")
        let otherAccountParent = self.key("parent", source: "codex-other")
        let orphan = self.key("orphan", source: "codex-other")
        let graph = CockpitTaskLineage.build(
            sessionIDs: [parent, fork, forkChild, otherAccountParent, orphan],
            metadata: [
                fork: .init(sessionID: "fork", forkedFromID: "parent"),
                forkChild: .init(sessionID: "fork-child", parentThreadID: "fork"),
                orphan: .init(sessionID: "orphan", parentThreadID: "fork"),
            ])

        #expect(graph.rootBySession[fork] == fork)
        #expect(graph.rootBySession[forkChild] == fork)
        #expect(graph.resolvedSessionIDs(for: [parent]) == [parent])
        #expect(graph.resolvedSessionIDs(for: [fork]) == [fork, forkChild])
        #expect(graph.groups.first { $0.rootID == orphan }?.issues == [.missingParent])
        #expect(graph.rootBySession[otherAccountParent] == otherAccountParent)
    }

    @Test
    func `missing parents and cycles preserve every session without inventing a root`() {
        let a = self.key("a")
        let b = self.key("b")
        let child = self.key("child")
        let missing = self.key("missing")
        let metadata: [CockpitTaskIdentity: CockpitTaskLineageMetadata] = [
            a: .init(sessionID: "a", parentThreadID: "b"),
            b: .init(sessionID: "b", parentThreadID: "a"),
            child: .init(sessionID: "child", parentThreadID: "b"),
            missing: .init(sessionID: "missing", parentThreadID: "not-in-range"),
        ]
        let graph = CockpitTaskLineage.build(sessionIDs: [child, b, a, missing], metadata: metadata)
        let repeated = CockpitTaskLineage.build(sessionIDs: [missing, a, b, child], metadata: metadata)

        #expect(graph == repeated)
        #expect(graph.rootBySession[a] == a)
        #expect(graph.rootBySession[b] == b)
        #expect(graph.rootBySession[child] == child)
        #expect(graph.groups.first { $0.rootID == a }?.issues == [.cycle])
        #expect(graph.groups.first { $0.rootID == child }?.issues == [.cycle])
        #expect(graph.groups.first { $0.rootID == missing }?.issues == [.missingParent])
        #expect(graph.resolvedSessionIDs(for: [a, b]) == [a, b])
        #expect(Set(graph.groups.flatMap(\.sessionIDs)) == [a, b, child, missing])
    }

    @Test
    func `missing or conflicting metadata remains visible without inventing ownership`() {
        let unavailable = self.key("unavailable")
        let conflict = self.key("conflict")
        let nonCodex = self.key("other", source: "claude-main")
        let graph = CockpitTaskLineage.build(
            sessionIDs: [unavailable, conflict, nonCodex],
            metadata: [conflict: .init(sessionID: "conflict", parentThreadID: "other")],
            metadataRequired: [unavailable, conflict],
            conflictingMetadata: [conflict])

        #expect(graph.groups.first { $0.rootID == unavailable }?.issues == [.metadataUnavailable])
        #expect(graph.groups.first { $0.rootID == conflict }?.issues == [.conflictingMetadata])
        #expect(graph.groups.first { $0.rootID == nonCodex }?.issues == [])
    }

    @Test
    func `identity does not collide when source or session contains separators`() throws {
        let first = self.key("c", source: "a:b")
        let second = self.key("b:c", source: "a")
        #expect(first != second)
        #expect(first.id != second.id)
        #expect(try JSONDecoder().decode(CockpitTaskIdentity.self, from: JSONEncoder().encode(first)) == first)
    }

    @Test
    func `metadata accepts nested and legacy subagents but keeps ordinary forks independent`() throws {
        let modern = try #require(self.parse([
            "id": "leaf",
            "forked_from_id": "base-history",
            "source": ["subagent": ["thread_spawn": ["parent_thread_id": "root"]]],
            "message": "not retained",
        ], expected: "leaf"))
        #expect(modern.parentThreadID == "root")
        #expect(modern.forkedFromID == "base-history")
        #expect(modern.isSubagent)

        let legacy = try #require(self.parse([
            "id": "leaf", "source": "subagent", "forked_from_id": "root",
        ], expected: "leaf"))
        #expect(legacy.parentThreadID == "root")
        let fork = try #require(self.parse([
            "id": "fork", "forkedFromId": "root", "source": "cli",
        ], expected: "fork"))
        #expect(!fork.isSubagent)
        #expect(fork.parentThreadID == nil)
        #expect(fork.forkedFromID == "root")
        #expect(self.parse(["id": "different"], expected: "leaf") == nil)
        #expect(self.parse(["id": "leaf", "parent_thread_id": "bad\nID"], expected: "leaf")?.parentThreadID == nil)
        #expect(CockpitTaskLineageLoader.parse(line: Data("{\"type\":\"event_msg\"}".utf8),
                                             expectedSessionID: "leaf") == nil)
    }

    @Test
    func `bounded metadata loader deduplicates paths and does not retain transcript bodies`() throws {
        let directory = try self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try self.writeSource(
            directory: directory,
            filename: "leaf.jsonl",
            payload: ["id": "leaf", "parent_thread_id": "root"])
        let result = try CockpitTaskLineageLoader.read(sources: [source, source])
        #expect(result.metadata[source.identity]?.parentThreadID == "root")
        #expect(result.unavailable.isEmpty)
        #expect(!result.wasLimited)
        #expect(!String(describing: result).contains("DO_NOT_RETAIN_TRANSCRIPT"))

        let mismatch = CockpitTaskLineageSource(
            identity: self.key("other"),
            source: SessionToolActivitySource(fileURL: source.source.fileURL, sessionID: "leaf"))
        let failed = try CockpitTaskLineageLoader.read(sources: [mismatch])
        #expect(failed.metadata.isEmpty)
        #expect(failed.unavailable == [mismatch.identity])
    }

    @Test
    func `conflicting copies stay ungrouped and read limits never imply complete coverage`() throws {
        let directory = try self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try self.writeSource(
            directory: directory, filename: "first.jsonl", payload: ["id": "leaf", "parent_thread_id": "root-a"])
        let second = try self.writeSource(
            directory: directory, filename: "second.jsonl", payload: ["id": "leaf", "parent_thread_id": "root-b"])
        let conflicting = try CockpitTaskLineageLoader.read(sources: [second, first])
        #expect(conflicting.metadata.isEmpty)
        #expect(conflicting.conflicting == [first.identity])
        #expect(conflicting.unavailable == [first.identity])

        let limited = try CockpitTaskLineageLoader.read(sources: [first], limits: .init(files: 0))
        #expect(limited.wasLimited)
        #expect(limited.metadata.isEmpty)
        #expect(limited.unavailable == [first.identity])
        let lineLimited = try CockpitTaskLineageLoader.read(sources: [first], limits: .init(lineBytes: 8))
        #expect(lineLimited.metadata.isEmpty)
        #expect(lineLimited.wasLimited)
        #expect(lineLimited.unavailable == [first.identity])
        #expect(throws: CancellationError.self) {
            try CockpitTaskLineageLoader.read(sources: [first], checkCancellation: { throw CancellationError() })
        }
    }

    @Test
    func `symlinked metadata and truncated records are unavailable`() throws {
        let directory = try self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try self.writeSource(directory: directory, filename: "leaf.jsonl", payload: ["id": "leaf"])
        let link = directory.appendingPathComponent("linked.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source.source.fileURL)
        let linked = CockpitTaskLineageSource(
            identity: source.identity, source: .init(fileURL: link, sessionID: "leaf"))
        #expect(try CockpitTaskLineageLoader.read(sources: [linked]).unavailable == [source.identity])
        try Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"leaf\"".utf8).write(to: source.source.fileURL)
        #expect(try CockpitTaskLineageLoader.read(sources: [source]).metadata.isEmpty)
    }

    private func parse(_ payload: [String: Any], expected: String) -> CockpitTaskLineageMetadata? {
        guard let data = try? JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": payload])
        else { return nil }
        return CockpitTaskLineageLoader.parse(line: data, expectedSessionID: expected)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cockpit-lineage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeSource(
        directory: URL,
        filename: String,
        payload: [String: Any]) throws -> CockpitTaskLineageSource
    {
        let url = directory.appendingPathComponent(filename)
        var data = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": payload])
        data.append(Data("\n{\"type\":\"response_item\",\"body\":\"DO_NOT_RETAIN_TRANSCRIPT\"}\n".utf8))
        try data.write(to: url)
        let id = payload["id"] as? String ?? "leaf"
        return CockpitTaskLineageSource(identity: self.key(id), source: .init(fileURL: url, sessionID: id))
    }
}
