# =============================================================================
# 🔄 Mandalina — Windows Otomatik Güncelleme Aracı (update.ps1)
# Tek Satır Güncelleme Komutu (PowerShell):
# irm https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/update.ps1 | iex
# =============================================================================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "==========================================================" -ForegroundColor DarkYellow
Write-Host "🔄  Mandalina (Windows) — Otomatik Güncelleme Aracı       " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor DarkYellow

# Açık olan Mandalina örneğini kapat
Get-Process pythonw -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -like "*\.mandalina-udf\*"
} | Stop-Process -Force -ErrorAction SilentlyContinue

# install.ps1 betiğini çalıştırarak dosyaları ve bağımlılıkları güncelle
$InstallUrl = "https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/install.ps1"
Invoke-RestMethod -Uri $InstallUrl | Invoke-Expression
