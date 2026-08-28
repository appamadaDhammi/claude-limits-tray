import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // .accessory — ни иконки в доке, ни строки меню: живём одной панелью.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Ключ хранения позиции. Вынесен из класса: к нему обращается
/// обработчик перемещения окна, а тот не изолирован главным актором.
private let panelOriginKey = "panelOrigin"

/// Безрамочное окно должно уметь становиться ключевым, иначе галочка
/// и кнопки внутри него не получат кликов.
final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = LimitsStore()
    private let statusStore = StatusStore()
    private var panel: WidgetWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingView(rootView: WidgetView(store: store, statusStore: statusStore))
        hosting.layer?.backgroundColor = .clear
        // Окно следует за содержимым: без этого раскрытие блока
        // состояния просто обрежется прежним размером окна.
        hosting.sizingOptions = [.preferredContentSize]

        // Обычное окно, а не NSPanel: служебные панели Mission Control
        // не показывает. Заголовок делаем прозрачным и пустым — визуально
        // окно остаётся безрамочным, но для системы это полноценное окно.
        let panel = WidgetWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = "Claude Limits"
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        // На ступеньку выше обычных окон, но НЕ .floating: окна плавающего
        // уровня Mission Control не показывает, а значит их нельзя перетащить
        // на соседний рабочий стол.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
        // Таскается за любое место — заголовка у панели нет.
        panel.isMovableByWindowBackground = true
        // .managed вместо .canJoinAllSpaces: окно принадлежит одному столу
        // и потому участвует в Mission Control. «Виден на всех столах» и
        // «перетаскивается между столами» — взаимоисключающие режимы.
        panel.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.setContentSize(hosting.fittingSize)
        panel.setFrameOrigin(restoredOrigin(for: panel))
        panel.orderFrontRegardless()
        self.panel = panel

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { note in
            // Очередь .main, поэтому изоляция фактически соблюдена —
            // сообщаем об этом компилятору явно.
            MainActor.assumeIsolated {
                guard let moved = note.object as? NSWindow else { return }
                let origin = moved.frame.origin
                UserDefaults.standard.set([origin.x, origin.y], forKey: panelOriginKey)
            }
        }

        store.start()
        statusStore.start()
    }

    /// Восстанавливает положение; если сохранённая точка вне текущих экранов
    /// (отключили монитор) — возвращает панель в правый верхний угол.
    private func restoredOrigin(for panel: NSWindow) -> NSPoint {
        let size = panel.frame.size
        if let saved = UserDefaults.standard.array(forKey: panelOriginKey) as? [Double],
           saved.count == 2 {
            let point = NSPoint(x: saved[0], y: saved[1])
            let frame = NSRect(origin: point, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return point
            }
        }
        guard let screen = NSScreen.main else { return .zero }
        return NSPoint(
            x: screen.visibleFrame.maxX - size.width - 20,
            y: screen.visibleFrame.maxY - size.height - 20
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}
