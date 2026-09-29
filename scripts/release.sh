#!/usr/bin/env bash
# Đóng gói SelectTranslate thành DMG để chia sẻ.
#
#   ./scripts/release.sh                         # ký ad-hoc (người nhận phải bấm "Open Anyway")
#   SIGN_IDENTITY="Developer ID Application: Cuong Nguyen (TEAMID)" \
#   NOTARY_PROFILE="selecttranslate" ./scripts/release.sh   # ký + notarize → mở được ngay
#
# Notarize có 2 cách cấp credentials:
#   1) NOTARY_PROFILE: tạo 1 lần bằng
#      xcrun notarytool store-credentials selecttranslate --apple-id you@x.com --team-id TEAMID
#   2) NOTARY_APPLE_ID + NOTARY_TEAM_ID + NOTARY_PASSWORD (app-specific password) — dùng cho CI
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="SelectTranslate"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
IDENTITY="${SIGN_IDENTITY:--}"
# Ngoài ~/Desktop: iCloud gắn com.apple.FinderInfo lên .app → codesign từ chối (xem Makefile).
APP_DIR="${APP_DIR:-${HOME}/Library/Caches/${APP_NAME}}"
APP="${APP_DIR}/${APP_NAME}.app"
DMG="build/${APP_NAME}-${VERSION}.dmg"
ARCHS=(arm64 x86_64)

# Build từng arch rồi lipo: `swift build --arch a --arch b` cần XCBuild (chỉ có trong
# Xcode.app), còn cách này chạy được với Command Line Tools.
echo "▸ Build universal (Apple Silicon + Intel) v${VERSION}"
BINS=()
for arch in "${ARCHS[@]}"; do
  swift build -c release --triple "${arch}-apple-macosx"
  BINS+=("$(swift build -c release --triple "${arch}-apple-macosx" --show-bin-path)/${APP_NAME}")
done

echo "▸ Đóng gói ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
lipo -create "${BINS[@]}" -output "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "${APP}/Contents/Resources/"; fi

xattr -cr "${APP}"

echo "▸ Ký app (${IDENTITY})"
if [[ "${IDENTITY}" == "-" ]]; then
  codesign --force --options runtime --sign - "${APP}"
else
  codesign --force --options runtime --timestamp --sign "${IDENTITY}" "${APP}"
fi
codesign --verify --strict --verbose=2 "${APP}"

echo "▸ Tạo DMG"
STAGE="$(mktemp -d)"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
mkdir -p build
rm -f "${DMG}"
hdiutil create -volname "Select Translate" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${STAGE}"
if [[ "${IDENTITY}" != "-" ]]; then
  codesign --force --timestamp --sign "${IDENTITY}" "${DMG}"
fi

if [[ "${IDENTITY}" != "-" ]]; then
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "▸ Notarize (profile ${NOTARY_PROFILE})"
    xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
  elif [[ -n "${NOTARY_APPLE_ID:-}" ]]; then
    echo "▸ Notarize (${NOTARY_APPLE_ID})"
    xcrun notarytool submit "${DMG}" --apple-id "${NOTARY_APPLE_ID}" \
      --team-id "${NOTARY_TEAM_ID}" --password "${NOTARY_PASSWORD}" --wait
  fi
  if [[ -n "${NOTARY_PROFILE:-}${NOTARY_APPLE_ID:-}" ]]; then
    xcrun stapler staple "${DMG}"
  fi
fi

echo "✓ ${DMG}"
