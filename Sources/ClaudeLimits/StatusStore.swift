import Foundation
import LimitsCore

/// Состояние сервисов Claude. Отдельно от лимитов: другой адрес, другая
/// природа отказов, никакой авторизации — смешивать их в одном хранилище
/// значило бы связать несвязанное.
@MainActor
final class StatusStore: ObservableObject {
    @Published private(set) var status: ServiceStatus?
    @Published private(set) var unreachable = false

    private let client = StatusClient()
    private var timer: Timer?
    private let interval: TimeInterval = 300

    func start() {
        refresh()
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in store.refresh() }
        }
    }

    func refresh() {
        Task {
            switch await client.fetch() {
            case .success(let fresh):
                status = fresh
                unreachable = false
            case .failure(let error):
                Diagnostics.log("статус недоступен: \(error.logDetail)")
                // Прошлое состояние не стираем: «неизвестно» честнее,
                // чем ложное «всё работает».
                unreachable = true
            }
        }
    }

    /// Строка для свёрнутого вида: интересует прежде всего Claude Code.
    var headline: String {
        guard let status else { return unreachable ? "статус недоступен" : "запрашиваю…" }
        if let code = status.claudeCode { return code.label }
        return status.summary
    }

    /// Есть ли что показывать в раскрытом окне.
    var hasTrouble: Bool { status?.hasTrouble ?? false }
}
