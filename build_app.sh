#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

APP_NAME="Mandalina"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

if command -v swiftc &> /dev/null; then
  echo "🔨 [1/4] Swift kaynak dosyaları derleniyor..."
  swiftc -O \
    Sources/Models.swift \
    Sources/ZipHelper.swift \
    Sources/UDFEngine.swift \
    Sources/MediaConverterEngine.swift \
    Sources/DemoFilesGenerator.swift \
    Sources/DocumentPreviewWindow.swift \
    Sources/RadialWheelOverlay.swift \
    Sources/DragMonitorAndHUD.swift \
    Sources/MainStudioAndApp.swift \
    -o MandalinaBin
else
  echo "ℹ️ [1/4] Hazır derlenmiş MandalinaBin ikili dosyası kullanılıyor..."
fi

echo "📦 [2/4] Uygulama paketi (${APP_BUNDLE}) hazırlanıyor..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp -X MandalinaBin "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp -X Info.plist "${CONTENTS_DIR}/Info.plist"

if [ -f "AppIcon.icns" ]; then
  cp -X "AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -f "version.json" ]; then
  cp -X "version.json" "${RESOURCES_DIR}/version.json"
fi

echo "🔏 [3/4] macOS yerel kod imzası (ad-hoc codesign) uygulanıyor..."
xattr -cr "${APP_BUNDLE}"
codesign --force --deep --sign - "${APP_BUNDLE}"

if [ "$1" != "--skip-test" ]; then
  echo "🧪 [4/4] Otomatik dönüşüm testleri çalıştırılıyor..."
  "./${MACOS_DIR}/${APP_NAME}" --self-test
fi

echo "✅ ${APP_BUNDLE} başarıyla oluşturuldu: $(pwd)/${APP_BUNDLE}"
