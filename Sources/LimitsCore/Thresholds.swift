import Foundation

public struct Alert: Equatable {
    public enum Kind: Equatable {
        case threshold(Int)   // пересечён порог: 80 или 95
        case sessionReset     // часовое окно обнулилось
    }
    public let kind: Kind
    public let limitName: String
    public let percent: Int
}

/// Решает, о чём уведомлять. Держит состояние между опросами:
/// каждый порог срабатывает один раз на окно, окно опознаётся по resetsAt.
public struct ThresholdTracker {
    public static let thresholds = [80, 95]

    /// Ключ — имя лимита; значение — окно и уже сработавшие в нём пороги.
    private var fired: [String: (window: Date?, levels: Set<Int>)] = [:]
    private var lastSessionWindow: Date??

    public init() {}

    public mutating func check(_ limits: Limits) -> [Alert] {
        var alerts: [Alert] = []

        let named: [(String, Limit?)] = [
            ("Сессия · 5ч", limits.session),
            ("Неделя · всё", limits.weeklyAll),
            ("Неделя · Fable", limits.weeklyFable),
        ]

        for (name, limit) in named {
            guard let limit else { continue }
            var state = fired[name] ?? (window: limit.resetsAt, levels: [])
            // Окно сменилось — прошлые срабатывания больше не в счёт.
            if state.window != limit.resetsAt {
                state = (window: limit.resetsAt, levels: [])
            }
            for level in Self.thresholds where limit.percent >= level && !state.levels.contains(level) {
                state.levels.insert(level)
                alerts.append(Alert(kind: .threshold(level), limitName: name, percent: limit.percent))
            }
            fired[name] = state
        }

        // Обнуление часового окна: resetsAt сдвинулся вперёд, а расход упал.
        if let session = limits.session {
            if let previous = lastSessionWindow, let prev = previous,
               let current = session.resetsAt, current > prev, session.percent < 50 {
                alerts.append(Alert(kind: .sessionReset, limitName: "Сессия · 5ч",
                                    percent: session.percent))
            }
            lastSessionWindow = .some(session.resetsAt)
        }

        return alerts
    }
}

public extension Alert {
    var title: String {
        switch kind {
        case .threshold(let level): return level >= 95 ? "Лимит почти исчерпан" : "Приближаешься к лимиту"
        case .sessionReset: return "Часовой лимит обнулился"
        }
    }

    var body: String {
        switch kind {
        case .threshold: return "\(limitName) — \(percent)%"
        case .sessionReset: return "Можно работать дальше"
        }
    }
}
