import CryptoKit
import Foundation

#if os(macOS)
import Security

/// Team credentials never enter preferences, iCloud payloads, caches or diagnostic descriptions.
public enum CockpitTeamCredentialStore {
    private static func query(endpoint: String, deviceID: String) -> [String: Any] {
        let digest = SHA256.hash(data: Data(endpoint.utf8)).map { String(format: "%02x", $0) }.joined()
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(CockpitAppIdentity.keychainService).team",
            kSecAttrAccount as String: "\(digest):\(deviceID)",
            kSecAttrSynchronizable as String: false,
        ]
    }

    public static func load(endpoint: String, deviceID: String) throws -> String? {
        guard !KeychainAccessGate.isDisabled else { return nil }
        var query = self.query(endpoint: endpoint, deviceID: deviceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        KeychainNoUIQuery.apply(to: &query)
        var result: CFTypeRef?
        let status = KeychainSecurity.copyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { throw CockpitTeamCredentialError.unavailable }
        return value
    }

    public static func save(_ token: String?, endpoint: String, deviceID: String) throws {
        guard !KeychainAccessGate.isDisabled else { throw CockpitTeamCredentialError.unavailable }
        var query = self.query(endpoint: endpoint, deviceID: deviceID)
        KeychainNoUIQuery.apply(to: &query)
        guard let token else {
            let status = KeychainSecurity.delete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CockpitTeamCredentialError.unavailable
            }
            return
        }
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = KeychainSecurity.update(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = self.query(endpoint: endpoint, deviceID: deviceID)
            item[kSecValueData as String] = Data(token.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard KeychainSecurity.add(item as CFDictionary, nil) == errSecSuccess else {
                throw CockpitTeamCredentialError.unavailable
            }
        } else if status != errSecSuccess {
            throw CockpitTeamCredentialError.unavailable
        }
    }
}

public enum CockpitTeamCredentialError: Error { case unavailable }
#endif
