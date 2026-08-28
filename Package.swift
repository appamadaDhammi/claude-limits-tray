// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeLimits",
    platforms: [.macOS(.v13)],
    targets: [
        // Чистая логика: разбор ответа, Keychain, пороги, форматирование.
        // Не знает про UI и покрыта тестами.
        .target(name: "LimitsCore"),

        // Приложение строки меню.
        .executableTarget(name: "ClaudeLimits", dependencies: ["LimitsCore"]),

        // Тесты отдельным исполняемым таргетом: XCTest недоступен без полного Xcode.
        // Запуск: swift run LimitsTests
        .executableTarget(name: "LimitsTests", dependencies: ["LimitsCore"]),
    ]
)
