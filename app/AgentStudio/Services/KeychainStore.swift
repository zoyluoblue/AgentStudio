import Foundation
import Security

/// Stores BYO API keys in the macOS Keychain (generic password items) so secrets
/// never land in the plaintext settings.json. Keyed per lane (left / right connect independently).
enum KeychainStore {
    private static let service = "com.example.agentstudio"

    private static func account(_ lane: Lane) -> String { "apiKey.lane.\(lane.rawValue)" }

    static func get(_ lane: Lane) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(lane),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    static func set(_ value: String, for lane: Lane) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(lane),
        ]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            SecItemDelete(base as CFDictionary)
            return
        }
        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func loadKeys() -> PerLane<String> {
        PerLane(master: get(.master), slave: get(.slave))
    }

    static func saveKeys(_ keys: PerLane<String>) {
        set(keys.master, for: .master)
        set(keys.slave, for: .slave)
    }
}
