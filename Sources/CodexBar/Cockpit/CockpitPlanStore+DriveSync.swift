import CodexBarCore
import CryptoKit
import Foundation

enum CockpitDriveSyncError: Error {
    case invalidRecord
    case tooManyRecords
}

@MainActor
extension CockpitPlanStore {
    /// Only user-authored calendar feedback and personal caps leave this store. Credential-derived
    /// observations, raw account identities and local Token measurements are excluded.
    func driveSyncValues() throws -> [String: Data] {
        try self.requireReadableDriveSyncState()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var values: [String: Data] = [:]
        for cap in self.state.personalCaps where Self.validDriveCap(cap) {
            values[Self.driveCapKey(cap)] = try encoder.encode(cap)
        }
        for record in self.state.comfortRecords {
            let projected = Self.driveComfortProjection(record)
            guard Self.validDriveComfort(projected) else { continue }
            values[Self.driveComfortKey(projected)] = try encoder.encode(projected)
        }
        return values
    }

    /// A known key with no value is an explicit tombstone. Keys outside these two namespaces do not
    /// affect the planner, and a missing remote file cannot clear the local planning state.
    func applyDriveSyncValues(_ values: [String: Data], managedKeys: Set<String>) throws {
        try self.requireReadableDriveSyncState()
        let scopedValues = values.filter { Self.isDrivePlanKey($0.key) }
        guard scopedValues.count <= 6000 else { throw CockpitDriveSyncError.tooManyRecords }
        let decoder = JSONDecoder()
        var incomingCaps: [String: CockpitPersonalCap] = [:]
        var incomingComfort: [String: CockpitComfortRecord] = [:]
        // Validate the complete incoming transaction before changing any records or writing a file.
        for (key, data) in scopedValues {
            guard data.count <= 8192, managedKeys.contains(key) else { throw CockpitDriveSyncError.invalidRecord }
            if key.hasPrefix("plan.cap.") {
                let cap = try decoder.decode(CockpitPersonalCap.self, from: data)
                guard Self.validDriveCap(cap), Self.driveCapKey(cap) == key else {
                    throw CockpitDriveSyncError.invalidRecord
                }
                incomingCaps[key] = cap
            } else {
                let record = try decoder.decode(CockpitComfortRecord.self, from: data)
                guard Self.validDriveComfort(record), Self.driveComfortKey(record) == key else {
                    throw CockpitDriveSyncError.invalidRecord
                }
                incomingComfort[key] = record
            }
        }
        var caps = self.state.personalCaps.filter {
            !Self.validDriveCap($0) || !managedKeys.contains(Self.driveCapKey($0))
        }
        caps.append(contentsOf: incomingCaps.values)
        let previousComfort = Dictionary(
            self.state.comfortRecords.map { (Self.driveComfortKey($0), $0) },
            uniquingKeysWith: { _, last in last })
        var comfort = self.state.comfortRecords.filter {
            !Self.validDriveComfort(Self.driveComfortProjection($0)) ||
                !managedKeys.contains(Self.driveComfortKey($0))
        }
        comfort.append(contentsOf: incomingComfort.map { key, record in
            guard record.accountID == "local-machine", let previous = previousComfort[key] else { return record }
            // The feeling is shared. Measurements still describe this Mac's own local history.
            return CockpitComfortRecord(
                providerID: record.providerID,
                accountID: record.accountID,
                localDateKey: record.localDateKey,
                timeZoneIdentifier: record.timeZoneIdentifier,
                recordedAt: record.recordedAt,
                feeling: record.feeling,
                totalTokens: previous.totalTokens,
                coverage: previous.coverage,
                usedPercent: previous.usedPercent)
        })
        caps.sort { Self.driveCapKey($0) < Self.driveCapKey($1) }
        comfort.sort { Self.driveComfortKey($0) < Self.driveComfortKey($1) }
        guard caps.count <= 6000, comfort.count <= 6000 else { throw CockpitDriveSyncError.tooManyRecords }
        var merged = self.state
        merged.replacePersonalSyncRecords(personalCaps: caps, comfortRecords: comfort)
        guard merged != self.state else { return }
        try self.persistDriveSyncState(merged)
    }

    private static func isDrivePlanKey(_ key: String) -> Bool {
        key.hasPrefix("plan.cap.") || key.hasPrefix("plan.comfort.")
    }

    private static func driveCapKey(_ cap: CockpitPersonalCap) -> String {
        let identity = [cap.providerID, cap.accountID, cap.timeZoneIdentifier, cap.localDateKey]
        return "plan.cap." + self.driveDigest(identity.joined(separator: "|"))
    }

    private static func driveComfortKey(_ record: CockpitComfortRecord) -> String {
        "plan.comfort." + self.driveDigest(record.id)
    }

    private static func driveDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func driveComfortProjection(_ record: CockpitComfortRecord) -> CockpitComfortRecord {
        let used = record.accountID == "local-machine" ? nil : record.usedPercent
        return CockpitComfortRecord(
            providerID: record.providerID,
            accountID: record.accountID,
            localDateKey: record.localDateKey,
            timeZoneIdentifier: record.timeZoneIdentifier,
            recordedAt: record.recordedAt,
            feeling: record.feeling,
            totalTokens: nil,
            coverage: used == nil ? .unavailable : record.coverage,
            usedPercent: used)
    }

    private static func validDriveCap(_ cap: CockpitPersonalCap) -> Bool {
        self.validDriveScope(
            providerID: cap.providerID,
            accountID: cap.accountID,
            day: cap.localDateKey,
            zone: cap.timeZoneIdentifier,
            permitsLocal: false)
            && cap.percent.isFinite && (0...100).contains(cap.percent)
    }

    private static func validDriveComfort(_ record: CockpitComfortRecord) -> Bool {
        guard self.validDriveScope(
            providerID: record.providerID,
            accountID: record.accountID,
            day: record.localDateKey,
            zone: record.timeZoneIdentifier,
            permitsLocal: true),
            record.recordedAt.timeIntervalSince1970.isFinite,
            record.totalTokens == nil else { return false }
        if record.accountID == "local-machine" {
            return record.usedPercent == nil && record.coverage == .unavailable
        }
        if let used = record.usedPercent {
            return used.isFinite && (0...10000).contains(used) && record.coverage != .unavailable
        }
        return record.coverage == .unavailable
    }

    private static func validDriveScope(
        providerID: String,
        accountID: String,
        day: String,
        zone: String,
        permitsLocal: Bool) -> Bool
    {
        guard UsageProvider(rawValue: providerID) != nil,
              TimeZone(identifier: zone) != nil, self.validDriveDay(day) else { return false }
        if permitsLocal, accountID == "local-machine" { return true }
        return accountID.utf8.count == 64 && accountID.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func validDriveDay(_ day: String) -> Bool {
        guard day.utf8.count == 10 else { return false }
        let pieces = day.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              pieces.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(pieces[0]), (1900...2200).contains(year),
              let month = Int(pieces[1]), let dayOfMonth = Int(pieces[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        guard let date = calendar.date(from: components) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == year && actual.month == month && actual.day == dayOfMonth
    }
}
