#!/bin/bash
# Собирает всё, что раздаётся с kadu.su/claudelimits.
#
# Приложение подписано ad-hoc, а не Developer ID: любой файл, скачанный
# браузером, получает карантинную метку, и Gatekeeper откажется его открывать.
# Поэтому способов установки три, от самого гладкого к самому привычному:
#   install.sh — снимает карантин сам, предупреждения не будет;
#   .dmg       — перетащить в Программы, при первом запуске «Открыть» из меню;
#   .pkg       — двойной клик, тоже через «Открыть» из контекстного меню.
set -euo pipefail

cd "$(dirname "$0")"
NAME="Claude Limits"
VERSION="1.0"
BUNDLE_ID="com.kadu.claude-limits"
BASE_URL="https://kadu.su/claudelimits"
DIST="dist"

./make.sh

echo "==> подготовка dist"
rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> zip (для install.sh)"
ditto -c -k --keepParent "build/$NAME.app" "$DIST/ClaudeLimits-$VERSION.zip"

echo "==> pkg"
pkgbuild --quiet \
    --install-location /Applications \
    --component "build/$NAME.app" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    "$DIST/ClaudeLimits-$VERSION.pkg"

echo "==> dmg"
STAGE=$(mktemp -d)
cp -R "build/$NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" \
    -ov -format UDZO "$DIST/ClaudeLimits-$VERSION.dmg"
rm -rf "$STAGE"

echo "==> install.sh"
cat > "$DIST/install.sh" <<INSTALLER
#!/bin/bash
# Установщик Claude Limits. Скачивает приложение, кладёт в /Applications
# и снимает карантинную метку — иначе macOS откажется открывать программу,
# подписанную не Developer ID.
set -euo pipefail

NAME="Claude Limits"
URL="$BASE_URL/ClaudeLimits-$VERSION.zip"

echo "Claude Limits $VERSION"

if [[ "\$(uname)" != "Darwin" ]]; then
    echo "Только для macOS." >&2
    exit 1
fi

MAJOR=\$(sw_vers -productVersion | cut -d. -f1)
if (( MAJOR < 13 )); then
    echo "Нужна macOS 13 или новее (у вас \$(sw_vers -productVersion))." >&2
    exit 1
fi

if ! command -v claude >/dev/null 2>&1 && [[ ! -d "/Applications/Claude.app" ]]; then
    echo "Внимание: Claude Code не найден. Панель читает его токен из связки"
    echo "ключей и без установленного и залогиненного Claude Code работать не будет."
    echo
fi

TMP=\$(mktemp -d)
trap 'rm -rf "\$TMP"' EXIT

echo "==> скачиваю"
curl -fsSL "\$URL" -o "\$TMP/app.zip"

echo "==> распаковываю"
unzip -q "\$TMP/app.zip" -d "\$TMP"

if pgrep -f "\$NAME.app/Contents/MacOS" >/dev/null; then
    echo "==> останавливаю запущенную версию"
    pkill -f "\$NAME.app/Contents/MacOS" || true
    sleep 2
fi

echo "==> устанавливаю в /Applications"
rm -rf "/Applications/\$NAME.app"
cp -R "\$TMP/\$NAME.app" /Applications/

# Без этого Gatekeeper покажет «программа повреждена»: метка ставится
# браузером и curl на всё скачанное из сети.
xattr -dr com.apple.quarantine "/Applications/\$NAME.app" 2>/dev/null || true

echo "==> запускаю"
open "/Applications/\$NAME.app"
echo
echo "Готово. Панель появится на рабочем столе."
echo "Управление — правой кнопкой по панели."
INSTALLER
chmod +x "$DIST/install.sh"

echo "==> страница"
cp web/index.html "$DIST/index.html"

echo "==> контрольные суммы"
(cd "$DIST" && shasum -a 256 ClaudeLimits-* install.sh > SHA256SUMS)

echo
echo "готово, $DIST:"
ls -lh "$DIST" | awk 'NR>1 {printf "    %-28s %s\n", $9, $5}'
