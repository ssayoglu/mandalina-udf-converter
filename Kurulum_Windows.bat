@echo off
chcp 65001 >nul
title Mandalina — UYAP UDF ve TIFF Donusturucu (Windows Kurulumu)
echo ==========================================================
echo   Mandalina — UYAP UDF ve TIFF Donusturucu Kuruluyor...
echo ==========================================================
if exist "%~dp0install.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/install.ps1 | iex"
)
pause
