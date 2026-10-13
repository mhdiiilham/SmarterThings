import Foundation
import Security

/// Stores a token as a generic password in the login Keychain.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.mo.TVRemote", account: String = "smartthings-token") {
        self.service = service
        self.account = account
    }

    public func token() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) throws {
        try clear()
        var item = baseQuery
        item[kSecValueData as String] = Data(token.utf8)
        try check(SecItemAdd(item as CFDictionary, nil))
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
