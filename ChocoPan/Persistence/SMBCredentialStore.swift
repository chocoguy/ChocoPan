import Foundation
import Security

nonisolated enum SMBCredentialError: Error, CustomStringConvertible {
    case saveFailed(OSStatus)

    var description: String {
        switch self {
        case .saveFailed(let status): "keychain write failed (\(status))"
        }
    }
}

/// Keychain storage for SMB share passwords, keyed by `LibrarySource.keychainAccount`.
///
/// A missing password means "ask the user again", never "the install is broken" — tvOS makes
/// weaker persistence guarantees than iOS and there is no iCloud Keychain to fall back on.
nonisolated enum SMBCredentialStore {
    private static let service = "net.vanillacoffeesoft.ChocoPan.smb"

    static func save(password: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            throw SMBCredentialError.saveFailed(updateStatus)
        }

        let addStatus = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SMBCredentialError.saveFailed(addStatus)
        }
    }

    static func password(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
