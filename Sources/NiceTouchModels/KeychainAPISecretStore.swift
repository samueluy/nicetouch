import Foundation
import Security
import LocalAuthentication

public final class KeychainAPISecretStore: APISecretStore, @unchecked Sendable {
    private let service: String
    public init(service: String = "org.nicetouch.model-api") { self.service = service }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    public func secret(account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw RuleModelError.invalidConfiguration("Could not read this endpoint's API key from Keychain. Unlock your Mac or save the key again.")
        }
        return value
    }
    public func setSecret(_ value: String, account: String) throws {
        guard !value.isEmpty else { throw RuleModelError.invalidConfiguration("Enter an API key.") }
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw RuleModelError.invalidConfiguration("Could not update the API key in Keychain.") }
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw RuleModelError.invalidConfiguration("Could not save the API key in Keychain.") }
    }
    public func deleteSecret(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RuleModelError.invalidConfiguration("Could not remove the API key from Keychain.") }
    }
}
