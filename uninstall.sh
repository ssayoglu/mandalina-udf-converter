#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${ORANGE}====================================================${NC}"
echo -e "${ORANGE}🗑️  Mandalina Kaldırma Aracı                        ${NC}"
echo -e "${ORANGE}====================================================${NC}"

echo -e "${YELLOW}🛑 Çalışan Mandalina işlemleri kapatılıyor...${NC}"
pkill -f "Mandalina.app/Contents/MacOS/Mandalina" 2>/dev/null || true

echo -e "${YELLOW}🧹 Uygulama dosyaları ve kısayolları temizleniyor...${NC}"
rm -rf "/Applications/Mandalina.app"
rm -rf "$HOME/Desktop/Mandalina.app"
rm -f "$HOME/Desktop/Mandalina Güncelle.command"
rm -rf "$HOME/.mandalina-udf"

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}✅ Mandalina sistemden başarıyla kaldırıldı.        ${NC}"
echo -e "${GREEN}====================================================${NC}"
