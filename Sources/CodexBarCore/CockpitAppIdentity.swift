import Foundation

/// The fork owns its settings, cached credentials and derived data. Provider-owned login files and
/// session logs keep their original locations; they are inputs rather than application storage.
public enum CockpitAppIdentity {
    public static let displayName = "CodexBar Cockpit"
    public static let bundleIdentifier = "io.github.kakapoo233.codexbar-cockpit"
    public static let debugBundleIdentifier = "\(CockpitAppIdentity.bundleIdentifier).debug"
    public static let storageDirectoryName = "CodexBar Cockpit"
    public static let configDirectoryName = "codexbar-cockpit"
    public static let configPathDisplay = "~/.config/codexbar-cockpit/config.json"
    public static let legacyConfigDirectoryName = ".codexbar-cockpit"
    public static let keychainService = "\(CockpitAppIdentity.bundleIdentifier).credentials"
    public static let keychainCacheService = "\(CockpitAppIdentity.bundleIdentifier).cache"
    public static let upstreamDefaultsDomain = "com.steipete.codexbar"

    public static func configDirectory(home: URL) -> URL {
        home.appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent(self.configDirectoryName, isDirectory: true)
    }

    public static func applicationSupportDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(self.storageDirectoryName, isDirectory: true)
    }

    public static func cacheDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(self.storageDirectoryName, isDirectory: true)
    }
}
