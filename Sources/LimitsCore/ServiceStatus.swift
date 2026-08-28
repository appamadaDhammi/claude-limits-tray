import Foundation

/// Состояние одного сервиса на странице status.claude.com.
public struct ServiceComponent: Equatable {
    public let name: String
    public let status: String   // operational, degraded_performance, partial_outage, ...

    public var isOperational: Bool { status == "operational" }

    /// Человеческое имя состояния.
    public var label: String {
        switch status {
        case "operational": return "работает"
        case "degraded_performance": return "замедлен"
        case "partial_outage": return "частичный сбой"
        case "major_outage": return "недоступен"
        case "under_maintenance": return "техработы"
        default: return status
        }
    }
}

/// Активный инцидент: то, что должно попасть в раскрывающееся окно.
public struct Incident: Equatable {
    public let name: String
    public let impact: String     // none, minor, major, critical
    public let status: String     // investigating, identified, monitoring, ...
    public let latestUpdate: String?
    public let updatedAt: Date?

    public var statusLabel: String {
        switch status {
        case "investigating": return "разбираются"
        case "identified": return "причина найдена"
        case "monitoring": return "наблюдают"
        case "resolved": return "закрыт"
        case "postmortem": return "разбор"
        default: return status
        }
    }
}

public struct ServiceStatus: Equatable {
    /// none | minor | major | critical
    public let indicator: String
    public let summary: String
    public let components: [ServiceComponent]
    public let incidents: [Incident]

    public var claudeCode: ServiceComponent? {
        components.first { $0.name == "Claude Code" }
    }

    public var api: ServiceComponent? {
        components.first { $0.name.contains("Claude API") }
    }

    /// Есть ли вообще о чём говорить: неработающий компонент или живой инцидент.
    public var hasTrouble: Bool {
        !incidents.isEmpty || components.contains { !$0.isOperational }
    }
}

public enum StatusParser {
    private struct Response: Decodable {
        struct Status: Decodable { let indicator: String?; let description: String? }
        struct Component: Decodable {
            let name: String
            let status: String
            let group: Bool?
        }
        struct Incident: Decodable {
            struct Update: Decodable { let body: String?; let created_at: String? }
            let name: String
            let impact: String?
            let status: String?
            let incident_updates: [Update]?
        }
        let status: Status?
        let components: [Component]?
        let incidents: [Incident]?
    }

    public static func parse(_ data: Data) throws -> ServiceStatus {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw LimitsParseError.notJSON
        }

        // Группы — это заголовки разделов, а не сервисы; в список не берём.
        let components = (decoded.components ?? [])
            .filter { $0.group != true }
            .map { ServiceComponent(name: $0.name, status: $0.status) }

        let incidents = (decoded.incidents ?? []).map { raw -> Incident in
            let latest = raw.incident_updates?.first
            return Incident(
                name: raw.name,
                impact: raw.impact ?? "none",
                status: raw.status ?? "",
                latestUpdate: latest?.body,
                updatedAt: LimitsParser.parseDate(latest?.created_at)
            )
        }

        return ServiceStatus(
            indicator: decoded.status?.indicator ?? "none",
            summary: decoded.status?.description ?? "",
            components: components,
            incidents: incidents
        )
    }
}

/// Читает публичную страницу состояния. Без авторизации: адрес открытый,
/// токен сюда не отправляется никогда.
public struct StatusClient {
    public static let endpoint = URL(string: "https://status.claude.com/api/v2/summary.json")!

    private let session: URLSession

    public init(session: URLSession? = nil) {
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

    /// Словарь отказов общий с UsageClient; здесь применимы только
    /// transport / http / parse — авторизации у этого адреса нет.
    public func fetch() async -> Result<ServiceStatus, UsageError> {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

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
        guard http.statusCode == 200 else {
            return .failure(.http(http.statusCode))
        }
        do {
            return .success(try StatusParser.parse(data))
        } catch {
            return .failure(.parse(String(describing: error)))
        }
    }
}
