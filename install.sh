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

TARGET_DIR="$HOME/.mandalina-udf"
ZIP_URL="https://github.com/ssayoglu/mandalina-udf-converter/archive/refs/heads/main.zip"
APP_NAME="Mandalina.app"
APPLICATIONS_DIR="/Applications"
DESKTOP_DIR="$HOME/Desktop"

echo -e "${YELLOW}📥 Dosyalar GitHub üzerinden indiriliyor ($TARGET_DIR)...${NC}"
mkdir -p "$TARGET_DIR"

TMP_ZIP="/tmp/mandalina_udf_main.zip"
TMP_UNZIP="/tmp/mandalina_udf_extracted"
rm -rf "$TMP_ZIP" "$TMP_UNZIP"

curl -fsSL "$ZIP_URL" -o "$TMP_ZIP"
mkdir -p "$TMP_UNZIP"
unzip -q -o "$TMP_ZIP" -d "$TMP_UNZIP"
cp -R "$TMP_UNZIP/mandalina-udf-converter-main/"* "$TARGET_DIR/"
rm -rf "$TMP_ZIP" "$TMP_UNZIP"
cd "$TARGET_DIR"

chmod +x "$TARGET_DIR/build_app.sh" "$TARGET_DIR/install.sh" "$TARGET_DIR/update.sh" "$TARGET_DIR/uninstall.sh" "$TARGET_DIR/Kurulum.command" "$TARGET_DIR/Guncelle.command" "$TARGET_DIR/MandalinaBin" 2>/dev/null || true

echo -e "${YELLOW}🔨 macOS Uygulama Paketi ($APP_NAME) hazırlanıyor...${NC}"
bash "$TARGET_DIR/build_app.sh" --skip-test

echo -e "${YELLOW}🛑 Açık olan eski sürüm varsa kapatılıyor...${NC}"
pkill -f "Mandalina.app/Contents/MacOS/Mandalina" 2>/dev/null || true

echo -e "${YELLOW}📁 Uygulamalar (/Applications) ve Masaüstüne yerleştiriliyor...${NC}"
rm -rf "$APPLICATIONS_DIR/$APP_NAME" "$DESKTOP_DIR/$APP_NAME"
cp -R "$TARGET_DIR/$APP_NAME" "$APPLICATIONS_DIR/"
cp -R "$TARGET_DIR/$APP_NAME" "$DESKTOP_DIR/"
cp -f "$TARGET_DIR/Guncelle.command" "$DESKTOP_DIR/Mandalina Güncelle.command" 2>/dev/null || true
chmod +x "$DESKTOP_DIR/Mandalina Güncelle.command" 2>/dev/null || true

xattr -cr "$APPLICATIONS_DIR/$APP_NAME" "$DESKTOP_DIR/$APP_NAME" 2>/dev/null || true
touch "$APPLICATIONS_DIR/$APP_NAME" "$DESKTOP_DIR/$APP_NAME" 2>/dev/null || true

# macOS simge önbelleğini yenile
killall Finder Dock 2>/dev/null || true

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}✅  Mandalina Kurulumu Başarıyla Tamamlandı!        ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "🚀 Uygulama şimdi otomatik olarak başlatılıyor..."
open "$APPLICATIONS_DIR/$APP_NAME" || true
