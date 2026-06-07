import Foundation
import Security

public protocol APIKeyVault {
    func save(_ key: String) throws
    func load() throws -> String?
    func clear() throws
}

public final class KeychainAPIKeyVault: APIKeyVault {
    public enum Error: Swift.Error, Equatable {
        case unhandledStatus(OSStatus)
    }

    private let service: String
    private let account: String

    public init(service: String = "TodoSticky.OpenAI", account: String = "api-key") {
        self.service = service
        self.account = account
    }

    public func save(_ key: String) throws {
        try clear()
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Error.unhandledStatus(status)
        }
    }

    public func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw Error.unhandledStatus(status)
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.unhandledStatus(status)
        }
    }
}

public final class InMemoryAPIKeyVault: APIKeyVault {
    private var value: String?

    public init() {}

    public func save(_ key: String) throws {
        value = key
    }

    public func load() throws -> String? {
        value
    }

    public func clear() throws {
        value = nil
    }
}
