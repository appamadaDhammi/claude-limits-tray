import Foundation

/// Журнал отказов. Нужен ровно для одного: когда панель говорит «не смогла»,
/// должно быть место, где написано ЧТО именно не смогла — иначе диагноз
/// подменяется догадкой.
///
/// Токен в журнал не попадает никогда: пишутся только вид отказа, код ответа
/// и время. Файл держится маленьким (последние 200 строк).
public enum Diagnostics {
    public static let path = NSHomeDirectory() + "/Library/Logs/ClaudeLimits.log"

    private static let queue = DispatchQueue(label: "claude-limits.log")
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    public static func log(_ message: String) {
        let line = "[\(stamp.string(from: Date()))] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
            }
            trim()
        }
    }

    private static func trim() {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 200 else { return }
        let tail = lines.suffix(200).joined(separator: "\n")
        try? tail.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

public extension UsageError {
    /// Короткое человеческое имя отказа для строки состояния.
    var shortReason: String {
        switch self {
        case .unauthorized: return "токен не принят"
        case .forbidden: return "нет прав"
        case .rateLimited: return "сервер просит подождать"
        case .http(let code): return "сервер ответил \(code)"
        case .transport: return "нет сети"
        case .parse: return "ответ не разобран"
        }
    }

    /// Подробность для журнала.
    var logDetail: String {
        switch self {
        case .unauthorized: return "401 unauthorized"
        case .forbidden(let text): return "403 forbidden: \(text)"
        case .rateLimited(let after):
            return "429 rate limited (retry-after: \(after.map { "\($0)с" } ?? "не указан"))"
        case .http(let code): return "HTTP \(code)"
        case .transport(let text): return "transport: \(text)"
        case .parse(let text): return "parse: \(text)"
        }
    }
}
