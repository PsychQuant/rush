import Foundation
import Security

enum AuthError: Error, LocalizedError {
    case itemNotFound
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "TDX credentials missing. Run: CheTransportMCP --setup"
        case .keychainError(let status):
            return "Keychain error (OSStatus \(status))"
        }
    }
}

enum Auth {
    static let defaultService = "che-transport-tdx"

    static func save(service: String = defaultService, account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw AuthError.keychainError(status) }
    }

    static func read(service: String = defaultService, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw AuthError.itemNotFound }
            throw AuthError.keychainError(status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw AuthError.itemNotFound
        }
        return value
    }

    static func delete(service: String = defaultService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.keychainError(status)
        }
    }
}
