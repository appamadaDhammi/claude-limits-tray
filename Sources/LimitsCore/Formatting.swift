import Foundation

public enum Formatting {
    /// «в 04:30» для сегодня/ближайших часов, «в ср 01:00» для другого дня.
    /// Календарь и зона передаются явно, чтобы тесты не зависели от машины.
    public static func resetTime(
        _ date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ru_RU")
    ) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "E HH:mm"
        return formatter.string(from: date)
    }

    /// «через 2 ч 30 мин», «через 12 мин», «вот-вот».
    public static func timeLeft(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "вот-вот" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "через \(hours) ч \(minutes) мин" }
        return "через \(minutes) мин"
    }

    /// «обновлено 02:14» или «обновлено 12 мин назад», если давно.
    public static func freshness(
        _ date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else { return "нет данных" }
        let minutes = Int(now.timeIntervalSince(date)) / 60
        // Опрос идёт раз в 5 минут, поэтому «только что» — это первая
        // минута; дальше называем возраст в минутах.
        if minutes < 1 { return "обновлено только что" }
        if minutes < 60 { return "обновлено \(minutes) мин назад" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return "обновлено в \(formatter.string(from: date))"
    }

    /// Полоса заполнения для панели: ▓▓░░░░░░░░░░
    public static func bar(percent: Int, width: Int = 12) -> String {
        let clamped = max(0, min(100, percent))
        let filled = Int((Double(clamped) / 100 * Double(width)).rounded())
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: width - filled)
    }
}
