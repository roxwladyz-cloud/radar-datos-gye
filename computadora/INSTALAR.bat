@echo off
title Instalacion Radar Urbano
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0radar_descarga.ps1" -Instalar
