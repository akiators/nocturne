import Foundation
import Security

/// Тонкая обёртка Keychain для токенов провайдеров и секретов пользователя.
enum KeychainStore {
    static let service = "app.nocturne.music"

    static func setData(_ data: Data, account: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw NSError(domain: "Keychain", code: Int(updateStatus))
            }
        } else {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: "Keychain", code: Int(addStatus))
            }
        }
    }

    static func data(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func setString(_ value: String?, account: String) throws {
        if let value {
            try setData(Data(value.utf8), account: account)
        } else {
            delete(account: account)
        }
    }

    static func string(account: String) -> String? {
        guard let data = data(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
