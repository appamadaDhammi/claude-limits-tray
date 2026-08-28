#!/bin/bash
# Собирает Claude Limits.app из SwiftPM-бинаря. Xcode не требуется.
# Использование: ./make.sh [--install]   (--install кладёт в /Applications)
set -euo pipefail

cd "$(dirname "$0")"
NAME="Claude Limits"
BUNDLE_ID="com.kadu.claude-limits"
VERSION="1.0"
APP="build/$NAME.app"

echo "==> тесты"
swift run LimitsTests 2>/dev/null

echo "==> сборка релиза"
# Статус берём у самой сборки, а не у grep: иначе провал компиляции
# проходит незамеченным и в бандл уезжает бинарь от прошлой сборки.
BUILD_LOG=$(mktemp)
if ! swift build -c release --product ClaudeLimits >"$BUILD_LOG" 2>&1; then
    grep -vE "XCTest paths|xcrun: error" "$BUILD_LOG" || true
    rm -f "$BUILD_LOG"
    echo "СБОРКА ПРОВАЛЕНА"
    exit 1
fi
grep -vE "XCTest paths|xcrun: error|^ *$" "$BUILD_LOG" | tail -3 || true
rm -f "$BUILD_LOG"
BINARY=$(swift build -c release --product ClaudeLimits --show-bin-path 2>/dev/null)/ClaudeLimits
test -x "$BINARY" || { echo "бинарь не собрался: $BINARY"; exit 1; }

echo "==> сборка бандла"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/ClaudeLimits"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>ClaudeLimits</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <!-- Живёт только в строке меню: без иконки в доке и без переключения приложений -->
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Личная утилита</string>
</dict>
</plist>
PLIST

echo "==> подпись ad-hoc"
codesign --force --deep --sign - "$APP"

echo "==> готово: $APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> установка в /Applications"
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" "/Applications/$NAME.app"
    echo "==> запуск"
    open "/Applications/$NAME.app"
fi
