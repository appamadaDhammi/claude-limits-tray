import AppKit
import Foundation
import LimitsCore
import UserNotifications

/// Единственный источник правды для интерфейса: опрашивает эндпоинт,
/// держит состояние и решает, когда уведомлять.
@MainActor
final class LimitsStore: ObservableObject {
    enum State: Equatable {
        case loading
        case ok(Limits)
        case stale(Limits)            // сеть отвалилась, показываем последнее известное
        case expired                  // 401 — токен протух, обновит сам Claude Code
        case noCredentials(CredentialsError)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var updatedAt: Date?
    @Published private(set) var plan: String?

    private let client = UsageClient()
    private var tracker = ThresholdTracker()
    private var timer: Timer?
    private var notificationsAllowed = false
    private var consecutiveFailures = 0
    private var cached: (credentials: Credentials, readAt: Date)?
    /// Название последнего отказа — показывается в строке состояния.
    @Published private(set) var lastError: String?

    // Расход меняется медленно, а квота эндпоинта общая с Claude Code —
    // частый опрос ничего не даёт, кроме отбитых запросов.
    private let normalInterval: TimeInterval = 300
    private let backoffInterval: TimeInterval = 300
    /// Пауза после 429, если сервер не назвал свою.
    private let rateLimitPause: TimeInterval = 90

    // MARK: - Жизненный цикл

    func start() {
        requestNotificationPermissionOnce()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in store.refresh() }
        }
        refresh()
        scheduleTimer(after: normalInterval)
    }

    private func scheduleTimer(after interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in store.refresh() }
        }
    }

    // MARK: - Опрос

    func refresh() {
        Task { await performRefresh() }
    }

    private func performRefresh() async {
        switch await credentials(reload: false) {
        case .failure(let error):
            // Токена нет — честно показываем и молчим.
            // Никаких попыток что-то запустить или починить (issue CodexBar #1844).
            state = .noCredentials(error)
            scheduleTimer(after: backoffInterval)

        case .success(let credentials):
            plan = credentials.subscriptionType
            var result = await client.fetch(token: credentials.accessToken)
            // Токен мог обновиться в Claude Code раньше, чем истёк наш кэш —
            // перечитываем связку один раз и пробуем снова.
            if case .failure(.unauthorized) = result,
               case .success(let fresh) = await self.credentials(reload: true),
               fresh.accessToken != credentials.accessToken {
                plan = fresh.subscriptionType
                result = await client.fetch(token: fresh.accessToken)
            }
            switch result {
            case .success(let limits):
                consecutiveFailures = 0
                lastError = nil
                state = .ok(limits)
                updatedAt = Date()
                deliver(tracker.check(limits))
                scheduleTimer(after: normalInterval)

            case .failure(.rateLimited(let retryAfter)):
                // Не ошибка: показанные цифры верны, просто сейчас
                // спрашивать нельзя. Состояние и отметку времени не трогаем.
                Diagnostics.log("429 — пропускаю опрос, повтор через "
                                + "\(Int(retryAfter ?? rateLimitPause)) с")
                // Если данных ещё нет (холодный старт попал на 429),
                // «запрашиваю…» было бы неправдой — говорим, чего ждём.
                lastError = limits == nil ? "жду очереди к серверу" : nil
                scheduleTimer(after: retryAfter ?? rateLimitPause)

            case .failure(.unauthorized), .failure(.forbidden):
                Diagnostics.log("токен отвергнут сервером")
                lastError = nil
                state = .expired
                scheduleTimer(after: backoffInterval)

            case .failure(let error):
                consecutiveFailures += 1
                // Причину называем как есть: «нет сети» на сбое сервера —
                // это подмена диагноза догадкой.
                Diagnostics.log("\(error.logDetail) (подряд: \(consecutiveFailures))")
                lastError = error.shortReason
                // Последнее удачное значение не стираем — показываем серым.
                if case .ok(let previous) = state { state = .stale(previous) }
                else if case .stale(let previous) = state { state = .stale(previous) }
                scheduleTimer(after: consecutiveFailures > 1 ? backoffInterval : normalInterval)
            }
        }
    }

    // MARK: - Доступ к связке ключей

    /// Токен держим в памяти до истечения срока: каждое обращение к Keychain
    /// может поднять системный диалог доступа, а опрос идёт регулярно —
    /// перечитывать связку каждый раз незачем и раздражающе.
    ///
    /// Само чтение уходит с главного потока: `SecItemCopyMatching` блокируется
    /// на всё время, пока система показывает диалог доступа, и на главном
    /// потоке это вешает весь интерфейс до ввода пароля.
    private func credentials(reload: Bool) async -> Result<Credentials, CredentialsError> {
        if !reload, let entry = cached, isFresh(entry) {
            return .success(entry.credentials)
        }
        let result = await Task.detached(priority: .utility) {
            KeychainReader.read()
        }.value
        switch result {
        case .success(let credentials): cached = (credentials, Date())
        case .failure: cached = nil
        }
        return result
    }

    private func isFresh(_ entry: (credentials: Credentials, readAt: Date)) -> Bool {
        // Токен живёт около восьми часов — перечитываем за две минуты до конца.
        if let expiresAt = entry.credentials.expiresAt {
            return expiresAt.timeIntervalSinceNow > 120
        }
        // Срок неизвестен — перечитываем раз в полчаса.
        return Date().timeIntervalSince(entry.readAt) < 1800
    }

    // MARK: - Отображение

    var limits: Limits? {
        switch state {
        case .ok(let limits), .stale(let limits): return limits
        default: return nil
        }
    }

    var isStale: Bool {
        if case .stale = state { return true }
        return false
    }

    var statusLine: String {
        switch state {
        case .loading: return lastError ?? "запрашиваю…"
        case .ok: return Formatting.freshness(updatedAt)
        case .stale: return Formatting.freshness(updatedAt) + " · " + (lastError ?? "сбой")
        case .expired: return "Запусти Claude Code — он обновит токен"
        case .noCredentials(.noClaudeToken): return "В Keychain нет токена Claude Code"
        case .noCredentials: return "Нет доступа к токену Claude Code"
        }
    }

    // MARK: - Уведомления

    private func requestNotificationPermissionOnce() {
        // Работает только в собранном .app; из голого бинаря молча пропускаем.
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            [weak self] granted, _ in
            Task { @MainActor in self?.notificationsAllowed = granted }
        }
    }

    private func deliver(_ alerts: [Alert]) {
        guard notificationsAllowed, !alerts.isEmpty else { return }
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
