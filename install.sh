#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${ORANGE}====================================================${NC}"
echo -e "${ORANGE}🍊  Mandalina — UYAP UDF & TIFF Dönüştürücü Kurulumu ${NC}"
echo -e "${ORANGE}====================================================${NC}"

# 0. Sistem ve Bileşen Kontrolü
echo -e "${BLUE}🔍 [0/4] Sistem bileşenleri ve gereksinimler kontrol ediliyor...${NC}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo -e "${RED}❌ Bu uygulama yalnızca macOS işletim sisteminde çalışır.${NC}"
  exit 1
fi

ensure_tool() {
  local cmd="$1"
  local pkg="$2"
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${YELLOW}⚠️  '$cmd' bileşeni bulunamadı, kuruluyor...${NC}"
    if command -v brew &>/dev/null; then
      brew install "$pkg" || true
    fi
  else
    echo -e "   ✓ $cmd hazır"
  fi
}

ensure_tool "curl" "curl"
ensure_tool "unzip" "unzip"
ensure_tool "zip" "zip"

if ! xcode-select -p &>/dev/null; then
  echo -e "${YELLOW}ℹ️  Xcode Command Line Tools kurulu değil.${NC}"
  echo -e "${YELLOW}   Hazır derlenmiş Universal Binary (Apple Silicon + Intel) kullanılacağı için kurulum kesintisiz devam edecek.${NC}"
else
  echo -e "   ✓ Xcode Command Line Tools hazır ($(xcode-select -p))"
fi

TARGET_DIR="$HOME/.mandalina-udf"
ZIP_URL="https://github.com/ssayoglu/mandalina-udf-converter/archive/refs/heads/main.zip"
APP_NAME="Mandalina.app"
APPLICATIONS_DIR="/Applications"
DESKTOP_DIR="$HOME/Desktop"

echo -e "${YELLOW}📥 [1/4] Dosyalar GitHub üzerinden indiriliyor ($TARGET_DIR)...${NC}"
mkdir -p "$TARGET_DIR"

TMP_ZIP="/tmp/mandalina_udf_main.zip"
TMP_UNZIP="/tmp/mandalina_udf_extracted"
rm -rf "$TMP_ZIP" "$TMP_UNZIP"

if command -v curl &>/dev/null; then
  curl -fsSL "$ZIP_URL" -o "$TMP_ZIP"
elif command -v wget &>/dev/null; then
  wget -qO "$TMP_ZIP" "$ZIP_URL"
else
  python3 -c "import urllib.request; urllib.request.urlretrieve('$ZIP_URL', '$TMP_ZIP')"
fi

mkdir -p "$TMP_UNZIP"
if command -v unzip &>/dev/null; then
  unzip -q -o "$TMP_ZIP" -d "$TMP_UNZIP"
else
  ditto -x -k "$TMP_ZIP" "$TMP_UNZIP"
fi

cp -R "$TMP_UNZIP/mandalina-udf-converter-main/"* "$TARGET_DIR/"
rm -rf "$TMP_ZIP" "$TMP_UNZIP"
cd "$TARGET_DIR"

chmod +x "$TARGET_DIR/build_app.sh" "$TARGET_DIR/install.sh" "$TARGET_DIR/update.sh" "$TARGET_DIR/uninstall.sh" "$TARGET_DIR/Kurulum.command" "$TARGET_DIR/Guncelle.command" "$TARGET_DIR/MandalinaBin" 2>/dev/null || true

echo -e "${YELLOW}🔨 [2/4] macOS Uygulama Paketi ($APP_NAME) hazırlanıyor...${NC}"
bash "$TARGET_DIR/build_app.sh" --skip-test

echo -e "${YELLOW}🛑 [3/4] Açık olan eski sürüm varsa kapatılıyor...${NC}"
pkill -f "Mandalina.app/Contents/MacOS/Mandalina" 2>/dev/null || true

echo -e "${YELLOW}📁 [4/4] Uygulamalar (/Applications) ve Masaüstüne yerleştiriliyor...${NC}"
rm -rf "$APPLICATIONS_DIR/$APP_NAME" "$DESKTOP_DIR/$APP_NAME"
cp -R "$TARGET_DIR/$APP_NAME" "$APPLICATIONS_DIR/"
cp -R "$TARGET_DIR/$APP_NAME" "$DESKTOP_DIR/"
cp -f "$TARGET_DIR/Guncelle.command" "$DESKTOP_DIR/Mandalina Güncelle.command" 2>/dev/null || true
chmod +x "$DESKTOP_DIR/Mandalina Güncelle.command" 2>/dev/null || true

if command -v xattr &>/dev/null; then
  xattr -cr "$APPLICATIONS_DIR/$APP_NAME" "$DESKTOP_DIR/$APP_NAME" 2>/dev/null || true
fi
touch "$APPLICATIONS_DIR/$APP_NAME" "$DESKTOP_DIR/$APP_NAME" 2>/dev/null || true

# macOS simge önbelleğini yenile
killall Finder Dock 2>/dev/null || true

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}✅  Mandalina Kurulumu Başarıyla Tamamlandı!        ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "🚀 Uygulama şimdi otomatik olarak başlatılıyor..."
open "$APPLICATIONS_DIR/$APP_NAME" || true
