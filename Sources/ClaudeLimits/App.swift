import AppKit
import LimitsCore
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
/// Ключ хранит ВЕРХНИЙ левый угол. Имя отличается от прежнего
/// (`panelOrigin`, нижний край) намеренно: сменив смысл значения,
/// нельзя оставлять старое имя — прочитается как своё и уведёт окно.
private let panelTopLeftKey = "panelTopLeft"

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
    private var hosting: NSView?
    /// Ширина панели (210) плюс поля (12×2). Высота — стартовая,
    /// дальше окно следует за содержимым.
    private static let initialSize = NSSize(width: 210, height: 250)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingView(rootView: WidgetView(
            store: store,
            statusStore: statusStore,
            onResize: { [weak self] size in
                MainActor.assumeIsolated { self?.resizePanel(to: size) }
            }
        ))
        hosting.layer?.backgroundColor = .clear
        // Размером управляем сами, через PanelSizeKey (см. resizePanel):
        // автоматический sizingOptions однажды уже схлопнул окно в ноль, а
        // при раскрытии блока состояния вовсе не сработал.

        // Обычное окно, а не NSPanel: служебные панели Mission Control
        // не показывает. Заголовок делаем прозрачным и пустым — визуально
        // окно остаётся безрамочным, но для системы это полноценное окно.
        let panel = WidgetWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        self.hosting = hosting
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
        panel.collectionBehavior = [.managed, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.setFrameOrigin(restoredOrigin(for: panel))
        self.panel = panel
        // Показываем СРАЗУ на активном столе. macOS запоминает, какому столу
        // принадлежали окна приложения, и без этого возвращает панель туда,
        // где её оставили в прошлый раз — пользователь запускает программу,
        // а система молча уводит его на другой рабочий стол.
        summonPanel()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { note in
            // Очередь .main, поэтому изоляция фактически соблюдена —
            // сообщаем об этом компилятору явно.
            MainActor.assumeIsolated {
                guard let moved = note.object as? NSWindow else { return }
                let frame = moved.frame
                UserDefaults.standard.set([frame.minX, frame.maxY], forKey: panelTopLeftKey)
            }
        }

        store.start()
        statusStore.start()

        // Страховка от схлопывания окна в ноль: такое уже случалось, когда
        // ручной размер конфликтовал с автоматическим. Окно нулевого размера
        // неотличимо от «приложение не запустилось», поэтому проверяем и
        // чиним, а не полагаемся на то, что этого больше не будет.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let panel = self?.panel else { return }
                if panel.frame.width < 40 || panel.frame.height < 40 {
                    Diagnostics.log("окно схлопнулось в \(panel.frame.size) — ставлю размер вручную")
                    panel.setContentSize(AppDelegate.initialSize)
                    panel.orderFrontRegardless()
                }
            }
        }
    }

    /// Восстанавливает положение; если сохранённая точка вне текущих экранов
    /// (отключили монитор) — возвращает панель в правый верхний угол.
    private func restoredOrigin(for panel: NSWindow) -> NSPoint {
        let size = panel.frame.size
        if let saved = UserDefaults.standard.array(forKey: panelTopLeftKey) as? [Double],
           saved.count == 2 {
            // Хранится верхний левый угол — из него получаем начало координат
            // окна (нижний левый), чтобы панель не прыгала при смене высоты.
            let point = NSPoint(x: saved[0], y: saved[1] - size.height)
            let frame = NSRect(origin: point, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return clamped(frame).origin
            }
        }
        guard let screen = NSScreen.main else { return .zero }
        return NSPoint(
            x: screen.visibleFrame.maxX - size.width - 20,
            y: screen.visibleFrame.maxY - size.height - 20
        )
    }

    /// Не даёт окну уехать за пределы экрана — при восстановлении позиции
    /// и при росте вниз.
    private func clamped(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })
                ?? NSScreen.main else { return frame }
        let area = screen.visibleFrame
        var result = frame
        result.origin.x = min(max(area.minX, result.origin.x), area.maxX - result.width)
        result.origin.y = min(max(area.minY, result.origin.y), area.maxY - result.height)
        return result
    }

    /// Подгоняет окно под содержимое. Верхний край остаётся на месте:
    /// окно растёт ВНИЗ. Иначе, из-за начала координат в левом нижнем углу,
    /// раскрытие блока состояния выталкивало бы панель вверх.
    private func resizePanel(to _: CGSize) {
        guard let panel, let hosting else { return }
        // Естественный размер спрашиваем у хостинга: содержимое, зажатое в
        // окно, о своей настоящей высоте не сообщает.
        hosting.layoutSubtreeIfNeeded()
        let natural = hosting.fittingSize
        guard natural.width > 1, natural.height > 1 else { return }
        let target = panel.frameRect(forContentRect: NSRect(origin: .zero, size: natural)).size
        let current = panel.frame
        guard abs(target.height - current.height) > 0.5
                || abs(target.width - current.width) > 0.5 else { return }
        let top = current.maxY
        panel.setFrame(
            clamped(NSRect(x: current.minX, y: top - target.height,
                           width: target.width, height: target.height)),
            display: true
        )
    }

    /// Повторный запуск уже работающего приложения. Без этого клик по иконке
    /// не делает НИЧЕГО: иконки в доке нет, окна не всплывают, а панель может
    /// стоять на другом рабочем столе — вернуть её было нечем.
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Diagnostics.log("повторный запуск (окна видны: \(hasVisibleWindows))")
        summonPanel()
        return true
    }

    /// Переносит панель на текущий рабочий стол и показывает её.
    private func summonPanel() {
        guard let panel else { return }

        // Если сохранённое место оказалось вне видимых экранов — возвращаем
        // панель в угол, иначе «призыв» покажет её там, где её не видно.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            panel.setFrameOrigin(restoredOrigin(for: panel))
        }

        // AppKit каскадирует окна с заголовком при показе — без явного
        // возврата координат панель уползала бы по экрану на каждом призыве,
        // и сдвинутое место ещё и сохранялось бы как «выбранное пользователем».
        let keep = panel.frame.origin

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.setFrameOrigin(keep)
        DispatchQueue.main.async { panel.setFrameOrigin(keep) }
        Diagnostics.log("призыв панели: \(Int(keep.x)),\(Int(keep.y))")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}
