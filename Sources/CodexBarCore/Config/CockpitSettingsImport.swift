import Foundation

/// A read-only projection prepared after the user chooses to import CodexBar settings. Applying it
/// copies presentation and first-party provider order/visibility, never login material or access consent.
public struct CockpitSettingsImport: Sendable {
    public let preferences: PreferencesDocument
    public let appLanguage: String?
    public let providerSelection: [ProviderConfig]

    public var importedSettingCount: Int {
        self.preferences.settingCount + self.providerSelection.count + (self.appLanguage == nil ? 0 : 1)
    }

    public init(upstreamPreferences: [String: Any], upstreamConfigData: Data? = nil) throws {
        self.preferences = try PreferencesDocument(persistentDomain: upstreamPreferences)
        if let language = upstreamPreferences["appLanguage"] as? String,
           language.count <= 35,
           language.unicodeScalars
               .allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) })
        {
            self.appLanguage = language
        } else {
            self.appLanguage = nil
        }
        if let upstreamConfigData {
            let config = try CodexBarConfig.decode(from: upstreamConfigData)
            self.providerSelection = config.providers.compactMap { provider in
                guard provider.id.firstPartyProvider != nil else { return nil }
                return ProviderConfig(id: provider.id, enabled: provider.enabled)
            }
        } else {
            self.providerSelection = []
        }
    }

    /// Keeps all settings already configured in the fork; only imported order and enabled flags win.
    public func applyingProviderSelection(to current: CodexBarConfig) -> CodexBarConfig {
        guard !self.providerSelection.isEmpty else { return current }
        var result = current
        var included = Set<ProviderInstanceID>()
        var providers: [ProviderConfig] = []
        for selection in self.providerSelection where included.insert(selection.id).inserted {
            var provider = current.providerConfig(for: selection.id) ?? ProviderConfig(id: selection.id)
            provider.enabled = selection.enabled
            providers.append(provider)
        }
        providers.append(contentsOf: current.providers.filter { included.insert($0.id).inserted })
        result.providers = providers
        return result
    }
}
