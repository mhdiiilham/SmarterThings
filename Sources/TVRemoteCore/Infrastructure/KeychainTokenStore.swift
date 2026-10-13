import Foundation
import Security

/// Stores the SmartThings token as a generic password in the login Keychain.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "smartthings-token"

    public init(service: String = "com.mo.TVRemote") {
        self.service = service
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
