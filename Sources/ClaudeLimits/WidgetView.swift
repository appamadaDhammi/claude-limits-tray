import AppKit
import LimitsCore
import ServiceManagement
import SwiftUI

/// Фон панели — плотный цвет, без матового стекла.
///
/// Размытие «сквозь окно» рисует оконный сервер, и во время перетаскивания
/// он его гасит: панель выглядит плоской и серой. Вернуть эффект сразу после
/// остановки окна надёжно не получается — сервер решает сам, когда
/// перестраивать слой. Плотный фон от компоновки не зависит вовсе, поэтому
/// панель выглядит одинаково всегда: при перетаскивании, при потере фокуса,
/// в Mission Control.
struct PanelBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(scheme == .dark
                  ? Color(red: 0.13, green: 0.12, blue: 0.11)   // тёплый тёмный
                  : Color(red: 0.98, green: 0.97, blue: 0.96))  // тёплый светлый
    }
}

/// Палитра в духе Claude Code: коралловый акцент, приглушённый текст.
enum Palette {
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)   // #D97757
    static let danger = Color(red: 0.86, green: 0.31, blue: 0.27)
    static let muted = Color.secondary
    static let ok = Color(red: 0.35, green: 0.66, blue: 0.44)
}

struct LimitRow: View {
    let title: String
    let limit: Limit?
    let dimmed: Bool

    private var tint: Color {
        guard let percent = limit?.percent else { return Palette.muted }
        if percent >= 95 { return Palette.danger }
        if percent >= 80 { return Palette.accent }
        return .primary
    }

    private var fill: Double {
        Double(max(0, min(100, limit?.percent ?? 0))) / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(dimmed ? Palette.muted : .primary)
                Spacer(minLength: 4)
                Text(limit.map { "\($0.percent)%" } ?? "—")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(dimmed ? Palette.muted : tint)
            }
            HStack(spacing: 6) {
                // Полоса — формами, а не символами: ровная высота и настоящий цвет.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(dimmed ? Palette.muted : tint)
                            .frame(width: geo.size.width * fill)
                    }
                }
                .frame(height: 4)

                Text(limit?.resetsAt != nil ? "до \(Formatting.resetTime(limit?.resetsAt))" : "")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .fixedSize()
            }
        }
    }
}

/// Блок состояния сервисов Claude: свёрнутая строка + раскрывающееся окно
/// с тем, что сейчас не так.
struct StatusSection: View {
    @ObservedObject var store: StatusStore
    @Binding var expanded: Bool

    private var dot: Color {
        guard let status = store.status else { return Palette.muted }
        if let code = status.claudeCode, !code.isOperational {
            return code.status == "major_outage" ? Palette.danger : Palette.accent
        }
        return status.hasTrouble ? Palette.accent : Palette.ok
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }) {
                HStack(spacing: 6) {
                    Circle().fill(dot).frame(width: 6, height: 6)
                    Text("Claude Code")
                        .font(.system(size: 11))
                    Spacer(minLength: 4)
                    Text(store.headline)
                        .font(.system(size: 10))
                        .foregroundStyle(store.hasTrouble ? Palette.accent : Palette.muted)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if let status = store.status {
                        ForEach(status.incidents, id: \.name) { incident in
                            IncidentRow(incident: incident)
                        }
                        // Компоненты показываем только проблемные: список из
                        // шести зелёных строк не сообщает ничего.
                        ForEach(status.components.filter { !$0.isOperational }, id: \.name) { component in
                            HStack(spacing: 5) {
                                Circle().fill(Palette.accent).frame(width: 4, height: 4)
                                Text("\(component.name) — \(component.label)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.primary)
                            }
                        }
                        if !status.hasTrouble {
                            Text("Все сервисы работают, инцидентов нет")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                        }
                    } else {
                        Text(store.unreachable
                             ? "Страница состояния недоступна"
                             : "запрашиваю…")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct IncidentRow: View {
    let incident: Incident

    private var impactColor: Color {
        switch incident.impact {
        case "critical", "major": return Palette.danger
        case "minor": return Palette.accent
        default: return Palette.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 5) {
                Circle().fill(impactColor).frame(width: 4, height: 4).padding(.top, 4)
                Text(incident.name)
                    .font(.system(size: 10, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(incident.statusLabel
                 + (incident.updatedAt != nil
                    ? " · \(Formatting.resetTime(incident.updatedAt))" : ""))
                .font(.system(size: 9))
                .foregroundStyle(Palette.muted)
                .padding(.leading, 9)
            if let update = incident.latestUpdate {
                Text(update)
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 9)
            }
        }
    }
}

/// Плавающая панель: таскается за любое место, положение запоминается.
struct WidgetView: View {
    @ObservedObject var store: LimitsStore
    @ObservedObject var statusStore: StatusStore
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("statusExpanded") private var statusExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("✳")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.accent)
                Text("Claude Limits")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let plan = store.plan {
                    Text(plan.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                }
            }

            if let limits = store.limits {
                LimitRow(title: "Сессия · 5ч", limit: limits.session, dimmed: store.isStale)
                LimitRow(title: "Неделя · всё", limit: limits.weeklyAll, dimmed: store.isStale)
                if limits.weeklyFable != nil {
                    LimitRow(title: "Неделя · Fable", limit: limits.weeklyFable, dimmed: store.isStale)
                }
            } else {
                Text(store.statusLine)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }

            Divider().opacity(0.5)

            StatusSection(store: statusStore, expanded: $statusExpanded)

            // Внизу только текст: кликабельного под курсором нет, поэтому
            // перетаскивание панели ничего случайно не нажимает.
            //
            // TimelineView, а не обычный Text: возраст данных должен идти
            // сам по себе. Обычная строка пересчитывается только при
            // изменении данных, то есть в момент удачного запроса — и тогда
            // она вечно показывает «только что», сколько бы ни прошло.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(store.limits != nil ? store.statusLine : "")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.muted)
            }
            .frame(height: 12)
        }
        .padding(12)
        .frame(width: 210)
        .background(
            PanelBackground()
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
        // Всё управление — правой кнопкой. Ни одна опасная команда
        // не лежит на пути курсора при перетаскивании.
        .contextMenu {
            Button("Обновить сейчас") {
                store.refresh()
                statusStore.refresh()
            }
            Divider()
            Toggle("Запускать при входе", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in setLaunchAtLogin(enabled) }
            Divider()
            Button("Закрыть Claude Limits") { NSApplication.shared.terminate(nil) }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            // Не смогли — не настаиваем и ничего не запускаем.
        }
    }
}
