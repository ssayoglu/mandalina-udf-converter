@echo off
chcp 65001 >nul
title Mandalina — Otomatik Guncelleme Araci (Windows)
echo ==========================================================
echo   Mandalina — En Son Surume Guncelleniyor...
echo ==========================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/update.ps1 | iex"
pause
