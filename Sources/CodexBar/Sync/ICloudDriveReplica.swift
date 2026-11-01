import Foundation

enum ICloudDriveReplicaError: Error, Equatable {
    case invalidLocation
    case invalidDevice
    case invalidDocument
    case unsupportedVersion
    case pendingDownload
    case limitExceeded
    case obsoleteAcknowledgement
}

struct ICloudDriveSyncResult: Sendable {
    let values: [String: Data]
    let removedKeys: Set<String>
    let deviceCount: Int
    let didUpload: Bool
    /// Apple's local metadata; nil means unavailable, rather than confirmed cloud delivery.
    let uploadedToICloud: Bool?
    let synchronizedAt: Date
    fileprivate let acknowledgementID: UUID
}

/// Per-device files prevent two Macs from overwriting one shared document. Lamport registers retain
/// explicit deletions. Values are typed, non-secret projections supplied and validated by the caller.
actor ICloudDriveReplica {
    private struct Stamp: Codable, Equatable, Comparable {
        let counter: UInt64
        let deviceID: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.counter == rhs.counter ? lhs.deviceID < rhs.deviceID : lhs.counter < rhs.counter
        }
    }

    private struct Register: Codable, Equatable {
        let stamp: Stamp
        let value: Data?
    }

    private struct Document: Codable {
        let version: Int
        let deviceID: String
        var records: [String: Register]
    }

    private struct Journal: Codable {
        let version: Int
        let deviceID: String
        var records: [String: Register]
        var lastApplied: [String: Data]?
    }

    private static let version = 1
    private static let maximumRecords = 10000
    private static let maximumValueBytes = 2 * 1024 * 1024
    private static let maximumDocumentBytes = 24 * 1024 * 1024
    private static let maximumDevices = 64
    private let directoryURL: URL
    private let localStateURL: URL
    private let deviceID: String
    private var pendingAcknowledgement: UUID?

    init(directoryURL: URL, localStateURL: URL, deviceID: String) throws {
        guard let device = UUID(uuidString: deviceID) else { throw ICloudDriveReplicaError.invalidDevice }
        guard directoryURL.isFileURL, localStateURL.isFileURL,
              directoryURL.standardizedFileURL != localStateURL.standardizedFileURL,
              !localStateURL.standardizedFileURL.path.hasPrefix(
                  directoryURL.standardizedFileURL.path + "/")
        else { throw ICloudDriveReplicaError.invalidLocation }
        self.directoryURL = directoryURL.standardizedFileURL
        self.localStateURL = localStateURL.standardizedFileURL
        self.deviceID = device.uuidString.lowercased()
    }

    /// Does no work until invoked. Callers must serialize application-level read/apply/ack cycles.
    /// A failed read, future schema or pending download never becomes an empty remote state.
    func synchronize(
        localValues: [String: Data],
        locallyChangedKeys: Set<String> = [],
        now: Date = Date()) throws -> ICloudDriveSyncResult
    {
        try Task.checkCancellation()
        try Self.validateValues(localValues)
        guard locallyChangedKeys.count <= Self.maximumRecords,
              locallyChangedKeys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 })
        else { throw ICloudDriveReplicaError.limitExceeded }
        var journal = try self.readJournal()
        try Self.ensureDirectory(self.directoryURL)
        let documents = try self.readDocuments()
        var merged = journal.records
        for document in documents {
            try Self.merge(document.records, into: &merged)
        }
        let existingOwn = documents.first { $0.deviceID == self.deviceID }
        var counter = merged.values.map(\.stamp.counter).max() ?? 0
        let keys = Set(localValues.keys).union(journal.lastApplied?.keys ?? [String: Data]().keys)
            .union(locallyChangedKeys)
        for key in keys.sorted() {
            let value = localValues[key]
            let changed: Bool = if locallyChangedKeys.contains(key) {
                true
            } else if let baseline = journal.lastApplied {
                // The app may have applied our previous result immediately before a crash prevented
                // acknowledgement. That already-offered value is not a new edit on restart, even if
                // another device has since published a newer value.
                value != baseline[key]
                    && !(journal.records[key] != nil && journal.records[key]?.value == value)
            } else {
                // A new Mac adopts an existing value or tombstone before publishing its defaults.
                merged[key] == nil && value != nil
            }
            guard changed else { continue }
            guard counter < UInt64.max else { throw ICloudDriveReplicaError.limitExceeded }
            counter += 1
            merged[key] = Register(stamp: Stamp(counter: counter, deviceID: self.deviceID), value: value)
        }
        guard merged.count <= Self.maximumRecords else { throw ICloudDriveReplicaError.limitExceeded }
        let ownRecords = merged.filter { $0.value.stamp.deviceID == self.deviceID }
        let upload = existingOwn?.records != ownRecords
        let ownURL = self.directoryURL.appendingPathComponent(self.deviceID + ".json")
        if upload {
            guard documents.count < Self.maximumDevices || FileManager.default.fileExists(atPath: ownURL.path) else {
                throw ICloudDriveReplicaError.limitExceeded
            }
            let document = Document(version: Self.version, deviceID: self.deviceID, records: ownRecords)
            try Self.write(document, to: ownURL)
        }
        journal.records = merged
        try self.saveJournal(journal)
        let acknowledgementID = UUID()
        self.pendingAcknowledgement = acknowledgementID
        let cloudMetadata = try? ownURL.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey,
        ])
        return ICloudDriveSyncResult(
            values: merged.compactMapValues(\.value),
            removedKeys: Set(merged.compactMap { $0.value.value == nil ? $0.key : nil }),
            deviceCount: Set(documents.map(\.deviceID)).union([self.deviceID]).count,
            didUpload: upload,
            uploadedToICloud: cloudMetadata?.isUbiquitousItem == true
                ? cloudMetadata?.ubiquitousItemIsUploaded : nil,
            synchronizedAt: now,
            acknowledgementID: acknowledgementID)
    }

    /// Acknowledge only after the typed adapter applies the result successfully. Without this step,
    /// interrupted or failed application is retried rather than echoed as a new local edit.
    func acknowledge(_ result: ICloudDriveSyncResult, appliedValues: [String: Data]? = nil) throws {
        guard self.pendingAcknowledgement == result.acknowledgementID else {
            throw ICloudDriveReplicaError.obsoleteAcknowledgement
        }
        let values = appliedValues ?? result.values
        try Self.validateValues(values)
        var journal = try self.readJournal()
        journal.lastApplied = values
        try self.saveJournal(journal)
        self.pendingAcknowledgement = nil
    }

    private func readJournal() throws -> Journal {
        guard FileManager.default.fileExists(atPath: self.localStateURL.path) else {
            return Journal(version: Self.version, deviceID: self.deviceID, records: [:], lastApplied: nil)
        }
        let data = try Self.read(self.localStateURL)
        let journal = try Self.decode(Journal.self, data: data)
        guard journal.version == Self.version else { throw ICloudDriveReplicaError.unsupportedVersion }
        guard journal.deviceID == self.deviceID else { throw ICloudDriveReplicaError.invalidDevice }
        try Self.validateRecords(journal.records)
        if let values = journal.lastApplied { try Self.validateValues(values) }
        return journal
    }

    private func saveJournal(_ journal: Journal) throws {
        try Self.ensureDirectory(self.localStateURL.deletingLastPathComponent())
        try Self.write(journal, to: self.localStateURL)
    }

    private func readDocuments() throws -> [Document] {
        let files = try FileManager.default.contentsOfDirectory(
            at: self.directoryURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
            ])
        let candidates = files.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".json") || (name.hasPrefix(".") && name.hasSuffix(".json.icloud"))
        }
        guard candidates.count <= Self.maximumDevices else { throw ICloudDriveReplicaError.limitExceeded }
        return try candidates.map { url in
            let name = url.lastPathComponent
            let canonical = name.hasPrefix(".") ? String(name.dropFirst()) : name
            guard UUID(uuidString: String(canonical.prefix(36))) != nil else {
                throw ICloudDriveReplicaError.invalidDocument
            }
            if name.hasSuffix(".icloud") {
                let target = url.deletingLastPathComponent()
                    .appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                try? FileManager.default.startDownloadingUbiquitousItem(at: target)
                throw ICloudDriveReplicaError.pendingDownload
            }
            let document = try Self.decode(Document.self, data: Self.read(url))
            guard document.version == Self.version else { throw ICloudDriveReplicaError.unsupportedVersion }
            guard let device = UUID(uuidString: document.deviceID),
                  device.uuidString.lowercased() == document.deviceID,
                  canonical.hasPrefix(document.deviceID)
            else { throw ICloudDriveReplicaError.invalidDocument }
            try Self.validateRecords(document.records, owner: document.deviceID)
            return document
        }
    }

    private static func validateValues(_ values: [String: Data]) throws {
        guard values.count <= self.maximumRecords,
              values.allSatisfy({ !$0.key.isEmpty && $0.key.utf8.count <= 512
                      && $0.value.count <= self.maximumValueBytes }),
              values.values.reduce(0, { $0 + $1.count }) <= self.maximumDocumentBytes / 2
        else { throw ICloudDriveReplicaError.limitExceeded }
    }

    private static func validateRecords(_ records: [String: Register], owner: String? = nil) throws {
        guard records.count <= self.maximumRecords,
              records.allSatisfy({ key, record in
                  !key.isEmpty && key.utf8.count <= 512 && record.stamp.counter > 0
                      && UUID(uuidString: record.stamp.deviceID) != nil
                      && (owner == nil || record.stamp.deviceID == owner)
                      && (record.value?.count ?? 0) <= self.maximumValueBytes
              })
        else { throw ICloudDriveReplicaError.invalidDocument }
    }

    private static func merge(_ records: [String: Register], into merged: inout [String: Register]) throws {
        for (key, record) in records {
            if let existing = merged[key] {
                if existing.stamp == record.stamp, existing.value != record.value {
                    throw ICloudDriveReplicaError.invalidDocument
                }
                if existing.stamp < record.stamp { merged[key] = record }
            } else {
                merged[key] = record
            }
        }
    }

    private static func ensureDirectory(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw ICloudDriveReplicaError.invalidLocation
            }
        } else {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private static func read(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ])
        guard values.isSymbolicLink != true else {
            throw ICloudDriveReplicaError.invalidLocation
        }
        if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw ICloudDriveReplicaError.pendingDownload
        }
        guard values.isRegularFile == true else { throw ICloudDriveReplicaError.invalidLocation }
        guard (values.fileSize ?? 0) <= self.maximumDocumentBytes else {
            throw ICloudDriveReplicaError.limitExceeded
        }
        var result: Result<Data, any Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result { try Data(contentsOf: coordinated) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ICloudDriveReplicaError.invalidDocument }
        let data = try result.get()
        guard data.count <= self.maximumDocumentBytes else { throw ICloudDriveReplicaError.limitExceeded }
        return data
    }

    private static func write(_ value: some Encodable, to url: URL) throws {
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: url.path) {
            let attributes = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard attributes.isSymbolicLink != true, attributes.isRegularFile == true else {
                throw ICloudDriveReplicaError.invalidLocation
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= self.maximumDocumentBytes else { throw ICloudDriveReplicaError.limitExceeded }
        var result: Result<Void, any Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError)
        { coordinated in
            result = Result {
                try Task.checkCancellation()
                try data.write(to: coordinated, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: coordinated.path)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ICloudDriveReplicaError.invalidDocument }
        try result.get()
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, data: Data) throws -> Value {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int else { throw ICloudDriveReplicaError.invalidDocument }
        guard version == self.version else { throw ICloudDriveReplicaError.unsupportedVersion }
        do { return try JSONDecoder().decode(type, from: data) } catch {
            throw ICloudDriveReplicaError.invalidDocument
        }
    }
}
