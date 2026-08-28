import Foundation
import LimitsCore

// Тесты отдельным исполняемым таргетом: XCTest недоступен без полного Xcode
// (`swift test` → "error: XCTest not available"). Запуск: swift run LimitsTests

var failures = 0
var checks = 0

func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if condition {
        print("  ✓ \(name)")
    } else {
        failures += 1
        let extra = detail()
        print("  ✗ \(name)\(extra.isEmpty ? "" : "\n      \(extra)")")
    }
}

func group(_ name: String) { print("\n\(name)") }

// MARK: - Фикстуры (реальные ответы эндпоинта, идентификаторы вычищены)

let fullResponse = """
{
  "five_hour": {"utilization": 13.0, "resets_at": "2026-08-26T01:30:00.387122+00:00"},
  "seven_day": {"utilization": 3.0, "resets_at": "2026-08-26T22:00:00.387151+00:00"},
  "seven_day_overage_included": null,
  "limits": [
    {"kind": "session", "group": "session", "percent": 13, "severity": "normal",
     "resets_at": "2026-08-26T01:30:00.387122+00:00", "scope": null, "is_active": true},
    {"kind": "weekly_all", "group": "weekly", "percent": 3, "severity": "normal",
     "resets_at": "2026-08-26T22:00:00.387151+00:00", "scope": null, "is_active": false},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 2, "severity": "normal",
     "resets_at": "2026-08-26T22:00:00.387260+00:00",
     "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null},
     "is_active": false}
  ]
}
""".data(using: .utf8)!

let noFable = """
{"limits": [
  {"kind": "session", "percent": 42, "resets_at": "2026-08-26T01:30:00.387122+00:00", "scope": null},
  {"kind": "weekly_all", "percent": 7, "resets_at": "2026-08-26T22:00:00.387151+00:00", "scope": null}
]}
""".data(using: .utf8)!

let otherModelScoped = """
{"limits": [
  {"kind": "weekly_scoped", "percent": 66, "resets_at": null,
   "scope": {"model": {"display_name": "Sonnet"}}},
  {"kind": "unknown_future_kind", "percent": 99, "resets_at": null, "scope": null}
]}
""".data(using: .utf8)!

let noResetTime = """
{"limits": [{"kind": "session", "percent": 5, "resets_at": null, "scope": null}]}
""".data(using: .utf8)!

// MARK: - Разбор ответа

group("Разбор ответа эндпоинта")

do {
    let limits = try LimitsParser.parse(fullResponse)
    check("часовой лимит прочитан", limits.session?.percent == 13,
          "получено \(String(describing: limits.session?.percent))")
    check("недельный общий прочитан", limits.weeklyAll?.percent == 3)
    check("недельный Fable прочитан из limits[], а не из легаси-поля",
          limits.weeklyFable?.percent == 2,
          "seven_day_overage_included = null, но строка Fable в limits[] есть")
    check("время сброса разобрано", limits.session?.resetsAt != nil)
    check("худший лимит — часовой", limits.worstPercent == 13)
} catch {
    check("полный ответ разбирается", false, "\(error)")
}

do {
    let limits = try LimitsParser.parse(noFable)
    check("без строки Fable — nil, а не ноль", limits.weeklyFable == nil)
    check("остальные строки при этом целы", limits.session?.percent == 42 && limits.weeklyAll?.percent == 7)
} catch {
    check("ответ без Fable разбирается", false, "\(error)")
}

do {
    let limits = try LimitsParser.parse(otherModelScoped)
    check("weekly_scoped чужой модели не попадает в строку Fable", limits.weeklyFable == nil,
          "Sonnet не должен подменять Fable")
    check("незнакомый kind игнорируется молча", limits.session == nil && limits.weeklyAll == nil)
} catch {
    check("ответ с чужой моделью разбирается", false, "\(error)")
}

do {
    let limits = try LimitsParser.parse(noResetTime)
    check("resets_at = null не ломает разбор", limits.session?.percent == 5)
    check("время сброса при этом nil", limits.session?.resetsAt == nil)
} catch {
    check("ответ без времени сброса разбирается", false, "\(error)")
}

do {
    _ = try LimitsParser.parse("не json".data(using: .utf8)!)
    check("мусор вместо JSON отвергается", false, "разбор не должен был пройти")
} catch {
    check("мусор вместо JSON отвергается", true)
}

// MARK: - Keychain

group("Разбор записи Keychain")

let ccShape = """
{"claudeAiOauth": {"accessToken": "sk-ant-oat01-TESTTOKEN", "refreshToken": "sk-ant-ort01-X",
 "expiresAt": 1787718267178, "subscriptionType": "max", "scopes": ["user:profile"]}}
""".data(using: .utf8)!

let mcpOnlyShape = """
{"mcpOAuth": {"craft": {"accessToken": "", "serverName": "craft"}}}
""".data(using: .utf8)!

switch KeychainReader.parse(ccShape) {
case .success(let creds):
    check("токен прочитан", creds.accessToken == "sk-ant-oat01-TESTTOKEN")
    check("тариф прочитан", creds.subscriptionType == "max")
    check("срок жизни переведён из миллисекунд",
          creds.expiresAt.map { abs($0.timeIntervalSince1970 - 1787718267.178) < 1 } == true)
case .failure(let error):
    check("запись обычной формы читается", false, "\(error)")
}

switch KeychainReader.parse(mcpOnlyShape) {
case .success:
    check("запись только с mcpOAuth опознаётся как «нет токена»", false,
          "именно эта форма положила CodexBar в цикл починки")
case .failure(let error):
    check("запись только с mcpOAuth опознаётся как «нет токена»", error == .noClaudeToken,
          "получено \(error)")
}

switch KeychainReader.parse("{}".data(using: .utf8)!) {
case .success: check("пустой объект — не токен", false)
case .failure(let error): check("пустой объект — не токен", error == .noClaudeToken)
}

// MARK: - Пороги уведомлений

group("Пороги уведомлений")

let window = Date(timeIntervalSince1970: 1_787_800_000)
func limitsWith(session: Int, window: Date? = window) -> Limits {
    Limits(session: Limit(percent: session, resetsAt: window), weeklyAll: nil, weeklyFable: nil)
}

var tracker = ThresholdTracker()
check("на 13% молчит", tracker.check(limitsWith(session: 13)).isEmpty)
check("на 79% молчит", tracker.check(limitsWith(session: 79)).isEmpty)

let at80 = tracker.check(limitsWith(session: 80))
check("на 80% срабатывает один раз", at80.count == 1 && at80.first?.kind == .threshold(80),
      "получено \(at80)")
check("на 85% повторно не срабатывает", tracker.check(limitsWith(session: 85)).isEmpty)

let at95 = tracker.check(limitsWith(session: 96))
check("на 95% срабатывает отдельно", at95.count == 1 && at95.first?.kind == .threshold(95))
check("на 97% больше не срабатывает", tracker.check(limitsWith(session: 97)).isEmpty)

let newWindow = window.addingTimeInterval(5 * 3600)
let afterReset = tracker.check(limitsWith(session: 4, window: newWindow))
check("смена окна даёт уведомление о сбросе",
      afterReset.contains { $0.kind == .sessionReset }, "получено \(afterReset)")
check("в новом окне порог 80 может сработать снова",
      tracker.check(limitsWith(session: 81, window: newWindow))
        .contains { $0.kind == .threshold(80) })

// MARK: - Форматирование

group("Форматирование")

let noon = Date(timeIntervalSince1970: 1_787_745_600)
check("нет времени сброса — прочерк", Formatting.resetTime(nil) == "—")
check("остаток в часах и минутах",
      Formatting.timeLeft(noon.addingTimeInterval(2 * 3600 + 30 * 60), now: noon) == "через 2 ч 30 мин",
      Formatting.timeLeft(noon.addingTimeInterval(2 * 3600 + 30 * 60), now: noon))
check("остаток в минутах",
      Formatting.timeLeft(noon.addingTimeInterval(12 * 60), now: noon) == "через 12 мин")
check("прошедшее время не уходит в минус",
      Formatting.timeLeft(noon.addingTimeInterval(-60), now: noon) == "вот-вот")
check("свежесть: только что",
      Formatting.freshness(noon.addingTimeInterval(-30), now: noon) == "обновлено только что")
check("свежесть: минуты назад",
      Formatting.freshness(noon.addingTimeInterval(-12 * 60), now: noon) == "обновлено 12 мин назад")
check("свежесть: через 3 минуты уже НЕ «только что»",
      Formatting.freshness(noon.addingTimeInterval(-3 * 60), now: noon) == "обновлено 3 мин назад",
      Formatting.freshness(noon.addingTimeInterval(-3 * 60), now: noon))
check("свежесть: минута с небольшим — уже возраст, а не «только что»",
      Formatting.freshness(noon.addingTimeInterval(-70), now: noon) == "обновлено 1 мин назад")
check("свежесть: нет данных", Formatting.freshness(nil) == "нет данных")
check("полоса на 0%", Formatting.bar(percent: 0) == "░░░░░░░░░░░░")
check("полоса на 100%", Formatting.bar(percent: 100) == "▓▓▓▓▓▓▓▓▓▓▓▓")
check("полоса на 50%", Formatting.bar(percent: 50) == "▓▓▓▓▓▓░░░░░░", Formatting.bar(percent: 50))
check("полоса не переполняется за 100%", Formatting.bar(percent: 150).count == 12)

// MARK: - Именование отказов

group("Именование отказов")

check("сбой сети называется сетью",
      UsageError.transport("offline").shortReason == "нет сети")
check("ответ сервера НЕ называется сбоем сети",
      UsageError.http(500).shortReason == "сервер ответил 500",
      "получено: \(UsageError.http(500).shortReason)")
check("частота НЕ называется сбоем сети",
      UsageError.http(429).shortReason == "сервер ответил 429")
check("неразобранный ответ НЕ называется сбоем сети",
      UsageError.parse("bad json").shortReason == "ответ не разобран")
check("отвергнутый токен назван отдельно",
      UsageError.unauthorized.shortReason == "токен не принят")
check("в журнал уходит подробность, а не короткое имя",
      UsageError.http(503).logDetail == "HTTP 503")
check("429 отделён от прочих кодов и не зовётся сбоем сети",
      UsageError.rateLimited(retryAfter: nil).shortReason == "сервер просит подождать")
check("нулевой Retry-After не выдаётся за паузу",
      UsageError.rateLimited(retryAfter: nil).logDetail.contains("не указан"))
check("названная сервером пауза попадает в журнал",
      UsageError.rateLimited(retryAfter: 30).logDetail.contains("30"))

// MARK: - Состояние сервисов

group("Состояние сервисов Claude")

let allGood = """
{"status": {"indicator": "none", "description": "All Systems Operational"},
 "components": [
   {"name": "Claude API (api.anthropic.com)", "status": "operational", "group": false},
   {"name": "Claude Code", "status": "operational", "group": false},
   {"name": "Раздел", "status": "operational", "group": true}],
 "incidents": []}
""".data(using: .utf8)!

let stormy = """
{"status": {"indicator": "major", "description": "Partial Outage"},
 "components": [
   {"name": "Claude API (api.anthropic.com)", "status": "degraded_performance", "group": false},
   {"name": "Claude Code", "status": "major_outage", "group": false}],
 "incidents": [
   {"name": "Elevated error rates", "impact": "major", "status": "investigating",
    "incident_updates": [
      {"body": "We are investigating elevated error rates.",
       "created_at": "2026-08-27T10:15:00.000Z"}]}]}
""".data(using: .utf8)!

do {
    let status = try StatusParser.parse(allGood)
    check("Claude Code найден среди компонентов", status.claudeCode?.name == "Claude Code")
    check("всё работает — тревоги нет", status.hasTrouble == false)
    check("группы-заголовки отброшены", status.components.count == 2,
          "получено \(status.components.map(\.name))")
    check("состояние переведено", status.claudeCode?.label == "работает")
} catch {
    check("спокойный ответ разбирается", false, "\(error)")
}

do {
    let status = try StatusParser.parse(stormy)
    check("сбой распознан как тревога", status.hasTrouble)
    check("недоступность Claude Code названа", status.claudeCode?.label == "недоступен")
    check("короткое имя состояния помещается в строку заголовка",
          ServiceComponent(name: "x", status: "partial_outage").shortLabel == "сбой")
    check("полное имя остаётся для раскрытого списка",
          ServiceComponent(name: "x", status: "partial_outage").label == "частичный сбой")
    check("замедление API названо", status.api?.label == "замедлен")
    check("инцидент прочитан", status.incidents.first?.name == "Elevated error rates")
    check("стадия инцидента переведена", status.incidents.first?.statusLabel == "разбираются")
    check("последнее сообщение инцидента взято",
          status.incidents.first?.latestUpdate?.hasPrefix("We are investigating") == true)
    check("время сообщения разобрано", status.incidents.first?.updatedAt != nil)
} catch {
    check("ответ со сбоем разбирается", false, "\(error)")
}

// MARK: - Итог

print("\n" + String(repeating: "─", count: 46))
if failures == 0 {
    print("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ: \(checks)")
    exit(0)
} else {
    print("ПРОВАЛЕНО: \(failures) из \(checks)")
    exit(1)
}
