import Foundation

/// Один лимит: сколько израсходовано и когда окно обнулится.
public struct Limit: Equatable {
    public let percent: Int
    public let resetsAt: Date?

    public init(percent: Int, resetsAt: Date?) {
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

/// Три лимита, которые показывает утилита. `nil` означает «строки нет в ответе»,
/// что не то же самое, что ноль процентов, и рисуется иначе.
public struct Limits: Equatable {
    public let session: Limit?
    public let weeklyAll: Limit?
    public let weeklyFable: Limit?

    public init(session: Limit?, weeklyAll: Limit?, weeklyFable: Limit?) {
        self.session = session
        self.weeklyAll = weeklyAll
        self.weeklyFable = weeklyFable
    }

    /// Худший из известных лимитов — для цвета и порогов уведомлений.
    public var worstPercent: Int {
        [session, weeklyAll, weeklyFable].compactMap { $0?.percent }.max() ?? 0
    }
}

public enum LimitsParseError: Error, Equatable {
    case notJSON
    case noLimitsArray
}

public enum LimitsParser {
    /// Модель, чей недельный лимит показываем отдельной строкой.
    /// Сверяем по display_name: позиция строки в ответе не гарантирована.
    public static let scopedModelName = "Fable"

    private struct Response: Decodable {
        struct Row: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let display_name: String? }
                let model: Model?
            }
            let kind: String
            let percent: Double
            let resets_at: String?
            let scope: Scope?
        }
        let limits: [Row]?
    }

    public static func parse(_ data: Data) throws -> Limits {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw LimitsParseError.notJSON
        }
        guard let rows = decoded.limits else { throw LimitsParseError.noLimitsArray }

        var session: Limit?
        var weeklyAll: Limit?
        var weeklyFable: Limit?

        for row in rows {
            let limit = Limit(percent: Int(row.percent.rounded()), resetsAt: parseDate(row.resets_at))
            switch row.kind {
            case "session":
                session = limit
            case "weekly_all":
                weeklyAll = limit
            case "weekly_scoped":
                if row.scope?.model?.display_name == scopedModelName { weeklyFable = limit }
            default:
                continue  // состав строк может меняться — незнакомые игнорируем молча
            }
        }
        return Limits(session: session, weeklyAll: weeklyAll, weeklyFable: weeklyFable)
    }

    /// resets_at приходит как ISO 8601 в UTC, обычно с дробными секундами,
    /// но полагаться на их наличие нельзя — пробуем оба формата.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
