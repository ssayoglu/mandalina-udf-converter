#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
ORANGE='\033[0;33m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${ORANGE}====================================================${NC}"
echo -e "${ORANGE}🔄  Mandalina — Otomatik Güncelleme Aracı           ${NC}"
echo -e "${ORANGE}====================================================${NC}"

TARGET_DIR="$HOME/.mandalina-udf"
ZIP_URL="https://github.com/ssayoglu/mandalina-udf-converter/archive/refs/heads/main.zip"
APP_NAME="Mandalina.app"

echo -e "${BLUE}🔍 Sistem bileşenleri kontrol ediliyor...${NC}"
for tool in curl unzip zip; do
  if ! command -v "$tool" &>/dev/null && command -v brew &>/dev/null; then
    echo -e "${YELLOW}⚠️  '$tool' eksik, Homebrew ile kuruluyor...${NC}"
    brew install "$tool" || true
  fi
done

mkdir -p "$TARGET_DIR"
TMP_ZIP="/tmp/mandalina_udf_update.zip"
TMP_UNZIP="/tmp/mandalina_udf_update_extracted"
rm -rf "$TMP_ZIP" "$TMP_UNZIP"

echo -e "${YELLOW}📥 En güncel sürüm GitHub'dan indiriliyor...${NC}"
if command -v curl &>/dev/null; then
  curl -fsSL "$ZIP_URL" -o "$TMP_ZIP"
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
chmod +x build_app.sh MandalinaBin install.sh update.sh uninstall.sh Guncelle.command Kurulum.command 2>/dev/null || true

echo -e "${YELLOW}🔨 Güncel uygulama paketi hazırlanıyor...${NC}"
bash "$TARGET_DIR/build_app.sh" --skip-test

pkill -f "Mandalina.app/Contents/MacOS/Mandalina" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME" "$HOME/Desktop/$APP_NAME"
cp -R "$TARGET_DIR/$APP_NAME" "/Applications/"
cp -R "$TARGET_DIR/$APP_NAME" "$HOME/Desktop/"
xattr -cr "/Applications/$APP_NAME" "$HOME/Desktop/$APP_NAME" 2>/dev/null || true
touch "/Applications/$APP_NAME" "$HOME/Desktop/$APP_NAME" 2>/dev/null || true

echo -e "${GREEN}✅ Mandalina en son sürüme başarıyla güncellendi!${NC}"
