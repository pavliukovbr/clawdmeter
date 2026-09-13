import Foundation
import Security

/// Pairing details and the last reply, kept in the keychain group the app shares with its
/// widgets. Nothing here leaves the phone.
enum PhoneVault {
    struct StoredReply: Codable, Equatable {
        var reply: PhoneLinkReply
        var receivedAt: Date
        var host: String

        var viaTailscale: Bool {
            let octets = host.split(separator: ".").compactMap { Int($0) }
            return octets.count == 4 && octets[0] == 100 && (64...127).contains(octets[1])
        }
    }

    static var pairing: PhonePairing? {
        get { read("pairing") }
        set { write(newValue, account: "pairing") }
    }

    static var lastReply: StoredReply? {
        get { read("reply") }
        set { write(newValue, account: "reply") }
    }

    private static let service = "Clawdmeter"

    private static func read<Value: Decodable>(_ account: String) -> Value? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? PhoneLink.decoder.decode(Value.self, from: data)
    }

    private static func write<Value: Encodable>(_ value: Value?, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = try? PhoneLink.encoder.encode(value) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
