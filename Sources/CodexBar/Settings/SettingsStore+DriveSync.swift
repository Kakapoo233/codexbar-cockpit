import CodexBarCore
import Foundation

/// The Drive format projects typed presentation settings, never the defaults or provider config domains.
extension SettingsStore {
    func driveSyncSettingsValues() throws -> [String: Data] {
        let encoder = Self.driveSettingsEncoder()
        var preferences = try JSONDecoder().decode(
            [String: DriveSettingValue].self,
            from: encoder.encode(self.syncedPreferences))
        if self.syncedPreferences.weeklyProgressWorkDays == nil {
            preferences["weeklyProgressWorkDays"] = .null
        }
        var values: [String: Data] = [:]
        for key in DriveSettingsProjection.preferenceKeys {
            guard let value = preferences[key] else { continue }
            values[DriveSettingsProjection.preferencePrefix + key] = try encoder.encode(value)
        }
        values["settings.appLanguage"] = try encoder.encode(self.appLanguage)
        values["settings.menuBarEnglishText"] = try encoder.encode(self.menuBarEnglishText)
        values["settings.menuBarLayout"] = try encoder.encode(DriveMenuBarLayout(settings: self))
        try self.validateDriveSyncSettingsValues(values)
        return values
    }

    func validateDriveSyncSettingsValues(_ values: [String: Data]) throws {
        _ = try self.prepareDriveSyncSettingsValues(values)
    }

    func applyDriveSyncSettingsValues(_ values: [String: Data]) throws {
        // Validate every known field before the first normal setter can persist a change.
        let prepared = try self.prepareDriveSyncSettingsValues(values)
        let current = try self.driveSyncSettingsValues()
        guard values.contains(where: { key, value in
            let knownPreference = key.hasPrefix(DriveSettingsProjection.preferencePrefix)
                && DriveSettingsProjection.preferenceKeys.contains(
                    String(key.dropFirst(DriveSettingsProjection.preferencePrefix.count)))
            return (current[key] != nil || knownPreference) && current[key] != value
        }) else { return }
        let consent = self.adaptiveActivityScanConsent
        self.applySyncedPreferences(prepared.preferences)
        if self.adaptiveActivityScanConsent != consent { self.adaptiveActivityScanConsent = consent }
        if let language = prepared.language, language != self.appLanguage { self.appLanguage = language }
        if let english = prepared.english { self.menuBarEnglishText = english }
        if let layout = prepared.layout {
            self.menuBarLayoutConditionals = layout.conditionals
            self.menuBarLayout = layout.global
            for key in self.defaultsState.menuBarLayoutOverridesRaw.keys where layout.overrides[key] == nil {
                if let instance = ProviderInstanceID(rawValue: key) {
                    self.removeMenuBarLayoutOverride(forInstanceID: instance)
                }
            }
            for (key, value) in layout.overrides {
                if let instance = ProviderInstanceID(rawValue: key) {
                    self.setMenuBarLayout(value, forInstanceID: instance)
                }
            }
            self.menuBarLayoutSize = MenuBarLayoutSize(rawValue: layout.size) ?? .regular
            self.menuBarLayoutGap = MenuBarLayoutGap(rawValue: layout.gap) ?? .regular
            self.menuBarLayoutMonospacedDigits = layout.monospacedDigits
            self.menuBarLayoutShowWindowLabels = layout.showWindowLabels
            self.menuBarLayoutVerticalAdjustment = layout.verticalAdjustment
        }
    }

    private func prepareDriveSyncSettingsValues(_ values: [String: Data]) throws -> PreparedDriveSettings {
        var document = PreferencesDocument()
        for key in DriveSettingsProjection.preferenceKeys {
            guard let data = values[DriveSettingsProjection.preferencePrefix + key] else { continue }
            try Self.validateDriveSettingsSize(data)
            let value = try JSONDecoder().decode(DriveSettingValue.self, from: data)
            try document.set(key, value)
        }
        try document.validate()
        let preferences = try document.applying(to: self.syncedPreferences)
        var prepared = PreparedDriveSettings(preferences: preferences)
        if let data = values["settings.appLanguage"] {
            try Self.validateDriveSettingsSize(data)
            let language = try JSONDecoder().decode(String.self, from: data)
            guard AppLanguage(rawValue: language) != nil else { throw DriveSettingsError.invalidValue }
            prepared.language = language
        }
        if let data = values["settings.menuBarEnglishText"] {
            try Self.validateDriveSettingsSize(data)
            prepared.english = try JSONDecoder().decode(Bool.self, from: data)
        }
        if let data = values["settings.menuBarLayout"] {
            try Self.validateDriveSettingsSize(data)
            let layout = try JSONDecoder().decode(DriveMenuBarLayout.self, from: data)
            try layout.validate()
            prepared.layout = layout
        }
        return prepared
    }

    private static func validateDriveSettingsSize(_ data: Data) throws {
        guard data.count <= 256 * 1024 else { throw DriveSettingsError.oversizedValue }
    }

    private static func driveSettingsEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private enum DriveSettingsProjection {
    static let preferencePrefix = "settings.preferences."
    /// This stays explicit if SyncedPreferences later grows a credential, permission or machine-local field.
    static let preferenceKeys: Set<String> = [
        "statusChecksEnabled", "sessionQuotaNotificationsEnabled", "quotaWarningNotificationsEnabled",
        "predictivePaceWarningNotificationsEnabled", "quotaWarningThresholds", "quotaWarningSessionThresholds",
        "quotaWarningWeeklyThresholds", "quotaWarningSessionEnabled", "quotaWarningWeeklyEnabled",
        "quotaWarningSoundEnabled", "quotaWarningOnScreenAlertEnabled", "quotaWarningMarkersVisible",
        "paceVisible", "weeklyProgressWorkDays", "workdayTickAppearance", "usageBarsShowUsed",
        "resetTimesShowAbsolute", "costUsageEnabled", "costComparisonPeriodsEnabled", "costSummaryDisplayStyle",
        "hidePersonalInfo", "randomBlinkEnabled", "confettiOnSessionLimitResetsEnabled",
        "confettiOnWeeklyLimitResetsEnabled", "menuBarShowsHighestUsage", "unifiedIconSource",
        "showOptionalCreditsAndExtraUsage", "providerChangelogLinksEnabled", "preferredCurrencyCode",
        "providersSortedAlphabetically", "refreshFrequency", "refreshAllProvidersOnMenuOpen",
    ]
}

private enum DriveSettingsError: Error {
    case invalidValue
    case oversizedValue
}

/// Only scalar preferences and their arrays belong to the Drive allowlist.
private enum DriveSettingValue: Codable {
    case null
    case bool(Bool)
    case integer(Int)
    case string(String)
    case array([DriveSettingValue])

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let bool = try? value.decode(Bool.self) {
            self = .bool(bool)
        } else if let integer = try? value.decode(Int.self) {
            self = .integer(integer)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else {
            self = try .array(value.decode([DriveSettingValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case let .bool(bool): try value.encode(bool)
        case let .integer(integer): try value.encode(integer)
        case let .string(string): try value.encode(string)
        case let .array(array): try value.encode(array)
        }
    }
}

private struct PreparedDriveSettings {
    var preferences: SyncedPreferences
    var language: String?
    var english: Bool?
    var layout: DriveMenuBarLayout?
}

/// Layout and its referenced rule library travel in one register, including provider-specific layouts.
private struct DriveMenuBarLayout: Codable {
    let global: MenuBarLayout
    let overrides: [String: MenuBarLayout]
    let conditionals: [MenuBarLayoutConditional]
    let size: String
    let gap: String
    let monospacedDigits: Bool
    let showWindowLabels: Bool
    let verticalAdjustment: Int

    @MainActor
    init(settings: SettingsStore) {
        self.global = settings.menuBarLayout
        self.overrides = settings.defaultsState.menuBarLayoutOverridesRaw
        self.conditionals = settings.menuBarLayoutConditionals
        self.size = settings.menuBarLayoutSize.rawValue
        self.gap = settings.menuBarLayoutGap.rawValue
        self.monospacedDigits = settings.menuBarLayoutMonospacedDigits
        self.showWindowLabels = settings.menuBarLayoutShowWindowLabels
        self.verticalAdjustment = settings.menuBarLayoutVerticalAdjustment
    }

    func validate() throws {
        guard self.overrides.count <= 256, self.conditionals.count <= 256,
              self.overrides.keys.allSatisfy({ ProviderInstanceID(rawValue: $0) != nil }),
              MenuBarLayoutSize(rawValue: self.size) != nil,
              MenuBarLayoutGap(rawValue: self.gap) != nil,
              (-20...20).contains(self.verticalAdjustment),
              Set(self.conditionals.map(\.id)).count == self.conditionals.count
        else { throw DriveSettingsError.invalidValue }
        let libraryIDs = Set(self.conditionals.map(\.id))
        let tokens = ([self.global] + Array(self.overrides.values)).flatMap { $0.lines.flatMap(\.self) }
            + self.conditionals.flatMap { [$0.thenToken, $0.elseToken] }
        guard tokens.count <= 4096, tokens.allSatisfy({ token in
            if case let .conditional(id) = token { return libraryIDs.contains(id) }
            return true
        }) else { throw DriveSettingsError.invalidValue }
    }
}
