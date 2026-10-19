# =============================================================================
# 🍊 Mandalina — UYAP (.udf) & TIFF Dönüştürücü (Windows Otomatik Kurulum)
# Tek Satır Kurulum Komutu (PowerShell):
# irm https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/install.ps1 | iex
# =============================================================================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "==========================================================" -ForegroundColor DarkYellow
Write-Host "🍊  Mandalina — UYAP UDF & TIFF Dönüştürücü (Windows)    " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor DarkYellow

$TargetDir = Join-Path $env:USERPROFILE ".mandalina-udf"
$ZipUrl = "https://github.com/ssayoglu/mandalina-udf-converter/archive/refs/heads/main.zip"
$VenvDir = Join-Path $TargetDir "venv"

# -----------------------------------------------------------------------------
# 0. Python 3 & Sistem Bileşenleri Kontrolü (Yoksa Otomatik Kurar)
# -----------------------------------------------------------------------------
Write-Host "`n🔍 [0/5] Sistem bileşenleri (Python 3 & Tkinter) kontrol ediliyor..." -ForegroundColor Cyan

function Find-ValidPython {
    $candidates = @(
        "python",
        "py",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
        "C:\Python312\python.exe",
        "C:\Python311\python.exe"
    )
    foreach ($cmd in $candidates) {
        try {
            if ($cmd -eq "py") {
                $ver = & py -3 -c "import sys, tkinter; print(sys.executable)" 2>$null
            } else {
                $ver = & $cmd -c "import sys, tkinter; print(sys.executable)" 2>$null
            }
            if ($LASTEXITCODE -eq 0 -and $ver -and ($ver -notmatch "WindowsApps")) {
                return $ver.Trim()
            }
        } catch {}
    }
    return $null
}

$PythonExe = Find-ValidPython

if (-not $PythonExe) {
    Write-Host "⚠️  Sistemde Python 3 (veya Tkinter) bulunamadı. Otomatik kuruluyor..." -ForegroundColor Yellow

    $installed = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "   📦 winget üzerinden Python 3.12 kuruluyor..." -ForegroundColor Yellow
        try {
            winget install -e --id Python.Python.3.12 --scope user --accept-package-agreements --accept-source-agreements --silent
            $installed = $true
        } catch {}
    }

    if (-not $installed) {
        Write-Host "   📥 Resmi Python 3.12 kurulum paketi indiriliyor..." -ForegroundColor Yellow
        $pyInstaller = Join-Path $env:TEMP "python-3.12.7-amd64.exe"
        Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe" -OutFile $pyInstaller -UseBasicParsing
        Write-Host "   ⚙️  Python 3.12 sessiz modda kuruluyor (1-2 dakika sürebilir)..." -ForegroundColor Yellow
        Start-Process -FilePath $pyInstaller -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_tcltk=1 Include_pip=1" -Wait
        Remove-Item $pyInstaller -Force -ErrorAction SilentlyContinue
    }

    # PATH ortam değişkenini yenile
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $PythonExe = Find-ValidPython

    if (-not $PythonExe) {
        Write-Host "❌ Python 3 otomatik kurulumu tamamlanamadı. Lütfen https://www.python.org/downloads/ adresinden Python 3 kurup tekrar deneyin." -ForegroundColor Red
        exit 1
    }
}

Write-Host "   ✓ Python hazır: $PythonExe" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 1. GitHub Üzerinden Mandalina Dosyalarını İndirme
# -----------------------------------------------------------------------------
Write-Host "`n📥 [1/5] Mandalina kaynak dosyaları GitHub'dan indiriliyor..." -ForegroundColor Cyan

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$TmpZip = Join-Path $env:TEMP "mandalina_udf_win.zip"
$TmpExtract = Join-Path $env:TEMP "mandalina_udf_win_extracted"

if (Test-Path $TmpZip) { Remove-Item $TmpZip -Force }
if (Test-Path $TmpExtract) { Remove-Item $TmpExtract -Recurse -Force }

Invoke-WebRequest -Uri $ZipUrl -OutFile $TmpZip -UseBasicParsing
Expand-Archive -Path $TmpZip -DestinationPath $TmpExtract -Force

$ExtractedRoot = Join-Path $TmpExtract "mandalina-udf-converter-main"
Copy-Item -Path "$ExtractedRoot\*" -Destination $TargetDir -Recurse -Force

Remove-Item $TmpZip -Force -ErrorAction SilentlyContinue
Remove-Item $TmpExtract -Recurse -Force -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------------
# 2. Sanal Ortam (venv) ve Gerekli Kütüphanelerin Kurulumu
# -----------------------------------------------------------------------------
Write-Host "`n📦 [2/5] Gerekli dönüşüm bileşenleri (PDF, Word, TIFF, Sistem Tepsisi) kuruluyor..." -ForegroundColor Cyan

if (-not (Test-Path (Join-Path $VenvDir "Scripts\python.exe"))) {
    & $PythonExe -m venv $VenvDir
}

$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$VenvPythonw = Join-Path $VenvDir "Scripts\pythonw.exe"
$ReqFile = Join-Path $TargetDir "windows\requirements.txt"

& $VenvPython -m pip install --upgrade pip --quiet
& $VenvPython -m pip install -r $ReqFile --quiet

Write-Host "   ✓ Tüm Python dönüşüm kütüphaneleri başarıyla kuruldu." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 3. Otomatik Dönüşüm Testi (--self-test)
# -----------------------------------------------------------------------------
Write-Host "`n🧪 [3/5] Otomatik dönüşüm testleri çalıştırılıyor..." -ForegroundColor Cyan
$AppScript = Join-Path $TargetDir "windows\mandalina_app.py"
& $VenvPython $AppScript --self-test

# -----------------------------------------------------------------------------
# 4. Masaüstü, Başlat Menüsü ve Sağ Tık (Gönder / SendTo) Kısayolları
# -----------------------------------------------------------------------------
Write-Host "`n🖥️  [4/5] Masaüstü, Başlat Menüsü ve Sağ Tık (Gönder) kısayolları oluşturuluyor..." -ForegroundColor Cyan

$IconPath = Join-Path $TargetDir "AppIcon.ico"
$WshShell = New-Object -ComObject WScript.Shell

# 4a. Masaüstü Kısayolu
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$DesktopShortcutPath = Join-Path $DesktopDir "Mandalina.lnk"
$Shortcut = $WshShell.CreateShortcut($DesktopShortcutPath)
$Shortcut.TargetPath = $VenvPythonw
$Shortcut.Arguments = "`"$AppScript`""
$Shortcut.WorkingDirectory = $TargetDir
$Shortcut.Description = "Mandalina — UYAP (.udf) & TIFF Dönüştürücü"
if (Test-Path $IconPath) { $Shortcut.IconLocation = "$IconPath,0" }
$Shortcut.Save()

# 4b. Başlat Menüsü Kısayolu
$StartMenuDir = [Environment]::GetFolderPath("Programs")
$StartShortcutPath = Join-Path $StartMenuDir "Mandalina.lnk"
$StartShortcut = $WshShell.CreateShortcut($StartShortcutPath)
$StartShortcut.TargetPath = $VenvPythonw
$StartShortcut.Arguments = "`"$AppScript`""
$StartShortcut.WorkingDirectory = $TargetDir
$StartShortcut.Description = "Mandalina — UYAP (.udf) & TIFF Dönüştürücü"
if (Test-Path $IconPath) { $StartShortcut.IconLocation = "$IconPath,0" }
$StartShortcut.Save()

# 4c. Windows Gezgini Sağ Tık -> Gönder (SendTo) Menüsü Kısayolu
$SendToDir = [Environment]::GetFolderPath("SendTo")
if ($SendToDir -and (Test-Path $SendToDir)) {
    $SendToShortcutPath = Join-Path $SendToDir "Mandalina UDF Dönüştürücü.lnk"
    $SendShortcut = $WshShell.CreateShortcut($SendToShortcutPath)
    $SendShortcut.TargetPath = $VenvPythonw
    $SendShortcut.Arguments = "`"$AppScript`""
    $SendShortcut.WorkingDirectory = $TargetDir
    if (Test-Path $IconPath) { $SendShortcut.IconLocation = "$IconPath,0" }
    $SendShortcut.Save()
}

# 4d. Masaüstüne Tek Tıkla Güncelleme Aracı
$UpdateBatSrc = Join-Path $TargetDir "Guncelle_Windows.bat"
if (Test-Path $UpdateBatSrc) {
    Copy-Item -Path $UpdateBatSrc -Destination (Join-Path $DesktopDir "Mandalina Güncelle.bat") -Force
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅  Mandalina (Windows) Kurulumu Başarıyla Tamamlandı!    " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "🚀 Uygulama şimdi otomatik olarak başlatılıyor..." -ForegroundColor Yellow

Start-Process -FilePath $VenvPythonw -ArgumentList "`"$AppScript`"" -WorkingDirectory $TargetDir
