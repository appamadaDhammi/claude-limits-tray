import Foundation

public enum UsageError: Error, Equatable {
    /// Токен протух или отозван — Claude Code обновит его при следующем запуске.
    case unauthorized
    case forbidden(String)
    /// Эндпоинт жёстко ограничивает частоту, и квота ОБЩАЯ с Claude Code:
    /// 429 чаще значит «только что спрашивал кто-то другой», а не поломку.
    /// Показанные цифры при этом остаются верными.
    case rateLimited(retryAfter: Double?)
    case http(Int)
    case transport(String)
    case parse(String)
}

/// Единственный сетевой контакт утилиты: один GET на api.anthropic.com.
/// Квоту не тратит — это чтение счётчика, а не обращение к модели.
public struct UsageClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: URLSession

    public init(session: URLSession? = nil) {
        // Своя сессия, а не `.shared`: общий кэш и переиспользуемые соединения
        // после смены сети или пробуждения из сна отдают ошибки на живом
        // интернете. Эфемерная конфигурация ничего не кэширует.
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.timeoutIntervalForRequest = 15
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    public func fetch(token: String) async -> Result<Limits, UsageError> {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        // Достаточно одного заголовка: проверено, anthropic-beta и
        // anthropic-version эндпоинту лимитов не требуются.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.transport("не HTTP-ответ"))
        }
        switch http.statusCode {
        case 200:
            break
        case 401:
            return .failure(.unauthorized)
        case 403:
            let detail = String(data: data, encoding: .utf8) ?? ""
            return .failure(.forbidden(detail.prefix(200).description))
        case 429:
            // Заголовок бывает нулевым — тогда паузу выбирает вызывающий.
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            return .failure(.rateLimited(retryAfter: retryAfter.flatMap { $0 > 0 ? $0 : nil }))
        default:
            return .failure(.http(http.statusCode))
        }

        do {
            return .success(try LimitsParser.parse(data))
        } catch {
            return .failure(.parse(String(describing: error)))
        }
    }
}
