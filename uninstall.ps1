# =============================================================================
# 🗑️ Mandalina — Windows Kaldırma Aracı (uninstall.ps1)
# =============================================================================

Write-Host "🗑️ Mandalina sistemden kaldırılıyor..." -ForegroundColor Yellow

Get-Process pythonw -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -like "*\.mandalina-udf\*"
} | Stop-Process -Force -ErrorAction SilentlyContinue

$TargetDir = Join-Path $env:USERPROFILE ".mandalina-udf"
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$StartMenuDir = [Environment]::GetFolderPath("Programs")
$SendToDir = [Environment]::GetFolderPath("SendTo")

Remove-Item (Join-Path $DesktopDir "Mandalina.lnk") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $DesktopDir "Mandalina Güncelle.bat") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $StartMenuDir "Mandalina.lnk") -Force -ErrorAction SilentlyContinue
if ($SendToDir) {
    Remove-Item (Join-Path $SendToDir "Mandalina UDF Dönüştürücü.lnk") -Force -ErrorAction SilentlyContinue
}
if (Test-Path $TargetDir) {
    Remove-Item $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "✅ Mandalina başarıyla kaldırıldı." -ForegroundColor Green
