import Foundation

/// Keep status-item text independent from the language of menus and settings.
enum MenuBarTextLanguage {
    static func withEnglish<Result>(enabled: Bool, operation: () throws -> Result) rethrows -> Result {
        guard enabled else { return try operation() }
        return try CodexBarLocalizationOverride.$appLanguage.withValue("en", operation: operation)
    }
}
