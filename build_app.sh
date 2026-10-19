#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

APP_NAME="Mandalina"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

SOURCES=(
  Sources/Models.swift
  Sources/ZipHelper.swift
  Sources/UDFEngine.swift
  Sources/MediaConverterEngine.swift
  Sources/DemoFilesGenerator.swift
  Sources/DocumentPreviewWindow.swift
  Sources/RadialWheelOverlay.swift
  Sources/DragMonitorAndHUD.swift
  Sources/MainStudioAndApp.swift
)

COMPILED=false

if xcode-select -p &>/dev/null && command -v swiftc &>/dev/null; then
  echo "🔨 [1/4] Swift kaynak dosyaları derleniyor (Universal Binary: arm64 + x86_64)..."
  if swiftc -O -target arm64-apple-macos13.0 "${SOURCES[@]}" -o MandalinaBin_arm64 2>/dev/null && \
     swiftc -O -target x86_64-apple-macos13.0 "${SOURCES[@]}" -o MandalinaBin_x86_64 2>/dev/null && \
     command -v lipo &>/dev/null; then
    lipo -create -output MandalinaBin MandalinaBin_arm64 MandalinaBin_x86_64
    rm -f MandalinaBin_arm64 MandalinaBin_x86_64
    COMPILED=true
    echo "   ✓ Universal Binary (Apple Silicon + Intel) başarıyla derlendi."
  else
    rm -f MandalinaBin_arm64 MandalinaBin_x86_64
    echo "   ℹ️ Tek mimarili yerel derleme deneniyor..."
    if swiftc -O "${SOURCES[@]}" -o MandalinaBin_native; then
      mv -f MandalinaBin_native MandalinaBin
      COMPILED=true
      echo "   ✓ Yerel mimari için başarıyla derlendi."
    else
      rm -f MandalinaBin_native
      echo "   ⚠️ Yerel Swift derleyicisinde eksik bileşen algılandı; hazır Universal Binary (MandalinaBin) kullanılacak."
    fi
  fi
else
  echo "ℹ️ [1/4] Xcode Command Line Tools bulunamadı; hazır derlenmiş Universal Binary (MandalinaBin) kullanılıyor..."
fi

if [ ! -f "MandalinaBin" ]; then
  echo "❌ Hata: MandalinaBin bulunamadı ve derleme yapılamadı. Xcode Command Line Tools kuruluyor..."
  xcode-select --install 2>/dev/null || true
  exit 1
fi

echo "📦 [2/4] Uygulama paketi (${APP_BUNDLE}) hazırlanıyor..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp -X MandalinaBin "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || cp MandalinaBin "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp -X Info.plist "${CONTENTS_DIR}/Info.plist" 2>/dev/null || cp Info.plist "${CONTENTS_DIR}/Info.plist"

if [ -f "AppIcon.icns" ]; then
  cp -X "AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns" 2>/dev/null || cp "AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -f "version.json" ]; then
  cp -X "version.json" "${RESOURCES_DIR}/version.json" 2>/dev/null || cp "version.json" "${RESOURCES_DIR}/version.json"
fi

echo "🔏 [3/4] macOS yerel kod imzası (ad-hoc codesign) uygulanıyor..."
if command -v xattr &>/dev/null; then
  xattr -cr "${APP_BUNDLE}" 2>/dev/null || true
fi
if command -v codesign &>/dev/null; then
  codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true
fi

if [ "$1" != "--skip-test" ]; then
  echo "🧪 [4/4] Otomatik dönüşüm testleri çalıştırılıyor..."
  "./${MACOS_DIR}/${APP_NAME}" --self-test
fi

echo "✅ ${APP_BUNDLE} başarıyla oluşturuldu: $(pwd)/${APP_BUNDLE}"
