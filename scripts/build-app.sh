#!/usr/bin/env bash
# Build SelectTranslate.app từ Swift Package.
#   CONFIG=debug|release (mặc định release)
#   SIGN_IDENTITY="Apple Development: ..." để ký bằng cert cố định
#   (giữ được quyền Accessibility giữa các lần build). Mặc định ký ad-hoc "-".
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="SelectTranslate"
CONFIG="${CONFIG:-release}"
IDENTITY="${SIGN_IDENTITY:--}"
# Ngoài ~/Desktop: iCloud gắn com.apple.FinderInfo lên .app → codesign từ chối (xem Makefile).
APP_DIR="${APP_DIR:-${HOME}/Library/Caches/${APP_NAME}}"
APP="${APP_DIR}/${APP_NAME}.app"

echo "▸ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"
BIN_DIR="$(swift build -c "${CONFIG}" --show-bin-path)"

echo "▸ Đóng gói ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "${APP}/Contents/Resources/"; fi

xattr -cr "${APP}"

echo "▸ codesign (${IDENTITY})"
codesign --force --options runtime --timestamp=none --sign "${IDENTITY}" "${APP}"

echo "✓ ${APP}"
