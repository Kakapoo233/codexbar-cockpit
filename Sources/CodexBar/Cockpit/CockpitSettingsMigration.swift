import CodexBarCore
import Foundation

@MainActor
enum CockpitSettingsMigration {
    enum ImportError: LocalizedError {
        case noSettings
        case fileTooLarge

        var errorDescription: String? {
            switch self {
            case .noSettings: L("cockpit_ui_import_missing")
            case .fileTooLarge: L("cockpit_ui_import_too_large")
            }
        }
    }

    /// Called only by the explicit import button. Credentials and cloud identity never cross this seam.
    static func importFromInstalledCodexBar(into settings: SettingsStore) throws -> Int {
        let defaults = UserDefaults.standard.persistentDomain(forName: CockpitAppIdentity.upstreamDefaultsDomain) ?? [:]
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [".config/codexbar/config.json", ".codexbar/config.json"].map {
            home.appendingPathComponent($0)
        }
        let configURL = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
        var data: Data?
        if let configURL {
            let size = try configURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 4 * 1024 * 1024 else { throw ImportError.fileTooLarge }
            data = try Data(contentsOf: configURL)
        }
        guard !defaults.isEmpty || data != nil else { throw ImportError.noSettings }
        let imported = try CockpitSettingsImport(upstreamPreferences: defaults, upstreamConfigData: data)
        try imported.preferences.validate()
        let backupDirectory = CockpitAppIdentity.applicationSupportDirectory(home: home)
            .appendingPathComponent("setting-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backup = backupDirectory.appendingPathComponent("before-import-\(UUID().uuidString).json")
        try settings.exportPreferences().encoded().write(to: backup, options: .atomic)
        try settings.importPreferences(imported.preferences)
        if let language = imported.appLanguage { settings.appLanguage = language }
        settings.updateConfig(reason: "cockpit-settings-import", affectsBackgroundWork: true) { config in
            config = imported.applyingProviderSelection(to: config)
        }
        return imported.importedSettingCount
    }
}
