import Foundation
import Security

struct KeychainStore: Sendable {
    let service = "com.hanshuheng.CodexHistorySync.account"

    func save(_ credentials: AccountCredentials, for id: String) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: id]
        let status = SecItemAdd(query.merging([kSecValueData as String: data]) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard update == errSecSuccess else { throw AccountServiceError.keychain(update) }
        } else if status != errSecSuccess {
            throw AccountServiceError.keychain(status)
        }
    }

    func read(for id: String) throws -> AccountCredentials {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: id,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw AccountServiceError.keychain(status) }
        return try JSONDecoder().decode(AccountCredentials.self, from: data)
    }
}
