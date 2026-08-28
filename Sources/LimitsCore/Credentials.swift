import Foundation
import Security

/// Токен Claude Code, прочитанный из Keychain. Значение живёт только в памяти:
/// ни на диск, ни в UserDefaults, ни в лог оно не попадает.
public struct Credentials: Equatable {
    public let accessToken: String
    public let subscriptionType: String?
    public let expiresAt: Date?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

public enum CredentialsError: Error, Equatable {
    /// Записи в Keychain нет, или пользователь не дал к ней доступ.
    case notAvailable
    /// Запись есть, но основного токена в ней нет — известный формат
    /// некоторых установок Claude Code 2.1.x (там только mcpOAuth).
    case noClaudeToken
    /// Запись есть, но это не тот JSON, которого мы ждём.
    case malformed
}

public enum KeychainReader {
    public static let service = "Claude Code-credentials"

    /// Читает запись Keychain. Только чтение: функций записи в этом типе нет
    /// и появиться не должно — это гарантия, а не обещание.
    public static func read() -> Result<Credentials, CredentialsError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return .failure(.notAvailable)
        }
        return parse(data)
    }

    /// Вынесено отдельно, чтобы разбор проверялся тестами без Keychain.
    public static func parse(_ data: Data) -> Result<Credentials, CredentialsError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.malformed)
        }
        // Обычная форма — вложенный claudeAiOauth; редкая — те же поля в корне.
        let holder = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = holder["accessToken"] as? String, !token.isEmpty else {
            return .failure(.noClaudeToken)
        }
        let expiresAt = (holder["expiresAt"] as? Double).map {
            Date(timeIntervalSince1970: $0 / 1000)  // Claude Code хранит миллисекунды
        }
        return .success(Credentials(
            accessToken: token,
            subscriptionType: holder["subscriptionType"] as? String,
            expiresAt: expiresAt
        ))
    }
}
