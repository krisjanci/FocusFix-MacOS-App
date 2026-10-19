import Foundation
import Security

// The ID survives relaunches and ordinary app updates. No name, email or hardware ID.
enum SharingIdentity {
    private static let service = "org.focusfix.research-sharing"

    static func read(_ account: String) throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw SharingError.message("Couldn't read the research identity from Keychain. Local recording still works.")
        }
        return value
    }

    static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw SharingError.message("Couldn't save the research identity in Keychain.")
            }
        } else if status != errSecSuccess {
            throw SharingError.message("Couldn't update the research identity in Keychain.")
        }
    }

    static func participantID() throws -> String {
        if let value = try read("participant-id") {
            guard UUID(uuidString: value) != nil else {
                throw SharingError.message("The saved participant ID is invalid. Contact the researcher before sharing.")
            }
            return value
        }
        let value = UUID().uuidString.lowercased()
        try save(value, account: "participant-id")
        return value
    }
}
